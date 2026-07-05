// Purpose: Generic external event CDC wrapper around cdc_valid_ack with
// optional level IRQ synchronization.
// Role: Synthesizable RTL reference/helper.
// Related design docs:
// - design_spec/nand_cdc_ip.md
// - design_spec/nand_adapter_contracts.md
// Block contract: Converts an external-domain valid/data event into a
// destination-domain valid/data event. NAND role adapters may use the lower
// CDC primitives directly when role-specific payload naming is clearer.
// File version: v0.1
// Revision history:
// - v0.1: Import external event adapter into NAND repository.

module external_event_adapter #(
    parameter integer DATA_WIDTH = 64,
    parameter integer USE_EXT_IRQ = 0
) (
    input  wire                  ext_clk,
    input  wire                  ext_resetn,
    input  wire                  ext_valid,
    output wire                  ext_ready,
    input  wire                  ext_irq,
    input  wire [DATA_WIDTH-1:0] ext_data,

    input  wire                  soc_clk,
    input  wire                  soc_resetn,
    output wire                  soc_event_valid,
    input  wire                  soc_event_ready,
    output wire [DATA_WIDTH-1:0] soc_event_data,
    output wire                  soc_irq
);
    cdc_valid_ack #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_event_cdc (
        .src_clk(ext_clk),
        .src_resetn(ext_resetn),
        .src_valid(ext_valid),
        .src_ready(ext_ready),
        .src_data(ext_data),
        .dst_clk(soc_clk),
        .dst_resetn(soc_resetn),
        .dst_valid(soc_event_valid),
        .dst_ready(soc_event_ready),
        .dst_data(soc_event_data)
    );

    generate
        if (USE_EXT_IRQ) begin : g_irq_sync
            cdc_level_sync u_irq_sync (
                .src_level(ext_irq),
                .dst_clk(soc_clk),
                .dst_resetn(soc_resetn),
                .dst_level(soc_irq)
            );
        end else begin : g_no_irq_sync
            assign soc_irq = 1'b0;
        end
    endgenerate
endmodule
