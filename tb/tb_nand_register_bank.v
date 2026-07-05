`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"
`include "onfi_sdr_defs.vh"

// Purpose: Module-level smoke test for nand_register_bank.
// Role: Simulation-only testbench.
// Related design docs:
// - design_spec/nand_register_bank.md
// - design_spec/nand_control_fw.md
// - design_spec/nand_model_vpl.md
// Block contract: Verifies host event mailbox capture/W1C, FW-visible
// register access, VPL command snapshot generation, VPL result status/IRQ, and
// clear pulse side effects.
// File version: v0.4
// Revision history:
// - v0.4: Verify REG_HOST_EVENT writes are ignored and host
//   event pending/error clear only through REG_IRQ_STATUS.HOST_CMD_IRQ W1C.
// - v0.3: Check accepted Read ID address snapshot output for
//   Read Output Datapath.
// - v0.2: Expect PROGRAM VPL transfer byte count to come from
//   accepted host program data count.
// - v0.1: Initial NAND Register Bank directed smoke test.

module tb_nand_register_bank;

    localparam [31:0] REG_BASE            = 32'h0200_0000;
    localparam [31:0] REG_HOST_CMD        = REG_BASE + 32'h0000_0000;
    localparam [31:0] REG_HOST_ADDR0      = REG_BASE + 32'h0000_0004;
    localparam [31:0] REG_HOST_ADDR1      = REG_BASE + 32'h0000_0008;
    localparam [31:0] REG_HOST_ADDR2      = REG_BASE + 32'h0000_000c;
    localparam [31:0] REG_HOST_ADDR3      = REG_BASE + 32'h0000_0010;
    localparam [31:0] REG_HOST_ADDR4      = REG_BASE + 32'h0000_0014;
    localparam [31:0] REG_HOST_META       = REG_BASE + 32'h0000_0018;
    localparam [31:0] REG_HOST_EVENT      = REG_BASE + 32'h0000_001c;
    localparam [31:0] REG_NAND_STATUS     = REG_BASE + 32'h0000_0020;
    localparam [31:0] REG_IRQ_STATUS      = REG_BASE + 32'h0000_0024;
    localparam [31:0] REG_IRQ_ENABLE      = REG_BASE + 32'h0000_0028;
    localparam [31:0] REG_HOST_DATA_COUNT = REG_BASE + 32'h0000_002c;
    localparam [31:0] REG_BLOCK_SEL       = REG_BASE + 32'h0000_0030;
    localparam [31:0] REG_PAGE_SEL        = REG_BASE + 32'h0000_0034;
    localparam [31:0] REG_COL_SEL         = REG_BASE + 32'h0000_0038;
    localparam [31:0] REG_PAGE_BYTES      = REG_BASE + 32'h0000_003c;
    localparam [31:0] REG_OP_CTRL         = REG_BASE + 32'h0000_0040;
    localparam [31:0] REG_OP_TRIGGER      = REG_BASE + 32'h0000_0044;
    localparam [31:0] REG_OP_STATUS       = REG_BASE + 32'h0000_0048;
    localparam [31:0] REG_OP_STATUS_CLR   = REG_BASE + 32'h0000_004c;
    localparam [31:0] REG_OP_ERROR        = REG_BASE + 32'h0000_0050;
    localparam [31:0] REG_OP_LATENCY      = REG_BASE + 32'h0000_0054;
    localparam [31:0] REG_READOUT_CTRL    = REG_BASE + 32'h0000_0058;
    localparam [31:0] REG_VREAD_LEVEL     = REG_BASE + 32'h0000_0060;
    localparam [31:0] REG_VPGM_LEVEL      = REG_BASE + 32'h0000_0064;
    localparam [31:0] REG_VPASS_LEVEL     = REG_BASE + 32'h0000_0068;
    localparam [31:0] REG_VERS_LEVEL      = REG_BASE + 32'h0000_006c;
    localparam [31:0] REG_BL_CTRL         = REG_BASE + 32'h0000_0070;
    localparam [31:0] REG_WL_CTRL         = REG_BASE + 32'h0000_0074;
    localparam [31:0] REG_LINE_CTRL       = REG_BASE + 32'h0000_0078;
    localparam [31:0] REG_BIAS_PROFILE    = REG_BASE + 32'h0000_007c;

    reg clk;
    reg resetn;

    reg        cpu_valid;
    reg [31:0] cpu_addr;
    reg [31:0] cpu_wdata;
    reg [3:0]  cpu_wstrb;
    wire [31:0] cpu_rdata;
    wire       cpu_ready;

    reg        reg_event_valid;
    wire       reg_event_ready;
    reg [3:0]  reg_decoded_op;
    reg [7:0]  reg_cmd;
    reg [7:0]  reg_addr0;
    reg [7:0]  reg_addr1;
    reg [7:0]  reg_addr2;
    reg [7:0]  reg_addr3;
    reg [7:0]  reg_addr4;
    reg [2:0]  reg_addr_count;
    reg [12:0] reg_prog_data_count;
    reg        reg_protocol_error;
    reg [3:0]  reg_protocol_error_code;

    reg        wp_n;
    reg        pb_prog_ready;
    reg        pb_overflow;
    wire       pb_prog_clear;

    wire        vpl_cmd_valid;
    reg         vpl_cmd_ready;
    wire [31:0] vpl_cmd_block;
    wire [31:0] vpl_cmd_page;
    wire [31:0] vpl_cmd_col;
    wire [31:0] vpl_cmd_page_bytes;
    wire [31:0] vpl_cmd_op_ctrl;
    wire [31:0] vpl_cmd_latency;
    wire [7:0]  vpl_cmd_vread_level;
    wire [7:0]  vpl_cmd_vpgm_level;
    wire [7:0]  vpl_cmd_vpass_level;
    wire [7:0]  vpl_cmd_vers_level;
    wire [2:0]  vpl_cmd_bl_ctrl;
    wire [8:0]  vpl_cmd_wl_ctrl;
    wire [6:0]  vpl_cmd_line_ctrl;
    wire [1:0]  vpl_cmd_bias_profile;

    reg        vpl_rsp_valid;
    wire       vpl_rsp_ready;
    reg        vpl_rsp_done;
    reg        vpl_rsp_error;
    reg [7:0]  vpl_rsp_error_code;
    reg        vpl_rsp_fail;
    reg        vpl_rsp_pb_valid;

    wire [7:0] nand_status;
    wire [5:0] op_status;
    wire [7:0] op_error;
    wire [7:0] readout_ctrl;
    wire [7:0] readout_id_addr;
    wire       readout_ptr_reset_pulse;
    wire       host_event_pending;
    wire [2:0] irq_status;
    wire [2:0] irq_enable;
    wire       irq;
    wire       reg_busy;
    wire       reg_ready;
    wire       access_error;

    integer fail_count;
    reg [31:0] read_value;

    nand_register_bank #(
        .REG_BASE(REG_BASE)
    ) dut (
        .core_clk(clk),
        .core_rst_n(resetn),
        .cpu_valid_i(cpu_valid),
        .cpu_addr_i(cpu_addr),
        .cpu_wdata_i(cpu_wdata),
        .cpu_wstrb_i(cpu_wstrb),
        .cpu_rdata_o(cpu_rdata),
        .cpu_ready_o(cpu_ready),
        .reg_event_valid_i(reg_event_valid),
        .reg_event_ready_o(reg_event_ready),
        .reg_decoded_op_i(reg_decoded_op),
        .reg_cmd_i(reg_cmd),
        .reg_addr0_i(reg_addr0),
        .reg_addr1_i(reg_addr1),
        .reg_addr2_i(reg_addr2),
        .reg_addr3_i(reg_addr3),
        .reg_addr4_i(reg_addr4),
        .reg_addr_count_i(reg_addr_count),
        .reg_prog_data_count_i(reg_prog_data_count),
        .reg_protocol_error_i(reg_protocol_error),
        .reg_protocol_error_code_i(reg_protocol_error_code),
        .wp_n_i(wp_n),
        .pb_prog_ready_i(pb_prog_ready),
        .pb_overflow_i(pb_overflow),
        .pb_prog_clear_o(pb_prog_clear),
        .vpl_cmd_valid_o(vpl_cmd_valid),
        .vpl_cmd_ready_i(vpl_cmd_ready),
        .vpl_cmd_block_o(vpl_cmd_block),
        .vpl_cmd_page_o(vpl_cmd_page),
        .vpl_cmd_col_o(vpl_cmd_col),
        .vpl_cmd_page_bytes_o(vpl_cmd_page_bytes),
        .vpl_cmd_op_ctrl_o(vpl_cmd_op_ctrl),
        .vpl_cmd_latency_o(vpl_cmd_latency),
        .vpl_cmd_vread_level_o(vpl_cmd_vread_level),
        .vpl_cmd_vpgm_level_o(vpl_cmd_vpgm_level),
        .vpl_cmd_vpass_level_o(vpl_cmd_vpass_level),
        .vpl_cmd_vers_level_o(vpl_cmd_vers_level),
        .vpl_cmd_bl_ctrl_o(vpl_cmd_bl_ctrl),
        .vpl_cmd_wl_ctrl_o(vpl_cmd_wl_ctrl),
        .vpl_cmd_line_ctrl_o(vpl_cmd_line_ctrl),
        .vpl_cmd_bias_profile_o(vpl_cmd_bias_profile),
        .vpl_rsp_valid_i(vpl_rsp_valid),
        .vpl_rsp_ready_o(vpl_rsp_ready),
        .vpl_rsp_done_i(vpl_rsp_done),
        .vpl_rsp_error_i(vpl_rsp_error),
        .vpl_rsp_error_code_i(vpl_rsp_error_code),
        .vpl_rsp_fail_i(vpl_rsp_fail),
        .vpl_rsp_pb_valid_i(vpl_rsp_pb_valid),
        .nand_status_o(nand_status),
        .op_status_o(op_status),
        .op_error_o(op_error),
        .readout_ctrl_o(readout_ctrl),
        .readout_id_addr_o(readout_id_addr),
        .readout_ptr_reset_pulse_o(readout_ptr_reset_pulse),
        .host_event_pending_o(host_event_pending),
        .irq_status_o(irq_status),
        .irq_enable_o(irq_enable),
        .irq_o(irq),
        .reg_busy_o(reg_busy),
        .reg_ready_o(reg_ready),
        .access_error_o(access_error)
    );

    always #5 clk = ~clk;

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
        input [1023:0] message;
        begin
            if (!condition) begin
                $display("[FAIL] %0s", message);
                fail_count = fail_count + 1;
            end else begin
                $display("[PASS] %0s", message);
            end
        end
    endtask

    task check_eq32;
        input [31:0] actual;
        input [31:0] expected;
        input [1023:0] message;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=0x%08x expected=0x%08x",
                         message, actual, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("[PASS] %0s actual=0x%08x", message, actual);
            end
        end
    endtask

    task cpu_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            cpu_addr = addr;
            cpu_wdata = data;
            cpu_wstrb = 4'b1111;
            cpu_valid = 1'b1;
            @(negedge clk);
            cpu_valid = 1'b0;
            cpu_wstrb = 4'b0000;
            cpu_addr = 32'h0000_0000;
            cpu_wdata = 32'h0000_0000;
        end
    endtask

    task cpu_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);
            cpu_addr = addr;
            cpu_wdata = 32'h0000_0000;
            cpu_wstrb = 4'b0000;
            cpu_valid = 1'b1;
            #1;
            data = cpu_rdata;
            @(negedge clk);
            cpu_valid = 1'b0;
            cpu_addr = 32'h0000_0000;
        end
    endtask

    task launch_host_event;
        input [3:0]  op;
        input [7:0]  cmd;
        input [7:0]  addr0;
        input [7:0]  addr1;
        input [7:0]  addr2;
        input [7:0]  addr3;
        input [7:0]  addr4;
        input [2:0]  addr_count;
        input [12:0] data_count;
        input        protocol_error;
        input [3:0]  protocol_error_code;
        begin
            @(negedge clk);
            reg_decoded_op = op;
            reg_cmd = cmd;
            reg_addr0 = addr0;
            reg_addr1 = addr1;
            reg_addr2 = addr2;
            reg_addr3 = addr3;
            reg_addr4 = addr4;
            reg_addr_count = addr_count;
            reg_prog_data_count = data_count;
            reg_protocol_error = protocol_error;
            reg_protocol_error_code = protocol_error_code;
            reg_event_valid = 1'b1;
            @(negedge clk);
            reg_event_valid = 1'b0;
            reg_protocol_error = 1'b0;
            reg_protocol_error_code = `ONFI_ERR_NONE;
            wait_clk(1);
        end
    endtask

    task send_vpl_response;
        input done;
        input error;
        input [7:0] error_code;
        input fail;
        input pb_valid;
        begin
            @(negedge clk);
            vpl_rsp_done = done;
            vpl_rsp_error = error;
            vpl_rsp_error_code = error_code;
            vpl_rsp_fail = fail;
            vpl_rsp_pb_valid = pb_valid;
            vpl_rsp_valid = 1'b1;
            @(negedge clk);
            vpl_rsp_valid = 1'b0;
            vpl_rsp_done = 1'b0;
            vpl_rsp_error = 1'b0;
            vpl_rsp_error_code = 8'h00;
            vpl_rsp_fail = 1'b0;
            vpl_rsp_pb_valid = 1'b0;
            wait_clk(1);
        end
    endtask

    initial begin
        clk = 1'b0;
        resetn = 1'b0;
        cpu_valid = 1'b0;
        cpu_addr = 32'h0000_0000;
        cpu_wdata = 32'h0000_0000;
        cpu_wstrb = 4'b0000;
        reg_event_valid = 1'b0;
        reg_decoded_op = `ONFI_OP_NONE;
        reg_cmd = 8'h00;
        reg_addr0 = 8'h00;
        reg_addr1 = 8'h00;
        reg_addr2 = 8'h00;
        reg_addr3 = 8'h00;
        reg_addr4 = 8'h00;
        reg_addr_count = 3'd0;
        reg_prog_data_count = 13'd0;
        reg_protocol_error = 1'b0;
        reg_protocol_error_code = `ONFI_ERR_NONE;
        wp_n = 1'b1;
        pb_prog_ready = 1'b0;
        pb_overflow = 1'b0;
        vpl_cmd_ready = 1'b0;
        vpl_rsp_valid = 1'b0;
        vpl_rsp_done = 1'b0;
        vpl_rsp_error = 1'b0;
        vpl_rsp_error_code = 8'h00;
        vpl_rsp_fail = 1'b0;
        vpl_rsp_pb_valid = 1'b0;
        fail_count = 0;

        wait_clk(4);
        resetn = 1'b1;
        wait_clk(2);

        $display("[SCENARIO] Reset/default register state");
        cpu_read(REG_NAND_STATUS, read_value);
        check_eq32(read_value, 32'h0000_00c0, "NAND status reset ready/wp_n");
        cpu_read(REG_IRQ_STATUS, read_value);
        check_eq32(read_value, 32'h0000_0000, "IRQ status reset");
        check_true(reg_event_ready, "Host event ready after reset");

        $display("[SCENARIO] Host event mailbox capture and W1C clear");
        cpu_write(REG_IRQ_ENABLE, 32'h0000_0007);
        launch_host_event(`ONFI_OP_PROGRAM, 8'h10, 8'h34, 8'h12, 8'h56, 8'h78,
                          8'h9a, 3'd5, 13'd16, 1'b0, `ONFI_ERR_NONE);

        check_eq32({29'h00000000, irq_status}, 32'h0000_0001,
                   "Host event sets HOST_CMD_IRQ");
        check_true(irq, "IRQ output asserted after host event");
        check_true(!reg_event_ready, "Host event backpressure while pending");

        cpu_read(REG_HOST_CMD, read_value);
        check_eq32(read_value, 32'h0000_0010, "Host command mailbox");
        cpu_read(REG_HOST_ADDR0, read_value);
        check_eq32(read_value, 32'h0000_0034, "Host addr0 mailbox");
        cpu_read(REG_HOST_ADDR1, read_value);
        check_eq32(read_value, 32'h0000_0012, "Host addr1 mailbox");
        cpu_read(REG_HOST_ADDR2, read_value);
        check_eq32(read_value, 32'h0000_0056, "Host addr2 mailbox");
        cpu_read(REG_HOST_ADDR3, read_value);
        check_eq32(read_value, 32'h0000_0078, "Host addr3 mailbox");
        cpu_read(REG_HOST_ADDR4, read_value);
        check_eq32(read_value, 32'h0000_009a, "Host addr4 mailbox");
        cpu_read(REG_HOST_META, read_value);
        check_eq32(read_value, 32'h0000_0055, "Host meta decoded_op/addr_count");
        cpu_read(REG_HOST_DATA_COUNT, read_value);
        check_eq32(read_value, 32'h0000_0010, "Host program data count");
        cpu_read(REG_HOST_EVENT, read_value);
        check_eq32(read_value, 32'h0000_0001, "Host event pending bit");

        cpu_write(REG_HOST_EVENT, 32'h0000_0001);
        wait_clk(1);
        check_eq32({29'h00000000, irq_status}, 32'h0000_0001,
                   "REG_HOST_EVENT write is ignored");
        check_true(!reg_event_ready, "Host event remains backpressured after REG_HOST_EVENT write");

        cpu_write(REG_IRQ_STATUS, 32'h0000_0001);
        wait_clk(1);
        check_eq32({29'h00000000, irq_status}, 32'h0000_0000,
                   "IRQ_STATUS W1C clears HOST_CMD_IRQ");
        check_true(reg_event_ready, "Host event ready reopens after W1C");

        launch_host_event(`ONFI_OP_UNSUPPORTED, 8'hee, 8'h00, 8'h00, 8'h00,
                          8'h00, 8'h00, 3'd0, 13'd0, 1'b1,
                          `ONFI_ERR_UNSUPPORTED_CMD);
        cpu_read(REG_HOST_EVENT, read_value);
        check_eq32(read_value, 32'h0000_0003, "Protocol error event pending/error bits");
        cpu_write(REG_HOST_EVENT, 32'h0000_0003);
        wait_clk(1);
        cpu_read(REG_HOST_EVENT, read_value);
        check_eq32(read_value, 32'h0000_0003, "Protocol error view survives REG_HOST_EVENT write");
        cpu_write(REG_IRQ_STATUS, 32'h0000_0001);
        wait_clk(1);
        cpu_read(REG_HOST_EVENT, read_value);
        check_eq32(read_value, 32'h0000_0000, "IRQ_STATUS W1C clears protocol error view");

        launch_host_event(`ONFI_OP_READ_ID, 8'h90, 8'h20, 8'h00, 8'h00,
                          8'h00, 8'h00, 3'd1, 13'd0, 1'b0,
                          `ONFI_ERR_NONE);
        check_eq32({24'h000000, readout_id_addr}, 32'h0000_0020,
                   "Readout ID address snapshot updates on Read ID event");
        cpu_write(REG_IRQ_STATUS, 32'h0000_0001);
        wait_clk(1);

        $display("[SCENARIO] FW writes VPL command registers and starts operation");
        cpu_write(REG_BLOCK_SEL, 32'h0000_0003);
        cpu_write(REG_PAGE_SEL, 32'h0000_0012);
        cpu_write(REG_COL_SEL, 32'h0000_0040);
        cpu_write(REG_OP_CTRL, 32'h0003_0002);
        cpu_write(REG_OP_LATENCY, 32'h0000_007b);
        cpu_write(REG_VREAD_LEVEL, 32'h0000_0005);
        cpu_write(REG_VPGM_LEVEL, 32'h0000_0010);
        cpu_write(REG_VPASS_LEVEL, 32'h0000_000a);
        cpu_write(REG_VERS_LEVEL, 32'h0000_0014);
        cpu_write(REG_BL_CTRL, 32'h0000_0004);
        cpu_write(REG_WL_CTRL, 32'h0000_0112);
        cpu_write(REG_LINE_CTRL, 32'h0000_0017);
        cpu_write(REG_BIAS_PROFILE, 32'h0000_0002);
        cpu_write(REG_READOUT_CTRL, 32'h0000_0007);
        cpu_read(REG_READOUT_CTRL, read_value);
        check_eq32(read_value, 32'h0000_0007, "Readout control stores source/enable");
        cpu_write(REG_READOUT_CTRL, 32'h0000_000f);
        check_true(readout_ptr_reset_pulse, "Readout pointer reset pulse");

        vpl_cmd_ready = 1'b0;
        cpu_write(REG_OP_TRIGGER, 32'h0000_0001);
        wait_clk(1);
        check_true(vpl_cmd_valid, "VPL command valid after START");
        check_eq32(vpl_cmd_block, 32'h0000_0003, "VPL snapshot block");
        check_eq32(vpl_cmd_page, 32'h0000_0012, "VPL snapshot page");
        check_eq32(vpl_cmd_col, 32'h0000_0040, "VPL snapshot column");
        check_eq32(vpl_cmd_page_bytes, 32'h0000_0010,
                   "VPL snapshot program byte count");
        check_eq32(vpl_cmd_op_ctrl, 32'h0003_0002, "VPL snapshot op control");
        check_eq32(vpl_cmd_latency, 32'h0000_007b, "VPL snapshot latency");
        check_eq32({24'h000000, vpl_cmd_vpgm_level}, 32'h0000_0010,
                   "VPL snapshot program level");
        check_eq32({29'h00000000, vpl_cmd_bl_ctrl}, 32'h0000_0004,
                   "VPL snapshot BL control");
        check_true(!reg_event_ready, "Host event blocked during VPL operation");

        cpu_read(REG_OP_STATUS, read_value);
        check_eq32(read_value[5:0], 32'h0000_0001, "OP_STATUS busy after START");
        cpu_read(REG_NAND_STATUS, read_value);
        check_eq32(read_value, 32'h0000_0080, "NAND status busy clears ready");

        vpl_cmd_ready = 1'b1;
        wait_clk(2);
        check_true(!vpl_cmd_valid, "VPL command valid clears after ready");
        vpl_cmd_ready = 1'b0;

        $display("[SCENARIO] VPL done response updates status and IRQ");
        send_vpl_response(1'b1, 1'b0, 8'h00, 1'b0, 1'b1);
        cpu_read(REG_OP_STATUS, read_value);
        check_eq32(read_value[5:0], 32'h0000_000a, "OP_STATUS done and PB valid");
        cpu_read(REG_NAND_STATUS, read_value);
        check_eq32(read_value, 32'h0000_00c0, "NAND status ready/pass after VPL done");
        cpu_read(REG_IRQ_STATUS, read_value);
        check_eq32(read_value, 32'h0000_0002, "VPL done sets OP_DONE_IRQ");

        cpu_write(REG_IRQ_STATUS, 32'h0000_0002);
        wait_clk(1);
        check_true(!reg_event_ready, "OP_STATUS done holds host event backpressure");
        cpu_write(REG_OP_STATUS_CLR, 32'h0000_0005);
        wait_clk(1);
        cpu_read(REG_OP_STATUS, read_value);
        check_eq32(read_value[5:0], 32'h0000_0000, "OP_STATUS done/PB valid clear");
        check_true(reg_event_ready, "Host event ready reopens after OP_STATUS clear");

        $display("[SCENARIO] Busy START creates error status and OP_ERROR_IRQ");
        cpu_write(REG_OP_CTRL, 32'h0002_0001);
        cpu_write(REG_OP_TRIGGER, 32'h0000_0001);
        wait_clk(1);
        cpu_write(REG_OP_TRIGGER, 32'h0000_0001);
        wait_clk(1);
        cpu_read(REG_OP_STATUS, read_value);
        check_eq32(read_value[5:0], 32'h0000_0005, "Busy START leaves busy/error status");
        cpu_read(REG_OP_ERROR, read_value);
        check_eq32(read_value, 32'h0000_0002, "Busy START error code");
        cpu_read(REG_IRQ_STATUS, read_value);
        check_eq32(read_value, 32'h0000_0004, "Busy START sets OP_ERROR_IRQ");

        cpu_write(REG_IRQ_STATUS, 32'h0000_0004);
        cpu_write(REG_OP_STATUS_CLR, 32'h0000_000a);
        check_true(pb_prog_clear, "PB_PROG_CLEAR pulse");

        if (fail_count == 0) begin
            $display("PASS: nand_register_bank smoke test");
        end else begin
            $display("FAIL: nand_register_bank smoke test fail_count=%0d", fail_count);
            $fatal;
        end

        $finish;
    end

endmodule

`default_nettype wire
