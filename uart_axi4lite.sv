// uart_axi4lite.sv
//
// UART peripheral, AXI4-Lite addressable, wrapping uart_tx / uart_rx.
//
// Register map:
//   0x00  TXDATA       W     writing a byte starts a transmission (if idle)
//   0x04  RXDATA       R     most recently received byte
//   0x08  STATUS       R     bit0 tx_busy, bit1 rx_valid (unread byte ready),
//                            bit2 tx_ready (= !tx_busy)
//   0x0C  CTRL         R/W   [15:0] baud_div, [16] uart_enable
//   0x10  INT_EN       R/W   bit0 tx_done_ie, bit1 rx_valid_ie
//   0x14  INT_STATUS   R/W1C bit0 tx_done sticky, bit1 rx_valid sticky

module uart_axi4lite #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    axi4_lite_if.slave axi,

    output logic uart_tx_line,
    input  logic uart_rx_line,
    output logic irq
);

    localparam logic [7:0] OFF_TXDATA     = 8'h00;
    localparam logic [7:0] OFF_RXDATA     = 8'h04;
    localparam logic [7:0] OFF_STATUS     = 8'h08;
    localparam logic [7:0] OFF_CTRL       = 8'h0C;
    localparam logic [7:0] OFF_INT_EN     = 8'h10;
    localparam logic [7:0] OFF_INT_STATUS = 8'h14;

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

    logic [15:0] baud_div_q;
    logic        uart_en_q;
    logic [1:0]  int_en_q;
    logic [1:0]  int_status_q;

    logic tx_start;
    logic tx_busy, tx_done;
    logic [7:0] rx_data_latched;
    logic rx_valid_pulse, rx_valid_flag;

    uart_tx u_tx (
        .clk      (axi.clk),
        .rstn     (axi.rstn),
        .baud_div (baud_div_q),
        .tx_data  (reg_wdata[7:0]),
        .tx_start (tx_start),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done),
        .tx_line  (uart_tx_line)
    );

    uart_rx u_rx (
        .clk      (axi.clk),
        .rstn     (axi.rstn),
        .baud_div (baud_div_q),
        .rx_line  (uart_rx_line),
        .rx_data  (rx_data_latched),
        .rx_valid (rx_valid_pulse)
    );

    assign tx_start = reg_wen && (waddr_off == OFF_TXDATA) && !tx_busy;
    assign irq      = |(int_status_q & int_en_q);

    always_ff @(posedge axi.clk or negedge axi.rstn) begin
        if (!axi.rstn) begin
            baud_div_q    <= 16'd868; // ~115200 baud @ 100 MHz default
            uart_en_q     <= 1'b1;
            int_en_q      <= '0;
            int_status_q  <= '0;
            rx_valid_flag <= 1'b0;
        end else begin
            if (rx_valid_pulse) begin
                rx_valid_flag <= 1'b1;
            end

            if (tx_done) begin
                int_status_q[0] <= 1'b1;
            end
            if (rx_valid_pulse) begin
                int_status_q[1] <= 1'b1;
            end

            if (reg_wen) begin
                case (waddr_off)
                    OFF_CTRL: begin
                        baud_div_q <= reg_wdata[15:0];
                        uart_en_q  <= reg_wdata[16];
                    end
                    OFF_INT_EN: int_en_q <= reg_wdata[1:0];
                    OFF_INT_STATUS: int_status_q <= int_status_q & ~reg_wdata[1:0]; // W1C
                    OFF_RXDATA: ; // read-only, ignore writes
                    default: ;
                endcase
            end

            // Reading RXDATA clears the "unread byte" flag.
            if (reg_ren && (raddr_off == OFF_RXDATA)) begin
                rx_valid_flag <= 1'b0;
            end
        end
    end

    always_comb begin
        case (raddr_off)
            OFF_RXDATA: reg_rdata = {24'b0, rx_data_latched};
            OFF_STATUS: reg_rdata = {29'b0, !tx_busy, rx_valid_flag, tx_busy};
            OFF_CTRL:   reg_rdata = {15'b0, uart_en_q, baud_div_q};
            OFF_INT_EN: reg_rdata = {30'b0, int_en_q};
            OFF_INT_STATUS: reg_rdata = {30'b0, int_status_q};
            default:    reg_rdata = '0;
        endcase
    end

endmodule : uart_axi4lite
