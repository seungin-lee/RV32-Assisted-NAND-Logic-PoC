// Purpose: Single-bit level synchronizer for long-lived status/control flags.
// Role: Synthesizable RTL.
// Related design docs:
// - design_spec/nand_cdc_ip.md
// - design_spec/nand_adapter_contracts.md
// Block contract: Synchronizes a single level into a destination clock domain
// with two flip-flops. Do not use this module for multi-bit payloads.
// File version: v0.1
// Revision history:
// - v0.1: Import CDC level synchronizer into NAND repository.

module cdc_level_sync (
    input  wire src_level,
    input  wire dst_clk,
    input  wire dst_resetn,
    output wire dst_level
);
    reg [1:0] sync_ff;

    assign dst_level = sync_ff[1];

    always @(posedge dst_clk) begin
        if (!dst_resetn)
            sync_ff <= 2'b00;
        else
            sync_ff <= {sync_ff[0], src_level};
    end
endmodule
