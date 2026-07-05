// Purpose: Multi-bit payload CDC primitive with source valid/ready and
// destination valid/ready handshakes.
// Role: Synthesizable RTL.
// Related design docs:
// - design_spec/nand_cdc_ip.md
// - design_spec/nand_adapter_contracts.md
// Block contract: Source holds one payload until destination accepts it; this
// primitive is for low-throughput command/event handoff, not streaming FIFOs.
// File version: v0.1
// Revision history:
// - v0.1: Import CDC valid/ack primitive into NAND repository.

module cdc_valid_ack #(
    parameter integer DATA_WIDTH = 32
) (
    input  wire                  src_clk,
    input  wire                  src_resetn,
    input  wire                  src_valid,
    output wire                  src_ready,
    input  wire [DATA_WIDTH-1:0] src_data,

    input  wire                  dst_clk,
    input  wire                  dst_resetn,
    output wire                  dst_valid,
    input  wire                  dst_ready,
    output wire [DATA_WIDTH-1:0] dst_data
);
    reg [DATA_WIDTH-1:0] src_data_hold;
    reg                  src_req_toggle;
    reg                  src_busy;
    reg [2:0]            src_ack_sync;

    reg [2:0]            dst_req_sync;
    reg                  dst_req_seen;
    reg                  dst_ack_toggle;
    reg                  dst_valid_reg;
    reg [DATA_WIDTH-1:0] dst_data_reg;

    wire src_ack_seen = src_ack_sync[2] ^ src_ack_sync[1];
    wire dst_req_seen_pulse = dst_req_sync[2] ^ dst_req_seen;

    assign src_ready = !src_busy;
    assign dst_valid = dst_valid_reg;
    assign dst_data = dst_data_reg;

    always @(posedge src_clk) begin
        if (!src_resetn) begin
            src_data_hold <= {DATA_WIDTH{1'b0}};
            src_req_toggle <= 1'b0;
            src_busy <= 1'b0;
            src_ack_sync <= 3'b000;
        end else begin
            src_ack_sync <= {src_ack_sync[1:0], dst_ack_toggle};

            if (src_ack_seen)
                src_busy <= 1'b0;

            if (src_valid && src_ready) begin
                src_data_hold <= src_data;
                src_req_toggle <= !src_req_toggle;
                src_busy <= 1'b1;
            end
        end
    end

    always @(posedge dst_clk) begin
        if (!dst_resetn) begin
            dst_req_sync <= 3'b000;
            dst_req_seen <= 1'b0;
            dst_ack_toggle <= 1'b0;
            dst_valid_reg <= 1'b0;
            dst_data_reg <= {DATA_WIDTH{1'b0}};
        end else begin
            dst_req_sync <= {dst_req_sync[1:0], src_req_toggle};

            if (!dst_valid_reg && dst_req_seen_pulse) begin
                dst_data_reg <= src_data_hold;
                dst_valid_reg <= 1'b1;
                dst_req_seen <= dst_req_sync[2];
            end

            if (dst_valid_reg && dst_ready) begin
                dst_valid_reg <= 1'b0;
                dst_ack_toggle <= !dst_ack_toggle;
            end
        end
    end
endmodule
