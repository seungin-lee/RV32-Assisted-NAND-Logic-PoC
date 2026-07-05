`timescale 1ns/1ps
`default_nettype none

// Purpose: Module-level smoke test for pin_sync_edge_detect.
// Role: Simulation-only testbench.
// Related design docs:
// - design_spec/SIMPLE_ONFI_SDR_decode_fsm.md
// - design_spec/nand_cdc_ip.md
// Block contract: Verifies generic 2-stage synchronization and per-bit
// one-cycle rise/fall pulse generation without ONFI-specific classification.
// File version: v0.2
// Revision history:
// - v0.2: Update CDC reference to NAND-owned CDC IP document.
// - v0.1: Initial generic pin sync and edge detect smoke test.

module tb_pin_sync_edge_detect;

    localparam integer WIDTH = 4;
    localparam [WIDTH-1:0] RESET_VALUE = 4'b1010;
    localparam integer CLK_PERIOD_NS = 10;

    reg clk;
    reg resetn;
    reg [WIDTH-1:0] async_pins;
    wire [WIDTH-1:0] sync_pins;
    wire [WIDTH-1:0] rise_pulse;
    wire [WIDTH-1:0] fall_pulse;

    integer fail_count;

    pin_sync_edge_detect #(
        .WIDTH(WIDTH),
        .RESET_VALUE(RESET_VALUE)
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .async_i(async_pins),
        .sync_o(sync_pins),
        .rise_pulse_o(rise_pulse),
        .fall_pulse_o(fall_pulse)
    );

    always #(CLK_PERIOD_NS/2) clk = ~clk;

    task wait_clk;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge clk);
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

    task check_eq;
        input [WIDTH-1:0] actual;
        input [WIDTH-1:0] expected;
        input [255:0] message;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=%b expected=%b",
                         message, actual, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("[SUCCESS] %0s actual=%b expected=%b",
                         message, actual, expected);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        resetn = 1'b0;
        async_pins = RESET_VALUE;
        fail_count = 0;

        wait_clk(3);
        check_eq(sync_pins, RESET_VALUE, "sync reset value");
        check_eq(rise_pulse, 4'b0000, "rise reset clear");
        check_eq(fall_pulse, 4'b0000, "fall reset clear");

        resetn = 1'b1;
        wait_clk(2);

        async_pins = 4'b1011;
        wait_clk(1);
        check_eq(rise_pulse, 4'b0000, "no pulse before synchronized update");
        wait_clk(1);
        check_eq(sync_pins, 4'b1011, "bit0 synchronized high");
        check_eq(rise_pulse, 4'b0001, "bit0 rise pulse");
        check_eq(fall_pulse, 4'b0000, "no fall on bit0 rise");
        wait_clk(1);
        check_eq(rise_pulse, 4'b0000, "rise pulse is one cycle");

        async_pins = 4'b0011;
        wait_clk(2);
        check_eq(sync_pins, 4'b0011, "bit3 synchronized low");
        check_eq(fall_pulse, 4'b1000, "bit3 fall pulse");
        check_eq(rise_pulse, 4'b0000, "no rise on bit3 fall");
        wait_clk(1);
        check_eq(fall_pulse, 4'b0000, "fall pulse is one cycle");

        async_pins = 4'b1100;
        wait_clk(2);
        check_eq(sync_pins, 4'b1100, "multi-bit synchronized update");
        check_eq(rise_pulse, 4'b1100, "multi-bit rise pulse");
        check_eq(fall_pulse, 4'b0011, "multi-bit fall pulse");

        check_true(fail_count == 0, "all checks passed");
        if (fail_count == 0) begin
            $display("[PASS] tb_pin_sync_edge_detect");
        end else begin
            $display("[FAIL] tb_pin_sync_edge_detect fail_count=%0d", fail_count);
            $fatal(1, "tb_pin_sync_edge_detect failed");
        end
        $finish;
    end

endmodule

`default_nettype wire
