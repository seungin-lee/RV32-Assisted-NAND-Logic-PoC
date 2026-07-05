`timescale 1ns/1ps
`default_nettype none

// Purpose: Generic multi-bit pin synchronizer and edge detector.
// Role: Synthesizable RTL utility IP.
// Related design docs:
// - design_spec/SIMPLE_ONFI_SDR_decode_fsm.md
// - design_spec/host_tb_traffice_scenario.md
// - design_spec/nand_cdc_ip.md
// Block contract: This block has no ONFI/NAND semantics. It only synchronizes
// async pins into clk and reports one-cycle rise/fall pulses per bit.
// File version: v0.2
// Revision history:
// - v0.2: Update CDC reference to NAND-owned CDC IP document.
// - v0.1: Initial generic pin sync and edge detect utility.

module pin_sync_edge_detect #(
    parameter integer WIDTH = 1,
    parameter [WIDTH-1:0] RESET_VALUE = {WIDTH{1'b0}}
) (
    input  wire             clk,
    input  wire             resetn,
    input  wire [WIDTH-1:0] async_i,
    output reg  [WIDTH-1:0] sync_o,
    output reg  [WIDTH-1:0] rise_pulse_o,
    output reg  [WIDTH-1:0] fall_pulse_o
);

    reg [WIDTH-1:0] sync_ff1;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            sync_ff1     <= RESET_VALUE;
            sync_o       <= RESET_VALUE;
            rise_pulse_o <= {WIDTH{1'b0}};
            fall_pulse_o <= {WIDTH{1'b0}};
        end else begin
            sync_ff1     <= async_i;
            sync_o       <= sync_ff1;
            rise_pulse_o <= (~sync_o) & sync_ff1;
            fall_pulse_o <= sync_o & (~sync_ff1);
        end
    end

endmodule

`default_nettype wire
