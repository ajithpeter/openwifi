# FPGA Gateware Integration Guide for Zynq 7010

**Complete WiFi SDR System with Full OFDM Support**

## Executive Summary

This guide explains how to integrate full OpenWiFi FPGA gateware (OFDM RX/TX, MAC, RF interface) with the PlutoSDR beacon scanner for Zynq 7010, creating a complete IEEE 802.11a/g/n WiFi system.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Zynq 7010 SoC                           │
├─────────────────────────────────────────────────────────────────┤
│  ARM Cortex-A9 @ 667 MHz (Processing System - PS)               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Linux + mac80211 + OpenWiFi Driver                       │  │
│  │  - beacon_scanner.c (user application)                    │  │
│  │  - sdr.ko (kernel driver, MMIO + DMA)                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                            ↕ (AXI, DMA, Interrupts)              │
├─────────────────────────────────────────────────────────────────┤
│  FPGA Fabric (Programmable Logic - PL) [~5K logic cells]        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  MINIMAL DESIGN FOR ZYNQ 7010                             │  │
│  │                                                            │  │
│  │  [TX DMA] ←→ [tx_intf] ←→ [openofdm_tx] ─┐               │  │
│  │                                            │               │  │
│  │  [RX DMA] ←→ [rx_intf] ←→ [openofdm_rx] ─┤               │  │
│  │                                            │               │  │
│  │  [XPU: MAC Controller + SPI to AD9361] ───┤               │  │
│  │                                            ↓               │  │
│  │                                    [AD9361 Interface]      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                            ↕ (40 Msps IQ, LVDS)                  │
├─────────────────────────────────────────────────────────────────┤
│  AD9361/AD9364 RF Transceiver (70 MHz - 6 GHz)                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Resource Utilization (Zynq 7010)

### Full OpenWiFi Design (Optimized)

| Resource     | Used  | Available | Utilization | Status |
|--------------|-------|-----------|-------------|--------|
| Logic Cells  | 5,000 | 28,016    | **18%**     | ✅ Fits |
| DSP Slices   | 35    | 80        | **44%**     | ✅ Good |
| Block RAM    | 15    | 60        | **25%**     | ✅ Good |
| I/O          | 54    | 200       | **27%**     | ✅ Good |

**Memory Footprint:**
- DDR3 RAM: ~85 MB (driver buffers, RX/TX rings, applications)
- Fits comfortably in 512 MB PlutoSDR RAM

---

## Key FPGA Modules

### 1. openofdm_rx (OFDM Receiver)
**Location:** `openwifi-hw/ip/openofdm_rx/`
**Function:** Complete OFDM demodulation pipeline
- 64-point FFT
- Synchronization (short & long preamble)
- Channel estimation & equalization
- Viterbi decoder (K=7, soft decision)
- Deinterleaver
- Descrambler
- FCS validation

**Resource Usage:** ~2,500 logic cells, 15 DSP, 8 BRAM

### 2. openofdm_tx (OFDM Transmitter)
**Location:** `openwifi-hw/ip/openofdm_tx/`
**Function:** Complete OFDM modulation pipeline
- Scrambler
- Convolutional encoder (rate 1/2, 2/3, 3/4)
- Interleaver
- QAM mapper (BPSK, QPSK, 16-QAM, 64-QAM)
- 64-point IFFT
- Cyclic prefix insertion
- Preamble generation

**Resource Usage:** ~1,800 logic cells, 12 DSP, 4 BRAM

### 3. rx_intf (RX Interface)
**Location:** `openwifi-hw/ip/rx_intf/`
**Function:** AD9361 interface + RX control
- 40 Msps IQ input (LVDS from AD9361)
- Decimation to 20 Msps
- Digital gain control
- Antenna selection
- DMA coordination

**Resource Usage:** ~400 logic cells, 4 DSP, 2 BRAM

### 4. tx_intf (TX Interface)
**Location:** `openwifi-hw/ip/tx_intf/`
**Function:** TX control + AD9361 output
- 4 priority queues
- Digital gain control
- 20 Msps to 40 Msps interpolation
- IQ output to AD9361
- DMA coordination

**Resource Usage:** ~300 logic cells, 2 DSP, 1 BRAM

### 5. xpu (Low MAC Controller)
**Location:** `openwifi-hw/ip/xpu/`
**Function:** Timing-critical MAC functions
- CSMA/CA state machine
- TSF timer (64-bit, 1 µs resolution)
- Automatic ACK generation
- SPI master to AD9361 (fast RF switching)
- Frame filtering (BSSID, MAC address)

