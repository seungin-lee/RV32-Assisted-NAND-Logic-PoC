`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"
`include "onfi_sdr_defs.vh"

// Purpose: Traffic-scenario based test for Decode Frontend plus external role
// adapters and sysclk Page Buffer.
// Role: Simulation-only testbench.
// Related design docs:
// - design_spec/Architecture.md
// - design_spec/SIMPLE_ONFI_SDR_behavior_model_reference.md
// - design_spec/host_tb_traffice_scenario.md
// - design_spec/SIMPLE_ONFI_SDR_decode_fsm.md
// - design_spec/nand_adapter_contracts.md
// Block contract: Drives ONFI SDR Mode 0-style host traffic and checks that
// raw Decode Frontend handoff ports become Register Bank event payloads and
// Page Buffer writes through top-level-style role adapter and Page Buffer
// instances.
// Register Bank IRQ/W1C, VPL, and read-output data drive are outside this test
// scope.
// File version: v0.10
// Revision history:
// - v0.10: Align with Decode Frontend port cleanup; read scenarios
//   verify decoded events instead of legacy mode outputs.
// - v0.9: Tie off exported frontend RE# edge outputs and Page
//   Buffer Read Output direct read ports.
// - v0.8: Tie off new nand_page_buffer VPL direct ports; Decode
//   frontend scenario coverage remains focused on host traffic and PB stream.
// - v0.7: Replace temporary Page Buffer write adapter instance
//   with nand_page_buffer direct program-stream input.
// - v0.6: Instantiate Host Event and Page Buffer write adapters
//   outside Decode Frontend to match nand_logic_top structure.
// - v0.5: Rename frontend ports to sys_clk/core_clk and treat PB
//   writes as a sys_clk-local direct path.
// - v0.4: Use shared nand_parameters.vh for geometry, sysclk, and
//   SDR Mode 0 timing guard cycles.
// - v0.3: Expanded into traffic-scenario/scoreboard-style checks
//   with explicit host input and expected decode result logs.
// - v0.2: Updated for CDC-aware adapter integration and PB freeze
//   check timing.
// - v0.1: Initial Decode FSM + Adapter integration smoke test.

