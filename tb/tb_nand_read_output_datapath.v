`timescale 1ns/1ps
`default_nettype none

// Purpose: Directed smoke test for nand_read_output_datapath.
// Role: Simulation-only testbench.
// Related design docs:
// - design_spec/nand_read_output_datapath.md
// - design_spec/nand_page_buffer.md
// Block contract: Checks Read ID 00h/20h tables, Read Status source, and
// Page Buffer readback through the sysclk direct read port.
// File version: v0.2
// Revision history:
// - v0.2: Check dq_oe release on RE# rise.
// - v0.1: Initial Read Output Datapath smoke test.

module tb_nand_read_output_datapath;

    localparam integer CLK_HALF_NS = 5;
    localparam integer PAGE_SIZE = 16;

    reg        sys_clk;
    reg        sys_rst_n;
    reg        re_fall;
    reg        re_rise;
    reg        ptr_reset;
    reg [7:0]  readout_ctrl;
    reg [7:0]  readout_id_addr;
    reg [7:0]  nand_status;
    wire       pb_rd_req_valid;
    wire       pb_rd_req_ready;
    wire [12:0] pb_rd_addr;
    wire       pb_rd_data_valid;
    wire       pb_rd_data_ready;
    wire [7:0] pb_rd_data;
    wire [7:0] dq_out;
    wire       dq_oe;
    wire [12:0] read_ptr;
    wire       readout_busy;

    reg        pb_prog_data_valid;
    wire       pb_prog_data_ready;
    reg [7:0]  pb_prog_data;
    reg        pb_clear;
    reg        pb_freeze;
    reg        pb_vpl_wr_valid;
    wire       pb_vpl_wr_ready;
    reg [12:0] pb_vpl_wr_addr;
    reg [7:0]  pb_vpl_wr_data;

    integer fail_count;

    nand_read_output_datapath #(
        .PAGE_SIZE(PAGE_SIZE)
    ) dut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .re_fall_i(re_fall),
        .re_rise_i(re_rise),
        .ptr_reset_i(ptr_reset),
        .readout_ctrl_i(readout_ctrl),
        .readout_id_addr_i(readout_id_addr),
        .nand_status_i(nand_status),
        .pb_rd_req_valid_o(pb_rd_req_valid),
        .pb_rd_req_ready_i(pb_rd_req_ready),
        .pb_rd_addr_o(pb_rd_addr),
        .pb_rd_data_valid_i(pb_rd_data_valid),
        .pb_rd_data_ready_o(pb_rd_data_ready),
        .pb_rd_data_i(pb_rd_data),
        .dq_out_o(dq_out),
        .dq_oe_o(dq_oe),
        .read_ptr_o(read_ptr),
        .busy_o(readout_busy)
    );

    nand_page_buffer #(
        .PAGE_SIZE(PAGE_SIZE)
    ) u_page_buffer (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .prog_data_valid_i(pb_prog_data_valid),
        .prog_data_ready_o(pb_prog_data_ready),
        .prog_data_i(pb_prog_data),
        .clear_i(pb_clear),
        .freeze_i(pb_freeze),
        .vpl_wr_valid_i(pb_vpl_wr_valid),
        .vpl_wr_ready_o(pb_vpl_wr_ready),
        .vpl_wr_addr_i(pb_vpl_wr_addr),
        .vpl_wr_data_i(pb_vpl_wr_data),
        .vpl_rd_req_valid_i(1'b0),
        .vpl_rd_req_ready_o(),
        .vpl_rd_addr_i(13'd0),
        .vpl_rd_data_valid_o(),
        .vpl_rd_data_ready_i(1'b0),
        .vpl_rd_data_o(),
        .readout_rd_req_valid_i(pb_rd_req_valid),
        .readout_rd_req_ready_o(pb_rd_req_ready),
        .readout_rd_addr_i(pb_rd_addr),
        .readout_rd_data_valid_o(pb_rd_data_valid),
        .readout_rd_data_ready_i(pb_rd_data_ready),
        .readout_rd_data_o(pb_rd_data),
        .write_valid_o(),
        .write_addr_o(),
        .write_data_o(),
        .write_count_o(),
        .prog_ready_o(),
        .overflow_o(),
        .busy_o()
    );

    always #CLK_HALF_NS sys_clk = ~sys_clk;

    task wait_clk;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge sys_clk);
            end
        end
    endtask

    task check_eq8;
        input [7:0] actual;
        input [7:0] expected;
        input [255:0] message;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=0x%02x expected=0x%02x",
                         message, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_true;
        input condition;
        input [255:0] message;
        begin
            if (!condition) begin
                $display("[FAIL] %0s", message);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task begin_read_cycle;
        begin
            re_fall = 1'b1;
            wait_clk(1);
            re_fall = 1'b0;
        end
    endtask

    task end_read_cycle;
        begin
            re_rise = 1'b1;
            wait_clk(1);
            re_rise = 1'b0;
            wait_clk(1);
            check_true(!dq_oe, "DQ output disabled after RE# rise");
        end
    endtask

    task expect_immediate_read;
        input [7:0] expected;
        input [255:0] message;
        begin
            begin_read_cycle();
            wait_clk(1);
            check_true(dq_oe, "DQ output enabled");
            check_eq8(dq_out, expected, message);
            end_read_cycle();
        end
    endtask

    task expect_page_read;
        input [7:0] expected;
        input [255:0] message;
        integer timeout;
        begin
            begin_read_cycle();
            timeout = 12;
            while (!dq_oe && timeout > 0) begin
                wait_clk(1);
                timeout = timeout - 1;
            end
            check_true(timeout > 0, "Page read output completed");
            check_true(dq_oe, "Page read DQ output enabled");
            check_eq8(dq_out, expected, message);
            end_read_cycle();
        end
    endtask

    task set_source;
        input [7:0] ctrl;
        begin
            readout_ctrl = ctrl;
            wait_clk(2);
        end
    endtask

    task reset_read_ptr;
        begin
            ptr_reset = 1'b1;
            wait_clk(1);
            ptr_reset = 1'b0;
            wait_clk(1);
            check_true(read_ptr == 13'd0, "Read pointer reset");
        end
    endtask

    task page_write;
        input [12:0] addr;
        input [7:0] value;
        begin
            check_true(pb_vpl_wr_ready, "Page Buffer write ready");
            pb_vpl_wr_addr = addr;
            pb_vpl_wr_data = value;
            pb_vpl_wr_valid = 1'b1;
            wait_clk(1);
            pb_vpl_wr_valid = 1'b0;
            wait_clk(1);
        end
    endtask

    initial begin
        sys_clk = 1'b0;
        sys_rst_n = 1'b0;
        re_fall = 1'b0;
        re_rise = 1'b0;
        ptr_reset = 1'b0;
        readout_ctrl = 8'h00;
        readout_id_addr = 8'h00;
        nand_status = 8'hc0;
        pb_prog_data_valid = 1'b0;
        pb_prog_data = 8'h00;
        pb_clear = 1'b0;
        pb_freeze = 1'b0;
        pb_vpl_wr_valid = 1'b0;
        pb_vpl_wr_addr = 13'd0;
        pb_vpl_wr_data = 8'h00;
        fail_count = 0;

        wait_clk(4);
        sys_rst_n = 1'b1;
        wait_clk(2);

        readout_id_addr = 8'h00;
        set_source(8'h05);
        expect_immediate_read(8'h2c, "Read ID 00h byte 0");
        expect_immediate_read(8'h68, "Read ID 00h byte 1");
        expect_immediate_read(8'h00, "Read ID 00h byte 2");

        readout_id_addr = 8'h20;
        wait_clk(2);
        check_true(read_ptr == 13'd0,
                   "Read pointer resets when Read ID address snapshot changes");
        expect_immediate_read(8'h4f, "Read ID 20h byte O");
        expect_immediate_read(8'h4e, "Read ID 20h byte N");
        expect_immediate_read(8'h46, "Read ID 20h byte F");
        expect_immediate_read(8'h49, "Read ID 20h byte I");

        nand_status = 8'h41;
        set_source(8'h06);
        expect_immediate_read(8'h41, "Read Status byte");
        nand_status = 8'hc0;
        expect_immediate_read(8'hc0, "Read Status polls latest status");

        page_write(13'd0, 8'ha5);
        page_write(13'd1, 8'h5a);
        page_write(13'd2, 8'hc3);
        set_source(8'h07);
        reset_read_ptr();
        expect_page_read(8'ha5, "Page Buffer read byte 0");
        expect_page_read(8'h5a, "Page Buffer read byte 1");
        expect_page_read(8'hc3, "Page Buffer read byte 2");

        set_source(8'h00);
        wait_clk(1);
        check_true(!dq_oe, "DQ output disabled when source is none");

        if (fail_count == 0) begin
            $display("[PASS] tb_nand_read_output_datapath");
        end else begin
            $display("[FAIL] tb_nand_read_output_datapath fail_count=%0d",
                     fail_count);
            $fatal(1, "tb_nand_read_output_datapath failed");
        end
        $finish;
    end

endmodule

`default_nettype wire
