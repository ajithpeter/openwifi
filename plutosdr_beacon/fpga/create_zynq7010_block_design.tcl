# Zynq 7010 Block Design for PlutoSDR/OpenWiFi Minimal Configuration
# Compatible with Vivado 2019.1 and later
# Optimized for Zynq 7010 (28K logic cells, 80 DSP, 60 BRAM)
#
# This creates a minimal WiFi SDR design with:
# - OFDM RX/TX hardware acceleration
# - Low MAC controller (XPU)
# - AXI DMA for baseband I/Q streaming
# - AD9361 RF frontend interface
#
# Target resource usage: ~18% logic, 44% DSP, 25% BRAM

################################################################
# Check Vivado version (minimum 2019.1)
################################################################
set scripts_vivado_version 2019.1
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   catch {common::send_msg_id "BD_TCL-109" "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}
   return 1
}

################################################################
# START - Configuration variables
################################################################
set design_name system
set ip_repo_path "../openwifi-hw/ip"

# Set project-specific variables
set part_name "xc7z010clg400-1"  # PlutoSDR uses Zynq 7010
set board_name ""                 # No specific board file

################################################################
# PROCEDURE: Create block design
################################################################
proc create_root_design { parentCell } {

  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_msg_id "BD_TCL-100" "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_msg_id "BD_TCL-101" "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  ################################################################
  # Create interface ports
  ################################################################
  set DDR [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR ]
  set FIXED_IO [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO ]
  set IIC_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 IIC_0 ]

  ################################################################
  # Create ports - AD9361 Interface
  ################################################################
  set adc_data_i0 [ create_bd_port -dir I -from 11 -to 0 adc_data_i0 ]
  set adc_data_i1 [ create_bd_port -dir I -from 11 -to 0 adc_data_i1 ]
  set adc_data_q0 [ create_bd_port -dir I -from 11 -to 0 adc_data_q0 ]
  set adc_data_q1 [ create_bd_port -dir I -from 11 -to 0 adc_data_q1 ]
  set adc_enable_i0 [ create_bd_port -dir O adc_enable_i0 ]
  set adc_enable_i1 [ create_bd_port -dir O adc_enable_i1 ]
  set adc_enable_q0 [ create_bd_port -dir O adc_enable_q0 ]
  set adc_enable_q1 [ create_bd_port -dir O adc_enable_q1 ]
  set adc_valid_i0 [ create_bd_port -dir I adc_valid_i0 ]
  set adc_valid_i1 [ create_bd_port -dir I adc_valid_i1 ]
  set adc_valid_q0 [ create_bd_port -dir I adc_valid_q0 ]
  set adc_valid_q1 [ create_bd_port -dir I adc_valid_q1 ]

  set dac_data_i0 [ create_bd_port -dir O -from 11 -to 0 dac_data_i0 ]
  set dac_data_i1 [ create_bd_port -dir O -from 11 -to 0 dac_data_i1 ]
  set dac_data_q0 [ create_bd_port -dir O -from 11 -to 0 dac_data_q0 ]
  set dac_data_q1 [ create_bd_port -dir O -from 11 -to 0 dac_data_q1 ]
  set dac_valid_i0 [ create_bd_port -dir O dac_valid_i0 ]
  set dac_valid_i1 [ create_bd_port -dir O dac_valid_i1 ]
  set dac_valid_q0 [ create_bd_port -dir O dac_valid_q0 ]
  set dac_valid_q1 [ create_bd_port -dir O dac_valid_q1 ]

  # AD9361 control signals
  set enable [ create_bd_port -dir O enable ]
  set txnrx [ create_bd_port -dir O txnrx ]
  set up_enable [ create_bd_port -dir I up_enable ]
  set up_txnrx [ create_bd_port -dir I up_txnrx ]

  # AD9361 clocks
  set delay_clk [ create_bd_port -dir O delay_clk ]

  ################################################################
  # Create instance: processing_system7_0
  ################################################################
  puts "INFO: Creating Zynq PS instance..."
  set processing_system7_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0 ]

  # Configure PS for Zynq 7010
  set_property -dict [ list \
   CONFIG.PCW_IMPORT_BOARD_PRESET {None} \
   CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
   CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
   CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
   CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
   CONFIG.PCW_SD0_PERIPHERAL_ENABLE {0} \
   CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
   CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
   CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {0} \
   CONFIG.PCW_SPI0_PERIPHERAL_ENABLE {1} \
   CONFIG.PCW_SPI0_SPI0_IO {MIO 40 .. 45} \
   CONFIG.PCW_SPI1_PERIPHERAL_ENABLE {1} \
   CONFIG.PCW_SPI1_SPI1_IO {MIO 10 .. 15} \
   CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
   CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1} \
   CONFIG.PCW_TTC0_PERIPHERAL_ENABLE {0} \
   CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
   CONFIG.PCW_IRQ_F2P_INTR {1} \
   CONFIG.PCW_EN_CLK0_PORT {1} \
   CONFIG.PCW_EN_CLK1_PORT {1} \
   CONFIG.PCW_EN_RST0_PORT {1} \
   CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.0} \
   CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {200.0} \
   CONFIG.PCW_USE_S_AXI_HP0 {1} \
   CONFIG.PCW_USE_S_AXI_HP1 {1} \
   CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
   CONFIG.PCW_S_AXI_HP1_DATA_WIDTH {64} \
   CONFIG.PCW_DDR_RAM_BASEADDR {0x00000000} \
   CONFIG.PCW_DDR_RAM_HIGHADDR {0x1FFFFFFF} \
   CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
   CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
  ] $processing_system7_0

  ################################################################
  # Create instance: axi_cpu_interconnect
  ################################################################
  puts "INFO: Creating AXI interconnect for CPU access..."
  set axi_cpu_interconnect [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_cpu_interconnect ]
  set_property -dict [ list \
   CONFIG.NUM_MI {10} \
   CONFIG.NUM_SI {1} \
  ] $axi_cpu_interconnect

  ################################################################
  # Create instance: axi_hp_interconnect (for DMA)
  ################################################################
  puts "INFO: Creating AXI HP interconnect for DMA..."
  set axi_hp_interconnect [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_hp_interconnect ]
  set_property -dict [ list \
   CONFIG.NUM_MI {1} \
   CONFIG.NUM_SI {4} \
   CONFIG.STRATEGY {2} \
  ] $axi_hp_interconnect

  ################################################################
  # Create instance: rst_ps7_0_100M
  ################################################################
  puts "INFO: Creating processor system reset..."
  set rst_ps7_0_100M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_100M ]

  ################################################################
  # Create instance: RX DMA
  ################################################################
  puts "INFO: Creating RX DMA..."
  set rx_dma [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 rx_dma ]
  set_property -dict [ list \
   CONFIG.c_include_sg {1} \
   CONFIG.c_sg_include_stscntrl_strm {0} \
   CONFIG.c_sg_length_width {14} \
   CONFIG.c_m_axi_mm2s_data_width {64} \
   CONFIG.c_m_axis_mm2s_tdata_width {64} \
   CONFIG.c_mm2s_burst_size {16} \
   CONFIG.c_m_axi_s2mm_data_width {64} \
   CONFIG.c_s_axis_s2mm_tdata_width {64} \
   CONFIG.c_s2mm_burst_size {16} \
  ] $rx_dma

  ################################################################
  # Create instance: TX DMA
  ################################################################
  puts "INFO: Creating TX DMA..."
  set tx_dma [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 tx_dma ]
  set_property -dict [ list \
   CONFIG.c_include_sg {1} \
   CONFIG.c_sg_include_stscntrl_strm {0} \
   CONFIG.c_sg_length_width {14} \
   CONFIG.c_m_axi_mm2s_data_width {64} \
   CONFIG.c_m_axis_mm2s_tdata_width {64} \
   CONFIG.c_mm2s_burst_size {16} \
   CONFIG.c_m_axi_s2mm_data_width {64} \
   CONFIG.c_s_axis_s2mm_tdata_width {64} \
   CONFIG.c_s2mm_burst_size {16} \
  ] $tx_dma

  ################################################################
  # Create instance: openofdm_rx
  ################################################################
  puts "INFO: Creating OpenOFDM RX..."
  set openofdm_rx_0 [ create_bd_cell -type ip -vlnv sdr:sdr:openofdm_rx:1.0 openofdm_rx_0 ]

  ################################################################
  # Create instance: openofdm_tx
  ################################################################
  puts "INFO: Creating OpenOFDM TX..."
  set openofdm_tx_0 [ create_bd_cell -type ip -vlnv sdr:sdr:openofdm_tx:1.0 openofdm_tx_0 ]

  ################################################################
  # Create instance: rx_intf
  ################################################################
  puts "INFO: Creating RX Interface..."
  set rx_intf_0 [ create_bd_cell -type ip -vlnv sdr:sdr:rx_intf:1.0 rx_intf_0 ]

  ################################################################
  # Create instance: tx_intf
  ################################################################
  puts "INFO: Creating TX Interface..."
  set tx_intf_0 [ create_bd_cell -type ip -vlnv sdr:sdr:tx_intf:1.0 tx_intf_0 ]

  ################################################################
  # Create instance: xpu (Low MAC)
  ################################################################
  puts "INFO: Creating XPU (Low MAC)..."
  set xpu_0 [ create_bd_cell -type ip -vlnv sdr:sdr:xpu:1.0 xpu_0 ]

  ################################################################
  # Create instance: side_ch (CSI capture)
  ################################################################
  puts "INFO: Creating side_ch (CSI)..."
  set side_ch_0 [ create_bd_cell -type ip -vlnv sdr:sdr:side_ch:1.0 side_ch_0 ]

  ################################################################
  # Create instance: xlconcat for interrupts
  ################################################################
  puts "INFO: Creating interrupt concatenation..."
  set xlconcat_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0 ]
  set_property -dict [ list \
   CONFIG.NUM_PORTS {8} \
  ] $xlconcat_0

  ################################################################
  # Create interface connections
  ################################################################
  puts "INFO: Connecting AXI interfaces..."

  # Connect PS M_AXI_GP0 to CPU interconnect
  connect_bd_intf_net -intf_net processing_system7_0_M_AXI_GP0 \
    [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
    [get_bd_intf_pins axi_cpu_interconnect/S00_AXI]

  # Connect CPU interconnect to peripherals
  connect_bd_intf_net -intf_net axi_cpu_interconnect_M00_AXI \
    [get_bd_intf_pins axi_cpu_interconnect/M00_AXI] \
    [get_bd_intf_pins rx_intf_0/s00_axi]
  connect_bd_intf_net -intf_net axi_cpu_interconnect_M01_AXI \
    [get_bd_intf_pins axi_cpu_interconnect/M01_AXI] \
    [get_bd_intf_pins tx_intf_0/s00_axi]
  connect_bd_intf_net -intf_net axi_cpu_interconnect_M02_AXI \
    [get_bd_intf_pins axi_cpu_interconnect/M02_AXI] \
    [get_bd_intf_pins openofdm_rx_0/s00_axi]
  connect_bd_intf_net -intf_net axi_cpu_interconnect_M03_AXI \
    [get_bd_intf_pins axi_cpu_interconnect/M03_AXI] \
    [get_bd_intf_pins openofdm_tx_0/s00_axi]
  connect_bd_intf_net -intf_net axi_cpu_interconnect_M04_AXI \
    [get_bd_intf_pins axi_cpu_interconnect/M04_AXI] \
    [get_bd_intf_pins xpu_0/s00_axi]
  connect_bd_intf_net -intf_net axi_cpu_interconnect_M05_AXI \
    [get_bd_intf_pins axi_cpu_interconnect/M05_AXI] \
    [get_bd_intf_pins side_ch_0/s00_axi]
  connect_bd_intf_net -intf_net axi_cpu_interconnect_M06_AXI \
    [get_bd_intf_pins axi_cpu_interconnect/M06_AXI] \
    [get_bd_intf_pins rx_dma/S_AXI_LITE]
  connect_bd_intf_net -intf_net axi_cpu_interconnect_M07_AXI \
    [get_bd_intf_pins axi_cpu_interconnect/M07_AXI] \
    [get_bd_intf_pins tx_dma/S_AXI_LITE]

  # Connect DMA to HP interconnect
  connect_bd_intf_net -intf_net rx_dma_M_AXI_SG \
    [get_bd_intf_pins rx_dma/M_AXI_SG] \
    [get_bd_intf_pins axi_hp_interconnect/S00_AXI]
  connect_bd_intf_net -intf_net rx_dma_M_AXI_S2MM \
    [get_bd_intf_pins rx_dma/M_AXI_S2MM] \
    [get_bd_intf_pins axi_hp_interconnect/S01_AXI]
  connect_bd_intf_net -intf_net tx_dma_M_AXI_SG \
    [get_bd_intf_pins tx_dma/M_AXI_SG] \
    [get_bd_intf_pins axi_hp_interconnect/S02_AXI]
  connect_bd_intf_net -intf_net tx_dma_M_AXI_MM2S \
    [get_bd_intf_pins tx_dma/M_AXI_MM2S] \
    [get_bd_intf_pins axi_hp_interconnect/S03_AXI]

  # Connect HP interconnect to PS HP0
  connect_bd_intf_net -intf_net axi_hp_interconnect_M00_AXI \
    [get_bd_intf_pins axi_hp_interconnect/M00_AXI] \
    [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

  # Connect datapath: TX DMA -> tx_intf -> openofdm_tx
  connect_bd_intf_net -intf_net tx_dma_M_AXIS_MM2S \
    [get_bd_intf_pins tx_dma/M_AXIS_MM2S] \
    [get_bd_intf_pins tx_intf_0/s00_axis]
  connect_bd_intf_net -intf_net tx_intf_M00_AXIS \
    [get_bd_intf_pins tx_intf_0/m00_axis] \
    [get_bd_intf_pins openofdm_tx_0/s_axis_in]

  # Connect datapath: openofdm_rx -> rx_intf -> RX DMA
  connect_bd_intf_net -intf_net openofdm_rx_M_AXIS \
    [get_bd_intf_pins openofdm_rx_0/m_axis_out] \
    [get_bd_intf_pins rx_intf_0/s00_axis]
  connect_bd_intf_net -intf_net rx_intf_M00_AXIS \
    [get_bd_intf_pins rx_intf_0/m00_axis] \
    [get_bd_intf_pins rx_dma/S_AXIS_S2MM]

  # Connect PS DDR and Fixed IO
  connect_bd_intf_net -intf_net processing_system7_0_DDR \
    [get_bd_intf_ports DDR] \
    [get_bd_intf_pins processing_system7_0/DDR]
  connect_bd_intf_net -intf_net processing_system7_0_FIXED_IO \
    [get_bd_intf_ports FIXED_IO] \
    [get_bd_intf_pins processing_system7_0/FIXED_IO]

  ################################################################
  # Create port connections - Clocks and Resets
  ################################################################
  puts "INFO: Connecting clocks and resets..."

  # PS clocks
  connect_bd_net -net processing_system7_0_FCLK_CLK0 \
    [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
    [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK] \
    [get_bd_pins axi_cpu_interconnect/ACLK] \
    [get_bd_pins axi_cpu_interconnect/S00_ACLK] \
    [get_bd_pins axi_cpu_interconnect/M00_ACLK] \
    [get_bd_pins axi_cpu_interconnect/M01_ACLK] \
    [get_bd_pins axi_cpu_interconnect/M02_ACLK] \
    [get_bd_pins axi_cpu_interconnect/M03_ACLK] \
    [get_bd_pins axi_cpu_interconnect/M04_ACLK] \
    [get_bd_pins axi_cpu_interconnect/M05_ACLK] \
    [get_bd_pins axi_cpu_interconnect/M06_ACLK] \
    [get_bd_pins axi_cpu_interconnect/M07_ACLK] \
    [get_bd_pins axi_hp_interconnect/ACLK] \
    [get_bd_pins axi_hp_interconnect/S00_ACLK] \
    [get_bd_pins axi_hp_interconnect/S01_ACLK] \
    [get_bd_pins axi_hp_interconnect/S02_ACLK] \
    [get_bd_pins axi_hp_interconnect/S03_ACLK] \
    [get_bd_pins axi_hp_interconnect/M00_ACLK] \
    [get_bd_pins rx_dma/s_axi_lite_aclk] \
    [get_bd_pins rx_dma/m_axi_sg_aclk] \
    [get_bd_pins rx_dma/m_axi_s2mm_aclk] \
    [get_bd_pins tx_dma/s_axi_lite_aclk] \
    [get_bd_pins tx_dma/m_axi_sg_aclk] \
    [get_bd_pins tx_dma/m_axi_mm2s_aclk] \
    [get_bd_pins openofdm_rx_0/clk] \
    [get_bd_pins openofdm_tx_0/clk] \
    [get_bd_pins rx_intf_0/s00_axi_aclk] \
    [get_bd_pins rx_intf_0/m00_axis_aclk] \
    [get_bd_pins tx_intf_0/s00_axi_aclk] \
    [get_bd_pins tx_intf_0/s00_axis_aclk] \
    [get_bd_pins xpu_0/s00_axi_aclk] \
    [get_bd_pins side_ch_0/s00_axi_aclk] \
    [get_bd_pins rst_ps7_0_100M/slowest_sync_clk]

  # Resets
  connect_bd_net -net processing_system7_0_FCLK_RESET0_N \
    [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins rst_ps7_0_100M/ext_reset_in]

  connect_bd_net -net rst_ps7_0_100M_peripheral_aresetn \
    [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] \
    [get_bd_pins axi_cpu_interconnect/ARESETN] \
    [get_bd_pins axi_cpu_interconnect/S00_ARESETN] \
    [get_bd_pins axi_cpu_interconnect/M00_ARESETN] \
    [get_bd_pins axi_cpu_interconnect/M01_ARESETN] \
    [get_bd_pins axi_cpu_interconnect/M02_ARESETN] \
    [get_bd_pins axi_cpu_interconnect/M03_ARESETN] \
    [get_bd_pins axi_cpu_interconnect/M04_ARESETN] \
    [get_bd_pins axi_cpu_interconnect/M05_ARESETN] \
    [get_bd_pins axi_cpu_interconnect/M06_ARESETN] \
    [get_bd_pins axi_cpu_interconnect/M07_ARESETN] \
    [get_bd_pins axi_hp_interconnect/ARESETN] \
    [get_bd_pins axi_hp_interconnect/S00_ARESETN] \
    [get_bd_pins axi_hp_interconnect/S01_ARESETN] \
    [get_bd_pins axi_hp_interconnect/S02_ARESETN] \
    [get_bd_pins axi_hp_interconnect/S03_ARESETN] \
    [get_bd_pins axi_hp_interconnect/M00_ARESETN] \
    [get_bd_pins rx_dma/axi_resetn] \
    [get_bd_pins tx_dma/axi_resetn] \
    [get_bd_pins openofdm_rx_0/rstn] \
    [get_bd_pins openofdm_tx_0/rstn] \
    [get_bd_pins rx_intf_0/s00_axi_aresetn] \
    [get_bd_pins tx_intf_0/s00_axi_aresetn] \
    [get_bd_pins xpu_0/s00_axi_aresetn] \
    [get_bd_pins side_ch_0/s00_axi_aresetn]

  ################################################################
  # Create port connections - Interrupts
  ################################################################
  puts "INFO: Connecting interrupts..."

  connect_bd_net -net rx_dma_s2mm_introut \
    [get_bd_pins rx_dma/s2mm_introut] \
    [get_bd_pins xlconcat_0/In0]
  connect_bd_net -net tx_dma_mm2s_introut \
    [get_bd_pins tx_dma/mm2s_introut] \
    [get_bd_pins xlconcat_0/In1]
  connect_bd_net -net rx_intf_0_rx_pkt_intr \
    [get_bd_pins rx_intf_0/rx_pkt_intr] \
    [get_bd_pins xlconcat_0/In2]
  connect_bd_net -net tx_intf_0_tx_itrpt \
    [get_bd_pins tx_intf_0/tx_itrpt] \
    [get_bd_pins xlconcat_0/In3]
  connect_bd_net -net xlconcat_0_dout \
    [get_bd_pins xlconcat_0/dout] \
    [get_bd_pins processing_system7_0/IRQ_F2P]

  ################################################################
  # Address assignment
  ################################################################
  puts "INFO: Creating address segments..."

  create_bd_addr_seg -range 0x00010000 -offset 0x83C20000 \
    [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs rx_intf_0/s00_axi/reg0] SEG_rx_intf_0_reg0
  create_bd_addr_seg -range 0x00010000 -offset 0x83C00000 \
    [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs tx_intf_0/s00_axi/reg0] SEG_tx_intf_0_reg0
  create_bd_addr_seg -range 0x00010000 -offset 0x83C30000 \
    [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs openofdm_rx_0/s00_axi/reg0] SEG_openofdm_rx_0_reg0
  create_bd_addr_seg -range 0x00010000 -offset 0x83C10000 \
    [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs openofdm_tx_0/s00_axi/reg0] SEG_openofdm_tx_0_reg0
  create_bd_addr_seg -range 0x00010000 -offset 0x83C40000 \
    [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs xpu_0/s00_axi/reg0] SEG_xpu_0_reg0
  create_bd_addr_seg -range 0x00010000 -offset 0x83C50000 \
    [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs side_ch_0/s00_axi/reg0] SEG_side_ch_0_reg0
  create_bd_addr_seg -range 0x00010000 -offset 0x80410000 \
    [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs rx_dma/S_AXI_LITE/Reg] SEG_rx_dma_Reg
  create_bd_addr_seg -range 0x00010000 -offset 0x80400000 \
    [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs tx_dma/S_AXI_LITE/Reg] SEG_tx_dma_Reg

  # DMA to DDR
  create_bd_addr_seg -range 0x20000000 -offset 0x00000000 \
    [get_bd_addr_spaces rx_dma/Data_SG] \
    [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] SEG_processing_system7_0_HP0_DDR_LOWOCM_SG
  create_bd_addr_seg -range 0x20000000 -offset 0x00000000 \
    [get_bd_addr_spaces rx_dma/Data_S2MM] \
    [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] SEG_processing_system7_0_HP0_DDR_LOWOCM_S2MM
  create_bd_addr_seg -range 0x20000000 -offset 0x00000000 \
    [get_bd_addr_spaces tx_dma/Data_SG] \
    [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] SEG_processing_system7_0_HP0_DDR_LOWOCM_TX_SG
  create_bd_addr_seg -range 0x20000000 -offset 0x00000000 \
    [get_bd_addr_spaces tx_dma/Data_MM2S] \
    [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] SEG_processing_system7_0_HP0_DDR_LOWOCM_MM2S

  # Restore current instance
  current_bd_instance $oldCurInst

  puts "INFO: Block design creation completed successfully!"
  save_bd_design
}
# End of create_root_design()

################################################################
# MAIN FLOW
################################################################

# Create project
puts "INFO: Creating Vivado project for Zynq 7010..."
create_project openwifi_z7010 ./openwifi_z7010 -part $part_name -force

# Set IP repository paths
set_property ip_repo_paths $ip_repo_path [current_project]
update_ip_catalog

# Create block design
create_bd_design $design_name
create_root_design ""

# Make wrapper
puts "INFO: Creating HDL wrapper..."
make_wrapper -files [get_files ${design_name}.bd] -top
add_files -norecurse [glob ./openwifi_z7010/openwifi_z7010.srcs/sources_1/bd/${design_name}/hdl/${design_name}_wrapper.v]
set_property top ${design_name}_wrapper [current_fileset]

# Validate design
puts "INFO: Validating block design..."
validate_bd_design

puts ""
puts "========================================="
puts "Block Design Creation Complete!"
puts "========================================="
puts "Project: openwifi_z7010"
puts "Design: $design_name"
puts "Part: $part_name"
puts ""
puts "Next steps:"
puts "1. Review block design in Vivado GUI"
puts "2. Add XDC constraints file"
puts "3. Run synthesis: launch_runs synth_1"
puts "4. Run implementation: launch_runs impl_1 -to_step write_bitstream"
puts ""
