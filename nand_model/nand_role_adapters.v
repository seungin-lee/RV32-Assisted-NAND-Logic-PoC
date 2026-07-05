`timescale 1ns/1ps
`default_nettype none

// Purpose: Reusable CDC adapter wrappers and NAND role adapters used by
// nand_logic_top integration.
// Role: Synthesizable RTL.
// Related design docs:
// - design_spec/nand_adapter_contracts.md
// - design_spec/Architecture.md
// Block contract: Role adapters own CDC handoff details so top-level logic can
// remain wire/module integration. Bulk Page Buffer program data is owned by
// nand_page_buffer and is not crossed here.
// File version: v0.5
// Revision history:
// - v0.5: Move Register Bank busy-to-sys handoff into Host Event
//   Adapter and add Host Pin Status Adapter for WP_N core-domain mirror.
// - v0.4: Add Read Output Mirror Adapter ID address snapshot
//   payload field.
// - v0.3: Move sys_clk Page Buffer write/count/freeze ownership
//   out to nand_page_buffer and keep this file focused on handoff adapters.
// - v0.2: Absorb Host Event CDC and sys_clk Page Buffer write
//   path roles so Decode Frontend can expose raw Decode FSM handoff ports.
// - v0.1: Initial reusable CDC wrappers plus Page Buffer,
//   VPL Command/Response, and Read Output Mirror role adapters.

module nand_cdc_payload_adapter #(
    parameter integer PAYLOAD_WIDTH = 1
) (
    input  wire                       src_clk,
    input  wire                       src_rst_n,
    input  wire                       src_valid_i,
    output wire                       src_ready_o,
    input  wire [PAYLOAD_WIDTH-1:0]   src_payload_i,

    input  wire                       dst_clk,
    input  wire                       dst_rst_n,
    output wire                       dst_valid_o,
    input  wire                       dst_ready_i,
    output wire [PAYLOAD_WIDTH-1:0]   dst_payload_o
);

    cdc_valid_ack #(
        .DATA_WIDTH(PAYLOAD_WIDTH)
    ) u_cdc_valid_ack (
        .src_clk(src_clk),
        .src_resetn(src_rst_n),
        .src_valid(src_valid_i),
        .src_ready(src_ready_o),
        .src_data(src_payload_i),
        .dst_clk(dst_clk),
        .dst_resetn(dst_rst_n),
        .dst_valid(dst_valid_o),
        .dst_ready(dst_ready_i),
        .dst_data(dst_payload_o)
    );

endmodule

module nand_cdc_level_adapter #(
    parameter integer WIDTH = 1
) (
    input  wire [WIDTH-1:0] src_level_i,
    input  wire             dst_clk,
    input  wire             dst_rst_n,
    output wire [WIDTH-1:0] dst_level_o
);

    genvar bit_idx;

    generate
        for (bit_idx = 0; bit_idx < WIDTH; bit_idx = bit_idx + 1) begin : g_level_sync
            cdc_level_sync u_level_sync (
                .src_level(src_level_i[bit_idx]),
                .dst_clk(dst_clk),
                .dst_resetn(dst_rst_n),
                .dst_level(dst_level_o[bit_idx])
            );
        end
    endgenerate

endmodule

