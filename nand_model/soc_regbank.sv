// Purpose: Reusable register bank core used by the NAND Register Bank wrapper.
// Role: Synthesizable RTL.
// Related design docs:
// - design_spec/nand_register_bank.md
// - design_spec/nand_picorv32.md
// Block contract: Captures parameterized hardware payload words, owns generic
// IRQ_STATUS/IRQ_ENABLE W1C state, and exposes ready/busy/access-error status.
// NAND-specific address remap and side effects stay in nand_register_bank.v.
// File version: v0.1
// Revision history:
// - v0.1: Import reusable soc_regbank into NAND repository.

module soc_regbank #(
    parameter [31:0] REG_BASE = 32'h0200_0000,
    parameter integer PAYLOAD_WORDS = 2,
    parameter integer IRQ_WIDTH = 1,
    parameter [31:0] IF_STATUS_OFFSET = 32'hffff_ffff,
    parameter [31:0] ID_VALUE = 32'h5053_4f43
) (
    input  wire                         clk,
    input  wire                         resetn,

    input  wire                         cpu_valid,
    input  wire [31:0]                  cpu_addr,
    input  wire [31:0]                  cpu_wdata,
    input  wire [ 3:0]                  cpu_wstrb,
    output reg  [31:0]                  cpu_rdata,

    input  wire                         ext_event_valid,
    output wire                         ext_event_ready,
    input  wire [PAYLOAD_WORDS*32-1:0]  ext_event_payload,
    input  wire [IRQ_WIDTH-1:0]         hw_irq_set_i,

    output wire [IRQ_WIDTH-1:0]         irq_status_out,
    output wire [IRQ_WIDTH-1:0]         irq_enable_out,
    output wire                         irq_o,
    output wire                         reg_busy_out,
    output wire                         reg_ready_out,
    output wire                         access_error_out
);
    localparam [31:0] REG_ID           = 32'h0000_0000;
    localparam [31:0] REG_IRQ_STATUS   = 32'h0000_0004;
    localparam [31:0] REG_IRQ_ENABLE   = 32'h0000_0008;
    localparam [31:0] REG_PAYLOAD_BASE = 32'h0000_000c;
    localparam [31:0] REG_PAYLOAD_END  = REG_PAYLOAD_BASE + PAYLOAD_WORDS * 4;
    localparam [31:0] REG_IF_STATUS    = IF_STATUS_OFFSET == 32'hffff_ffff ?
                                          REG_PAYLOAD_END : IF_STATUS_OFFSET;

    reg [IRQ_WIDTH-1:0] irq_status;
    reg [IRQ_WIDTH-1:0] irq_enable;
    reg                 access_error;
    reg [31:0]          payload_words [0:PAYLOAD_WORDS-1];

    wire        cpu_write = cpu_valid && |cpu_wstrb;
    wire        cpu_read  = cpu_valid && !cpu_write;
    wire [31:0] reg_addr  = cpu_addr - REG_BASE;
    wire        full_word_write = cpu_wstrb == 4'b1111;
    wire        payload_read = reg_addr >= REG_PAYLOAD_BASE &&
                               reg_addr < REG_PAYLOAD_END &&
                               reg_addr[1:0] == 2'b00;
    wire        w1c_irq_status = cpu_write && full_word_write &&
                                 reg_addr == REG_IRQ_STATUS;
    wire        w1c_access_error = cpu_write && full_word_write &&
                                   reg_addr == REG_IF_STATUS && cpu_wdata[2];
    wire        busy = |irq_status;
    wire        ready = !busy;
    wire        protected_irq_enable_write = cpu_write && full_word_write &&
                                             reg_addr == REG_IRQ_ENABLE;
    wire        blocked_irq_enable_write = protected_irq_enable_write && busy;

    wire [IRQ_WIDTH-1:0] cpu_irq_wdata = cpu_wdata[IRQ_WIDTH-1:0];
    wire [IRQ_WIDTH-1:0] event_irq_set = {{(IRQ_WIDTH-1){1'b0}}, ext_event_valid && ext_event_ready};
    wire [IRQ_WIDTH-1:0] irq_set = hw_irq_set_i | event_irq_set;

    integer i;
    integer payload_index;

    assign ext_event_ready = ready;
    assign irq_status_out = irq_status;
    assign irq_enable_out = irq_enable;
    assign irq_o = |(irq_status & irq_enable);
    assign reg_busy_out = busy;
    assign reg_ready_out = ready;
    assign access_error_out = access_error;

    always @(*) begin
        cpu_rdata = 32'h0000_0000;
        payload_index = (reg_addr - REG_PAYLOAD_BASE) >> 2;

        if (cpu_read) begin
            if (payload_read) begin
                cpu_rdata = payload_words[payload_index];
            end else begin
                case (reg_addr)
                    REG_ID:         cpu_rdata = ID_VALUE;
                    REG_IRQ_STATUS: cpu_rdata = {{(32-IRQ_WIDTH){1'b0}}, irq_status};
                    REG_IRQ_ENABLE: cpu_rdata = {{(32-IRQ_WIDTH){1'b0}}, irq_enable};
                    REG_IF_STATUS:  cpu_rdata = {29'b0, access_error, ready, busy};
                    default:        cpu_rdata = 32'h0000_0000;
                endcase
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            irq_status <= {IRQ_WIDTH{1'b0}};
            irq_enable <= {IRQ_WIDTH{1'b0}};
            access_error <= 1'b0;
            for (i = 0; i < PAYLOAD_WORDS; i = i + 1)
                payload_words[i] <= 32'h0000_0000;
        end else begin
            if (cpu_write && full_word_write && reg_addr == REG_IRQ_ENABLE) begin
                if (!busy)
                    irq_enable <= cpu_irq_wdata;
            end

            if (w1c_irq_status)
                irq_status <= irq_status & ~cpu_irq_wdata;

            if (w1c_access_error)
                access_error <= 1'b0;

            if (blocked_irq_enable_write)
                access_error <= 1'b1;

            if (ext_event_valid && ext_event_ready) begin
                for (i = 0; i < PAYLOAD_WORDS; i = i + 1)
                    payload_words[i] <= ext_event_payload[i*32 +: 32];
            end

            if (|irq_set)
                irq_status <= (w1c_irq_status ? (irq_status & ~cpu_irq_wdata) : irq_status) | irq_set;
        end
    end
endmodule
