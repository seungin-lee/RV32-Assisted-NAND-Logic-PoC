`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"
`include "onfi_sdr_defs.vh"

// Purpose: NAND-specific MMIO Register Bank using the reusable soc_regbank
// core for host event payload capture, W1C IRQ status, and IRQ enable handling.
// Role: Synthesizable RTL.
// Related design docs:
// - design_spec/nand_register_bank.md
// - design_spec/Architecture.md
// - design_spec/nand_picorv32.md
// Block contract: Decode/Host Event Adapter payloads are accepted atomically,
// FW-visible IRQ/W1C state is owned here, and VPL command/result side effects
// are exposed as small hardware handshakes.
// File version: v0.5
// Revision history:
// - v0.5: Update reusable soc_regbank reference to NAND-owned
//   vendored IP documentation.
// - v0.4: Make REG_HOST_EVENT write ignored per RO mailbox view
//   contract; host event clear is only via REG_IRQ_STATUS.HOST_CMD_IRQ W1C.
// - v0.3: Expose accepted Read ID address snapshot for sysclk
//   Read Output Datapath ID table selection.
// - v0.2: Track accepted PROGRAM host data count and use it as
//   PROGRAM VPL transfer byte count instead of always passing full page size.
// - v0.1: Initial NAND Register Bank RTL around PicoRV32
//   soc_regbank payload/IRQ core.