module nand_cdc_pulse_adapter (
    input  wire src_clk,
    input  wire src_rst_n,
    input  wire src_pulse_i,
    output wire src_busy_o,

    input  wire dst_clk,
    input  wire dst_rst_n,
    output wire dst_pulse_o
);

    reg        src_valid_q;
    wire       src_ready;
    wire       dst_valid;
    wire [0:0] dst_payload;

    assign src_busy_o = src_valid_q || !src_ready;
    assign dst_pulse_o = dst_valid && dst_payload[0];

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_valid_q <= 1'b0;
        end else if (src_valid_q && src_ready) begin
            src_valid_q <= src_pulse_i;
        end else if (src_pulse_i) begin
            src_valid_q <= 1'b1;
        end
    end

    nand_cdc_payload_adapter #(
        .PAYLOAD_WIDTH(1)
    ) u_pulse_payload_cdc (
        .src_clk(src_clk),
        .src_rst_n(src_rst_n),
        .src_valid_i(src_valid_q),
        .src_ready_o(src_ready),
        .src_payload_i(1'b1),
        .dst_clk(dst_clk),
        .dst_rst_n(dst_rst_n),
        .dst_valid_o(dst_valid),
        .dst_ready_i(1'b1),
        .dst_payload_o(dst_payload)
    );

endmodule

module nand_host_event_adapter #(
    parameter integer EVENT_PAYLOAD_WIDTH = 73
) (
    input  wire       sys_clk,
    input  wire       sys_rst_n,

    input  wire       decode_event_valid_i,
    output wire       decode_event_ready_o,
    input  wire [3:0] decoded_op_i,
    input  wire [7:0] cmd_i,
    input  wire [7:0] addr0_i,
    input  wire [7:0] addr1_i,
    input  wire [7:0] addr2_i,
    input  wire [7:0] addr3_i,
    input  wire [7:0] addr4_i,
    input  wire [2:0] addr_count_i,
    input  wire [12:0] prog_data_count_i,
    input  wire       protocol_error_i,
    input  wire [3:0] protocol_error_code_i,

    input  wire       core_clk,
    input  wire       core_rst_n,
    input  wire       reg_busy_i,
    output wire       reg_event_valid_o,
    input  wire       reg_event_ready_i,
    output wire [3:0] reg_decoded_op_o,
    output wire [7:0] reg_cmd_o,
    output wire [7:0] reg_addr0_o,
    output wire [7:0] reg_addr1_o,
    output wire [7:0] reg_addr2_o,
    output wire [7:0] reg_addr3_o,
    output wire [7:0] reg_addr4_o,
    output wire [2:0] reg_addr_count_o,
    output wire [12:0] reg_prog_data_count_o,
    output wire       reg_protocol_error_o,
    output wire [3:0] reg_protocol_error_code_o,

    output wire       host_busy_o,
    output wire       adapter_busy_o
);

    wire [EVENT_PAYLOAD_WIDTH-1:0] event_src_payload;
    wire [EVENT_PAYLOAD_WIDTH-1:0] event_dst_payload;
    wire                           event_src_ready;

    assign event_src_payload = {
        protocol_error_code_i,
        protocol_error_i,
        prog_data_count_i,
        addr_count_i,
        addr4_i,
        addr3_i,
        addr2_i,
        addr1_i,
        addr0_i,
        cmd_i,
        decoded_op_i
    };

    assign {
        reg_protocol_error_code_o,
        reg_protocol_error_o,
        reg_prog_data_count_o,
        reg_addr_count_o,
        reg_addr4_o,
        reg_addr3_o,
        reg_addr2_o,
        reg_addr1_o,
        reg_addr0_o,
        reg_cmd_o,
        reg_decoded_op_o
    } = event_dst_payload;

    assign decode_event_ready_o = event_src_ready;
    assign adapter_busy_o = !event_src_ready;

    nand_cdc_level_adapter #(
        .WIDTH(1)
    ) u_reg_busy_to_sys (
        .src_level_i(reg_busy_i),
        .dst_clk(sys_clk),
        .dst_rst_n(sys_rst_n),
        .dst_level_o(host_busy_o)
    );

    nand_cdc_payload_adapter #(
        .PAYLOAD_WIDTH(EVENT_PAYLOAD_WIDTH)
    ) u_reg_event_cdc (
        .src_clk(sys_clk),
        .src_rst_n(sys_rst_n),
        .src_valid_i(decode_event_valid_i),
        .src_ready_o(event_src_ready),
        .src_payload_i(event_src_payload),
        .dst_clk(core_clk),
        .dst_rst_n(core_rst_n),
        .dst_valid_o(reg_event_valid_o),
        .dst_ready_i(reg_event_ready_i),
        .dst_payload_o(event_dst_payload)
    );

