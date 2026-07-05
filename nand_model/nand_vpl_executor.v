`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"

// Purpose: Sysclk-domain clocked VPL executor.
// Role: RTL model for VPL command execution.
// Related design docs:
// - design_spec/nand_model_vpl.md
// - design_spec/nand_register_bank.md
// - design_spec/Architecture.md
// Block contract: Accepts a VPL command snapshot from the VPL
// Command/Response Adapter, performs opcode/range/Page Buffer status checks,
// waits a latency counter, executes READ/PROGRAM/ERASE against the internal
// NAND array through sysclk-local Page Buffer direct ports, and returns a
// done/error response.
// File version: v0.2
// Revision history:
// - v0.2: Add internal NAND array, READ_PAGE Page Buffer fill,
//   PROGRAM_PAGE Page Buffer source read/bitwise-AND commit, and ERASE_BLOCK
//   byte loop.
// - v0.1: Initial minimal clocked VPL executor with command
//   handshake, latency counter, and response status.

module nand_vpl_executor #(
    parameter integer PAGE_SIZE        = `NAND_PAGE_SIZE,
    parameter integer PAGES_PER_BLOCK  = `NAND_PAGES_PER_BLOCK,
    parameter integer NUM_BLOCKS       = `NAND_NUM_BLOCKS,
    parameter [31:0]  READ_LATENCY     = `NAND_T_R_CYCLES,
    parameter [31:0]  PROGRAM_LATENCY  = `NAND_T_PROG_CYCLES,
    parameter [31:0]  ERASE_LATENCY    = `NAND_T_BERS_CYCLES,
    parameter [31:0]  ERROR_LATENCY    = 32'd1
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    input  wire        cmd_valid_i,
    output wire        cmd_ready_o,
    input  wire [31:0] cmd_block_i,
    input  wire [31:0] cmd_page_i,
    input  wire [31:0] cmd_col_i,
    input  wire [31:0] cmd_page_bytes_i,
    input  wire [31:0] cmd_op_ctrl_i,
    input  wire [31:0] cmd_latency_i,
    input  wire [7:0]  cmd_vread_level_i,
    input  wire [7:0]  cmd_vpgm_level_i,
    input  wire [7:0]  cmd_vpass_level_i,
    input  wire [7:0]  cmd_vers_level_i,
    input  wire [2:0]  cmd_bl_ctrl_i,
    input  wire [8:0]  cmd_wl_ctrl_i,
    input  wire [6:0]  cmd_line_ctrl_i,
    input  wire [1:0]  cmd_bias_profile_i,

    output reg         rsp_valid_o,
    input  wire        rsp_ready_i,
    output reg         rsp_done_o,
    output reg         rsp_error_o,
    output reg  [7:0]  rsp_error_code_o,
    output reg         rsp_fail_o,
    output reg         rsp_pb_valid_o,

    input  wire        pb_prog_ready_i,
    input  wire        pb_overflow_i,

    output reg         pb_wr_valid_o,
    input  wire        pb_wr_ready_i,
    output reg  [12:0] pb_wr_addr_o,
    output reg  [7:0]  pb_wr_data_o,

    output reg         pb_rd_req_valid_o,
    input  wire        pb_rd_req_ready_i,
    output reg  [12:0] pb_rd_addr_o,
    input  wire        pb_rd_data_valid_i,
    output reg         pb_rd_data_ready_o,
    input  wire [7:0]  pb_rd_data_i
);

    localparam [2:0] ST_IDLE        = 3'd0;
    localparam [2:0] ST_LATENCY     = 3'd1;
    localparam [2:0] ST_READ_WRITE  = 3'd2;
    localparam [2:0] ST_PROGRAM_REQ = 3'd3;
    localparam [2:0] ST_PROGRAM_RSP = 3'd4;
    localparam [2:0] ST_ERASE       = 3'd5;
    localparam [2:0] ST_RSP         = 3'd6;

    localparam [2:0] OP_NONE    = 3'd0;
    localparam [2:0] OP_READ    = 3'd1;
    localparam [2:0] OP_PROGRAM = 3'd2;
    localparam [2:0] OP_ERASE   = 3'd3;

    localparam [7:0] ERR_NONE         = 8'h00;
    localparam [7:0] ERR_INVALID_OP   = 8'h01;
    localparam [7:0] ERR_BLOCK_RANGE  = 8'h03;
    localparam [7:0] ERR_PAGE_RANGE   = 8'h04;
    localparam [7:0] ERR_PB_NOT_READY = 8'h05;
    localparam [7:0] ERR_COL_RANGE    = 8'h09;

    localparam integer TOTAL_PAGES = NUM_BLOCKS * PAGES_PER_BLOCK;
    localparam integer TOTAL_BYTES = TOTAL_PAGES * PAGE_SIZE;
    localparam integer BLOCK_BYTES = PAGES_PER_BLOCK * PAGE_SIZE;

    reg [2:0]  state_q;
    reg [31:0] latency_count_q;
    reg [2:0]  op_code_q;
    reg [31:0] base_addr_q;
    reg [31:0] transfer_index_q;
    reg [31:0] transfer_bytes_q;
    reg        result_error_q;
    reg [7:0]  result_error_code_q;
    reg [7:0]  array_mem [0:TOTAL_BYTES-1];

    integer init_idx;

    initial begin
        for (init_idx = 0; init_idx < TOTAL_BYTES; init_idx = init_idx + 1) begin
            array_mem[init_idx] = 8'hFF;
        end
    end

    wire        cmd_accept = cmd_valid_i && cmd_ready_o;
    wire        rsp_accept = rsp_valid_o && rsp_ready_i;
    wire        pb_wr_accept = pb_wr_valid_o && pb_wr_ready_i;
    wire        pb_rd_req_accept = pb_rd_req_valid_o && pb_rd_req_ready_i;
    wire        pb_rd_data_accept = pb_rd_data_valid_i && pb_rd_data_ready_o;
    wire [2:0]  cmd_op_code = cmd_op_ctrl_i[2:0];
    wire [31:0] default_latency =
        (cmd_op_code == OP_READ)    ? READ_LATENCY :
        (cmd_op_code == OP_PROGRAM) ? PROGRAM_LATENCY :
        (cmd_op_code == OP_ERASE)   ? ERASE_LATENCY :
                                      ERROR_LATENCY;
    wire [31:0] selected_latency =
        (cmd_latency_i != 32'h0000_0000) ? cmd_latency_i : default_latency;
    wire [31:0] selected_transfer_bytes =
        (cmd_page_bytes_i > PAGE_SIZE) ? PAGE_SIZE[31:0] : cmd_page_bytes_i;

    assign cmd_ready_o = (state_q == ST_IDLE) && !rsp_valid_o &&
                         !pb_wr_valid_o && !pb_rd_req_valid_o &&
                         !pb_rd_data_ready_o;

    function automatic [31:0] page_base_addr;
        input [31:0] block_idx;
        input [31:0] page_idx;
        begin
            page_base_addr = ((block_idx * PAGES_PER_BLOCK) + page_idx) *
                             PAGE_SIZE;
        end
    endfunction

    function automatic [31:0] block_base_addr;
        input [31:0] block_idx;
        begin
            block_base_addr = block_idx * BLOCK_BYTES;
        end
    endfunction

    function automatic [7:0] validate_cmd;
        input [2:0]  op_code;
        input [31:0] block_idx;
        input [31:0] page_idx;
        input [31:0] col_idx;
        input [31:0] page_bytes;
        input        pb_prog_ready;
        input        pb_overflow;
        begin
            if (op_code != OP_READ && op_code != OP_PROGRAM &&
                op_code != OP_ERASE) begin
                validate_cmd = ERR_INVALID_OP;
            end else if (block_idx >= NUM_BLOCKS) begin
                validate_cmd = ERR_BLOCK_RANGE;
            end else if ((op_code != OP_ERASE) && (page_bytes == 32'd0)) begin
                validate_cmd = ERR_COL_RANGE;
            end else if ((op_code != OP_ERASE) &&
                         (page_idx >= PAGES_PER_BLOCK)) begin
                validate_cmd = ERR_PAGE_RANGE;
            end else if ((op_code != OP_ERASE) &&
                         (col_idx >= page_bytes || col_idx >= PAGE_SIZE)) begin
                validate_cmd = ERR_COL_RANGE;
            end else if ((op_code == OP_PROGRAM) &&
                         (!pb_prog_ready || pb_overflow)) begin
                validate_cmd = ERR_PB_NOT_READY;
            end else begin
                validate_cmd = ERR_NONE;
            end
        end
    endfunction

    wire [7:0] accept_error_code = validate_cmd(
        cmd_op_code,
        cmd_block_i,
        cmd_page_i,
        cmd_col_i,
        cmd_page_bytes_i,
        pb_prog_ready_i,
        pb_overflow_i
    );

    task automatic start_response;
        input        done;
        input        error;
        input [7:0]  error_code;
        input        fail;
        input        pb_valid;
        begin
            rsp_valid_o <= 1'b1;
            rsp_done_o <= done;
            rsp_error_o <= error;
            rsp_error_code_o <= error_code;
            rsp_fail_o <= fail;
            rsp_pb_valid_o <= pb_valid;
            state_q <= ST_RSP;
        end
    endtask

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state_q <= ST_IDLE;
            latency_count_q <= 32'h0000_0000;
            op_code_q <= OP_NONE;
            base_addr_q <= 32'h0000_0000;
            transfer_index_q <= 32'h0000_0000;
            transfer_bytes_q <= 32'h0000_0000;
            result_error_q <= 1'b0;
            result_error_code_q <= ERR_NONE;
            rsp_valid_o <= 1'b0;
            rsp_done_o <= 1'b0;
            rsp_error_o <= 1'b0;
            rsp_error_code_o <= ERR_NONE;
            rsp_fail_o <= 1'b0;
            rsp_pb_valid_o <= 1'b0;
            pb_wr_valid_o <= 1'b0;
            pb_wr_addr_o <= 13'd0;
            pb_wr_data_o <= 8'h00;
            pb_rd_req_valid_o <= 1'b0;
            pb_rd_addr_o <= 13'd0;
            pb_rd_data_ready_o <= 1'b0;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    if (cmd_accept) begin
                        op_code_q <= cmd_op_code;
                        base_addr_q <= (cmd_op_code == OP_ERASE) ?
                                       block_base_addr(cmd_block_i) :
                                       page_base_addr(cmd_block_i, cmd_page_i);
                        transfer_index_q <= 32'h0000_0000;
                        transfer_bytes_q <= (cmd_op_code == OP_ERASE) ?
                                            BLOCK_BYTES[31:0] :
                                            selected_transfer_bytes;
                        result_error_q <= (accept_error_code != ERR_NONE);
                        result_error_code_q <= accept_error_code;
                        latency_count_q <= (accept_error_code != ERR_NONE) ?
                                           ERROR_LATENCY : selected_latency;
                        state_q <= ST_LATENCY;
                    end
                end

                ST_LATENCY: begin
                    if (latency_count_q <= 32'd1) begin
                        if (result_error_q) begin
                            start_response(1'b0, 1'b1, result_error_code_q,
                                           1'b1, 1'b0);
                        end else if (op_code_q == OP_READ) begin
                            state_q <= ST_READ_WRITE;
                        end else if (op_code_q == OP_PROGRAM) begin
                            state_q <= ST_PROGRAM_REQ;
                        end else if (op_code_q == OP_ERASE) begin
                            state_q <= ST_ERASE;
                        end else begin
                            start_response(1'b0, 1'b1, ERR_INVALID_OP,
                                           1'b1, 1'b0);
                        end
                    end else begin
                        latency_count_q <= latency_count_q - 32'd1;
                    end
                end

                ST_READ_WRITE: begin
                    if (!pb_wr_valid_o) begin
                        pb_wr_valid_o <= 1'b1;
                        pb_wr_addr_o <= transfer_index_q[12:0];
                        pb_wr_data_o <= array_mem[base_addr_q +
                                                  transfer_index_q];
                    end else if (pb_wr_accept) begin
                        if (transfer_index_q + 32'd1 >= transfer_bytes_q) begin
                            pb_wr_valid_o <= 1'b0;
                            start_response(1'b1, 1'b0, ERR_NONE, 1'b0, 1'b1);
                        end else begin
                            transfer_index_q <= transfer_index_q + 32'd1;
                            pb_wr_addr_o <= transfer_index_q[12:0] + 13'd1;
                            pb_wr_data_o <= array_mem[base_addr_q +
                                                      transfer_index_q +
                                                      32'd1];
                        end
                    end
                end

                ST_PROGRAM_REQ: begin
                    if (!pb_rd_req_valid_o && !pb_rd_data_ready_o) begin
                        pb_rd_req_valid_o <= 1'b1;
                        pb_rd_addr_o <= transfer_index_q[12:0];
                    end else if (pb_rd_req_accept) begin
                        pb_rd_req_valid_o <= 1'b0;
                        pb_rd_data_ready_o <= 1'b1;
                        state_q <= ST_PROGRAM_RSP;
                    end
                end

                ST_PROGRAM_RSP: begin
                    if (pb_rd_data_accept) begin
                        array_mem[base_addr_q + transfer_index_q] <=
                            array_mem[base_addr_q + transfer_index_q] &
                            pb_rd_data_i;
                        pb_rd_data_ready_o <= 1'b0;
                        if (transfer_index_q + 32'd1 >= transfer_bytes_q) begin
                            start_response(1'b1, 1'b0, ERR_NONE, 1'b0, 1'b0);
                        end else begin
                            transfer_index_q <= transfer_index_q + 32'd1;
                            state_q <= ST_PROGRAM_REQ;
                        end
                    end
                end

                ST_ERASE: begin
                    array_mem[base_addr_q + transfer_index_q] <= 8'hFF;
                    if (transfer_index_q + 32'd1 >= transfer_bytes_q) begin
                        start_response(1'b1, 1'b0, ERR_NONE, 1'b0, 1'b0);
                    end else begin
                        transfer_index_q <= transfer_index_q + 32'd1;
                    end
                end

                ST_RSP: begin
                    if (rsp_accept) begin
                        rsp_valid_o <= 1'b0;
                        rsp_done_o <= 1'b0;
                        rsp_error_o <= 1'b0;
                        rsp_error_code_o <= ERR_NONE;
                        rsp_fail_o <= 1'b0;
                        rsp_pb_valid_o <= 1'b0;
                        op_code_q <= OP_NONE;
                        state_q <= ST_IDLE;
                        base_addr_q <= 32'h0000_0000;
                        transfer_index_q <= 32'h0000_0000;
                        transfer_bytes_q <= 32'h0000_0000;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                    pb_wr_valid_o <= 1'b0;
                    pb_rd_req_valid_o <= 1'b0;
                    pb_rd_data_ready_o <= 1'b0;
                end
            endcase
        end
    end

    // Bias/debug snapshot fields are intentionally accepted but not yet checked.
    wire unused_cmd_snapshot = ^{
        cmd_vread_level_i,
        cmd_vpgm_level_i,
        cmd_vpass_level_i,
        cmd_vers_level_i,
        cmd_bl_ctrl_i,
        cmd_wl_ctrl_i,
        cmd_line_ctrl_i,
        cmd_bias_profile_i,
        op_code_q
    };

endmodule

`default_nettype wire
