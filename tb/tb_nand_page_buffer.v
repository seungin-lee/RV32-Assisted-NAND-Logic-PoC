`timescale 1ns/1ps
`default_nettype none

// Purpose: Directed smoke test for nand_page_buffer data ports.
// Role: Simulation-only testbench.
// Related design docs:
// - design_spec/Architecture.md
// - design_spec/nand_adapter_contracts.md
// Block contract: Checks direct sysclk program data accept, VPL direct
// write/read access, Read Output direct read access, write monitor,
// freeze/prog_ready, clear, and overflow behavior.
// File version: v0.3
// Revision history:
// - v0.3: Add Read Output direct read port checks.
// - v0.2: Add VPL direct write/read port checks.
// - v0.1: Initial Page Buffer direct write path smoke test.

module tb_nand_page_buffer;

    localparam integer CLK_HALF_NS = 5;
    localparam integer PAGE_SIZE = 4;

    reg        sys_clk;
    reg        sys_rst_n;
    reg        prog_data_valid;
    wire       prog_data_ready;
    reg  [7:0] prog_data;
    reg        clear;
    reg        freeze;
    reg        vpl_wr_valid;
    wire       vpl_wr_ready;
    reg [12:0] vpl_wr_addr;
    reg [7:0]  vpl_wr_data;
    reg        vpl_rd_req_valid;
    wire       vpl_rd_req_ready;
    reg [12:0] vpl_rd_addr;
    wire       vpl_rd_data_valid;
    reg        vpl_rd_data_ready;
    wire [7:0] vpl_rd_data;
    reg        readout_rd_req_valid;
    wire       readout_rd_req_ready;
    reg [12:0] readout_rd_addr;
    wire       readout_rd_data_valid;
    reg        readout_rd_data_ready;
    wire [7:0] readout_rd_data;
    wire       write_valid;
    wire [12:0] write_addr;
    wire [7:0] write_data;
    wire [12:0] write_count;
    wire       prog_ready;
    wire       overflow;
    wire       busy;

    integer fail_count;
    integer accept_count;
    reg [7:0] captured [0:PAGE_SIZE-1];

    nand_page_buffer #(
        .PAGE_SIZE(PAGE_SIZE)
    ) dut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .prog_data_valid_i(prog_data_valid),
        .prog_data_ready_o(prog_data_ready),
        .prog_data_i(prog_data),
        .clear_i(clear),
        .freeze_i(freeze),
        .vpl_wr_valid_i(vpl_wr_valid),
        .vpl_wr_ready_o(vpl_wr_ready),
        .vpl_wr_addr_i(vpl_wr_addr),
        .vpl_wr_data_i(vpl_wr_data),
        .vpl_rd_req_valid_i(vpl_rd_req_valid),
        .vpl_rd_req_ready_o(vpl_rd_req_ready),
        .vpl_rd_addr_i(vpl_rd_addr),
        .vpl_rd_data_valid_o(vpl_rd_data_valid),
        .vpl_rd_data_ready_i(vpl_rd_data_ready),
        .vpl_rd_data_o(vpl_rd_data),
        .readout_rd_req_valid_i(readout_rd_req_valid),
        .readout_rd_req_ready_o(readout_rd_req_ready),
        .readout_rd_addr_i(readout_rd_addr),
        .readout_rd_data_valid_o(readout_rd_data_valid),
        .readout_rd_data_ready_i(readout_rd_data_ready),
        .readout_rd_data_o(readout_rd_data),
        .write_valid_o(write_valid),
        .write_addr_o(write_addr),
        .write_data_o(write_data),
        .write_count_o(write_count),
        .prog_ready_o(prog_ready),
        .overflow_o(overflow),
        .busy_o(busy)
    );

    always #CLK_HALF_NS sys_clk = ~sys_clk;

    always @(posedge sys_clk) begin
        if (write_valid) begin
            if (write_addr < PAGE_SIZE[12:0]) begin
                captured[write_addr] <= write_data;
            end
            accept_count <= accept_count + 1;
        end
    end

    task wait_clk;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge sys_clk);
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

    task write_byte;
        input [7:0] value;
        begin
            check_true(prog_data_ready, "Page Buffer ready before write");
            prog_data = value;
            prog_data_valid = 1'b1;
            wait_clk(1);
            prog_data_valid = 1'b0;
            wait_clk(1);
        end
    endtask

    task vpl_write_byte;
        input [12:0] addr;
        input [7:0] value;
        begin
            check_true(vpl_wr_ready, "VPL write ready before write");
            vpl_wr_addr = addr;
            vpl_wr_data = value;
            vpl_wr_valid = 1'b1;
            wait_clk(1);
            vpl_wr_valid = 1'b0;
            wait_clk(1);
        end
    endtask

    task vpl_read_expect;
        input [12:0] addr;
        input [7:0] expected;
        integer timeout;
        begin
            check_true(vpl_rd_req_ready, "VPL read request ready");
            vpl_rd_addr = addr;
            vpl_rd_req_valid = 1'b1;
            wait_clk(1);
            vpl_rd_req_valid = 1'b0;
            timeout = 8;
            while (!vpl_rd_data_valid && timeout > 0) begin
                wait_clk(1);
                timeout = timeout - 1;
            end
            check_true(timeout > 0, "VPL read data valid");
            check_true(vpl_rd_data == expected, "VPL read data matches");
            vpl_rd_data_ready = 1'b1;
            wait_clk(1);
            vpl_rd_data_ready = 1'b0;
            wait_clk(1);
        end
    endtask

    task readout_read_expect;
        input [12:0] addr;
        input [7:0] expected;
        integer timeout;
        begin
            check_true(readout_rd_req_ready, "Readout read request ready");
            readout_rd_addr = addr;
            readout_rd_req_valid = 1'b1;
            wait_clk(1);
            readout_rd_req_valid = 1'b0;
            timeout = 8;
            while (!readout_rd_data_valid && timeout > 0) begin
                wait_clk(1);
                timeout = timeout - 1;
            end
            check_true(timeout > 0, "Readout read data valid");
            check_true(readout_rd_data == expected, "Readout read data matches");
            readout_rd_data_ready = 1'b1;
            wait_clk(1);
            readout_rd_data_ready = 1'b0;
            wait_clk(1);
        end
    endtask

    initial begin
        sys_clk = 1'b0;
        sys_rst_n = 1'b0;
        prog_data_valid = 1'b0;
        prog_data = 8'h00;
        clear = 1'b0;
        freeze = 1'b0;
        vpl_wr_valid = 1'b0;
        vpl_wr_addr = 13'd0;
        vpl_wr_data = 8'h00;
        vpl_rd_req_valid = 1'b0;
        vpl_rd_addr = 13'd0;
        vpl_rd_data_ready = 1'b0;
        readout_rd_req_valid = 1'b0;
        readout_rd_addr = 13'd0;
        readout_rd_data_ready = 1'b0;
        fail_count = 0;
        accept_count = 0;

        wait_clk(4);
        sys_rst_n = 1'b1;
        wait_clk(2);

        write_byte(8'ha0);
        write_byte(8'ha1);
        write_byte(8'ha2);
        check_true(write_count == 13'd3, "write count after three bytes");
        check_true(accept_count == 3, "accept count after three bytes");
        check_true(captured[0] == 8'ha0, "captured byte 0");
        check_true(captured[2] == 8'ha2, "captured byte 2");

        freeze = 1'b1;
        wait_clk(1);
        freeze = 1'b0;
        wait_clk(1);
        check_true(prog_ready, "prog_ready set after freeze");
        check_true(!prog_data_ready, "not ready after freeze");

        clear = 1'b1;
        wait_clk(1);
        clear = 1'b0;
        wait_clk(1);
        check_true(write_count == 13'd0, "write count clears");
        check_true(!prog_ready, "prog_ready clears");
        check_true(!overflow, "overflow clears");

        vpl_write_byte(13'd0, 8'hc0);
        vpl_write_byte(13'd1, 8'hc1);
        vpl_read_expect(13'd0, 8'hc0);
        vpl_read_expect(13'd1, 8'hc1);
        readout_read_expect(13'd0, 8'hc0);
        readout_read_expect(13'd1, 8'hc1);

        write_byte(8'hb0);
        write_byte(8'hb1);
        write_byte(8'hb2);
        write_byte(8'hb3);
        check_true(write_count == PAGE_SIZE[12:0], "write count reaches page size");
        prog_data = 8'hff;
        prog_data_valid = 1'b1;
        wait_clk(1);
        prog_data_valid = 1'b0;
        wait_clk(1);
        check_true(overflow, "overflow set on write past page size");
        check_true(!prog_data_ready, "not ready after overflow");

        if (fail_count == 0) begin
            $display("[PASS] tb_nand_page_buffer");
        end else begin
            $display("[FAIL] tb_nand_page_buffer fail_count=%0d", fail_count);
            $fatal(1, "tb_nand_page_buffer failed");
        end
        $finish;
    end

endmodule

`default_nettype wire
