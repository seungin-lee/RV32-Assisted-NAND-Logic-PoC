`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"

// Purpose: Directed smoke test for nand_vpl_executor.
// Role: Simulation-only testbench.
// Related design docs:
// - design_spec/nand_model_vpl.md
// - design_spec/nand_register_bank.md
// Block contract: Checks command ready/valid, latency countdown,
// opcode/range/Page Buffer status checks, READ_PAGE fill, PROGRAM_PAGE
// bitwise-AND commit, ERASE_BLOCK, response payload, and response backpressure
// hold behavior.
// File version: v0.2
// Revision history:
// - v0.2: Add small Page Buffer model and verify READ/PROGRAM/
//   ERASE data effects through VPL direct ports.
// - v0.1: Initial minimal VPL executor smoke test.

module tb_nand_vpl_executor;

    localparam integer CLK_HALF_NS = 5;
    localparam integer TB_PAGE_SIZE = 8;
    localparam integer TB_PAGES_PER_BLOCK = 4;
    localparam integer TB_NUM_BLOCKS = 2;

    localparam [2:0] OP_READ    = 3'd1;
    localparam [2:0] OP_PROGRAM = 3'd2;
    localparam [2:0] OP_ERASE   = 3'd3;

    localparam [7:0] ERR_NONE         = 8'h00;
    localparam [7:0] ERR_INVALID_OP   = 8'h01;
    localparam [7:0] ERR_BLOCK_RANGE  = 8'h03;
    localparam [7:0] ERR_PAGE_RANGE   = 8'h04;
    localparam [7:0] ERR_PB_NOT_READY = 8'h05;
    localparam [7:0] ERR_COL_RANGE    = 8'h09;

    reg sys_clk;
    reg sys_rst_n;

    reg         cmd_valid;
    wire        cmd_ready;
    reg  [31:0] cmd_block;
    reg  [31:0] cmd_page;
    reg  [31:0] cmd_col;
    reg  [31:0] cmd_page_bytes;
    reg  [31:0] cmd_op_ctrl;
    reg  [31:0] cmd_latency;
    reg  [7:0]  cmd_vread_level;
    reg  [7:0]  cmd_vpgm_level;
    reg  [7:0]  cmd_vpass_level;
    reg  [7:0]  cmd_vers_level;
    reg  [2:0]  cmd_bl_ctrl;
    reg  [8:0]  cmd_wl_ctrl;
    reg  [6:0]  cmd_line_ctrl;
    reg  [1:0]  cmd_bias_profile;

    wire        rsp_valid;
    reg         rsp_ready;
    wire        rsp_done;
    wire        rsp_error;
    wire [7:0]  rsp_error_code;
    wire        rsp_fail;
    wire        rsp_pb_valid;

    reg         pb_prog_ready;
    reg         pb_overflow;
    wire        pb_wr_valid;
    wire        pb_wr_ready;
    wire [12:0] pb_wr_addr;
    wire [7:0]  pb_wr_data;
    wire        pb_rd_req_valid;
    wire        pb_rd_req_ready;
    wire [12:0] pb_rd_addr;
    reg         pb_rd_data_valid;
    wire        pb_rd_data_ready;
    reg  [7:0]  pb_rd_data;

    integer fail_count;
    integer pb_wr_count;
    reg [7:0] pb_mem [0:TB_PAGE_SIZE-1];

    nand_vpl_executor #(
        .PAGE_SIZE(TB_PAGE_SIZE),
        .PAGES_PER_BLOCK(TB_PAGES_PER_BLOCK),
        .NUM_BLOCKS(TB_NUM_BLOCKS),
        .READ_LATENCY(32'd4),
        .PROGRAM_LATENCY(32'd5),
        .ERASE_LATENCY(32'd6),
        .ERROR_LATENCY(32'd2)
    ) dut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .cmd_valid_i(cmd_valid),
        .cmd_ready_o(cmd_ready),
        .cmd_block_i(cmd_block),
        .cmd_page_i(cmd_page),
        .cmd_col_i(cmd_col),
        .cmd_page_bytes_i(cmd_page_bytes),
        .cmd_op_ctrl_i(cmd_op_ctrl),
        .cmd_latency_i(cmd_latency),
        .cmd_vread_level_i(cmd_vread_level),
        .cmd_vpgm_level_i(cmd_vpgm_level),
        .cmd_vpass_level_i(cmd_vpass_level),
        .cmd_vers_level_i(cmd_vers_level),
        .cmd_bl_ctrl_i(cmd_bl_ctrl),
        .cmd_wl_ctrl_i(cmd_wl_ctrl),
        .cmd_line_ctrl_i(cmd_line_ctrl),
        .cmd_bias_profile_i(cmd_bias_profile),
        .rsp_valid_o(rsp_valid),
        .rsp_ready_i(rsp_ready),
        .rsp_done_o(rsp_done),
        .rsp_error_o(rsp_error),
        .rsp_error_code_o(rsp_error_code),
        .rsp_fail_o(rsp_fail),
        .rsp_pb_valid_o(rsp_pb_valid),
        .pb_prog_ready_i(pb_prog_ready),
        .pb_overflow_i(pb_overflow),
        .pb_wr_valid_o(pb_wr_valid),
        .pb_wr_ready_i(pb_wr_ready),
        .pb_wr_addr_o(pb_wr_addr),
        .pb_wr_data_o(pb_wr_data),
        .pb_rd_req_valid_o(pb_rd_req_valid),
        .pb_rd_req_ready_i(pb_rd_req_ready),
        .pb_rd_addr_o(pb_rd_addr),
        .pb_rd_data_valid_i(pb_rd_data_valid),
        .pb_rd_data_ready_o(pb_rd_data_ready),
        .pb_rd_data_i(pb_rd_data)
    );

    assign pb_wr_ready = 1'b1;
    assign pb_rd_req_ready = !pb_rd_data_valid || pb_rd_data_ready;

    always #CLK_HALF_NS sys_clk = ~sys_clk;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            pb_rd_data_valid <= 1'b0;
            pb_rd_data <= 8'h00;
            pb_wr_count <= 0;
        end else begin
            if (pb_wr_valid && pb_wr_ready) begin
                if (pb_wr_addr < TB_PAGE_SIZE[12:0]) begin
                    pb_mem[pb_wr_addr] <= pb_wr_data;
                end
                pb_wr_count <= pb_wr_count + 1;
            end

            if (pb_rd_data_valid && pb_rd_data_ready) begin
                pb_rd_data_valid <= 1'b0;
            end

            if (pb_rd_req_valid && pb_rd_req_ready) begin
                pb_rd_data <= pb_mem[pb_rd_addr];
                pb_rd_data_valid <= 1'b1;
            end
        end
    end

    task automatic check_equal;
        input [511:0] name;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=0x%08x expected=0x%08x",
                         name, actual, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("[PASS] %0s actual=0x%08x", name, actual);
            end
        end
    endtask

    task automatic reset_inputs;
        begin
            cmd_valid = 1'b0;
            cmd_block = 32'h0000_0000;
            cmd_page = 32'h0000_0000;
            cmd_col = 32'h0000_0000;
            cmd_page_bytes = TB_PAGE_SIZE;
            cmd_op_ctrl = 32'h0000_0000;
            cmd_latency = 32'h0000_0000;
            cmd_vread_level = 8'h00;
            cmd_vpgm_level = 8'h00;
            cmd_vpass_level = 8'h00;
            cmd_vers_level = 8'h00;
            cmd_bl_ctrl = 3'b000;
            cmd_wl_ctrl = 9'h000;
            cmd_line_ctrl = 7'h00;
            cmd_bias_profile = 2'b00;
            rsp_ready = 1'b1;
            pb_prog_ready = 1'b0;
            pb_overflow = 1'b0;
        end
    endtask

    task automatic clear_pb_model;
        integer i;
        begin
            for (i = 0; i < TB_PAGE_SIZE; i = i + 1) begin
                pb_mem[i] = 8'h00;
            end
            pb_wr_count = 0;
        end
    endtask

    task automatic load_pb_pattern;
        input [7:0] base;
        integer i;
        begin
            for (i = 0; i < TB_PAGE_SIZE; i = i + 1) begin
                pb_mem[i] = base + i;
            end
        end
    endtask

    task automatic check_pb_byte;
        input [511:0] name;
        input integer index;
        input [7:0] expected;
        begin
            check_equal(name, {24'h000000, pb_mem[index]},
                        {24'h000000, expected});
        end
    endtask

    task automatic send_cmd;
        input [2:0]  op_code;
        input [31:0] block_idx;
        input [31:0] page_idx;
        input [31:0] col_idx;
        input [31:0] latency;
        begin
            @(negedge sys_clk);
            cmd_op_ctrl = {29'h00000000, op_code};
            cmd_block = block_idx;
            cmd_page = page_idx;
            cmd_col = col_idx;
            cmd_latency = latency;
            cmd_valid = 1'b1;
            while (!cmd_ready) begin
                @(negedge sys_clk);
            end
            @(negedge sys_clk);
            cmd_valid = 1'b0;
        end
    endtask

    task automatic expect_response;
        input [511:0] name;
        input         exp_done;
        input         exp_error;
        input [7:0]   exp_error_code;
        input         exp_fail;
        input         exp_pb_valid;
        integer timeout;
        begin
            timeout = 200;
            while (!rsp_valid && timeout > 0) begin
                @(posedge sys_clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                $display("[FAIL] %0s response timeout", name);
                fail_count = fail_count + 1;
            end else begin
                check_equal({name, " done"}, {31'h00000000, rsp_done},
                            {31'h00000000, exp_done});
                check_equal({name, " error"}, {31'h00000000, rsp_error},
                            {31'h00000000, exp_error});
                check_equal({name, " error_code"}, {24'h000000, rsp_error_code},
                            {24'h000000, exp_error_code});
                check_equal({name, " fail"}, {31'h00000000, rsp_fail},
                            {31'h00000000, exp_fail});
                check_equal({name, " pb_valid"}, {31'h00000000, rsp_pb_valid},
                            {31'h00000000, exp_pb_valid});
                @(negedge sys_clk);
            end
        end
    endtask

    initial begin
        sys_clk = 1'b0;
        sys_rst_n = 1'b0;
        fail_count = 0;
        reset_inputs();
        clear_pb_model();

        repeat (4) @(posedge sys_clk);
        sys_rst_n = 1'b1;
        repeat (2) @(posedge sys_clk);

        $display("[SCENARIO] READ_PAGE success");
        clear_pb_model();
        send_cmd(OP_READ, 32'd1, 32'd2, 32'd0, 32'd3);
        expect_response("READ_PAGE", 1'b1, 1'b0, ERR_NONE, 1'b0, 1'b1);
        check_equal("READ_PAGE writes full page", pb_wr_count, TB_PAGE_SIZE);
        check_pb_byte("READ_PAGE byte0 erased", 0, 8'hFF);
        check_pb_byte("READ_PAGE byte7 erased", 7, 8'hFF);

        $display("[SCENARIO] PROGRAM success");
        load_pb_pattern(8'ha0);
        pb_prog_ready = 1'b1;
        send_cmd(OP_PROGRAM, 32'd0, 32'd0, 32'd0, 32'd2);
        expect_response("PROGRAM", 1'b1, 1'b0, ERR_NONE, 1'b0, 1'b0);
        clear_pb_model();
        send_cmd(OP_READ, 32'd0, 32'd0, 32'd0, 32'd1);
        expect_response("READ_AFTER_PROGRAM", 1'b1, 1'b0, ERR_NONE, 1'b0, 1'b1);
        check_pb_byte("PROGRAM committed byte0", 0, 8'ha0);
        check_pb_byte("PROGRAM committed byte7", 7, 8'ha7);

        $display("[SCENARIO] ERASE success with response backpressure");
        rsp_ready = 1'b0;
        send_cmd(OP_ERASE, 32'd0, 32'd0, 32'd0, 32'd2);
        while (!rsp_valid) begin
            @(posedge sys_clk);
        end
        check_equal("ERASE response held while not ready",
                    {31'h00000000, rsp_valid}, 32'h0000_0001);
        rsp_ready = 1'b1;
        expect_response("ERASE", 1'b1, 1'b0, ERR_NONE, 1'b0, 1'b0);
        clear_pb_model();
        send_cmd(OP_READ, 32'd0, 32'd0, 32'd0, 32'd1);
        expect_response("READ_AFTER_ERASE", 1'b1, 1'b0, ERR_NONE, 1'b0, 1'b1);
        check_pb_byte("ERASE restored byte0", 0, 8'hFF);
        check_pb_byte("ERASE restored byte7", 7, 8'hFF);

        $display("[SCENARIO] Invalid opcode");
        send_cmd(3'd7, 32'd0, 32'd0, 32'd0, 32'd0);
        expect_response("INVALID_OP", 1'b0, 1'b1, ERR_INVALID_OP, 1'b1, 1'b0);

        $display("[SCENARIO] Range and Page Buffer errors");
        send_cmd(OP_READ, TB_NUM_BLOCKS, 32'd0, 32'd0, 32'd0);
        expect_response("BLOCK_RANGE", 1'b0, 1'b1, ERR_BLOCK_RANGE, 1'b1, 1'b0);
        send_cmd(OP_READ, 32'd0, TB_PAGES_PER_BLOCK, 32'd0, 32'd0);
        expect_response("PAGE_RANGE", 1'b0, 1'b1, ERR_PAGE_RANGE, 1'b1, 1'b0);
        send_cmd(OP_READ, 32'd0, 32'd0, TB_PAGE_SIZE, 32'd0);
        expect_response("COL_RANGE", 1'b0, 1'b1, ERR_COL_RANGE, 1'b1, 1'b0);

        pb_prog_ready = 1'b0;
        send_cmd(OP_PROGRAM, 32'd0, 32'd0, 32'd0, 32'd0);
        expect_response("PB_NOT_READY", 1'b0, 1'b1, ERR_PB_NOT_READY,
                        1'b1, 1'b0);

        pb_prog_ready = 1'b1;
        pb_overflow = 1'b1;
        send_cmd(OP_PROGRAM, 32'd0, 32'd0, 32'd0, 32'd0);
        expect_response("PB_OVERFLOW", 1'b0, 1'b1, ERR_PB_NOT_READY,
                        1'b1, 1'b0);

        if (fail_count == 0) begin
            $display("PASS: tb_nand_vpl_executor");
            $finish;
        end

        $display("FAIL: tb_nand_vpl_executor fail_count=%0d", fail_count);
        $fatal(1, "tb_nand_vpl_executor failed");
    end

endmodule

`default_nettype wire
