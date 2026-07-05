`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"
`include "onfi_sdr_defs.vh"

// Purpose: Integrate generic pin synchronization and ONFI SDR Decode FSM.
// Role: Synthesizable RTL top for the decode front-end bring-up scope.
// Related design docs:
// - design_spec/Architecture.md
// - design_spec/SIMPLE_ONFI_SDR_decode_fsm.md
// - design_spec/nand_adapter_contracts.md
// Block contract: Exposes raw Decode FSM transaction event and program data
// stream ports. Host Event CDC and Page Buffer write-path adapters are
// instantiated by the parent integration top.
// File version: v0.6
// Revision history:
// - v0.6: Export synchronized RE# edge pulses for the sysclk
//   Read Output Datapath.
// - v0.5: Remove internal adapter instances and expose raw Decode
//   FSM handoff ports for top-level role adapter integration.
// - v0.4: Rename public clocks to sys_clk/core_clk and keep Page
//   Buffer bulk data on a sys_clk-local direct path.
// - v0.3: Use shared nand_parameters.vh for default page size and
//   timing-checker default cycles.
// - v0.2: Added generic pin_sync_edge_detect integration and moved
//   synchronized pin-level handoff into the Decode FSM.
// - v0.1: Initial Decode FSM + Adapter integration wrapper.

module onfi_sdr_decode_frontend #(
    parameter integer CHECK_TIMING_EN = 0,
    parameter integer T_WC_CYCLES     = `NAND_T_WC_CYCLES
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    input  wire [7:0]  dq_in,
    input  wire        cle,
    input  wire        ale,
    input  wire        ce_n,
    input  wire        we_n,
    input  wire        re_n,
    input  wire        wp_n,

    input  wire        host_busy_i,

    output wire        decode_event_valid_o,
    input  wire        decode_event_ready_i,
    output wire [3:0]  decoded_op_o,
    output wire [7:0]  cmd_o,
    output wire [7:0]  addr0_o,
    output wire [7:0]  addr1_o,
    output wire [7:0]  addr2_o,
    output wire [7:0]  addr3_o,
    output wire [7:0]  addr4_o,
    output wire [2:0]  addr_count_o,
    output wire [12:0] prog_data_count_o,
    output wire        protocol_error_o,
    output wire [3:0]  protocol_error_code_o,

    output wire        prog_data_valid_o,
    input  wire        prog_data_ready_i,
    output wire [7:0]  prog_data_o,

    output wire        mode_status_o,
    output wire        mode_id_o,
    output wire        mode_read_o,
    output wire        fsm_busy_o,
    output wire        re_fall_o,
    output wire        re_rise_o,
    output wire [2:0]  seq_state_o
);

    localparam integer PIN_WIDTH = 14;
    localparam integer PIN_DQ_LSB = 0;
    localparam integer PIN_CLE    = 8;
    localparam integer PIN_ALE    = 9;
    localparam integer PIN_CE_N   = 10;
    localparam integer PIN_WE_N   = 11;
    localparam integer PIN_RE_N   = 12;
    localparam integer PIN_WP_N   = 13;
    localparam [PIN_WIDTH-1:0] PIN_RESET_VALUE = {
        1'b1, // wp_n
        1'b1, // re_n
        1'b1, // we_n
        1'b1, // ce_n
        1'b0, // ale
        1'b0, // cle
        8'h00 // dq
    };

    wire [PIN_WIDTH-1:0] async_pins;
    wire [PIN_WIDTH-1:0] sync_pins;
    wire [PIN_WIDTH-1:0] rise_pulses;
    wire [PIN_WIDTH-1:0] fall_pulses;

    assign async_pins[PIN_DQ_LSB +: 8] = dq_in;
    assign async_pins[PIN_CLE] = cle;
    assign async_pins[PIN_ALE] = ale;
    assign async_pins[PIN_CE_N] = ce_n;
    assign async_pins[PIN_WE_N] = we_n;
    assign async_pins[PIN_RE_N] = re_n;
    assign async_pins[PIN_WP_N] = wp_n;

    wire [7:0] sync_dq = sync_pins[PIN_DQ_LSB +: 8];
    wire       sync_cle = sync_pins[PIN_CLE];
    wire       sync_ale = sync_pins[PIN_ALE];
    wire       sync_ce_n = sync_pins[PIN_CE_N];
    wire       sync_wp_n = sync_pins[PIN_WP_N];
    wire       sync_we_rise = rise_pulses[PIN_WE_N];
    wire       sync_re_fall = fall_pulses[PIN_RE_N];
    wire       sync_re_rise = rise_pulses[PIN_RE_N];

    assign re_fall_o = sync_re_fall;
    assign re_rise_o = sync_re_rise;

    pin_sync_edge_detect #(
        .WIDTH(PIN_WIDTH),
        .RESET_VALUE(PIN_RESET_VALUE)
    ) u_pin_sync_edge_detect (
        .clk(sys_clk),
        .resetn(sys_rst_n),
        .async_i(async_pins),
        .sync_o(sync_pins),
        .rise_pulse_o(rise_pulses),
        .fall_pulse_o(fall_pulses)
    );

    onfi_sdr_decode_fsm #(
        .CHECK_TIMING_EN(CHECK_TIMING_EN),
        .T_WC_CYCLES(T_WC_CYCLES)
    ) u_decode_fsm (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .dq_sync_i(sync_dq),
        .cle_sync_i(sync_cle),
        .ale_sync_i(sync_ale),
        .ce_n_sync_i(sync_ce_n),
        .wp_n_sync_i(sync_wp_n),
        .we_rise_i(sync_we_rise),
        .re_fall_i(sync_re_fall),
        .re_rise_i(sync_re_rise),
        .host_busy_i(host_busy_i),
        .decode_event_ready_i(decode_event_ready_i),
        .prog_data_ready_i(prog_data_ready_i),
        .decode_event_valid_o(decode_event_valid_o),
        .decoded_op_o(decoded_op_o),
        .cmd_o(cmd_o),
        .addr0_o(addr0_o),
        .addr1_o(addr1_o),
        .addr2_o(addr2_o),
        .addr3_o(addr3_o),
        .addr4_o(addr4_o),
        .addr_count_o(addr_count_o),
        .prog_data_count_o(prog_data_count_o),
        .mode_status_o(mode_status_o),
        .mode_id_o(mode_id_o),
        .mode_read_o(mode_read_o),
        .prog_data_valid_o(prog_data_valid_o),
        .prog_data_o(prog_data_o),
        .protocol_error_o(protocol_error_o),
        .protocol_error_code_o(protocol_error_code_o),
        .fsm_busy_o(fsm_busy_o),
        .seq_state_o(seq_state_o)
    );

endmodule

`default_nettype wire
