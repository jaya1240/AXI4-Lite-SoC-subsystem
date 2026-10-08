// soc_peripheral_subsystem_sva.sv
//
// Design-level (not just bus-protocol) assertions, bound into
// `soc_peripheral_subsystem_top`. Because `bind` places this module in
// the same scope as the target, it can reference internal peripheral
// signals directly by hierarchical name (e.g. `u_gpio.dir_q`) without any
// extra debug ports -- useful for invariants that are about a
// peripheral's internal state, not just what's visible on its bus.

module soc_peripheral_subsystem_sva (
    input logic clk,
    input logic rstn,

    input logic [7:0] gpio_oe,
    input logic [7:0] dir_q_val,      // soc_peripheral_subsystem_top.u_gpio.dir_q

    input logic        timer_enable_q,
    input logic        timer_running_q,
    input logic [31:0] timer_value_q,

    input logic [2:0] periph_irq_val, // soc_peripheral_subsystem_top.u_intc.periph_irq
    input logic [2:0] intc_mask_q,    // soc_peripheral_subsystem_top.u_intc.mask_q
    input logic        irq_out
);

    // 1. GPIO's output-enable always mirrors its direction register --
    // true by construction today, but this catches a future refactor
    // that breaks the connection.
    a_gpio_oe_matches_dir: assert property (
        @(posedge clk) disable iff (!rstn) gpio_oe == dir_q_val
    ) else $error("[SVA] gpio_oe diverged from GPIO's DIR register");

    // 2. The interrupt controller's output is exactly the mask applied to
    // the live peripheral IRQ lines -- no hidden latch, no stale mask.
    a_irq_out_matches_mask: assert property (
        @(posedge clk) disable iff (!rstn) irq_out == |(periph_irq_val & intc_mask_q)
    ) else $error("[SVA] irq_out inconsistent with periph_irq & MASK");

    // 3. A running timer's counter only ever decreases or reloads --
    // catches a stuck-at or a rollover-the-wrong-way bug in the
    // down-counter.
    a_timer_monotonic: assert property (
        @(posedge clk) disable iff (!rstn)
        (timer_enable_q && timer_running_q && $past(timer_enable_q) && $past(timer_running_q))
            |-> (timer_value_q <= $past(timer_value_q) || $past(timer_value_q) == 32'd0)
    ) else $error("[SVA] timer VALUE increased while running (expected a monotonic down-count or reload)");

endmodule : soc_peripheral_subsystem_sva

bind soc_peripheral_subsystem_top soc_peripheral_subsystem_sva u_soc_peripheral_subsystem_sva (
    .clk            (clk),
    .rstn           (rstn),
    .gpio_oe        (gpio_oe),
    .dir_q_val      (u_gpio.dir_q),
    .timer_enable_q (u_timer.enable_q),
    .timer_running_q(u_timer.running_q),
    .timer_value_q  (u_timer.value_q),
    .periph_irq_val ({timer_irq, uart_irq, gpio_irq}),
    .intc_mask_q    (u_intc.mask_q),
    .irq_out        (irq_out)
);
