// uart_tx.sv
//
// Simple UART transmitter, 8 data bits, no parity, 1 stop bit (8-N-1).
// `baud_div` is the number of `clk` cycles per bit period
// (baud_div = clk_freq_hz / baud_rate), loaded by the register interface.

module uart_tx (
    input  logic        clk,
    input  logic        rstn,
    input  logic [15:0] baud_div,
    input  logic [7:0]  tx_data,
    input  logic        tx_start,   // one-cycle pulse to begin a transmission
    output logic        tx_busy,
    output logic        tx_done,    // one-cycle pulse when the stop bit completes
    output logic        tx_line
);

    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state;

    logic [15:0] baud_cnt;
    logic [2:0]  bit_idx;
    logic [7:0]  shift_reg;

    assign tx_busy = (state != IDLE);

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state     <= IDLE;
            tx_line   <= 1'b1; // idle high
            baud_cnt  <= '0;
            bit_idx   <= '0;
            shift_reg <= '0;
            tx_done   <= 1'b0;
        end else begin
            tx_done <= 1'b0;

            case (state)
                IDLE: begin
                    tx_line <= 1'b1;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        baud_cnt  <= '0;
                        state     <= START;
                    end
                end

                START: begin
                    tx_line <= 1'b0; // start bit
                    if (baud_cnt >= baud_div - 1) begin
                        baud_cnt <= '0;
                        bit_idx  <= '0;
                        state    <= DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                DATA: begin
                    tx_line <= shift_reg[0];
                    if (baud_cnt >= baud_div - 1) begin
                        baud_cnt  <= '0;
                        shift_reg <= shift_reg >> 1;
                        if (bit_idx == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                STOP: begin
                    tx_line <= 1'b1; // stop bit
                    if (baud_cnt >= baud_div - 1) begin
                        baud_cnt <= '0;
                        tx_done  <= 1'b1;
                        state    <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule : uart_tx
