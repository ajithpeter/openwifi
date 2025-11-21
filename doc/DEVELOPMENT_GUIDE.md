# OpenWiFi Development Guide

**Comprehensive Developer Documentation**
**Version:** 1.5.0+
**Last Updated:** 2025-11-21

---

## Table of Contents

1. [Development Environment Setup](#development-environment-setup)
2. [Code Organization](#code-organization)
3. [Development Workflows](#development-workflows)
4. [Driver Development](#driver-development)
5. [FPGA Integration](#fpga-integration)
6. [Testing Procedures](#testing-procedures)
7. [Debugging Techniques](#debugging-techniques)
8. [Adding New Features](#adding-new-features)
9. [Performance Optimization](#performance-optimization)
10. [Contributing](#contributing)

---

## Development Environment Setup

### Host Machine Requirements

**Minimum Specifications:**
- CPU: 4 cores, 8+ threads recommended
- RAM: 16 GB (32 GB for FPGA builds)
- Disk: 100 GB free space
- OS: Ubuntu 18.04/20.04/22.04 LTS

### Software Dependencies

**Essential Tools:**

```bash
# Build essentials
sudo apt-get update
sudo apt-get install -y build-essential git cmake

# Kernel development
sudo apt-get install -y libncurses-dev flex bison libssl-dev
sudo apt-get install -y device-tree-compiler u-boot-tools

# Cross-compilation toolchains
sudo apt-get install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf  # 32-bit
sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu      # 64-bit

# Libraries
sudo apt-get install -y libnl-3-dev libnl-genl-3-dev libpcap-dev

# Python tools
sudo apt-get install -y python3-pip python3-numpy python3-matplotlib
pip3 install scipy

# Documentation
sudo apt-get install -y doxygen graphviz
```

**Xilinx Tools (for FPGA development):**

```bash
# Download from Xilinx website:
# - Vivado 2021.1 or 2022.2 (Design Suite)
# - Vitis 2022.2 (for SDK tools)

# Installation path (standard):
export XILINX_DIR=/opt/Xilinx

# Add to ~/.bashrc
echo 'export XILINX_DIR=/opt/Xilinx' >> ~/.bashrc
echo 'source $XILINX_DIR/Vivado/2021.1/settings64.sh' >> ~/.bashrc
```

### Repository Setup

**Clone with submodules:**

```bash
# Main repository
git clone https://github.com/open-sdr/openwifi.git
cd openwifi

# Initialize submodules (kernel sources)
git submodule init
git submodule update

# FPGA hardware (optional, for FPGA development)
cd ..
git clone https://github.com/open-sdr/openwifi-hw.git

# Pre-built FPGA images
git clone https://github.com/open-sdr/openwifi-hw-img.git
```

**Environment Variables:**

```bash
# Add to ~/.bashrc or create setup script
export OPENWIFI_DIR=$HOME/openwifi
export OPENWIFI_HW_DIR=$HOME/openwifi-hw
export OPENWIFI_HW_IMG_DIR=$HOME/openwifi-hw-img
export XILINX_DIR=/opt/Xilinx

# Target board
export BOARD_NAME=adrv9364z7020  # or your board

# Architecture
export ARCH_BIT=32  # 32 for Zynq-7000, 64 for Zynq MPSoC
```

### Development Board Setup

**Network Configuration:**

```bash
# Host machine: 192.168.10.1
# Target board: 192.168.10.122 (default)

# Configure host interface
sudo ip addr add 192.168.10.1/24 dev ethX
sudo ip link set ethX up

# Test connection
ping 192.168.10.122
```

**SSH Access:**

```bash
# Default credentials
# Username: root
# Password: openwifi

# Set up SSH keys (recommended)
ssh-copy-id root@192.168.10.122

# Create SSH config (~/.ssh/config)
cat >> ~/.ssh/config << EOF
Host openwifi
    HostName 192.168.10.122
    User root
    IdentityFile ~/.ssh/id_rsa
EOF

# Now connect easily
ssh openwifi
```

---

## Code Organization

### Repository Structure

```
openwifi/
│
├── driver/                    # Linux kernel drivers
│   ├── sdr.c                 # Main driver (2760 lines)
│   ├── sdr.h                 # Data structures and definitions
│   ├── hw_def.h              # FPGA register definitions
│   ├── sysfs_intf.c          # Sysfs interface
│   ├── sdrctl_intf.c         # Netlink testmode interface
│   ├── Makefile              # Build system
│   ├── make_all.sh           # Build script
│   │
│   ├── tx_intf/              # TX interface driver
│   │   ├── tx_intf.c
│   │   ├── Makefile
│   │
│   ├── rx_intf/              # RX interface driver
│   ├── xpu/                  # MAC controller driver
│   ├── openofdm_tx/          # OFDM TX driver
│   ├── openofdm_rx/          # OFDM RX driver
│   ├── side_ch/              # Side channel driver
│   └── xilinx_dma/           # DMA engine driver
│
├── kernel_boot/              # Boot files and configs
│   ├── kernel_config         # Kernel configuration
│   ├── boards/               # Board-specific files
│   └── patches/              # Kernel patches
│
├── user_space/               # User-space tools
│   ├── sdrctl_src/           # Control utility
│   ├── inject_80211/         # Packet injection
│   ├── side_ch_ctl_src/      # CSI/IQ capture
│   ├── scripts/              # 60+ configuration scripts
│   └── webserver/            # Web interface
│
└── doc/                      # Documentation
    ├── ARCHITECTURE.md
    ├── PHY_MAC_GUIDE.md
    ├── BUILD_GUIDE.md
    └── ...
```

### Coding Standards

**Linux Kernel Style:**

```c
// Indentation: Tabs (8 spaces)
// Line length: 80 characters preferred, 100 maximum

// Function naming
static int openwifi_function_name(struct device *dev)
{
    // Local variables
    int ret = 0;
    u32 value;

    // Logic with clear comments
    value = reg_read(REGISTER_ADDR);
    if (value & ERROR_BIT) {
        pr_err("Error occurred\n");
        return -EIO;
    }

    return ret;
}

// Use kernel macros
#define DRIVER_NAME "openwifi"
#define DRIVER_VERSION "1.5.0"
```

**Logging:**

```c
// Use appropriate log levels
pr_debug("Debug message\n");    // Development
pr_info("Info message\n");      // General information
pr_warn("Warning message\n");   // Non-critical issues
pr_err("Error message\n");      // Errors

// With device context
dev_dbg(&pdev->dev, "Debug with device\n");
dev_info(&pdev->dev, "Info with device\n");

// Driver-specific prefix
#define sdr_compatible_str "openwifi"
printk("%s: message\n", sdr_compatible_str);
```

**Error Handling:**

```c
// Always check return values
ret = function_call();
if (ret < 0) {
    pr_err("function_call failed: %d\n", ret);
    goto error_cleanup;
}

// Use goto for cleanup
error_cleanup:
    cleanup_resources();
    return ret;
```

---

## Development Workflows

### Typical Development Cycle

```
┌──────────────────────────────────────────────────────┐
│                                                      │
│  1. Modify Code on Host                             │
│     └─> Edit driver/*.c files                       │
│                                                      │
├──────────────────────────────────────────────────────┤
│                                                      │
│  2. Compile                                          │
│     └─> ./driver/make_all.sh $XILINX_DIR 32         │
│                                                      │
├──────────────────────────────────────────────────────┤
│                                                      │
│  3. Transfer to Board                                │
│     └─> scp *.ko root@192.168.10.122:openwifi/      │
│                                                      │
├──────────────────────────────────────────────────────┤
│                                                      │
│  4. Test on Board                                    │
│     └─> SSH to board, reload drivers                │
│                                                      │
├──────────────────────────────────────────────────────┤
│                                                      │
│  5. Debug and Iterate                                │
│     └─> Check dmesg, test functionality             │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### Quick Build and Deploy Script

Create `~/dev_deploy.sh`:

```bash
#!/bin/bash

# Configuration
BOARD_IP="192.168.10.122"
XILINX_DIR="/opt/Xilinx"
ARCH_BIT=32

# Build
echo "Building drivers..."
cd ~/openwifi/driver
./make_all.sh $XILINX_DIR $ARCH_BIT

if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

# Transfer
echo "Transferring to board..."
scp `find ./ -name \*.ko` root@$BOARD_IP:openwifi/

# Reload on board
echo "Reloading drivers..."
ssh root@$BOARD_IP "cd openwifi && ./wgd.sh"

echo "Deployment complete!"
```

### Rapid Iteration Workflow

**For driver-only changes:**

```bash
# On host: build and transfer in one command
cd ~/openwifi/driver && \
./make_all.sh /opt/Xilinx 32 && \
scp sdr.ko root@192.168.10.122:openwifi/

# On board: quick reload
ssh openwifi "cd openwifi && rmmod sdr && insmod sdr.ko"
```

**For FPGA changes:**

```bash
# Transfer bitstream
scp system_top.bit.bin root@192.168.10.122:openwifi/

# On board: reload FPGA
ssh openwifi "cd openwifi && ./load_fpga_img.sh"
```

---

## Driver Development

### Adding a New Register

**1. Define in hw_def.h:**

```c
// File: /home/user/openwifi/driver/hw_def.h

// Add to appropriate section (e.g., XPU registers)
#define XPU_REG_MY_NEW_REG_ADDR  (63*4)  // Next available offset
```

**2. Create accessor in component driver:**

```c
// File: /home/user/openwifi/driver/xpu/xpu.c

static inline u32 XPU_REG_MY_NEW_REG_read(void)
{
    return reg_read(XPU_REG_MY_NEW_REG_ADDR);
}

static inline void XPU_REG_MY_NEW_REG_write(u32 value)
{
    reg_write(XPU_REG_MY_NEW_REG_ADDR, value);
}

// Export via API structure
struct xpu_driver_api xpu_driver_api_inst = {
    // ... existing functions
    .XPU_REG_MY_NEW_REG_read = XPU_REG_MY_NEW_REG_read,
    .XPU_REG_MY_NEW_REG_write = XPU_REG_MY_NEW_REG_write,
};
```

**3. Use in main driver:**

```c
// File: /home/user/openwifi/driver/sdr.c

// Read register
u32 value = xpu_api->XPU_REG_MY_NEW_REG_read();

// Write register
xpu_api->XPU_REG_MY_NEW_REG_write(0x12345);
```

**4. Expose via sdrctl (optional):**

```c
// File: /home/user/openwifi/driver/sdrctl_intf.c

// Add to testmode command handler
case OPENWIFI_CMD_MY_FEATURE:
    value = xpu_api->XPU_REG_MY_NEW_REG_read();
    // Send response via netlink
    break;
```

### Adding a New Sysfs Attribute

**Example: Add TX power readout**

```c
// File: /home/user/openwifi/driver/sysfs_intf.c

static ssize_t tx_power_show(struct device *dev,
                              struct device_attribute *attr, char *buf)
{
    struct openwifi_priv *priv = dev_get_drvdata(dev);
    u32 tx_atten_mdb;

    ad9361_get_tx_atten(priv->ad9361_phy, 1, &tx_atten_mdb);

    return sprintf(buf, "%d milli-dB\n", tx_atten_mdb);
}

static DEVICE_ATTR_RO(tx_power);

// Add to attribute group
static struct attribute *openwifi_attrs[] = {
    // ... existing attributes
    &dev_attr_tx_power.attr,
    NULL,
};

static const struct attribute_group openwifi_attr_group = {
    .attrs = openwifi_attrs,
};
```

**Access:**

```bash
cat /sys/devices/platform/fpga-axi@0/fpga-axi@0:sdr/tx_power
```

### Adding a New Statistics Counter

**1. Define in sdr.h:**

```c
// File: /home/user/openwifi/driver/sdr.h

struct openwifi_stat {
    // ... existing counters
    u64 my_new_counter;
};
```

**2. Increment in code:**

```c
// File: /home/user/openwifi/driver/sdr.c

// In appropriate location
priv->stat.my_new_counter++;
```

**3. Expose via sysfs:**

```c
// File: /home/user/openwifi/driver/sysfs_intf.c

static ssize_t my_counter_show(struct device *dev,
                                struct device_attribute *attr, char *buf)
{
    struct openwifi_priv *priv = dev_get_drvdata(dev);
    return sprintf(buf, "%llu\n", priv->stat.my_new_counter);
}

static DEVICE_ATTR_RO(my_counter);
```

### Handling Interrupts

**Register new interrupt:**

```c
// File: /home/user/openwifi/driver/sdr.c (in probe function)

int irq_my_feature;

// Parse from device tree
irq_my_feature = irq_of_parse_and_map(pdev->dev.of_node, 3);  // IRQ index 3

// Register handler
ret = request_irq(irq_my_feature, my_interrupt_handler,
                  IRQF_SHARED, "sdr,my_feature", dev);
if (ret) {
    pr_err("Failed to request IRQ %d\n", irq_my_feature);
    return ret;
}
```

**Interrupt handler:**

```c
static irqreturn_t my_interrupt_handler(int irq, void *dev_id)
{
    struct ieee80211_hw *dev = dev_id;
    struct openwifi_priv *priv = dev->priv;

    // Read interrupt status
    u32 status = my_module_api->STATUS_REG_read();

    // Handle interrupt
    if (status & ERROR_FLAG) {
        pr_err("Error detected\n");
        priv->stat.error_count++;
    }

    // Clear interrupt
    my_module_api->STATUS_REG_write(status);

    return IRQ_HANDLED;
}
```

---

## FPGA Integration

### FPGA-Driver Interface

**Register Interface (AXI-Lite):**

```c
// Each FPGA module has memory-mapped registers
// Driver accesses via ioread32()/iowrite32()

// Example: Reading FPGA status
u32 status = tx_intf_api->TX_INTF_REG_STATUS_read();

// Example: Writing configuration
tx_intf_api->TX_INTF_REG_CONFIG_write(config_value);
```

**DMA Interface (AXI-DMA):**

```c
// TX: Scatter-gather DMA (driver → FPGA)
struct scatterlist sg;
sg_init_table(&sg, 1);
sg_dma_address(&sg) = dma_addr;
sg_dma_len(&sg) = length;

txd = dmaengine_prep_slave_sg(tx_chan, &sg, 1, DMA_MEM_TO_DEV, flags);
tx_cookie = dmaengine_submit(txd);
dma_async_issue_pending(tx_chan);

// RX: Cyclic DMA (FPGA → driver)
rxd = dmaengine_prep_dma_cyclic(rx_chan, dma_addr, total_size,
                                 period_size, DMA_DEV_TO_MEM, flags);
rx_cookie = dmaengine_submit(rxd);
dma_async_issue_pending(rx_chan);
```

### Working with FPGA Hardware Repository

**Location:** https://github.com/open-sdr/openwifi-hw

**Structure:**

```
openwifi-hw/
├── ip/                      # Custom IP cores
│   ├── openofdm_rx/        # OFDM receiver (Verilog)
│   ├── openofdm_tx/        # OFDM transmitter (Verilog)
│   ├── xpu/                # MAC controller (Verilog)
│   ├── tx_intf/            # TX interface (Verilog)
│   └── rx_intf/            # RX interface (Verilog)
│
├── boards/                  # Board-specific projects
│   ├── zc706_fmcs2/
│   ├── adrv9364z7020/
│   └── ...
│
└── README.md
```

**Modifying FPGA Design:**

1. **Open project in Vivado:**
```bash
cd openwifi-hw/boards/adrv9364z7020
vivado system_top.xpr
```

2. **Make changes:**
   - Modify IP cores in `ip/` directory
   - Update block design
   - Adjust timing constraints

3. **Generate bitstream:**
   - Synthesis → Implementation → Generate Bitstream
   - Export XSA file: File → Export → Export Hardware

4. **Create BOOT.BIN:**
```bash
cd ~/openwifi/user_space
./boot_bin_gen.sh /opt/Xilinx adrv9364z7020 \
    ~/openwifi-hw/boards/adrv9364z7020/sdk/system_top.xsa
```

### Adding a New FPGA Register

**In Verilog (IP core):**

```verilog
// File: openwifi-hw/ip/my_module/src/my_module.v

// AXI-Lite slave registers
reg [31:0] my_new_register;

// Read logic
always @(*) begin
    case (axi_araddr[7:2])
        // ... existing registers
        6'd63: axi_rdata = my_new_register;
        default: axi_rdata = 32'h0;
    endcase
end

// Write logic
always @(posedge clk) begin
    if (axi_wvalid && axi_wready) begin
        case (axi_awaddr[7:2])
            // ... existing registers
            6'd63: my_new_register <= axi_wdata;
        endcase
    end
end
```

**In Driver (C):**

```c
// File: driver/hw_def.h
#define MY_MODULE_REG_NEW_ADDR (63*4)

// File: driver/my_module/my_module.c
static inline u32 MY_MODULE_REG_NEW_read(void) {
    return reg_read(MY_MODULE_REG_NEW_ADDR);
}
```

---

## Testing Procedures

### Unit Testing

**Test individual functions:**

```c
// Create test module (driver/test_module.c)

static int __init test_module_init(void)
{
    // Test register access
    u32 value = xpu_api->XPU_REG_TSF_RUNTIME_VAL_LOW_read();
    pr_info("TSF low: 0x%08x\n", value);

    // Test calculations
    int rssi_dbm = rssi_half_db_to_rssi_dbm(180, 153);
    pr_info("RSSI: %d dBm\n", rssi_dbm);

    return 0;
}

module_init(test_module_init);
```

**Compile and load:**

```bash
cd driver
make -C $KERNEL_DIR M=$(pwd) modules
scp test_module.ko root@192.168.10.122:
ssh openwifi "insmod test_module.ko && dmesg | tail"
```

### Integration Testing

**Test TX path:**

```bash
# On board
cd /root/openwifi

# Start AP mode
./fosdem.sh

# Connect client and test
# From another device:
# - Connect to "openwifi" network
# - ping 192.168.13.1

# Check statistics
./tx_stat_show.sh
./rx_stat_show.sh
```

**Test RX path:**

```bash
# Monitor mode
./monitor_ch.sh sdr0 44

# Capture packets
tcpdump -i sdr0 -w capture.pcap

# Analyze
wireshark capture.pcap
```

### Performance Testing

**Throughput test:**

```bash
# On board (server mode)
iperf3 -s

# On client
iperf3 -c 192.168.13.1 -t 60 -i 1

# UDP test
iperf3 -c 192.168.13.1 -u -b 50M
```

**Latency test:**

```bash
# Ping test
ping -c 1000 -i 0.001 192.168.13.1

# Analyze
# - Min/Avg/Max latency
# - Packet loss
# - Jitter
```

**Link quality test:**

```bash
# Automated test across all rates
./link_perf_test.sh

# Results: PER vs rate for different payload sizes
```

### Stress Testing

**High packet rate:**

```bash
# Generate traffic
./inject_80211 -m g -r 7 -t d -n 10000 -s 100 -d 100 mon0

# Monitor
watch -n 1 './tx_stat_show.sh'
```

**Long duration:**

```bash
# 24-hour test
iperf3 -c 192.168.13.1 -t 86400 &

# Monitor periodically
while true; do
    date >> stress_test.log
    ./tx_stat_show.sh >> stress_test.log
    sleep 300
done
```

---

## Debugging Techniques

### Kernel Debugging

**Enable debug messages:**

```bash
# Increase kernel log level
echo 8 > /proc/sys/kernel/printk

# Enable driver debug
echo 'module openwifi +p' > /sys/kernel/debug/dynamic_debug/control

# View messages
dmesg -w
```

**Add debug prints:**

```c
// In driver code
pr_debug("Variable x = %d\n", x);  // Only with debug enabled
pr_info("Always printed\n");        // Always visible

// Conditional compilation
#ifdef DEBUG_FEATURE
    pr_info("Debug: %s\n", __func__);
#endif
```

**Function tracing:**

```bash
# Enable ftrace
cd /sys/kernel/debug/tracing
echo function > current_tracer
echo openwifi_tx > set_ftrace_filter
echo 1 > tracing_on

# Generate traffic
ping -c 10 192.168.13.1

# View trace
cat trace
```

### FPGA Debugging

**Register dumps:**

```bash
# Read all registers from a module
for i in {0..63}; do
    val=$(./sdrctl dev sdr0 get reg xpu $i 2>&1 | grep -o '0x[0-9a-f]*')
    printf "Reg %2d: %s\n" $i $val
done
```

**State machine debugging:**

```bash
# XPU CSMA state
./sdrctl dev sdr0 get reg xpu 36

# OFDM RX state history
./sdrctl dev sdr0 get reg rx 20
```

**IQ capture for debugging:**

```bash
cd /root/openwifi/side_ch_ctl_src

# Capture IQ samples
python3 iq_capture.py &

# Generate test signal
cd /root/openwifi
./inject_80211 -m g -r 0 -t d -n 10 -s 100 mon0

# Analyze iq.txt in MATLAB/Octave
```

### RF Debugging

**TX debugging:**

```bash
# Check TX attenuation
cat /sys/bus/iio/devices/iio:device1/out_voltage0_hardwaregain

# Check TX LO frequency
cat /sys/bus/iio/devices/iio:device1/out_altvoltage1_TX_LO_frequency

# Check TX enable
cat /sys/bus/iio/devices/iio:device1/out_altvoltage1_TX_LO_powerdown

# Spectrum analyzer check
# Connect spectrum analyzer to TX port
# Should see signal at expected frequency
```

**RX debugging:**

```bash
# Check RX gain
./rx_gain_show.sh

# Check RSSI
./rssi_ad9361_show.sh

# Check AGC mode
cat /sys/bus/iio/devices/iio:device1/in_voltage0_gain_control_mode

# Known good signal test
# Place TX and RX antennas close together
# Check if packets are received
```

### GDB Remote Debugging

**On target:**

```bash
# Install gdbserver
apt-get install gdbserver

# Start program under gdbserver
gdbserver :1234 ./sdrctl dev sdr0 get reg xpu 0
```

**On host:**

```bash
# Cross-compile with debug symbols
arm-linux-gnueabihf-gcc -g -o sdrctl sdrctl.c

# Connect GDB
arm-linux-gnueabihf-gdb sdrctl
(gdb) target remote 192.168.10.122:1234
(gdb) break main
(gdb) continue
```

---

## Adding New Features

### Example: Add Rate Limit Feature

**1. Design:**
- Goal: Limit TX rate per queue
- Method: Add rate limiter in driver TX path
- Configuration: Via sysfs attribute

**2. Implementation:**

```c
// File: driver/sdr.h
struct openwifi_priv {
    // ... existing fields
    u32 rate_limit_mbps[MAX_NUM_SW_QUEUE];  // Per-queue limit
    unsigned long last_tx_time[MAX_NUM_SW_QUEUE];
};

// File: driver/sdr.c
static void openwifi_tx(...)
{
    // ... existing code

    // Rate limiting
    if (priv->rate_limit_mbps[queue_idx] > 0) {
        unsigned long now = jiffies;
        unsigned long delta = now - priv->last_tx_time[queue_idx];
        unsigned long min_interval = HZ * 8 * skb->len /
                                      (priv->rate_limit_mbps[queue_idx] * 1000000);

        if (delta < min_interval) {
            // Too fast, drop or delay
            dev_kfree_skb_any(skb);
            return;
        }

        priv->last_tx_time[queue_idx] = now;
    }

    // ... continue with TX
}

// File: driver/sysfs_intf.c
static ssize_t rate_limit_show(struct device *dev,
                                struct device_attribute *attr, char *buf)
{
    struct openwifi_priv *priv = dev_get_drvdata(dev);
    return sprintf(buf, "%u %u %u %u\n",
                   priv->rate_limit_mbps[0],
                   priv->rate_limit_mbps[1],
                   priv->rate_limit_mbps[2],
                   priv->rate_limit_mbps[3]);
}

static ssize_t rate_limit_store(struct device *dev,
                                 struct device_attribute *attr,
                                 const char *buf, size_t count)
{
    struct openwifi_priv *priv = dev_get_drvdata(dev);
    sscanf(buf, "%u %u %u %u",
           &priv->rate_limit_mbps[0],
           &priv->rate_limit_mbps[1],
           &priv->rate_limit_mbps[2],
           &priv->rate_limit_mbps[3]);
    return count;
}

static DEVICE_ATTR_RW(rate_limit);
```

**3. Testing:**

```bash
# Compile and deploy
./make_all.sh /opt/Xilinx 32
scp sdr.ko root@192.168.10.122:openwifi/

# Test
ssh openwifi
cd openwifi
./wgd.sh

# Set rate limit
echo "10 20 30 40" > /sys/devices/.../sdr/rate_limit

# Test with iperf
iperf3 -c 192.168.13.1

# Verify rate is limited
```

**4. Documentation:**

```bash
# Add to USER_TOOLS_GUIDE.md
# Add to API_REFERENCE.md
# Update CHANGELOG
```

---

## Performance Optimization

### Profiling

**CPU profiling with perf:**

```bash
# Install perf
apt-get install linux-perf

# Profile TX path
perf record -e cycles -g -- ping -c 1000 192.168.13.1

# View report
perf report

# Flamegraph
perf script | ./flamegraph.pl > flamegraph.svg
```

**Interrupt load:**

```bash
# Monitor interrupts
watch -n 1 'cat /proc/interrupts | grep sdr'

# Check CPU usage
top
# Look for high %si (software interrupt)
```

### Optimization Techniques

**1. Reduce Interrupt Rate:**

```c
// Batch RX processing
#define RX_BATCH_SIZE 16

static irqreturn_t openwifi_rx_interrupt(...)
{
    int processed = 0;

    while (processed < RX_BATCH_SIZE) {
        // Process packet
        processed++;
    }

    return IRQ_HANDLED;
}
```

**2. Optimize Critical Path:**

```c
// Use likely/unlikely for branch prediction
if (unlikely(skb == NULL)) {
    // Error path
}

if (likely(info->flags & IEEE80211_TX_CTL_AMPDU)) {
    // Fast path (aggregation)
}
```

**3. Cache Optimization:**

```c
// Align structures to cache lines
struct openwifi_priv {
    // Hot fields (frequently accessed)
    struct openwifi_ring tx_ring[4] ____cacheline_aligned;

    // Cold fields (rarely accessed)
    struct openwifi_stat stat ____cacheline_aligned;
};
```

**4. Lock Optimization:**

```c
// Use read/write locks when appropriate
rwlock_t my_rwlock;

// Read path (multiple concurrent readers OK)
read_lock(&my_rwlock);
// ... read operation
read_unlock(&my_rwlock);

// Write path (exclusive access)
write_lock(&my_rwlock);
// ... write operation
write_unlock(&my_rwlock);
```

---

## Contributing

### Contribution Process

**1. Fork and Clone:**

```bash
# Fork on GitHub
# https://github.com/open-sdr/openwifi

# Clone your fork
git clone https://github.com/YOUR_USERNAME/openwifi.git
cd openwifi
git remote add upstream https://github.com/open-sdr/openwifi.git
```

**2. Create Feature Branch:**

```bash
# Update main
git checkout main
git pull upstream main

# Create branch
git checkout -b feature/my-new-feature
```

**3. Make Changes:**

- Follow coding standards
- Add comments and documentation
- Write tests
- Update documentation

**4. Commit:**

```bash
# Stage changes
git add -p  # Review each change

# Commit with descriptive message
git commit -m "Add rate limiting feature for TX queues

- Implement per-queue rate limiting
- Add sysfs interface for configuration
- Include unit tests
- Update documentation

Signed-off-by: Your Name <your.email@example.com>"
```

**5. Push and Create PR:**

```bash
# Push to your fork
git push origin feature/my-new-feature

# Create Pull Request on GitHub
# Include:
# - Clear description
# - Testing performed
# - Related issues
```

### Contributor License Agreement (CLA)

**Required:** Sign CLA before first contribution

File: `/home/user/openwifi/CONTRIBUTING.md`

```markdown
All contributors must sign the Contributor License Agreement (CLA)
before their contributions can be accepted.

This protects both the project and contributors regarding
intellectual property rights.
```

**Process:**
1. Read CLA: https://github.com/open-sdr/openwifi/CLA.md
2. Sign electronically or print/scan/email
3. Submit with first PR

### Code Review

**What reviewers look for:**

- ✅ **Correctness:** Does it work as intended?
- ✅ **Style:** Follows Linux kernel coding style?
- ✅ **Performance:** No unnecessary overhead?
- ✅ **Safety:** Proper error handling?
- ✅ **Documentation:** Code comments and user docs?
- ✅ **Tests:** Adequate test coverage?

**Responding to feedback:**

```bash
# Make requested changes
git add modified_files
git commit --amend  # If updating last commit

# Or add new commit
git commit -m "Address review feedback"

# Force push (amend) or normal push (new commit)
git push -f origin feature/my-new-feature  # If amended
git push origin feature/my-new-feature     # If new commit
```

### Release Process

**Version numbering:** MAJOR.MINOR.PATCH

- **MAJOR:** Incompatible API changes
- **MINOR:** New features, backwards-compatible
- **PATCH:** Bug fixes

**Tagging releases:**

```bash
# Update version in code
# Update CHANGELOG.md

# Commit
git add -A
git commit -m "Release version 1.6.0"

# Tag
git tag -a v1.6.0 -m "Version 1.6.0 release"

# Push
git push upstream main --tags
```

---

## Best Practices

### General Guidelines

1. **Start Small:** Begin with minor bug fixes or documentation
2. **Ask Questions:** Use mailing list or GitHub issues
3. **Test Thoroughly:** On actual hardware, multiple boards if possible
4. **Document Everything:** Code comments, user guides, commit messages
5. **Follow Standards:** Linux kernel style, project conventions
6. **Be Patient:** Reviews take time, be receptive to feedback

### Common Pitfalls

**❌ Avoid:**

- Changing too many things at once
- Breaking existing functionality
- Adding features without tests
- Ignoring error handling
- Poor commit messages
- Mixing whitespace changes with functional changes

**✅ Do:**

- One feature per PR
- Preserve backwards compatibility when possible
- Add tests for new features
- Handle all error cases
- Write clear, descriptive commit messages
- Separate refactoring from functional changes

---

## Resources

### Documentation

- [ARCHITECTURE.md](/doc/ARCHITECTURE.md) - System architecture
- [PHY_MAC_GUIDE.md](/doc/PHY_MAC_GUIDE.md) - PHY/MAC implementation
- [BUILD_GUIDE.md](/doc/BUILD_GUIDE.md) - Build procedures
- [API_REFERENCE.md](/doc/API_REFERENCE.md) - API documentation

### External Resources

- [Linux Kernel Coding Style](https://www.kernel.org/doc/html/latest/process/coding-style.html)
- [Linux Device Drivers (LDD3)](https://lwn.net/Kernel/LDD3/)
- [mac80211 Documentation](https://wireless.wiki.kernel.org/en/developers/documentation/mac80211)
- [Xilinx Vivado Documentation](https://www.xilinx.com/support/documentation-navigation/design-hubs/dh0015-vivado-design-hub.html)

### Community

- **Mailing List:** openwifi@lists.open-sdr.org
- **GitHub Issues:** https://github.com/open-sdr/openwifi/issues
- **Chat:** #openwifi on IRC Libera.Chat

---

**Document Version:** 1.0
**Last Updated:** 2025-11-21
**License:** AGPL-3.0-or-later
