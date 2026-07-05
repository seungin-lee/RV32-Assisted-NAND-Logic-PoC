// Purpose: Directed simulation for the generic external_event_adapter wrapper.
// Role: Testbench only.
// Related design docs:
// - design_spec/nand_cdc_ip.md
// - design_spec/nand_adapter_contracts.md
// Block contract: Checks event payload CDC plus optional level IRQ
// synchronization through the wrapper.
// File version: v0.1
// Revision history:
// - v0.1: Import external event adapter TB into NAND repository.

module tb_external_event_adapter;
    localparam integer DATA_WIDTH = 64;

    reg ext_clk = 1'b0;
    reg soc_clk = 1'b0;
    reg ext_resetn = 1'b0;
    reg soc_resetn = 1'b0;

    reg                  ext_valid = 1'b0;
    wire                 ext_ready;
    reg                  ext_irq = 1'b0;
    reg [DATA_WIDTH-1:0] ext_data = {DATA_WIDTH{1'b0}};

    wire                 soc_event_valid;
    reg                  soc_event_ready = 1'b0;
    wire [DATA_WIDTH-1:0] soc_event_data;
    wire                 soc_irq;

    integer timeout_cycles;

    always #4 ext_clk = !ext_clk;
    always #9 soc_clk = !soc_clk;

    external_event_adapter #(
        .DATA_WIDTH(DATA_WIDTH),
        .USE_EXT_IRQ(1)
    ) u_dut (
        .ext_clk(ext_clk),
        .ext_resetn(ext_resetn),
        .ext_valid(ext_valid),
        .ext_ready(ext_ready),
        .ext_irq(ext_irq),
        .ext_data(ext_data),
        .soc_clk(soc_clk),
        .soc_resetn(soc_resetn),
        .soc_event_valid(soc_event_valid),
        .soc_event_ready(soc_event_ready),
        .soc_event_data(soc_event_data),
        .soc_irq(soc_irq)
    );

    task launch_event;
        input [DATA_WIDTH-1:0] data;
        begin
            @(posedge ext_clk);
            while (ext_ready !== 1'b1)
                @(posedge ext_clk);

            ext_data <= data;
            ext_valid <= 1'b1;
            @(posedge ext_clk);
            ext_valid <= 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge ext_clk);
        ext_resetn = 1'b1;
        repeat (5) @(posedge soc_clk);
        soc_resetn = 1'b1;

        soc_event_ready = 1'b0;
        launch_event(64'h2222_2222_1111_1111);

        timeout_cycles = 0;
        while (!soc_event_valid && timeout_cycles < 200) begin
            timeout_cycles = timeout_cycles + 1;
            @(posedge soc_clk);
        end

        if (!soc_event_valid) begin
            $display("FAIL: timeout waiting for soc_event_valid");
            $fatal;
        end

        if (soc_event_data !== 64'h2222_2222_1111_1111) begin
            $display("FAIL: soc_event_data mismatch got=0x%016x", soc_event_data);
            $fatal;
        end

        repeat (4) @(posedge soc_clk);
        if (soc_event_data !== 64'h2222_2222_1111_1111) begin
            $display("FAIL: soc_event_data changed while backpressured");
            $fatal;
        end

        soc_event_ready = 1'b1;
        @(posedge soc_clk);
        soc_event_ready = 1'b0;

        while (ext_ready !== 1'b1)
            @(posedge ext_clk);

        ext_irq = 1'b1;
        timeout_cycles = 0;
        while (!soc_irq && timeout_cycles < 50) begin
            timeout_cycles = timeout_cycles + 1;
            @(posedge soc_clk);
        end

        if (!soc_irq) begin
            $display("FAIL: timeout waiting for synchronized soc_irq high");
            $fatal;
        end

        ext_irq = 1'b0;
        timeout_cycles = 0;
        while (soc_irq && timeout_cycles < 50) begin
            timeout_cycles = timeout_cycles + 1;
            @(posedge soc_clk);
        end

        if (soc_irq) begin
            $display("FAIL: timeout waiting for synchronized soc_irq low");
            $fatal;
        end

        $display("PASS: external_event_adapter directed CDC test");
        $finish;
    end
endmodule