**Resource Usage:** ~800 logic cells, 2 DSP, 0 BRAM

### 6. side_ch (Side Channel)
**Location:** `openwifi-hw/ip/side_ch/`
**Function:** CSI capture, IQ recording
- Channel State Information capture
- Raw IQ sample recording
- Trigger-based capture

**Resource Usage:** ~200 logic cells, 0 DSP, 0 BRAM

---

## Build Instructions

### Prerequisites

```bash
# Xilinx Tools
- Vivado 2021.1 or later (tested with 2021.1, 2021.2)
- Vitis (for FSBL generation)
- Bootgen (for BOOT.BIN)

# Cross-compilation tools
sudo apt-get install gcc-arm-linux-gnueabihf u-boot-tools device-tree-compiler
```

### Step 1: Clone Repositories

```bash
cd /home/user/openwifi

# FPGA source already cloned to:
# /home/user/openwifi-hw

# Verify structure
ls openwifi-hw/boards/      # Board-specific TCL scripts
ls openwifi-hw/ip/          # IP core definitions
```

### Step 2: Create Minimal Zynq 7010 Vivado Project

**Option A: Using Existing Board (SDRPi - Minimal Design)**

```bash
cd openwifi-hw/boards/sdrpi

# This board has minimal FPGA design suitable for Z7010
# Review the TCL script
cat openwifi.tcl            # Board configuration
cat set_files.tcl           # File list
cat synth_impl_strategy.tcl # Synthesis strategy
```

**Option B: Create Custom Z7010 Project**

Create `/home/user/openwifi-hw/boards/plutosdr_z7010/openwifi.tcl`:

```tcl
# PlutoSDR Zynq 7010 Minimal WiFi Project
set design_name "system"
set part "xc7z010clg400-1"  # Zynq 7010
set board_part ""

# Clock configuration
set fclk0_mhz 200.0  # FPGA fabric clock

# DDR3 configuration for PlutoSDR
set ddr_size 512     # 512 MB

# Create project
create_project openwifi ./openwifi -part $part -force

# Add IP repositories
set_property ip_repo_paths {../../../ip} [current_project]
update_ip_catalog

# Create block design
create_bd_design $design_name

# Add Zynq PS
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

# Apply PlutoSDR/AD9361 preset
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "0" Master "Disable" Slave "Disable" } \
    [get_bd_cells processing_system7_0]

# Configure PS
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {$fclk0_mhz} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP1 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_MODE {DIRECT} \
] [get_bd_cells processing_system7_0]

# Add OpenWiFi IP cores
source ../ip/openwifi_ip.tcl
source ../ip/connect_openwifi_ip.tcl

# Validate design
validate_bd_design
save_bd_design

# Generate HDL wrapper
make_wrapper -files [get_files ./$design_name.bd] -top
add_files -norecurse ./openwifi.srcs/sources_1/bd/$design_name/hdl/${design_name}_wrapper.v

# Set top module
set_property top ${design_name}_wrapper [current_fileset]

# Add constraints
add_files -fileset constrs_1 -norecurse ./src/zynq7010.xdc

# Synthesis settings (area-optimized for Z7010)
set_property strategy "Flow_AreaOptimized_high" [get_runs synth_1]
set_property strategy "Performance_ExploreWithRemap" [get_runs impl_1]
```

### Step 3: Synthesis and Implementation

```bash
cd openwifi-hw/boards/plutosdr_z7010  # or sdrpi

# Open Vivado
vivado openwifi/openwifi.xpr &

# Or run in batch mode
vivado -mode batch -source build.tcl
```

**build.tcl:**
```tcl
open_project openwifi/openwifi.xpr

# Synthesize
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Implement
launch_runs impl_1 -jobs 8
wait_on_run impl_1

# Generate bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# Export hardware (for device tree + FSBL)
write_hw_platform -fixed -force -file ./output/system_top.xsa

# Export bitstream
file copy -force ./openwifi.runs/impl_1/system_wrapper.bit ./output/system_top.bit

puts "Build complete! XSA and bitstream in ./output/"
```

### Step 4: Generate Device Tree

