`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"

// Purpose: Sysclk-domain NAND Page Buffer storage and data access path.
// Role: Synthesizable RTL.
// Related design docs:
// - design_spec/Architecture.md
// - design_spec/nand_adapter_contracts.md
// Block contract: Accepts Decode FSM program data stream directly in sys_clk,
// provides sysclk-local VPL direct read/write ports and Read Output direct
// read port, and owns internal write count/freeze/prog_ready/overflow state.
// Coreclk Register Bank control/status crossing is handled outside this module
// by nand_page_buffer_adapter.
// File version: v0.4
// Revision history:
// - v0.4: Remove public write monitor/count ports; keep program
//   write count as module-internal state.
// - v0.3: Add sysclk-local Read Output direct read port.
// - v0.2: Add sysclk-local VPL write/read direct ports for
//   READ_PAGE fill and PROGRAM_PAGE source reads.
// - v0.1: Initial sysclk Page Buffer with direct program stream
//   input, storage, count, freeze/prog_ready, overflow, and clear handling.

module nand_page_buffer #(
    parameter integer PAGE_SIZE = `NAND_PAGE_SIZE
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    input  wire        prog_data_valid_i,
    output wire        prog_data_ready_o,
    input  wire [7:0]  prog_data_i,

    input  wire        clear_i,
    input  wire        freeze_i,

    input  wire        vpl_wr_valid_i,
    output wire        vpl_wr_ready_o,
    input  wire [12:0] vpl_wr_addr_i,
    input  wire [7:0]  vpl_wr_data_i,

    input  wire        vpl_rd_req_valid_i,
    output wire        vpl_rd_req_ready_o,
    input  wire [12:0] vpl_rd_addr_i,
    output reg         vpl_rd_data_valid_o,
    input  wire        vpl_rd_data_ready_i,
    output reg  [7:0]  vpl_rd_data_o,

    input  wire        readout_rd_req_valid_i,
    output wire        readout_rd_req_ready_o,
    input  wire [12:0] readout_rd_addr_i,
    output reg         readout_rd_data_valid_o,
    input  wire        readout_rd_data_ready_i,
    output reg  [7:0]  readout_rd_data_o,

    output reg         prog_ready_o,
    output reg         overflow_o,
    output wire        busy_o
);

    reg [7:0] storage [0:PAGE_SIZE-1];
    reg [12:0] write_count_q;

    wire count_full = (write_count_q >= PAGE_SIZE[12:0]);
    wire can_accept = (!prog_ready_o) && (!overflow_o) && (!count_full);
    wire data_accept = prog_data_valid_i && prog_data_ready_o;
    wire vpl_wr_addr_valid = (vpl_wr_addr_i < PAGE_SIZE[12:0]);
    wire vpl_rd_addr_valid = (vpl_rd_addr_i < PAGE_SIZE[12:0]);
    wire readout_rd_addr_valid = (readout_rd_addr_i < PAGE_SIZE[12:0]);
    wire vpl_wr_accept = vpl_wr_valid_i && vpl_wr_ready_o;
    wire vpl_rd_req_accept = vpl_rd_req_valid_i && vpl_rd_req_ready_o;
    wire vpl_rd_data_accept = vpl_rd_data_valid_o && vpl_rd_data_ready_i;
    wire readout_rd_req_accept = readout_rd_req_valid_i &&
                                 readout_rd_req_ready_o;
    wire readout_rd_data_accept = readout_rd_data_valid_o &&
                                  readout_rd_data_ready_i;

    assign prog_data_ready_o = can_accept && !vpl_wr_valid_i;
    assign vpl_wr_ready_o = !clear_i && vpl_wr_addr_valid;
    assign vpl_rd_req_ready_o = !clear_i && vpl_rd_addr_valid &&
                                (!vpl_rd_data_valid_o || vpl_rd_data_accept);
    assign readout_rd_req_ready_o = !clear_i && readout_rd_addr_valid &&
                                    (!readout_rd_data_valid_o ||
                                     readout_rd_data_accept);
    assign busy_o = prog_data_valid_i || prog_ready_o || overflow_o ||
                    vpl_wr_valid_i || vpl_rd_req_valid_i ||
                    vpl_rd_data_valid_o || readout_rd_req_valid_i ||
                    readout_rd_data_valid_o;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            write_count_q <= 13'd0;
            prog_ready_o  <= 1'b0;
            overflow_o    <= 1'b0;
            vpl_rd_data_valid_o <= 1'b0;
            vpl_rd_data_o <= 8'h00;
            readout_rd_data_valid_o <= 1'b0;
            readout_rd_data_o <= 8'h00;
        end else if (clear_i) begin
            write_count_q <= 13'd0;
            prog_ready_o  <= 1'b0;
            overflow_o    <= 1'b0;
            vpl_rd_data_valid_o <= 1'b0;
            vpl_rd_data_o <= 8'h00;
            readout_rd_data_valid_o <= 1'b0;
            readout_rd_data_o <= 8'h00;
        end else begin
            if (prog_data_valid_i && count_full) begin
                overflow_o <= 1'b1;
            end

            if (vpl_wr_accept) begin
                storage[vpl_wr_addr_i] <= vpl_wr_data_i;
            end

            if (data_accept) begin
                storage[write_count_q] <= prog_data_i;
                write_count_q <= write_count_q + 13'd1;
            end

            if (freeze_i && !overflow_o) begin
                prog_ready_o <= 1'b1;
            end

            if (vpl_rd_data_accept) begin
                vpl_rd_data_valid_o <= 1'b0;
            end

            if (vpl_rd_req_accept) begin
                vpl_rd_data_o <= storage[vpl_rd_addr_i];
                vpl_rd_data_valid_o <= 1'b1;
            end

            if (readout_rd_data_accept) begin
                readout_rd_data_valid_o <= 1'b0;
            end

            if (readout_rd_req_accept) begin
                readout_rd_data_o <= storage[readout_rd_addr_i];
                readout_rd_data_valid_o <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
