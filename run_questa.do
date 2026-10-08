# ModelSim/Questa batch simulation script.
# Usage: vsim -c -do sim/run_questa.do   (run from the repo root)
#
# Also produces waves.vcd (from the testbench's $dumpfile/$dumpvars) for
# waveform-based debugging in any VCD viewer.

vlib work

vlog -sv rtl/axi4_lite_if.sv
vlog -sv rtl/axi4_lite_slave_fsm.sv
vlog -sv rtl/axi4_lite_protocol_sva.sv
vlog -sv rtl/axi4_lite_interconnect.sv
vlog -sv rtl/gpio_axi4lite.sv
vlog -sv rtl/uart_tx.sv
vlog -sv rtl/uart_rx.sv
vlog -sv rtl/uart_axi4lite.sv
vlog -sv rtl/timer_axi4lite.sv
vlog -sv rtl/intr_ctrl_axi4lite.sv
vlog -sv rtl/soc_peripheral_subsystem_top.sv
vlog -sv rtl/soc_peripheral_subsystem_sva.sv
vlog -sv tb/tb_soc_peripheral_subsystem.sv

vsim -c work.tb_soc_peripheral_subsystem -do "run -all; quit -f"
