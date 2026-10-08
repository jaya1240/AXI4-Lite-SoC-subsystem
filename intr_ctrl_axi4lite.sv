// intr_ctrl_axi4lite.sv
//
// Simple interrupt controller: ORs a small set of already-latched
// peripheral interrupt lines into a single CPU-facing irq_out, with a
// per-source mask so software can enable/disable sources individually and
// a status register so an ISR can identify which peripheral(s) fired
// without polling each one.
//
// Each peripheral is expected to already latch/sticky its own interrupt
// (see gpio_axi4lite / uart_axi4lite / timer_axi4lite INT_STATUS
// registers) and clear it via its own W1C register -- this controller
// does not need its own separate latch for that reason.
//
// Register map:
//   0x00  SOURCE_STATUS  R     live level of each peripheral irq input
//                              bit0 = GPIO, bit1 = UART, bit2 = TIMER
//   0x04  MASK           R/W   per-source enable (1 = enabled)
//   0x08  MASKED_PENDING R     SOURCE_STATUS & MASK -- what's actually
//                              contributing to irq_out right now

module intr_ctrl_axi4lite #(
    parameter int NUM_SOURCES = 3,
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32
) (
    axi4_lite_if.slave axi,

    input  logic [NUM_SOURCES-1:0] periph_irq, // {timer_irq, uart_irq, gpio_irq}
    output logic                   irq_out
);

    localparam logic [7:0] OFF_SOURCE_STATUS  = 8'h00;
    localparam logic [7:0] OFF_MASK           = 8'h04;
    localparam logic [7:0] OFF_MASKED_PENDING = 8'h08;

    logic                    reg_wen, reg_ren;
    logic [ADDR_WIDTH-1:0]   reg_waddr, reg_raddr;
    logic [DATA_WIDTH-1:0]   reg_wdata, reg_rdata;
    logic [DATA_WIDTH/8-1:0] reg_wstrb;

    axi4_lite_slave_fsm #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_fsm (
        .axi       (axi),
        .reg_wen   (reg_wen),
        .reg_ren   (reg_ren),
        .reg_waddr (reg_waddr),
        .reg_raddr (reg_raddr),
        .reg_wdata (reg_wdata),
        .reg_wstrb (reg_wstrb),
        .reg_rdata (reg_rdata)
    );

    wire [7:0] waddr_off = reg_waddr[7:0];
    wire [7:0] raddr_off = reg_raddr[7:0];

    logic [NUM_SOURCES-1:0] mask_q;

    wire [NUM_SOURCES-1:0] masked_pending = periph_irq & mask_q;
    assign irq_out = |masked_pending;

    always_ff @(posedge axi.clk or negedge axi.rstn) begin
        if (!axi.rstn) begin
            mask_q <= '0;
        end else if (reg_wen && (waddr_off == OFF_MASK)) begin
            mask_q <= reg_wdata[NUM_SOURCES-1:0];
        end
    end

    always_comb begin
        case (raddr_off)
            OFF_SOURCE_STATUS:  reg_rdata = {{(DATA_WIDTH-NUM_SOURCES){1'b0}}, periph_irq};
            OFF_MASK:           reg_rdata = {{(DATA_WIDTH-NUM_SOURCES){1'b0}}, mask_q};
            OFF_MASKED_PENDING: reg_rdata = {{(DATA_WIDTH-NUM_SOURCES){1'b0}}, masked_pending};
            default:            reg_rdata = '0;
        endcase
    end

endmodule : intr_ctrl_axi4lite
