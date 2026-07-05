// Purpose: Directed simulation for cdc_valid_ack payload CDC behavior.
// Role: Testbench only.
// Related design docs:
// - design_spec/nand_cdc_ip.md
// Block contract: Exercises asynchronous source/destination clocks,
// destination backpressure, payload ordering, and hold-stability while
// dst_ready is low.
// File version: v0.1
// Revision history:
// - v0.1: Import CDC valid/ack directed TB into NAND repository.

module tb_cdc_valid_ack;
    localparam integer DATA_WIDTH = 32;
    localparam integer NUM_TRANSFERS = 8;

    reg src_clk = 1'b0;
    reg dst_clk = 1'b0;
    reg src_resetn = 1'b0;
    reg dst_resetn = 1'b0;

    reg                  src_valid = 1'b0;
    wire                 src_ready;
    reg [DATA_WIDTH-1:0] src_data = {DATA_WIDTH{1'b0}};

    wire                 dst_valid;
    reg                  dst_ready = 1'b0;
    wire [DATA_WIDTH-1:0] dst_data;

    reg [DATA_WIDTH-1:0] expected [0:NUM_TRANSFERS-1];
    integer idx;
    integer recv_count;
    integer timeout_cycles;
    integer stall_cycles;

    reg                  dst_hold_active;
    reg [DATA_WIDTH-1:0] dst_hold_data;

    always #3 src_clk = !src_clk;
    always #5 dst_clk = !dst_clk;

    cdc_valid_ack #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_dut (
        .src_clk(src_clk),
        .src_resetn(src_resetn),
        .src_valid(src_valid),
        .src_ready(src_ready),
        .src_data(src_data),
        .dst_clk(dst_clk),
        .dst_resetn(dst_resetn),
        .dst_valid(dst_valid),
        .dst_ready(dst_ready),
        .dst_data(dst_data)
    );

    task launch_transfer;
        input [DATA_WIDTH-1:0] data;
        begin
            @(posedge src_clk);
            while (src_ready !== 1'b1)
                @(posedge src_clk);

            src_data <= data;
            src_valid <= 1'b1;
            @(posedge src_clk);
            #1;

            if (src_ready !== 1'b0) begin
                $display("FAIL: src_ready did not deassert after launch");
                $fatal;
            end

            src_valid <= 1'b0;
            while (src_ready !== 1'b1)
                @(posedge src_clk);
        end
    endtask

    always @(posedge dst_clk) begin
        if (!dst_resetn) begin
            recv_count <= 0;
            dst_hold_active <= 1'b0;
            dst_hold_data <= {DATA_WIDTH{1'b0}};
        end else begin
            if (dst_valid && !dst_ready) begin
                if (!dst_hold_active) begin
                    dst_hold_active <= 1'b1;
                    dst_hold_data <= dst_data;
                end else if (dst_data !== dst_hold_data) begin
                    $display("FAIL: dst_data changed while dst_valid held without dst_ready");
                    $fatal;
                end
            end else begin
                dst_hold_active <= 1'b0;
            end

            if (dst_valid && dst_ready) begin
                if (recv_count >= NUM_TRANSFERS) begin
                    $display("FAIL: received too many transfers");
                    $fatal;
                end

                if (dst_data !== expected[recv_count]) begin
                    $display("FAIL: transfer %0d data mismatch expected=0x%08x got=0x%08x",
                             recv_count, expected[recv_count], dst_data);
                    $fatal;
                end

                recv_count <= recv_count + 1;
            end
        end
    end

    initial begin
        for (idx = 0; idx < NUM_TRANSFERS; idx = idx + 1)
            expected[idx] = 32'h1000_0000 + idx;

        repeat (4) @(posedge src_clk);
        src_resetn = 1'b1;
        repeat (7) @(posedge dst_clk);
        dst_resetn = 1'b1;

        fork
            begin
                for (idx = 0; idx < NUM_TRANSFERS; idx = idx + 1)
                    launch_transfer(expected[idx]);
            end

            begin
                dst_ready = 1'b0;
                repeat (5) @(posedge dst_clk);
                for (stall_cycles = 0; stall_cycles < 80; stall_cycles = stall_cycles + 1) begin
                    case (stall_cycles % 7)
                        0, 1, 4: dst_ready = 1'b0;
                        default: dst_ready = 1'b1;
                    endcase
                    @(posedge dst_clk);
                end
                dst_ready = 1'b1;
            end

            begin
                timeout_cycles = 0;
                while (recv_count < NUM_TRANSFERS && timeout_cycles < 2000) begin
                    timeout_cycles = timeout_cycles + 1;
                    @(posedge dst_clk);
                end
            end
        join_any

        if (recv_count != NUM_TRANSFERS) begin
            $display("FAIL: timeout or missing transfer recv_count=%0d", recv_count);
            $fatal;
        end

        repeat (10) @(posedge dst_clk);
        $display("PASS: cdc_valid_ack directed CDC test");
        $finish;
    end
endmodule