endmodule

module nand_host_pin_status_adapter (
    input  wire core_clk,
    input  wire core_rst_n,
    input  wire wp_n_i,
    output wire core_wp_n_o
);

    wire core_wp_protect;

    assign core_wp_n_o = ~core_wp_protect;

    nand_cdc_level_adapter #(
        .WIDTH(1)
    ) u_wp_protect_to_core (
        .src_level_i(~wp_n_i),
        .dst_clk(core_clk),
        .dst_rst_n(core_rst_n),
        .dst_level_o(core_wp_protect)
    );

endmodule

module nand_page_buffer_adapter (
    input  wire core_clk,
    input  wire core_rst_n,
    input  wire core_pb_clear_pulse_i,
    output wire core_pb_clear_busy_o,
    output wire core_pb_prog_ready_o,
    output wire core_pb_overflow_o,

    input  wire sys_clk,
    input  wire sys_rst_n,
    output wire sys_pb_clear_pulse_o,
    input  wire sys_pb_prog_ready_i,
    input  wire sys_pb_overflow_i
);

    wire [1:0] core_status;

    assign {core_pb_overflow_o, core_pb_prog_ready_o} = core_status;

    nand_cdc_pulse_adapter u_pb_clear_cdc (
        .src_clk(core_clk),
        .src_rst_n(core_rst_n),
        .src_pulse_i(core_pb_clear_pulse_i),
        .src_busy_o(core_pb_clear_busy_o),
        .dst_clk(sys_clk),
        .dst_rst_n(sys_rst_n),
        .dst_pulse_o(sys_pb_clear_pulse_o)
    );

    nand_cdc_level_adapter #(
        .WIDTH(2)
    ) u_pb_status_sync (
        .src_level_i({sys_pb_overflow_i, sys_pb_prog_ready_i}),
        .dst_clk(core_clk),
        .dst_rst_n(core_rst_n),
        .dst_level_o(core_status)
    );

endmodule

