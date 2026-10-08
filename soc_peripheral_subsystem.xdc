# Timing constraints for soc_peripheral_subsystem_top.
# Adjust the clock period / pin locations for your actual target board.

create_clock -name clk -period 10.000 [get_ports clk]

# Reset is asynchronous to the design's timing paths.
set_false_path -from [get_ports rstn]

# UART/GPIO pins are slow, asynchronous-to-the-outside-world I/O -- exclude
# them from setup/hold analysis against the system clock. In a real board
# constraints file you'd instead constrain them relative to their actual
# external timing requirements.
set_false_path -from [get_ports {gpio_in[*]}]
set_false_path -to   [get_ports {gpio_out[*] gpio_oe[*]}]
set_false_path -from [get_ports uart_rx]
set_false_path -to   [get_ports uart_tx]
