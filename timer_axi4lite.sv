// timer_axi4lite.sv
//
// Down-counting timer peripheral, AXI4-Lite addressable.
//
// Register map:
//   0x00  LOAD        R/W   reload value
//   0x04  VALUE       R     current counter value
//   0x08  CTRL        R/W   bit0 enable, bit1 mode (0=one-shot, 1=periodic)
//   0x0C  INT_EN      R/W   bit0 timeout interrupt enable
//   0x10  INT_STATUS  R/W1C bit0 sticky timeout flag
//
// The counter decrements once per `clk` cycle while enabled (a real SoC
// would typically prescale this from a faster system clock -- add a
// prescaler counter here if your target clock is much faster than the
// timer resolution you want).

module timer_axi4lite #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    axi4_lite_if.slave axi,
    output logic irq
);

    localparam logic [7:0] OFF_LOAD       = 8'h00;
    localparam logic [7:0] OFF_VALUE      = 8'h04;
    localparam logic [7:0] OFF_CTRL       = 8'h08;
    localparam logic [7:0] OFF_INT_EN     = 8'h0C;
    localparam logic [7:0] OFF_INT_STATUS = 8'h10;

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

    logic [31:0] load_q;
    logic [31:0] value_q;
    logic        enable_q;
    logic        periodic_q;
    logic        running_q;   // internal "still counting" flag for one-shot
    logic        int_en_q;
    logic        int_status_q;

    assign irq = int_status_q & int_en_q;

    always_ff @(posedge axi.clk or negedge axi.rstn) begin
        if (!axi.rstn) begin
            load_q       <= 32'hFFFF_FFFF;
            value_q      <= 32'hFFFF_FFFF;
            enable_q     <= 1'b0;
            periodic_q   <= 1'b0;
            running_q    <= 1'b0;
            int_en_q     <= 1'b0;
            int_status_q <= 1'b0;
        end else begin
            // Counting
            if (enable_q && running_q) begin
                if (value_q == 32'd0) begin
                    int_status_q <= 1'b1;
                    if (periodic_q) begin
                        value_q  <= load_q;
                        running_q <= 1'b1;
                    end else begin
                        running_q <= 1'b0; // one-shot: stop until re-armed
                    end
                end else begin
                    value_q <= value_q - 1'b1;
                end
            end

            if (reg_wen) begin
                case (waddr_off)
                    OFF_LOAD: load_q <= reg_wdata;
                    OFF_CTRL: begin
                        enable_q   <= reg_wdata[0];
                        periodic_q <= reg_wdata[1];
                        // Writing CTRL with enable=1 (re)arms the counter
                        // from LOAD -- this is how software restarts a
                        // one-shot timer after it fires.
                        if (reg_wdata[0]) begin
                            value_q   <= load_q;
                            running_q <= 1'b1;
                        end
                    end
                    OFF_INT_EN: int_en_q <= reg_wdata[0];
                    OFF_INT_STATUS: int_status_q <= int_status_q & ~reg_wdata[0]; // W1C
                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        case (raddr_off)
            OFF_LOAD:       reg_rdata = load_q;
            OFF_VALUE:      reg_rdata = value_q;
            OFF_CTRL:       reg_rdata = {30'b0, periodic_q, enable_q};
            OFF_INT_EN:     reg_rdata = {31'b0, int_en_q};
            OFF_INT_STATUS: reg_rdata = {31'b0, int_status_q};
            default:        reg_rdata = '0;
        endcase
    end

endmodule : timer_axi4lite
