# Zynq 7010 Deployment Guide

**Minimal WiFi Beacon Scanner for Zynq 7010**

## Overview

The Zynq 7010 is the smallest device in the Zynq 7000 family:

- **Logic Cells:** 28K
- **DSP Slices:** 80
- **Block RAM:** 2.1 Mb
- **ARM CPU:** Dual-core Cortex-A9 @ 667 MHz

This is significantly smaller than boards typically used for OpenWiFi (Z7020 with 85K logic cells). This guide shows how to deploy the minimal beacon scanner on Zynq 7010.

---

## Strategy for Zynq 7010

### Software-Only Approach

**Best for Zynq 7010:** Run everything in ARM software, use FPGA only for minimal AD9361 interface.

```
┌─────────────────────────────────────────────┐
│         ARM Cortex-A9 (667 MHz)             │
│  ┌───────────────────────────────────────┐  │
│  │  beacon_scanner application           │  │
│  │  - Beacon parsing (software)          │  │
│  │  - OFDM demod (software, optional)    │  │
│  └───────────────────────────────────────┘  │
│                   ↕                          │
│  ┌───────────────────────────────────────┐  │
│  │  libiio + Linux drivers               │  │
│  └───────────────────────────────────────┘  │
└─────────────────┬───────────────────────────┘
                  ↕
┌─────────────────▼───────────────────────────┐
│  FPGA (Minimal - <5K logic cells)           │
│  ┌───────────────────────────────────────┐  │
│  │  AXI DMA (RX/TX)                      │  │
│  │  AD9361 Interface                     │  │
│  │  (No OFDM - saves 20K+ logic cells)   │  │
│  └───────────────────────────────────────┘  │
└─────────────────┬───────────────────────────┘
                  ↕
          AD9361/AD9364 RF Frontend
```

### What Runs Where

| Component | Location | Resources |
|-----------|----------|-----------|
| **Beacon parsing** | ARM Software | ~10 KB RAM |
| **Frame generation** | ARM Software | ~5 KB RAM |
| **Channel scanning** | ARM Software | ~1 KB RAM |
| **AD9361 control** | ARM Software (libiio) | ~50 KB RAM |
| **DMA** | FPGA | ~2K logic cells |
| **AXI Interconnect** | FPGA | ~1K logic cells |
| **AD9361 Interface** | FPGA | ~2K logic cells |
| **TOTAL FPGA** | | **~5K logic cells** ✅ |

---

## Minimal FPGA Design for Zynq 7010

### Block Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                       Zynq 7010 FPGA                          │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │              Processing System (PS)                    │  │
│  │                                                         │  │
│  │  ┌──────────────┐  ┌──────────────┐                   │  │
│  │  │ ARM CPU 0    │  │ ARM CPU 1    │                   │  │
│  │  │ (667 MHz)    │  │ (667 MHz)    │                   │  │
│  │  └──────────────┘  └──────────────┘                   │  │
│  │                                                         │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Memory (DDR3 - 512MB typical)                   │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  │                                                         │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  AXI Interfaces (HP0, GP0)                       │  │  │
│  │  └──────────────┬───────────────┬───────────────────┘  │  │
│  └────────────────┼───────────────┼──────────────────────┘  │
│                   │               │                          │
│  ┌────────────────▼───────────────▼──────────────────────┐  │
│  │         Programmable Logic (PL)                       │  │
│  │                                                         │  │
│  │  ┌──────────────┐     ┌──────────────┐                │  │
│  │  │ AXI DMA      │◄───►│ AXI          │                │  │
│  │  │ (RX)         │     │ Interconnect │                │  │
│  │  └──────┬───────┘     └──────┬───────┘                │  │
│  │         │                    │                         │  │
│  │  ┌──────▼───────┐     ┌──────▼───────┐                │  │
│  │  │ AXI DMA      │     │ AD9361       │                │  │
│  │  │ (TX)         │     │ Interface    │                │  │
│  │  └──────────────┘     └──────┬───────┘                │  │
│  │                              │                         │  │
│  └──────────────────────────────┼─────────────────────────┘  │
│                                 │                             │
└─────────────────────────────────┼─────────────────────────────┘
                                  │ LVDS
                                  ▼
                           AD9361/AD9364
```

### Vivado Project Settings for Zynq 7010

**Part:** `xc7z010clg400-1`

**Key Settings:**
```tcl
# Minimal resource usage
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

# Enable resource sharing
set_param general.maxThreads 8