module nand_vpl_command_response_adapter (
    input  wire        core_clk,
    input  wire        core_rst_n,
    input  wire        core_cmd_valid_i,
    output wire        core_cmd_ready_o,
    input  wire [31:0] core_cmd_block_i,
    input  wire [31:0] core_cmd_page_i,
    input  wire [31:0] core_cmd_col_i,
    input  wire [31:0] core_cmd_page_bytes_i,
    input  wire [31:0] core_cmd_op_ctrl_i,
    input  wire [31:0] core_cmd_latency_i,
    input  wire [7:0]  core_cmd_vread_level_i,
    input  wire [7:0]  core_cmd_vpgm_level_i,
    input  wire [7:0]  core_cmd_vpass_level_i,
    input  wire [7:0]  core_cmd_vers_level_i,
    input  wire [2:0]  core_cmd_bl_ctrl_i,
    input  wire [8:0]  core_cmd_wl_ctrl_i,
    input  wire [6:0]  core_cmd_line_ctrl_i,
    input  wire [1:0]  core_cmd_bias_profile_i,
    output wire        core_rsp_valid_o,
    input  wire        core_rsp_ready_i,
    output wire        core_rsp_done_o,
    output wire        core_rsp_error_o,
    output wire [7:0]  core_rsp_error_code_o,
    output wire        core_rsp_fail_o,
    output wire        core_rsp_pb_valid_o,

    input  wire        sys_clk,
    input  wire        sys_rst_n,
    output wire        sys_cmd_valid_o,
    input  wire        sys_cmd_ready_i,
    output wire [31:0] sys_cmd_block_o,
    output wire [31:0] sys_cmd_page_o,
    output wire [31:0] sys_cmd_col_o,
    output wire [31:0] sys_cmd_page_bytes_o,
    output wire [31:0] sys_cmd_op_ctrl_o,
    output wire [31:0] sys_cmd_latency_o,
    output wire [7:0]  sys_cmd_vread_level_o,
    output wire [7:0]  sys_cmd_vpgm_level_o,
    output wire [7:0]  sys_cmd_vpass_level_o,
    output wire [7:0]  sys_cmd_vers_level_o,
    output wire [2:0]  sys_cmd_bl_ctrl_o,
    output wire [8:0]  sys_cmd_wl_ctrl_o,
    output wire [6:0]  sys_cmd_line_ctrl_o,
    output wire [1:0]  sys_cmd_bias_profile_o,
    input  wire        sys_rsp_valid_i,
    output wire        sys_rsp_ready_o,
    input  wire        sys_rsp_done_i,
    input  wire        sys_rsp_error_i,
    input  wire [7:0]  sys_rsp_error_code_i,
    input  wire        sys_rsp_fail_i,
    input  wire        sys_rsp_pb_valid_i
);

    localparam integer CMD_PAYLOAD_WIDTH = 245;
    localparam integer RSP_PAYLOAD_WIDTH = 12;

    wire [CMD_PAYLOAD_WIDTH-1:0] core_cmd_payload;
    wire [CMD_PAYLOAD_WIDTH-1:0] sys_cmd_payload;
    wire [RSP_PAYLOAD_WIDTH-1:0] sys_rsp_payload;
    wire [RSP_PAYLOAD_WIDTH-1:0] core_rsp_payload;

    assign core_cmd_payload = {
        core_cmd_bias_profile_i,
        core_cmd_line_ctrl_i,
        core_cmd_wl_ctrl_i,
        core_cmd_bl_ctrl_i,
        core_cmd_vers_level_i,
        core_cmd_vpass_level_i,
        core_cmd_vpgm_level_i,
        core_cmd_vread_level_i,
        core_cmd_latency_i,
        core_cmd_op_ctrl_i,
        core_cmd_page_bytes_i,
        core_cmd_col_i,
        core_cmd_page_i,
        core_cmd_block_i
    };

    assign {
        sys_cmd_bias_profile_o,
        sys_cmd_line_ctrl_o,
        sys_cmd_wl_ctrl_o,
        sys_cmd_bl_ctrl_o,
        sys_cmd_vers_level_o,
        sys_cmd_vpass_level_o,
        sys_cmd_vpgm_level_o,
        sys_cmd_vread_level_o,
        sys_cmd_latency_o,
        sys_cmd_op_ctrl_o,
        sys_cmd_page_bytes_o,
        sys_cmd_col_o,
        sys_cmd_page_o,
        sys_cmd_block_o
    } = sys_cmd_payload;

    assign sys_rsp_payload = {
        sys_rsp_pb_valid_i,
        sys_rsp_fail_i,
        sys_rsp_error_code_i,
        sys_rsp_error_i,
        sys_rsp_done_i
    };

    assign {
        core_rsp_pb_valid_o,
        core_rsp_fail_o,
        core_rsp_error_code_o,
        core_rsp_error_o,
        core_rsp_done_o
    } = core_rsp_payload;

    nand_cdc_payload_adapter #(
        .PAYLOAD_WIDTH(CMD_PAYLOAD_WIDTH)
    ) u_cmd_cdc (
        .src_clk(core_clk),
        .src_rst_n(core_rst_n),
        .src_valid_i(core_cmd_valid_i),
        .src_ready_o(core_cmd_ready_o),
        .src_payload_i(core_cmd_payload),
        .dst_clk(sys_clk),
        .dst_rst_n(sys_rst_n),
        .dst_valid_o(sys_cmd_valid_o),
        .dst_ready_i(sys_cmd_ready_i),
        .dst_payload_o(sys_cmd_payload)
    );

    nand_cdc_payload_adapter #(
        .PAYLOAD_WIDTH(RSP_PAYLOAD_WIDTH)
    ) u_rsp_cdc (
        .src_clk(sys_clk),
        .src_rst_n(sys_rst_n),
        .src_valid_i(sys_rsp_valid_i),
        .src_ready_o(sys_rsp_ready_o),
        .src_payload_i(sys_rsp_payload),
        .dst_clk(core_clk),
        .dst_rst_n(core_rst_n),
        .dst_valid_o(core_rsp_valid_o),
        .dst_ready_i(core_rsp_ready_i),
        .dst_payload_o(core_rsp_payload)
    );

