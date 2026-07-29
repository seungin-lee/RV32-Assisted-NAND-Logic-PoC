`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"

// Purpose: Full-sim reproduction of design_spec/host_tb_traffice_scenario.md.
// Role: Simulation-only testbench.
// Related design docs:
// - design_spec/Architecture.md
// - design_spec/host_tb_traffice_scenario.md
// - design_spec/nand_control_fw.md
// Block contract: Drives the canonical ONFI SDR Mode 0 host traffic scenario
// into the integrated top and checks Decode -> Register Bank -> Surrogate FW
// -> VPL -> Page Buffer -> Read Output behavior.
// File version: v0.8
// Revision history:
// - v0.8: Track Host Event Adapter busy and Page Buffer busy separately
//   after removing the top-level adapter_busy alias.
// - v0.7: Remove legacy Decode Frontend mode hierarchical
//   references; readout behavior is checked through REG_READOUT_CTRL and DQ.
// - v0.6: Update runtime command hint for the compact Makefile
//   surface: make sim / make sim-rv32.
// - v0.5: Treat RB_N as part of top-ready detection so RV32 FW
//   initialization backpressure is honored before host traffic starts.
// - v0.4: Add RV32-control full-sim timeout margins and trap
//   monitor for NAND_CONTROL_RV32 runs.
// - v0.3: Track host-facing top interface cleanup: drive inout DQ,
//   observe RB_N, and move debug/status checks to hierarchical references.
// - v0.2: Promoted to full-sim target and added timing/tWB/DQ
//   release guards for host traffic scenario reproduction.
// - v0.1: Initial top-level end-to-end smoke test.

module tb_nand_logic_top_e2e;

    localparam integer SYS_CLK_PERIOD_NS  = `NAND_SYS_CLK_PERIOD_NS;
    localparam integer CORE_CLK_PERIOD_NS = 14;
    localparam integer PROGRAM_BYTES      = 16;
    localparam integer READ_BYTES         = 16;
`ifdef NAND_CONTROL_RV32
    localparam integer WAIT_SHORT         = 20000;
    localparam integer WAIT_RESET         = `NAND_T_RST_CYCLES + 20000;
    localparam integer WAIT_PROGRAM       = `NAND_T_PROG_CYCLES + 100000;
    localparam integer WAIT_READ          = `NAND_T_R_CYCLES + 50000;
    localparam integer WAIT_ERASE         = `NAND_T_BERS_CYCLES +
                                            (`NAND_PAGES_PER_BLOCK *
                                             `NAND_PAGE_SIZE) + 200000;
`else
    localparam integer WAIT_SHORT         = 400;
    localparam integer WAIT_RESET         = `NAND_T_RST_CYCLES + 500;
    localparam integer WAIT_PROGRAM       = `NAND_T_PROG_CYCLES + 5000;
    localparam integer WAIT_READ          = `NAND_T_R_CYCLES + 5000;
    localparam integer WAIT_ERASE         = `NAND_T_BERS_CYCLES +
                                            (`NAND_PAGES_PER_BLOCK *
                                             `NAND_PAGE_SIZE) + 10000;
