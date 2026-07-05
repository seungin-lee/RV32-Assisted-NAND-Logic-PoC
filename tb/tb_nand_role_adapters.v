`timescale 1ns/1ps
`default_nettype none

`include "onfi_sdr_defs.vh"

// Purpose: Directed smoke test for reusable NAND role adapters.
// Role: Simulation-only testbench.
// Related design docs:
// - design_spec/nand_adapter_contracts.md
// - design_spec/Architecture.md
// Block contract: Checks Host Event CDC, Page Buffer control/status CDC, VPL
// command/response CDC, Host Pin Status CDC, and Read Output mirror snapshot
// behavior.
// File version: v0.5
// Revision history:
// - v0.5: Check Host Event Adapter busy mirror and Host Pin
//   Status Adapter WP_N mirror.
// - v0.4: Check Read Output ID address snapshot mirror.
// - v0.3: Keep Page Buffer bulk write coverage in
//   tb_nand_page_buffer and limit this TB to control/status CDC.
// - v0.2: Add Host Event CDC coverage after absorbing the old
//   Decode Adapter role into nand_role_adapters.v.
// - v0.1: Initial role adapter smoke test.

module tb_nand_role_adapters;

    localparam integer SYS_CLK_HALF_NS  = 5;
    localparam integer CORE_CLK_HALF_NS = 7;

    reg sys_clk;
    reg sys_rst_n;
    reg core_clk;
    reg core_rst_n;

    reg        host_decode_event_valid;
    wire       host_decode_event_ready;
    reg  [3:0] host_decoded_op;
    reg  [7:0] host_cmd;
    reg  [7:0] host_addr0;
    reg  [7:0] host_addr1;
    reg  [7:0] host_addr2;
    reg  [7:0] host_addr3;
    reg  [7:0] host_addr4;
    reg  [2:0] host_addr_count;
    reg [12:0] host_prog_data_count;
    reg        host_protocol_error;
    reg  [3:0] host_protocol_error_code;
    wire       host_reg_event_valid;
    reg        host_reg_event_ready;
    reg        host_reg_busy;
    wire [3:0] host_reg_decoded_op;
    wire [7:0] host_reg_cmd;
    wire [7:0] host_reg_addr0;
    wire [7:0] host_reg_addr1;
    wire [7:0] host_reg_addr2;
    wire [7:0] host_reg_addr3;
    wire [7:0] host_reg_addr4;
    wire [2:0] host_reg_addr_count;
    wire [12:0] host_reg_prog_data_count;
    wire       host_reg_protocol_error;
    wire [3:0] host_reg_protocol_error_code;
    wire       host_busy;
    wire       host_adapter_busy;

    reg        host_wp_n;
    wire       core_wp_n;

    reg  core_pb_clear_pulse;
    wire core_pb_clear_busy;
    wire core_pb_prog_ready;
    wire core_pb_overflow;
    wire sys_pb_clear_pulse;
    reg  sys_pb_prog_ready;
    reg  sys_pb_overflow;

    reg         core_cmd_valid;
    wire        core_cmd_ready;
    reg  [31:0] core_cmd_block;
    reg  [31:0] core_cmd_page;
    reg  [31:0] core_cmd_col;
    reg  [31:0] core_cmd_page_bytes;
    reg  [31:0] core_cmd_op_ctrl;
    reg  [31:0] core_cmd_latency;
    reg  [7:0]  core_cmd_vread_level;
    reg  [7:0]  core_cmd_vpgm_level;
    reg  [7:0]  core_cmd_vpass_level;
    reg  [7:0]  core_cmd_vers_level;
    reg  [2:0]  core_cmd_bl_ctrl;
    reg  [8:0]  core_cmd_wl_ctrl;
    reg  [6:0]  core_cmd_line_ctrl;
    reg  [1:0]  core_cmd_bias_profile;
    wire        core_rsp_valid;
    reg         core_rsp_ready;
    wire        core_rsp_done;
    wire        core_rsp_error;
    wire [7:0]  core_rsp_error_code;
    wire        core_rsp_fail;
    wire        core_rsp_pb_valid;

    wire        sys_cmd_valid;
    reg         sys_cmd_ready;
    wire [31:0] sys_cmd_block;
    wire [31:0] sys_cmd_page;
    wire [31:0] sys_cmd_col;
    wire [31:0] sys_cmd_page_bytes;
    wire [31:0] sys_cmd_op_ctrl;
    wire [31:0] sys_cmd_latency;
    wire [7:0]  sys_cmd_vread_level;
    wire [7:0]  sys_cmd_vpgm_level;
    wire [7:0]  sys_cmd_vpass_level;
    wire [7:0]  sys_cmd_vers_level;
    wire [2:0]  sys_cmd_bl_ctrl;
    wire [8:0]  sys_cmd_wl_ctrl;
    wire [6:0]  sys_cmd_line_ctrl;
    wire [1:0]  sys_cmd_bias_profile;
    reg         sys_rsp_valid;
    wire        sys_rsp_ready;
    reg         sys_rsp_done;
    reg         sys_rsp_error;
    reg  [7:0]  sys_rsp_error_code;
    reg         sys_rsp_fail;
    reg         sys_rsp_pb_valid;

    reg  [7:0] core_readout_ctrl;
    reg  [7:0] core_readout_id_addr;
    reg  [7:0] core_nand_status;
    reg        core_ptr_reset_pulse;
    wire [7:0] sys_readout_ctrl;
    wire [7:0] sys_readout_id_addr;
    wire [7:0] sys_nand_status;
    wire       sys_ptr_reset_pulse;

    integer fail_count;
    integer sys_pb_clear_count;
    integer sys_ptr_reset_count;

    nand_host_event_adapter u_host_event_adapter (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .decode_event_valid_i(host_decode_event_valid),
        .decode_event_ready_o(host_decode_event_ready),
        .decoded_op_i(host_decoded_op),
        .cmd_i(host_cmd),
        .addr0_i(host_addr0),
        .addr1_i(host_addr1),
        .addr2_i(host_addr2),
        .addr3_i(host_addr3),
        .addr4_i(host_addr4),
        .addr_count_i(host_addr_count),
        .prog_data_count_i(host_prog_data_count),
        .protocol_error_i(host_protocol_error),
        .protocol_error_code_i(host_protocol_error_code),
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .reg_busy_i(host_reg_busy),
        .reg_event_valid_o(host_reg_event_valid),
        .reg_event_ready_i(host_reg_event_ready),
        .reg_decoded_op_o(host_reg_decoded_op),
        .reg_cmd_o(host_reg_cmd),
        .reg_addr0_o(host_reg_addr0),
        .reg_addr1_o(host_reg_addr1),
        .reg_addr2_o(host_reg_addr2),
        .reg_addr3_o(host_reg_addr3),
        .reg_addr4_o(host_reg_addr4),
        .reg_addr_count_o(host_reg_addr_count),
        .reg_prog_data_count_o(host_reg_prog_data_count),
        .reg_protocol_error_o(host_reg_protocol_error),
        .reg_protocol_error_code_o(host_reg_protocol_error_code),
        .host_busy_o(host_busy),
        .adapter_busy_o(host_adapter_busy)
    );

    nand_host_pin_status_adapter u_host_pin_status_adapter (
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .wp_n_i(host_wp_n),
        .core_wp_n_o(core_wp_n)
    );

    nand_page_buffer_adapter u_page_buffer_adapter (
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .core_pb_clear_pulse_i(core_pb_clear_pulse),
        .core_pb_clear_busy_o(core_pb_clear_busy),
        .core_pb_prog_ready_o(core_pb_prog_ready),
        .core_pb_overflow_o(core_pb_overflow),
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .sys_pb_clear_pulse_o(sys_pb_clear_pulse),
        .sys_pb_prog_ready_i(sys_pb_prog_ready),
        .sys_pb_overflow_i(sys_pb_overflow)
    );

    nand_vpl_command_response_adapter u_vpl_adapter (
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .core_cmd_valid_i(core_cmd_valid),
        .core_cmd_ready_o(core_cmd_ready),
        .core_cmd_block_i(core_cmd_block),
        .core_cmd_page_i(core_cmd_page),
        .core_cmd_col_i(core_cmd_col),
        .core_cmd_page_bytes_i(core_cmd_page_bytes),
        .core_cmd_op_ctrl_i(core_cmd_op_ctrl),
        .core_cmd_latency_i(core_cmd_latency),
        .core_cmd_vread_level_i(core_cmd_vread_level),
        .core_cmd_vpgm_level_i(core_cmd_vpgm_level),
        .core_cmd_vpass_level_i(core_cmd_vpass_level),
        .core_cmd_vers_level_i(core_cmd_vers_level),
        .core_cmd_bl_ctrl_i(core_cmd_bl_ctrl),
        .core_cmd_wl_ctrl_i(core_cmd_wl_ctrl),
        .core_cmd_line_ctrl_i(core_cmd_line_ctrl),
        .core_cmd_bias_profile_i(core_cmd_bias_profile),
        .core_rsp_valid_o(core_rsp_valid),
        .core_rsp_ready_i(core_rsp_ready),
        .core_rsp_done_o(core_rsp_done),
        .core_rsp_error_o(core_rsp_error),
        .core_rsp_error_code_o(core_rsp_error_code),
        .core_rsp_fail_o(core_rsp_fail),
        .core_rsp_pb_valid_o(core_rsp_pb_valid),
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .sys_cmd_valid_o(sys_cmd_valid),
        .sys_cmd_ready_i(sys_cmd_ready),
        .sys_cmd_block_o(sys_cmd_block),
        .sys_cmd_page_o(sys_cmd_page),
        .sys_cmd_col_o(sys_cmd_col),
        .sys_cmd_page_bytes_o(sys_cmd_page_bytes),
        .sys_cmd_op_ctrl_o(sys_cmd_op_ctrl),
        .sys_cmd_latency_o(sys_cmd_latency),
        .sys_cmd_vread_level_o(sys_cmd_vread_level),
        .sys_cmd_vpgm_level_o(sys_cmd_vpgm_level),
        .sys_cmd_vpass_level_o(sys_cmd_vpass_level),
        .sys_cmd_vers_level_o(sys_cmd_vers_level),
        .sys_cmd_bl_ctrl_o(sys_cmd_bl_ctrl),
        .sys_cmd_wl_ctrl_o(sys_cmd_wl_ctrl),
        .sys_cmd_line_ctrl_o(sys_cmd_line_ctrl),
        .sys_cmd_bias_profile_o(sys_cmd_bias_profile),
        .sys_rsp_valid_i(sys_rsp_valid),
        .sys_rsp_ready_o(sys_rsp_ready),
        .sys_rsp_done_i(sys_rsp_done),
        .sys_rsp_error_i(sys_rsp_error),
        .sys_rsp_error_code_i(sys_rsp_error_code),
        .sys_rsp_fail_i(sys_rsp_fail),
        .sys_rsp_pb_valid_i(sys_rsp_pb_valid)
    );

    nand_read_output_mirror_adapter u_read_output_mirror_adapter (
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .core_readout_ctrl_i(core_readout_ctrl),
        .core_readout_id_addr_i(core_readout_id_addr),
        .core_nand_status_i(core_nand_status),
        .core_ptr_reset_pulse_i(core_ptr_reset_pulse),
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .sys_readout_ctrl_o(sys_readout_ctrl),
        .sys_readout_id_addr_o(sys_readout_id_addr),
        .sys_nand_status_o(sys_nand_status),
        .sys_ptr_reset_pulse_o(sys_ptr_reset_pulse)
    );

    always #SYS_CLK_HALF_NS sys_clk = ~sys_clk;
    always #CORE_CLK_HALF_NS core_clk = ~core_clk;

    always @(posedge sys_clk) begin
        if (sys_pb_clear_pulse) begin
            sys_pb_clear_count <= sys_pb_clear_count + 1;
        end
        if (sys_ptr_reset_pulse) begin
            sys_ptr_reset_count <= sys_ptr_reset_count + 1;
        end
    end

    task wait_sys_clk;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge sys_clk);
            end
        end
    endtask

    task wait_core_clk;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge core_clk);
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

    task check_eq32;
        input [31:0] actual;
        input [31:0] expected;
        input [255:0] message;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=0x%08x expected=0x%08x",
                         message, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task wait_sys_cmd_valid;
        input integer timeout;
        integer i;
        begin
            i = 0;
            while (!sys_cmd_valid && i < timeout) begin
                wait_sys_clk(1);
                i = i + 1;
            end
            check_true(sys_cmd_valid, "VPL command CDC timeout");
        end
    endtask

    task wait_core_rsp_valid;
        input integer timeout;
        integer i;
        begin
            i = 0;
            while (!core_rsp_valid && i < timeout) begin
                wait_core_clk(1);
                i = i + 1;
            end
            check_true(core_rsp_valid, "VPL response CDC timeout");
        end
    endtask

    task wait_host_reg_event_valid;
        input integer timeout;
        integer i;
        begin
            i = 0;
            while (!host_reg_event_valid && i < timeout) begin
                wait_core_clk(1);
                i = i + 1;
            end
            check_true(host_reg_event_valid, "Host Event CDC timeout");
        end
    endtask

    initial begin
        sys_clk = 1'b0;
        core_clk = 1'b0;
        sys_rst_n = 1'b0;
        core_rst_n = 1'b0;
        host_decode_event_valid = 1'b0;
        host_decoded_op = `ONFI_OP_NONE;
        host_cmd = 8'h00;
        host_addr0 = 8'h00;
        host_addr1 = 8'h00;
        host_addr2 = 8'h00;
        host_addr3 = 8'h00;
        host_addr4 = 8'h00;
        host_addr_count = 3'd0;
        host_prog_data_count = 13'd0;
        host_protocol_error = 1'b0;
        host_protocol_error_code = `ONFI_ERR_NONE;
        host_reg_event_ready = 1'b0;
        host_reg_busy = 1'b0;
        host_wp_n = 1'b1;
        core_pb_clear_pulse = 1'b0;
        sys_pb_prog_ready = 1'b0;
        sys_pb_overflow = 1'b0;
        core_cmd_valid = 1'b0;
        core_cmd_block = 32'h0000_0000;
        core_cmd_page = 32'h0000_0000;
        core_cmd_col = 32'h0000_0000;
        core_cmd_page_bytes = 32'h0000_0000;
        core_cmd_op_ctrl = 32'h0000_0000;
        core_cmd_latency = 32'h0000_0000;
        core_cmd_vread_level = 8'h00;
        core_cmd_vpgm_level = 8'h00;
        core_cmd_vpass_level = 8'h00;
        core_cmd_vers_level = 8'h00;
        core_cmd_bl_ctrl = 3'b000;
        core_cmd_wl_ctrl = 9'h000;
        core_cmd_line_ctrl = 7'h00;
        core_cmd_bias_profile = 2'b00;
        core_rsp_ready = 1'b0;
        sys_cmd_ready = 1'b0;
        sys_rsp_valid = 1'b0;
        sys_rsp_done = 1'b0;
        sys_rsp_error = 1'b0;
        sys_rsp_error_code = 8'h00;
        sys_rsp_fail = 1'b0;
        sys_rsp_pb_valid = 1'b0;
        core_readout_ctrl = 8'h00;
        core_readout_id_addr = 8'h00;
        core_nand_status = 8'h00;
        core_ptr_reset_pulse = 1'b0;
        fail_count = 0;
        sys_pb_clear_count = 0;
        sys_ptr_reset_count = 0;

        wait_core_clk(4);
        wait_sys_clk(4);
        core_rst_n = 1'b1;
        sys_rst_n = 1'b1;
        wait_core_clk(2);
        wait_sys_clk(2);

        host_reg_busy = 1'b1;
        wait_sys_clk(5);
        check_true(host_busy, "Host Event Adapter mirrors Register Bank busy to sys");
        host_reg_busy = 1'b0;
        wait_sys_clk(5);
        check_true(!host_busy, "Host Event Adapter clears mirrored busy");

        host_wp_n = 1'b0;
        wait_core_clk(5);
        check_true(!core_wp_n, "Host Pin Status Adapter mirrors WP_N low to core");
        host_wp_n = 1'b1;
        wait_core_clk(5);
        check_true(core_wp_n, "Host Pin Status Adapter mirrors WP_N high to core");

        host_decoded_op = `ONFI_OP_READ_PAGE;
        host_cmd = 8'h30;
        host_addr0 = 8'h34;
        host_addr1 = 8'h12;
        host_addr2 = 8'h4a;
        host_addr3 = 8'h01;
        host_addr4 = 8'h00;
        host_addr_count = 3'd5;
        host_prog_data_count = 13'd16;
        host_protocol_error = 1'b0;
        host_protocol_error_code = `ONFI_ERR_NONE;
        host_decode_event_valid = 1'b1;
        wait_sys_clk(1);
        host_decode_event_valid = 1'b0;
        wait_sys_clk(2);
        check_true(!host_decode_event_ready,
                   "Host Event adapter backpressures while event is pending");
        wait_host_reg_event_valid(40);
        check_true(host_adapter_busy, "Host Event adapter busy while pending");
        check_true(host_reg_decoded_op == `ONFI_OP_READ_PAGE,
                   "Host Event decoded op snapshot");
        check_eq8(host_reg_cmd, 8'h30, "Host Event command snapshot");
        check_eq8(host_reg_addr0, 8'h34, "Host Event addr0 snapshot");
        check_eq8(host_reg_addr2, 8'h4a, "Host Event addr2 snapshot");
        check_true(host_reg_addr_count == 3'd5, "Host Event address count snapshot");
        check_true(host_reg_prog_data_count == 13'd16,
                   "Host Event program data count snapshot");
        host_reg_event_ready = 1'b1;
        wait_core_clk(1);
        host_reg_event_ready = 1'b0;
        wait_sys_clk(12);
        check_true(host_decode_event_ready,
                   "Host Event adapter ready returns after core ack");

        sys_pb_prog_ready = 1'b1;
        sys_pb_overflow = 1'b1;
        wait_core_clk(5);
        check_true(core_pb_prog_ready, "Page Buffer prog_ready mirrored to core");
        check_true(core_pb_overflow, "Page Buffer overflow mirrored to core");

        core_pb_clear_pulse = 1'b1;
        wait_core_clk(1);
        core_pb_clear_pulse = 1'b0;
        wait_sys_clk(20);
        check_true(sys_pb_clear_count == 1, "Page Buffer clear pulse crossed to sys");

        core_cmd_block = 32'h0000_0003;
        core_cmd_page = 32'h0000_0012;
        core_cmd_col = 32'h0000_0040;
        core_cmd_page_bytes = 32'h0000_0800;
        core_cmd_op_ctrl = 32'h0003_0002;
        core_cmd_latency = 32'h0000_007b;
        core_cmd_vread_level = 8'h01;
        core_cmd_vpgm_level = 8'h10;
        core_cmd_vpass_level = 8'h22;
        core_cmd_vers_level = 8'h33;
        core_cmd_bl_ctrl = 3'b101;
        core_cmd_wl_ctrl = 9'h12a;
        core_cmd_line_ctrl = 7'h55;
        core_cmd_bias_profile = 2'b10;
        core_cmd_valid = 1'b1;
        wait_core_clk(1);
        core_cmd_valid = 1'b0;
        wait_sys_cmd_valid(40);
        check_eq32(sys_cmd_block, 32'h0000_0003, "VPL command block");
        check_eq32(sys_cmd_page, 32'h0000_0012, "VPL command page");
        check_eq32(sys_cmd_col, 32'h0000_0040, "VPL command column");
        check_eq32(sys_cmd_op_ctrl, 32'h0003_0002, "VPL command op_ctrl");
        check_eq8(sys_cmd_vpgm_level, 8'h10, "VPL command vpgm level");
        check_true(sys_cmd_bl_ctrl == 3'b101, "VPL command BL ctrl");
        check_true(sys_cmd_wl_ctrl == 9'h12a, "VPL command WL ctrl");
        check_true(sys_cmd_line_ctrl == 7'h55, "VPL command line ctrl");
        check_true(sys_cmd_bias_profile == 2'b10, "VPL command bias profile");
        sys_cmd_ready = 1'b1;
        wait_sys_clk(1);
        sys_cmd_ready = 1'b0;

        sys_rsp_done = 1'b1;
        sys_rsp_error = 1'b1;
        sys_rsp_error_code = 8'h5a;
        sys_rsp_fail = 1'b1;
        sys_rsp_pb_valid = 1'b1;
        sys_rsp_valid = 1'b1;
        wait_sys_clk(1);
        sys_rsp_valid = 1'b0;
        wait_core_rsp_valid(40);
        check_true(core_rsp_done, "VPL response done");
        check_true(core_rsp_error, "VPL response error");
        check_eq8(core_rsp_error_code, 8'h5a, "VPL response error code");
        check_true(core_rsp_fail, "VPL response fail");
        check_true(core_rsp_pb_valid, "VPL response pb_valid");
        core_rsp_ready = 1'b1;
        wait_core_clk(1);
        core_rsp_ready = 1'b0;

        core_readout_ctrl = 8'h07;
        core_readout_id_addr = 8'h20;
        core_nand_status = 8'hc0;
        wait_sys_clk(40);
        check_eq8(sys_readout_ctrl, 8'h07, "Readout ctrl mirrored to sys");
        check_eq8(sys_readout_id_addr, 8'h20, "Readout ID addr mirrored to sys");
        check_eq8(sys_nand_status, 8'hc0, "NAND status mirrored to sys");

        core_ptr_reset_pulse = 1'b1;
        wait_core_clk(1);
        core_ptr_reset_pulse = 1'b0;
        wait_sys_clk(40);
        check_true(sys_ptr_reset_count == 1, "Readout ptr reset pulse mirrored to sys");

        core_ptr_reset_pulse = 1'b1;
        wait_core_clk(1);
        core_ptr_reset_pulse = 1'b0;
        core_readout_ctrl = 8'h09;
        core_readout_id_addr = 8'h00;
        core_nand_status = 8'h5c;
        wait_sys_clk(60);
        check_true(sys_ptr_reset_count == 2,
                   "Readout ptr reset pulse preserved across pending mirror update");
        check_eq8(sys_readout_ctrl, 8'h09, "Readout ctrl updated after pending pulse");
        check_eq8(sys_readout_id_addr, 8'h00,
                  "Readout ID addr updated after pending pulse");
        check_eq8(sys_nand_status, 8'h5c, "NAND status updated after pending pulse");

        if (fail_count == 0) begin
            $display("[PASS] tb_nand_role_adapters");
        end else begin
            $display("[FAIL] tb_nand_role_adapters fail_count=%0d", fail_count);
            $fatal(1, "tb_nand_role_adapters failed");
        end
        $finish;
    end

endmodule

`default_nettype wire
