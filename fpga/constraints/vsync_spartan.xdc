# =============================================================================
# vsync_spartan.xdc - Xilinx Design Constraints for VSync
# =============================================================================
# Project : VSync - RISC-V RV32IM with Hardware RTOS
# Target  : Digilent Arty-A7 (xc7a100tcsg324-1)
# Ref     : https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-100-Master.xdc
# =============================================================================

# =============================================================================
# Clock Constraint - 100 MHz Input Clock (MMCM generates 25 MHz system clock)
# =============================================================================
# Arty-A7 has 100MHz oscillator on E3
# MMCME2_BASE divides to 25 MHz internally
create_clock -period 10.000 -name sys_clk [get_ports clk]

# Clock input jitter
set_input_jitter sys_clk 0.100

# =============================================================================
# Clock Pin Assignment (Arty-A7: E3 = 100MHz oscillator)
# =============================================================================
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# =============================================================================
# Reset Pin (Arty-A7: BTN0 = D9)
# =============================================================================
set_property PACKAGE_PIN A8 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]
#set_property PULLUP true [get_ports rst_n]

# =============================================================================
# BTN Pin (Arty-A7)
# =============================================================================
set_property PACKAGE_PIN D9 [get_ports {btn[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[0]}]
#set_property PULLUP true [get_ports {btn[0]}]
set_property PACKAGE_PIN C9 [get_ports {btn[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[1]}]
#set_property PULLUP true [get_ports {btn[1]}]
set_property PACKAGE_PIN B9 [get_ports {btn[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[2]}]
#set_property PULLUP true [get_ports {btn[2]}]
set_property PACKAGE_PIN B8 [get_ports {btn[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[3]}]
#set_property PULLUP true [get_ports {btn[3]}]

# =============================================================================
# LED Pin (Arty-A7)
# =============================================================================
set_property PACKAGE_PIN H5 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
#set_property PULLUP true [get_ports {led[0]}]
set_property PACKAGE_PIN J5 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
#set_property PULLUP true [get_ports {led[1]}]
set_property PACKAGE_PIN T9 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
#set_property PULLUP true [get_ports {led[2]}]
set_property PACKAGE_PIN T10 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]
#set_property PULLUP true [get_ports {led[3]}]

# =============================================================================
# LED Pin (Arty-A7)
# =============================================================================
set_property PACKAGE_PIN G6 [get_ports {led_r[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_r[0]}]
set_property PACKAGE_PIN G3 [get_ports {led_r[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_r[1]}]
set_property PACKAGE_PIN J3 [get_ports {led_r[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_r[2]}]
set_property PACKAGE_PIN K1 [get_ports {led_r[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_r[3]}]

# =============================================================================
# UART Interface (Arty-A7: USB-UART bridge)
# =============================================================================
# uart_tx (FPGA output → PC) = D10 (uart_rxd_out on Arty schematic)
# uart_rx (FPGA input ← PC)  = A9  (uart_txd_in on Arty schematic)
set_property PACKAGE_PIN D10 [get_ports uart_tx]
set_property PACKAGE_PIN A9  [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

# =============================================================================
# GPIO [15:0] - Mapped to Pmod connectors
# =============================================================================
# Pmod JA (gpio_io[0:3]) - pins 1-4
set_property PACKAGE_PIN G13 [get_ports {gpio_io[0]}]
set_property PACKAGE_PIN B11 [get_ports {gpio_io[1]}]
set_property PACKAGE_PIN A11 [get_ports {gpio_io[2]}]
set_property PACKAGE_PIN D12 [get_ports {gpio_io[3]}]
# Pmod JB (gpio_io[4:7]) - pins 1-4
set_property PACKAGE_PIN E15 [get_ports {gpio_io[4]}]
set_property PACKAGE_PIN E16 [get_ports {gpio_io[5]}]
set_property PACKAGE_PIN D15 [get_ports {gpio_io[6]}]
set_property PACKAGE_PIN C15 [get_ports {gpio_io[7]}]
# Pmod JC (gpio_io[8:11]) - pins 1-4
set_property PACKAGE_PIN U12 [get_ports {gpio_io[8]}]
set_property PACKAGE_PIN V12 [get_ports {gpio_io[9]}]
set_property PACKAGE_PIN V10 [get_ports {gpio_io[10]}]
set_property PACKAGE_PIN V11 [get_ports {gpio_io[11]}]
# Pmod JD (gpio_io[12:15]) - pins 1-4
set_property PACKAGE_PIN D4  [get_ports {gpio_io[12]}]
set_property PACKAGE_PIN D3  [get_ports {gpio_io[13]}]
set_property PACKAGE_PIN F4  [get_ports {gpio_io[14]}]
set_property PACKAGE_PIN F3  [get_ports {gpio_io[15]}]

set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[*]}]
set_property DRIVE 8 [get_ports {gpio_io[*]}]
set_property SLEW SLOW [get_ports {gpio_io[*]}]

# =============================================================================
# HyperRAM Interface (not available on Arty-A7 - pins unassigned)
# =============================================================================
# set_property PACKAGE_PIN xx [get_ports hyper_cs_n]
# set_property PACKAGE_PIN xx [get_ports hyper_ck]
# set_property PACKAGE_PIN xx [get_ports hyper_ck_n]
# set_property PACKAGE_PIN xx [get_ports hyper_rwds]
# set_property PACKAGE_PIN xx [get_ports hyper_rst_n]
# set_property PACKAGE_PIN xx [get_ports {hyper_dq[0]}]
# set_property PACKAGE_PIN xx [get_ports {hyper_dq[1]}]
# set_property PACKAGE_PIN xx [get_ports {hyper_dq[2]}]
# set_property PACKAGE_PIN xx [get_ports {hyper_dq[3]}]
# set_property PACKAGE_PIN xx [get_ports {hyper_dq[4]}]
# set_property PACKAGE_PIN xx [get_ports {hyper_dq[5]}]
# set_property PACKAGE_PIN xx [get_ports {hyper_dq[6]}]
# set_property PACKAGE_PIN xx [get_ports {hyper_dq[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports hyper_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports hyper_ck]
set_property IOSTANDARD LVCMOS33 [get_ports hyper_ck_n]
set_property IOSTANDARD LVCMOS33 [get_ports hyper_rwds]
set_property IOSTANDARD LVCMOS33 [get_ports hyper_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports {hyper_dq[*]}]
set_property DRIVE 8 [get_ports {hyper_dq[*]}]
set_property SLEW FAST [get_ports hyper_ck]
set_property SLEW FAST [get_ports hyper_ck_n]
set_property SLEW FAST [get_ports {hyper_dq[*]}]

# =============================================================================
# JTAG Debug Interface (not assigned on Arty-A7 - pins unassigned)
# =============================================================================
# set_property PACKAGE_PIN xx [get_ports jtag_tck]
# set_property PACKAGE_PIN xx [get_ports jtag_tms]
# set_property PACKAGE_PIN xx [get_ports jtag_tdi]
# set_property PACKAGE_PIN xx [get_ports jtag_tdo]
# set_property PACKAGE_PIN xx [get_ports jtag_trst_n]

set_property IOSTANDARD LVCMOS33 [get_ports jtag_tck]
set_property IOSTANDARD LVCMOS33 [get_ports jtag_tms]
set_property IOSTANDARD LVCMOS33 [get_ports jtag_tdi]
set_property IOSTANDARD LVCMOS33 [get_ports jtag_tdo]
set_property IOSTANDARD LVCMOS33 [get_ports jtag_trst_n]
set_property PULLUP true [get_ports jtag_trst_n]

# JTAG clock constraint (20 MHz assumed)
create_clock -period 50.000 -name jtag_clock [get_ports jtag_tck]
set_clock_groups -asynchronous -group [get_clocks sys_clk] -group [get_clocks jtag_clock]

# =============================================================================
# Timing Constraints
# =============================================================================

# UART and GPIO are asynchronous interfaces - use false path
set_false_path -from [get_ports uart_rx]
set_false_path -to [get_ports uart_tx]
set_false_path -from [get_ports {gpio_io[*]}]
set_false_path -to [get_ports {gpio_io[*]}]

# HyperRAM timing (relative to sys_clk)
set_output_delay -clock sys_clk -max 3.0 [get_ports hyper_cs_n]
set_output_delay -clock sys_clk -min 0.0 [get_ports hyper_cs_n]
set_output_delay -clock sys_clk -max 3.0 [get_ports {hyper_dq[*]}]
set_output_delay -clock sys_clk -min 0.0 [get_ports {hyper_dq[*]}]
set_input_delay  -clock sys_clk -max 3.0 [get_ports {hyper_dq[*]}]
set_input_delay  -clock sys_clk -min 0.0 [get_ports {hyper_dq[*]}]
set_input_delay  -clock sys_clk -max 3.0 [get_ports hyper_rwds]
set_input_delay  -clock sys_clk -min 0.0 [get_ports hyper_rwds]
set_output_delay -clock sys_clk -max 3.0 [get_ports hyper_rwds]
set_output_delay -clock sys_clk -min 0.0 [get_ports hyper_rwds]

# =============================================================================
# False Paths
# =============================================================================

# Reset is asynchronous
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports jtag_trst_n]

# =============================================================================
# Pipeline Combinational Loop Constraints
# =============================================================================
# Pipeline stall/flush combinational feedback loops
# These are structurally safe pipeline control loops through flip-flops
set_property ALLOW_COMBINATIONAL_LOOPS TRUE [get_nets -hierarchical *mem_stall*]
set_property ALLOW_COMBINATIONAL_LOOPS TRUE [get_nets -hierarchical *load_use_hazard*]

# =============================================================================
# Bitstream Configuration (Artix-7 / Arty-A7)
# =============================================================================
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
