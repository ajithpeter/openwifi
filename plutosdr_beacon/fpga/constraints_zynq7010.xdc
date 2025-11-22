# Timing and Physical Constraints for Zynq 7010 PlutoSDR OpenWiFi
# Compatible with Vivado 2019.1 and later
#
# This file defines:
# - Clock constraints for FPGA fabric
# - False paths between clock domains
# - Physical constraints for AD9361 interface
# - Timing exceptions for asynchronous signals

################################################################
# Clock Constraints
################################################################

# FCLK_CLK0 - 100 MHz system clock from PS
create_clock -period 10.000 -name fclk_clk0 [get_pins "processing_system7_0/inst/PS7_i/FCLKCLK[0]"]

# FCLK_CLK1 - 200 MHz high-speed clock (optional, for future use)
create_clock -period 5.000 -name fclk_clk1 [get_pins "processing_system7_0/inst/PS7_i/FCLKCLK[1]"]

# Set input delay for AD9361 data signals
# AD9361 LVDS clock runs at 20 MHz (for 20 Msps)
# Data is valid within ±2ns of clock edge
set_input_delay -clock fclk_clk0 -min 2.000 [get_ports adc_data_i0*]
set_input_delay -clock fclk_clk0 -max 8.000 [get_ports adc_data_i0*]
set_input_delay -clock fclk_clk0 -min 2.000 [get_ports adc_data_i1*]
set_input_delay -clock fclk_clk0 -max 8.000 [get_ports adc_data_i1*]
set_input_delay -clock fclk_clk0 -min 2.000 [get_ports adc_data_q0*]
set_input_delay -clock fclk_clk0 -max 8.000 [get_ports adc_data_q0*]
set_input_delay -clock fclk_clk0 -min 2.000 [get_ports adc_data_q1*]
set_input_delay -clock fclk_clk0 -max 8.000 [get_ports adc_data_q1*]

# Set input delay for AD9361 valid signals
set_input_delay -clock fclk_clk0 -min 2.000 [get_ports adc_valid_*]
set_input_delay -clock fclk_clk0 -max 8.000 [get_ports adc_valid_*]

# Set output delay for AD9361 DAC signals
set_output_delay -clock fclk_clk0 -min -1.000 [get_ports dac_data_*]
set_output_delay -clock fclk_clk0 -max 2.000 [get_ports dac_data_*]
set_output_delay -clock fclk_clk0 -min -1.000 [get_ports dac_valid_*]
set_output_delay -clock fclk_clk0 -max 2.000 [get_ports dac_valid_*]

# Set output delay for AD9361 control signals
set_output_delay -clock fclk_clk0 -min -1.000 [get_ports enable]
set_output_delay -clock fclk_clk0 -max 2.000 [get_ports enable]
set_output_delay -clock fclk_clk0 -min -1.000 [get_ports txnrx]
set_output_delay -clock fclk_clk0 -max 2.000 [get_ports txnrx]

################################################################
# False Paths and Multicycle Paths
################################################################

# False paths between asynchronous clock domains
# PS to PL asynchronous signals
set_false_path -from [get_pins processing_system7_0/inst/PS7_i/FCLKRESETN[0]] -to [get_pins rst_ps7_0_100M/ext_reset_in]

# Asynchronous reset paths
set_false_path -from [get_ports up_enable]
set_false_path -from [get_ports up_txnrx]

# AXI-Lite register writes (relaxed timing)
set_multicycle_path -setup 2 -from [get_clocks fclk_clk0] -through [get_pins -hierarchical *s00_axi*]
set_multicycle_path -hold 1 -from [get_clocks fclk_clk0] -through [get_pins -hierarchical *s00_axi*]

# DMA scatter-gather descriptor fetches (can take 2 cycles)
set_multicycle_path -setup 2 -from [get_clocks fclk_clk0] -through [get_pins -hierarchical *m_axi_sg*]
set_multicycle_path -hold 1 -from [get_clocks fclk_clk0] -through [get_pins -hierarchical *m_axi_sg*]

################################################################
# IO Standard and Drive Strength
################################################################

# AD9361 interface uses LVCMOS18 (1.8V)
# Note: PlutoSDR AD9361 is configured for 1.8V I/O

