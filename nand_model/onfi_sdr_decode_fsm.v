`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"
`include "onfi_sdr_defs.vh"

// Purpose: Decode synchronized ONFI SDR pin-level inputs into transaction
// events and program-data stream requests.
// Role: Synthesizable RTL.
// Related design docs:
// - design_spec/SIMPLE_ONFI_SDR_decode_fsm.md
// - design_spec/FSM_RTL_Design_Guide.md
// - design_spec/SIMPLE_ONFI_SDR_behavior_model_reference.md
// - design_spec/nand_adapter_contracts.md
// Block contract: This block owns ONFI command/address/data bus-cycle
// classification, command sequencing, and registered event/data outputs. It
// does not sample asynchronous host pins directly and does not own FW-visible
// IRQ/W1C state or the Page Buffer array.
// File version: v0.5
// Revision history:
// - v0.5: Remove unused RE#/WP_N inputs and legacy mode outputs;
//   readout source selection is owned by Register Bank/FW control.
// - v0.4: Use shared nand_parameters.vh for ONFI address-cycle
//   constants and timing-checker default cycles.
// - v0.3: Refactored into registered-output hybrid FSM with
//   explicit current/next registers and default-hold next-value logic.
// - v0.2: Switched from raw pin inputs to synchronized pin-level
//   inputs for CDC-aware frontend integration.
// - v0.1: Initial synthesizable Decode FSM core.