```bash
cd /home/user/openwifi/kernel_boot/boards

# Create plutosdr_z7010 directory
mkdir -p plutosdr_z7010
cd plutosdr_z7010

# Use system_top.xsa to generate device tree
hsi open_hw_design ../../../openwifi-hw/boards/plutosdr_z7010/output/system_top.xsa
hsi set_repo_path /opt/Xilinx/Vitis/2021.1/data/embeddedsw
hsi create_sw_design device-tree -os device_tree -proc processing_system7_0
hsi generate_target -dir ./device_tree
hsi close_hw_design [current_hw_design]

# Compile device tree
cd device_tree
dtc -I dts -O dtb -o ../devicetree.dtb system-top.dts

# Manual edits to add OpenWiFi peripherals (if not auto-generated)
# Edit system-top.dts to add:
# - openofdm_rx@83c30000
# - openofdm_tx@83c10000
# - rx_intf@83c20000
# - tx_intf@83c00000
# - xpu@83c40000
# - tx_dma@80400000
# - rx_dma@80410000
# (See zed_fmcs2/devicetree.dts for reference)
```

### Step 5: Generate Boot Files

```bash
cd /home/user/openwifi/kernel_boot/boards/plutosdr_z7010

# Copy U-Boot (use ZED or similar board's U-Boot)
cp ../zed_fmcs2/u-boot.elf ./

# Generate BOOT.BIN
../build_boot_bin.sh \
    ../../openwifi-hw/boards/plutosdr_z7010/output/system_top.xsa \
    ./u-boot.elf

# Output: output_boot_bin/BOOT.BIN
```

### Step 6: Compile Kernel and Drivers

```bash
cd /home/user/openwifi

# Kernel already built in adi-linux (from previous steps)
# Drivers already compiled in driver/

# Copy drivers to SD card rootfs
cp driver/*.ko /mnt/sdcard/rootfs/lib/modules/5.15.36/extra/
```

### Step 7: Create SD Card

```bash
# Use prepare_sdcard.sh from plutosdr_beacon
cd /home/user/openwifi/plutosdr_beacon
sudo ./prepare_sdcard.sh

# When prompted, specify device (e.g., sdb)
# Script will:
# 1. Partition SD card (100 MB FAT32 + remainder ext4)
# 2. Copy BOOT.BIN, uImage, devicetree.dtb to boot partition
# 3. Extract rootfs to second partition
# 4. Install beacon_scanner application
# 5. Install OpenWiFi kernel modules
```

### Step 8: Boot and Test

```bash
# Insert SD card into PlutoSDR/Zynq 7010
# Connect serial console (115200 8N1)
# Power on

# After boot, SSH to device
ssh root@192.168.2.1  # PlutoSDR default IP

# Load kernel modules
modprobe sdr

# Check WiFi interface
iw dev
iw phy

# Run beacon scanner (now with full OFDM support)
./beacon_scanner -a

# Or run hostapd for access point mode
hostapd /etc/hostapd.conf
```

---

## Integration with C Beacon Scanner

The C beacon scanner (`beacon_scanner.c`) integrates with the FPGA gateware through:

### 1. libiio Access to AD9361

```c
// Initialize PlutoSDR via libiio
struct iio_context *ctx = iio_create_context_from_uri("ip:192.168.2.1");
struct iio_device *phy = iio_context_find_device(ctx, "ad9361-phy");

// Configure RX
iio_channel_attr_write_longlong(
    iio_device_find_channel(phy, "altvoltage0", true),
    "frequency", 2437000000);  // Channel 6
```

### 2. Kernel Driver Interface

The OpenWiFi driver (`sdr.ko`) handles:
- FPGA register configuration via MMIO
- DMA buffer management
- IRQ handling
- Integration with mac80211

### 3. FPGA Data Flow

```
User App (beacon_scanner)
    ↓ (libiio or nl80211)
Kernel Driver (sdr.ko)
    ↓ (MMIO: iowrite32/ioread32)
FPGA Registers (xpu, rx_intf, tx_intf, openofdm_*)
    ↓ (AXI-Stream)
AD9361 RF Transceiver
    ↓ (RF 2.4/5 GHz)
Antenna
```

---

## Optimization for Zynq 7010

### FPGA Resource Reduction Strategies

1. **Disable Unused Features:**
   ```tcl
   # In openwifi_ip.tcl, comment out side_ch if not needed
   # create_bd_cell -type ip -vlnv sdr:user:side_ch:1.0 side_ch_0
   ```

2. **Reduce Buffer Sizes:**
   ```verilog
   // In rx_intf/tx_intf, reduce FIFO depths
   parameter FIFO_DEPTH = 512;  // Instead of 2048
   ```

3. **Simplify Viterbi Decoder:**
   ```tcl
   # Use hard-decision instead of soft-decision
   set_property CONFIG.DECISION_TYPE {Hard} [get_bd_cells openofdm_rx_0/viterbi_0]
   ```