module nand_register_bank #(
    parameter [31:0]  REG_BASE  = 32'h0200_0000,
    parameter integer PAGE_SIZE = `NAND_PAGE_SIZE
) (
    input  wire        core_clk,
    input  wire        core_rst_n,

    input  wire        cpu_valid_i,
    input  wire [31:0] cpu_addr_i,
    input  wire [31:0] cpu_wdata_i,
    input  wire [ 3:0] cpu_wstrb_i,
    output reg  [31:0] cpu_rdata_o,
    output wire        cpu_ready_o,

    input  wire        reg_event_valid_i,
    output wire        reg_event_ready_o,
    input  wire [3:0]  reg_decoded_op_i,
    input  wire [7:0]  reg_cmd_i,
    input  wire [7:0]  reg_addr0_i,
    input  wire [7:0]  reg_addr1_i,
    input  wire [7:0]  reg_addr2_i,
    input  wire [7:0]  reg_addr3_i,
    input  wire [7:0]  reg_addr4_i,
    input  wire [2:0]  reg_addr_count_i,
    input  wire [12:0] reg_prog_data_count_i,
    input  wire        reg_protocol_error_i,
    input  wire [3:0]  reg_protocol_error_code_i,

    input  wire        wp_n_i,
    input  wire        pb_prog_ready_i,
    input  wire        pb_overflow_i,
    output reg         pb_prog_clear_o,

    output reg         vpl_cmd_valid_o,
    input  wire        vpl_cmd_ready_i,
    output reg  [31:0] vpl_cmd_block_o,
    output reg  [31:0] vpl_cmd_page_o,
    output reg  [31:0] vpl_cmd_col_o,
    output reg  [31:0] vpl_cmd_page_bytes_o,
    output reg  [31:0] vpl_cmd_op_ctrl_o,
    output reg  [31:0] vpl_cmd_latency_o,
    output reg  [7:0]  vpl_cmd_vread_level_o,
    output reg  [7:0]  vpl_cmd_vpgm_level_o,
    output reg  [7:0]  vpl_cmd_vpass_level_o,
    output reg  [7:0]  vpl_cmd_vers_level_o,
    output reg  [2:0]  vpl_cmd_bl_ctrl_o,
    output reg  [8:0]  vpl_cmd_wl_ctrl_o,
    output reg  [6:0]  vpl_cmd_line_ctrl_o,
    output reg  [1:0]  vpl_cmd_bias_profile_o,

    input  wire        vpl_rsp_valid_i,
    output wire        vpl_rsp_ready_o,
    input  wire        vpl_rsp_done_i,
    input  wire        vpl_rsp_error_i,
    input  wire [7:0]  vpl_rsp_error_code_i,
    input  wire        vpl_rsp_fail_i,
    input  wire        vpl_rsp_pb_valid_i,

    output wire [7:0]  nand_status_o,
    output wire [5:0]  op_status_o,
    output wire [7:0]  op_error_o,
    output wire [7:0]  readout_ctrl_o,
    output wire [7:0]  readout_id_addr_o,
    output reg         readout_ptr_reset_pulse_o,

    output wire        host_event_pending_o,
    output wire [2:0]  irq_status_o,
    output wire [2:0]  irq_enable_o,
    output wire        irq_o,
    output wire        reg_busy_o,
    output wire        reg_ready_o,
    output wire        access_error_o
);

    localparam integer HOST_PAYLOAD_WORDS = 8;
    localparam integer IRQ_WIDTH          = 3;

    localparam [31:0] PAGE_BYTES_VALUE = PAGE_SIZE;

    localparam [31:0] REG_HOST_CMD        = 32'h0000_0000;
    localparam [31:0] REG_HOST_ADDR0      = 32'h0000_0004;
    localparam [31:0] REG_HOST_ADDR1      = 32'h0000_0008;
    localparam [31:0] REG_HOST_ADDR2      = 32'h0000_000c;
    localparam [31:0] REG_HOST_ADDR3      = 32'h0000_0010;
    localparam [31:0] REG_HOST_ADDR4      = 32'h0000_0014;
    localparam [31:0] REG_HOST_META       = 32'h0000_0018;
    localparam [31:0] REG_HOST_EVENT      = 32'h0000_001c;
    localparam [31:0] REG_NAND_STATUS     = 32'h0000_0020;
    localparam [31:0] REG_IRQ_STATUS      = 32'h0000_0024;
    localparam [31:0] REG_IRQ_ENABLE      = 32'h0000_0028;
    localparam [31:0] REG_HOST_DATA_COUNT = 32'h0000_002c;
    localparam [31:0] REG_BLOCK_SEL       = 32'h0000_0030;
    localparam [31:0] REG_PAGE_SEL        = 32'h0000_0034;
    localparam [31:0] REG_COL_SEL         = 32'h0000_0038;
    localparam [31:0] REG_PAGE_BYTES      = 32'h0000_003c;
    localparam [31:0] REG_OP_CTRL         = 32'h0000_0040;
    localparam [31:0] REG_OP_TRIGGER      = 32'h0000_0044;
    localparam [31:0] REG_OP_STATUS       = 32'h0000_0048;
    localparam [31:0] REG_OP_STATUS_CLR   = 32'h0000_004c;
    localparam [31:0] REG_OP_ERROR        = 32'h0000_0050;
    localparam [31:0] REG_OP_LATENCY      = 32'h0000_0054;
    localparam [31:0] REG_READOUT_CTRL    = 32'h0000_0058;
    localparam [31:0] REG_VREAD_LEVEL     = 32'h0000_0060;
    localparam [31:0] REG_VPGM_LEVEL      = 32'h0000_0064;
    localparam [31:0] REG_VPASS_LEVEL     = 32'h0000_0068;
    localparam [31:0] REG_VERS_LEVEL      = 32'h0000_006c;
    localparam [31:0] REG_BL_CTRL         = 32'h0000_0070;
    localparam [31:0] REG_WL_CTRL         = 32'h0000_0074;
    localparam [31:0] REG_LINE_CTRL       = 32'h0000_0078;
    localparam [31:0] REG_BIAS_PROFILE    = 32'h0000_007c;

    localparam [31:0] CORE_IRQ_STATUS     = 32'h0000_0004;
    localparam [31:0] CORE_IRQ_ENABLE     = 32'h0000_0008;
    localparam [31:0] CORE_PAYLOAD_BASE   = 32'h0000_000c;
    localparam [31:0] CORE_PAYLOAD_CMD    = CORE_PAYLOAD_BASE + 32'd0;
    localparam [31:0] CORE_PAYLOAD_ADDR0  = CORE_PAYLOAD_BASE + 32'd4;
    localparam [31:0] CORE_PAYLOAD_ADDR1  = CORE_PAYLOAD_BASE + 32'd8;
    localparam [31:0] CORE_PAYLOAD_ADDR2  = CORE_PAYLOAD_BASE + 32'd12;
    localparam [31:0] CORE_PAYLOAD_ADDR3  = CORE_PAYLOAD_BASE + 32'd16;
    localparam [31:0] CORE_PAYLOAD_ADDR4  = CORE_PAYLOAD_BASE + 32'd20;
    localparam [31:0] CORE_PAYLOAD_META   = CORE_PAYLOAD_BASE + 32'd24;
    localparam [31:0] CORE_PAYLOAD_COUNT  = CORE_PAYLOAD_BASE + 32'd28;
    localparam [31:0] CORE_IF_STATUS      = 32'h0000_0100;

    localparam [7:0] ERR_NONE = 8'h00;
    localparam [7:0] ERR_BUSY = 8'h02;
    localparam [2:0] OP_CODE_PROGRAM = 3'd2;

    reg [31:0] core_cpu_addr;
    reg [31:0] core_cpu_wdata;
    reg [ 3:0] core_cpu_wstrb;
    reg        core_cpu_valid;
    wire [31:0] core_cpu_rdata;

    wire        core_ext_event_ready;
    wire        core_reg_busy;
    wire        core_reg_ready;
    wire        core_access_error;
    wire [2:0]  core_irq_status;
    wire [2:0]  core_irq_enable;
    wire [2:0]  core_hw_irq_set;

    reg [31:0] block_sel_q;
    reg [31:0] page_sel_q;
    reg [31:0] col_sel_q;
    reg [31:0] op_ctrl_q;
    reg [31:0] op_latency_q;
    reg [2:0]  readout_source_q;
    reg [7:0]  readout_id_addr_q;
    reg [7:0]  vread_level_q;
    reg [7:0]  vpgm_level_q;
    reg [7:0]  vpass_level_q;
    reg [7:0]  vers_level_q;
    reg [2:0]  bl_ctrl_q;
    reg [8:0]  wl_ctrl_q;
    reg [6:0]  line_ctrl_q;
    reg [1:0]  bias_profile_q;
    reg [12:0] host_prog_data_count_q;

    reg        host_event_error_q;
    reg        op_busy_q;
    reg        op_done_q;
    reg        op_error_q;
    reg        op_pb_valid_q;
    reg [7:0]  op_error_code_q;
    reg        nand_fail_q;
    reg        nand_ready_q;
    reg        cmd_irq_done_en_q;
    reg        cmd_irq_error_en_q;

    wire        addr_in_range;
    wire [31:0] reg_addr;
    wire        cpu_write;
    wire        cpu_read;
    wire        full_word_write;
    wire        cpu_write_full;
    wire        host_event_blocked;
    wire        core_ext_event_valid;
    wire        host_event_accept;
    wire        vpl_rsp_accept;
    wire        start_write;
    wire        start_busy_error;
    wire        start_accept;
    wire        op_done_irq_set;
    wire        op_error_irq_set;
    wire [255:0] host_event_payload;

    assign addr_in_range = (cpu_addr_i >= REG_BASE) &&
                           (cpu_addr_i < (REG_BASE + 32'h0000_0080));
    assign reg_addr = cpu_addr_i - REG_BASE;
    assign cpu_write = cpu_valid_i && |cpu_wstrb_i;
    assign cpu_read = cpu_valid_i && !cpu_write;
    assign full_word_write = (cpu_wstrb_i == 4'b1111);
    assign cpu_write_full = addr_in_range && cpu_write && full_word_write;
    assign cpu_ready_o = cpu_valid_i;

    assign host_event_blocked = op_busy_q || op_done_q || op_error_q ||
                                vpl_cmd_valid_o;
    assign core_ext_event_valid = reg_event_valid_i && !host_event_blocked;
    assign reg_event_ready_o = core_ext_event_ready && !host_event_blocked;
    assign host_event_accept = core_ext_event_valid && core_ext_event_ready;

    assign host_event_payload[0*32 +: 32] = {24'h000000, reg_cmd_i};
    assign host_event_payload[1*32 +: 32] = {24'h000000, reg_addr0_i};
    assign host_event_payload[2*32 +: 32] = {24'h000000, reg_addr1_i};
    assign host_event_payload[3*32 +: 32] = {24'h000000, reg_addr2_i};
    assign host_event_payload[4*32 +: 32] = {24'h000000, reg_addr3_i};
    assign host_event_payload[5*32 +: 32] = {24'h000000, reg_addr4_i};
    assign host_event_payload[6*32 +: 32] = {
        20'h00000,
        reg_protocol_error_code_i,
        reg_protocol_error_i,
        reg_addr_count_i,
        reg_decoded_op_i
    };
    assign host_event_payload[7*32 +: 32] = {19'h00000, reg_prog_data_count_i};

    assign vpl_rsp_ready_o = 1'b1;
    assign vpl_rsp_accept = vpl_rsp_valid_i && vpl_rsp_ready_o;

    assign start_write = cpu_write_full &&
                         (reg_addr == REG_OP_TRIGGER) &&
                         cpu_wdata_i[0];
    assign start_busy_error = start_write && (op_busy_q || vpl_cmd_valid_o);
    assign start_accept = start_write && !op_busy_q && !vpl_cmd_valid_o;

    assign op_done_irq_set = vpl_rsp_accept && vpl_rsp_done_i && cmd_irq_done_en_q;
    assign op_error_irq_set = (vpl_rsp_accept && vpl_rsp_error_i && cmd_irq_error_en_q) ||
                              (start_busy_error && op_ctrl_q[17]);
    assign core_hw_irq_set = {op_error_irq_set, op_done_irq_set, 1'b0};

    assign nand_status_o = {wp_n_i, nand_ready_q, 5'b00000, nand_fail_q};
    assign op_status_o = {
        pb_overflow_i,
        pb_prog_ready_i,
        op_pb_valid_q,
        op_error_q,
        op_done_q,
        op_busy_q
    };
    assign op_error_o = op_error_code_q;
    assign readout_ctrl_o = {4'b0000, 1'b0, readout_source_q};
    assign readout_id_addr_o = readout_id_addr_q;

    wire [31:0] vpl_snapshot_page_bytes =
        (op_ctrl_q[2:0] == OP_CODE_PROGRAM) ?
        {19'h00000, host_prog_data_count_q} : PAGE_BYTES_VALUE;

    assign host_event_pending_o = core_irq_status[0];
    assign irq_status_o = core_irq_status;
    assign irq_enable_o = core_irq_enable;
    assign reg_busy_o = core_reg_busy || op_busy_q || op_done_q ||
                        op_error_q || vpl_cmd_valid_o;
    assign reg_ready_o = !reg_busy_o;
    assign access_error_o = core_access_error;

    always @(*) begin
        core_cpu_valid = 1'b0;
        core_cpu_addr = 32'h0000_0000;
        core_cpu_wdata = cpu_wdata_i;
        core_cpu_wstrb = cpu_wstrb_i;

        if (addr_in_range && cpu_read) begin
            case (reg_addr)
                REG_HOST_CMD:        begin core_cpu_valid = 1'b1; core_cpu_addr = CORE_PAYLOAD_CMD; end
                REG_HOST_ADDR0:      begin core_cpu_valid = 1'b1; core_cpu_addr = CORE_PAYLOAD_ADDR0; end
                REG_HOST_ADDR1:      begin core_cpu_valid = 1'b1; core_cpu_addr = CORE_PAYLOAD_ADDR1; end
                REG_HOST_ADDR2:      begin core_cpu_valid = 1'b1; core_cpu_addr = CORE_PAYLOAD_ADDR2; end
                REG_HOST_ADDR3:      begin core_cpu_valid = 1'b1; core_cpu_addr = CORE_PAYLOAD_ADDR3; end
                REG_HOST_ADDR4:      begin core_cpu_valid = 1'b1; core_cpu_addr = CORE_PAYLOAD_ADDR4; end
                REG_HOST_META:       begin core_cpu_valid = 1'b1; core_cpu_addr = CORE_PAYLOAD_META; end
                REG_IRQ_STATUS:      begin core_cpu_valid = 1'b1; core_cpu_addr = CORE_IRQ_STATUS; end
                REG_IRQ_ENABLE:      begin core_cpu_valid = 1'b1; core_cpu_addr = CORE_IRQ_ENABLE; end
                REG_HOST_DATA_COUNT: begin core_cpu_valid = 1'b1; core_cpu_addr = CORE_PAYLOAD_COUNT; end
                default: begin
                end
            endcase
        end else if (cpu_write_full) begin
            case (reg_addr)
                REG_IRQ_STATUS: begin
                    core_cpu_valid = 1'b1;
                    core_cpu_addr = CORE_IRQ_STATUS;
                    core_cpu_wdata = {29'b0, cpu_wdata_i[2:0]};
                    core_cpu_wstrb = 4'b1111;
                end
                REG_IRQ_ENABLE: begin
                    core_cpu_valid = 1'b1;
                    core_cpu_addr = CORE_IRQ_ENABLE;
                    core_cpu_wdata = {29'b0, cpu_wdata_i[2:0]};
                    core_cpu_wstrb = 4'b1111;
                end
                default: begin
                end
            endcase
        end
    end

    always @(*) begin
        cpu_rdata_o = 32'h0000_0000;

        if (addr_in_range) begin
            case (reg_addr)
                REG_HOST_CMD:        cpu_rdata_o = {24'h000000, core_cpu_rdata[7:0]};
                REG_HOST_ADDR0:      cpu_rdata_o = {24'h000000, core_cpu_rdata[7:0]};
                REG_HOST_ADDR1:      cpu_rdata_o = {24'h000000, core_cpu_rdata[7:0]};
                REG_HOST_ADDR2:      cpu_rdata_o = {24'h000000, core_cpu_rdata[7:0]};
                REG_HOST_ADDR3:      cpu_rdata_o = {24'h000000, core_cpu_rdata[7:0]};
                REG_HOST_ADDR4:      cpu_rdata_o = {24'h000000, core_cpu_rdata[7:0]};
                REG_HOST_META:       cpu_rdata_o = core_cpu_rdata;
                REG_HOST_EVENT:      cpu_rdata_o = {30'h00000000, host_event_error_q, core_irq_status[0]};
                REG_NAND_STATUS:     cpu_rdata_o = {24'h000000, nand_status_o};
                REG_IRQ_STATUS:      cpu_rdata_o = {29'h00000000, core_irq_status};
                REG_IRQ_ENABLE:      cpu_rdata_o = {29'h00000000, core_irq_enable};
                REG_HOST_DATA_COUNT: cpu_rdata_o = {19'h00000, core_cpu_rdata[12:0]};
                REG_BLOCK_SEL:       cpu_rdata_o = block_sel_q;
                REG_PAGE_SEL:        cpu_rdata_o = page_sel_q;
                REG_COL_SEL:         cpu_rdata_o = col_sel_q;
                REG_PAGE_BYTES:      cpu_rdata_o = PAGE_BYTES_VALUE;
                REG_OP_CTRL:         cpu_rdata_o = op_ctrl_q;
                REG_OP_STATUS:       cpu_rdata_o = {26'h0000000, op_status_o};
                REG_OP_ERROR:        cpu_rdata_o = {24'h000000, op_error_code_q};
                REG_OP_LATENCY:      cpu_rdata_o = op_latency_q;
                REG_READOUT_CTRL:    cpu_rdata_o = {24'h000000, readout_ctrl_o};
                REG_VREAD_LEVEL:     cpu_rdata_o = {24'h000000, vread_level_q};
                REG_VPGM_LEVEL:      cpu_rdata_o = {24'h000000, vpgm_level_q};
                REG_VPASS_LEVEL:     cpu_rdata_o = {24'h000000, vpass_level_q};
                REG_VERS_LEVEL:      cpu_rdata_o = {24'h000000, vers_level_q};
                REG_BL_CTRL:         cpu_rdata_o = {29'h00000000, bl_ctrl_q};
                REG_WL_CTRL:         cpu_rdata_o = {23'h000000, wl_ctrl_q};
                REG_LINE_CTRL:       cpu_rdata_o = {25'h0000000, line_ctrl_q};
                REG_BIAS_PROFILE:    cpu_rdata_o = {30'h00000000, bias_profile_q};
                default:             cpu_rdata_o = 32'h0000_0000;
            endcase
        end
    end

    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            block_sel_q <= 32'h0000_0000;
            page_sel_q <= 32'h0000_0000;
            col_sel_q <= 32'h0000_0000;
            op_ctrl_q <= 32'h0000_0000;
            op_latency_q <= 32'h0000_0000;
            readout_source_q <= 3'b000;
            readout_id_addr_q <= 8'h00;
            vread_level_q <= 8'h00;
            vpgm_level_q <= 8'h00;
            vpass_level_q <= 8'h00;
            vers_level_q <= 8'h00;
            bl_ctrl_q <= 3'b000;
            wl_ctrl_q <= 9'h000;
            line_ctrl_q <= 7'h00;
            bias_profile_q <= 2'b00;
            host_prog_data_count_q <= 13'd0;
            host_event_error_q <= 1'b0;
            op_busy_q <= 1'b0;
            op_done_q <= 1'b0;
            op_error_q <= 1'b0;
            op_pb_valid_q <= 1'b0;
            op_error_code_q <= ERR_NONE;
            nand_fail_q <= 1'b0;
            nand_ready_q <= 1'b1;
            cmd_irq_done_en_q <= 1'b0;
            cmd_irq_error_en_q <= 1'b0;
            vpl_cmd_valid_o <= 1'b0;
            vpl_cmd_block_o <= 32'h0000_0000;
            vpl_cmd_page_o <= 32'h0000_0000;
            vpl_cmd_col_o <= 32'h0000_0000;
            vpl_cmd_page_bytes_o <= PAGE_BYTES_VALUE;
            vpl_cmd_op_ctrl_o <= 32'h0000_0000;
            vpl_cmd_latency_o <= 32'h0000_0000;
            vpl_cmd_vread_level_o <= 8'h00;
            vpl_cmd_vpgm_level_o <= 8'h00;
            vpl_cmd_vpass_level_o <= 8'h00;
            vpl_cmd_vers_level_o <= 8'h00;
            vpl_cmd_bl_ctrl_o <= 3'b000;
            vpl_cmd_wl_ctrl_o <= 9'h000;
            vpl_cmd_line_ctrl_o <= 7'h00;
            vpl_cmd_bias_profile_o <= 2'b00;
            pb_prog_clear_o <= 1'b0;
            readout_ptr_reset_pulse_o <= 1'b0;
        end else begin
            pb_prog_clear_o <= 1'b0;
            readout_ptr_reset_pulse_o <= 1'b0;

            if (vpl_cmd_valid_o && vpl_cmd_ready_i) begin
                vpl_cmd_valid_o <= 1'b0;
            end

            if (host_event_accept &&
                (reg_decoded_op_i == `ONFI_OP_PROGRAM) &&
                !reg_protocol_error_i) begin
                host_prog_data_count_q <= reg_prog_data_count_i;
            end

            if (host_event_accept &&
                (reg_decoded_op_i == `ONFI_OP_READ_ID) &&
                !reg_protocol_error_i) begin
                readout_id_addr_q <= reg_addr0_i;
            end

            if (cpu_write_full) begin
                case (reg_addr)
                    REG_IRQ_STATUS: begin
                        if (cpu_wdata_i[0]) begin
                            host_event_error_q <= 1'b0;
                        end
                    end
                    REG_BLOCK_SEL:    block_sel_q <= cpu_wdata_i;
                    REG_PAGE_SEL:     page_sel_q <= cpu_wdata_i;
                    REG_COL_SEL:      col_sel_q <= cpu_wdata_i;
                    REG_OP_CTRL:      op_ctrl_q <= cpu_wdata_i & 32'h0003_0707;
                    REG_OP_LATENCY:   op_latency_q <= cpu_wdata_i;
                    REG_READOUT_CTRL: begin
                        readout_source_q <= cpu_wdata_i[2:0];
                        if (cpu_wdata_i[3]) begin
                            readout_ptr_reset_pulse_o <= 1'b1;
                        end
                    end
                    REG_OP_TRIGGER: begin
                        if (cpu_wdata_i[0]) begin
                            if (op_busy_q || vpl_cmd_valid_o) begin
                                op_error_q <= 1'b1;
                                op_error_code_q <= ERR_BUSY;
                                nand_fail_q <= 1'b1;
                            end else begin
                                vpl_cmd_valid_o <= 1'b1;
                                vpl_cmd_block_o <= block_sel_q;
                                vpl_cmd_page_o <= page_sel_q;
                                vpl_cmd_col_o <= col_sel_q;
                                vpl_cmd_page_bytes_o <= vpl_snapshot_page_bytes;
                                vpl_cmd_op_ctrl_o <= op_ctrl_q;
                                vpl_cmd_latency_o <= op_latency_q;
                                vpl_cmd_vread_level_o <= vread_level_q;
                                vpl_cmd_vpgm_level_o <= vpgm_level_q;
                                vpl_cmd_vpass_level_o <= vpass_level_q;
                                vpl_cmd_vers_level_o <= vers_level_q;
                                vpl_cmd_bl_ctrl_o <= bl_ctrl_q;
                                vpl_cmd_wl_ctrl_o <= wl_ctrl_q;
                                vpl_cmd_line_ctrl_o <= line_ctrl_q;
                                vpl_cmd_bias_profile_o <= bias_profile_q;
                                op_busy_q <= 1'b1;
                                op_done_q <= 1'b0;
                                op_error_q <= 1'b0;
                                op_pb_valid_q <= 1'b0;
                                op_error_code_q <= ERR_NONE;
                                nand_fail_q <= 1'b0;
                                nand_ready_q <= 1'b0;
                                cmd_irq_done_en_q <= op_ctrl_q[16];
                                cmd_irq_error_en_q <= op_ctrl_q[17];
                            end
                        end
                    end
                    REG_OP_STATUS_CLR: begin
                        if (cpu_wdata_i[0]) begin
                            op_done_q <= 1'b0;
                        end
                        if (cpu_wdata_i[1]) begin
                            op_error_q <= 1'b0;
                            op_error_code_q <= ERR_NONE;
                        end
                        if (cpu_wdata_i[2]) begin
                            op_pb_valid_q <= 1'b0;
                        end
                        if (cpu_wdata_i[3]) begin
                            pb_prog_clear_o <= 1'b1;
                        end
                    end
                    REG_VREAD_LEVEL:  vread_level_q <= cpu_wdata_i[7:0];
                    REG_VPGM_LEVEL:   vpgm_level_q <= cpu_wdata_i[7:0];
                    REG_VPASS_LEVEL:  vpass_level_q <= cpu_wdata_i[7:0];
                    REG_VERS_LEVEL:   vers_level_q <= cpu_wdata_i[7:0];
                    REG_BL_CTRL:      bl_ctrl_q <= cpu_wdata_i[2:0];
                    REG_WL_CTRL:      wl_ctrl_q <= cpu_wdata_i[8:0];
                    REG_LINE_CTRL:    line_ctrl_q <= cpu_wdata_i[6:0];
                    REG_BIAS_PROFILE: bias_profile_q <= cpu_wdata_i[1:0];
                    default: begin
                    end
                endcase
            end

            if (vpl_rsp_accept) begin
                op_busy_q <= 1'b0;
                if (vpl_rsp_done_i) begin
                    op_done_q <= 1'b1;
                end
                if (vpl_rsp_error_i) begin
                    op_error_q <= 1'b1;
                    op_error_code_q <= vpl_rsp_error_code_i;
                end
                if (vpl_rsp_pb_valid_i) begin
                    op_pb_valid_q <= 1'b1;
                end
                nand_fail_q <= vpl_rsp_fail_i || vpl_rsp_error_i;
                nand_ready_q <= 1'b1;
            end

            if (host_event_accept) begin
                host_event_error_q <= reg_protocol_error_i;
            end
        end
    end

    soc_regbank #(
        .REG_BASE(32'h0000_0000),
        .PAYLOAD_WORDS(HOST_PAYLOAD_WORDS),
        .IRQ_WIDTH(IRQ_WIDTH),
        .IF_STATUS_OFFSET(CORE_IF_STATUS),
        .ID_VALUE(32'h4e41_4e44)
    ) u_core_regbank (
        .clk(core_clk),
        .resetn(core_rst_n),
        .cpu_valid(core_cpu_valid),
        .cpu_addr(core_cpu_addr),
        .cpu_wdata(core_cpu_wdata),
        .cpu_wstrb(core_cpu_wstrb),
        .cpu_rdata(core_cpu_rdata),
        .ext_event_valid(core_ext_event_valid),
        .ext_event_ready(core_ext_event_ready),
        .ext_event_payload(host_event_payload),
        .hw_irq_set_i(core_hw_irq_set),
        .irq_status_out(core_irq_status),
        .irq_enable_out(core_irq_enable),
        .irq_o(irq_o),
        .reg_busy_out(core_reg_busy),
        .reg_ready_out(core_reg_ready),
        .access_error_out(core_access_error)
    );

endmodule

`default_nettype wire