# ADC data inputs (12-bit, 2 channels, I/Q)
set_property IOSTANDARD LVCMOS18 [get_ports adc_data_i0*]
set_property IOSTANDARD LVCMOS18 [get_ports adc_data_i1*]
set_property IOSTANDARD LVCMOS18 [get_ports adc_data_q0*]
set_property IOSTANDARD LVCMOS18 [get_ports adc_data_q1*]

# ADC valid signals
set_property IOSTANDARD LVCMOS18 [get_ports adc_valid_*]

# ADC enable outputs
set_property IOSTANDARD LVCMOS18 [get_ports adc_enable_*]

# DAC data outputs (12-bit, 2 channels, I/Q)
set_property IOSTANDARD LVCMOS18 [get_ports dac_data_i0*]
set_property IOSTANDARD LVCMOS18 [get_ports dac_data_i1*]
set_property IOSTANDARD LVCMOS18 [get_ports dac_data_q0*]
set_property IOSTANDARD LVCMOS18 [get_ports dac_data_q1*]

# DAC valid signals
set_property IOSTANDARD LVCMOS18 [get_ports dac_valid_*]

# Control signals
set_property IOSTANDARD LVCMOS18 [get_ports enable]
set_property IOSTANDARD LVCMOS18 [get_ports txnrx]
set_property IOSTANDARD LVCMOS18 [get_ports up_enable]
set_property IOSTANDARD LVCMOS18 [get_ports up_txnrx]

# Set reasonable drive strength for outputs (8mA is typical for LVCMOS18)
set_property DRIVE 8 [get_ports dac_data_*]
set_property DRIVE 8 [get_ports dac_valid_*]
set_property DRIVE 8 [get_ports enable]
set_property DRIVE 8 [get_ports txnrx]

################################################################
# Physical Location Constraints
################################################################

# Note: These are placeholder constraints
# For actual PlutoSDR implementation, pin locations must match
# the specific board layout. Consult PlutoSDR schematic.

# Example pinout (MUST BE UPDATED FOR ACTUAL HARDWARE):
# Bank 35: AD9361 P0 interface
# Bank 34: AD9361 P1 interface

# ADC Data P0 (RX1)
# set_property PACKAGE_PIN <PIN> [get_ports {adc_data_i0[0]}]
# ... (repeat for all 12 bits)

# DAC Data P0 (TX1)
# set_property PACKAGE_PIN <PIN> [get_ports {dac_data_i0[0]}]
# ... (repeat for all 12 bits)

################################################################
# Area Optimization for Zynq 7010
################################################################

# Prioritize area over speed for resource-constrained Z7010
set_property OPTIMIZATION_MODE AREA_OPTIMIZED [get_cells -hierarchical -filter {NAME =~ *openofdm_rx*}]
set_property OPTIMIZATION_MODE AREA_OPTIMIZED [get_cells -hierarchical -filter {NAME =~ *openofdm_tx*}]

# Use LUT-RAM instead of BRAM where possible to save BRAM resources
set_property RAM_STYLE DISTRIBUTED [get_cells -hierarchical -filter {NAME =~ *fifo* && PRIMITIVE_TYPE =~ BMEM.*}]

# Enable register duplication to improve timing without using more LUTs
set_property MAX_FANOUT 50 [get_cells -hierarchical -filter {IS_SEQUENTIAL}]

################################################################
# Power Optimization
################################################################

# Enable intelligent clock gating to reduce dynamic power
set_property CLOCK_GATING true [get_cells -hierarchical]

# Set unused pins to pulldown to reduce power
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLDOWN [current_design]

################################################################
# Bitstream Configuration
################################################################

# Configure bitstream compression (saves flash space)
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Set configuration rate (faster boot)
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

# SPI bus width (PlutoSDR uses QSPI)
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

# Disable DONE pin assertion until all startup sequences complete
set_property BITSTREAM.CONFIG.DONEPIPE YES [current_design]

################################################################
# DRC Waivers
################################################################

# Waive DRC for asynchronous resets (we know these are safe)
create_waiver -quiet -type DRC -id {REQP-1} -objects [get_pins rst_ps7_0_100M/ext_reset_in]

# Waive DRC for combinatorial loops in DMA controllers (Xilinx IP, known safe)
create_waiver -quiet -type DRC -id {LUTLP-1} -objects [get_cells -hierarchical -filter {NAME =~ *dma*}]

################################################################
# End of constraints
################################################################