module tb_onfi_sdr_decode_frontend;

    localparam integer SYS_CLK_PERIOD_NS = `NAND_SYS_CLK_PERIOD_NS;
    localparam integer T_WHR_CYCLES      = `NAND_T_WHR_CYCLES;
    localparam integer T_ADL_CYCLES      = `NAND_T_ADL_CYCLES;
    localparam integer T_RR_CYCLES       = `NAND_T_RR_CYCLES;
    localparam integer PROGRAM_BYTES     = 16;
    localparam integer CAPTURE_DEPTH     = 32;
    localparam [2:0]   PAGE_ADDR_CYCLES  = `NAND_PAGE_ADDR_CYCLES;
    localparam [2:0]   ERASE_ADDR_CYCLES = `NAND_ERASE_ADDR_CYCLES;

    reg        sys_clk;
    reg        sys_rst_n;
    reg [7:0]  dq_in;
    reg        cle;
    reg        ale;
    reg        ce_n;
    reg        we_n;
    reg        re_n;
    reg        host_busy;
    wire       decode_event_valid;
    wire       decode_event_ready;
    wire [3:0] decoded_op;
    wire [7:0] cmd;
    wire [7:0] addr0;
    wire [7:0] addr1;
    wire [7:0] addr2;
    wire [7:0] addr3;
    wire [7:0] addr4;
    wire [2:0] addr_count;
    wire [12:0] prog_data_count;
    wire       protocol_error;
    wire [3:0] protocol_error_code;
    wire       decode_event_accept;
    wire       host_event_adapter_busy;
    wire       reg_event_valid;
    reg        reg_event_ready;
    wire [3:0] reg_decoded_op;
    wire [7:0] reg_cmd;
    wire [7:0] reg_addr0;
    wire [7:0] reg_addr1;
    wire [7:0] reg_addr2;
    wire [7:0] reg_addr3;
    wire [7:0] reg_addr4;
    wire [2:0] reg_addr_count;
    wire [12:0] reg_prog_data_count;
    wire       reg_protocol_error;
    wire [3:0] reg_protocol_error_code;
    wire       prog_data_valid;
    wire       prog_data_ready;
    wire [7:0] prog_data;
    wire       pb_write_valid;
    wire [12:0] pb_write_addr;
    wire [7:0] pb_write_data;
    reg        pb_clear;
    wire [12:0] pb_write_count;
    wire       pb_prog_ready;
    wire       pb_overflow;
    wire       pb_busy;
    wire       fsm_busy;
    wire       adapter_busy;
    wire [2:0] seq_state;

    integer fail_count;
    integer captured_count;
    integer scenario_count;
    reg [7:0] captured_pb [0:CAPTURE_DEPTH-1];
    reg [7:0] page_c1;
    reg [7:0] page_c2;
    reg [7:0] page_r1;
    reg [7:0] page_r2;
    reg [7:0] page_r3;
    reg [7:0] erase_r1;
    reg [7:0] erase_r2;
    reg [7:0] erase_r3;

    assign decode_event_accept = decode_event_valid && decode_event_ready;
    assign adapter_busy = host_event_adapter_busy || pb_busy;

    onfi_sdr_decode_frontend dut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .dq_in(dq_in),
        .cle(cle),
        .ale(ale),
        .ce_n(ce_n),
        .we_n(we_n),
        .re_n(re_n),
        .host_busy_i(host_busy),
        .decode_event_valid_o(decode_event_valid),
        .decode_event_ready_i(decode_event_ready),
        .decoded_op_o(decoded_op),
        .cmd_o(cmd),
        .addr0_o(addr0),
        .addr1_o(addr1),
        .addr2_o(addr2),
        .addr3_o(addr3),
        .addr4_o(addr4),
        .addr_count_o(addr_count),
        .prog_data_count_o(prog_data_count),
        .protocol_error_o(protocol_error),
        .protocol_error_code_o(protocol_error_code),
        .prog_data_valid_o(prog_data_valid),
        .prog_data_ready_i(prog_data_ready),
        .prog_data_o(prog_data),
        .fsm_busy_o(fsm_busy),
        .re_fall_o(),
        .re_rise_o(),
        .seq_state_o(seq_state)
    );

    nand_host_event_adapter u_host_event_adapter (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .decode_event_valid_i(decode_event_valid),
        .decode_event_ready_o(decode_event_ready),
        .decoded_op_i(decoded_op),
        .cmd_i(cmd),
        .addr0_i(addr0),
        .addr1_i(addr1),
        .addr2_i(addr2),
        .addr3_i(addr3),
        .addr4_i(addr4),
        .addr_count_i(addr_count),
        .prog_data_count_i(prog_data_count),
        .protocol_error_i(protocol_error),
        .protocol_error_code_i(protocol_error_code),
        .core_clk(sys_clk),
        .core_rst_n(sys_rst_n),
        .reg_event_valid_o(reg_event_valid),
        .reg_event_ready_i(reg_event_ready),
        .reg_decoded_op_o(reg_decoded_op),
        .reg_cmd_o(reg_cmd),
        .reg_addr0_o(reg_addr0),
        .reg_addr1_o(reg_addr1),
        .reg_addr2_o(reg_addr2),
        .reg_addr3_o(reg_addr3),
        .reg_addr4_o(reg_addr4),
        .reg_addr_count_o(reg_addr_count),
        .reg_prog_data_count_o(reg_prog_data_count),
        .reg_protocol_error_o(reg_protocol_error),
        .reg_protocol_error_code_o(reg_protocol_error_code),
        .adapter_busy_o(host_event_adapter_busy)
    );

    nand_page_buffer #(
        .PAGE_SIZE(`NAND_PAGE_SIZE)
    ) u_page_buffer (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .prog_data_valid_i(prog_data_valid),
        .prog_data_ready_o(prog_data_ready),
        .prog_data_i(prog_data),
        .clear_i(pb_clear),
        .freeze_i(decode_event_accept &&
                  (decoded_op == `ONFI_OP_PROGRAM) &&
                  !protocol_error),
        .vpl_wr_valid_i(1'b0),
        .vpl_wr_ready_o(),
        .vpl_wr_addr_i(13'd0),
        .vpl_wr_data_i(8'h00),
        .vpl_rd_req_valid_i(1'b0),
        .vpl_rd_req_ready_o(),
        .vpl_rd_addr_i(13'd0),
        .vpl_rd_data_valid_o(),
        .vpl_rd_data_ready_i(1'b0),
        .vpl_rd_data_o(),
        .readout_rd_req_valid_i(1'b0),
        .readout_rd_req_ready_o(),
        .readout_rd_addr_i(13'd0),
        .readout_rd_data_valid_o(),
        .readout_rd_data_ready_i(1'b0),
        .readout_rd_data_o(),
        .write_valid_o(pb_write_valid),
        .write_addr_o(pb_write_addr),
        .write_data_o(pb_write_data),
        .write_count_o(pb_write_count),
        .prog_ready_o(pb_prog_ready),
        .overflow_o(pb_overflow),
        .busy_o(pb_busy)
    );

    always #(SYS_CLK_PERIOD_NS/2) sys_clk = ~sys_clk;

    always @(posedge sys_clk) begin
        if (pb_write_valid) begin
            if (captured_count < CAPTURE_DEPTH) begin
                captured_pb[captured_count] <= pb_write_data;
                $display("[PB] accept[%0d] addr=%0d data=0x%02x",
                         captured_count, pb_write_addr, pb_write_data);
            end
            captured_count <= captured_count + 1;
        end
    end

    function [127:0] op_name;
        input [3:0] op;
        begin
            case (op)
                `ONFI_OP_RESET:       op_name = "RESET";
                `ONFI_OP_READ_ID:     op_name = "READ_ID";
                `ONFI_OP_READ_STATUS: op_name = "READ_STATUS";
                `ONFI_OP_READ_PAGE:   op_name = "READ_PAGE";
                `ONFI_OP_PROGRAM:     op_name = "PROGRAM";
                `ONFI_OP_ERASE:       op_name = "ERASE";
                `ONFI_OP_UNSUPPORTED: op_name = "UNSUPPORTED";
                default:              op_name = "UNKNOWN";
            endcase
        end
    endfunction

    function [127:0] err_name;
        input [3:0] err;
        begin
            case (err)
                `ONFI_ERR_NONE:             err_name = "NONE";
                `ONFI_ERR_INVALID_BUS:      err_name = "INVALID_BUS";
                `ONFI_ERR_UNSUPPORTED_CMD:  err_name = "UNSUPPORTED_CMD";
                `ONFI_ERR_UNEXPECTED_ADDR:  err_name = "UNEXPECTED_ADDR";
                `ONFI_ERR_BAD_CONFIRM:      err_name = "BAD_CONFIRM";
                `ONFI_ERR_UNEXPECTED_DATA:  err_name = "UNEXPECTED_DATA";
                `ONFI_ERR_BUSY_ILLEGAL_CMD: err_name = "BUSY_ILLEGAL_CMD";
                `ONFI_ERR_PAGE_OVERFLOW:    err_name = "PAGE_OVERFLOW";
                `ONFI_ERR_PB_NOT_READY:     err_name = "PB_NOT_READY";
                default:                    err_name = "UNKNOWN";
            endcase
        end
    endfunction

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
            $display("=== SCENARIO %0d: %0s ===", scenario_count, name);
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

    task check_eq1;
        input actual;
        input expected;
        input [1023:0] message;
        begin
            if (actual === expected) begin
                $display("[CHECK PASS] %0s actual=%0b expected=%0b",
                         message, actual, expected);
            end else begin
                $display("[CHECK FAIL] %0s actual=%0b expected=%0b",
                         message, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_eq3;
        input [2:0] actual;
        input [2:0] expected;
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

    task check_eq4;
        input [3:0] actual;
        input [3:0] expected;
        input [1023:0] message;
        begin
            if (actual === expected) begin
                $display("[CHECK PASS] %0s actual=%0s expected=%0s",
                         message, op_name(actual), op_name(expected));
            end else begin
                $display("[CHECK FAIL] %0s actual=%0s(0x%0h) expected=%0s(0x%0h)",
                         message, op_name(actual), actual, op_name(expected), expected);
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
            row = block * `NAND_PAGES_PER_BLOCK + page;
            c1 = column[7:0];
            c2 = (column >> 8) & 8'hff;
            r1 = row[7:0];
            r2 = (row >> 8) & 8'hff;
            r3 = (row >> 16) & 8'hff;
            $display("[ADDR] page block=%0d page=%0d column=%0d -> C1=%02x C2=%02x R1=%02x R2=%02x R3=%02x",
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
            row = block * `NAND_PAGES_PER_BLOCK;
            r1 = row[7:0];
            r2 = (row >> 8) & 8'hff;
            r3 = (row >> 16) & 8'hff;
            $display("[ADDR] erase block=%0d -> R1=%02x R2=%02x R3=%02x",
                     block, r1, r2, r3);
        end
    endtask

    task host_write_cycle;
        input [7:0] value;
        begin
            dq_in = value;
            wait_sys_cycles(2);
            we_n = 1'b0;
            wait_sys_cycles(5);
            we_n = 1'b1;
            wait_sys_cycles(7);
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

    task host_read_strobe;
        begin
            $display("[HOST] RE_N toggle (decode_frontend observes edge only; dq output outside scope)");
            cle = 1'b0;
            ale = 1'b0;
            wait_sys_cycles(2);
            re_n = 1'b0;
            wait_sys_cycles(5);
            re_n = 1'b1;
            wait_sys_cycles(7);
        end
    endtask

    task wait_reg_event;
        input [1023:0] label;
        input integer timeout_cycles;
        integer i;
        begin
            $display("[EXPECT] %0s: wait for Register Bank event within %0d cycles",
                     label, timeout_cycles);
            i = 0;
            while (!reg_event_valid && i < timeout_cycles) begin
                wait_sys_cycles(1);
                i = i + 1;
            end
            if (reg_event_valid) begin
                $display("[EVENT] %0s: op=%0s cmd=0x%02x addr={%02x,%02x,%02x,%02x,%02x} addr_count=%0d prog_count=%0d error=%0b/%0s latency=%0d cycles",
                         label, op_name(reg_decoded_op), reg_cmd,
                         reg_addr0, reg_addr1, reg_addr2, reg_addr3, reg_addr4,
                         reg_addr_count, reg_prog_data_count, reg_protocol_error,
                         err_name(reg_protocol_error_code), i);
            end else begin
                $display("[CHECK FAIL] %0s: Register event timeout", label);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task ack_reg_event;
        begin
            $display("[TB] ACK Register event");
            reg_event_ready = 1'b1;
            wait_sys_cycles(2);
            reg_event_ready = 1'b0;
            wait_sys_cycles(3);
        end
    endtask

    task expect_event_common;
        input [1023:0] label;
        input [3:0] expected_op;
        input [7:0] expected_cmd;
        input [2:0] expected_addr_count;
        input [12:0] expected_prog_count;
        input expected_error;
        input [3:0] expected_error_code;
        begin
            check_eq4(reg_decoded_op, expected_op, {label, " op"});
            check_eq8(reg_cmd, expected_cmd, {label, " command"});
            check_eq3(reg_addr_count, expected_addr_count, {label, " address count"});
            check_eq13(reg_prog_data_count, expected_prog_count, {label, " program data count"});
            check_eq1(reg_protocol_error, expected_error, {label, " protocol_error"});
            if (reg_protocol_error_code === expected_error_code) begin
                $display("[CHECK PASS] %0s error_code actual=%0s expected=%0s",
                         label, err_name(reg_protocol_error_code),
                         err_name(expected_error_code));
            end else begin
                $display("[CHECK FAIL] %0s error_code actual=%0s(0x%0h) expected=%0s(0x%0h)",
                         label, err_name(reg_protocol_error_code),
                         reg_protocol_error_code, err_name(expected_error_code),
                         expected_error_code);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task clear_page_buffer_write_path;
        begin
            $display("[TB] Clear Page Buffer write path state");
            pb_clear = 1'b1;
            wait_sys_cycles(1);
            pb_clear = 1'b0;
            wait_sys_cycles(3);
        end
    endtask

    task reset_capture;
        integer i;
        begin
            captured_count = 0;
            for (i = 0; i < CAPTURE_DEPTH; i = i + 1) begin
                captured_pb[i] = 8'h00;
            end
        end
    endtask

    task wait_pb_prog_ready;
        input integer timeout_cycles;
        integer i;
        begin
            $display("[EXPECT] Page Buffer write path freezes after Program confirm");
            i = 0;
            while (!pb_prog_ready && i < timeout_cycles) begin
                wait_sys_cycles(1);
                i = i + 1;
            end
            check_true(pb_prog_ready, "Page Buffer write path program-ready/frozen");
        end
    endtask

    task check_program_payload;
        integer i;
        reg [7:0] expected;
        begin
            check_true(captured_count == PROGRAM_BYTES,
                       "Page Buffer captured all program bytes");
            check_eq13(pb_write_count, PROGRAM_BYTES[12:0],
                       "Page Buffer write path count");
            for (i = 0; i < PROGRAM_BYTES; i = i + 1) begin
                expected = 8'ha0 + i[7:0];
                check_eq8(captured_pb[i], expected,
                          "Program payload byte matched captured PB stream");
            end
        end
    endtask

    initial begin
        sys_clk = 1'b0;
        sys_rst_n = 1'b0;
        dq_in = 8'h00;
        cle = 1'b0;
        ale = 1'b0;
        ce_n = 1'b0;
        we_n = 1'b1;
        re_n = 1'b1;
        host_busy = 1'b0;
        reg_event_ready = 1'b0;
        pb_clear = 1'b0;
        fail_count = 0;
        scenario_count = 0;
        reset_capture();

        $display("=== tb_onfi_sdr_decode_frontend ===");
        $display("[INFO] Scope: host traffic -> Decode FSM -> Host Event Adapter + sys_clk PB write stream");
        $display("[INFO] Out of scope: Register Bank IRQ/W1C, VPL commit, read-output dq data");

        wait_sys_cycles(5);
        sys_rst_n = 1'b1;
        wait_sys_cycles(8);

        make_page_addr(5, 10, 16'h1234, page_c1, page_c2,
                       page_r1, page_r2, page_r3);
        make_erase_addr(5, erase_r1, erase_r2, erase_r3);

        scenario_begin("Reset FFh");
        $display("[EXPECT] Reset command produces OP_RESET event with cmd=FFh and no protocol error");
        host_cmd(8'hFF);
        wait_reg_event("Reset FFh", 100);
        expect_event_common("Reset FFh", `ONFI_OP_RESET, 8'hFF, 3'd0, 13'd0,
                            1'b0, `ONFI_ERR_NONE);
        ack_reg_event();

        scenario_begin("Read ID 90h + addr 00h");
        $display("[EXPECT] Read ID addr 00h produces OP_READ_ID with addr0=00h");
        host_cmd(8'h90);
        host_addr(8'h00);
        wait_sys_cycles(T_WHR_CYCLES);
        host_read_strobe();
        wait_reg_event("Read ID 00h", 140);
        expect_event_common("Read ID 00h", `ONFI_OP_READ_ID, 8'h90, 3'd1, 13'd0,
                            1'b0, `ONFI_ERR_NONE);
        check_eq8(reg_addr0, 8'h00, "Read ID 00h address snapshot");
        ack_reg_event();

        scenario_begin("Read ID 90h + addr 20h");
        $display("[EXPECT] Read ID addr 20h produces OP_READ_ID and selects ONFI signature source");
        host_cmd(8'h90);
        host_addr(8'h20);
        wait_sys_cycles(T_WHR_CYCLES);
        host_read_strobe();
        wait_reg_event("Read ID 20h", 140);
        expect_event_common("Read ID 20h", `ONFI_OP_READ_ID, 8'h90, 3'd1, 13'd0,
                            1'b0, `ONFI_ERR_NONE);
        check_eq8(reg_addr0, 8'h20, "Read ID 20h address snapshot");
        ack_reg_event();

        scenario_begin("Page Program 80h + 5addr + 16 data + 10h");
        $display("[EXPECT] Program stores A0..AF into Page Buffer write path and emits OP_PROGRAM with count=16");
        clear_page_buffer_write_path();
        reset_capture();
        host_cmd(8'h80);
        host_addr(page_c1);
        host_addr(page_c2);
        host_addr(page_r1);
        host_addr(page_r2);
        host_addr(page_r3);
        wait_sys_cycles(T_ADL_CYCLES);
        host_data_in(8'ha0);
        host_data_in(8'ha1);
        host_data_in(8'ha2);
        host_data_in(8'ha3);
        host_data_in(8'ha4);
        host_data_in(8'ha5);
        host_data_in(8'ha6);
        host_data_in(8'ha7);
        host_data_in(8'ha8);
        host_data_in(8'ha9);
        host_data_in(8'haa);
        host_data_in(8'hab);
        host_data_in(8'hac);
        host_data_in(8'had);
        host_data_in(8'hae);
        host_data_in(8'haf);
        host_cmd(8'h10);
        wait_reg_event("Page Program", 220);
        expect_event_common("Page Program", `ONFI_OP_PROGRAM, 8'h10, PAGE_ADDR_CYCLES,
                            PROGRAM_BYTES[12:0], 1'b0, `ONFI_ERR_NONE);
        check_eq8(reg_addr0, page_c1, "Program C1 snapshot");
        check_eq8(reg_addr1, page_c2, "Program C2 snapshot");
        check_eq8(reg_addr2, page_r1, "Program R1 snapshot");
        check_eq8(reg_addr3, page_r2, "Program R2 snapshot");
        check_eq8(reg_addr4, page_r3, "Program R3 snapshot");
        wait_pb_prog_ready(60);
        check_program_payload();
        ack_reg_event();

        scenario_begin("Read Status 70h after Program");
        $display("[EXPECT] Read Status command is decoded even after Program");
        host_cmd(8'h70);
        wait_sys_cycles(T_WHR_CYCLES);
        host_read_strobe();
        wait_reg_event("Read Status after Program", 120);
        expect_event_common("Read Status after Program", `ONFI_OP_READ_STATUS,
                            8'h70, 3'd0, PROGRAM_BYTES[12:0],
                            1'b0, `ONFI_ERR_NONE);
        ack_reg_event();

        scenario_begin("Read Page 00h + 5addr + 30h");
        $display("[EXPECT] Read Page confirm produces OP_READ_PAGE with address snapshot");
        host_cmd(8'h00);
        host_addr(page_c1);
        host_addr(page_c2);
        host_addr(page_r1);
        host_addr(page_r2);
        host_addr(page_r3);
        host_cmd(8'h30);
        wait_sys_cycles(T_RR_CYCLES);
        host_read_strobe();
        wait_reg_event("Read Page after Program", 180);
        expect_event_common("Read Page after Program", `ONFI_OP_READ_PAGE,
                            8'h30, PAGE_ADDR_CYCLES, PROGRAM_BYTES[12:0],
                            1'b0, `ONFI_ERR_NONE);
        check_eq8(reg_addr0, page_c1, "Read Page C1 snapshot");
        check_eq8(reg_addr1, page_c2, "Read Page C2 snapshot");
        check_eq8(reg_addr2, page_r1, "Read Page R1 snapshot");
        check_eq8(reg_addr3, page_r2, "Read Page R2 snapshot");
        check_eq8(reg_addr4, page_r3, "Read Page R3 snapshot");
        ack_reg_event();

        scenario_begin("Block Erase 60h + 3row + D0h");
        $display("[EXPECT] Erase confirm produces OP_ERASE with 3 row address bytes");
        host_cmd(8'h60);
        host_addr(erase_r1);
        host_addr(erase_r2);
        host_addr(erase_r3);
        host_cmd(8'hD0);
        wait_reg_event("Block Erase", 180);
        expect_event_common("Block Erase", `ONFI_OP_ERASE, 8'hD0, ERASE_ADDR_CYCLES,
                            PROGRAM_BYTES[12:0], 1'b0, `ONFI_ERR_NONE);
        check_eq8(reg_addr0, erase_r1, "Erase R1 snapshot");
        check_eq8(reg_addr1, erase_r2, "Erase R2 snapshot");
        check_eq8(reg_addr2, erase_r3, "Erase R3 snapshot");
        ack_reg_event();

        scenario_begin("Read Status 70h after Erase");
        $display("[EXPECT] Read Status remains legal and produces OP_READ_STATUS");
        host_cmd(8'h70);
        wait_sys_cycles(T_WHR_CYCLES);
        host_read_strobe();
        wait_reg_event("Read Status after Erase", 120);
        expect_event_common("Read Status after Erase", `ONFI_OP_READ_STATUS,
                            8'h70, 3'd0, PROGRAM_BYTES[12:0],
                            1'b0, `ONFI_ERR_NONE);
        ack_reg_event();

        scenario_begin("Read Page 00h + 5addr + 30h after Erase");
        $display("[EXPECT] Final Read Page traffic is decoded; erased data compare belongs to VPL/top TB");
        host_cmd(8'h00);
        host_addr(page_c1);
        host_addr(page_c2);
        host_addr(page_r1);
        host_addr(page_r2);
        host_addr(page_r3);
        host_cmd(8'h30);
        wait_sys_cycles(T_RR_CYCLES);
        host_read_strobe();
        wait_reg_event("Read Page after Erase", 180);
        expect_event_common("Read Page after Erase", `ONFI_OP_READ_PAGE,
                            8'h30, PAGE_ADDR_CYCLES, PROGRAM_BYTES[12:0],
                            1'b0, `ONFI_ERR_NONE);
        ack_reg_event();

        scenario_begin("Busy illegal command policy");
        $display("[EXPECT] host_busy=1 rejects normal Read Page command with BUSY_ILLEGAL_CMD");
        host_busy = 1'b1;
        host_cmd(8'h00);
        wait_reg_event("Busy illegal Read Page", 120);
        expect_event_common("Busy illegal Read Page", `ONFI_OP_UNSUPPORTED,
                            8'h00, 3'd0, PROGRAM_BYTES[12:0],
                            1'b1, `ONFI_ERR_BUSY_ILLEGAL_CMD);
        ack_reg_event();
        host_busy = 1'b0;

        wait_sys_cycles(10);
        if (fail_count == 0) begin
            $display("");
            $display("[PASS] tb_onfi_sdr_decode_frontend scenarios=%0d", scenario_count);
        end else begin
            $display("");
            $display("[FAIL] tb_onfi_sdr_decode_frontend fail_count=%0d scenarios=%0d",
                     fail_count, scenario_count);
            $fatal(1, "tb_onfi_sdr_decode_frontend failed");
        end
        $finish;
    end

endmodule

`default_nettype wire
