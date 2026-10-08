// uart_rx.sv
//
// Simple UART receiver, 8 data bits, no parity, 1 stop bit (8-N-1).
// Samples the middle of each bit period (half a bit-time after detecting
// the start-bit edge) to be tolerant of small clock/phase drift.

module uart_rx (
    input  logic        clk,
    input  logic        rstn,
    input  logic [15:0] baud_div,
    input  logic        rx_line,
    output logic [7:0]  rx_data,
    output logic        rx_valid   // one-cycle pulse when a byte is received
);

    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state;

    logic [15:0] baud_cnt;
    logic [2:0]  bit_idx;
    logic [7:0]  shift_reg;
    logic        rx_sync0, rx_sync1; // 2-FF synchronizer for the async rx pin

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
        end else begin
            rx_sync0 <= rx_line;
            rx_sync1 <= rx_sync0;
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state     <= IDLE;
            baud_cnt  <= '0;
            bit_idx   <= '0;
            shift_reg <= '0;
            rx_data   <= '0;
            rx_valid  <= 1'b0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (!rx_sync1) begin // falling edge -> start bit begins
                        baud_cnt <= '0;
                        state    <= START;
                    end
                end

                START: begin
                    // Sample at mid-bit to confirm it's a real start bit.
                    if (baud_cnt >= (baud_div >> 1)) begin
                        baud_cnt <= '0;
                        bit_idx  <= '0;
                        state    <= rx_sync1 ? IDLE : DATA; // glitch reject
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                DATA: begin
                    if (baud_cnt >= baud_div - 1) begin
                        baud_cnt           <= '0;
                        shift_reg[bit_idx] <= rx_sync1;
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
                    if (baud_cnt >= baud_div - 1) begin
                        baud_cnt <= '0;
                        rx_data  <= shift_reg;
                        rx_valid <= 1'b1;
                        state    <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule : uart_rx
