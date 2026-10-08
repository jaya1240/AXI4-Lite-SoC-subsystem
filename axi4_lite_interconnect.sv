// axi4_lite_interconnect.sv
//
// Single-master, 4-slave AXI4-Lite interconnect for this subsystem
// (GPIO, UART, Timer, Interrupt Controller). Address-decodes each 4 KB
// region to the matching slave and muxes responses back based on the
// slave selected for the currently outstanding write/read transaction.
// Single outstanding transaction per channel -- sufficient for a simple
// peripheral subsystem; a general-purpose N-way crossbar would pipeline
// multiple outstanding transactions, which isn't needed here.
//
// Address map (see docs/register_map.md for full details):
//   0x0000_0000 - 0x0000_0FFF : GPIO
//   0x0000_1000 - 0x0000_1FFF : UART
//   0x0000_2000 - 0x0000_2FFF : Timer
//   0x0000_3000 - 0x0000_3FFF : Interrupt Controller

module axi4_lite_interconnect #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    axi4_lite_if.slave  s_axi,   // from the system master (e.g. a CPU or TB BFM)
    axi4_lite_if.master m_gpio,
    axi4_lite_if.master m_uart,
    axi4_lite_if.master m_timer,
    axi4_lite_if.master m_intc
);

    localparam logic [ADDR_WIDTH-1:0] GPIO_BASE  = 32'h0000_0000;
    localparam logic [ADDR_WIDTH-1:0] UART_BASE  = 32'h0000_1000;
    localparam logic [ADDR_WIDTH-1:0] TIMER_BASE = 32'h0000_2000;
    localparam logic [ADDR_WIDTH-1:0] INTC_BASE  = 32'h0000_3000;
    localparam logic [ADDR_WIDTH-1:0] REGION_MASK = 32'hFFFF_F000; // 4 KB regions

    typedef enum logic [2:0] {SEL_NONE, SEL_GPIO, SEL_UART, SEL_TIMER, SEL_INTC} sel_t;

    function automatic sel_t decode(logic [ADDR_WIDTH-1:0] addr);
        case (addr & REGION_MASK)
            GPIO_BASE:  decode = SEL_GPIO;
            UART_BASE:  decode = SEL_UART;
            TIMER_BASE: decode = SEL_TIMER;
            INTC_BASE:  decode = SEL_INTC;
            default:    decode = SEL_NONE;
        endcase
    endfunction

    // ------------------------------------------------------------------
    // Write channel: decode on AWVALID, remember which slave owns the
    // in-flight write until its BVALID/BREADY completes.
    // ------------------------------------------------------------------
    sel_t wsel_q;
    logic wbusy_q;
    logic werr_pending_q; // unmapped write: interconnect answers directly, no real slave involved

    wire sel_t wsel_next = decode(s_axi.awaddr);

    always_ff @(posedge s_axi.clk or negedge s_axi.rstn) begin
        if (!s_axi.rstn) begin
            wsel_q         <= SEL_NONE;
            wbusy_q        <= 1'b0;
            werr_pending_q <= 1'b0;
        end else begin
            if (!wbusy_q && s_axi.awvalid && s_axi.wvalid) begin
                wsel_q  <= wsel_next;
                wbusy_q <= 1'b1;
                if (wsel_next == SEL_NONE) werr_pending_q <= 1'b1;
            end else if (wbusy_q && s_axi.bvalid && s_axi.bready) begin
                wbusy_q        <= 1'b0;
                werr_pending_q <= 1'b0;
            end
        end
    end

    wire sel_t wsel = wbusy_q ? wsel_q : wsel_next;

    // Fan the write channel out to whichever slave is selected; unselected
    // slaves see AWVALID/WVALID deasserted.
    assign m_gpio.awaddr  = s_axi.awaddr;
    assign m_uart.awaddr  = s_axi.awaddr;
    assign m_timer.awaddr = s_axi.awaddr;
    assign m_intc.awaddr  = s_axi.awaddr;

    assign m_gpio.awvalid  = s_axi.awvalid && (wsel == SEL_GPIO);
    assign m_uart.awvalid  = s_axi.awvalid && (wsel == SEL_UART);
    assign m_timer.awvalid = s_axi.awvalid && (wsel == SEL_TIMER);
    assign m_intc.awvalid  = s_axi.awvalid && (wsel == SEL_INTC);

    assign m_gpio.wdata  = s_axi.wdata;
    assign m_uart.wdata  = s_axi.wdata;
    assign m_timer.wdata = s_axi.wdata;
    assign m_intc.wdata  = s_axi.wdata;

    assign m_gpio.wstrb  = s_axi.wstrb;
    assign m_uart.wstrb  = s_axi.wstrb;
    assign m_timer.wstrb = s_axi.wstrb;
    assign m_intc.wstrb  = s_axi.wstrb;

    assign m_gpio.wvalid  = s_axi.wvalid && (wsel == SEL_GPIO);
    assign m_uart.wvalid  = s_axi.wvalid && (wsel == SEL_UART);
    assign m_timer.wvalid = s_axi.wvalid && (wsel == SEL_TIMER);
    assign m_intc.wvalid  = s_axi.wvalid && (wsel == SEL_INTC);

    assign m_gpio.bready  = s_axi.bready;
    assign m_uart.bready  = s_axi.bready;
    assign m_timer.bready = s_axi.bready;
    assign m_intc.bready  = s_axi.bready;

    always_comb begin
        case (wsel)
            SEL_GPIO:  begin s_axi.awready = m_gpio.awready;  s_axi.wready = m_gpio.wready;  s_axi.bvalid = m_gpio.bvalid;  s_axi.bresp = m_gpio.bresp;  end
            SEL_UART:  begin s_axi.awready = m_uart.awready;  s_axi.wready = m_uart.wready;  s_axi.bvalid = m_uart.bvalid;  s_axi.bresp = m_uart.bresp;  end
            SEL_TIMER: begin s_axi.awready = m_timer.awready; s_axi.wready = m_timer.wready; s_axi.bvalid = m_timer.bvalid; s_axi.bresp = m_timer.bresp; end
            SEL_INTC:  begin s_axi.awready = m_intc.awready;  s_axi.wready = m_intc.wready;  s_axi.bvalid = m_intc.bvalid;  s_axi.bresp = m_intc.bresp;  end
            default: begin
                // Unmapped address: the interconnect itself answers --
                // no real slave to wait on -- accepting immediately and
                // returning DECERR (2'b11) once accepted, so a write to
                // an invalid address completes cleanly instead of
                // hanging the bus forever.
                s_axi.awready = !wbusy_q;
                s_axi.wready  = !wbusy_q;
                s_axi.bvalid  = werr_pending_q;
                s_axi.bresp   = 2'b11;
            end
        endcase
    end

    // ------------------------------------------------------------------
    // Read channel: same pattern, decoded on ARVALID.
    // ------------------------------------------------------------------
    sel_t rsel_q;
    logic rbusy_q;
    logic rerr_pending_q;

    wire sel_t rsel_next = decode(s_axi.araddr);

    always_ff @(posedge s_axi.clk or negedge s_axi.rstn) begin
        if (!s_axi.rstn) begin
            rsel_q         <= SEL_NONE;
            rbusy_q        <= 1'b0;
            rerr_pending_q <= 1'b0;
        end else begin
            if (!rbusy_q && s_axi.arvalid) begin
                rsel_q  <= rsel_next;
                rbusy_q <= 1'b1;
                if (rsel_next == SEL_NONE) rerr_pending_q <= 1'b1;
            end else if (rbusy_q && s_axi.rvalid && s_axi.rready) begin
                rbusy_q        <= 1'b0;
                rerr_pending_q <= 1'b0;
            end
        end
    end

    wire sel_t rsel = rbusy_q ? rsel_q : rsel_next;

    assign m_gpio.araddr  = s_axi.araddr;
    assign m_uart.araddr  = s_axi.araddr;
    assign m_timer.araddr = s_axi.araddr;
    assign m_intc.araddr  = s_axi.araddr;

    assign m_gpio.arvalid  = s_axi.arvalid && (rsel == SEL_GPIO);
    assign m_uart.arvalid  = s_axi.arvalid && (rsel == SEL_UART);
    assign m_timer.arvalid = s_axi.arvalid && (rsel == SEL_TIMER);
    assign m_intc.arvalid  = s_axi.arvalid && (rsel == SEL_INTC);

    assign m_gpio.rready  = s_axi.rready;
    assign m_uart.rready  = s_axi.rready;
    assign m_timer.rready = s_axi.rready;
    assign m_intc.rready  = s_axi.rready;

    always_comb begin
        case (rsel)
            SEL_GPIO:  begin s_axi.arready = m_gpio.arready;  s_axi.rvalid = m_gpio.rvalid;  s_axi.rdata = m_gpio.rdata;  s_axi.rresp = m_gpio.rresp;  end
            SEL_UART:  begin s_axi.arready = m_uart.arready;  s_axi.rvalid = m_uart.rvalid;  s_axi.rdata = m_uart.rdata;  s_axi.rresp = m_uart.rresp;  end
            SEL_TIMER: begin s_axi.arready = m_timer.arready; s_axi.rvalid = m_timer.rvalid; s_axi.rdata = m_timer.rdata; s_axi.rresp = m_timer.rresp; end
            SEL_INTC:  begin s_axi.arready = m_intc.arready;  s_axi.rvalid = m_intc.rvalid;  s_axi.rdata = m_intc.rdata;  s_axi.rresp = m_intc.rresp;  end
            default: begin
                s_axi.arready = !rbusy_q;
                s_axi.rvalid  = rerr_pending_q;
                s_axi.rdata   = '0;
                s_axi.rresp   = 2'b11;
            end
        endcase
    end

endmodule : axi4_lite_interconnect