module onfi_sdr_decode_fsm #(
    parameter integer CHECK_TIMING_EN = 0,
    parameter integer T_WC_CYCLES     = `NAND_T_WC_CYCLES
) (
    input  wire       sys_clk,
    input  wire       sys_rst_n,

    input  wire [7:0] dq_sync_i,
    input  wire       cle_sync_i,
    input  wire       ale_sync_i,
    input  wire       ce_n_sync_i,
    input  wire       we_rise_i,

    input  wire       host_busy_i,
    input  wire       decode_event_ready_i,
    input  wire       prog_data_ready_i,

    output wire       decode_event_valid_o,
    output wire [3:0] decoded_op_o,
    output wire [7:0] cmd_o,
    output wire [7:0] addr0_o,
    output wire [7:0] addr1_o,
    output wire [7:0] addr2_o,
    output wire [7:0] addr3_o,
    output wire [7:0] addr4_o,
    output wire [2:0] addr_count_o,
    output wire [12:0] prog_data_count_o,

    output wire       prog_data_valid_o,
    output wire [7:0] prog_data_o,

    output wire       protocol_error_o,
    output wire [3:0] protocol_error_code_o,
    output wire       fsm_busy_o,
    output wire [2:0] seq_state_o
);

    localparam [2:0] ST_IDLE         = 3'd0;
    localparam [2:0] ST_COLLECT_ADDR = 3'd1;
    localparam [2:0] ST_WAIT_CONFIRM = 3'd2;
    localparam [2:0] ST_PROG_DATA    = 3'd3;
    localparam [2:0] ST_EVENT_HOLD   = 3'd4;

    localparam [2:0] SEQ_NONE      = 3'd0;
    localparam [2:0] SEQ_READ_ID   = 3'd1;
    localparam [2:0] SEQ_READ_PAGE = 3'd2;
    localparam [2:0] SEQ_PROGRAM   = 3'd3;
    localparam [2:0] SEQ_ERASE     = 3'd4;

    localparam [2:0] READ_ID_ADDR_CYCLES = `NAND_READ_ID_ADDR_CYCLES;
    localparam [2:0] PAGE_ADDR_CYCLES    = `NAND_PAGE_ADDR_CYCLES;
    localparam [2:0] ERASE_ADDR_CYCLES   = `NAND_ERASE_ADDR_CYCLES;

    reg [2:0] state_q;
    reg [2:0] state_d;
    reg [2:0] seq_kind_q;
    reg [2:0] seq_kind_d;
    reg [2:0] addr_target_q;
    reg [2:0] addr_target_d;
    reg [7:0] confirm_cmd_q;
    reg [7:0] confirm_cmd_d;
    reg [3:0] pending_op_q;
    reg [3:0] pending_op_d;
    reg [7:0] start_cmd_q;
    reg [7:0] start_cmd_d;
    reg [7:0] we_gap_count_q;
    reg [7:0] we_gap_count_d;

    reg        decode_event_valid_q;
    reg        decode_event_valid_d;
    reg [3:0]  decoded_op_q;
    reg [3:0]  decoded_op_d;
    reg [7:0]  cmd_q;
    reg [7:0]  cmd_d;
    reg [7:0]  addr0_q;
    reg [7:0]  addr0_d;
    reg [7:0]  addr1_q;
    reg [7:0]  addr1_d;
    reg [7:0]  addr2_q;
    reg [7:0]  addr2_d;
    reg [7:0]  addr3_q;
    reg [7:0]  addr3_d;
    reg [7:0]  addr4_q;
    reg [7:0]  addr4_d;
    reg [2:0]  addr_count_q;
    reg [2:0]  addr_count_d;
    reg [12:0] prog_data_count_q;
    reg [12:0] prog_data_count_d;
    reg        prog_data_valid_q;
    reg        prog_data_valid_d;
    reg [7:0]  prog_data_q;
    reg [7:0]  prog_data_d;
    reg        protocol_error_q;
    reg        protocol_error_d;
    reg [3:0]  protocol_error_code_q;
    reg [3:0]  protocol_error_code_d;
    reg        fsm_busy_q;
    reg        fsm_busy_d;

    wire [7:0] bus_data = dq_sync_i;
    wire       active_write = we_rise_i && !ce_n_sync_i;
    wire       cmd_event = active_write && cle_sync_i && !ale_sync_i;
    wire       addr_event = active_write && !cle_sync_i && ale_sync_i;
    wire       data_in_event = active_write && !cle_sync_i && !ale_sync_i;
    wire       invalid_bus_event = active_write && cle_sync_i && ale_sync_i;
    wire       event_accept = decode_event_valid_q && decode_event_ready_i;
    wire       prog_data_accept = prog_data_valid_q && prog_data_ready_i;
    wire       timing_violation =
        CHECK_TIMING_EN && we_rise_i && (we_gap_count_q < T_WC_CYCLES[7:0]);

    assign decode_event_valid_o = decode_event_valid_q;
    assign decoded_op_o = decoded_op_q;
    assign cmd_o = cmd_q;
    assign addr0_o = addr0_q;
    assign addr1_o = addr1_q;
    assign addr2_o = addr2_q;
    assign addr3_o = addr3_q;
    assign addr4_o = addr4_q;
    assign addr_count_o = addr_count_q;
    assign prog_data_count_o = prog_data_count_q;
    assign prog_data_valid_o = prog_data_valid_q;
    assign prog_data_o = prog_data_q;
    assign protocol_error_o = protocol_error_q;
    assign protocol_error_code_o = protocol_error_code_q;
    assign fsm_busy_o = fsm_busy_q;
    assign seq_state_o = state_q;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state_q <= ST_IDLE;
            seq_kind_q <= SEQ_NONE;
            addr_target_q <= 3'd0;
            confirm_cmd_q <= 8'h00;
            pending_op_q <= `ONFI_OP_NONE;
            start_cmd_q <= 8'h00;
            we_gap_count_q <= 8'hff;
            decode_event_valid_q <= 1'b0;
            decoded_op_q <= `ONFI_OP_NONE;
            cmd_q <= 8'h00;
            addr0_q <= 8'h00;
            addr1_q <= 8'h00;
            addr2_q <= 8'h00;
            addr3_q <= 8'h00;
            addr4_q <= 8'h00;
            addr_count_q <= 3'd0;
            prog_data_count_q <= 13'd0;
            prog_data_valid_q <= 1'b0;
            prog_data_q <= 8'h00;
            protocol_error_q <= 1'b0;
            protocol_error_code_q <= `ONFI_ERR_NONE;
            fsm_busy_q <= 1'b0;
        end else begin
            state_q <= state_d;
            seq_kind_q <= seq_kind_d;
            addr_target_q <= addr_target_d;
            confirm_cmd_q <= confirm_cmd_d;
            pending_op_q <= pending_op_d;
            start_cmd_q <= start_cmd_d;
            we_gap_count_q <= we_gap_count_d;
            decode_event_valid_q <= decode_event_valid_d;
            decoded_op_q <= decoded_op_d;
            cmd_q <= cmd_d;
            addr0_q <= addr0_d;
            addr1_q <= addr1_d;
            addr2_q <= addr2_d;
            addr3_q <= addr3_d;
            addr4_q <= addr4_d;
            addr_count_q <= addr_count_d;
            prog_data_count_q <= prog_data_count_d;
            prog_data_valid_q <= prog_data_valid_d;
            prog_data_q <= prog_data_d;
            protocol_error_q <= protocol_error_d;
            protocol_error_code_q <= protocol_error_code_d;
            fsm_busy_q <= fsm_busy_d;
        end
    end

    always @* begin
        state_d = state_q;
        seq_kind_d = seq_kind_q;
        addr_target_d = addr_target_q;
        confirm_cmd_d = confirm_cmd_q;
        pending_op_d = pending_op_q;
        start_cmd_d = start_cmd_q;
        we_gap_count_d = we_gap_count_q;
        decode_event_valid_d = decode_event_valid_q;
        decoded_op_d = decoded_op_q;
        cmd_d = cmd_q;
        addr0_d = addr0_q;
        addr1_d = addr1_q;
        addr2_d = addr2_q;
        addr3_d = addr3_q;
        addr4_d = addr4_q;
        addr_count_d = addr_count_q;
        prog_data_count_d = prog_data_count_q;
        prog_data_valid_d = prog_data_valid_q;
        prog_data_d = prog_data_q;
        protocol_error_d = protocol_error_q;
        protocol_error_code_d = protocol_error_code_q;

        if (we_gap_count_q != 8'hff) begin
            we_gap_count_d = we_gap_count_q + 8'd1;
        end
        if (we_rise_i) begin
            we_gap_count_d = 8'd0;
        end

        if (prog_data_accept) begin
            prog_data_valid_d = 1'b0;
            prog_data_count_d = prog_data_count_q + 13'd1;
        end

        if (state_q == ST_EVENT_HOLD) begin
            if (event_accept) begin
                decode_event_valid_d = 1'b0;
                state_d = ST_IDLE;
            end
        end else if (timing_violation) begin
            decode_event_valid_d = 1'b1;
            decoded_op_d = `ONFI_OP_UNSUPPORTED;
            cmd_d = bus_data;
            protocol_error_d = 1'b1;
            protocol_error_code_d = `ONFI_ERR_UNEXPECTED_DATA;
            seq_kind_d = SEQ_NONE;
            addr_target_d = 3'd0;
            confirm_cmd_d = 8'h00;
            pending_op_d = `ONFI_OP_NONE;
            start_cmd_d = 8'h00;
            state_d = ST_EVENT_HOLD;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    if (invalid_bus_event) begin
                        decode_event_valid_d = 1'b1;
                        decoded_op_d = `ONFI_OP_UNSUPPORTED;
                        cmd_d = bus_data;
                        protocol_error_d = 1'b1;
                        protocol_error_code_d = `ONFI_ERR_INVALID_BUS;
                        state_d = ST_EVENT_HOLD;
                    end else if (cmd_event) begin
                        addr0_d = 8'h00;
                        addr1_d = 8'h00;
                        addr2_d = 8'h00;
                        addr3_d = 8'h00;
                        addr4_d = 8'h00;
                        addr_count_d = 3'd0;

                        if (host_busy_i && (bus_data != 8'h70) &&
                            (bus_data != 8'hFF)) begin
                            decode_event_valid_d = 1'b1;
                            decoded_op_d = `ONFI_OP_UNSUPPORTED;
                            cmd_d = bus_data;
                            protocol_error_d = 1'b1;
                            protocol_error_code_d = `ONFI_ERR_BUSY_ILLEGAL_CMD;
                            state_d = ST_EVENT_HOLD;
                        end else begin
                            case (bus_data)
                                8'hFF: begin
                                    seq_kind_d = SEQ_NONE;
                                    addr_target_d = 3'd0;
                                    confirm_cmd_d = 8'h00;
                                    pending_op_d = `ONFI_OP_NONE;
                                    start_cmd_d = 8'h00;
                                    prog_data_count_d = 13'd0;
                                    prog_data_valid_d = 1'b0;
                                    decode_event_valid_d = 1'b1;
                                    decoded_op_d = `ONFI_OP_RESET;
                                    cmd_d = 8'hFF;
                                    protocol_error_d = 1'b0;
                                    protocol_error_code_d = `ONFI_ERR_NONE;
                                    state_d = ST_EVENT_HOLD;
                                end
                                8'h70: begin
                                    seq_kind_d = SEQ_NONE;
                                    addr_target_d = 3'd0;
                                    confirm_cmd_d = 8'h00;
                                    pending_op_d = `ONFI_OP_NONE;
                                    start_cmd_d = 8'h00;
                                    decode_event_valid_d = 1'b1;
                                    decoded_op_d = `ONFI_OP_READ_STATUS;
                                    cmd_d = 8'h70;
                                    protocol_error_d = 1'b0;
                                    protocol_error_code_d = `ONFI_ERR_NONE;
                                    state_d = ST_EVENT_HOLD;
                                end
                                8'h90: begin
                                    seq_kind_d = SEQ_READ_ID;
                                    addr_target_d = READ_ID_ADDR_CYCLES;
                                    confirm_cmd_d = 8'h00;
                                    pending_op_d = `ONFI_OP_READ_ID;
                                    start_cmd_d = 8'h90;
                                    cmd_d = 8'h90;
                                    state_d = ST_COLLECT_ADDR;
                                end
                                8'h00: begin
                                    seq_kind_d = SEQ_READ_PAGE;
                                    addr_target_d = PAGE_ADDR_CYCLES;
                                    confirm_cmd_d = 8'h30;
                                    pending_op_d = `ONFI_OP_READ_PAGE;
                                    start_cmd_d = 8'h00;
                                    cmd_d = 8'h00;
                                    state_d = ST_COLLECT_ADDR;
                                end
                                8'h80: begin
                                    prog_data_count_d = 13'd0;
                                    prog_data_valid_d = 1'b0;
                                    seq_kind_d = SEQ_PROGRAM;
                                    addr_target_d = PAGE_ADDR_CYCLES;
                                    confirm_cmd_d = 8'h10;
                                    pending_op_d = `ONFI_OP_PROGRAM;
                                    start_cmd_d = 8'h80;
                                    cmd_d = 8'h80;
                                    state_d = ST_COLLECT_ADDR;
                                end
                                8'h60: begin
                                    seq_kind_d = SEQ_ERASE;
                                    addr_target_d = ERASE_ADDR_CYCLES;
                                    confirm_cmd_d = 8'hD0;
                                    pending_op_d = `ONFI_OP_ERASE;
                                    start_cmd_d = 8'h60;
                                    cmd_d = 8'h60;
                                    state_d = ST_COLLECT_ADDR;
                                end
                                default: begin
                                    seq_kind_d = SEQ_NONE;
                                    decode_event_valid_d = 1'b1;
                                    decoded_op_d = `ONFI_OP_UNSUPPORTED;
                                    cmd_d = bus_data;
                                    protocol_error_d = 1'b1;
                                    protocol_error_code_d = `ONFI_ERR_UNSUPPORTED_CMD;
                                    state_d = ST_EVENT_HOLD;
                                end
                            endcase
                        end
                    end else if (addr_event || data_in_event) begin
                        decode_event_valid_d = 1'b1;
                        decoded_op_d = `ONFI_OP_UNSUPPORTED;
                        cmd_d = bus_data;
                        protocol_error_d = 1'b1;
                        protocol_error_code_d = `ONFI_ERR_UNEXPECTED_DATA;
                        state_d = ST_EVENT_HOLD;
                    end
                end

                ST_COLLECT_ADDR: begin
                    if (invalid_bus_event) begin
                        decode_event_valid_d = 1'b1;
                        decoded_op_d = `ONFI_OP_UNSUPPORTED;
                        cmd_d = bus_data;
                        protocol_error_d = 1'b1;
                        protocol_error_code_d = `ONFI_ERR_INVALID_BUS;
                        state_d = ST_EVENT_HOLD;
                    end else if (addr_event) begin
                        case (addr_count_q)
                            3'd0: addr0_d = bus_data;
                            3'd1: addr1_d = bus_data;
                            3'd2: addr2_d = bus_data;
                            3'd3: addr3_d = bus_data;
                            3'd4: addr4_d = bus_data;
                            default: begin end
                        endcase
                        addr_count_d = addr_count_q + 3'd1;

                        if ((addr_count_q + 3'd1) == addr_target_q) begin
                            if (seq_kind_q == SEQ_READ_ID) begin
                                decode_event_valid_d = 1'b1;
                                decoded_op_d = `ONFI_OP_READ_ID;
                                cmd_d = start_cmd_q;
                                protocol_error_d = 1'b0;
                                protocol_error_code_d = `ONFI_ERR_NONE;
                                seq_kind_d = SEQ_NONE;
                                state_d = ST_EVENT_HOLD;
                            end else if (seq_kind_q == SEQ_PROGRAM) begin
                                state_d = ST_PROG_DATA;
                            end else begin
                                state_d = ST_WAIT_CONFIRM;
                            end
                        end
                    end else if (cmd_event) begin
                        decode_event_valid_d = 1'b1;
                        decoded_op_d = `ONFI_OP_UNSUPPORTED;
                        cmd_d = bus_data;
                        protocol_error_d = 1'b1;
                        protocol_error_code_d = `ONFI_ERR_UNEXPECTED_ADDR;
                        state_d = ST_EVENT_HOLD;
                    end else if (data_in_event) begin
                        decode_event_valid_d = 1'b1;
                        decoded_op_d = `ONFI_OP_UNSUPPORTED;
                        cmd_d = bus_data;
                        protocol_error_d = 1'b1;
                        protocol_error_code_d = `ONFI_ERR_UNEXPECTED_DATA;
                        state_d = ST_EVENT_HOLD;
                    end
                end

                ST_WAIT_CONFIRM: begin
                    if (invalid_bus_event) begin
                        decode_event_valid_d = 1'b1;
                        decoded_op_d = `ONFI_OP_UNSUPPORTED;
                        cmd_d = bus_data;
                        protocol_error_d = 1'b1;
                        protocol_error_code_d = `ONFI_ERR_INVALID_BUS;
                        state_d = ST_EVENT_HOLD;
                    end else if (cmd_event) begin
                        if (bus_data == confirm_cmd_q) begin
                            decode_event_valid_d = 1'b1;
                            decoded_op_d = pending_op_q;
                            cmd_d = bus_data;
                            protocol_error_d = 1'b0;
                            protocol_error_code_d = `ONFI_ERR_NONE;
                            seq_kind_d = SEQ_NONE;
                            state_d = ST_EVENT_HOLD;
                        end else begin
                            decode_event_valid_d = 1'b1;
                            decoded_op_d = `ONFI_OP_UNSUPPORTED;
                            cmd_d = bus_data;
                            protocol_error_d = 1'b1;
                            protocol_error_code_d = `ONFI_ERR_BAD_CONFIRM;
                            state_d = ST_EVENT_HOLD;
                        end
                    end else if (addr_event) begin
                        decode_event_valid_d = 1'b1;
                        decoded_op_d = `ONFI_OP_UNSUPPORTED;
                        cmd_d = bus_data;
                        protocol_error_d = 1'b1;
                        protocol_error_code_d = `ONFI_ERR_UNEXPECTED_ADDR;
                        state_d = ST_EVENT_HOLD;
                    end else if (data_in_event) begin
                        decode_event_valid_d = 1'b1;
                        decoded_op_d = `ONFI_OP_UNSUPPORTED;
                        cmd_d = bus_data;
                        protocol_error_d = 1'b1;
                        protocol_error_code_d = `ONFI_ERR_UNEXPECTED_DATA;
                        state_d = ST_EVENT_HOLD;
                    end
                end

                ST_PROG_DATA: begin
                    if (invalid_bus_event) begin
                        decode_event_valid_d = 1'b1;
                        decoded_op_d = `ONFI_OP_UNSUPPORTED;
                        cmd_d = bus_data;
                        protocol_error_d = 1'b1;
                        protocol_error_code_d = `ONFI_ERR_INVALID_BUS;
                        state_d = ST_EVENT_HOLD;
                    end else if (data_in_event) begin
                        if (!prog_data_valid_q || prog_data_ready_i) begin
                            prog_data_valid_d = 1'b1;
                            prog_data_d = bus_data;
                        end else begin
                            decode_event_valid_d = 1'b1;
                            decoded_op_d = `ONFI_OP_PROGRAM;
                            cmd_d = start_cmd_q;
                            protocol_error_d = 1'b1;
                            protocol_error_code_d = `ONFI_ERR_PB_NOT_READY;
                            state_d = ST_EVENT_HOLD;
                        end
                    end else if (cmd_event) begin
                        if (bus_data == 8'h10) begin
                            decode_event_valid_d = 1'b1;
                            decoded_op_d = `ONFI_OP_PROGRAM;
                            cmd_d = bus_data;
                            if (prog_data_valid_q && !prog_data_ready_i) begin
                                protocol_error_d = 1'b1;
                                protocol_error_code_d = `ONFI_ERR_PB_NOT_READY;
                            end else begin
                                protocol_error_d = 1'b0;
                                protocol_error_code_d = `ONFI_ERR_NONE;
                            end
                            seq_kind_d = SEQ_NONE;
                            state_d = ST_EVENT_HOLD;
                        end else begin
                            decode_event_valid_d = 1'b1;
                            decoded_op_d = `ONFI_OP_UNSUPPORTED;
                            cmd_d = bus_data;
                            protocol_error_d = 1'b1;
                            protocol_error_code_d = `ONFI_ERR_BAD_CONFIRM;
                            state_d = ST_EVENT_HOLD;
                        end
                    end else if (addr_event) begin
                        decode_event_valid_d = 1'b1;
                        decoded_op_d = `ONFI_OP_UNSUPPORTED;
                        cmd_d = bus_data;
                        protocol_error_d = 1'b1;
                        protocol_error_code_d = `ONFI_ERR_UNEXPECTED_ADDR;
                        state_d = ST_EVENT_HOLD;
                    end
                end

                default: begin
                    state_d = ST_IDLE;
                    seq_kind_d = SEQ_NONE;
                end
            endcase
        end

        fsm_busy_d = (state_d != ST_IDLE) || decode_event_valid_d ||
                     prog_data_valid_d || host_busy_i;
    end

endmodule

`default_nettype wire