# Optimize for area
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE AreaOptimized_high [get_runs synth_1]
```

### IP Cores Needed (Minimal)

1. **Zynq Processing System** (Auto-included)
   - Enable HP0 (High Performance AXI port)
   - Enable GP0 (General Purpose AXI port)
   - DDR configuration: 512MB

2. **AXI DMA** (2 instances for RX/TX)
   - Scatter-Gather: Disabled (saves resources)
   - Width: 64-bit
   - Depth: 512 bytes

3. **AXI Interconnect**
   - Master ports: 3
   - Slave ports: 1

4. **AD9361 Interface IP** (Custom or from ADI)
   - Use Analog Devices' IP from HDL repository
   - Minimal configuration (no DSP)

### Resource Utilization Estimate

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| **Logic Cells** | 5,000 | 28,016 | ~18% ✅ |
| **DSP Slices** | 4 | 80 | ~5% ✅ |
| **Block RAM** | 12 | 60 | ~20% ✅ |
| **I/O** | 40 | 100 | ~40% ✅ |

**Result:** Fits comfortably on Zynq 7010! ✅

---

## Software Configuration

### Cross-Compilation for Zynq 7010

```bash
# Install ARM toolchain
sudo apt-get install gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf

# Build for Zynq ARM
cd plutosdr_beacon
make cross CROSS_COMPILE=arm-linux-gnueabihf-

# Result: beacon_scanner (ARM binary)
```

### Linux Configuration

**Minimal Linux for Zynq 7010:**

```bash
# Kernel configuration
# Use PetaLinux or build minimal kernel

# Required kernel modules:
CONFIG_IIO=y
CONFIG_AD9361=m
CONFIG_AXI_DMA=y
CONFIG_WIRELESS=y

# Total kernel size: ~5 MB
# Total rootfs size: ~50 MB (with busybox)
```

### Memory Usage

**RAM Requirements:**

| Component | RAM | Notes |
|-----------|-----|-------|
| Linux kernel | ~30 MB | Minimal config |
| Rootfs | ~20 MB | Busybox |
| beacon_scanner | ~5 MB | Application |
| libiio | ~10 MB | Library + drivers |
| Buffers | ~20 MB | DMA buffers |
| **Total** | **~85 MB** | Fits in 512MB easily ✅ |

---

## Deployment Methods

### Method 1: SD Card Boot (Recommended)

**Create bootable SD card:**

1. **Partition SD card:**
```bash
# Partition 1: FAT32, 100MB (BOOT)
# Partition 2: ext4, remaining (ROOT)

sudo fdisk /dev/sdX
# Create partitions as above

sudo mkfs.vfat -F 32 /dev/sdX1
sudo mkfs.ext4 /dev/sdX2
```

2. **Copy boot files:**
```bash
# Mount boot partition
sudo mount /dev/sdX1 /mnt/boot

# Copy files
sudo cp BOOT.BIN /mnt/boot/
sudo cp uImage /mnt/boot/  # or Image for 64-bit
sudo cp devicetree.dtb /mnt/boot/

sudo umount /mnt/boot
```

3. **Copy root filesystem:**
```bash
# Mount root partition
sudo mount /dev/sdX2 /mnt/root

# Extract rootfs
sudo tar -xzf rootfs.tar.gz -C /mnt/root/

# Copy beacon_scanner
sudo cp beacon_scanner /mnt/root/root/

sudo umount /mnt/root
```

### Method 2: QSPI Boot (For Production)

```bash
# Flash QSPI from U-Boot
sf probe
sf erase 0 0x1000000
sf write 0x1000000 0 ${filesize}  # BOOT.BIN

# Kernel and devicetree also in QSPI
```

### Method 3: JTAG Boot (For Development)

```bash
# Use Xilinx SDK or Vivado
# Download bitstream + application via JTAG
# Fast for development, not persistent
```

---

## Running on Zynq 7010

### First Boot

```bash
# Connect serial console (115200 8N1)
# Board should boot to Linux prompt

# Check AD9361
cat /sys/bus/iio/devices/iio:device1/name
# Should show: ad9361-phy

# List IIO devices
ls /sys/bus/iio/devices/
```

### Run Beacon Scanner

```bash
# Make executable
chmod +x /root/beacon_scanner

# Test connection to AD9361
/root/beacon_scanner -h

# Scan channel 6
/root/beacon_scanner -m scan -c 6 -t 5000

