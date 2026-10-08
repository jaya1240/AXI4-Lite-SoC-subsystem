// gpio_axi4lite.sv
//
// GPIO peripheral, AXI4-Lite addressable.
//
// Register map (offsets from the peripheral's base address):
//   0x00  GPIO_DATA        R/W   bit[i] = output value (if DIR[i]=1) on write;
//                                on read, bit[i] = live pin value for both
//                                input and output pins (readback).
//   0x04  GPIO_DIR         R/W   bit[i] = 1 -> pin i is an output, 0 -> input
//   0x08  GPIO_INT_EN      R/W   bit[i] = 1 -> rising edge on pin i (while an
//                                input) raises an interrupt
//   0x0C  GPIO_INT_STATUS  R/W1C bit[i] = sticky rising-edge-detected flag;
//                                write 1 to a bit to clear it

module gpio_axi4lite #(
    parameter int GPIO_WIDTH = 8,
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    axi4_lite_if.slave axi,

    input  logic [GPIO_WIDTH-1:0] gpio_in,
    output logic [GPIO_WIDTH-1:0] gpio_out,
    output logic [GPIO_WIDTH-1:0] gpio_oe,   // 1 = drive gpio_out onto the pad
    output logic                  irq
);

    localparam logic [7:0] OFF_DATA       = 8'h00;
    localparam logic [7:0] OFF_DIR        = 8'h04;
    localparam logic [7:0] OFF_INT_EN     = 8'h08;
    localparam logic [7:0] OFF_INT_STATUS = 8'h0C;

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

    logic [GPIO_WIDTH-1:0] dir_q;       // 1 = output
    logic [GPIO_WIDTH-1:0] out_q;
    logic [GPIO_WIDTH-1:0] int_en_q;
    logic [GPIO_WIDTH-1:0] int_status_q;
    logic [GPIO_WIDTH-1:0] gpio_in_dly; // previous sample, for edge detect

    assign gpio_out = out_q;
    assign gpio_oe  = dir_q;
    assign irq      = |int_status_q;

    // Byte offset (index into the peripheral's own small address space)
    wire [7:0] waddr_off = reg_waddr[7:0];
    wire [7:0] raddr_off = reg_raddr[7:0];

    always_ff @(posedge axi.clk or negedge axi.rstn) begin
        if (!axi.rstn) begin
            dir_q         <= '0;
            out_q         <= '0;
            int_en_q      <= '0;
            int_status_q  <= '0;
            gpio_in_dly   <= '0;
        end else begin
            gpio_in_dly <= gpio_in;

            // Rising-edge detection, latched sticky per enabled pin.
            int_status_q |= (gpio_in & ~gpio_in_dly) & int_en_q;

            if (reg_wen) begin
                case (waddr_off)
                    OFF_DATA:   out_q    <= reg_wdata[GPIO_WIDTH-1:0];
                    OFF_DIR:    dir_q    <= reg_wdata[GPIO_WIDTH-1:0];
                    OFF_INT_EN: int_en_q <= reg_wdata[GPIO_WIDTH-1:0];
                    OFF_INT_STATUS: int_status_q <= int_status_q & ~reg_wdata[GPIO_WIDTH-1:0]; // W1C
                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        case (raddr_off)
            OFF_DATA:       reg_rdata = {{(DATA_WIDTH-GPIO_WIDTH){1'b0}}, (dir_q & out_q) | (~dir_q & gpio_in)};
            OFF_DIR:        reg_rdata = {{(DATA_WIDTH-GPIO_WIDTH){1'b0}}, dir_q};
            OFF_INT_EN:     reg_rdata = {{(DATA_WIDTH-GPIO_WIDTH){1'b0}}, int_en_q};
            OFF_INT_STATUS: reg_rdata = {{(DATA_WIDTH-GPIO_WIDTH){1'b0}}, int_status_q};
            default:        reg_rdata = '0;
        endcase
    end

endmodule : gpio_axi4lite
