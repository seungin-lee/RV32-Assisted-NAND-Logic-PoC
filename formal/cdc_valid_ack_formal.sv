// Purpose: Bounded formal harness for cdc_valid_ack.
// Role: Formal verification only.
// Related design docs:
// - design_spec/nand_cdc_ip.md
// Block contract: Single-clock abstraction sanity-checks one-in-flight payload
// ordering, destination hold stability, and source ready/busy behavior.
// File version: v0.1
// Revision history:
// - v0.1: Import CDC formal harness into NAND repository.

module cdc_valid_ack_formal (
    input wire clk
);
    localparam integer DATA_WIDTH = 32;

    reg [3:0] reset_count = 4'd0;
    wire resetn = reset_count[3];

    (* anyseq *) reg                  src_start;
    (* anyseq *) reg [DATA_WIDTH-1:0] src_data_any;
    (* anyseq *) reg                  dst_ready_any;

    reg                  src_valid = 1'b0;
    wire                 src_ready;
    reg [DATA_WIDTH-1:0] src_data = {DATA_WIDTH{1'b0}};

    wire                 dst_valid;
    wire                 dst_ready = resetn && dst_ready_any;
    wire [DATA_WIDTH-1:0] dst_data;

    reg                  pending = 1'b0;
    reg [DATA_WIDTH-1:0] pending_data = {DATA_WIDTH{1'b0}};

    cdc_valid_ack #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_dut (
        .src_clk(clk),
        .src_resetn(resetn),
        .src_valid(src_valid),
        .src_ready(src_ready),
        .src_data(src_data),
        .dst_clk(clk),
        .dst_resetn(resetn),
        .dst_valid(dst_valid),
        .dst_ready(dst_ready),
        .dst_data(dst_data)
    );

    always @(posedge clk) begin
        if (!resetn)
            reset_count <= reset_count + 4'd1;
    end

    always @(posedge clk) begin
        if (!resetn) begin
            src_valid <= 1'b0;
            src_data <= {DATA_WIDTH{1'b0}};
        end else if (src_valid && src_ready) begin
            src_valid <= 1'b0;
        end else if (!src_valid && src_ready && src_start) begin
            src_valid <= 1'b1;
            src_data <= src_data_any;
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            pending <= 1'b0;
            pending_data <= {DATA_WIDTH{1'b0}};
        end else begin
            if (src_valid && src_ready) begin
                assert(!pending);
                pending <= 1'b1;
                pending_data <= src_data;
            end

            if (dst_valid && dst_ready) begin
                assert(pending);
                assert(dst_data == pending_data);
                pending <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (resetn && $past(resetn)) begin
            if ($past(src_valid && src_ready))
                assert(!src_ready);

            if ($past(dst_valid && !dst_ready)) begin
                assert(dst_valid);
                assert(dst_data == $past(dst_data));
            end
        end
    end
endmodule
