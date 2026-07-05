`timescale 1ns/1ps
`default_nettype none

// Purpose: PicoRV32-based control agent for the NAND Register Bank cpu_* MMIO
// slot.
// Role: Synthesizable-style RV32 integration wrapper with simulation SRAM
// firmware image loading.
// Related design docs:
// - design_spec/Architecture.md
// - design_spec/nand_control_fw.md
// - design_spec/nand_picorv32.md
// Block contract: Instantiates the vanilla PicoRV32 core, decodes its native
// memory bus into local firmware SRAM and the existing NAND Register Bank MMIO
// window, and connects Register Bank irq_o to a PicoRV32 IRQ bit.
// File version: v0.3
// Revision history:
// - v0.3: Update PicoRV32 reference to NAND-owned vendored core
//   integration documentation.
// - v0.2: Add FW-ready indication after IRQ enable MMIO write so
//   the top can hold host traffic off until the RV32 agent is initialized.
// - v0.1: Initial RV32 control-agent wrapper for NAND FW bring-up.

module nand_rv32_control_agent #(
    parameter [31:0]  REG_BASE    = 32'h0200_0000,
    parameter integer SRAM_WORDS  = 8192,
    parameter [31:0]  STACKADDR   = 32'h0000_8000,
    parameter         FW_HEX_FILE = "build/nand/nand_control_fw.hex"
) (
    input  wire        core_clk,
    input  wire        core_rst_n,
    input  wire        enable_i,
    input  wire        irq_i,

    output wire        cpu_valid_o,
    output wire [31:0] cpu_addr_o,
    output wire [31:0] cpu_wdata_o,
    output wire [ 3:0] cpu_wstrb_o,
    input  wire [31:0] cpu_rdata_i,
    input  wire        cpu_ready_i,

    output reg         fw_ready_o,
    output wire        trap_o
);

    localparam [31:0] NOP_INSN = 32'h0000_0013;
    localparam [31:0] REG_IRQ_ENABLE_ADDR = REG_BASE + 32'h0000_0028;

    wire        cpu_resetn;
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [ 3:0] mem_wstrb;
    wire [31:0] mem_rdata;
    wire [31:0] irq_bus;
    wire [31:0] eoi;

    wire        reg_sel;
    wire        sram_sel;
    wire [31:0] sram_word_addr;
    wire        reg_new_req;
    wire        reg_active_req;
    wire [31:0] reg_active_addr;
    wire [31:0] reg_active_wdata;
    wire [ 3:0] reg_active_wstrb;
    wire        reg_active_write;
    wire        fw_irq_enable_write;
    wire        sram_req;

    reg         reg_wait_q;
    reg         reg_ready_q;
    reg [31:0] reg_addr_q;
    reg [31:0] reg_wdata_q;
    reg [ 3:0] reg_wstrb_q;
    reg [31:0] reg_rdata_q;

    reg         sram_ready_q;
    reg [31:0] sram_rdata_q;
    reg [31:0] sram [0:SRAM_WORDS-1];

    integer i;

    assign cpu_resetn = core_rst_n && enable_i;

    assign reg_sel = (mem_addr[31:12] == REG_BASE[31:12]);
    assign sram_word_addr = {2'b00, mem_addr[31:2]};
    assign sram_sel = !reg_sel && (sram_word_addr < SRAM_WORDS);

    assign reg_new_req = mem_valid && reg_sel && !reg_wait_q && !reg_ready_q;
    assign reg_active_req = reg_wait_q || reg_new_req;
    assign reg_active_addr = reg_wait_q ? reg_addr_q : mem_addr;
    assign reg_active_wdata = reg_wait_q ? reg_wdata_q : mem_wdata;
    assign reg_active_wstrb = reg_wait_q ? reg_wstrb_q : mem_wstrb;
    assign reg_active_write = |reg_active_wstrb;
    assign fw_irq_enable_write = reg_active_req && cpu_ready_i &&
                                 reg_active_write &&
                                 (reg_active_addr == REG_IRQ_ENABLE_ADDR) &&
                                 ((reg_active_wdata & 32'h0000_0007) !=
                                  32'h0000_0000);

    assign cpu_valid_o = reg_active_req;
    assign cpu_addr_o = reg_active_addr;
    assign cpu_wdata_o = reg_active_wdata;
    assign cpu_wstrb_o = reg_active_wstrb;

    assign sram_req = mem_valid && sram_sel && !sram_ready_q;
    assign mem_ready = reg_sel ? reg_ready_q : sram_ready_q;
    assign mem_rdata = reg_sel ? reg_rdata_q : sram_rdata_q;

    assign irq_bus[2:0] = 3'b000;
    assign irq_bus[3] = irq_i;
    assign irq_bus[31:4] = 28'h0000000;

    initial begin
        for (i = 0; i < SRAM_WORDS; i = i + 1) begin
            sram[i] = NOP_INSN;
        end
        $readmemh(FW_HEX_FILE, sram);
    end

    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            reg_wait_q <= 1'b0;
            reg_ready_q <= 1'b0;
            reg_addr_q <= 32'h0000_0000;
            reg_wdata_q <= 32'h0000_0000;
            reg_wstrb_q <= 4'b0000;
            reg_rdata_q <= 32'h0000_0000;
            fw_ready_o <= 1'b0;
        end else begin
            reg_ready_q <= 1'b0;

            if (reg_new_req && !cpu_ready_i) begin
                reg_wait_q <= 1'b1;
                reg_addr_q <= mem_addr;
                reg_wdata_q <= mem_wdata;
                reg_wstrb_q <= mem_wstrb;
            end

            if (reg_active_req && cpu_ready_i) begin
                reg_rdata_q <= cpu_rdata_i;
                reg_ready_q <= 1'b1;
                reg_wait_q <= 1'b0;
            end

            if (fw_irq_enable_write) begin
                fw_ready_o <= 1'b1;
            end
        end
    end

    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            sram_ready_q <= 1'b0;
            sram_rdata_q <= 32'h0000_0000;
        end else begin
            sram_ready_q <= 1'b0;
            sram_rdata_q <= NOP_INSN;

            if (sram_req) begin
                sram_ready_q <= 1'b1;
                sram_rdata_q <= sram[sram_word_addr];
                if (mem_wstrb[0])
                    sram[sram_word_addr][ 7: 0] <= mem_wdata[ 7: 0];
                if (mem_wstrb[1])
                    sram[sram_word_addr][15: 8] <= mem_wdata[15: 8];
                if (mem_wstrb[2])
                    sram[sram_word_addr][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3])
                    sram[sram_word_addr][31:24] <= mem_wdata[31:24];
            end
        end
    end

    picorv32 #(
        .ENABLE_COUNTERS(0),
        .ENABLE_COUNTERS64(0),
        .ENABLE_REGS_16_31(1),
        .ENABLE_REGS_DUALPORT(1),
        .COMPRESSED_ISA(0),
        .ENABLE_IRQ(1),
        .ENABLE_IRQ_QREGS(0),
        .ENABLE_IRQ_TIMER(0),
        .MASKED_IRQ(32'h0000_0000),
        .LATCHED_IRQ(32'hffff_ffff),
        .PROGADDR_RESET(32'h0000_0000),
        .PROGADDR_IRQ(32'h0000_0010),
        .STACKADDR(STACKADDR)
    ) u_cpu (
        .clk(core_clk),
        .resetn(cpu_resetn),
        .trap(trap_o),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .mem_la_read(),
        .mem_la_write(),
        .mem_la_addr(),
        .mem_la_wdata(),
        .mem_la_wstrb(),
        .pcpi_valid(),
        .pcpi_insn(),
        .pcpi_rs1(),
        .pcpi_rs2(),
        .pcpi_wr(1'b0),
        .pcpi_rd(32'h0000_0000),
        .pcpi_wait(1'b0),
        .pcpi_ready(1'b0),
        .irq(irq_bus),
        .eoi(eoi),
        .trace_valid(),
        .trace_data()
    );

endmodule

`default_nettype wire