# Automated scan
/root/beacon_scanner -a
```

### Performance on Zynq 7010

**Expected Performance:**

| Operation | Performance |
|-----------|-------------|
| **Scan speed** | ~500ms per channel |
| **CPU usage** | ~25% (single core) |
| **Memory** | ~85 MB total |
| **Power** | ~2W (typical) |

**Bottlenecks:**

- CPU speed (667 MHz) - adequate for beacon-only
- No hardware OFDM - all in software (slower but works)

---

## Optimization Tips

### Reduce Resource Usage Further

**If you need even smaller:**

1. **Remove TX support:**
```c
// In beacon_scanner.c, remove transmit_beacon() function
// Remove TX DMA from FPGA design
// Saves ~1K logic cells
```

2. **Single channel only:**
```c
// Remove channel scanning loop
// Hardcode to one channel
// Saves ~2 KB RAM
```

3. **Polling instead of DMA:**
```c
// Use programmed I/O instead of DMA
// Saves ~2K logic cells in FPGA
// Slower but works for low data rate
```

### Increase Performance

**If you have room:**

1. **Add simple hardware correlator:**
```verilog
// Add preamble detector in FPGA
// Reduces CPU load for sync detection
// Costs ~3K logic cells
```

2. **Use both ARM cores:**
```c
// Use pthread to parallelize
// Core 0: RX processing
// Core 1: Display and logging
```

3. **Overclock (carefully):**
```tcl
# In Vivado, increase PS clock
# 667 MHz → 800 MHz (if cooling adequate)
# Verify stability!
```

---

## Example Projects

### Minimal Zynq 7010 Configuration

**Download pre-built:**

```bash
# Placeholder - would host on GitHub releases
wget https://github.com/.../zynq7010_minimal.tar.gz
tar -xzf zynq7010_minimal.tar.gz

# Contains:
# - BOOT.BIN
# - uImage
# - devicetree.dtb
# - rootfs.tar.gz
# - beacon_scanner
```

### Build from Scratch

**Using PetaLinux:**

```bash
# Create PetaLinux project
petalinux-create -t project -n beacon_scanner_z7010 \
    --template zynq

cd beacon_scanner_z7010

# Configure for Zynq 7010
petalinux-config --get-hw-description=/path/to/hardware.xsa

# Enable AD9361 drivers
petalinux-config -c kernel

# Build
petalinux-build

# Package boot files
petalinux-package --boot \
    --fsbl images/linux/zynq_fsbl.elf \
    --fpga images/linux/system.bit \
    --u-boot
```

---

## Troubleshooting

### Not Enough Resources

**Error:** "Cannot fit design in target device"

**Solution:**
```tcl
# Check resource usage
report_utilization -hierarchical

# Reduce buffer sizes in C code:
#define BUFFER_SIZE 1024  # Instead of 4096

# Disable unused FPGA features
# Remove TX DMA if only scanning
```

### Slow Performance

**Symptom:** Scanning takes too long

**Solutions:**
1. Reduce dwell time: `-t 200` (200ms)
2. Scan fewer channels
3. Use both ARM cores (pthread)
4. Optimize C code with `-O3`

### Out of Memory

**Error:** Cannot allocate memory

**Solutions:**
```bash
# Reduce DMA buffer size
# In device tree, reduce DMA region

# Use swap (not recommended for production)
dd if=/dev/zero of=/swapfile bs=1M count=128
mkswap /swapfile
swapon /swapfile
```

---

## Comparison: Zynq 7010 vs Other Platforms

| Platform | Logic Cells | Cost | Beacon Scanner |
|----------|-------------|------|----------------|
| **Zynq 7010** | 28K | $30-50 | ✅ Software-only |
| Zynq 7020 | 85K | $80-150 | ✅ With HW accel |
| Zynq 7035 | 275K | $200+ | ✅ Full OFDM |
| PlutoSDR | 28K (Z7010) | $150 | ✅ Perfect fit |

**Recommendation:** Zynq 7010 is ideal for beacon-only, software implementation! ✅

---

## Next Steps

1. **Build FPGA design:**
   - Use Vivado 2021.1 or newer
   - Target xc7z010clg400-1
   - Follow minimal IP core list

2. **Build Linux:**
   - Use PetaLinux or Yocto
   - Enable AD9361 and IIO
   - Minimal configuration

3. **Deploy software:**
   - Cross-compile beacon_scanner
   - Copy to SD card
   - Boot and test

4. **Optimize:**
   - Profile with perf
   - Reduce resource usage
   - Tune for your use case

---

## Resources

### Zynq 7010 Documentation

- [Zynq 7000 TRM](https://www.xilinx.com/support/documentation/user_guides/ug585-Zynq-7000-TRM.pdf)
- [Zynq 7010 Datasheet](https://www.xilinx.com/support/documentation/data_sheets/ds190-Zynq-7000-Overview.pdf)

### AD9361 on Zynq

- [AD9361 HDL Reference](https://github.com/analogdevicesinc/hdl)
- [AD9361 Linux Driver](https://wiki.analog.com/resources/tools-software/linux-drivers/iio-transceiver/ad9361)

### Example Boards with Zynq 7010

- **ADALM-PLUTO** (PlutoSDR) - Uses Zynq 7010 + AD9364
- **MYIR Z-turn Lite** - Zynq 7010 dev board
- **Digilent Cora Z7-10** - Low-cost Zynq 7010

---

**This guide shows that the minimal beacon scanner FITS on Zynq 7010!** ✅

The key is running everything in ARM software and using FPGA only for AD9361 interface, which uses less than 20% of available logic cells.

---

**Document Version:** 1.0
**Last Updated:** 2025-11-21
**Target:** Zynq 7010 (xc7z010clg400-1)