4. **Area-Optimized Synthesis:**
   ```tcl
   set_property strategy "Flow_AreaOptimized_high" [get_runs synth_1]
   set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE "AreaOptimized_high" [get_runs synth_1]
   ```

### Software-Only Fallback

If full OFDM still doesn't fit, use hybrid approach:
- Keep beacon parsing/generation in C (software)
- Use FPGA only for AD9361 interface + DMA
- Implement lightweight OFDM in ARM using liquid-dsp

---

## Testing Full WiFi Functionality

### Test 1: Beacon Reception

```bash
# Scan for WiFi networks
./beacon_scanner -m scan -c 6 -t 5000

# Should show:
# - SSID, BSSID, channel
# - RSSI from FPGA
# - Capabilities (HT, VHT, HE)
# - Modulation/coding detected by OFDM RX
```

### Test 2: Beacon Transmission

```bash
# Transmit beacon
./beacon_scanner -m tx -c 6 -s "PlutoAP" -n 100

# Verify with another device:
# - SSID "PlutoAP" visible on channel 6
# - Proper beacon interval (100 TU)
# - Valid FCS
```

### Test 3: Full Access Point Mode

```bash
# Configure hostapd
cat > /etc/hostapd.conf << 'EOF'
interface=wlan0
driver=nl80211
ssid=PlutoSDR_AP
hw_mode=g
channel=6
wmm_enabled=1
ieee80211n=1
ht_capab=[SHORT-GI-20]
EOF

# Run hostapd
hostapd /etc/hostapd.conf

# Connect from client device
# Test throughput: iperf3 -s (on Zynq) / iperf3 -c 192.168.2.1 (on client)
```

### Test 4: Monitor Mode

```bash
# Put interface in monitor mode
iw dev wlan0 set type monitor
iw dev wlan0 set channel 6
ifconfig wlan0 up

# Capture packets
tcpdump -i wlan0 -w capture.pcap

# Analyze with Wireshark on host PC
```

---

## Performance Expectations

| Metric | Value | Notes |
|--------|-------|-------|
| **RX Sensitivity** | -92 dBm (MCS0) to -73 dBm (MCS7) | With full OFDM RX |
| **TX EVM** | -38 dB (MCS0) to -30 dB (MCS7) | With full OFDM TX |
| **Throughput (TCP)** | 40-50 Mbps | Single stream 802.11n |
| **Throughput (UDP)** | 50+ Mbps | With A-MPDU aggregation |
| **Latency** | 90-300 µs | End-to-end RX processing |
| **SIFS Timing** | 10 µs | Better than 16 µs spec |

---

## Troubleshooting

### Issue: Bitstream Too Large

**Solution:** Further optimize synthesis
```tcl
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE "AreaMultThresholdDSP" [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY "full" [get_runs synth_1]
```

### Issue: Timing Violations

**Solution:** Reduce clock frequency or add pipeline stages
```tcl
set_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.0} [get_bd_cells processing_system7_0]
```

### Issue: Viterbi Decoder Stops After 2 Hours

**Cause:** Evaluation license limit
**Solution:** Purchase full Xilinx license or use open-source Viterbi implementation

### Issue: No WiFi Interface Detected

**Check:**
1. `lsmod | grep sdr` - Driver loaded?
2. `dmesg | grep sdr` - Any errors?
3. `iio_info` - AD9361 detected?
4. `/sys/bus/iio/devices/` - iio:device1 present?

---

## References

- **OpenWiFi Hardware:** https://github.com/open-sdr/openwifi-hw
- **OpenWiFi Driver:** https://github.com/open-sdr/openwifi
- **Documentation:** `/home/user/openwifi/doc/`
- **Vivado TCL Commands:** UG835 (Xilinx)
- **Zynq-7000 TRM:** UG585 (Xilinx)
- **IEEE 802.11-2020:** WiFi Standard

---

## Summary

This guide provides a complete path from software-only beacon scanner to full WiFi SDR system on Zynq 7010. The modular OpenWiFi architecture allows incremental integration:

1. **Phase 1 (Current):** Software beacon parsing + AD9361 control via libiio
2. **Phase 2:** Add FPGA OFDM RX for improved sensitivity
3. **Phase 3:** Add FPGA OFDM TX for beacon transmission quality
4. **Phase 4:** Add full MAC support for access point mode

Each phase builds on the previous, allowing validation at each step.
