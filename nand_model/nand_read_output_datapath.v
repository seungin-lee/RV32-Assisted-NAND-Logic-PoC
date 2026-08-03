`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"

// Purpose: Sysclk-domain host read data output mux for Read ID, Read Status,
// and Page Buffer readback.
// Role: Synthesizable RTL.
// Related design docs:
// - design_spec/Architecture.md
// - design_spec/nand_adapter_contracts.md
// - design_spec/nand_read_output_datapath.md
// Block contract: Uses mirrored Register Bank readout control/status snapshots
// and sysclk Page Buffer read port to update dq output on synchronized RE#
// falling edges. Coreclk FW/Register Bank latency is kept out of the host read
// timing path.
// File version: v0.3
// Revision history:
// - v0.3: Refactor into registered-output hybrid FSM with
//   current/next registers while preserving read cycle behavior.
// - v0.2: Add RE# rise input and deassert dq_oe after each host
//   read cycle to avoid command/address bus contention.
// - v0.1: Initial Read ID/Status/Page Buffer source mux.

module nand_read_output_datapath #(
    parameter integer PAGE_SIZE = `NAND_PAGE_SIZE
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    input  wire        re_fall_i,
    input  wire        re_rise_i,
    input  wire        ptr_reset_i,
    input  wire [7:0]  readout_ctrl_i,
    input  wire [7:0]  readout_id_addr_i,
    input  wire [7:0]  nand_status_i,

    output reg         pb_rd_req_valid_o,
    input  wire        pb_rd_req_ready_i,
    output reg  [12:0] pb_rd_addr_o,
    input  wire        pb_rd_data_valid_i,
    output reg         pb_rd_data_ready_o,
    input  wire [7:0]  pb_rd_data_i,

    output reg  [7:0]  dq_out_o,
    output reg         dq_oe_o,
    output wire [12:0] read_ptr_o,
    output wire        busy_o
);

    localparam [1:0] SOURCE_NONE        = 2'd0;
    localparam [1:0] SOURCE_READ_ID     = 2'd1;
    localparam [1:0] SOURCE_READ_STATUS = 2'd2;
    localparam [1:0] SOURCE_PAGE_BUFFER = 2'd3;

    localparam [1:0] ST_IDLE    = 2'd0;
    localparam [1:0] ST_PB_REQ  = 2'd1;
    localparam [1:0] ST_PB_DATA = 2'd2;

    reg [1:0]  state_q;
    reg [1:0]  state_d;
    reg [12:0] read_ptr_q;
    reg [12:0] read_ptr_d;
    reg [7:0]  readout_ctrl_q;
    reg [7:0]  readout_ctrl_d;
    reg [7:0]  readout_id_addr_q;
    reg [7:0]  readout_id_addr_d;
    reg        pb_rd_req_valid_d;
    reg [12:0] pb_rd_addr_d;
    reg        pb_rd_data_ready_d;
    reg [7:0]  dq_out_d;
    reg        dq_oe_d;

    wire [1:0] source = readout_ctrl_i[1:0];
    wire       enable = readout_ctrl_i[2];
    wire       ctrl_changed = (readout_ctrl_i != readout_ctrl_q);
    wire       id_addr_changed = (readout_id_addr_i != readout_id_addr_q);
    wire       page_addr_valid = (read_ptr_q < PAGE_SIZE[12:0]);
    wire       page_read_start = re_fall_i && enable &&
                                 (source == SOURCE_PAGE_BUFFER) &&
                                 page_addr_valid &&
                                 (state_q == ST_IDLE);

    assign read_ptr_o = read_ptr_q;
    assign busy_o = (state_q != ST_IDLE) || pb_rd_req_valid_o ||
                    pb_rd_data_ready_o;

    function [7:0] id_byte;
        input [7:0] addr;
        input [12:0] index;
        begin
            if (addr == 8'h20) begin
                case (index[2:0])
                    3'd0: id_byte = 8'h4f;
                    3'd1: id_byte = 8'h4e;
                    3'd2: id_byte = 8'h46;
                    3'd3: id_byte = 8'h49;
                    default: id_byte = 8'h00;
                endcase
            end else begin
                case (index[2:0])
                    3'd0: id_byte = 8'h2c;
                    3'd1: id_byte = 8'h68;
                    default: id_byte = 8'h00;
                endcase
            end
        end
    endfunction

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state_q <= ST_IDLE;
            read_ptr_q <= 13'd0;
            readout_ctrl_q <= 8'h00;
            readout_id_addr_q <= 8'h00;
            pb_rd_req_valid_o <= 1'b0;
            pb_rd_addr_o <= 13'd0;
            pb_rd_data_ready_o <= 1'b0;
            dq_out_o <= 8'h00;
            dq_oe_o <= 1'b0;
        end else begin
            state_q <= state_d;
            read_ptr_q <= read_ptr_d;
            readout_ctrl_q <= readout_ctrl_d;
            readout_id_addr_q <= readout_id_addr_d;
            pb_rd_req_valid_o <= pb_rd_req_valid_d;
            pb_rd_addr_o <= pb_rd_addr_d;
            pb_rd_data_ready_o <= pb_rd_data_ready_d;
            dq_out_o <= dq_out_d;
            dq_oe_o <= dq_oe_d;
        end
    end

    always @* begin
        state_d = state_q;
        read_ptr_d = read_ptr_q;
        readout_ctrl_d = readout_ctrl_i;
        readout_id_addr_d = readout_id_addr_i;
        pb_rd_req_valid_d = pb_rd_req_valid_o;
        pb_rd_addr_d = pb_rd_addr_o;
        pb_rd_data_ready_d = 1'b0;
        dq_out_d = dq_out_o;
        dq_oe_d = dq_oe_o;

        if (ptr_reset_i || ctrl_changed || id_addr_changed) begin
            state_d = ST_IDLE;
            read_ptr_d = 13'd0;
            pb_rd_req_valid_d = 1'b0;
            pb_rd_data_ready_d = 1'b0;
            dq_oe_d = 1'b0;
        end else if (!enable || (source == SOURCE_NONE)) begin
            state_d = ST_IDLE;
            pb_rd_req_valid_d = 1'b0;
            pb_rd_data_ready_d = 1'b0;
            dq_oe_d = 1'b0;
        end else begin
            if (re_rise_i) begin
                dq_oe_d = 1'b0;
            end

            case (state_q)
                ST_IDLE: begin
                    if (re_fall_i && (source == SOURCE_READ_ID)) begin
                        dq_out_d = id_byte(readout_id_addr_i, read_ptr_q);
                        dq_oe_d = 1'b1;
                        read_ptr_d = read_ptr_q + 13'd1;
                    end else if (re_fall_i &&
                                 (source == SOURCE_READ_STATUS)) begin
                        dq_out_d = nand_status_i;
                        dq_oe_d = 1'b1;
                    end else if (page_read_start) begin
                        pb_rd_req_valid_d = 1'b1;
                        pb_rd_addr_d = read_ptr_q;
                        state_d = ST_PB_REQ;
                    end
                end

                ST_PB_REQ: begin
                    if (pb_rd_req_valid_o && pb_rd_req_ready_i) begin
                        pb_rd_req_valid_d = 1'b0;
                        pb_rd_data_ready_d = 1'b1;
                        state_d = ST_PB_DATA;
                    end
                end

                ST_PB_DATA: begin
                    pb_rd_data_ready_d = 1'b1;
                    if (pb_rd_data_valid_i) begin
                        dq_out_d = pb_rd_data_i;
                        dq_oe_d = 1'b1;
                        read_ptr_d = read_ptr_q + 13'd1;
                        pb_rd_data_ready_d = 1'b0;
                        state_d = ST_IDLE;
                    end
                end

                default: begin
                    state_d = ST_IDLE;
                    pb_rd_req_valid_d = 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
