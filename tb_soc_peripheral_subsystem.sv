// tb_soc_peripheral_subsystem.sv
//
// Directed, self-checking testbench for soc_peripheral_subsystem_top.
// Drives the DUT's AXI4-Lite slave port with simple blocking tasks
// (axi_write / axi_read) acting as an AXI4-Lite master BFM, and checks
// GPIO, UART (looped back on itself), Timer, and interrupt-controller
// behavior against expected values.
//
// Run with any SystemVerilog simulator (see sim/README or the top-level
// README for Vivado xsim / Questa commands).

`timescale 1ns/1ps

module tb_soc_peripheral_subsystem;

    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;
    localparam int GPIO_WIDTH = 8;
    localparam time CLK_PERIOD = 10ns; // 100 MHz

    // Peripheral offsets (see docs/register_map.md)
    localparam logic [ADDR_WIDTH-1:0] GPIO_BASE  = 32'h0000_0000;
    localparam logic [ADDR_WIDTH-1:0] UART_BASE  = 32'h0000_1000;
    localparam logic [ADDR_WIDTH-1:0] TIMER_BASE = 32'h0000_2000;
    localparam logic [ADDR_WIDTH-1:0] INTC_BASE  = 32'h0000_3000;

    logic clk = 0;
    logic rstn;

    always #(CLK_PERIOD/2) clk = ~clk;

    axi4_lite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) s_axi (.clk(clk), .rstn(rstn));

    logic [GPIO_WIDTH-1:0] gpio_in;
    logic [GPIO_WIDTH-1:0] gpio_out;
    logic [GPIO_WIDTH-1:0] gpio_oe;
    logic uart_loopback; // ties DUT's tx to DUT's rx for a self-test
    logic irq_out;

    soc_peripheral_subsystem_top #(.GPIO_WIDTH(GPIO_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) dut (
        .clk      (clk),
        .rstn     (rstn),
        .s_axi    (s_axi.slave),
        .gpio_in  (gpio_in),
        .gpio_out (gpio_out),
        .gpio_oe  (gpio_oe),
        .uart_tx  (uart_loopback),
        .uart_rx  (uart_loopback),
        .irq_out  (irq_out)
    );

    int errors = 0;

    // Waveform dump for post-run debugging in any viewer (GTKWave, Vivado
    // waveform viewer, Questa, etc.) -- tool-agnostic, unlike a simulator-
    // specific .wdb/.wlf script.
    initial begin
        $dumpfile("waves.vcd");
        $dumpvars(0, tb_soc_peripheral_subsystem);
    end

    // ------------------------------------------------------------------
    // AXI4-Lite master BFM tasks
    // ------------------------------------------------------------------
    task automatic axi_write(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] data);
        @(posedge clk);
        s_axi.awaddr  <= addr;
        s_axi.awvalid <= 1'b1;
        s_axi.wdata   <= data;
        s_axi.wstrb   <= '1;
        s_axi.wvalid  <= 1'b1;
        s_axi.bready  <= 1'b1;
        @(posedge clk);
        while (!(s_axi.awready && s_axi.wready)) @(posedge clk);
        s_axi.awvalid <= 1'b0;
        s_axi.wvalid  <= 1'b0;
        while (!s_axi.bvalid) @(posedge clk);
        @(posedge clk);
        s_axi.bready <= 1'b0;
    endtask

    task automatic axi_read(input logic [ADDR_WIDTH-1:0] addr, output logic [DATA_WIDTH-1:0] data);
        @(posedge clk);
        s_axi.araddr  <= addr;
        s_axi.arvalid <= 1'b1;
        s_axi.rready  <= 1'b1;
        @(posedge clk);
        while (!s_axi.arready) @(posedge clk);
        s_axi.arvalid <= 1'b0;
        while (!s_axi.rvalid) @(posedge clk);
        data = s_axi.rdata;
        @(posedge clk);
        s_axi.rready <= 1'b0;
    endtask

    // Variants that also check BRESP/RRESP -- used for the unmapped-
    // address corner case, where we expect a clean DECERR rather than a
    // hang.
    task automatic axi_write_expect_resp(input logic [ADDR_WIDTH-1:0] addr,
                                          input logic [DATA_WIDTH-1:0] data,
                                          input logic [1:0] expected_resp);
        @(posedge clk);
        s_axi.awaddr  <= addr;
        s_axi.awvalid <= 1'b1;
        s_axi.wdata   <= data;
        s_axi.wstrb   <= '1;
        s_axi.wvalid  <= 1'b1;
        s_axi.bready  <= 1'b1;
        @(posedge clk);
        while (!(s_axi.awready && s_axi.wready)) @(posedge clk);
        s_axi.awvalid <= 1'b0;
        s_axi.wvalid  <= 1'b0;
        while (!s_axi.bvalid) @(posedge clk);
        check("unmapped write BRESP", s_axi.bresp, expected_resp);
        @(posedge clk);
        s_axi.bready <= 1'b0;
    endtask

    task automatic axi_read_expect_resp(input logic [ADDR_WIDTH-1:0] addr,
                                         input logic [1:0] expected_resp);
        @(posedge clk);
        s_axi.araddr  <= addr;
        s_axi.arvalid <= 1'b1;
        s_axi.rready  <= 1'b1;
        @(posedge clk);
        while (!s_axi.arready) @(posedge clk);
        s_axi.arvalid <= 1'b0;
        while (!s_axi.rvalid) @(posedge clk);
        check("unmapped read RRESP", s_axi.rresp, expected_resp);
        @(posedge clk);
        s_axi.rready <= 1'b0;
    endtask

    task automatic check(input string name, input logic [DATA_WIDTH-1:0] got, input logic [DATA_WIDTH-1:0] expected);
        if (got !== expected) begin
            $display("[FAIL] %-40s got=0x%08x expected=0x%08x", name, got, expected);
            errors++;
        end else begin
            $display("[PASS] %-40s = 0x%08x", name, got);
        end
    endtask

    logic [DATA_WIDTH-1:0] rdata;

    initial begin
        rstn = 0;
        gpio_in = '0;
        s_axi.awvalid = 0; s_axi.wvalid = 0; s_axi.bready = 0;
        s_axi.arvalid = 0; s_axi.rready = 0;
        repeat (5) @(posedge clk);
        rstn = 1;
        repeat (5) @(posedge clk);

        // ---------------- GPIO ----------------
        $display("--- GPIO test ---");
        axi_write(GPIO_BASE + 32'h04, 32'h0000_00F0); // DIR: pins[7:4]=out, pins[3:0]=in
        axi_write(GPIO_BASE + 32'h00, 32'h0000_00A0); // DATA: drive out pins to 0xA (on nibble 7:4 -> 0xA0)
        @(posedge clk);
        check("gpio_out", gpio_out, 8'hA0);
        check("gpio_oe",  gpio_oe,  8'hF0);

        axi_read(GPIO_BASE + 32'h00, rdata);
        check("gpio DATA readback (out bits)", rdata[7:4], 4'hA);

        // GPIO interrupt: enable int on pin0, drive a rising edge on gpio_in[0]
        axi_write(GPIO_BASE + 32'h08, 32'h0000_0001); // INT_EN[0] = 1
        gpio_in[0] = 1'b0; @(posedge clk);
        gpio_in[0] = 1'b1; @(posedge clk); @(posedge clk);
        axi_read(GPIO_BASE + 32'h0C, rdata);
        check("gpio INT_STATUS after rising edge", rdata[0], 1'b1);
        axi_write(GPIO_BASE + 32'h0C, 32'h0000_0001); // W1C clear
        axi_read(GPIO_BASE + 32'h0C, rdata);
        check("gpio INT_STATUS after clear", rdata[0], 1'b0);

        // ---------------- UART (loopback) ----------------
        $display("--- UART loopback test ---");
        axi_write(UART_BASE + 32'h0C, {15'b0, 1'b1, 16'd4}); // CTRL: enable=1, baud_div=4 (fast for sim)
        axi_write(UART_BASE + 32'h10, 32'h0000_0003);        // INT_EN: tx_done + rx_valid
        axi_write(UART_BASE + 32'h00, 32'h0000_00A5);        // TXDATA = 0xA5

        // Wait generously for a full frame (start + 8 data + stop) at baud_div=4
        repeat (200) @(posedge clk);

        axi_read(UART_BASE + 32'h08, rdata); // STATUS
        check("uart rx_valid flag set", rdata[1], 1'b1);

        axi_read(UART_BASE + 32'h04, rdata); // RXDATA
        check("uart looped-back byte", rdata[7:0], 8'hA5);

        axi_read(UART_BASE + 32'h14, rdata); // INT_STATUS
        check("uart INT_STATUS tx_done|rx_valid", rdata[1:0], 2'b11);
        axi_write(UART_BASE + 32'h14, 32'h0000_0003); // W1C clear

        // ---------------- Timer ----------------
        $display("--- Timer test ---");
        axi_write(TIMER_BASE + 32'h00, 32'd10);         // LOAD = 10 cycles
        axi_write(TIMER_BASE + 32'h0C, 32'h0000_0001);  // INT_EN
        axi_write(TIMER_BASE + 32'h08, 32'h0000_0001);  // CTRL: enable=1, one-shot

        repeat (15) @(posedge clk);
        axi_read(TIMER_BASE + 32'h10, rdata); // INT_STATUS
        check("timer INT_STATUS after timeout", rdata[0], 1'b1);

        // ---------------- Interrupt controller ----------------
        $display("--- Interrupt controller test ---");
        axi_write(INTC_BASE + 32'h04, 32'h0000_0007); // MASK: enable all 3 sources
        @(posedge clk);
        check("irq_out asserted (timer pending+masked)", irq_out, 1'b1);

        axi_read(INTC_BASE + 32'h08, rdata); // MASKED_PENDING
        check("intc MASKED_PENDING bit2 (timer)", rdata[2], 1'b1);

        axi_write(TIMER_BASE + 32'h10, 32'h0000_0001); // clear timer INT_STATUS
        @(posedge clk);
        check("irq_out deasserted after clearing timer", irq_out, 1'b0);

        // ---------------- Corner case: unmapped address ----------------
        $display("--- Corner case: unmapped address ---");
        axi_write_expect_resp(32'h0000_5000, 32'hDEAD_BEEF, 2'b11); // no peripheral there -> DECERR
        axi_read_expect_resp(32'h0000_5000, 2'b11);

        // ---------------- Corner case: GPIO write to an input-configured pin ----------------
        $display("--- Corner case: GPIO write ignored on input pins ---");
        axi_write(GPIO_BASE + 32'h04, 32'h0000_00F0); // DIR: [7:4]=out, [3:0]=in (same as earlier test)
        axi_write(GPIO_BASE + 32'h00, 32'h0000_000F); // attempt to drive the INPUT-configured low nibble
        @(posedge clk);
        check("gpio_out low nibble unaffected by DIR=input", gpio_out[3:0], 4'h0);

        // ---------------- Corner case: timer LOAD=0 fires on the very next cycle ----------------
        $display("--- Corner case: timer LOAD=0 (immediate timeout) ---");
        axi_write(TIMER_BASE + 32'h10, 32'h0000_0001); // clear any stale INT_STATUS first
        axi_write(TIMER_BASE + 32'h00, 32'd0);         // LOAD = 0
        axi_write(TIMER_BASE + 32'h08, 32'h0000_0001); // CTRL: enable=1, one-shot -- (re)arms from LOAD=0
        @(posedge clk); @(posedge clk);
        axi_read(TIMER_BASE + 32'h10, rdata);
        check("timer fires immediately when LOAD=0", rdata[0], 1'b1);
        axi_write(TIMER_BASE + 32'h10, 32'h0000_0001); // clear

        // ---------------- Corner case: back-to-back UART bytes ----------------
        $display("--- Corner case: back-to-back UART transmission ---");
        axi_write(UART_BASE + 32'h14, 32'h0000_0003); // clear stale INT_STATUS
        axi_write(UART_BASE + 32'h00, 32'h0000_0011); // TXDATA = 0x11
        // Poll STATUS.tx_busy and only send the next byte once idle --
        // exercises the same tx_start/!tx_busy guard a real driver would
        // rely on, back-to-back with no idle gap in between.
        do begin
            axi_read(UART_BASE + 32'h08, rdata);
        end while (rdata[0]); // wait while tx_busy
        axi_write(UART_BASE + 32'h00, 32'h0000_0022); // TXDATA = 0x22, immediately after the first completes
        repeat (100) @(posedge clk);
        axi_read(UART_BASE + 32'h04, rdata);
        check("uart back-to-back second byte received", rdata[7:0], 8'h22);

        // ---------------- Summary ----------------
        if (errors == 0) begin
            $display("\n=== ALL TESTS PASSED ===");
        end else begin
            $display("\n=== %0d TEST(S) FAILED ===", errors);
        end

        $finish;
    end

    // Safety timeout in case a handshake never completes
    initial begin
        #100000;
        $display("[FAIL] Testbench timeout -- a transaction likely hung");
        $finish;
    end

endmodule : tb_soc_peripheral_subsystem
