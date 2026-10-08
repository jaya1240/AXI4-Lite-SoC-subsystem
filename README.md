# AMBA AXI4-Lite-Based SoC Peripheral Subsystem

A small, synthesizable SoC peripheral subsystem in **SystemVerilog**,
built around the **AMBA AXI4-Lite** protocol: an AXI4-Lite slave interface
reused by four memory-mapped peripherals — **GPIO**, **UART**, a **Timer**,
and an **interrupt controller** — connected through a lightweight
address-decoded interconnect, with a self-checking testbench and
Vivado synthesis/timing-analysis scripts.

## Features

- **Reusable AXI4-Lite slave FSM** (`axi4_lite_slave_fsm.sv`) — implements
  the AW/W/B write handshake and AR/R read handshake once; every
  peripheral wraps it with just a register file.
- **GPIO** — direction-configurable pins, readback, per-pin rising-edge
  interrupts.
- **UART** — 8-N-1 TX/RX cores with a configurable baud-rate divisor,
  status/control registers, and TX-done / RX-valid interrupts.
- **Timer** — one-shot or periodic down-counter with a timeout interrupt.
- **Interrupt controller** — masks and OR-reduces the three peripheral IRQ
  lines into a single CPU-facing `irq_out`, with a status register an ISR
  can use to identify the source.
- **Address-decoded AXI4-Lite interconnect** — one master port, four
  4 KB-per-peripheral slave regions, with a clean DECERR response (not a
  bus hang) for accesses to unmapped addresses.
- **Self-checking SystemVerilog testbench** with an AXI4-Lite master BFM
  (no external verification IP required) exercising every peripheral,
  including a UART loopback test, an end-to-end interrupt-controller
  test, and corner cases: unmapped-address DECERR, GPIO writes to
  input-configured pins being correctly ignored, a timer armed with
  `LOAD=0` firing immediately, and back-to-back UART transmission with no
  idle gap between bytes.
- **SystemVerilog assertions**, bound automatically (no manual wiring)
  into every AXI4-Lite interface instance and into the top-level module:
  bus-protocol checks (VALID/READY stability, no unknown values on
  control signals) and design-level invariants (GPIO output-enable
  matches its direction register, the interrupt controller's output
  matches its mask, the timer counts down monotonically).
- **Waveform-based debugging**: the testbench dumps a VCD (`waves.vcd`)
  on every run, viewable in GTKWave or any other VCD-capable viewer.
- **Synthesis + timing analysis scripts** for Vivado (non-project batch
  mode) producing utilization and timing-summary reports.

## Repository Layout

```
axi4-lite-soc-peripheral-subsystem/
├── rtl/
│   ├── axi4_lite_if.sv               # AXI4-Lite interface (master/slave modports)
│   ├── axi4_lite_slave_fsm.sv        # shared AW/W/B + AR/R protocol FSM
│   ├── axi4_lite_protocol_sva.sv     # bus-protocol assertions, bound to every axi4_lite_if instance
│   ├── axi4_lite_interconnect.sv     # 1-master / 4-slave address decoder
│   ├── gpio_axi4lite.sv
│   ├── uart_axi4lite.sv
│   ├── uart_tx.sv
│   ├── uart_rx.sv
│   ├── timer_axi4lite.sv
│   ├── intr_ctrl_axi4lite.sv
│   ├── soc_peripheral_subsystem_top.sv
│   └── soc_peripheral_subsystem_sva.sv # design-level assertions, bound into the top module
├── tb/
│   └── tb_soc_peripheral_subsystem.sv
├── sim/
│   ├── run_sim.sh                    # Vivado xsim (non-project) flow
│   └── run_questa.do                 # ModelSim/Questa flow
├── scripts/
│   └── synth.tcl                     # Vivado out-of-context synthesis + timing reports
├── constraints/
│   └── soc_peripheral_subsystem.xdc  # 100 MHz clock, false paths for slow I/O
├── docs/
│   ├── architecture.md               # block diagram, design rationale
│   └── register_map.md               # full per-peripheral register reference
└── LICENSE
```

## Simulating

**Vivado (xsim):**
```bash
chmod +x sim/run_sim.sh
./sim/run_sim.sh
```

**ModelSim/Questa:**
```bash
vsim -c -do sim/run_questa.do
```

Either way, the testbench prints a `[PASS]`/`[FAIL]` line per check
(GPIO direction/readback/interrupt, UART loopback byte + interrupts,
timer timeout, interrupt-controller masking, plus the corner cases listed
above) and a final `ALL TESTS PASSED` / `N TEST(S) FAILED` summary. Watch
the log for `[SVA]`-prefixed `$error` messages too — those come from the
bound assertions, not the directed checks, and indicate a protocol or
design-invariant violation rather than a functional mismatch. A
`waves.vcd` file is written every run for waveform-based debugging in
GTKWave or any other VCD viewer.

> This RTL was written and reviewed against the AXI4-Lite protocol
> carefully by hand, but wasn't run through an actual simulator in the
> environment this repo was generated in (no SystemVerilog simulator
> available). **Run the testbench yourself before relying on it** — see
> the note at the bottom of this README.

## Synthesis & Timing Analysis

```bash
vivado -mode batch -source scripts/synth.tcl
```

Produces, under `reports/`:
- `utilization.rpt` — LUT/FF/BRAM usage post-synthesis
- `timing_summary.rpt` — WNS/TNS/WHS/THS summary
- `timing_worst_paths.rpt` — the 10 worst setup paths

The default target part in `scripts/synth.tcl` is an Arty A7-35T
(`xc7a35ticsg324-1L`); change the `part` variable for your own board/part.

## Address Map (summary)

| Peripheral | Base Offset  |
|------------|--------------|
| GPIO       | `0x0000_0000` |
| UART       | `0x0000_1000` |
| Timer      | `0x0000_2000` |
| Interrupt Controller | `0x0000_3000` |

Full register-level detail: [`docs/register_map.md`](docs/register_map.md).
Block diagram and design rationale: [`docs/architecture.md`](docs/architecture.md).

## Publishing to GitHub

```bash
cd axi4-lite-soc-peripheral-subsystem
git init
git add .
git commit -m "Initial commit: AMBA AXI4-Lite SoC peripheral subsystem"
git branch -M main
git remote add origin https://github.com/<your-username>/<repo-name>.git
git push -u origin main
```

## A Note on Verification Status

Every module here follows standard, well-established patterns (a
registered-handshake AXI4-Lite slave FSM, address-region decoding, W1C
interrupt status registers, a synchronizer on the asynchronous UART RX
pin), and the testbench exercises each peripheral's full register
interface, one end-to-end interrupt scenario, and the corner cases listed
above, backed by SVA assertions bound automatically at both the bus-
protocol and design level. That said, this was generated without access
to a SystemVerilog simulator to run it against — hand-tracing the
interconnect's unmapped-address path during development did catch one
real bug this way (an access to an address with no matching peripheral
would leave `BVALID`/`RVALID` stuck low forever instead of returning a
clean error response — fixed; see `axi4_lite_interconnect.sv`'s comments),
which is exactly the kind of thing corner-case testing and assertions
exist to catch. **Please run `sim/run_sim.sh` (or the Questa flow)
yourself and treat any failure or `[SVA]` error as real** before treating
this as verified, working RTL for your portfolio.

## License

MIT — see [`LICENSE`](LICENSE).