`endif

    localparam [7:0] STATUS_READY_PASS = 8'hc0;

    reg        sys_clk;
    reg        sys_rst_n;
    reg        core_clk;
    reg        core_rst_n;
    reg [7:0]  host_dq;
    reg        host_dq_oe;
    reg        cle;
    reg        ale;
    reg        ce_n;
    reg        we_n;
    reg        re_n;
    reg        wp_n;

    wire [7:0] dq;
    wire [7:0] dq_out;
    wire       dq_oe;
    wire       rb_n;
    wire       pb_write_valid;
    wire [12:0] pb_write_addr;
    wire [7:0] pb_write_data;
    wire [12:0] pb_write_count;
    wire       pb_prog_ready;
    wire       pb_overflow;
    wire [7:0] nand_status;
    wire [5:0] op_status;
    wire [7:0] op_error;
    wire [7:0] readout_ctrl;
    wire       readout_ptr_reset_pulse;
    wire [12:0] readout_ptr;
    wire       readout_busy;
    wire       fsm_busy;
    wire       host_event_adapter_busy;
    wire       pb_busy;
    wire [2:0] seq_state;
    wire       host_event_pending;
    wire [2:0] irq_status;
    wire [2:0] irq_enable;
    wire       irq;
    wire       reg_busy;
    wire       reg_ready;
    wire       access_error;
    wire       rv32_trap;

    integer fail_count;
    integer scenario_count;
    integer pb_accept_count;
    integer sys_cycle_count;
    integer busy_monitor_elapsed;
    integer busy_monitor_seen_at;
    reg     expect_busy_after_write;
    reg     busy_monitor_active;
    reg     busy_monitor_seen;
    reg [7:0] page_c1;
    reg [7:0] page_c2;
    reg [7:0] page_r1;
    reg [7:0] page_r2;
    reg [7:0] page_r3;
    reg [7:0] erase_r1;
    reg [7:0] erase_r2;
    reg [7:0] erase_r3;

    assign dq = host_dq_oe ? host_dq : 8'hzz;
    assign dq_out = dq;
    assign dq_oe = u_top.dq_oe;
    assign pb_write_valid = u_top.pb_write_valid;
    assign pb_write_addr = u_top.pb_write_addr;
    assign pb_write_data = u_top.pb_write_data;
    assign pb_write_count = u_top.pb_write_count;
    assign pb_prog_ready = u_top.pb_prog_ready;
    assign pb_overflow = u_top.pb_overflow;
    assign nand_status = u_top.nand_status;
    assign op_status = u_top.op_status;
    assign op_error = u_top.op_error;
    assign readout_ctrl = u_top.readout_ctrl;
    assign readout_ptr_reset_pulse = u_top.readout_ptr_reset_pulse;
    assign readout_ptr = u_top.readout_ptr;
    assign readout_busy = u_top.readout_busy;
    assign fsm_busy = u_top.fsm_busy;
    assign host_event_adapter_busy = u_top.host_event_adapter_busy;
    assign pb_busy = u_top.pb_busy;
    assign seq_state = u_top.seq_state;
    assign host_event_pending = u_top.host_event_pending;
    assign irq_status = u_top.irq_status;
    assign irq_enable = u_top.irq_enable;
    assign irq = u_top.irq;
    assign reg_busy = u_top.reg_busy;
    assign reg_ready = u_top.reg_ready;
    assign access_error = u_top.access_error;
    assign rv32_trap = u_top.rv32_trap;

    nand_logic_top u_top (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .dq(dq),
        .cle(cle),
        .ale(ale),
        .ce_n(ce_n),
        .we_n(we_n),
        .re_n(re_n),
        .wp_n(wp_n),
        .rb_n(rb_n)
    );

    always #(SYS_CLK_PERIOD_NS/2) sys_clk = ~sys_clk;
    always #(CORE_CLK_PERIOD_NS/2) core_clk = ~core_clk;

    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            sys_cycle_count <= 0;
            busy_monitor_elapsed <= 0;
            busy_monitor_seen_at <= -1;
            busy_monitor_active <= 1'b0;
            busy_monitor_seen <= 1'b0;
        end else begin
            sys_cycle_count <= sys_cycle_count + 1;
            if (busy_monitor_active) begin
                busy_monitor_elapsed <= busy_monitor_elapsed + 1;
                if (!rb_n && !busy_monitor_seen) begin
                    busy_monitor_seen <= 1'b1;
                    busy_monitor_seen_at <= busy_monitor_elapsed;
                end
            end
        end

        if (host_dq_oe && dq_oe) begin
            $display("[CHECK FAIL] Host/DUT DQ contention time=%0t", $time);
            fail_count <= fail_count + 1;
        end

        if (pb_write_valid) begin
            pb_accept_count <= pb_accept_count + 1;
            $display("[PB] accept[%0d] addr=%0d data=0x%02x",
                     pb_accept_count, pb_write_addr, pb_write_data);
        end

        if (core_rst_n && rv32_trap) begin
            $display("[CHECK FAIL] RV32 control agent trapped time=%0t", $time);
            fail_count <= fail_count + 1;
        end
    end

    task wait_sys_cycles;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge sys_clk);
            end
        end
    endtask

    task scenario_begin;
        input [1023:0] name;
        begin
            scenario_count = scenario_count + 1;
            $display("");
            $display("=== TOP E2E SCENARIO %0d: %0s ===",
                     scenario_count, name);
        end
    endtask

    task check_true;
        input condition;
        input [1023:0] message;
        begin
            if (condition) begin
                $display("[CHECK PASS] %0s", message);
            end else begin
                $display("[CHECK FAIL] %0s", message);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_eq8;
        input [7:0] actual;
        input [7:0] expected;
        input [1023:0] message;
        begin
            if (actual === expected) begin
                $display("[CHECK PASS] %0s actual=0x%02x expected=0x%02x",
                         message, actual, expected);
            end else begin
                $display("[CHECK FAIL] %0s actual=0x%02x expected=0x%02x",
                         message, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_eq13;
        input [12:0] actual;
        input [12:0] expected;
        input [1023:0] message;
        begin
            if (actual === expected) begin
                $display("[CHECK PASS] %0s actual=%0d expected=%0d",
                         message, actual, expected);
            end else begin
                $display("[CHECK FAIL] %0s actual=%0d expected=%0d",
                         message, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_min_cycles;
        input integer observed;
        input integer required;
        input [1023:0] message;
        begin
            if (observed >= required) begin
                $display("[TIMING PASS] %0s observed=%0d required>=%0d",
                         message, observed, required);
            end else begin
                $display("[TIMING FAIL] %0s observed=%0d required>=%0d",
                         message, observed, required);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task wait_timing_guard;
        input integer cycles;
        input [1023:0] message;
        begin
            wait_sys_cycles(cycles);
            $display("[TIMING PASS] %0s guard=%0d cycles", message, cycles);
        end
    endtask

    task make_page_addr;
        input integer block;
        input integer page;
        input integer column;
        output [7:0] c1;
        output [7:0] c2;
        output [7:0] r1;
        output [7:0] r2;
        output [7:0] r3;
        integer row;
        begin
            check_true(block >= 0 && block < `NAND_NUM_BLOCKS,
                       "Page address block in SIMPLE geometry range");
            check_true(page >= 0 && page < `NAND_PAGES_PER_BLOCK,
                       "Page address page in SIMPLE geometry range");
            check_true(column >= 0 && column < `NAND_PAGE_SIZE,
                       "Page address column in SIMPLE geometry range");
            row = block * `NAND_PAGES_PER_BLOCK + page;
            c1 = column[7:0];
            c2 = (column >> 8) & 8'hff;
            r1 = row[7:0];
            r2 = (row >> 8) & 8'hff;
            r3 = (row >> 16) & 8'hff;
            $display("[ADDR] page block=%0d page=%0d column=%0d -> %02x %02x %02x %02x %02x",
                     block, page, column, c1, c2, r1, r2, r3);
        end
    endtask

    task make_erase_addr;
        input integer block;
        output [7:0] r1;
        output [7:0] r2;
        output [7:0] r3;
        integer row;
        begin
            check_true(block >= 0 && block < `NAND_NUM_BLOCKS,
                       "Erase address block in SIMPLE geometry range");
            row = block * `NAND_PAGES_PER_BLOCK;
            r1 = row[7:0];
            r2 = (row >> 8) & 8'hff;
            r3 = (row >> 16) & 8'hff;
            $display("[ADDR] erase block=%0d -> %02x %02x %02x",
                     block, r1, r2, r3);
        end
    endtask

    task host_write_cycle;
        input [7:0] value;
        integer cycle_start;
        begin
            cycle_start = sys_cycle_count;
            host_dq_oe = 1'b1;
            host_dq = value;
            wait_sys_cycles(2);
            we_n = 1'b0;
            wait_sys_cycles(5);
            we_n = 1'b1;
            if (expect_busy_after_write) begin
                busy_monitor_active = 1'b1;
                busy_monitor_seen = 1'b0;
                busy_monitor_seen_at = -1;
                busy_monitor_elapsed = 0;
                expect_busy_after_write = 1'b0;
            end
            wait_sys_cycles(7);
            check_min_cycles(sys_cycle_count - cycle_start,
                             `NAND_T_WC_CYCLES,
                             "Mode 0 tWC write cycle");
        end
    endtask

    task host_cmd;
        input [7:0] value;
        begin
            $display("[HOST] CMD 0x%02x", value);
            cle = 1'b1;
            ale = 1'b0;
            host_write_cycle(value);
            cle = 1'b0;
            wait_sys_cycles(2);
        end
    endtask

    task host_cmd_expect_busy;
        input [7:0] value;
        input [1023:0] label;
        begin
            $display("[EXPECT] %0s should drive host-visible Busy within tWB",
                     label);
            expect_busy_after_write = 1'b1;
            host_cmd(value);
        end
    endtask

    task host_addr;
        input [7:0] value;
        begin
            $display("[HOST] ADDR 0x%02x", value);
            cle = 1'b0;
            ale = 1'b1;
            host_write_cycle(value);
            ale = 1'b0;
            wait_sys_cycles(2);
        end
    endtask

    task host_data_in;
        input [7:0] value;
        begin
            $display("[HOST] DATA_IN 0x%02x", value);
            cle = 1'b0;
            ale = 1'b0;
            host_write_cycle(value);
            wait_sys_cycles(2);
        end
    endtask

    task host_read_byte;
        output [7:0] value;
        integer i;
        integer cycle_start;
        begin
            cycle_start = sys_cycle_count;
            host_dq_oe = 1'b0;
            cle = 1'b0;
            ale = 1'b0;
            wait_sys_cycles(2);
            re_n = 1'b0;
            wait_sys_cycles(8);
            i = 0;
            while (!dq_oe && i < 20) begin
                wait_sys_cycles(1);
                i = i + 1;
            end
            if (!dq_oe) begin
                $display("[CHECK FAIL] host_read_byte timeout waiting dq_oe");
                fail_count = fail_count + 1;
                value = 8'hxx;
                re_n = 1'b1;
            end else begin
                value = dq_out;
                re_n = 1'b1;
                $display("[HOST] READ data=0x%02x sampled at RE# rise", value);
                i = 0;
                while (dq_oe && i < 20) begin
                    wait_sys_cycles(1);
                    i = i + 1;
                end
                if (dq_oe) begin
                    $display("[CHECK FAIL] DQ output did not release after RE# rise");
                    fail_count = fail_count + 1;
                end else begin
                    $display("[CHECK PASS] DQ output released after RE# rise");
                end
            end
            wait_sys_cycles(7);
            check_min_cycles(sys_cycle_count - cycle_start,
                             `NAND_T_RC_CYCLES,
                             "Mode 0 tRC read cycle");
        end
    endtask

    task wait_top_ready;
        input [1023:0] label;
        input integer timeout_cycles;
        integer i;
        begin
            i = 0;
            while ((!rb_n || !reg_ready || host_event_pending || irq ||
                    host_event_adapter_busy || pb_busy || fsm_busy) &&
                   i < timeout_cycles) begin
                wait_sys_cycles(1);
                i = i + 1;
            end
            if (i >= timeout_cycles) begin
                $display("[CHECK FAIL] %0s top ready timeout rb_n=%0b reg_ready=%0b host_pending=%0b irq=%0b host_event_adapter_busy=%0b pb_busy=%0b fsm_busy=%0b irq_status=0x%01x op_status=0x%02x",
                         label, rb_n, reg_ready, host_event_pending, irq,
                         host_event_adapter_busy, pb_busy, fsm_busy,
                         irq_status, op_status);
                fail_count = fail_count + 1;
            end else begin
                $display("[WAIT] %0s ready after %0d sys cycles", label, i);
            end
        end
    endtask

    task wait_readout_ctrl;
        input [2:0] expected_ctrl;
        input [1023:0] label;
        input integer timeout_cycles;
        integer i;
        begin
            i = 0;
            while (readout_ctrl[2:0] !== expected_ctrl &&
                   i < timeout_cycles) begin
                wait_sys_cycles(1);
                i = i + 1;
            end
            if (readout_ctrl[2:0] !== expected_ctrl) begin
                $display("[CHECK FAIL] %0s readout_ctrl timeout actual=0x%02x expected=0x%01x",
                         label, readout_ctrl, expected_ctrl);
                fail_count = fail_count + 1;
            end else begin
                $display("[WAIT] %0s readout_ctrl=0x%02x after %0d cycles",
                         label, readout_ctrl, i);
            end
            wait_sys_cycles(4);
        end
    endtask

    task wait_busy_then_ready;
        input [1023:0] label;
        input integer timeout_cycles;
        integer i;
        begin
            i = 0;
            while (i < timeout_cycles) begin
                if (busy_monitor_seen && rb_n) begin
                    $display("[WAIT] %0s busy->ready after %0d cycles",
                             label, i);
                    i = timeout_cycles;
                end else begin
                    wait_sys_cycles(1);
                    i = i + 1;
                end
            end
            if (busy_monitor_seen &&
                busy_monitor_seen_at <= `NAND_T_WB_CYCLES) begin
                $display("[TIMING PASS] %0s Busy observed within tWB at %0d cycles",
                         label, busy_monitor_seen_at);
            end else if (busy_monitor_seen) begin
                $display("[TIMING FAIL] %0s Busy observed after tWB at %0d cycles limit=%0d",
                         label, busy_monitor_seen_at, `NAND_T_WB_CYCLES);
                fail_count = fail_count + 1;
            end else begin
                $display("[TIMING FAIL] %0s Busy was not observed", label);
                fail_count = fail_count + 1;
            end

            if (!busy_monitor_seen || !rb_n) begin
                $display("[CHECK FAIL] %0s busy/ready timeout rb_n=%0b nand_status=0x%02x reg_ready=%0b irq=0x%01x host_pending=%0b host_event_adapter_busy=%0b pb_busy=%0b fsm_busy=%0b op_status=0x%02x op_error=0x%02x",
                         label, rb_n, nand_status, reg_ready,
                         irq_status, host_event_pending,
                         host_event_adapter_busy, pb_busy, fsm_busy,
                         op_status, op_error);
                fail_count = fail_count + 1;
            end
            busy_monitor_active = 1'b0;
        end
    endtask

    task wait_page_buffer_cleared;
        input [1023:0] label;
        input integer timeout_cycles;
        integer i;
        begin
            i = 0;
            while ((pb_write_count != 13'd0 || pb_prog_ready ||
                    pb_overflow) && i < timeout_cycles) begin
                wait_sys_cycles(1);
                i = i + 1;
            end
            if (pb_write_count != 13'd0 || pb_prog_ready || pb_overflow) begin
                $display("[CHECK FAIL] %0s PB clear timeout count=%0d prog_ready=%0b overflow=%0b",
                         label, pb_write_count, pb_prog_ready, pb_overflow);
                fail_count = fail_count + 1;
            end else begin
                $display("[WAIT] %0s PB cleared after %0d cycles", label, i);
            end
        end
    endtask

    task read_and_expect;
        input [7:0] expected;
        input [1023:0] label;
        reg [7:0] actual;
        begin
            host_read_byte(actual);
            check_eq8(actual, expected, label);
        end
    endtask

    task check_status_ready_pass;
        input [7:0] status;
        input [1023:0] label;
        begin
            check_true(status[7], {label, " WP_N bit high"});
            check_true(status[6], {label, " ready bit high"});
            check_true(!status[0], {label, " fail bit low"});
        end
    endtask

    task issue_read_status_and_check;
        input [1023:0] label;
        reg [7:0] status;
        begin
            host_cmd(8'h70);
            wait_readout_ctrl(3'b110, {label, " readout status"}, WAIT_SHORT);
            wait_timing_guard(`NAND_T_WHR_CYCLES, {label, " tWHR"});
            host_read_byte(status);
            check_status_ready_pass(status, label);
            check_eq8(status, STATUS_READY_PASS, {label, " status byte"});
            wait_top_ready({label, " after status"}, WAIT_SHORT);
        end
    endtask

    integer idx;

    initial begin
        sys_clk = 1'b0;
        core_clk = 1'b0;
        sys_rst_n = 1'b0;
        core_rst_n = 1'b0;
        host_dq = 8'h00;
        host_dq_oe = 1'b0;
        cle = 1'b0;
        ale = 1'b0;
        ce_n = 1'b0;
        we_n = 1'b1;
        re_n = 1'b1;
        wp_n = 1'b1;
        fail_count = 0;
        scenario_count = 0;
        pb_accept_count = 0;
        sys_cycle_count = 0;
        expect_busy_after_write = 1'b0;
        busy_monitor_active = 1'b0;
        busy_monitor_seen = 1'b0;
        busy_monitor_elapsed = 0;
        busy_monitor_seen_at = -1;

        $display("=== NAND FULL-SIM: host_tb_traffice_scenario reproduction ===");
        $display("[INFO] Scope: Host traffic -> nand_logic_top integrated data/control path");
        $display("[INFO] Command: make sim or make sim-rv32");

        wait_sys_cycles(8);
        sys_rst_n = 1'b1;
        core_rst_n = 1'b1;
        wait_sys_cycles(20);
        wait_top_ready("initial", WAIT_SHORT);

        make_page_addr(0, 0, 0, page_c1, page_c2,
                       page_r1, page_r2, page_r3);
        make_erase_addr(0, erase_r1, erase_r2, erase_r3);

        scenario_begin("Reset FFh");
        host_cmd_expect_busy(8'hff, "Reset FFh");
        wait_busy_then_ready("Reset FFh", WAIT_RESET);
        check_eq8(nand_status, STATUS_READY_PASS, "Reset status ready/pass");

        scenario_begin("Read ID 90h + addr 00h");
        host_cmd(8'h90);
        host_addr(8'h00);
        wait_readout_ctrl(3'b101, "Read ID 00h", WAIT_SHORT);
        wait_timing_guard(`NAND_T_WHR_CYCLES, "Read ID 00h tWHR");
        read_and_expect(8'h2c, "Read ID 00h byte 0");
        read_and_expect(8'h68, "Read ID 00h byte 1");
        read_and_expect(8'h00, "Read ID 00h byte 2");
        read_and_expect(8'h00, "Read ID 00h byte 3");
        read_and_expect(8'h00, "Read ID 00h byte 4");
        read_and_expect(8'h00, "Read ID 00h byte 5");
        wait_top_ready("Read ID 00h done", WAIT_SHORT);

        scenario_begin("Read ID 90h + addr 20h");
        host_cmd(8'h90);
        host_addr(8'h20);
        wait_readout_ctrl(3'b101, "Read ID 20h", WAIT_SHORT);
        wait_timing_guard(`NAND_T_WHR_CYCLES, "Read ID 20h tWHR");
        read_and_expect(8'h4f, "Read ID 20h byte O");
        read_and_expect(8'h4e, "Read ID 20h byte N");
        read_and_expect(8'h46, "Read ID 20h byte F");
        read_and_expect(8'h49, "Read ID 20h byte I");
        read_and_expect(8'h00, "Read ID 20h byte 4");
        read_and_expect(8'h00, "Read ID 20h byte 5");
        wait_top_ready("Read ID 20h done", WAIT_SHORT);

        scenario_begin("Page Program 80h + data + 10h");
        pb_accept_count = 0;
        host_cmd(8'h80);
        host_addr(page_c1);
        host_addr(page_c2);
        host_addr(page_r1);
        host_addr(page_r2);
        host_addr(page_r3);
        wait_timing_guard(`NAND_T_ADL_CYCLES, "Program tADL");
        for (idx = 0; idx < PROGRAM_BYTES; idx = idx + 1) begin
            host_data_in(8'ha0 + idx[7:0]);
        end
        host_cmd_expect_busy(8'h10, "Program confirm 10h");
        wait_busy_then_ready("Program", WAIT_PROGRAM);
        wait_page_buffer_cleared("Program", WAIT_SHORT);
        check_eq13(pb_write_count, 13'd0,
                   "Page Buffer count cleared after successful program");
        check_true(!pb_prog_ready, "Page Buffer prog_ready cleared after program");
        check_true(!pb_overflow, "Page Buffer overflow clear after program");
        check_true(pb_accept_count == PROGRAM_BYTES,
                   "Page Buffer accepted program payload");

        scenario_begin("Read Status after Program");
        issue_read_status_and_check("Program status");

        scenario_begin("Read Page after Program");
        host_cmd(8'h00);
        host_addr(page_c1);
        host_addr(page_c2);
        host_addr(page_r1);
        host_addr(page_r2);
        host_addr(page_r3);
        host_cmd_expect_busy(8'h30, "Read Page confirm 30h");
        wait_busy_then_ready("Read Page after Program", WAIT_READ);
        wait_readout_ctrl(3'b111, "Read Page output after Program",
                          WAIT_SHORT);
        wait_timing_guard(`NAND_T_RR_CYCLES, "Read Page after Program tRR");
        for (idx = 0; idx < READ_BYTES; idx = idx + 1) begin
            read_and_expect(8'ha0 + idx[7:0], "Program readback byte");
        end
        wait_top_ready("Read Page after Program done", WAIT_SHORT);

        scenario_begin("Block Erase 60h + D0h");
        host_cmd(8'h60);
        host_addr(erase_r1);
        host_addr(erase_r2);
        host_addr(erase_r3);
        host_cmd_expect_busy(8'hd0, "Erase confirm D0h");
        wait_busy_then_ready("Erase", WAIT_ERASE);

        scenario_begin("Read Status after Erase");
        issue_read_status_and_check("Erase status");

        scenario_begin("Read Page after Erase");
        host_cmd(8'h00);
        host_addr(page_c1);
        host_addr(page_c2);
        host_addr(page_r1);
        host_addr(page_r2);
        host_addr(page_r3);
        host_cmd_expect_busy(8'h30, "Read Page confirm 30h after Erase");
        wait_busy_then_ready("Read Page after Erase", WAIT_READ);
        wait_readout_ctrl(3'b111, "Read Page output after Erase",
                          WAIT_SHORT);
        wait_timing_guard(`NAND_T_RR_CYCLES, "Read Page after Erase tRR");
        for (idx = 0; idx < READ_BYTES; idx = idx + 1) begin
            read_and_expect(8'hff, "Erase readback byte");
        end
        wait_top_ready("Read Page after Erase done", WAIT_SHORT);

        wait_sys_cycles(20);
        if (fail_count == 0) begin
            $display("");
            $display("[PASS] NAND full-sim scenarios=%0d",
                     scenario_count);
        end else begin
            $display("");
            $display("[FAIL] NAND full-sim fail_count=%0d scenarios=%0d",
                     fail_count, scenario_count);
            $fatal(1, "NAND full-sim failed");
        end
        $finish;
    end

endmodule

`default_nettype wire
