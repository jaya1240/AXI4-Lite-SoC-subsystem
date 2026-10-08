#!/usr/bin/env bash
# Compile and run the testbench using Vivado's non-project xsim flow.
# Requires Vivado's bin directory on PATH (xvlog, xelab, xsim).
#
# Produces waves.vcd (from $dumpfile/$dumpvars in the testbench) for
# waveform-based debugging in GTKWave, Vivado's waveform viewer, or any
# other VCD-capable viewer.
set -euo pipefail

cd "$(dirname "$0")/.."

RTL_FILES=(
    rtl/axi4_lite_if.sv
    rtl/axi4_lite_slave_fsm.sv
    rtl/axi4_lite_protocol_sva.sv
    rtl/axi4_lite_interconnect.sv
    rtl/gpio_axi4lite.sv
    rtl/uart_tx.sv
    rtl/uart_rx.sv
    rtl/uart_axi4lite.sv
    rtl/timer_axi4lite.sv
    rtl/intr_ctrl_axi4lite.sv
    rtl/soc_peripheral_subsystem_top.sv
    rtl/soc_peripheral_subsystem_sva.sv
)

TB_FILE=tb/tb_soc_peripheral_subsystem.sv

xvlog --sv "${RTL_FILES[@]}" "$TB_FILE"
xelab -debug typical tb_soc_peripheral_subsystem -s tb_sim
xsim tb_sim -runall

echo ""
echo "Waveform written to waves.vcd -- open with GTKWave or your viewer of choice."
