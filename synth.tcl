# Vivado non-project-mode synthesis + timing analysis for the AXI4-Lite
# SoC peripheral subsystem.
#
# Usage:
#   vivado -mode batch -source scripts/synth.tcl
#
# Produces, under reports/:
#   utilization.rpt   - post-synthesis resource utilization
#   timing_summary.rpt - post-synthesis timing summary (WNS/TNS/WHS/THS)
#   synth.dcp          - checkpoint for further P&R if desired

set part xc7a35ticsg324-1L  ;# Arty A7-35T; change to your target part

read_verilog -sv {
    rtl/axi4_lite_if.sv
    rtl/axi4_lite_slave_fsm.sv
    rtl/axi4_lite_interconnect.sv
    rtl/gpio_axi4lite.sv
    rtl/uart_tx.sv
    rtl/uart_rx.sv
    rtl/uart_axi4lite.sv
    rtl/timer_axi4lite.sv
    rtl/intr_ctrl_axi4lite.sv
    rtl/soc_peripheral_subsystem_top.sv
}

read_xdc constraints/soc_peripheral_subsystem.xdc

synth_design -top soc_peripheral_subsystem_top -part $part

file mkdir reports

report_utilization -file reports/utilization.rpt
report_timing_summary -file reports/timing_summary.rpt
report_timing -delay_type max -max_paths 10 -file reports/timing_worst_paths.rpt

write_checkpoint -force reports/synth.dcp

puts "Synthesis + timing analysis complete. See reports/."
