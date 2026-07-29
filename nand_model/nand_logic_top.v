`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"
`include "onfi_sdr_defs.vh"

// Purpose: Host-facing NAND Logic Top integration for Decode Frontend,
// Register Bank, Page Buffer, VPL, Read Output, and the current control agent.
// Role: PoC integration top. The surrogate FW control-agent path is
// simulation-only; the rest of the datapath/control RTL is synthesizable.
// Related design docs:
// - design_spec/Architecture.md
// - design_spec/nand_adapter_contracts.md
// - design_spec/nand_register_bank.md
// Block contract: Instantiates Decode Frontend, role adapters, Page Buffer,
// Register Bank, and one control agent. By default the Register Bank cpu_* MMIO
// bus is driven by nand_surrogate_fw_agent. NAND_CONTROL_RV32 selects the
// PicoRV32-based control agent and keeps host traffic back-pressured until FW
// initialization reaches the IRQ-enable step.
// File version: v0.15
// Revision history:
// - v0.15: Remove the ambiguous top-level adapter_busy alias and
//   use Host Event Adapter busy and Page Buffer busy directly in RB_N gating.
// - v0.14: Remove unused Decode Frontend mode wires and keep RE#
//   edge ownership on the Read Output Datapath path.
// - v0.13: Gate host-ready/backpressure with control-agent ready
//   so RV32 FW can initialize IRQ handling before the first host command.
// - v0.12: Replace NAND_CONTROL_RV32 tie-off with
//   nand_rv32_control_agent instance that drives the Register Bank cpu_* MMIO
//   slot.
// - v0.11: Collapse public interface to host pins plus clock/reset,
//   expose bidirectional DQ and RB_N, and move scalar CDC handoffs behind role
//   adapters.
// - v0.10: Connect RE# rise to Read Output Datapath so dq_oe is
//   released between host read cycles.
// - v0.9: Instantiate sysclk Read Output Datapath and connect it
//   to mirrored Register Bank source/status and Page Buffer read port.
// - v0.8: Wire VPL executor direct sysclk Page Buffer read/write
//   ports for READ_PAGE fill and PROGRAM_PAGE source reads.
// - v0.7: Instantiate minimal clocked VPL executor in the top
//   integration path.
// - v0.6: Absorb temporary nand_logic_core back into
//   nand_logic_top and add a compile-time control-agent selection point.
// - v0.5: Replace temporary Page Buffer write adapter with
//   nand_page_buffer direct program-stream input.
// - v0.4: Move Host Event and Page Buffer write adapters out of
//   Decode Frontend and instantiate them at this integration level.
// - v0.3: Move raw CDC handoff into role adapters and wire
//   sys_clk/core_clk VPL, Page Buffer, and Read Output boundaries.
// - v0.2: Rename host clock ports to sys_clk/sys_rst_n and keep
//   Page Buffer bulk write path in the sys_clk domain.
// - v0.1: Initial Decode Frontend + Register Bank integration top.

