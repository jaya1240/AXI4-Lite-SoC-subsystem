// soc_peripheral_subsystem_top.sv
//
// Top-level AMBA AXI4-Lite SoC peripheral subsystem. A single AXI4-Lite
// master (a CPU's bus interface, or the testbench BFM) plugs into `s_axi`;
// the interconnect fans it out to GPIO, UART, Timer, and an interrupt
// controller. See docs/register_map.md for the address map and per-
// peripheral register layout, and docs/architecture.md for the block
// diagram and design notes.

module soc_peripheral_subsystem_top #(
    parameter int GPIO_WIDTH = 8,
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input  logic clk,
    input  logic rstn,

    axi4_lite_if.slave s_axi,

    // GPIO pins
    input  logic [GPIO_WIDTH-1:0] gpio_in,
    output logic [GPIO_WIDTH-1:0] gpio_out,
    output logic [GPIO_WIDTH-1:0] gpio_oe,

    // UART pins
    output logic uart_tx,
    input  logic uart_rx,

    // Single aggregated interrupt line out to the CPU
    output logic irq_out
);

    axi4_lite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) axi_gpio  (.clk(clk), .rstn(rstn));
    axi4_lite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) axi_uart  (.clk(clk), .rstn(rstn));
    axi4_lite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) axi_timer (.clk(clk), .rstn(rstn));
    axi4_lite_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) axi_intc  (.clk(clk), .rstn(rstn));

    logic gpio_irq, uart_irq, timer_irq;

    axi4_lite_interconnect #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_interconnect (
        .s_axi   (s_axi),
        .m_gpio  (axi_gpio.master),
        .m_uart  (axi_uart.master),
        .m_timer (axi_timer.master),
        .m_intc  (axi_intc.master)
    );

    gpio_axi4lite #(.GPIO_WIDTH(GPIO_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_gpio (
        .axi      (axi_gpio.slave),
        .gpio_in  (gpio_in),
        .gpio_out (gpio_out),
        .gpio_oe  (gpio_oe),
        .irq      (gpio_irq)
    );

    uart_axi4lite #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_uart (
        .axi          (axi_uart.slave),
        .uart_tx_line (uart_tx),
        .uart_rx_line (uart_rx),
        .irq          (uart_irq)
    );

    timer_axi4lite #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_timer (
        .axi (axi_timer.slave),
        .irq (timer_irq)
    );

    intr_ctrl_axi4lite #(.NUM_SOURCES(3), .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_intc (
        .axi        (axi_intc.slave),
        .periph_irq ({timer_irq, uart_irq, gpio_irq}),
        .irq_out    (irq_out)
    );

endmodule : soc_peripheral_subsystem_top
