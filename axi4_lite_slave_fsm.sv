// axi4_lite_slave_fsm.sv
//
// Reusable AXI4-Lite slave bus logic. Handles the AW/W/B write handshake and
// the AR/R read handshake and exposes a plain, single-cycle register-style
// interface (reg_wen/reg_ren/reg_waddr/reg_raddr/reg_wdata/reg_wstrb ->
// reg_rdata) so each peripheral only has to implement its own register
// file, not the AXI protocol itself.
//
// Simplifications appropriate for a peripheral (not a high-throughput
// memory) slave: single outstanding transaction at a time per channel,
// AWVALID and WVALID are required together before a write is accepted
// (common in simple AXI-Lite peripheral templates), and every response is
// OKAY. Write and read channels run independently, as AXI4-Lite allows.

module axi4_lite_slave_fsm #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    axi4_lite_if.slave axi,

    // Local register-file side
    output logic                      reg_wen,    // one-cycle write strobe
    output logic                      reg_ren,    // one-cycle read strobe
    output logic [ADDR_WIDTH-1:0]     reg_waddr,  // valid alongside reg_wen
    output logic [ADDR_WIDTH-1:0]     reg_raddr,  // valid alongside reg_ren
    output logic [DATA_WIDTH-1:0]     reg_wdata,
    output logic [DATA_WIDTH/8-1:0]   reg_wstrb,
    input  logic [DATA_WIDTH-1:0]     reg_rdata   // combinational, addr -> data
);

    localparam logic [1:0] RESP_OKAY = 2'b00;

    // ------------------------------------------------------------------
    // Write channel
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {W_IDLE, W_RESP} wstate_t;
    wstate_t wstate;

    always_ff @(posedge axi.clk or negedge axi.rstn) begin
        if (!axi.rstn) begin
            wstate      <= W_IDLE;
            axi.awready <= 1'b0;
            axi.wready  <= 1'b0;
            axi.bvalid  <= 1'b0;
            axi.bresp   <= RESP_OKAY;
            reg_wen     <= 1'b0;
            reg_waddr   <= '0;
            reg_wdata   <= '0;
            reg_wstrb   <= '0;
        end else begin
            reg_wen <= 1'b0;

            case (wstate)
                W_IDLE: begin
                    // Accept a write only once both address and data are
                    // presented together.
                    if (axi.awvalid && axi.wvalid) begin
                        axi.awready <= 1'b1;
                        axi.wready  <= 1'b1;
                        reg_waddr   <= axi.awaddr;
                        reg_wdata   <= axi.wdata;
                        reg_wstrb   <= axi.wstrb;
                        reg_wen     <= 1'b1;
                        axi.bvalid  <= 1'b1;
                        wstate      <= W_RESP;
                    end else begin
                        axi.awready <= 1'b0;
                        axi.wready  <= 1'b0;
                    end
                end

                W_RESP: begin
                    axi.awready <= 1'b0;
                    axi.wready  <= 1'b0;
                    if (axi.bvalid && axi.bready) begin
                        axi.bvalid <= 1'b0;
                        wstate     <= W_IDLE;
                    end
                end

                default: wstate <= W_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Read channel
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {R_IDLE, R_DATA} rstate_t;
    rstate_t rstate;

    always_ff @(posedge axi.clk or negedge axi.rstn) begin
        if (!axi.rstn) begin
            rstate      <= R_IDLE;
            axi.arready <= 1'b0;
            axi.rvalid  <= 1'b0;
            axi.rresp   <= RESP_OKAY;
            axi.rdata   <= '0;
            reg_ren     <= 1'b0;
            reg_raddr   <= '0;
        end else begin
            reg_ren <= 1'b0;

            case (rstate)
                R_IDLE: begin
                    if (axi.arvalid) begin
                        axi.arready <= 1'b1;
                        reg_raddr   <= axi.araddr;
                        reg_ren     <= 1'b1;
                        rstate      <= R_DATA;
                    end else begin
                        axi.arready <= 1'b0;
                    end
                end

                R_DATA: begin
                    axi.arready <= 1'b0;
                    axi.rvalid  <= 1'b1;
                    axi.rdata   <= reg_rdata; // register file drove this off reg_ren/reg_raddr last cycle
                    if (axi.rvalid && axi.rready) begin
                        axi.rvalid <= 1'b0;
                        rstate     <= R_IDLE;
                    end
                end

                default: rstate <= R_IDLE;
            endcase
        end
    end

endmodule : axi4_lite_slave_fsm