module nand_logic_top #(
    parameter [31:0]  REG_BASE        = 32'h0200_0000,
    parameter integer PAGE_SIZE       = `NAND_PAGE_SIZE,
    parameter integer CHECK_TIMING_EN = 0,
    parameter integer T_WC_CYCLES     = `NAND_T_WC_CYCLES
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        core_clk,
    input  wire        core_rst_n,

    inout  wire [7:0]  dq,
    input  wire        cle,
    input  wire        ale,
    input  wire        ce_n,
    input  wire        we_n,
    input  wire        re_n,
    input  wire        wp_n,
    output wire        rb_n
);

    wire        reg_busy_sys;
    wire        wp_n_core;
    wire        pb_clear_busy;
    wire [7:0]  dq_in;
    wire [7:0]  dq_out;
    wire        dq_oe;

    wire        cpu_valid;
    wire [31:0] cpu_addr;
    wire [31:0] cpu_wdata;
    wire [3:0]  cpu_wstrb;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;

    wire        reg_event_valid;
    wire        reg_event_ready;
    wire [3:0]  reg_decoded_op;
    wire [7:0]  reg_cmd;
    wire [7:0]  reg_addr0;
    wire [7:0]  reg_addr1;
    wire [7:0]  reg_addr2;
    wire [7:0]  reg_addr3;
    wire [7:0]  reg_addr4;
    wire [2:0]  reg_addr_count;
    wire [12:0] reg_prog_data_count;
    wire        reg_protocol_error;
    wire [3:0]  reg_protocol_error_code;

    wire        decode_event_valid;
    wire        decode_event_ready;
    wire [3:0]  decode_decoded_op;
    wire [7:0]  decode_cmd;
    wire [7:0]  decode_addr0;
    wire [7:0]  decode_addr1;
    wire [7:0]  decode_addr2;
    wire [7:0]  decode_addr3;
    wire [7:0]  decode_addr4;
    wire [2:0]  decode_addr_count;
    wire [12:0] decode_prog_data_count;
    wire        decode_protocol_error;
    wire [3:0]  decode_protocol_error_code;
    wire        decode_event_accept;
    wire        host_event_adapter_busy;
    wire        decode_re_fall;
    wire        decode_re_rise;

    wire        prog_data_valid;
    wire        prog_data_ready;
    wire [7:0]  prog_data;
    wire        pb_busy;
    wire        pb_write_valid;
    wire [12:0] pb_write_addr;
    wire [7:0]  pb_write_data;
    wire [12:0] pb_write_count;
    wire        pb_prog_ready;
    wire        pb_overflow;

    wire        pb_prog_ready_core;
    wire        pb_overflow_core;
    wire        pb_clear_core_pulse;
    wire        pb_clear_sys_pulse;
    wire        pb_vpl_wr_valid;
    wire        pb_vpl_wr_ready;
    wire [12:0] pb_vpl_wr_addr;
    wire [7:0]  pb_vpl_wr_data;
    wire        pb_vpl_rd_req_valid;
    wire        pb_vpl_rd_req_ready;
    wire [12:0] pb_vpl_rd_addr;
    wire        pb_vpl_rd_data_valid;
    wire        pb_vpl_rd_data_ready;
    wire [7:0]  pb_vpl_rd_data;
    wire        pb_readout_rd_req_valid;
    wire        pb_readout_rd_req_ready;
    wire [12:0] pb_readout_rd_addr;
    wire        pb_readout_rd_data_valid;
    wire        pb_readout_rd_data_ready;
    wire [7:0]  pb_readout_rd_data;

    wire        core_vpl_cmd_valid;
    wire        core_vpl_cmd_ready;
    wire [31:0] core_vpl_cmd_block;
    wire [31:0] core_vpl_cmd_page;
    wire [31:0] core_vpl_cmd_col;
    wire [31:0] core_vpl_cmd_page_bytes;
    wire [31:0] core_vpl_cmd_op_ctrl;
    wire [31:0] core_vpl_cmd_latency;
    wire [7:0]  core_vpl_cmd_vread_level;
    wire [7:0]  core_vpl_cmd_vpgm_level;
    wire [7:0]  core_vpl_cmd_vpass_level;
    wire [7:0]  core_vpl_cmd_vers_level;
    wire [2:0]  core_vpl_cmd_bl_ctrl;
    wire [8:0]  core_vpl_cmd_wl_ctrl;
    wire [6:0]  core_vpl_cmd_line_ctrl;
    wire [1:0]  core_vpl_cmd_bias_profile;
    wire        core_vpl_rsp_valid;
    wire        core_vpl_rsp_ready;
    wire        core_vpl_rsp_done;
    wire        core_vpl_rsp_error;
    wire [7:0]  core_vpl_rsp_error_code;
    wire        core_vpl_rsp_fail;
    wire        core_vpl_rsp_pb_valid;

    wire        sys_vpl_cmd_valid;
    wire        sys_vpl_cmd_ready;
    wire [31:0] sys_vpl_cmd_block;
    wire [31:0] sys_vpl_cmd_page;
    wire [31:0] sys_vpl_cmd_col;
    wire [31:0] sys_vpl_cmd_page_bytes;
    wire [31:0] sys_vpl_cmd_op_ctrl;
    wire [31:0] sys_vpl_cmd_latency;
    wire [7:0]  sys_vpl_cmd_vread_level;
    wire [7:0]  sys_vpl_cmd_vpgm_level;
    wire [7:0]  sys_vpl_cmd_vpass_level;
    wire [7:0]  sys_vpl_cmd_vers_level;
    wire [2:0]  sys_vpl_cmd_bl_ctrl;
    wire [8:0]  sys_vpl_cmd_wl_ctrl;
    wire [6:0]  sys_vpl_cmd_line_ctrl;
    wire [1:0]  sys_vpl_cmd_bias_profile;
    wire        sys_vpl_rsp_valid;
    wire        sys_vpl_rsp_ready;
    wire        sys_vpl_rsp_done;
    wire        sys_vpl_rsp_error;
    wire [7:0]  sys_vpl_rsp_error_code;
    wire        sys_vpl_rsp_fail;
    wire        sys_vpl_rsp_pb_valid;

    wire [7:0]  core_nand_status;
    wire [7:0]  core_readout_ctrl;
    wire [7:0]  core_readout_id_addr;
    wire [7:0]  readout_ctrl;
    wire [7:0]  nand_status;
    wire [7:0]  sys_readout_id_addr;
    wire        core_readout_ptr_reset_pulse;
    wire        readout_ptr_reset_pulse;
    wire [12:0] readout_ptr;
    wire        readout_busy;
    wire        fsm_busy;
    wire [2:0]  seq_state;
    wire [5:0]  op_status;
    wire [7:0]  op_error;
    wire        host_event_pending;
    wire [2:0]  irq_status;
    wire [2:0]  irq_enable;
    wire        irq;
    wire        reg_busy;
    wire        reg_ready;
    wire        access_error;
    wire        rv32_trap;
    wire        control_ready_core;
    wire        control_ready_sys;
    wire        host_lockout_sys;

    assign dq_in = dq;
    assign dq = dq_oe ? dq_out : 8'hzz;
    assign decode_event_accept = decode_event_valid && decode_event_ready;
    assign host_lockout_sys = reg_busy_sys || !control_ready_sys;
    assign rb_n = control_ready_sys && !reg_busy_sys &&
                  !host_event_adapter_busy && !pb_busy &&
                  !fsm_busy && nand_status[6];

    nand_host_pin_status_adapter u_host_pin_status_adapter (
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .wp_n_i(wp_n),
        .core_wp_n_o(wp_n_core)
    );

    nand_cdc_level_adapter #(
        .WIDTH(1)
    ) u_control_ready_to_sys (
        .src_level_i(control_ready_core),
        .dst_clk(sys_clk),
        .dst_rst_n(sys_rst_n),
        .dst_level_o(control_ready_sys)
    );

    nand_page_buffer_adapter u_page_buffer_adapter (
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .core_pb_clear_pulse_i(pb_clear_core_pulse),
        .core_pb_clear_busy_o(pb_clear_busy),
        .core_pb_prog_ready_o(pb_prog_ready_core),
        .core_pb_overflow_o(pb_overflow_core),
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .sys_pb_clear_pulse_o(pb_clear_sys_pulse),
        .sys_pb_prog_ready_i(pb_prog_ready),
        .sys_pb_overflow_i(pb_overflow)
    );

    onfi_sdr_decode_frontend #(
        .CHECK_TIMING_EN(CHECK_TIMING_EN),
        .T_WC_CYCLES(T_WC_CYCLES)
    ) u_decode_frontend (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .dq_in(dq_in),
        .cle(cle),
        .ale(ale),
        .ce_n(ce_n),
        .we_n(we_n),
        .re_n(re_n),
        .host_busy_i(host_lockout_sys),
        .decode_event_valid_o(decode_event_valid),
        .decode_event_ready_i(decode_event_ready),
        .decoded_op_o(decode_decoded_op),
        .cmd_o(decode_cmd),
        .addr0_o(decode_addr0),
        .addr1_o(decode_addr1),
        .addr2_o(decode_addr2),
        .addr3_o(decode_addr3),
        .addr4_o(decode_addr4),
        .addr_count_o(decode_addr_count),
        .prog_data_count_o(decode_prog_data_count),
        .protocol_error_o(decode_protocol_error),
        .protocol_error_code_o(decode_protocol_error_code),
        .prog_data_valid_o(prog_data_valid),
        .prog_data_ready_i(prog_data_ready),
        .prog_data_o(prog_data),
        .fsm_busy_o(fsm_busy),
        .re_fall_o(decode_re_fall),
        .re_rise_o(decode_re_rise),
        .seq_state_o(seq_state)
    );

    nand_host_event_adapter u_host_event_adapter (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .decode_event_valid_i(decode_event_valid),
        .decode_event_ready_o(decode_event_ready),
        .decoded_op_i(decode_decoded_op),
        .cmd_i(decode_cmd),
        .addr0_i(decode_addr0),
        .addr1_i(decode_addr1),
        .addr2_i(decode_addr2),
        .addr3_i(decode_addr3),
        .addr4_i(decode_addr4),
        .addr_count_i(decode_addr_count),
        .prog_data_count_i(decode_prog_data_count),
        .protocol_error_i(decode_protocol_error),
        .protocol_error_code_i(decode_protocol_error_code),
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .reg_busy_i(reg_busy),
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
        .host_busy_o(reg_busy_sys),
        .adapter_busy_o(host_event_adapter_busy)
    );

    nand_page_buffer #(
        .PAGE_SIZE(PAGE_SIZE)
    ) u_page_buffer (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .prog_data_valid_i(prog_data_valid),
        .prog_data_ready_o(prog_data_ready),
        .prog_data_i(prog_data),
        .clear_i(pb_clear_sys_pulse),
        .freeze_i(decode_event_accept &&
                  (decode_decoded_op == `ONFI_OP_PROGRAM) &&
                  !decode_protocol_error),
        .vpl_wr_valid_i(pb_vpl_wr_valid),
        .vpl_wr_ready_o(pb_vpl_wr_ready),
        .vpl_wr_addr_i(pb_vpl_wr_addr),
        .vpl_wr_data_i(pb_vpl_wr_data),
        .vpl_rd_req_valid_i(pb_vpl_rd_req_valid),
        .vpl_rd_req_ready_o(pb_vpl_rd_req_ready),
        .vpl_rd_addr_i(pb_vpl_rd_addr),
        .vpl_rd_data_valid_o(pb_vpl_rd_data_valid),
        .vpl_rd_data_ready_i(pb_vpl_rd_data_ready),
        .vpl_rd_data_o(pb_vpl_rd_data),
        .readout_rd_req_valid_i(pb_readout_rd_req_valid),
        .readout_rd_req_ready_o(pb_readout_rd_req_ready),
        .readout_rd_addr_i(pb_readout_rd_addr),
        .readout_rd_data_valid_o(pb_readout_rd_data_valid),
        .readout_rd_data_ready_i(pb_readout_rd_data_ready),
        .readout_rd_data_o(pb_readout_rd_data),
        .write_valid_o(pb_write_valid),
        .write_addr_o(pb_write_addr),
        .write_data_o(pb_write_data),
        .write_count_o(pb_write_count),
        .prog_ready_o(pb_prog_ready),
        .overflow_o(pb_overflow),
        .busy_o(pb_busy)
    );

    nand_register_bank #(
        .REG_BASE(REG_BASE),
        .PAGE_SIZE(PAGE_SIZE)
    ) u_register_bank (
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
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
        .wp_n_i(wp_n_core),
        .pb_prog_ready_i(pb_prog_ready_core),
        .pb_overflow_i(pb_overflow_core),
        .pb_prog_clear_o(pb_clear_core_pulse),
        .vpl_cmd_valid_o(core_vpl_cmd_valid),
        .vpl_cmd_ready_i(core_vpl_cmd_ready),
        .vpl_cmd_block_o(core_vpl_cmd_block),
        .vpl_cmd_page_o(core_vpl_cmd_page),
        .vpl_cmd_col_o(core_vpl_cmd_col),
        .vpl_cmd_page_bytes_o(core_vpl_cmd_page_bytes),
        .vpl_cmd_op_ctrl_o(core_vpl_cmd_op_ctrl),
        .vpl_cmd_latency_o(core_vpl_cmd_latency),
        .vpl_cmd_vread_level_o(core_vpl_cmd_vread_level),
        .vpl_cmd_vpgm_level_o(core_vpl_cmd_vpgm_level),
        .vpl_cmd_vpass_level_o(core_vpl_cmd_vpass_level),
        .vpl_cmd_vers_level_o(core_vpl_cmd_vers_level),
        .vpl_cmd_bl_ctrl_o(core_vpl_cmd_bl_ctrl),
        .vpl_cmd_wl_ctrl_o(core_vpl_cmd_wl_ctrl),
        .vpl_cmd_line_ctrl_o(core_vpl_cmd_line_ctrl),
        .vpl_cmd_bias_profile_o(core_vpl_cmd_bias_profile),
        .vpl_rsp_valid_i(core_vpl_rsp_valid),
        .vpl_rsp_ready_o(core_vpl_rsp_ready),
        .vpl_rsp_done_i(core_vpl_rsp_done),
        .vpl_rsp_error_i(core_vpl_rsp_error),
        .vpl_rsp_error_code_i(core_vpl_rsp_error_code),
        .vpl_rsp_fail_i(core_vpl_rsp_fail),
        .vpl_rsp_pb_valid_i(core_vpl_rsp_pb_valid),
        .nand_status_o(core_nand_status),
        .op_status_o(op_status),
        .op_error_o(op_error),
        .readout_ctrl_o(core_readout_ctrl),
        .readout_id_addr_o(core_readout_id_addr),
        .readout_ptr_reset_pulse_o(core_readout_ptr_reset_pulse),
        .host_event_pending_o(host_event_pending),
        .irq_status_o(irq_status),
        .irq_enable_o(irq_enable),
        .irq_o(irq),
        .reg_busy_o(reg_busy),
        .reg_ready_o(reg_ready),
        .access_error_o(access_error)
    );

    nand_vpl_command_response_adapter u_vpl_adapter (
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .core_cmd_valid_i(core_vpl_cmd_valid),
        .core_cmd_ready_o(core_vpl_cmd_ready),
        .core_cmd_block_i(core_vpl_cmd_block),
        .core_cmd_page_i(core_vpl_cmd_page),
        .core_cmd_col_i(core_vpl_cmd_col),
        .core_cmd_page_bytes_i(core_vpl_cmd_page_bytes),
        .core_cmd_op_ctrl_i(core_vpl_cmd_op_ctrl),
        .core_cmd_latency_i(core_vpl_cmd_latency),
        .core_cmd_vread_level_i(core_vpl_cmd_vread_level),
        .core_cmd_vpgm_level_i(core_vpl_cmd_vpgm_level),
        .core_cmd_vpass_level_i(core_vpl_cmd_vpass_level),
        .core_cmd_vers_level_i(core_vpl_cmd_vers_level),
        .core_cmd_bl_ctrl_i(core_vpl_cmd_bl_ctrl),
        .core_cmd_wl_ctrl_i(core_vpl_cmd_wl_ctrl),
        .core_cmd_line_ctrl_i(core_vpl_cmd_line_ctrl),
        .core_cmd_bias_profile_i(core_vpl_cmd_bias_profile),
        .core_rsp_valid_o(core_vpl_rsp_valid),
        .core_rsp_ready_i(core_vpl_rsp_ready),
        .core_rsp_done_o(core_vpl_rsp_done),
        .core_rsp_error_o(core_vpl_rsp_error),
        .core_rsp_error_code_o(core_vpl_rsp_error_code),
        .core_rsp_fail_o(core_vpl_rsp_fail),
        .core_rsp_pb_valid_o(core_vpl_rsp_pb_valid),
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .sys_cmd_valid_o(sys_vpl_cmd_valid),
        .sys_cmd_ready_i(sys_vpl_cmd_ready),
        .sys_cmd_block_o(sys_vpl_cmd_block),
        .sys_cmd_page_o(sys_vpl_cmd_page),
        .sys_cmd_col_o(sys_vpl_cmd_col),
        .sys_cmd_page_bytes_o(sys_vpl_cmd_page_bytes),
        .sys_cmd_op_ctrl_o(sys_vpl_cmd_op_ctrl),
        .sys_cmd_latency_o(sys_vpl_cmd_latency),
        .sys_cmd_vread_level_o(sys_vpl_cmd_vread_level),
        .sys_cmd_vpgm_level_o(sys_vpl_cmd_vpgm_level),
        .sys_cmd_vpass_level_o(sys_vpl_cmd_vpass_level),
        .sys_cmd_vers_level_o(sys_vpl_cmd_vers_level),
        .sys_cmd_bl_ctrl_o(sys_vpl_cmd_bl_ctrl),
        .sys_cmd_wl_ctrl_o(sys_vpl_cmd_wl_ctrl),
        .sys_cmd_line_ctrl_o(sys_vpl_cmd_line_ctrl),
        .sys_cmd_bias_profile_o(sys_vpl_cmd_bias_profile),
        .sys_rsp_valid_i(sys_vpl_rsp_valid),
        .sys_rsp_ready_o(sys_vpl_rsp_ready),
        .sys_rsp_done_i(sys_vpl_rsp_done),
        .sys_rsp_error_i(sys_vpl_rsp_error),
        .sys_rsp_error_code_i(sys_vpl_rsp_error_code),
        .sys_rsp_fail_i(sys_vpl_rsp_fail),
        .sys_rsp_pb_valid_i(sys_vpl_rsp_pb_valid)
    );

    nand_vpl_executor #(
        .PAGE_SIZE(PAGE_SIZE)
    ) u_vpl_executor (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .cmd_valid_i(sys_vpl_cmd_valid),
        .cmd_ready_o(sys_vpl_cmd_ready),
        .cmd_block_i(sys_vpl_cmd_block),
        .cmd_page_i(sys_vpl_cmd_page),
        .cmd_col_i(sys_vpl_cmd_col),
        .cmd_page_bytes_i(sys_vpl_cmd_page_bytes),
        .cmd_op_ctrl_i(sys_vpl_cmd_op_ctrl),
        .cmd_latency_i(sys_vpl_cmd_latency),
        .cmd_vread_level_i(sys_vpl_cmd_vread_level),
        .cmd_vpgm_level_i(sys_vpl_cmd_vpgm_level),
        .cmd_vpass_level_i(sys_vpl_cmd_vpass_level),
        .cmd_vers_level_i(sys_vpl_cmd_vers_level),
        .cmd_bl_ctrl_i(sys_vpl_cmd_bl_ctrl),
        .cmd_wl_ctrl_i(sys_vpl_cmd_wl_ctrl),
        .cmd_line_ctrl_i(sys_vpl_cmd_line_ctrl),
        .cmd_bias_profile_i(sys_vpl_cmd_bias_profile),
        .rsp_valid_o(sys_vpl_rsp_valid),
        .rsp_ready_i(sys_vpl_rsp_ready),
        .rsp_done_o(sys_vpl_rsp_done),
        .rsp_error_o(sys_vpl_rsp_error),
        .rsp_error_code_o(sys_vpl_rsp_error_code),
        .rsp_fail_o(sys_vpl_rsp_fail),
        .rsp_pb_valid_o(sys_vpl_rsp_pb_valid),
        .pb_prog_ready_i(pb_prog_ready),
        .pb_overflow_i(pb_overflow),
        .pb_wr_valid_o(pb_vpl_wr_valid),
        .pb_wr_ready_i(pb_vpl_wr_ready),
        .pb_wr_addr_o(pb_vpl_wr_addr),
        .pb_wr_data_o(pb_vpl_wr_data),
        .pb_rd_req_valid_o(pb_vpl_rd_req_valid),
        .pb_rd_req_ready_i(pb_vpl_rd_req_ready),
        .pb_rd_addr_o(pb_vpl_rd_addr),
        .pb_rd_data_valid_i(pb_vpl_rd_data_valid),
        .pb_rd_data_ready_o(pb_vpl_rd_data_ready),
        .pb_rd_data_i(pb_vpl_rd_data)
    );

    nand_read_output_mirror_adapter u_read_output_mirror_adapter (
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .core_readout_ctrl_i(core_readout_ctrl),
        .core_readout_id_addr_i(core_readout_id_addr),
        .core_nand_status_i(core_nand_status),
        .core_ptr_reset_pulse_i(core_readout_ptr_reset_pulse),
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .sys_readout_ctrl_o(readout_ctrl),
        .sys_readout_id_addr_o(sys_readout_id_addr),
        .sys_nand_status_o(nand_status),
        .sys_ptr_reset_pulse_o(readout_ptr_reset_pulse)
    );

    nand_read_output_datapath #(
        .PAGE_SIZE(PAGE_SIZE)
    ) u_read_output_datapath (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .re_fall_i(decode_re_fall),
        .re_rise_i(decode_re_rise),
        .ptr_reset_i(readout_ptr_reset_pulse),
        .readout_ctrl_i(readout_ctrl),
        .readout_id_addr_i(sys_readout_id_addr),
        .nand_status_i(nand_status),
        .pb_rd_req_valid_o(pb_readout_rd_req_valid),
        .pb_rd_req_ready_i(pb_readout_rd_req_ready),
        .pb_rd_addr_o(pb_readout_rd_addr),
        .pb_rd_data_valid_i(pb_readout_rd_data_valid),
        .pb_rd_data_ready_o(pb_readout_rd_data_ready),
        .pb_rd_data_i(pb_readout_rd_data),
        .dq_out_o(dq_out),
        .dq_oe_o(dq_oe),
        .read_ptr_o(readout_ptr),
        .busy_o(readout_busy)
    );

`ifdef NAND_CONTROL_RV32
    nand_rv32_control_agent #(
        .REG_BASE(REG_BASE)
    ) u_rv32_control_agent (
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .enable_i(1'b1),
        .irq_i(irq),
        .cpu_valid_o(cpu_valid),
        .cpu_addr_o(cpu_addr),
        .cpu_wdata_o(cpu_wdata),
        .cpu_wstrb_o(cpu_wstrb),
        .cpu_rdata_i(cpu_rdata),
        .cpu_ready_i(cpu_ready),
        .fw_ready_o(control_ready_core),
        .trap_o(rv32_trap)
    );
`else
    assign rv32_trap = 1'b0;
    assign control_ready_core = 1'b1;

    nand_surrogate_fw_agent #(
        .REG_BASE(REG_BASE)
    ) u_surrogate_fw (
        .core_clk(core_clk),
        .core_rst_n(core_rst_n),
        .enable_i(1'b1),
        .irq_i(irq),
        .cpu_valid_o(cpu_valid),
        .cpu_addr_o(cpu_addr),
        .cpu_wdata_o(cpu_wdata),
        .cpu_wstrb_o(cpu_wstrb),
        .cpu_rdata_i(cpu_rdata),
        .cpu_ready_i(cpu_ready)
    );
`endif

endmodule

`default_nettype wire