endmodule

module nand_read_output_mirror_adapter (
    input  wire       core_clk,
    input  wire       core_rst_n,
    input  wire [7:0] core_readout_ctrl_i,
    input  wire [7:0] core_readout_id_addr_i,
    input  wire [7:0] core_nand_status_i,
    input  wire       core_ptr_reset_pulse_i,

    input  wire       sys_clk,
    input  wire       sys_rst_n,
    output reg  [7:0] sys_readout_ctrl_o,
    output reg  [7:0] sys_readout_id_addr_o,
    output reg  [7:0] sys_nand_status_o,
    output reg        sys_ptr_reset_pulse_o
);

    localparam integer MIRROR_PAYLOAD_WIDTH = 25;

    reg  [MIRROR_PAYLOAD_WIDTH-1:0] pending_payload_q;
    reg  [23:0]                     mirrored_payload_q;
    reg                             pending_valid_q;
    wire                            pending_ready;
    wire [MIRROR_PAYLOAD_WIDTH-1:0] current_payload;
    wire [MIRROR_PAYLOAD_WIDTH-1:0] sys_payload;
    wire                            sys_valid;
    wire                            mirror_update;
    wire                            pending_ptr_reset;

    assign current_payload = {
        core_ptr_reset_pulse_i,
        core_nand_status_i,
        core_readout_id_addr_i,
        core_readout_ctrl_i
    };
    assign mirror_update = (current_payload[23:0] != mirrored_payload_q) ||
                           core_ptr_reset_pulse_i;
    assign pending_ptr_reset = pending_valid_q && !pending_ready &&
                               pending_payload_q[24];

    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            pending_payload_q <= {MIRROR_PAYLOAD_WIDTH{1'b0}};
            mirrored_payload_q <= 24'h000000;
            pending_valid_q <= 1'b0;
        end else begin
            if (pending_valid_q && pending_ready) begin
                mirrored_payload_q <= pending_payload_q[23:0];
                pending_valid_q <= 1'b0;
            end

            if (mirror_update) begin
                pending_payload_q <= {
                    core_ptr_reset_pulse_i || pending_ptr_reset,
                    core_nand_status_i,
                    core_readout_id_addr_i,
                    core_readout_ctrl_i
                };
                pending_valid_q <= 1'b1;
            end
        end
    end

    nand_cdc_payload_adapter #(
        .PAYLOAD_WIDTH(MIRROR_PAYLOAD_WIDTH)
    ) u_readout_mirror_cdc (
        .src_clk(core_clk),
        .src_rst_n(core_rst_n),
        .src_valid_i(pending_valid_q),
        .src_ready_o(pending_ready),
        .src_payload_i(pending_payload_q),
        .dst_clk(sys_clk),
        .dst_rst_n(sys_rst_n),
        .dst_valid_o(sys_valid),
        .dst_ready_i(1'b1),
        .dst_payload_o(sys_payload)
    );

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            sys_readout_ctrl_o <= 8'h00;
            sys_readout_id_addr_o <= 8'h00;
            sys_nand_status_o <= 8'h00;
            sys_ptr_reset_pulse_o <= 1'b0;
        end else begin
            sys_ptr_reset_pulse_o <= 1'b0;

            if (sys_valid) begin
                sys_readout_ctrl_o <= sys_payload[7:0];
                sys_readout_id_addr_o <= sys_payload[15:8];
                sys_nand_status_o <= sys_payload[23:16];
                sys_ptr_reset_pulse_o <= sys_payload[24];
            end
        end
    end

endmodule

`default_nettype wire
