# Register Map

All registers are 32 bits, word-aligned. Addresses below are offsets from
the subsystem's base address (i.e. exactly what a CPU/testbench drives on
`s_axi.awaddr` / `s_axi.araddr`).

## Address Map

| Region  | Base Offset  | Size  |
|---------|--------------|-------|
| GPIO    | `0x0000_0000` | 4 KB  |
| UART    | `0x0000_1000` | 4 KB  |
| Timer   | `0x0000_2000` | 4 KB  |
| INTC    | `0x0000_3000` | 4 KB  |

## GPIO (base + …)

| Offset | Name           | Access | Description |
|--------|-----------------|--------|-------------|
| `0x00` | `GPIO_DATA`      | R/W    | Write: sets output value for pins configured as outputs. Read: live pin value for both input and output pins. |
| `0x04` | `GPIO_DIR`       | R/W    | Per-pin direction: `1` = output, `0` = input. |
| `0x08` | `GPIO_INT_EN`    | R/W    | Per-pin rising-edge interrupt enable. |
| `0x0C` | `GPIO_INT_STATUS`| R/W1C  | Sticky per-pin rising-edge-detected flag. Write `1` to a bit to clear it. |

`GPIO_WIDTH` (default 8) sets how many of the low bits in each register are
implemented; the rest read as 0.

## UART (base + …)

| Offset | Name           | Access | Description |
|--------|-----------------|--------|-------------|
| `0x00` | `TXDATA`         | W      | Writing a byte starts a transmission if the transmitter is idle. |
| `0x04` | `RXDATA`         | R      | Most recently received byte. Reading clears the "unread byte" status bit. |
| `0x08` | `STATUS`         | R      | bit0 `tx_busy`, bit1 `rx_valid` (unread byte waiting), bit2 `tx_ready` (`= !tx_busy`). |
| `0x0C` | `CTRL`           | R/W    | bits `[15:0]` = `baud_div` (clk cycles per bit); bit `16` = UART enable. |
| `0x10` | `INT_EN`         | R/W    | bit0 tx-done interrupt enable, bit1 rx-valid interrupt enable. |
| `0x14` | `INT_STATUS`     | R/W1C  | bit0 sticky tx-done flag, bit1 sticky rx-valid flag. Write `1` to a bit to clear it. |

`baud_div = clk_freq_hz / desired_baud_rate`. Default reset value
(16'd868) targets ~115200 baud at a 100 MHz `clk`.

## Timer (base + …)

| Offset | Name           | Access | Description |
|--------|-----------------|--------|-------------|
| `0x00` | `LOAD`           | R/W    | Reload value for the down-counter. |
| `0x04` | `VALUE`          | R      | Current counter value. |
| `0x08` | `CTRL`           | R/W    | bit0 enable (writing `1` also (re)arms the counter from `LOAD`), bit1 mode (`0` = one-shot, `1` = periodic). |
| `0x0C` | `INT_EN`         | R/W    | bit0 timeout interrupt enable. |
| `0x10` | `INT_STATUS`     | R/W1C  | bit0 sticky timeout flag. Write `1` to clear. |

The counter decrements once per `clk` cycle while running; add an internal
prescaler if you need a longer period than `2^32` clock cycles or a
specific real-time tick rate from a fast system clock.

## Interrupt Controller (base + …)

| Offset | Name             | Access | Description |
|--------|-------------------|--------|-------------|
| `0x00` | `SOURCE_STATUS`    | R      | Live level of each peripheral's IRQ output: bit0 GPIO, bit1 UART, bit2 Timer. |
| `0x04` | `MASK`             | R/W    | Per-source enable, same bit order as `SOURCE_STATUS`. |
| `0x08` | `MASKED_PENDING`   | R      | `SOURCE_STATUS & MASK` — exactly what's driving `irq_out` right now. |

A typical ISR reads `MASKED_PENDING` to identify the source(s), then
clears the corresponding peripheral's own `INT_STATUS` register (the
interrupt controller has no `INT_STATUS`/clear of its own — see
[`architecture.md`](architecture.md) for why).
