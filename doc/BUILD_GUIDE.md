# OpenWiFi Comprehensive Build and Configuration Guide

**Complete Build Instructions for All Components**
**Version:** 1.5.0+
**Last Updated:** 2025-11-21
**License:** AGPL-3.0-or-later

---

## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites and Dependencies](#prerequisites-and-dependencies)
3. [Repository Setup](#repository-setup)
4. [Cross-Compilation Environment](#cross-compilation-environment)
5. [Kernel Preparation](#kernel-preparation)
6. [Driver Compilation](#driver-compilation)
7. [FPGA Bitstream Generation](#fpga-bitstream-generation)
8. [SD Card Image Creation](#sd-card-image-creation)
9. [Boot Files Generation](#boot-files-generation)
10. [Board-Specific Configurations](#board-specific-configurations)
11. [Deployment Procedures](#deployment-procedures)
12. [Configuration Examples](#configuration-examples)
13. [Common Build Issues and Solutions](#common-build-issues-and-solutions)
14. [Advanced Topics](#advanced-topics)

---

## Introduction

This guide provides comprehensive instructions for building the complete openwifi system from source. OpenWiFi is a Linux mac80211-compatible full-stack IEEE 802.11/Wi-Fi implementation based on Software Defined Radio (SDR).

### Build System Overview

The openwifi build system consists of three main repositories:

1. **openwifi** (this repository): Linux drivers, user-space tools, kernel configurations
2. **openwifi-hw**: FPGA design files (Verilog/Verilog, Vivado projects)
3. **openwifi-hw-img**: Pre-built FPGA bitstreams (.xsa files) and SDK files

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    User Space Tools                          │
│  hostapd, wpa_supplicant, sdrctl, side_ch_ctl, inject_80211 │
└────────────────────┬────────────────────────────────────────┘
                     │ nl80211/cfg80211
┌────────────────────▼────────────────────────────────────────┐
│              Linux Kernel Space                              │
│  ┌─────────────────────────────────────────────────┐         │
│  │        mac80211 SoftMAC Subsystem               │         │
│  └────────────────┬────────────────────────────────┘         │
│  ┌────────────────▼────────────────────────────────┐         │
│  │  openwifi Driver (sdr.c)                        │         │
│  │  Component Drivers: tx_intf, rx_intf, xpu,      │         │
│  │  openofdm_tx, openofdm_rx, side_ch              │         │
│  └────────────────┬────────────────────────────────┘         │
└───────────────────┼─────────────────────────────────────────┘
                    │ AXI-Lite MMIO + DMA
┌───────────────────▼─────────────────────────────────────────┐
│                   FPGA (Zynq PL)                             │
│  tx_intf, rx_intf, xpu, openofdm_tx, openofdm_rx, side_ch   │
│  ├─ CSMA/CA MAC layer (10μs SIFS)                           │
│  ├─ OFDM Tx/Rx PHY                                          │
│  └─ Side channel & time-sensitive control                   │
└───────────────────┬─────────────────────────────────────────┘
                    │ Digital IF
┌───────────────────▼─────────────────────────────────────────┐
│              AD9361/AD9363/AD9364 RF Frontend                │
│              (70 MHz - 6 GHz transceiver)                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites and Dependencies

### Hardware Requirements

**Development Machine:**
- **OS:** Ubuntu 18.04/20.04/22.04 (64-bit) or compatible Linux distribution
- **RAM:** Minimum 16 GB (32 GB recommended for FPGA builds)
- **Storage:** 100+ GB free space for all tools and builds
- **CPU:** Multi-core processor (4+ cores recommended)

**Target Board:**
- One of the 13 supported boards (see [Board-Specific Configurations](#board-specific-configurations))
- SD card (16 GB minimum, Class 10 or faster)
- Antennas (2.4 GHz and/or 5 GHz depending on use case)
- Power supply appropriate for the board
- Ethernet cable for connection to development PC

### Software Dependencies

#### Required Packages (Ubuntu/Debian)

```bash
# Essential build tools
sudo apt-get update
sudo apt-get install -y build-essential git cmake

# Kernel build dependencies
sudo apt-get install -y flex bison libssl-dev device-tree-compiler u-boot-tools

# Cross-compilation toolchains
sudo apt-get install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf  # 32-bit ARM
sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu      # 64-bit ARM

# Additional utilities
sudo apt-get install -y unzip wget curl rsync
sudo apt-get install -y python3 python3-pip

# Optional: For visualization and analysis
sudo apt-get install -y python3-numpy python3-matplotlib python3-tk
```

#### Xilinx Vivado and Vitis

**Version Required:** Vivado/Vitis 2022.2

**Installation:**
1. Download Xilinx Vivado 2022.2 from [Xilinx Downloads](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-design-tools/2022-2.html)
2. Install both Vivado AND Vitis (NOT Vitis_HLS!)
3. Ensure you have the correct license for your board (see board table)
4. After installation, verify the directory structure:
   ```
   /opt/Xilinx/
   ├── Vivado/
   │   └── 2022.2/
   │       └── settings64.sh
   └── Vitis/
       └── 2022.2/
           └── settings64.sh
   ```

**License Requirements by Board:**

| Board | Vivado License Required |
|-------|------------------------|
| zc706_fmcs2 | Yes (Commercial) |
| zc702_fmcs2 | No (WebPack) |
| zed_fmcs2 | No (WebPack) |
| adrv9361z7035 | Yes (Commercial) |
| adrv9364z7020 | No (WebPack) |
| antsdr | No (WebPack) |
| antsdr_e200 | No (WebPack) |
| e310v2 | No (WebPack) |
| sdrpi | No (WebPack) |
| neptunesdr | No (WebPack) |
| zcu102_fmcs2 | Yes (Commercial) |
| zcu102_9371 | Yes (Commercial) |
| adrv9361z7035_fmc | Yes (Commercial) |

---

## Repository Setup

### Clone Required Repositories

```bash
# Set up workspace directory
export WORKSPACE=$HOME/openwifi-workspace
mkdir -p $WORKSPACE
cd $WORKSPACE

# Clone main openwifi repository (drivers, user-space tools, kernel configs)
git clone https://github.com/open-sdr/openwifi.git
cd openwifi

# Initialize and update kernel submodules
git submodule init adi-linux       # 32-bit ARM kernel
git submodule init adi-linux-64    # 64-bit ARM kernel (ZynqMP)
git submodule update adi-linux
git submodule update adi-linux-64

# Clone FPGA hardware images repository
cd $WORKSPACE
git clone https://github.com/open-sdr/openwifi-hw-img.git

# Optional: Clone FPGA source repository (only needed for FPGA development)
# git clone https://github.com/open-sdr/openwifi-hw.git
```

### Environment Variables Setup

Create a setup script for easy environment configuration:

```bash
# Create environment setup script
cat > $WORKSPACE/openwifi_env.sh << 'EOF'
#!/bin/bash

# OpenWiFi directories
export OPENWIFI_DIR=$WORKSPACE/openwifi
export OPENWIFI_HW_IMG_DIR=$WORKSPACE/openwifi-hw-img
# export OPENWIFI_HW_DIR=$WORKSPACE/openwifi-hw  # Only if building FPGA from source

# Xilinx installation directory
export XILINX_DIR=/opt/Xilinx

# Board name - set to your target board
export BOARD_NAME=antsdr  # Change this to your board

# Architecture (auto-detected based on board)
if [ "$BOARD_NAME" == "zcu102_fmcs2" ] || [ "$BOARD_NAME" == "zcu102_9371" ]; then
    export ARCH_BIT=64
else
    export ARCH_BIT=32
fi

echo "OpenWiFi environment configured:"
echo "  OPENWIFI_DIR: $OPENWIFI_DIR"
echo "  OPENWIFI_HW_IMG_DIR: $OPENWIFI_HW_IMG_DIR"
echo "  XILINX_DIR: $XILINX_DIR"
echo "  BOARD_NAME: $BOARD_NAME"
echo "  ARCH_BIT: $ARCH_BIT"
EOF

# Source the environment
source $WORKSPACE/openwifi_env.sh
```

---

## Cross-Compilation Environment

### Understanding ARM Architectures

OpenWiFi supports two ARM architectures:

1. **32-bit ARM (armv7):**
   - Used by: Zynq-7000 series (zc706, zc702, zed, adrv936x, antsdr, e310v2, sdrpi, neptunesdr)
   - Toolchain: `arm-linux-gnueabihf-`
   - Kernel: `adi-linux`
   - Kernel image: `uImage`

2. **64-bit ARM (aarch64):**
   - Used by: Zynq UltraScale+ MPSoC (zcu102)
   - Toolchain: `aarch64-linux-gnu-`
   - Kernel: `adi-linux-64`
   - Kernel image: `Image`

### Verify Cross-Compilation Tools

```bash
# For 32-bit ARM
arm-linux-gnueabihf-gcc --version
# Expected: arm-xilinx-linux-gnueabi-gcc (GCC) 10.2.0 or similar

# For 64-bit ARM
aarch64-linux-gnu-gcc --version
# Expected: aarch64-linux-gnu-gcc (Ubuntu) 9.x.x or later
```

### Xilinx Environment Setup

The build scripts automatically source the Xilinx environment:

```bash
# This is done automatically in build scripts:
source $XILINX_DIR/Vitis/2022.2/settings64.sh

# Manual verification:
which xsct      # Should return: /opt/Xilinx/Vitis/2022.2/bin/xsct
which bootgen   # Should return: /opt/Xilinx/Vitis/2022.2/bin/bootgen
which vivado    # Should return: /opt/Xilinx/Vivado/2022.2/bin/vivado
```

---

## Kernel Preparation

The Linux kernel must be prepared before building drivers. This step configures, patches, and optionally builds the Analog Devices Linux kernel.

### Kernel Preparation Script

**Location:** `/home/user/openwifi/user_space/prepare_kernel.sh`

**Purpose:**
- Initializes and checks out ADI Linux kernel submodules
- Applies openwifi-specific patches for AD9361 and HDMI support
- Configures the kernel with openwifi configuration
- Prepares kernel headers for driver compilation
- Optionally builds the complete kernel image

### Script Parameters

```bash
cd $OPENWIFI_DIR/user_space
./prepare_kernel.sh $XILINX_DIR ARCH_BIT
```

**Parameters:**
- `$XILINX_DIR`: Path to Xilinx installation (e.g., `/opt/Xilinx`)
- `ARCH_BIT`: `32` for Zynq-7000, `64` for Zynq UltraScale+ MPSoC

### Detailed Workflow

#### For 32-bit ARM (Zynq-7000)

```bash
cd $OPENWIFI_DIR/user_space
./prepare_kernel.sh /opt/Xilinx 32
```

**What it does:**

1. **Submodule Initialization:**
   ```bash
   cd $OPENWIFI_DIR
   git submodule init adi-linux
   git submodule update adi-linux
   cd adi-linux
   ```

2. **Checkout Specific Kernel Version:**
   ```bash
   git fetch
   git checkout 2022_R2
   git reset --hard c2f371e014f0704be4db02e5014c51ae99477c13  # TSN support
   ```

3. **Apply Configuration:**
   ```bash
   cp $OPENWIFI_DIR/kernel_boot/kernel_config ./.config
   ```

4. **Apply OpenWiFi Patches:**
   ```bash
   git apply ../kernel_boot/axi_hdmi_crtc.patch      # HDMI support
   git apply ../kernel_boot/ad9361.patch             # AD9361 driver updates
   git apply ../kernel_boot/ad9361_private.patch     # AD9361 private headers
   git apply ../kernel_boot/ad9361_conv.patch        # AD9361 converter updates
   ```

5. **Setup Cross-Compilation Environment:**
   ```bash
   source /opt/Xilinx/Vitis/2022.2/settings64.sh
   export ARCH=arm
   export CROSS_COMPILE=arm-linux-gnueabihf-
   ```

6. **Prepare Kernel:**
   ```bash
   make oldconfig                # Update configuration
   make prepare                  # Prepare kernel build
   make modules_prepare          # Prepare module build infrastructure
   ```

7. **Build Kernel and Modules (optional):**
   ```bash
   make -j12 uImage UIMAGE_LOADADDR=0x8000  # Build kernel image
   make modules                              # Build kernel modules
   ```

   **Output:** `$OPENWIFI_DIR/adi-linux/arch/arm/boot/uImage`

#### For 64-bit ARM (Zynq MPSoC)

```bash
cd $OPENWIFI_DIR/user_space
./prepare_kernel.sh /opt/Xilinx 64
```

**What it does:**

1. **Submodule Initialization:**
   ```bash
   cd $OPENWIFI_DIR
   git submodule init adi-linux-64
   git submodule update adi-linux-64
   cd adi-linux-64
   ```

2. **Checkout and Patch (same as 32-bit):**
   ```bash
   git checkout 2022_R2
   git reset --hard c2f371e014f0704be4db02e5014c51ae99477c13
   cp $OPENWIFI_DIR/kernel_boot/kernel_config_zynqmp ./.config
   git apply ../kernel_boot/axi_hdmi_crtc.patch
   git apply ../kernel_boot/ad9361.patch
   git apply ../kernel_boot/ad9361_private.patch
   git apply ../kernel_boot/ad9361_conv.patch
   ```

3. **Setup Cross-Compilation:**
   ```bash
   export ARCH=arm64
   export CROSS_COMPILE=aarch64-linux-gnu-
   ```

4. **Build:**
   ```bash
   make oldconfig
   make prepare && make modules_prepare
   make -j12 Image              # Note: "Image" not "uImage"
   make modules
   ```

   **Output:** `$OPENWIFI_DIR/adi-linux-64/arch/arm64/boot/Image`

### Kernel Configuration Details

The kernel configurations are located at:
- **32-bit:** `/home/user/openwifi/kernel_boot/kernel_config`
- **64-bit:** `/home/user/openwifi/kernel_boot/kernel_config_zynqmp`

**Key Configuration Features:**
- ADI (Analog Devices) drivers enabled
- IEEE 802.11 wireless subsystem (cfg80211, mac80211)
- Device tree support
- IIO (Industrial I/O) for AD9361 control
- DMA engine support (Xilinx AXI DMA)
- Ethernet, USB, SD card support
- Time-Sensitive Networking (TSN) support

### Kernel Patches Explained

**1. axi_hdmi_crtc.patch**
- Fixes for AXI HDMI display controller
- Enables HDMI output on boards with video support

**2. ad9361.patch**
- Updates to AD9361 transceiver driver
- OpenWiFi-specific enhancements for better Wi-Fi performance

**3. ad9361_private.patch**
- Exposes private AD9361 functions needed by openwifi drivers

**4. ad9361_conv.patch**
- Updates to AD9361 data converter interface
- Optimizations for IQ sample streaming

### Troubleshooting Kernel Preparation

**Issue: Kernel submodule not found**
```bash
# Solution: Initialize submodules
cd $OPENWIFI_DIR
git submodule init
git submodule update --recursive
```

**Issue: Patch fails to apply**
```bash
# Solution: Reset kernel tree and retry
cd $OPENWIFI_DIR/adi-linux  # or adi-linux-64
git reset --hard
git clean -fdx
cd $OPENWIFI_DIR/user_space
./prepare_kernel.sh /opt/Xilinx 32  # or 64
```

**Issue: Cross-compiler not found**
```bash
# Solution: Install cross-compilation tools
sudo apt-get install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf     # 32-bit
sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu         # 64-bit
```

**Issue: "flex: not found" or "bison: not found"**
```bash
# Solution: Install kernel build dependencies
sudo apt-get install -y flex bison libssl-dev device-tree-compiler u-boot-tools
```

---

## Driver Compilation

The openwifi driver consists of multiple kernel modules that interface between Linux mac80211 and the FPGA hardware.

### Driver Architecture

**Main Driver Modules:**

1. **sdr.ko** - Main SoftMAC driver (implements ieee80211_ops)
2. **openofdm_tx.ko** - OFDM transmitter control driver
3. **openofdm_rx.ko** - OFDM receiver control driver
4. **tx_intf.ko** - Tx DMA interface driver
5. **rx_intf.ko** - Rx DMA interface driver
6. **xpu.ko** - Packet processor unit (low MAC, CSMA/CA) driver
7. **side_ch.ko** - Side channel for time-sensitive control
8. **xilinx_dma.ko** - Xilinx DMA engine driver (included)

### Driver Build Script

**Location:** `/home/user/openwifi/driver/make_all.sh`

**Purpose:**
- Compiles all openwifi kernel modules
- Supports conditional compilation via pre-processor defines
- Generates git revision information

### Script Parameters

```bash
cd $OPENWIFI_DIR/driver
./make_all.sh $XILINX_DIR ARCH_BIT [DEFINE1] [DEFINE2] [DEFINE3] [DEFINE4] [DEFINE5]
```

**Parameters:**
- `$XILINX_DIR`: Path to Xilinx installation
- `ARCH_BIT`: `32` or `64`
- `DEFINE1-5` (optional): Preprocessor defines for conditional compilation

### Compilation Workflow

#### Standard Compilation (32-bit)

```bash
cd $OPENWIFI_DIR/driver
./make_all.sh /opt/Xilinx 32
```

**Detailed Steps:**

1. **Source Xilinx Environment:**
   ```bash
   source /opt/Xilinx/Vitis/2022.2/settings64.sh
   ```

2. **Set Kernel Source Directory:**
   ```bash
   LINUX_KERNEL_SRC_DIR=$OPENWIFI_DIR/adi-linux/
   ARCH="arm"
   CROSS_COMPILE="arm-linux-gnueabihf-"
   ```

3. **Generate Git Revision Header:**
   ```bash
   cd $OPENWIFI_DIR/driver/
   if git log -1; then
       echo "#define GIT_REV 0x"$(git log -1 --pretty=%h) > git_rev.h
   else
       echo "#define GIT_REV 0xFFFFFFFF" > git_rev.h
   fi
   ```

4. **Create pre_def.h with Conditional Defines:**
   ```bash
   echo "#define USE_NEW_RX_INTERRUPT 1" > pre_def.h
   # Additional defines from command-line arguments are appended
   ```

5. **Compile Each Module:**
   ```bash
   # OpenOFDM Tx driver
   cd $OPENWIFI_DIR/driver/openofdm_tx
   make KDIR=$LINUX_KERNEL_SRC_DIR ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE

   # OpenOFDM Rx driver
   cd $OPENWIFI_DIR/driver/openofdm_rx
   make KDIR=$LINUX_KERNEL_SRC_DIR ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE

   # Tx interface driver
   cd $OPENWIFI_DIR/driver/tx_intf
   make KDIR=$LINUX_KERNEL_SRC_DIR ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE

   # Rx interface driver
   cd $OPENWIFI_DIR/driver/rx_intf
   make KDIR=$LINUX_KERNEL_SRC_DIR ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE

   # XPU (packet processor) driver
   cd $OPENWIFI_DIR/driver/xpu
   make KDIR=$LINUX_KERNEL_SRC_DIR ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE

   # Side channel driver
   cd $OPENWIFI_DIR/driver/side_ch
   ./make_driver.sh /opt/Xilinx 32

   # Main SDR driver
   cd $OPENWIFI_DIR/driver/
   make KDIR=$LINUX_KERNEL_SRC_DIR ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE
   ```

**Output Files:**
```
$OPENWIFI_DIR/driver/sdr.ko
$OPENWIFI_DIR/driver/openofdm_tx/openofdm_tx.ko
$OPENWIFI_DIR/driver/openofdm_rx/openofdm_rx.ko
$OPENWIFI_DIR/driver/tx_intf/tx_intf.ko
$OPENWIFI_DIR/driver/rx_intf/rx_intf.ko
$OPENWIFI_DIR/driver/xpu/xpu.ko
$OPENWIFI_DIR/driver/side_ch/side_ch.ko
$OPENWIFI_DIR/driver/xilinx_dma/xilinx_dma.ko
```

#### Compilation with Custom Defines

You can pass up to 5 preprocessor defines for conditional compilation:

```bash
# Example: Enable custom features
cd $OPENWIFI_DIR/driver
./make_all.sh /opt/Xilinx 32 FEATURE_A FEATURE_B DEBUG_MODE
```

This creates:
```c
// pre_def.h
#define USE_NEW_RX_INTERRUPT 1
#define FEATURE_A
#define FEATURE_B
#define DEBUG_MODE
```

### Driver Module Details

#### sdr.ko (Main Driver)

**Source:** `/home/user/openwifi/driver/sdr.c`, `sdr.h`

**Implements:**
- ieee80211_ops API for mac80211 integration
- Tx/Rx packet handling
- RF control (AD9361 configuration)
- TSF (timing synchronization function)
- AMPDU aggregation support
- sdrctl interface via testmode_cmd
- Sysfs interfaces for debugging

**Key Functions:**
- `openwifi_tx()` - Transmit packet to FPGA
- `openwifi_rx_interrupt()` - Handle received packets
- `openwifi_tx_interrupt()` - Handle Tx completion
- `openwifi_start()` - Initialize NIC
- `openwifi_config()` - Channel/frequency configuration
- `openwifi_testmode_cmd()` - sdrctl command handler

#### Component Drivers

Each FPGA IP core has a corresponding kernel driver:

**openofdm_tx.ko / openofdm_rx.ko**
- Controls OFDM PHY layer
- Manages modulation/demodulation parameters
- Provides register access to FPGA OFDM cores

**tx_intf.ko / rx_intf.ko**
- DMA interface for packet transfer
- Ring buffer management
- Streaming IQ samples and packet data

**xpu.ko**
- Low MAC layer control (CSMA/CA)
- TSF timer management
- CCA threshold, SIFS/DIFS timing
- RTS/CTS configuration

**side_ch.ko**
- Side channel for auxiliary data
- GPIO control
- Custom signaling

### Transferring Drivers to Board

#### Method 1: SCP Transfer

```bash
cd $OPENWIFI_DIR/driver
scp `find ./ -name \*.ko` root@192.168.10.122:openwifi/
```

#### Method 2: Using Helper Script

```bash
cd $OPENWIFI_DIR/user_space
./transfer_driver_userspace_to_board.sh
```

#### Method 3: Creating Deployment Package

```bash
cd $OPENWIFI_DIR/user_space
./drv_and_fpga_package_gen.sh $OPENWIFI_HW_IMG_DIR /opt/Xilinx $BOARD_NAME

# This creates: drv_and_fpga.tar.gz
# Transfer to board:
scp drv_and_fpga.tar.gz root@192.168.10.122:~/
```

### Loading Drivers on Board

**Using wgd.sh (recommended):**
```bash
# On board:
cd ~/openwifi
./wgd.sh
```

**Manual loading:**
```bash
# On board:
cd ~/openwifi

# Load prerequisite modules
sudo modprobe mac80211
sudo insmod xilinx_dma.ko

# Load openwifi modules in order
sudo insmod side_ch.ko
sudo insmod openofdm_tx.ko
sudo insmod openofdm_rx.ko
sudo insmod tx_intf.ko
sudo insmod rx_intf.ko
sudo insmod xpu.ko
sudo insmod sdr.ko

# Verify
lsmod | grep -E "sdr|openofdm|xpu|_intf|side_ch"
```

### Troubleshooting Driver Compilation

**Issue: "fatal error: linux/module.h: No such file or directory"**
```bash
# Solution: Kernel not prepared
cd $OPENWIFI_DIR/user_space
./prepare_kernel.sh /opt/Xilinx 32  # or 64
```

**Issue: "version magic mismatch"**
```bash
# Solution: Kernel version mismatch between compiled modules and running kernel
# Need to update kernel on SD card or recompile with correct kernel
cd $OPENWIFI_DIR/adi-linux
cat include/generated/utsrelease.h  # Check compiled kernel version

# On board:
uname -r  # Check running kernel version
# If different, need to update kernel image on SD card
```

**Issue: "Unknown symbol" when loading module**
```bash
# Solution: Module dependencies not met or incorrect load order
# Check kernel logs:
dmesg | tail -50

# Verify all modules loaded in correct order (see "Loading Drivers on Board" above)
```

**Issue: Cross-compiler cannot create executables**
```bash
# Solution: Missing libraries or incorrect toolchain
sudo apt-get install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu

# Verify:
arm-linux-gnueabihf-gcc --version
aarch64-linux-gnu-gcc --version
```

---

## FPGA Bitstream Generation

The FPGA bitstream contains the hardware implementation of the Wi-Fi PHY/MAC layers. For most users, pre-built bitstreams from the openwifi-hw-img repository are sufficient. This section covers both using pre-built bitstreams and building from source.

### Using Pre-built Bitstreams

**Location:** `$OPENWIFI_HW_IMG_DIR/boards/$BOARD_NAME/sdk/system_top.xsa`

The `.xsa` file contains:
- FPGA bitstream (.bit)
- Hardware definition for SDK
- All necessary metadata

#### Converting .xsa to .bit.bin

The FPGA needs the bitstream in `.bit.bin` format for dynamic loading. This conversion is done by `boot_bin_gen.sh`:

```bash
cd $OPENWIFI_DIR/user_space
./boot_bin_gen.sh /opt/Xilinx $BOARD_NAME $OPENWIFI_HW_IMG_DIR/boards/$BOARD_NAME/sdk/system_top.xsa
```

**What it does:**

1. **Extract Bitstream from .xsa:**
   ```bash
   unzip -o system_top.xsa
   # Extracts: system_top.bit
   ```

2. **Convert to Binary Format:**
   ```bash
   # Creates .bif file:
   echo "all:" > ./fpga_bit_to_bin.bif
   echo "{" >> ./fpga_bit_to_bin.bif
   echo "system_top.bit" >> ./fpga_bit_to_bin.bif
   echo "}" >> ./fpga_bit_to_bin.bif

   # Convert using bootgen:
   bootgen -image fpga_bit_to_bin.bif -arch zynq -process_bitstream bin -w
   # Output: system_top.bit.bin
   ```

3. **Transfer to Board:**
   ```bash
   scp system_top.bit.bin root@192.168.10.122:openwifi/
   ```

### Building FPGA from Source (Advanced)

**Prerequisites:**
- openwifi-hw repository cloned
- Vivado 2022.2 with appropriate license
- 50+ GB disk space
- 4-8 hours build time

**Repository:** https://github.com/open-sdr/openwifi-hw

```bash
cd $WORKSPACE
git clone https://github.com/open-sdr/openwifi-hw.git
cd openwifi-hw
```

#### FPGA Build Process

**1. Board Selection:**
```bash
cd $WORKSPACE/openwifi-hw/boards/$BOARD_NAME
```

**2. Open Vivado Project:**
```bash
source /opt/Xilinx/Vivado/2022.2/settings64.sh
vivado openwifi.xpr &
```

**3. Build in Vivado GUI:**
- Open Block Design: `openwifi.bd`
- Validate Design: Tools → Validate Design
- Generate Bitstream: Flow → Generate Bitstream
- Export Hardware: File → Export → Export Hardware (include bitstream)
- Output: `system_top.xsa`

**4. Or Build via Tcl Script (if available):**
```bash
vivado -mode batch -source build.tcl
```

#### FPGA IP Cores

The openwifi FPGA design consists of:

**Custom IP Cores:**
- `openofdm_tx` - OFDM transmitter (Verilog)
- `openofdm_rx` - OFDM receiver (Verilog)
- `tx_intf` - Tx interface and DMA (Verilog)
- `rx_intf` - Rx interface and DMA (Verilog)
- `xpu` - Packet processor, low MAC, CSMA/CA (Verilog)
- `side_ch` - Side channel interface (Verilog)

**Xilinx IP:**
- Zynq Processing System (PS)
- AXI Interconnects
- AXI DMA
- AXI GPIO
- Clock wizards
- AD9361 interface IP

**Integration:**
```
┌────────────────────────────────────────────────┐
│            Zynq Processing System              │
│  (ARM Cortex-A9/A53 + DDR + Peripherals)       │
└─────────┬──────────────────────┬───────────────┘
          │ AXI HP (DMA)         │ AXI GP (Control)
┌─────────▼──────────────────────▼───────────────┐
│           AXI Interconnect                      │
└─┬────┬────┬────┬────┬────┬────┬────────────────┘
  │    │    │    │    │    │    │
  │    │    │    │    │    │    └─→ side_ch
  │    │    │    │    │    └──────→ xpu
  │    │    │    │    └───────────→ rx_intf ──→ openofdm_rx
  │    │    │    └────────────────→ tx_intf ──→ openofdm_tx
  │    │    └─────────────────────→ AXI GPIO
  │    └──────────────────────────→ Clock Wizard
  └───────────────────────────────→ AD9361 Interface
                                    │
                                    ▼
                              AD9361 RF Chip
```

### FPGA Resource Utilization

Typical resource usage varies by board. Example for Zynq-7020:

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUTs | ~35,000 | 53,200 | ~65% |
| FFs | ~42,000 | 106,400 | ~40% |
| BRAM | ~80 | 140 | ~57% |
| DSP | ~120 | 220 | ~55% |

### Modifying FPGA Design

To modify and rebuild a specific IP core:

```bash
cd $WORKSPACE/openwifi-hw/ip/openofdm_tx  # or any IP core

# Edit Verilog files
vim src/openofdm_tx.v

# Re-package IP
vivado -mode batch -source package_ip.tcl

# Rebuild project
cd ../../boards/$BOARD_NAME
vivado -mode batch -source build.tcl
```

---

## SD Card Image Creation

This section covers creating a bootable SD card image from scratch or updating an existing image.

### Option 1: Use Pre-built Image (Quickest)

**Download Pre-built Image:**
```bash
cd $WORKSPACE
wget https://users.ugent.be/~xjiao/openwifi-1.5.0-shahecheng.img.xz
unxz openwifi-1.5.0-shahecheng.img.xz
```

**Flash to SD Card:**
```bash
# Identify SD card device (CAREFUL! Wrong device = data loss)
lsblk
# Example output: /dev/sdb (SD card), /dev/sda (your system drive)

# Flash image (replace /dev/sdX with your SD card device)
sudo dd bs=512 count=31116288 if=openwifi-1.5.0-shahecheng.img of=/dev/sdX status=progress
sync

# Verify
fdisk -l openwifi-1.5.0-shahecheng.img
```

**Configure for Your Board:**
```bash
# Mount SD card partitions
sudo mkdir -p /mnt/sdcard_boot /mnt/sdcard_rootfs
sudo mount /dev/sdX1 /mnt/sdcard_boot
sudo mount /dev/sdX2 /mnt/sdcard_rootfs

# Copy board-specific files to BOOT partition
sudo cp /mnt/sdcard_boot/openwifi/$BOARD_NAME/* /mnt/sdcard_boot/

# Clean up (if needed)
sudo rm -rf /mnt/sdcard_rootfs/root/kernel_modules
sudo rm -rf /mnt/sdcard_rootfs/etc/network/interfaces.new

# Unmount
sudo umount /mnt/sdcard_boot
sudo umount /mnt/sdcard_rootfs
```

### Option 2: Build from ADI Kuiper Linux Base

**Download ADI Kuiper Base Image:**
```bash
cd $WORKSPACE
wget https://github.com/analogdevicesinc/adi-kuiper-gen/releases/download/13-December-2023-v0.10/image_2023-12-13-ADI-Kuiper-full.zip
unzip image_2023-12-13-ADI-Kuiper-full.zip
```

**Flash Base Image:**
```bash
sudo dd bs=512 count=24182784 if=2023-12-13-ADI-Kuiper-full.img of=/dev/sdX status=progress
sync
```

**Mount Partitions:**
```bash
sudo mkdir -p /mnt/sdcard_boot /mnt/sdcard_rootfs
sudo mount /dev/sdX1 /mnt/sdcard_boot
sudo mount /dev/sdX2 /mnt/sdcard_rootfs
```

**Configure Network:**
```bash
# Edit rootfs/etc/network/interfaces
sudo tee /mnt/sdcard_rootfs/etc/network/interfaces > /dev/null << 'EOF'
# The loopback interface
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.10.122
    gateway 192.168.10.1
    netmask 255.255.255.0
    network 192.168.10.0
    broadcast 192.168.10.255
EOF
```

**Configure System:**
```bash
# Enable IP forwarding
sudo bash -c "echo 'net.ipv4.ip_forward=1' >> /mnt/sdcard_rootfs/etc/sysctl.conf"

# Reduce shutdown timeout
sudo sed -i 's/#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=2s/' /mnt/sdcard_rootfs/etc/systemd/system.conf

# Copy udev rules for network device naming
sudo cp $OPENWIFI_DIR/kernel_boot/10-network-device.rules /mnt/sdcard_rootfs/etc/udev/rules.d/
```

**Populate SD Card with OpenWiFi:**
```bash
cd $OPENWIFI_DIR/user_space

# Run update_sdcard.sh
# This will build kernel, drivers, and populate SD card
./update_sdcard.sh $OPENWIFI_HW_IMG_DIR /opt/Xilinx /mnt/sdcard

# Syntax: ./update_sdcard.sh $OPENWIFI_HW_IMG_DIR $XILINX_DIR $SDCARD_DIR [SKIP_FLAGS] [BOARD_NAMES]
# SKIP_FLAGS (optional): bit 0: skip kernel, bit 1: skip BOOT, bit 2: skip rootfs
# BOARD_NAMES (optional): space-separated list of boards (default: all supported boards)
```

**What update_sdcard.sh does:**

1. **Kernel Preparation (both 32-bit and 64-bit):**
   ```bash
   ./prepare_kernel.sh /opt/Xilinx 32
   ./prepare_kernel.sh /opt/Xilinx 64
   ```

2. **For Each Board:**
   - Generate BOOT.BIN using `boot_bin_gen.sh`
   - Compile device tree (.dts → .dtb)
   - Convert FPGA bitstream (.xsa → .bit.bin)
   - Copy to BOOT partition: `BOOT/openwifi/$BOARD_NAME/`
     - BOOT.BIN
     - devicetree.dtb (or system.dtb for ZynqMP)
     - system_top.bit.bin

3. **Kernel Images:**
   - Copy to BOOT partition:
     - `Image` (64-bit kernel for ZynqMP)
     - `uImage` (32-bit kernel for Zynq)

4. **Rootfs Population:**
   - Copy user_space tools to `/root/openwifi/`
   - Copy board-specific files to `/root/openwifi_BOOT/`
   - For both 32-bit and 64-bit:
     - Build all drivers (./make_all.sh)
     - Copy .ko files to `/root/openwifi32/` or `/root/openwifi64/`
     - Copy kernel modules to `/root/kernel_modules32/` or `/root/kernel_modules64/`
   - Download video file for web server

**Manual Alternative (Build Components Separately):**

If you want more control, you can run individual steps:

```bash
# 1. Prepare kernels
cd $OPENWIFI_DIR/user_space
./prepare_kernel.sh /opt/Xilinx 32
./prepare_kernel.sh /opt/Xilinx 64

# 2. Build drivers for your architecture
cd $OPENWIFI_DIR/driver
./make_all.sh /opt/Xilinx 32  # or 64 for ZynqMP

# 3. Generate boot files for your board
cd $OPENWIFI_DIR/user_space
./boot_bin_gen.sh /opt/Xilinx $BOARD_NAME $OPENWIFI_HW_IMG_DIR/boards/$BOARD_NAME/sdk/system_top.xsa

# 4. Compile device tree
cd $OPENWIFI_DIR/kernel_boot/boards/$BOARD_NAME
if [ "$BOARD_NAME" == "zcu102_fmcs2" ]; then
    dtc -I dts -O dtb -o system.dtb system.dts
else
    dtc -I dts -O dtb -o devicetree.dtb devicetree.dts
fi

# 5. Manually copy files to mounted SD card
# ... (see directory structure below)
```

**Unmount SD Card:**
```bash
cd /
sudo umount /mnt/sdcard_boot
sudo umount /mnt/sdcard_rootfs
sync
```

### SD Card Directory Structure

After building, the SD card should have this structure:

```
SD CARD
├── BOOT (Partition 1, FAT32)
│   ├── BOOT.BIN (from current board config)
│   ├── devicetree.dtb or system.dtb (from current board config)
│   ├── uImage (32-bit kernel)
│   ├── Image (64-bit kernel)
│   └── openwifi/
│       ├── antsdr/
│       │   ├── BOOT.BIN
│       │   ├── devicetree.dtb
│       │   └── system_top.bit.bin
│       ├── antsdr_e200/
│       │   └── ...
│       ├── e310v2/
│       │   └── ...
│       ├── sdrpi/
│       │   └── ...
│       ├── zc706_fmcs2/
│       │   └── ...
│       ├── zc702_fmcs2/
│       │   └── ...
│       ├── zed_fmcs2/
│       │   └── ...
│       ├── adrv9361z7035/
│       │   └── ...
│       ├── adrv9364z7020/
│       │   └── ...
│       ├── neptunesdr/
│       │   └── ...
│       └── zcu102_fmcs2/
│           ├── BOOT.BIN
│           ├── system.dtb
│           └── system_top.bit.bin
│
└── rootfs (Partition 2, ext4)
    ├── bin/, lib/, usr/, etc/ (standard Linux filesystem)
    └── root/
        ├── openwifi/              (user space tools and scripts)
        │   ├── wgd.sh
        │   ├── fosdem.sh
        │   ├── sdrctl
        │   ├── hostapd-openwifi.conf
        │   └── ... (all user_space files)
        ├── openwifi32/            (32-bit drivers)
        │   ├── sdr.ko
        │   ├── openofdm_tx.ko
        │   ├── openofdm_rx.ko
        │   ├── tx_intf.ko
        │   ├── rx_intf.ko
        │   ├── xpu.ko
        │   └── side_ch.ko
        ├── openwifi64/            (64-bit drivers)
        │   └── ... (same as openwifi32)
        ├── openwifi_BOOT/         (copy of all board configs)
        │   └── ... (mirror of BOOT/openwifi/)
        ├── kernel_modules32/      (32-bit kernel modules)
        │   └── *.ko (all kernel modules)
        └── kernel_modules64/      (64-bit kernel modules)
            └── *.ko (all kernel modules)
```

### First Boot Configuration

After inserting SD card and booting:

```bash
# On PC: Setup static IP
sudo ip addr add 192.168.10.1/24 dev ethX  # Replace ethX with your interface

# SSH to board (password: analog for fresh Kuiper, openwifi for pre-built image)
ssh root@192.168.10.122

# On board: Change password
passwd
# Enter new password: openwifi

# Expand rootfs (if SD card > 16GB)
raspi-config --expand-rootfs
reboot now

# After reboot, SSH again
ssh root@192.168.10.122

# Run setup (only once)
cd ~/openwifi
chmod +x *.sh
./setup_once.sh
reboot now

# Setup internet routing on PC
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o wlanX -j MASQUERADE  # Replace wlanX
sudo ip route add 192.168.13.0/24 via 192.168.10.122 dev ethX

# SSH again and test
ssh root@192.168.10.122
ping 8.8.8.8  # Should work if routing is correct

# Install required packages (one-time)
sudo apt-get update
sudo apt-get install -y isc-dhcp-server hostapd tcpdump webfs iperf iperf3
sudo apt-get install -y libpcap-dev bridge-utils libnl-3-dev libnl-genl-3-dev

# Build on-board tools
cd ~/openwifi/sdrctl_src
make clean && make
cp sdrctl ../

cd ~/openwifi/side_ch_ctl_src
gcc -o side_ch_ctl side_ch_ctl.c
cp side_ch_ctl ../

cd ~/openwifi/inject_80211
make clean && make
```

---

## Boot Files Generation

Boot files are required for Zynq devices to configure the FPGA and boot the ARM processor.

### Boot File Components

**For Zynq-7000 (32-bit):**
- **BOOT.BIN** contains:
  1. FSBL (First Stage Boot Loader)
  2. FPGA bitstream (system_top.bit)
  3. U-Boot (u-boot.elf)

**For Zynq UltraScale+ MPSoC (64-bit):**
- **BOOT.BIN** contains:
  1. FSBL (First Stage Boot Loader)
  2. PMUFW (Platform Management Unit Firmware)
  3. FPGA bitstream (system_top.bit)
  4. ATF (ARM Trusted Firmware - bl31.elf)
  5. U-Boot (u-boot.elf)

### Zynq-7000 Boot Generation

**Script:** `/home/user/openwifi/kernel_boot/build_boot_bin.sh`

**Usage:**
```bash
cd $OPENWIFI_DIR/kernel_boot
./build_boot_bin.sh system_top.xsa u-boot.elf [output-archive]
```

**Called by boot_bin_gen.sh:**
```bash
cd $OPENWIFI_DIR/kernel_boot
./build_boot_bin.sh \
    $OPENWIFI_HW_IMG_DIR/boards/$BOARD_NAME/sdk/system_top.xsa \
    boards/$BOARD_NAME/u-boot.elf
```

**Process:**

1. **Extract Components from .xsa:**
   ```bash
   unzip system_top.xsa
   # Extracts: system_top.bit and hardware definition
   ```

2. **Generate FSBL using XSCT:**
   ```tcl
   # Create create_fsbl_project.tcl
   hsi open_hw_design system_top.xsa
   set cpu_name [lindex [hsi get_cells -filter {IP_TYPE==PROCESSOR}] 0]
   platform create -name hw0 -hw system_top.xsa -os standalone -proc $cpu_name
   platform generate
   ```

   ```bash
   xsct create_fsbl_project.tcl
   # Generates: build_boot_bin/build/sdk/hw0/export/hw0/sw/hw0/boot/fsbl.elf
   ```

3. **Create Boot Image Format file (zynq.bif):**
   ```
   the_ROM_image:
   {
       [bootloader] fsbl.elf
       system_top.bit
       u-boot.elf
   }
   ```

4. **Generate BOOT.BIN:**
   ```bash
   bootgen -arch zynq -image zynq.bif -o BOOT.BIN -w
   ```

**Output:** `$OPENWIFI_DIR/kernel_boot/boards/$BOARD_NAME/output_boot_bin/BOOT.BIN`

### Zynq MPSoC Boot Generation

**Script:** `/home/user/openwifi/kernel_boot/build_zynqmp_boot_bin.sh`

**Usage:**
```bash
cd $OPENWIFI_DIR/kernel_boot
./build_zynqmp_boot_bin.sh system_top.xsa u-boot.elf (download | bl31.elf | path-to-atf) [output-archive]
```

**Called by boot_bin_gen.sh:**
```bash
cd $OPENWIFI_DIR/kernel_boot
./build_zynqmp_boot_bin.sh \
    $OPENWIFI_HW_IMG_DIR/boards/$BOARD_NAME/sdk/system_top.xsa \
    boards/$BOARD_NAME/u-boot_xilinx_zynqmp_zcu102_revA.elf \
    boards/$BOARD_NAME/bl31.elf
```

**Process:**

1. **Get or Build ARM Trusted Firmware (ATF):**

   **Option A: Use provided bl31.elf:**
   ```bash
   cp boards/$BOARD_NAME/bl31.elf output_boot_bin/
   ```

   **Option B: Download and build ATF:**
   ```bash
   git clone https://github.com/Xilinx/arm-trusted-firmware.git
   cd arm-trusted-firmware
   git checkout xilinx-v2022.2
   make CROSS_COMPILE=aarch64-linux-gnu- PLAT=zynqmp RESET_TO_BL31=1 ZYNQMP_CONSOLE=cadence0
   # Output: build/zynqmp/release/bl31/bl31.elf
   ```

2. **Generate FSBL and PMUFW:**
   ```tcl
   hsi open_hw_design system_top.xsa
   set cpu_name [lindex [hsi get_cells -filter {IP_TYPE==PROCESSOR}] 0]
   platform create -name hw0 -hw system_top.xsa -os standalone -proc $cpu_name
   platform generate
   ```

   **Outputs:**
   - FSBL: `build/sdk/hw0/export/hw0/sw/hw0/boot/fsbl.elf`
   - PMUFW: `build/sdk/hw0/export/hw0/sw/hw0/boot/pmufw.elf`

3. **Create Boot Image Format (zynq.bif):**
   ```
   the_ROM_image:
   {
       [bootloader,destination_cpu=a53-0] fsbl.elf
       [pmufw_image] pmufw.elf
       [destination_device=pl] system_top.bit
       [destination_cpu=a53-0,exception_level=el-3,trustzone] bl31.elf
       [destination_cpu=a53-0,exception_level=el-2] u-boot.elf
   }
   ```

4. **Generate BOOT.BIN:**
   ```bash
   bootgen -arch zynqmp -image zynq.bif -o BOOT.BIN -w
   ```

**Output:** `$OPENWIFI_DIR/kernel_boot/boards/$BOARD_NAME/output_boot_bin/BOOT.BIN`

### Unified Boot Generation Script

**Script:** `/home/user/openwifi/user_space/boot_bin_gen.sh`

**Usage:**
```bash
cd $OPENWIFI_DIR/user_space
./boot_bin_gen.sh $XILINX_DIR $BOARD_NAME $XSA_FILE
```

**Example:**
```bash
cd $OPENWIFI_DIR/user_space
./boot_bin_gen.sh /opt/Xilinx antsdr $OPENWIFI_HW_IMG_DIR/boards/antsdr/sdk/system_top.xsa
```

**What it does:**

1. **Detects Board Architecture:**
   ```bash
   if [ "$BOARD_NAME" == "zcu102_fmcs2" ] || [ "$BOARD_NAME" == "zcu102_9371" ]; then
       ARCH="zynqmp"
       ARCH_BIT=64
       # Call build_zynqmp_boot_bin.sh
   else
       ARCH="zynq"
       ARCH_BIT=32
       # Call build_boot_bin.sh
   fi
   ```

2. **Calls Appropriate Script:**
   ```bash
   cd $OPENWIFI_DIR/kernel_boot
   if [ $ARCH == "zynqmp" ]; then
       ./build_zynqmp_boot_bin.sh $XSA_FILE boards/$BOARD_NAME/u-boot.elf boards/$BOARD_NAME/bl31.elf
   else
       ./build_boot_bin.sh $XSA_FILE boards/$BOARD_NAME/u-boot.elf
   fi
   ```

3. **Organizes Output:**
   ```bash
   rm -rf build_boot_bin
   mv output_boot_bin boards/$BOARD_NAME/
   ```

4. **Generates .bit.bin for FPGA Dynamic Loading:**
   ```bash
   # Create .bif for bitstream conversion
   echo "all:" > ./fpga_bit_to_bin.bif
   echo "{" >> ./fpga_bit_to_bin.bif
   echo "system_top.bit" >> ./fpga_bit_to_bin.bif
   echo "}" >> ./fpga_bit_to_bin.bif

   # Extract and convert
   unzip -o $XSA_FILE
   bootgen -image fpga_bit_to_bin.bif -arch $ARCH -process_bitstream bin -w
   # Output: system_top.bit.bin
   ```

**Outputs:**
- `boards/$BOARD_NAME/output_boot_bin/BOOT.BIN`
- `system_top.bit.bin` (in user_space directory)

### Board-Specific U-Boot and Bootloaders

Each board has pre-compiled bootloader components in `kernel_boot/boards/$BOARD_NAME/`:

**Zynq-7000 Boards:**
- `u-boot.elf` - Pre-compiled U-Boot

**Zynq MPSoC Boards:**
- `u-boot_xilinx_zynqmp_zcu102_revA.elf` - Pre-compiled U-Boot
- `bl31.elf` - Pre-compiled ARM Trusted Firmware

**Note:** These are board-specific and tested. Custom U-Boot builds require detailed knowledge of device trees and board initialization.

---

## Board-Specific Configurations

OpenWiFi supports 13 different hardware platforms. Each board has unique characteristics and configuration requirements.

### Supported Boards Summary

| Board Name | SoC | RF Chip | ARCH_BIT | Vivado License | Notes |
|------------|-----|---------|----------|----------------|-------|
| **zc706_fmcs2** | Zynq-7045 | AD9361 (FMCOMMS2/3/4) | 32 | Commercial | High-end Xilinx eval board |
| **zc702_fmcs2** | Zynq-7020 | AD9361 (FMCOMMS2/3/4) | 32 | WebPack | Xilinx eval board |
| **zed_fmcs2** | Zynq-7020 | AD9361 (FMCOMMS2/3/4) | 32 | WebPack | Avnet ZedBoard + FMC |
| **adrv9361z7035** | Zynq-7035 | AD9361 | 32 | Commercial | ADI integrated board + BOB/FMC |
| **adrv9364z7020** | Zynq-7020 | AD9364 | 32 | WebPack | ADI integrated board + BOB |
| **antsdr** | Zynq-7020 | AD9361 | 32 | WebPack | MicroPhase compact SDR |
| **antsdr_e200** | Zynq-7020 | AD9361 | 32 | WebPack | MicroPhase compact, PL Ethernet |
| **e310v2** | Zynq-7020 | AD9361 | 32 | WebPack | MicroPhase with GPS, VCXO |
| **sdrpi** | Zynq-7020 | AD9361 | 32 | WebPack | HexSDR Raspberry Pi form factor |
| **neptunesdr** | Zynq-7020 | AD9361 | 32 | WebPack | Low-cost community board |
| **zcu102_fmcs2** | Zynq MPSoC (ZU9EG) | AD9361 (FMCOMMS2/3/4) | 64 | Commercial | High-end ZynqMP eval board |
| **zcu102_9371** | Zynq MPSoC (ZU9EG) | AD9371 | 64 | Commercial | ZCU102 + AD9371 (advanced) |
| **adrv9361z7035_fmc** | Zynq-7035 | AD9361 | 32 | Commercial | ADRV9361 with FMC connector |

### Board-Specific File Locations

Each board has a directory: `/home/user/openwifi/kernel_boot/boards/$BOARD_NAME/`

**Common Files:**
- `devicetree.dts` or `system.dts` - Device tree source
- `devicetree.dtb` or `system.dtb` - Compiled device tree
- `u-boot.elf` - U-Boot bootloader
- `bl31.elf` - ARM Trusted Firmware (64-bit only)
- `output_boot_bin/BOOT.BIN` - Generated boot file
- `README.md` or `notes.md` - Board-specific documentation

### Device Tree Configuration

The device tree defines hardware components and their interconnections.

**Location:**
- 32-bit: `kernel_boot/boards/$BOARD_NAME/devicetree.dts`
- 64-bit: `kernel_boot/boards/$BOARD_NAME/system.dts`

**Key Sections:**

```dts
/ {
    // CPU and memory
    cpus { ... }
    memory { ... }

    // AXI bus and peripherals
    axi {
        // OpenWiFi FPGA modules
        tx_intf@83c00000 { ... };
        rx_intf@83c10000 { ... };
        openofdm_tx@83c20000 { ... };
        openofdm_rx@83c30000 { ... };
        xpu@83c40000 { ... };
        side_ch@83c50000 { ... };

        // AD9361 interface
        cf-ad9361-lpc@79020000 { ... };
        cf-ad9361-dds-core-lpc@79024000 { ... };

        // DMA engines
        dma@80400000 { ... };

        // Other peripherals (GPIO, UART, Ethernet, etc.)
        ...
    };
};
```

**Compiling Device Tree:**
```bash
cd $OPENWIFI_DIR/kernel_boot/boards/$BOARD_NAME

# For 32-bit boards:
dtc -I dts -O dtb -o devicetree.dtb devicetree.dts

# For 64-bit boards:
dtc -I dts -O dtb -o system.dtb system.dts
```

### Board-Specific Configurations

#### antsdr

**Specifications:**
- SoC: Zynq-7020
- RF: AD9361 (70 MHz - 6 GHz)
- Form factor: Compact (similar to ADALM-PLUTO++)
- Ethernet: PS-based GigE
- Special features: RF switch for frequency ranges

**RF Switch Configuration:**
```
< 3 GHz: Isolated (switch position for 3-6 GHz range)
≥ 3 GHz: Passed through
```

**Notes:**
- RF switch currently fixed in hardware
- Future: Software-controlled RF switch via device tree
- See: `/home/user/openwifi/kernel_boot/boards/antsdr/notes.md`

**Quick Start:**
```bash
export BOARD_NAME=antsdr
cd $OPENWIFI_DIR/user_space
./boot_bin_gen.sh /opt/Xilinx $BOARD_NAME $OPENWIFI_HW_IMG_DIR/boards/$BOARD_NAME/sdk/system_top.xsa
scp system_top.bit.bin root@192.168.10.122:openwifi/

cd $OPENWIFI_DIR/driver
./make_all.sh /opt/Xilinx 32
scp `find ./ -name \*.ko` root@192.168.10.122:openwifi/
```

#### antsdr_e200

**Specifications:**
- SoC: Zynq-7020
- RF: AD9361
- Form factor: Smaller/cheaper than antsdr
- **Ethernet: PL-based** (uses FPGA fabric)

**Unique Features:**
- Ethernet implemented in programmable logic (PL)
- Still uses Zynq GEM controller
- Higher bandwidth for IIO streaming
- Compatible with UHD driver: https://github.com/MicroPhase/antsdr_uhd

**Architecture:**
```
  ┌──────────────────────────────────┐
  │     Zynq-7020 PS                 │
  │  (ARM Cortex-A9, DDR, USB, SD)   │
  └───────┬──────────────────────────┘
          │ AXI
  ┌───────▼──────────────────────────┐
  │     Zynq-7020 PL (FPGA)          │
  │  ┌────────────────────────────┐  │
  │  │  OpenWiFi IP Cores         │  │
  │  └────────────────────────────┘  │
  │  ┌────────────────────────────┐  │
  │  │  GEM Ethernet MAC          │──┼──→ RJ45 Ethernet
  │  │  (routed through PL)       │  │
  │  └────────────────────────────┘  │
  └───────┬──────────────────────────┘
          │
  ┌───────▼──────────────────────────┐
  │      AD9361 RF Transceiver       │
  └──────────────────────────────────┘
```

**See:** `/home/user/openwifi/kernel_boot/boards/antsdr_e200/README.md`

#### e310v2

**Specifications:**
- SoC: Zynq-7020
- RF: AD9361
- Special features:
  - **GPS module** integrated
  - **VCXO** (Voltage Controlled Crystal Oscillator)
  - **External 10 MHz/PPS input**
  - PL-based Ethernet (like E200)

**Clock Architecture:**
```
External 10MHz ──┐
                 ├──→ VCXO + DAC ──→ High-precision clock
GPS PPS ─────────┘
```

**Applications:**
- Time-sensitive networking
- GPS-synchronized communications
- Distributed MIMO
- Accurate frequency reference applications

**Compatible with UHD:** https://github.com/MicroPhase/antsdr_uhd

**See:** `/home/user/openwifi/kernel_boot/boards/e310v2/README.md`

#### sdrpi

**Specifications:**
- SoC: Zynq-7020
- RF: AD9361
- Form factor: Raspberry Pi size/shape
- Developer: HexSDR

**Features:**
- Compact form factor
- Compatible mounting holes with RPi
- Standard FPGA peripherals

**Notes:**
- See: `/home/user/openwifi/kernel_boot/boards/sdrpi/notes.md`

#### zc706_fmcs2, zc702_fmcs2, zed_fmcs2

**Development Board + FMC Card Setup:**

**zc706_fmcs2:**
- Board: Xilinx ZC706 Evaluation Board
- SoC: Zynq-7045 (high-end, large FPGA)
- FMC: FMCOMMS2/3/4 (AD9361 carrier)
- License: **Commercial required**
- Use case: Advanced development, maximum resources

**zc702_fmcs2:**
- Board: Xilinx ZC702 Evaluation Board
- SoC: Zynq-7020
- FMC: FMCOMMS2/3/4
- License: WebPack (free)
- Use case: Standard development

**zed_fmcs2:**
- Board: Avnet ZedBoard
- SoC: Zynq-7020
- FMC: FMCOMMS2/3/4
- License: WebPack (free)
- Use case: Popular low-cost eval platform

**FMC Cards (FMCOMMS):**
- FMCOMMS2: AD9361, 2x2 MIMO, 70 MHz - 6 GHz
- FMCOMMS3: AD9363, 1x1 SISO, 70 MHz - 6 GHz
- FMCOMMS4: AD9364, 1x1 SISO, 70 MHz - 6 GHz

**Connection:**
```
Xilinx Eval Board (ZC706/ZC702/ZED)
        │
        │ FMC Connector (FPGA Mezzanine Card)
        │
        ▼
FMCOMMS2/3/4 Card
        │
        ▼
    Antennas
```

#### adrv9361z7035, adrv9364z7020

**Analog Devices Integrated Boards:**

**adrv9361z7035:**
- Integrated: Zynq-7035 + AD9361
- RF: 2x2 MIMO
- Carrier: ADRV1CRR-BOB or ADRV1CRR-FMC
- License: **Commercial required**
- Note: **Very low TX power in 5 GHz** - move closer for testing

**adrv9364z7020:**
- Integrated: Zynq-7020 + AD9364
- RF: 1x1 SISO
- Carrier: ADRV1CRR-BOB
- License: WebPack (free)

**Carriers:**
- **BOB** (Break-Out Board): Simple connector board, direct SMA
- **FMC**: Mezzanine format, can plug into other FPGA boards

#### zcu102_fmcs2

**High-End Zynq MPSoC Platform:**

**Specifications:**
- Board: Xilinx ZCU102 Evaluation Board
- SoC: Zynq UltraScale+ MPSoC XCZU9EG
- CPU: Quad-core ARM Cortex-A53 (64-bit) + Dual-core ARM Cortex-R5
- FMC: FMCOMMS2/3/4 (AD9361)
- License: **Commercial required**
- Architecture: **64-bit** (ARCH_BIT=64)

**Key Differences from Zynq-7000:**
- 64-bit ARM architecture
- More powerful CPU
- Larger FPGA fabric
- Advanced memory subsystem
- Requires ATF (ARM Trusted Firmware)

**Build Commands:**
```bash
export BOARD_NAME=zcu102_fmcs2

# Kernel preparation (64-bit)
cd $OPENWIFI_DIR/user_space
./prepare_kernel.sh /opt/Xilinx 64

# Driver compilation (64-bit)
cd $OPENWIFI_DIR/driver
./make_all.sh /opt/Xilinx 64

# Boot file generation
cd $OPENWIFI_DIR/user_space
./boot_bin_gen.sh /opt/Xilinx zcu102_fmcs2 $OPENWIFI_HW_IMG_DIR/boards/zcu102_fmcs2/sdk/system_top.xsa
```

**Device Tree:** Uses `system.dts` / `system.dtb` (not `devicetree.*`)

#### neptunesdr

**Community Low-Cost Board:**

**Specifications:**
- SoC: Zynq-7020
- RF: AD9361
- Status: Unofficial community support
- License: WebPack (free)

**Note:** May require additional community resources for troubleshooting.

### RF Frontend Configuration (AD9361)

All boards use Analog Devices AD936x series transceivers:
- **AD9361**: 2x2 MIMO, 70 MHz - 6 GHz
- **AD9363**: 1x1 SISO, 70 MHz - 6 GHz
- **AD9364**: 1x1 SISO, 70 MHz - 6 GHz
- **AD9371**: Advanced, higher bandwidth (zcu102_9371 only)

**AD9361 Initialization:**

RF initialization is done via scripts on the board:
- `/home/user/openwifi/user_space/rf_init.sh` - Standard init
- `/home/user/openwifi/user_space/rf_init_11n.sh` - 802.11n optimized

**FIR Filters:**

Custom FIR filters for different modes:
- `openwifi_ad9361_fir.ftr` - Standard filter
- `openwifi_ad9361_fir_tx_0MHz.ftr` - TX filter (legacy)
- `openwifi_ad9361_fir_tx_0MHz_11n.ftr` - TX filter for 11n
- `openwifi_ad9361_fir_tx_0MHz_11n_narrow1.ftr` - Narrow filter for 11n

**Frequency Range Operation:**

```bash
# 2.4 GHz band (ch 1-13)
# Configured by hostapd-openwifi.conf: channel=1

# 5 GHz band (ch 36-165)
# Configured by hostapd-openwifi.conf: channel=44

# Arbitrary frequency (advanced)
# See doc/README.md#let-openwifi-work-at-arbitrary-frequency
```

---

## Deployment Procedures

### Quick Deployment (Pre-built Image)

**Step 1: Download and Flash Image**
```bash
# Download
wget https://users.ugent.be/~xjiao/openwifi-1.5.0-shahecheng.img.xz
unxz openwifi-1.5.0-shahecheng.img.xz

# Flash (replace sdX with your SD card device!)
sudo dd bs=512 count=31116288 if=openwifi-1.5.0-shahecheng.img of=/dev/sdX status=progress
sync
```

**Step 2: Configure for Your Board**
```bash
# Mount SD card
sudo mkdir -p /mnt/sdcard_boot /mnt/sdcard_rootfs
sudo mount /dev/sdX1 /mnt/sdcard_boot
sudo mount /dev/sdX2 /mnt/sdcard_rootfs

# Copy board-specific files (replace antsdr with your board name)
export BOARD_NAME=antsdr
sudo cp /mnt/sdcard_boot/openwifi/$BOARD_NAME/* /mnt/sdcard_boot/

# Cleanup old files
sudo rm -rf /mnt/sdcard_rootfs/root/kernel_modules
sudo rm -rf /mnt/sdcard_rootfs/etc/network/interfaces.new

# Unmount
sudo umount /mnt/sdcard_boot /mnt/sdcard_rootfs
sync
```

**Step 3: First Boot Setup**
```bash
# On PC: Configure network
sudo ip addr add 192.168.10.1/24 dev ethX  # Replace ethX

# Insert SD card into board, power on, wait ~1 minute

# SSH to board (password: openwifi)
ssh root@192.168.10.122

# On board: Expand filesystem (if SD > 16GB)
raspi-config --expand-rootfs
reboot

# SSH again after reboot
ssh root@192.168.10.122

# Run one-time setup
cd ~/openwifi
./setup_once.sh
reboot
```

**Step 4: Start OpenWiFi AP**
```bash
# SSH to board
ssh root@192.168.10.122

# Configure routing on PC first (in another terminal):
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o wlanY -j MASQUERADE  # Replace wlanY
sudo ip route add 192.168.13.0/24 via 192.168.10.122 dev ethX

# On board: Start AP
cd ~/openwifi
./wgd.sh
./fosdem.sh

# Connect your WiFi device to SSID: openwifi
# Browse to: http://192.168.13.1
```

### Full Custom Deployment

**Step 1: Prepare Build Environment**
```bash
# Install dependencies
sudo apt-get install -y flex bison libssl-dev device-tree-compiler u-boot-tools
sudo apt-get install -y gcc-arm-linux-gnueabihf gcc-aarch64-linux-gnu

# Clone repositories
export WORKSPACE=$HOME/openwifi-workspace
mkdir -p $WORKSPACE && cd $WORKSPACE
git clone https://github.com/open-sdr/openwifi.git
git clone https://github.com/open-sdr/openwifi-hw-img.git

# Setup environment
export OPENWIFI_DIR=$WORKSPACE/openwifi
export OPENWIFI_HW_IMG_DIR=$WORKSPACE/openwifi-hw-img
export XILINX_DIR=/opt/Xilinx
export BOARD_NAME=antsdr  # Change to your board
```

**Step 2: Build Kernel**
```bash
cd $OPENWIFI_DIR/user_space

# For 32-bit boards (most boards)
./prepare_kernel.sh /opt/Xilinx 32

# For 64-bit boards (zcu102_fmcs2, zcu102_9371)
./prepare_kernel.sh /opt/Xilinx 64
```

**Step 3: Build Drivers**
```bash
cd $OPENWIFI_DIR/driver

# For 32-bit boards
./make_all.sh /opt/Xilinx 32

# For 64-bit boards
./make_all.sh /opt/Xilinx 64
```

**Step 4: Generate FPGA Bitstream**
```bash
cd $OPENWIFI_DIR/user_space
./boot_bin_gen.sh /opt/Xilinx $BOARD_NAME $OPENWIFI_HW_IMG_DIR/boards/$BOARD_NAME/sdk/system_top.xsa
```

**Step 5: Create SD Card Image**
```bash
# Download and flash ADI Kuiper base image
wget https://github.com/analogdevicesinc/adi-kuiper-gen/releases/download/13-December-2023-v0.10/image_2023-12-13-ADI-Kuiper-full.zip
unzip image_2023-12-13-ADI-Kuiper-full.zip
sudo dd bs=512 count=24182784 if=2023-12-13-ADI-Kuiper-full.img of=/dev/sdX status=progress
sync

# Mount SD card
sudo mkdir -p /mnt/sdcard
sudo mount /dev/sdX1 /mnt/sdcard/BOOT
sudo mount /dev/sdX2 /mnt/sdcard/rootfs

# Populate with openwifi
cd $OPENWIFI_DIR/user_space
./update_sdcard.sh $OPENWIFI_HW_IMG_DIR /opt/Xilinx /mnt/sdcard 0 "$BOARD_NAME"

# Configure network
sudo tee /mnt/sdcard/rootfs/etc/network/interfaces > /dev/null << 'EOF'
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
    address 192.168.10.122
    gateway 192.168.10.1
    netmask 255.255.255.0
EOF

# Copy udev rules
sudo cp $OPENWIFI_DIR/kernel_boot/10-network-device.rules /mnt/sdcard/rootfs/etc/udev/rules.d/

# Unmount
cd /
sudo umount /mnt/sdcard/BOOT
sudo umount /mnt/sdcard/rootfs
sync
```

**Step 6: First Boot and Configuration**
```bash
# Insert SD card, configure PC network, power on board
sudo ip addr add 192.168.10.1/24 dev ethX

# SSH (password: analog)
ssh root@192.168.10.122

# Change password
passwd  # Enter: openwifi

# Expand filesystem
raspi-config --expand-rootfs
reboot

# After reboot, setup internet routing on PC
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o wlanY -j MASQUERADE
sudo ip route add 192.168.13.0/24 via 192.168.10.122 dev ethX

# SSH again
ssh root@192.168.10.122

# Update packages
sudo apt-get update

# Install required packages
sudo apt-get install -y isc-dhcp-server hostapd tcpdump webfs iperf iperf3
sudo apt-get install -y libpcap-dev bridge-utils libnl-3-dev libnl-genl-3-dev

# Configure DHCP
sudo cp ~/openwifi/dhcpd.conf /etc/dhcp/dhcpd.conf

# Build on-board tools
cd ~/openwifi/sdrctl_src
make clean && make
cp sdrctl ../

cd ~/openwifi/side_ch_ctl_src
gcc -o side_ch_ctl side_ch_ctl.c
cp side_ch_ctl ../

cd ~/openwifi/inject_80211
make clean && make

# Make scripts executable
cd ~/openwifi
chmod +x *.sh

# Run one-time setup
./setup_once.sh
reboot
```

### Updating Components (Without SD Card Rebuild)

#### Update FPGA Only

```bash
# On PC: Generate new bitstream
cd $OPENWIFI_DIR/user_space
./boot_bin_gen.sh /opt/Xilinx $BOARD_NAME $OPENWIFI_HW_IMG_DIR/boards/$BOARD_NAME/sdk/system_top.xsa

# Transfer to board
scp system_top.bit.bin root@192.168.10.122:openwifi/

# On board: Reload FPGA
cd ~/openwifi
./wgd.sh  # Will automatically load new FPGA image if system_top.bit.bin exists
```

#### Update Driver Only

```bash
# On PC: Compile drivers
cd $OPENWIFI_DIR/driver
./make_all.sh /opt/Xilinx 32  # or 64

# Transfer to board
scp `find ./ -name \*.ko` root@192.168.10.122:openwifi/

# On board: Reload drivers
cd ~/openwifi
./wgd.sh  # Will load new .ko files
```

#### Update Both FPGA and Driver

```bash
# On PC: Create deployment package
cd $OPENWIFI_DIR/user_space
./drv_and_fpga_package_gen.sh $OPENWIFI_HW_IMG_DIR /opt/Xilinx $BOARD_NAME

# Transfer to board
scp drv_and_fpga.tar.gz root@192.168.10.122:~/

# On board: Load from package
cd ~
./openwifi/wgd.sh drv_and_fpga.tar.gz
```

#### Update Kernel

```bash
# On PC: Build kernel
cd $OPENWIFI_DIR/user_space
./prepare_kernel.sh /opt/Xilinx 32  # or 64

# Transfer kernel image
# For 32-bit:
scp $OPENWIFI_DIR/adi-linux/arch/arm/boot/uImage root@192.168.10.122:~/

# For 64-bit:
scp $OPENWIFI_DIR/adi-linux-64/arch/arm64/boot/Image root@192.168.10.122:~/

# On board: Update kernel on SD card
sudo mount /dev/mmcblk0p1 /mnt
sudo cp ~/uImage /mnt/  # or ~/Image for 64-bit
sudo umount /mnt
sync
reboot
```

---

## Configuration Examples

### Access Point (AP) Mode

**Standard 5 GHz AP:**

```bash
# On board
cd ~/openwifi
./wgd.sh
./fosdem.sh
```

**Configuration file:** `~/openwifi/hostapd-openwifi.conf`

```ini
interface=sdr0
driver=nl80211
ssid=openwifi
channel=44
hw_mode=a

# 802.11n support
ieee80211n=1
ht_capab=[SHORT-GI-20]

# Security (optional - default is open)
# wpa=2
# wpa_passphrase=your_password
# wpa_key_mgmt=WPA-PSK
# wpa_pairwise=CCMP

# QoS
wmm_enabled=1

# DHCP will give clients 192.168.13.x addresses
```

**2.4 GHz AP:**

```bash
cd ~/openwifi
./fosdem-11ag.sh
```

**Configuration:** `~/openwifi/hostapd-openwifi-11ag.conf`

```ini
interface=sdr0
driver=nl80211
ssid=openwifi
channel=1
hw_mode=g

# Force 802.11a/g (no 11n)
ieee80211n=0
wmm_enabled=1
```

**Custom AP Configuration:**

```bash
# Edit config file
vi ~/openwifi/hostapd-openwifi.conf

# Change SSID
ssid=MyCustomSSID

# Change channel
channel=36  # or 40, 44, 48, etc. for 5GHz
# channel=6  # for 2.4 GHz

# Add WPA2 security
wpa=2
wpa_passphrase=SecurePassword123
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP

# Start AP
./wgd.sh
hostapd hostapd-openwifi.conf
```

**Enable AMPDU (Aggregation):**

```bash
./wgd.sh 1  # "1" enables AMPDU aggregation
./fosdem.sh
```

### Client (Station) Mode

**Connect to Another AP:**

```bash
# On board: Edit connection config
vi ~/openwifi/wpa-connect.conf
```

```ini
network={
    ssid="TargetAPName"
    psk="TargetAPPassword"
    key_mgmt=WPA-PSK
}
```

```bash
# Connect
cd ~/openwifi
./wgd.sh
route del default gw 192.168.10.1
wpa_supplicant -i sdr0 -c wpa-connect.conf &
dhclient sdr0
```

**Monitor Connection:**
```bash
iw dev sdr0 link
iwconfig sdr0
```

### Ad-hoc Mode

**Node 1 (Creator):**

```bash
# On board 1
cd ~/openwifi
./wgd.sh
./sdr-ad-hoc-up.sh
```

**Node 2 (Joiner):**

```bash
# On board 2
cd ~/openwifi
./wgd.sh
./sdr-ad-hoc-join.sh
```

**Configuration:** `sdr-ad-hoc-up.sh`

```bash
#!/bin/bash
iw dev sdr0 set type ibss
ip link set sdr0 up
iw dev sdr0 ibss join openwifi-adhoc 5200 HT20 fixed-freq 02:12:34:56:78:9A
ip addr add 10.10.10.1/24 dev sdr0
```

**Test Connection:**

```bash
# On node 1
ping 10.10.10.2

# On node 2
ping 10.10.10.1
```

### Monitor Mode (Packet Capture)

**Basic Monitor:**

```bash
cd ~/openwifi
./wgd.sh
./monitor_ch.sh 44  # Monitor channel 44 (5GHz)
```

**Capture Packets:**

```bash
cd ~/openwifi
./wgd.sh
./monitor_ch.sh 1  # 2.4 GHz channel 1

# In another SSH session
tcpdump -i sdr0 -w capture.pcap

# Or with display
tcpdump -i sdr0 -v
```

**Packet Injection:**

```bash
cd ~/openwifi
./wgd.sh
./monitor_ch.sh 44

# Inject packets using inject_80211 tool
cd ~/openwifi/inject_80211
./inject_80211 -m n -r 6 -n 100  # Inject 100 packets at MCS 6
```

### CSI (Channel State Information) Collection

**Enable CSI Output:**

```bash
# On board
cd ~/openwifi
./wgd.sh
./fosdem.sh

# In another SSH session
cd ~/openwifi
./sdrctl dev sdr0 set reg xpu 1 1  # Enable CSI capture
```

**Collect CSI on PC:**

```bash
# On PC
cd $OPENWIFI_DIR/user_space
python3 csi_viewer.py

# May need to install dependencies first:
sudo apt-get install -y python3-numpy python3-matplotlib python3-tk
```

**See:** [CSI Application Note](https://github.com/open-sdr/openwifi/blob/master/doc/app_notes/csi.md)

### IQ Sample Capture

**Real-time IQ Streaming:**

```bash
# On board: Enable IQ capture
cd ~/openwifi
./wgd.sh
./fosdem.sh

# Configure IQ capture
./sdrctl dev sdr0 set reg xpu 2 1
```

**View on PC:**

```bash
# On PC
cd $OPENWIFI_DIR/user_space
python3 iq_viewer.py
```

**See:** [IQ Application Note](https://github.com/open-sdr/openwifi/blob/master/doc/app_notes/iq.md)

### Advanced RF Configuration

**Manual Frequency Setting:**

```bash
# On board
cd ~/openwifi

# Set center frequency (in Hz)
./sdrctl dev sdr0 set reg rf 0 2437000000  # 2.437 GHz (WiFi ch 6)
./sdrctl dev sdr0 set reg rf 0 5200000000  # 5.2 GHz (WiFi ch 40)
```

**TX Attenuation:**

```bash
# Set TX attenuation (0-89 dB)
./sdrctl dev sdr0 set reg drv_tx 2 30  # 30 dB attenuation
```

**RX Gain Control:**

```bash
# Automatic gain control
./set_rx_gain_auto.sh

# Manual gain
./set_rx_gain_manual.sh 70  # Gain value 0-127
```

**CCA Threshold:**

```bash
# Set Clear Channel Assessment threshold
./sdrctl dev sdr0 set reg drv_rx 0 70  # Threshold: -70 dBm
```

### Time Slicing (Advanced)

**Configure Network Slicing:**

```bash
# Configure slice 0 for specific MAC address
./sdrctl dev sdr0 set slice_idx 0
./sdrctl dev sdr0 set addr b94cb1c1  # Target MAC: 6c:fd:b9:4c:b1:c1
./sdrctl dev sdr0 set slice_total 49999  # 50 ms cycle
./sdrctl dev sdr0 set slice_start 10000  # Start at 10 ms
./sdrctl dev sdr0 set slice_end 39999    # End at 40 ms

# Activate all slices
./sdrctl dev sdr0 set slice_idx 4
```

**See:** [Time Slicing Tutorial](https://doc.ilabt.imec.be/ilabt/wilab/tutorials/openwifi.html#sdr-tx-time-slicing)

---

## Common Build Issues and Solutions

### Kernel Build Issues

**Issue 1: "fatal error: openssl/opensslv.h: No such file or directory"**

**Symptoms:**
```
  HOSTCC  scripts/extract-cert
scripts/extract-cert.c:21:10: fatal error: openssl/opensslv.h: No such file or directory
```

**Solution:**
```bash
sudo apt-get install -y libssl-dev
```

---

**Issue 2: "flex: not found" or "bison: command not found"**

**Symptoms:**
```
/bin/sh: 1: flex: not found
make[1]: *** [scripts/Makefile.lib:xxx] Error 127
```

**Solution:**
```bash
sudo apt-get install -y flex bison
```

---

**Issue 3: "dtc: not found" (device tree compiler)**

**Symptoms:**
```
DTC     arch/arm/boot/dts/zynq-zed-adv7511-ad9361-fmcomms2-3.dtb
/bin/sh: 1: dtc: not found
```

**Solution:**
```bash
sudo apt-get install -y device-tree-compiler
```

---

**Issue 4: Kernel build fails with "recipe for target 'uImage' failed"**

**Symptoms:**
```
make: *** [arch/arm/boot/uImage] Error 1
```

**Solution:**
```bash
sudo apt-get install -y u-boot-tools
```

---

**Issue 5: Patch fails to apply**

**Symptoms:**
```
error: patch failed: drivers/gpu/drm/adi_axi_hdmi/axi_hdmi_crtc.c:xxx
error: drivers/gpu/drm/adi_axi_hdmi/axi_hdmi_crtc.c: patch does not apply
```

**Solution:**
```bash
# Reset kernel repository
cd $OPENWIFI_DIR/adi-linux  # or adi-linux-64
git reset --hard
git clean -fdx

# Re-run prepare script
cd $OPENWIFI_DIR/user_space
./prepare_kernel.sh /opt/Xilinx 32  # or 64
```

---

**Issue 6: Wrong kernel version/commit**

**Solution:**
```bash
cd $OPENWIFI_DIR/adi-linux  # or adi-linux-64
git fetch
git checkout 2022_R2
git pull origin 2022_R2
git reset --hard c2f371e014f0704be4db02e5014c51ae99477c13
```

---

### Driver Build Issues

**Issue 7: "No such file or directory: linux/module.h"**

**Symptoms:**
```
fatal error: linux/module.h: No such file or directory
 #include <linux/module.h>
```

**Cause:** Kernel headers not prepared

**Solution:**
```bash
# Prepare kernel first
cd $OPENWIFI_DIR/user_space
./prepare_kernel.sh /opt/Xilinx 32  # or 64

# Then rebuild drivers
cd $OPENWIFI_DIR/driver
./make_all.sh /opt/Xilinx 32  # or 64
```

---

**Issue 8: Cross-compiler not found**

**Symptoms:**
```
make[1]: arm-linux-gnueabihf-gcc: Command not found
```

**Solution:**
```bash
# For 32-bit
sudo apt-get install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf

# For 64-bit
sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu

# Verify
arm-linux-gnueabihf-gcc --version
aarch64-linux-gnu-gcc --version
```

---

**Issue 9: "modpost: Symbol version dump ... is missing"**

**Symptoms:**
```
WARNING: Symbol version dump .../Module.symvers is missing
```

**Cause:** Kernel modules not built

**Solution:**
```bash
cd $OPENWIFI_DIR/adi-linux  # or adi-linux-64
source /opt/Xilinx/Vitis/2022.2/settings64.sh
export ARCH=arm  # or arm64
export CROSS_COMPILE=arm-linux-gnueabihf-  # or aarch64-linux-gnu-

make modules
make modules_prepare

# Then rebuild drivers
cd $OPENWIFI_DIR/driver
./make_all.sh /opt/Xilinx 32  # or 64
```

---

**Issue 10: "version magic mismatch" when loading module**

**Symptoms:**
```
insmod: ERROR: could not insert module sdr.ko: Invalid module format
dmesg: version magic '5.15.36-g... SMP preempt mod_unload ARMv7'
       should be '5.15.36-g... SMP preempt mod_unload ARMv7 p2v8'
```

**Cause:** Compiled modules don't match running kernel version

**Solution 1: Update kernel on SD card**
```bash
# Copy new kernel to SD card BOOT partition
cd $OPENWIFI_DIR
# For 32-bit:
sudo cp adi-linux/arch/arm/boot/uImage /path/to/sdcard/BOOT/

# For 64-bit:
sudo cp adi-linux-64/arch/arm64/boot/Image /path/to/sdcard/BOOT/

sync
# Reboot board
```

**Solution 2: Check kernel versions**
```bash
# On PC: Check compiled kernel version
cat $OPENWIFI_DIR/adi-linux/include/generated/utsrelease.h

# On board: Check running kernel version
uname -r
uname -v

# They must match exactly
```

---

### FPGA/Xilinx Tool Issues

**Issue 11: "xsct: command not found"**

**Symptoms:**
```
./build_boot_bin.sh: line 36: xsct: command not found
```

**Solution:**
```bash
# Source Xilinx environment
source /opt/Xilinx/Vitis/2022.2/settings64.sh

# Verify
which xsct
which bootgen
which vivado
```

---

**Issue 12: "bootgen: command not found"**

**Solution:**
```bash
source /opt/Xilinx/Vitis/2022.2/settings64.sh
which bootgen  # Should return /opt/Xilinx/Vitis/2022.2/bin/bootgen
```

---

**Issue 13: License error when building FPGA**

**Symptoms:**
```
ERROR: [Common 17-69] Command failed: This design contains one or more cells for which bitstream generation is not permitted
```

**Cause:** Board requires commercial Vivado license

**Solution:**

Check board license requirements:
- **Need Commercial License:** zc706_fmcs2, adrv9361z7035, zcu102_fmcs2, zcu102_9371
- **WebPack (Free):** All other boards

Obtain appropriate license from Xilinx or use a different board.

---

**Issue 14: .xsa file not found**

**Symptoms:**
```
system_top.xsa: File not found!
```

**Solution:**
```bash
# Verify openwifi-hw-img repository
cd $OPENWIFI_HW_IMG_DIR
git pull

# Check if file exists
ls boards/$BOARD_NAME/sdk/system_top.xsa

# If missing, download latest openwifi-hw-img
cd $WORKSPACE
rm -rf openwifi-hw-img
git clone https://github.com/open-sdr/openwifi-hw-img.git
```

---

**Issue 15: FSBL generation fails**

**Symptoms:**
```
xsct: Application exception encountered
```

**Solution:**
```bash
# Ensure Vitis (not Vitis_HLS) is installed
ls /opt/Xilinx/Vitis/2022.2/

# Reinstall or update Vitis if necessary
# Check Xilinx installation logs
```

---

### SD Card and Boot Issues

**Issue 16: Board doesn't boot (no output)**

**Troubleshooting Steps:**

1. **Check SD card boot mode:**
   - Verify board jumpers/switches set for SD boot
   - Consult board manual for correct boot mode settings

2. **Verify SD card partitions:**
   ```bash
   # On PC with SD card inserted
   sudo fdisk -l /dev/sdX
   # Should show:
   #   /dev/sdX1  (BOOT, FAT32)
   #   /dev/sdX2  (rootfs, ext4)
   ```

3. **Check BOOT partition contents:**
   ```bash
   sudo mount /dev/sdX1 /mnt
   ls /mnt/
   # Should contain: BOOT.BIN, devicetree.dtb (or system.dtb), uImage (or Image)
   ```

4. **Verify BOOT.BIN for correct board:**
   ```bash
   ls /mnt/openwifi/$BOARD_NAME/
   # Copy to root of BOOT partition
   sudo cp /mnt/openwifi/$BOARD_NAME/* /mnt/
   sudo umount /mnt
   ```

---

**Issue 17: Kernel panic on boot**

**Symptoms (via UART/serial console):**
```
Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(179,2)
```

**Cause:** Wrong device tree or rootfs partition issue

**Solution:**
```bash
# Ensure correct device tree for board
cd $OPENWIFI_DIR/kernel_boot/boards/$BOARD_NAME
dtc -I dts -O dtb -o devicetree.dtb devicetree.dts  # or system.dtb from system.dts

# Copy to SD card
sudo mount /dev/sdX1 /mnt
sudo cp devicetree.dtb /mnt/
sudo umount /mnt
```

---

**Issue 18: Cannot SSH to board (192.168.10.122 unreachable)**

**Troubleshooting:**

1. **Verify PC network configuration:**
   ```bash
   ip addr show ethX
   # Should have: 192.168.10.1/24

   # If not:
   sudo ip addr add 192.168.10.1/24 dev ethX
   sudo ip link set ethX up
   ```

2. **Check Ethernet cable:**
   - Try different cable
   - Check link LEDs on board and PC

3. **Verify board Ethernet configuration:**
   - Check `/etc/network/interfaces` on SD card rootfs:
   ```bash
   sudo mount /dev/sdX2 /mnt
   cat /mnt/etc/network/interfaces
   # Should have static IP 192.168.10.122
   ```

4. **Try UART/serial console:**
   - Connect USB-to-serial adapter
   - Use minicom/screen: `sudo minicom -D /dev/ttyUSB0 -b 115200`
   - Check boot messages and login

---

**Issue 19: "Permission denied" when flashing SD card**

**Symptoms:**
```
dd: failed to open '/dev/sdX': Permission denied
```

**Solution:**
```bash
# Use sudo
sudo dd bs=512 count=31116288 if=openwifi-xyz.img of=/dev/sdX status=progress

# Or add user to disk group (logout/login required)
sudo usermod -aG disk $USER
```

---

**Issue 20: SD card not detected or wrong device**

**Solution:**
```bash
# List all block devices
lsblk

# Identify SD card (look for size, removable)
# Common devices: /dev/sdb, /dev/mmcblk0

# IMPORTANT: Double-check before using dd!
# Wrong device = data loss!

# Verify it's the SD card:
sudo fdisk -l /dev/sdX
```

---

### Runtime/Driver Loading Issues

**Issue 21: "Invalid module format" when loading driver**

**Symptoms:**
```
insmod: ERROR: could not insert module sdr.ko: Invalid module format
```

**Solutions:**

1. **Check kernel version mismatch** (see Issue 10)

2. **Verify architecture match:**
   ```bash
   # On board
   uname -m
   # Should be: armv7l (32-bit) or aarch64 (64-bit)

   # On PC: Check compiled module
   file $OPENWIFI_DIR/driver/sdr.ko
   # Should match board architecture
   ```

3. **Rebuild drivers for correct architecture:**
   ```bash
   cd $OPENWIFI_DIR/driver
   ./make_all.sh /opt/Xilinx 32  # or 64 for ZynqMP
   scp `find ./ -name \*.ko` root@192.168.10.122:openwifi/
   ```

---

**Issue 22: "Unknown symbol" error when loading module**

**Symptoms:**
```
insmod: ERROR: could not insert module xpu.ko: Unknown symbol in module
dmesg: xpu: Unknown symbol ieee80211_... (err -2)
```

**Cause:** Missing prerequisite modules or mac80211 not loaded

**Solution:**
```bash
# On board: Load modules in correct order
sudo modprobe mac80211
sudo insmod xilinx_dma.ko
sudo insmod side_ch.ko
sudo insmod openofdm_tx.ko
sudo insmod openofdm_rx.ko
sudo insmod tx_intf.ko
sudo insmod rx_intf.ko
sudo insmod xpu.ko
sudo insmod sdr.ko

# Or use wgd.sh:
./wgd.sh
```

---

**Issue 23: FPGA loading fails**

**Symptoms:**
```
Error: Failed to load FPGA bitstream
```

**Solutions:**

1. **Check FPGA bitstream file:**
   ```bash
   # On board
   ls -lh ~/openwifi/system_top.bit.bin
   # Should be ~3-5 MB

   # If missing or too small, regenerate:
   # On PC:
   cd $OPENWIFI_DIR/user_space
   ./boot_bin_gen.sh /opt/Xilinx $BOARD_NAME $OPENWIFI_HW_IMG_DIR/boards/$BOARD_NAME/sdk/system_top.xsa
   scp system_top.bit.bin root@192.168.10.122:openwifi/
   ```

2. **Manually load FPGA:**
   ```bash
   # On board
   cd ~/openwifi
   ./load_fpga_img.sh system_top.bit.bin
   ```

3. **Check FPGA manager:**
   ```bash
   # On board
   cat /sys/class/fpga_manager/fpga0/state
   # Should be: "operating" after successful load
   ```

---

**Issue 24: "No such device: sdr0" after loading drivers**

**Symptoms:**
```
ifconfig sdr0
sdr0: error fetching interface information: Device not found
```

**Troubleshooting:**

1. **Check driver loaded:**
   ```bash
   lsmod | grep sdr
   # Should show: sdr, with other modules
   ```

2. **Check kernel logs:**
   ```bash
   dmesg | tail -50
   # Look for openwifi/sdr related messages
   ```

3. **Common issues:**
   - FPGA not loaded correctly
   - Driver initialization failed
   - Wrong FPGA bitstream for driver version

4. **Solution:**
   ```bash
   # Reload everything
   cd ~/openwifi
   ./wgd.sh

   # Check interface
   ip link show sdr0
   ```

---

**Issue 25: Viterbi decoder halts after ~2 hours**

**Symptoms:**
- WiFi stops working after ~2 hours
- `./sdrctl dev sdr0 get reg rx 20` returns same value repeatedly

**Cause:** Xilinx Evaluation License limitation on Viterbi decoder IP

**Solution:**

**Option 1: Reload FPGA (Quick)**
```bash
cd ~/openwifi
./load_fpga_img.sh system_top.bit.bin
./wgd.sh
./fosdem.sh
```

**Option 2: Power cycle board**

**Long-term:** Obtain proper Xilinx license or use alternate FEC implementation

---

### Performance Issues

**Issue 26: Low throughput (< 10 Mbps)**

**Troubleshooting:**

1. **Check AMPDU aggregation:**
   ```bash
   # Enable aggregation
   cd ~/openwifi
   ./wgd.sh 1  # "1" enables AMPDU
   ./fosdem.sh
   ```

2. **Verify 802.11n enabled:**
   ```bash
   cat ~/openwifi/hostapd-openwifi.conf
   # Should have:
   # ieee80211n=1
   # ht_capab=[SHORT-GI-20]
   ```

3. **Check client capabilities:**
   - Ensure client supports 802.11n
   - Check client's negotiated rate: `iw dev wlanX station dump`

4. **Optimize RF settings:**
   ```bash
   # On board
   cd ~/openwifi
   ./set_rx_gain_auto.sh
   ./sdrctl dev sdr0 get reg drv_tx 2  # Check TX attenuation (lower = higher power)
   ```

---

**Issue 27: High packet loss or errors**

**Solutions:**

1. **Check signal strength:**
   ```bash
   ./rssi_openwifi_show.sh
   ./rx_stat_show.sh
   ```

2. **Adjust CCA threshold:**
   ```bash
   # Lower threshold = more sensitive (may increase false detections)
   ./sdrctl dev sdr0 set reg drv_rx 0 70  # -70 dBm
   ```

3. **Use cable connection for testing:**
   - Connect TX to RX via attenuator (30 dB minimum)
   - Eliminates multipath/interference issues

4. **Check for interference:**
   ```bash
   # Scan for other APs
   ./wgd.sh
   ./monitor_ch.sh 44
   iw dev sdr0 scan
   ```

---

### Miscellaneous Issues

**Issue 28: Cannot access internet from WiFi clients**

**Cause:** Routing not configured on PC

**Solution:**

```bash
# On PC (host computer):
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o wlanY -j MASQUERADE
sudo ip route add 192.168.13.0/24 via 192.168.10.122 dev ethX

# Make persistent (optional):
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# Verify:
sysctl net.ipv4.ip_forward  # Should be 1
iptables -t nat -L -v  # Should show MASQUERADE rule
```

---

**Issue 29: sdrctl command not found**

**Solution:**

```bash
# On board: Build sdrctl
cd ~/openwifi/sdrctl_src
make clean
make
cp sdrctl ../

# Verify
~/openwifi/sdrctl
# Should show usage
```

---

**Issue 30: Time slicing not working**

**Troubleshooting:**

1. **Verify slice configuration:**
   ```bash
   ./sdrctl dev sdr0 set slice_idx 0
   ./sdrctl dev sdr0 get slice_total
   ./sdrctl dev sdr0 get slice_start
   ./sdrctl dev sdr0 get slice_end
   ```

2. **Ensure slice synchronization:**
   ```bash
   # After configuring all slices, synchronize:
   ./sdrctl dev sdr0 set slice_idx 4
   ```

3. **Check TSF timer:**
   ```bash
   ./sdrctl dev sdr0 get tsf
   # Should increment over time
   ```

---

## Advanced Topics

### Custom Kernel Configuration

If you need to modify kernel configuration:

```bash
cd $OPENWIFI_DIR/adi-linux  # or adi-linux-64
source /opt/Xilinx/Vitis/2022.2/settings64.sh
export ARCH=arm  # or arm64
export CROSS_COMPILE=arm-linux-gnueabihf-  # or aarch64-linux-gnu-

# Menuconfig for interactive configuration
make menuconfig

# Save configuration
cp .config $OPENWIFI_DIR/kernel_boot/kernel_config  # or kernel_config_zynqmp

# Build
make -j12 uImage UIMAGE_LOADADDR=0x8000  # or: make Image for 64-bit
make modules
```

### Building Custom FPGA Design

**Prerequisites:**
- openwifi-hw repository
- Vivado 2022.2
- Understanding of Verilog and Vivado Block Design

**Workflow:**

1. **Clone FPGA source:**
   ```bash
   cd $WORKSPACE
   git clone https://github.com/open-sdr/openwifi-hw.git
   cd openwifi-hw
   ```

2. **Modify IP cores:**
   ```bash
   cd ip/openofdm_tx  # or any IP
   # Edit Verilog files in src/
   vim src/openofdm_tx.v

   # Re-package IP
   vivado -mode batch -source package_ip.tcl
   ```

3. **Open board project:**
   ```bash
   cd $WORKSPACE/openwifi-hw/boards/$BOARD_NAME
   source /opt/Xilinx/Vivado/2022.2/settings64.sh
   vivado openwifi.xpr &
   ```

4. **Build in Vivado:**
   - Flow → Generate Bitstream
   - File → Export → Export Hardware (include bitstream)
   - Save as: `system_top.xsa`

5. **Use custom bitstream:**
   ```bash
   cd $OPENWIFI_DIR/user_space
   ./boot_bin_gen.sh /opt/Xilinx $BOARD_NAME /path/to/custom/system_top.xsa
   scp system_top.bit.bin root@192.168.10.122:openwifi/
   ```

### Creating Custom Board Port

To port openwifi to a new Zynq-based board:

1. **Hardware Requirements:**
   - Zynq-7000 or Zynq MPSoC SoC
   - AD936x RF transceiver
   - Sufficient FPGA resources (see resource utilization table)
   - FMC or direct connection to AD936x

2. **FPGA Design:**
   - Start from similar board (e.g., zed_fmcs2 for Zynq-7020)
   - Create Vivado project for new board
   - Adjust pin constraints for your board
   - Verify clock/reset topology
   - Build and test bitstream

3. **Software Components:**

   **Create board directory:**
   ```bash
   mkdir $OPENWIFI_DIR/kernel_boot/boards/my_board
   ```

   **Device Tree:**
   - Copy from similar board
   - Adjust memory map (check Vivado address editor)
   - Update peripheral addresses
   - Adjust AD9361 configuration

   **U-Boot:**
   - Build U-Boot for your board (if needed)
   - Or use existing from similar board

   **BOOT.BIN:**
   - Generate using boot_bin_gen.sh with your .xsa

4. **Testing:**
   - Test FPGA load
   - Test driver load
   - Test basic RF functionality
   - Full WiFi testing

See: [Porting Guide in main README](https://github.com/open-sdr/openwifi/blob/master/README.md#Porting-guide)

### Debugging Techniques

**Enable Driver Debug Messages:**

```bash
# On board
cd ~/openwifi

# Set debug level (higher = more verbose)
./sdrctl dev sdr0 set reg drv_rx 7 3
# Bit 0: General debug
# Bit 1: Rx debug
# Bit 2: Tx debug

# View messages
dmesg -w
```

**FPGA Register Access:**

```bash
# Read FPGA register
./sdrctl dev sdr0 get reg xpu 10  # Read XPU register 10

# Write FPGA register
./sdrctl dev sdr0 set reg xpu 10 0x1234

# Dump important registers
./rx_stat_show.sh
./tx_stat_show.sh
```

**Analyze Packet Capture:**

```bash
# Capture on monitor interface
./wgd.sh
./monitor_ch.sh 44
tcpdump -i sdr0 -w capture.pcap

# View on PC with Wireshark
scp root@192.168.10.122:capture.pcap .
wireshark capture.pcap
```

**Serial Console Debug:**

Connect UART to see early boot messages and kernel panics:

```bash
# On PC
sudo minicom -D /dev/ttyUSB0 -b 115200
# Or
sudo screen /dev/ttyUSB0 115200
```

### Performance Tuning

**CPU Governor:**
```bash
# On board: Set performance governor
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

**Interrupt Affinity:**
```bash
# Bind interrupts to specific CPU
# Check IRQ number
cat /proc/interrupts | grep openwifi

# Set affinity (example: bind to CPU 0)
echo 1 > /proc/irq/IRQ_NUMBER/smp_affinity
```

**DMA Buffer Tuning:**

Edit driver source `sdr.c` and adjust:
```c
#define TX_BD_NUM_TOTAL 64  // Increase for higher throughput
#define RX_BD_NUM_TOTAL 64
```

Then rebuild driver.

### Multi-Board Setup

For experiments with multiple SDRs:

**Board 1 (AP):**
```bash
# Set unique IP
vi /etc/network/interfaces
# address 192.168.10.101

./wgd.sh
./fosdem.sh
```

**Board 2 (Client or Monitor):**
```bash
# Set unique IP
vi /etc/network/interfaces
# address 192.168.10.102

./wgd.sh
./monitor_ch.sh 44
```

**PC Network:**
```bash
# Add route to both boards
sudo ip route add 192.168.10.101/32 dev ethX
sudo ip route add 192.168.10.102/32 dev ethX
```

---

## Conclusion

This guide covers the complete build and configuration process for OpenWiFi. For additional information:

- **Main README:** [https://github.com/open-sdr/openwifi/blob/master/README.md](https://github.com/open-sdr/openwifi/blob/master/README.md)
- **Project Documentation:** [/home/user/openwifi/doc/README.md](/home/user/openwifi/doc/README.md)
- **Application Notes:** [/home/user/openwifi/doc/app_notes/README.md](/home/user/openwifi/doc/app_notes/README.md)
- **Mailing List:** [https://lists.ugent.be/wws/subscribe/openwifi](https://lists.ugent.be/wws/subscribe/openwifi)
- **Publications:** [/home/user/openwifi/doc/publications.md](/home/user/openwifi/doc/publications.md)

### Key References

**Scripts:**
- Kernel preparation: `/home/user/openwifi/user_space/prepare_kernel.sh`
- Driver compilation: `/home/user/openwifi/driver/make_all.sh`
- Boot generation: `/home/user/openwifi/user_space/boot_bin_gen.sh`
- SD card update: `/home/user/openwifi/user_space/update_sdcard.sh`
- Driver/FPGA package: `/home/user/openwifi/user_space/drv_and_fpga_package_gen.sh`

**Directories:**
- Kernel configs: `/home/user/openwifi/kernel_boot/`
- Board files: `/home/user/openwifi/kernel_boot/boards/`
- User space: `/home/user/openwifi/user_space/`
- Drivers: `/home/user/openwifi/driver/`
- Documentation: `/home/user/openwifi/doc/`

### Quick Reference Commands

**Build Everything:**
```bash
# Setup environment
export OPENWIFI_DIR=$HOME/openwifi-workspace/openwifi
export OPENWIFI_HW_IMG_DIR=$HOME/openwifi-workspace/openwifi-hw-img
export XILINX_DIR=/opt/Xilinx
export BOARD_NAME=antsdr  # Your board

# Prepare kernel (one-time)
cd $OPENWIFI_DIR/user_space
./prepare_kernel.sh $XILINX_DIR 32  # or 64

# Build drivers
cd $OPENWIFI_DIR/driver
./make_all.sh $XILINX_DIR 32  # or 64

# Generate boot files and bitstream
cd $OPENWIFI_DIR/user_space
./boot_bin_gen.sh $XILINX_DIR $BOARD_NAME $OPENWIFI_HW_IMG_DIR/boards/$BOARD_NAME/sdk/system_top.xsa

# Transfer to board
scp system_top.bit.bin root@192.168.10.122:openwifi/
cd $OPENWIFI_DIR/driver
scp `find ./ -name \*.ko` root@192.168.10.122:openwifi/
```

**Quick Start on Board:**
```bash
cd ~/openwifi
./wgd.sh      # Load drivers and FPGA
./fosdem.sh   # Start AP
```

---

**Document Version:** 1.0
**Created:** 2025-11-21
**Author:** OpenWiFi Community
**License:** AGPL-3.0-or-later

For questions or issues, please consult the mailing list or GitHub issues page.
