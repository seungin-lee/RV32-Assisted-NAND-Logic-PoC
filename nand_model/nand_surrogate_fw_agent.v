`timescale 1ns/1ps
`default_nettype none

`include "nand_parameters.vh"
`include "onfi_sdr_defs.vh"

// Purpose: Simulation-only surrogate FW agent for the NAND Register Bank.
// Role: Behavioral testbench model, not synthesizable RTL.
// Related design docs:
// - design_spec/nand_control_fw.md
// - design_spec/nand_register_bank.md
// - design_spec/nand_model_vpl.md
// Block contract: Uses the same Register Bank MMIO/IRQ contract as the RV32
// control FW: it waits for irq_o or polls REG_IRQ_STATUS, reads the host
// mailbox via MMIO, writes VPL/readout control registers, and clears handled
// IRQ/status bits through the documented W1C/clear registers.
// File version: v0.2
// Revision history:
// - v0.2: Reword the block contract now that the RV32 control path
//   is implemented alongside the surrogate path.
// - v0.1: Initial IRQ-driven behavioral FW agent for Register Bank
//   MMIO command dispatch.

module nand_surrogate_fw_agent #(
    parameter [31:0] REG_BASE = 32'h0200_0000
) (
    input  wire        core_clk,
    input  wire        core_rst_n,

    input  wire        enable_i,
    input  wire        irq_i,

    output reg         cpu_valid_o,
    output reg  [31:0] cpu_addr_o,
    output reg  [31:0] cpu_wdata_o,
    output reg  [ 3:0] cpu_wstrb_o,
    input  wire [31:0] cpu_rdata_i,
    input  wire        cpu_ready_i
);

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
    localparam [31:0] REG_OP_CTRL         = REG_BASE + 32'h0000_0040;
    localparam [31:0] REG_OP_TRIGGER      = REG_BASE + 32'h0000_0044;
    localparam [31:0] REG_OP_STATUS       = REG_BASE + 32'h0000_0048;
    localparam [31:0] REG_OP_STATUS_CLR   = REG_BASE + 32'h0000_004c;
    localparam [31:0] REG_OP_ERROR        = REG_BASE + 32'h0000_0050;
    localparam [31:0] REG_READOUT_CTRL    = REG_BASE + 32'h0000_0058;
    localparam [31:0] REG_VREAD_LEVEL     = REG_BASE + 32'h0000_0060;
    localparam [31:0] REG_VPGM_LEVEL      = REG_BASE + 32'h0000_0064;
    localparam [31:0] REG_VPASS_LEVEL     = REG_BASE + 32'h0000_0068;
    localparam [31:0] REG_VERS_LEVEL      = REG_BASE + 32'h0000_006c;
    localparam [31:0] REG_BL_CTRL         = REG_BASE + 32'h0000_0070;
    localparam [31:0] REG_WL_CTRL         = REG_BASE + 32'h0000_0074;
    localparam [31:0] REG_LINE_CTRL       = REG_BASE + 32'h0000_0078;
    localparam [31:0] REG_BIAS_PROFILE    = REG_BASE + 32'h0000_007c;

    localparam [2:0] OP_CODE_NONE    = 3'd0;
    localparam [2:0] OP_CODE_READ    = 3'd1;
    localparam [2:0] OP_CODE_PROGRAM = 3'd2;
    localparam [2:0] OP_CODE_ERASE   = 3'd3;

    localparam [1:0] BIAS_NONE    = 2'd0;
    localparam [1:0] BIAS_READ    = 2'd1;
    localparam [1:0] BIAS_PROGRAM = 2'd2;
    localparam [1:0] BIAS_ERASE   = 2'd3;

    localparam [2:0] READOUT_NONE        = 3'd0;
    localparam [2:0] READOUT_READ_ID     = 3'd1;
    localparam [2:0] READOUT_READ_STATUS = 3'd2;
    localparam [2:0] READOUT_PAGE_BUFFER = 3'd3;

    localparam [7:0] ERR_PB_NOT_READY = 8'h05;

    reg [3:0]  host_op;
    reg [7:0]  host_cmd;
    reg [7:0]  host_addr0;
    reg [7:0]  host_addr1;
    reg [7:0]  host_addr2;
    reg [7:0]  host_addr3;
    reg [7:0]  host_addr4;
    reg [2:0]  host_addr_count;
    reg [12:0] host_data_count;
    reg        host_protocol_error;
    reg [3:0]  host_protocol_error_code;

    reg [31:0] col_addr;
    reg [31:0] row_addr;
    reg [31:0] block_idx;
    reg [31:0] page_idx;
    reg [3:0]  current_vpl_op;
    reg        fw_busy;

    task automatic fw_write32;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(negedge core_clk);
            cpu_addr_o = addr;
            cpu_wdata_o = data;
            cpu_wstrb_o = 4'b1111;
            cpu_valid_o = 1'b1;
            @(negedge core_clk);
            while (!cpu_ready_i) begin
                @(negedge core_clk);
            end
            cpu_valid_o = 1'b0;
            cpu_wstrb_o = 4'b0000;
            cpu_addr_o = 32'h0000_0000;
            cpu_wdata_o = 32'h0000_0000;
        end
    endtask

    task automatic fw_read32;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(negedge core_clk);
            cpu_addr_o = addr;
            cpu_wdata_o = 32'h0000_0000;
            cpu_wstrb_o = 4'b0000;
            cpu_valid_o = 1'b1;
            #1;
            data = cpu_rdata_i;
            @(negedge core_clk);
            while (!cpu_ready_i) begin
                @(negedge core_clk);
            end
            cpu_valid_o = 1'b0;
            cpu_addr_o = 32'h0000_0000;
        end
    endtask

    task automatic fw_clear_irq;
        input [2:0] irq_bits;
        begin
            if (irq_bits != 3'b000) begin
                fw_write32(REG_IRQ_STATUS, {29'h00000000, irq_bits});
            end
        end
    endtask

    task automatic fw_clear_op_status;
        input [3:0] clear_bits;
        begin
            if (clear_bits != 4'b0000) begin
                fw_write32(REG_OP_STATUS_CLR, {28'h0000000, clear_bits});
            end
        end
    endtask

    task automatic fw_read_host_mailbox;
        reg [31:0] value;
        begin
            fw_read32(REG_HOST_EVENT, value);
            fw_read32(REG_HOST_META, value);
            host_op = value[3:0];
            host_addr_count = value[6:4];
            host_protocol_error = value[7];
            host_protocol_error_code = value[11:8];

            fw_read32(REG_HOST_CMD, value);
            host_cmd = value[7:0];
            fw_read32(REG_HOST_ADDR0, value);
            host_addr0 = value[7:0];
            fw_read32(REG_HOST_ADDR1, value);
            host_addr1 = value[7:0];
            fw_read32(REG_HOST_ADDR2, value);
            host_addr2 = value[7:0];
            fw_read32(REG_HOST_ADDR3, value);
            host_addr3 = value[7:0];
            fw_read32(REG_HOST_ADDR4, value);
            host_addr4 = value[7:0];
            fw_read32(REG_HOST_DATA_COUNT, value);
            host_data_count = value[12:0];
        end
    endtask

    task automatic fw_decode_page_addr;
        begin
            col_addr = {24'h000000, host_addr0} |
                       ({24'h000000, host_addr1} << 8);
            row_addr = {24'h000000, host_addr2} |
                       ({24'h000000, host_addr3} << 8) |
                       ({24'h000000, host_addr4} << 16);
            block_idx = row_addr / `NAND_PAGES_PER_BLOCK;
            page_idx = row_addr % `NAND_PAGES_PER_BLOCK;
        end
    endtask

    task automatic fw_decode_erase_addr;
        begin
            row_addr = {24'h000000, host_addr0} |
                       ({24'h000000, host_addr1} << 8) |
                       ({24'h000000, host_addr2} << 16);
            block_idx = row_addr / `NAND_PAGES_PER_BLOCK;
            page_idx = row_addr % `NAND_PAGES_PER_BLOCK;
            col_addr = 32'h0000_0000;
        end
    endtask

    task automatic fw_setup_read_bias;
        begin
            fw_write32(REG_VREAD_LEVEL, 32'h0000_0001);
            fw_write32(REG_VPASS_LEVEL, 32'h0000_0001);
            fw_write32(REG_BL_CTRL, 32'h0000_0003);
            fw_write32(REG_WL_CTRL, 32'h0000_0011);
            fw_write32(REG_LINE_CTRL, 32'h0000_000f);
            fw_write32(REG_BIAS_PROFILE, {30'h00000000, BIAS_READ});
        end
    endtask

    task automatic fw_setup_program_bias;
        begin
            fw_write32(REG_VPGM_LEVEL, 32'h0000_0010);
            fw_write32(REG_VPASS_LEVEL, 32'h0000_000a);
            fw_write32(REG_BL_CTRL, 32'h0000_0004);
            fw_write32(REG_WL_CTRL, 32'h0000_0022);
            fw_write32(REG_LINE_CTRL, 32'h0000_000f);
            fw_write32(REG_BIAS_PROFILE, {30'h00000000, BIAS_PROGRAM});
        end
    endtask

    task automatic fw_setup_erase_bias;
        begin
            fw_write32(REG_VERS_LEVEL, 32'h0000_0014);
            fw_write32(REG_BL_CTRL, 32'h0000_0000);
            fw_write32(REG_WL_CTRL, 32'h0000_0100);
            fw_write32(REG_LINE_CTRL, 32'h0000_0071);
            fw_write32(REG_BIAS_PROFILE, {30'h00000000, BIAS_ERASE});
        end
    endtask

    task automatic fw_start_vpl_op;
        input [2:0] opcode;
        input [31:0] options;
        begin
            fw_write32(REG_BLOCK_SEL, block_idx);
            fw_write32(REG_PAGE_SEL, page_idx);
            fw_write32(REG_COL_SEL, col_addr);
            fw_write32(REG_OP_CTRL, options | {29'h00000000, opcode});
            fw_write32(REG_OP_TRIGGER, 32'h0000_0001);
        end
    endtask

    task automatic fw_handle_reset;
        begin
            current_vpl_op = `ONFI_OP_RESET;
            fw_write32(REG_READOUT_CTRL, {29'h00000000, READOUT_NONE});
            fw_clear_op_status(4'b1111);
            fw_clear_irq(3'b001);
        end
    endtask

    task automatic fw_handle_read_id;
        begin
            current_vpl_op = `ONFI_OP_READ_ID;
            fw_write32(REG_READOUT_CTRL, {28'h0000000, 1'b0, READOUT_READ_ID | 3'b100});
            fw_clear_irq(3'b001);
        end
    endtask

    task automatic fw_handle_read_status;
        begin
            current_vpl_op = `ONFI_OP_READ_STATUS;
            fw_write32(REG_READOUT_CTRL, {28'h0000000, 1'b0, READOUT_READ_STATUS | 3'b100});
            fw_clear_irq(3'b001);
        end
    endtask

    task automatic fw_handle_read_page;
        begin
            fw_decode_page_addr();
            fw_setup_read_bias();
            fw_start_vpl_op(OP_CODE_READ, 32'h0001_0200);
            current_vpl_op = `ONFI_OP_READ_PAGE;
            fw_clear_irq(3'b001);
        end
    endtask

    task automatic fw_handle_program;
        reg [31:0] op_status;
        begin
            fw_decode_page_addr();
            fw_read32(REG_OP_STATUS, op_status);
            if (!op_status[4] || op_status[5]) begin
                $display("[FW] PROGRAM skipped pb_ready=%0d pb_overflow=%0d time=%0t",
                         op_status[4], op_status[5], $time);
                fw_clear_irq(3'b001);
            end else begin
                fw_setup_program_bias();
                fw_start_vpl_op(OP_CODE_PROGRAM, 32'h0003_0700);
                current_vpl_op = `ONFI_OP_PROGRAM;
                fw_clear_irq(3'b001);
            end
        end
    endtask

    task automatic fw_handle_erase;
        begin
            fw_decode_erase_addr();
            fw_setup_erase_bias();
            fw_start_vpl_op(OP_CODE_ERASE, 32'h0003_0600);
            current_vpl_op = `ONFI_OP_ERASE;
            fw_clear_irq(3'b001);
        end
    endtask

    task automatic fw_handle_host_irq;
        begin
            fw_read_host_mailbox();
            if (host_protocol_error) begin
                $display("[FW] protocol error cmd=0x%02x code=0x%01x time=%0t",
                         host_cmd, host_protocol_error_code, $time);
                fw_clear_irq(3'b001);
            end else begin
                case (host_op)
                    `ONFI_OP_RESET:       fw_handle_reset();
                    `ONFI_OP_READ_ID:     fw_handle_read_id();
                    `ONFI_OP_READ_STATUS: fw_handle_read_status();
                    `ONFI_OP_READ_PAGE:   fw_handle_read_page();
                    `ONFI_OP_PROGRAM:     fw_handle_program();
                    `ONFI_OP_ERASE:       fw_handle_erase();
                    default: begin
                        $display("[FW] unsupported decoded_op=%0d cmd=0x%02x time=%0t",
                                 host_op, host_cmd, $time);
                        fw_clear_irq(3'b001);
                    end
                endcase
            end
        end
    endtask

    task automatic fw_handle_vpl_irq;
        input [2:0] irq_status;
        reg [31:0] op_status;
        reg [31:0] op_error;
        reg [31:0] nand_status;
        reg [3:0]  op_clear;
        begin
            fw_read32(REG_OP_STATUS, op_status);
            fw_read32(REG_OP_ERROR, op_error);
            fw_read32(REG_NAND_STATUS, nand_status);

            $display("[FW] VPL irq status=0x%01x op_status=0x%02x op_error=0x%02x nand_status=0x%02x time=%0t",
                     irq_status, op_status[5:0], op_error[7:0],
                     nand_status[7:0], $time);

            if (op_status[1] && current_vpl_op == `ONFI_OP_READ_PAGE &&
                !op_status[2]) begin
                fw_write32(REG_READOUT_CTRL,
                           {28'h0000000, 1'b0, READOUT_PAGE_BUFFER | 3'b100});
            end

            op_clear = 4'b0000;
            if (op_status[1]) begin
                op_clear[0] = 1'b1;
            end
            if (op_status[2]) begin
                op_clear[1] = 1'b1;
            end
            if (op_status[3]) begin
                op_clear[2] = 1'b1;
            end
            if (op_status[1] && current_vpl_op == `ONFI_OP_PROGRAM &&
                !op_status[2]) begin
                op_clear[3] = 1'b1;
            end
            fw_clear_op_status(op_clear);
            fw_clear_irq(irq_status & 3'b110);
            current_vpl_op = `ONFI_OP_NONE;
        end
    endtask

    task automatic fw_handle_irq;
        reg [31:0] irq_status_value;
        reg [2:0]  pending;
        begin
            fw_read32(REG_IRQ_STATUS, irq_status_value);
            pending = irq_status_value[2:0];
            if (pending[0]) begin
                fw_handle_host_irq();
            end
            if (pending[2:1] != 2'b00) begin
                fw_handle_vpl_irq(pending);
            end
        end
    endtask

    initial begin
        cpu_valid_o = 1'b0;
        cpu_addr_o = 32'h0000_0000;
        cpu_wdata_o = 32'h0000_0000;
        cpu_wstrb_o = 4'b0000;
        host_op = `ONFI_OP_NONE;
        host_cmd = 8'h00;
        host_addr0 = 8'h00;
        host_addr1 = 8'h00;
        host_addr2 = 8'h00;
        host_addr3 = 8'h00;
        host_addr4 = 8'h00;
        host_addr_count = 3'd0;
        host_data_count = 13'd0;
        host_protocol_error = 1'b0;
        host_protocol_error_code = `ONFI_ERR_NONE;
        col_addr = 32'h0000_0000;
        row_addr = 32'h0000_0000;
        block_idx = 32'h0000_0000;
        page_idx = 32'h0000_0000;
        current_vpl_op = `ONFI_OP_NONE;
        fw_busy = 1'b0;

        wait (core_rst_n == 1'b1);
        @(posedge core_clk);
        fw_write32(REG_IRQ_ENABLE, 32'h0000_0007);

        forever begin
            wait (enable_i && irq_i);
            fw_busy = 1'b1;
            fw_handle_irq();
            fw_busy = 1'b0;
            @(posedge core_clk);
        end
    end

endmodule

`default_nettype wire
