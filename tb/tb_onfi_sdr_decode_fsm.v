`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"
`include "onfi_sdr_defs.vh"

// Purpose: Module-level smoke test for onfi_sdr_decode_fsm.
// Role: Simulation-only testbench.
// Related design docs:
// - design_spec/SIMPLE_ONFI_SDR_decode_fsm.md
// - design_spec/SIMPLE_ONFI_SDR_behavior_model_reference.md
// Block contract: Drives synchronized pin-level bus cycles and verifies decode
// event hold, address snapshot, program data ready/valid behavior, and busy
// illegal command handling without pin synchronization, Register Bank, or Page
// Buffer implementation.
// File version: v0.4
// Revision history:
// - v0.4: Align with Decode FSM port cleanup; verify read decode
//   through decoded_op instead of legacy mode outputs.
// - v0.3: Use shared nand_parameters.vh for sysclk and
//   address-cycle constants.
// - v0.2: Updated for synchronized pin-level input interface.
// - v0.1: Initial Decode FSM module smoke tests.

module tb_onfi_sdr_decode_fsm;

    localparam integer SYS_CLK_PERIOD_NS = `NAND_SYS_CLK_PERIOD_NS;
    localparam [2:0]   READ_ID_ADDR_CYCLES = `NAND_READ_ID_ADDR_CYCLES;
    localparam [2:0]   PAGE_ADDR_CYCLES    = `NAND_PAGE_ADDR_CYCLES;

    reg        sys_clk;
    reg        sys_rst_n;
    reg [7:0]  dq_sync;
    reg        cle_sync;
    reg        ale_sync;
    reg        ce_n_sync;
    reg        we_rise;
    reg        host_busy;
    reg        decode_event_ready;
    reg        prog_data_ready;

    wire       decode_event_valid;
    wire [3:0] decoded_op;
    wire [7:0] cmd;
    wire [7:0] addr0;
    wire [7:0] addr1;
    wire [7:0] addr2;
    wire [7:0] addr3;
    wire [7:0] addr4;
    wire [2:0] addr_count;
    wire [12:0] prog_data_count;
    wire       prog_data_valid;
    wire [7:0] prog_data;
    wire       protocol_error;
    wire [3:0] protocol_error_code;
    wire       fsm_busy;
    wire [2:0] seq_state;

    integer fail_count;

    onfi_sdr_decode_fsm dut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .dq_sync_i(dq_sync),
        .cle_sync_i(cle_sync),
        .ale_sync_i(ale_sync),
        .ce_n_sync_i(ce_n_sync),
        .we_rise_i(we_rise),
        .host_busy_i(host_busy),
        .decode_event_ready_i(decode_event_ready),
        .prog_data_ready_i(prog_data_ready),
        .decode_event_valid_o(decode_event_valid),
        .decoded_op_o(decoded_op),
        .cmd_o(cmd),
        .addr0_o(addr0),
        .addr1_o(addr1),
        .addr2_o(addr2),
        .addr3_o(addr3),
        .addr4_o(addr4),
        .addr_count_o(addr_count),
        .prog_data_count_o(prog_data_count),
        .prog_data_valid_o(prog_data_valid),
        .prog_data_o(prog_data),
        .protocol_error_o(protocol_error),
        .protocol_error_code_o(protocol_error_code),
        .fsm_busy_o(fsm_busy),
        .seq_state_o(seq_state)
    );

    always #(SYS_CLK_PERIOD_NS/2) sys_clk = ~sys_clk;

    task wait_sys_cycles;
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

    task check_eq4;
        input [3:0] actual;
        input [3:0] expected;
        input [255:0] message;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=0x%0h expected=0x%0h",
                         message, actual, expected);
                fail_count = fail_count + 1;
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

    task check_eq13;
        input [12:0] actual;
        input [12:0] expected;
        input [255:0] message;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=%0d expected=%0d",
                         message, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task clear_bus_cycle;
        begin
            cle_sync = 1'b0;
            ale_sync = 1'b0;
            ce_n_sync = 1'b0;
            we_rise = 1'b0;
        end
    endtask

    task pulse_cmd;
        input [7:0] value;
        begin
            dq_sync = value;
            cle_sync = 1'b1;
            ale_sync = 1'b0;
            ce_n_sync = 1'b0;
            we_rise = 1'b1;
            wait_sys_cycles(1);
            clear_bus_cycle();
            wait_sys_cycles(1);
        end
    endtask

    task pulse_addr;
        input [7:0] value;
        begin
            dq_sync = value;
            cle_sync = 1'b0;
            ale_sync = 1'b1;
            ce_n_sync = 1'b0;
            we_rise = 1'b1;
            wait_sys_cycles(1);
            clear_bus_cycle();
            wait_sys_cycles(1);
        end
    endtask

    task pulse_data;
        input [7:0] value;
        begin
            dq_sync = value;
            cle_sync = 1'b0;
            ale_sync = 1'b0;
            ce_n_sync = 1'b0;
            we_rise = 1'b1;
            wait_sys_cycles(1);
            clear_bus_cycle();
            wait_sys_cycles(1);
        end
    endtask

    task wait_event_valid;
        input integer timeout_cycles;
        integer i;
        begin
            i = 0;
            while (!decode_event_valid && i < timeout_cycles) begin
                wait_sys_cycles(1);
                i = i + 1;
            end
            check_true(decode_event_valid, "decode_event_valid timeout");
        end
    endtask

    task accept_event;
        begin
            decode_event_ready = 1'b1;
            wait_sys_cycles(2);
            decode_event_ready = 1'b0;
            wait_sys_cycles(1);
        end
    endtask

    initial begin
        sys_clk = 1'b0;
        sys_rst_n = 1'b0;
        dq_sync = 8'h00;
        clear_bus_cycle();
        host_busy = 1'b0;
        decode_event_ready = 1'b0;
        prog_data_ready = 1'b1;
        fail_count = 0;

        wait_sys_cycles(5);
        sys_rst_n = 1'b1;
        wait_sys_cycles(5);

        pulse_cmd(8'h70);
        wait_event_valid(20);
        check_eq4(decoded_op, `ONFI_OP_READ_STATUS, "70h decoded op");
        check_eq8(cmd, 8'h70, "70h command payload");
        wait_sys_cycles(3);
        check_true(decode_event_valid, "event held while adapter not ready");
        accept_event();
        check_true(!decode_event_valid, "event cleared after accept");

        pulse_cmd(8'h90);
        pulse_addr(8'h20);
        wait_event_valid(30);
        check_eq4(decoded_op, `ONFI_OP_READ_ID, "90h decoded op");
        check_eq8(addr0, 8'h20, "Read ID address snapshot");
        check_true(addr_count == READ_ID_ADDR_CYCLES, "Read ID address count");
        accept_event();

        pulse_cmd(8'h00);
        pulse_addr(8'h34);
        pulse_addr(8'h12);
        pulse_addr(8'h4a);
        pulse_addr(8'h01);
        pulse_addr(8'h00);
        pulse_cmd(8'h30);
        wait_event_valid(40);
        check_eq4(decoded_op, `ONFI_OP_READ_PAGE, "Read Page decoded op");
        check_eq8(cmd, 8'h30, "Read Page confirm command payload");
        check_eq8(addr0, 8'h34, "Read Page addr0");
        check_eq8(addr1, 8'h12, "Read Page addr1");
        check_eq8(addr2, 8'h4a, "Read Page addr2");
        check_true(addr_count == PAGE_ADDR_CYCLES, "Read Page address count");
        accept_event();

        pulse_cmd(8'h80);
        pulse_addr(8'h00);
        pulse_addr(8'h00);
        pulse_addr(8'h00);
        pulse_addr(8'h00);
        pulse_addr(8'h00);
        prog_data_ready = 1'b0;
        pulse_data(8'h5a);
        check_true(prog_data_valid, "program data held when adapter not ready");
        check_eq8(prog_data, 8'h5a, "held program byte");
        check_eq13(prog_data_count, 13'd0, "program count waits for accept");
        prog_data_ready = 1'b1;
        wait_sys_cycles(2);
        check_eq13(prog_data_count, 13'd1, "program count increments on accept");
        pulse_data(8'ha0);
        pulse_data(8'ha1);
        pulse_cmd(8'h10);
        wait_event_valid(40);
        check_eq4(decoded_op, `ONFI_OP_PROGRAM, "Program decoded op");
        check_eq8(cmd, 8'h10, "Program confirm command payload");
        check_eq13(prog_data_count, 13'd3, "Program data count");
        accept_event();

        host_busy = 1'b1;
        pulse_cmd(8'h00);
        wait_event_valid(20);
        check_true(protocol_error, "busy illegal command sets protocol error");
        check_eq4(protocol_error_code, `ONFI_ERR_BUSY_ILLEGAL_CMD,
                  "busy illegal command error code");
        accept_event();
        host_busy = 1'b0;

        wait_sys_cycles(5);
        if (fail_count == 0) begin
            $display("[PASS] tb_onfi_sdr_decode_fsm");
        end else begin
            $display("[FAIL] tb_onfi_sdr_decode_fsm fail_count=%0d", fail_count);
            $fatal(1, "tb_onfi_sdr_decode_fsm failed");
        end
        $finish;
    end

endmodule

`default_nettype wire
