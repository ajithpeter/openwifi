# OpenWiFi User-Space Tools Guide

This comprehensive guide documents all user-space tools, utilities, and scripts for OpenWiFi, an open-source IEEE 802.11 SDR implementation.

## Table of Contents

1. [Overview](#overview)
2. [sdrctl - SDR Control Utility](#sdrctl---sdr-control-utility)
3. [inject_80211 - Packet Injection Tool](#inject_80211---packet-injection-tool)
4. [side_ch_ctl - Side Channel Control](#side_ch_ctl---side-channel-control)
5. [Python Visualization Tools](#python-visualization-tools)
6. [Configuration Scripts](#configuration-scripts)
7. [Performance Testing Tools](#performance-testing-tools)
8. [Debugging and Monitoring](#debugging-and-monitoring)

---

## Overview

OpenWiFi provides a comprehensive suite of user-space tools for:
- Hardware register access and configuration
- Packet injection and fuzzing
- CSI (Channel State Information) capture
- IQ signal capture and analysis
- Network configuration (AP, client, monitor, ad-hoc modes)
- RF parameter tuning
- Performance testing
- Real-time monitoring and debugging

**Location**: All tools are located in `/openwifi/user_space/`

---

## sdrctl - SDR Control Utility

`sdrctl` is the primary control interface for OpenWiFi, providing access to hardware registers, network slicing, and various configuration parameters.

### Location and Build

**Source**: `/user_space/sdrctl_src/`

**Build**:
```bash
cd /openwifi/user_space/sdrctl_src/
make
```

**Binary**: `./sdrctl`

### Basic Usage

```bash
./sdrctl [options] <device> <section> <command> [arguments]
```

**Options**:
- `--debug`: Enable netlink debugging
- `--version`: Show version information

**Device identification**:
- `dev <devname>`: Use network device (e.g., `dev sdr0`)
- `phy <phyname>`: Use PHY device
- `wdev <idx>`: Use wireless device index

### Commands

#### 1. Register Access

**Read Register**:
```bash
./sdrctl dev sdr0 get reg <module> <reg_idx>
```

**Write Register**:
```bash
./sdrctl dev sdr0 set reg <module> <reg_idx> <value>
```

**Register Modules**:
- `rf`: AD9361 RF transceiver registers
- `rx_intf`: RX interface registers
- `tx_intf`: TX interface registers
- `rx`: RX FPGA module registers
- `tx`: TX FPGA module registers
- `xpu`: XPU (Transmit/Receive Unit) registers
- `drv_rx`: Driver RX registers
- `drv_tx`: Driver TX registers
- `drv_xpu`: Driver XPU registers

**Examples**:

```bash
# Read TX register 0
./sdrctl dev sdr0 get reg tx 0

# Output:
# SENDaddr: 00050000
# reg  val: 00000001

# Write value 123 to RX interface register 5
./sdrctl dev sdr0 set reg rx_intf 5 123

# Output:
# reg  cat: 2
# reg addr: 00020014
# reg  val: 0000007b

# Read RF transceiver register 10
./sdrctl dev sdr0 get reg rf 10
```

#### 2. RSSI Threshold Configuration

**Get RSSI Threshold**:
```bash
./sdrctl dev sdr0 get rssi_th
```

**Output**:
```
openwifi rssi_th: 150
```

**Set RSSI Threshold**:
```bash
./sdrctl dev sdr0 set rssi_th <value>
```

**Example**:
```bash
# Set RSSI threshold to 140
./sdrctl dev sdr0 set rssi_th 140

# Output:
# openwifi rssi_th: 140
```

The RSSI threshold determines packet reception sensitivity. Lower values increase sensitivity but may accept more noise.

#### 3. Network Slicing Configuration

OpenWiFi supports network slicing with time-division scheduling for different users/services.

**Set Slice Parameters**:

```bash
# Set slice total duration
./sdrctl dev sdr0 set slice_total <duration_us>

# Set slice start time
./sdrctl dev sdr0 set slice_start <start_time_us>

# Set slice end time
./sdrctl dev sdr0 set slice_end <end_time_us>

# Set slice index (bit mask)
./sdrctl dev sdr0 set slice_idx <hex_value>

# Set target MAC address for slice (low 32 bits)
./sdrctl dev sdr0 set addr <mac_low32_hex>
```

**Get Slice Parameters**:

```bash
./sdrctl dev sdr0 get slice_total
./sdrctl dev sdr0 get slice_start
./sdrctl dev sdr0 get slice_end
./sdrctl dev sdr0 get slice_idx
./sdrctl dev sdr0 get addr
```

**Example - Configure Network Slice**:

```bash
# Set 10ms cycle period for slice 0
./sdrctl dev sdr0 set slice_total 10000

# Output:
# openwifi slice_total (duration): 10000us

# Set slice to start at 0us
./sdrctl dev sdr0 set slice_start 0

# Set slice to end at 5000us (50% duty cycle)
./sdrctl dev sdr0 set slice_end 5000

# Set slice index bitmask
./sdrctl dev sdr0 set slice_idx 00000001

# Set target MAC address (example: lower 32 bits)
./sdrctl dev sdr0 set addr 33222211
```

**Helper Script** - `slice_cfg.sh`:

```bash
./slice_cfg.sh <slice_idx> <mac_addr> <cycle_us> <start_us> <end_us>
```

Example:
```bash
# Configure slice 0 for MAC 33222211, 10ms cycle, 0-5ms active
./slice_cfg.sh 0 33222211 10000 0 5000
```

#### 4. Inter-Frame Gap Configuration

**Get Gap**:
```bash
./sdrctl dev sdr0 get gap
```

**Set Gap**:
```bash
./sdrctl dev sdr0 set gap <gap_usec>
```

**Example**:
```bash
# Set inter-frame gap to 20 microseconds
./sdrctl dev sdr0 set gap 20

# Get current gap
./sdrctl dev sdr0 get gap
# Output: openwifi GAP (usec): 20
```

#### 5. TSF (Timing Synchronization Function)

**Set TSF**:
```bash
./sdrctl dev sdr0 set tsf <high_32bits> <low_32bits>
```

**Example**:
```bash
# Set TSF to a specific timestamp
./sdrctl dev sdr0 set tsf 0 1000000

# Output:
# high_tsf val: 00000000
# low_tsf  val: 000f4240
```

### Advanced Register Access Examples

**Enable/Disable Features**:

```bash
# Disable NAV (Network Allocation Vector)
./sdrctl dev sdr0 set reg xpu 2 0

# Disable CW (Contention Window)
./sdrctl dev sdr0 set reg xpu 3 0

# Disable DIFS (DCF Interframe Space)
./sdrctl dev sdr0 set reg xpu 1 0

# Disable EIFS (Extended Interframe Space)
./sdrctl dev sdr0 set reg xpu 0 0
```

**TX Power and Rate Control**:

```bash
# Set TX rate/MCS index (0-11 for 802.11n)
./sdrctl dev sdr0 set reg drv_tx 0 7

# Read current TX MCS
./sdrctl dev sdr0 get reg drv_tx 0
```

---

## inject_80211 - Packet Injection Tool

`inject_80211` enables raw 802.11 packet injection with full control over packet format, rate, and timing.

### Location and Build

**Source**: `/user_space/inject_80211/`

**Build**:
```bash
cd /openwifi/user_space/inject_80211/
make
```

**Binary**: `./inject_80211`

### Usage

```bash
./inject_80211 [options] <monitor_interface>
```

### Options

- `-m, --hw_mode <mode>`: Hardware mode (a, g, n)
- `-r, --rate_index <index>`: Rate/MCS index (0-7)
- `-t, --packet_type <type>`: Packet type (m/c/d/r for management/control/data/reserved)
- `-e, --sub_type <hex>`: Subtype in hex
- `-a, --addr1 <mac>`: Destination MAC address (hex, no colons)
- `-b, --addr2 <mac>`: Source MAC address (hex, no colons)
- `-i, --sgi_flag <0|1>`: Short Guard Interval flag
- `-n, --num_packets <count>`: Number of packets to inject
- `-s, --payload_size <bytes>`: Payload size in bytes
- `-d, --delay <usec>`: Delay between packets in microseconds
- `-h`: Show help

### Packet Types and Subtypes

**Management Packets** (`-t m`):
- `0x8`: Beacon
- `0xA`: Disassociation
- `0xB`: Authentication
- `0xC`: Deauthentication

**Control Packets** (`-t c`):
- `0xA`: PS-Poll
- `0xB`: RTS (Request To Send)
- `0xC`: CTS (Clear To Send)
- `0xD`: ACK (Acknowledgment)

**Data Packets** (`-t d`):
- `0x0`: Data
- `0x1`: Data+CF-Ack
- `0x2`: Data+CF-Poll
- `0x8`: QoS-Data

### Examples

#### 1. Basic Data Packet Injection

```bash
# Setup monitor mode first
iw dev sdr0 interface add mon0 type monitor
ifconfig mon0 up

# Inject 100 data packets at 6Mbps (802.11a/g)
./inject_80211 -m a -r 0 -t d -e 0 -n 100 -s 100 -d 100000 mon0
```

**Output**:
```
mode = 802.11a, rate index = 0, SHORT GI = 0, number of packets = 100 and packet size = 178 bytes, delay = 100000 usec
packet_type d sub_type 0 payload_len 104 ieee_hdr_len 24 addr1 0000000000000001 addr2 0000000000000002
number of packets sent = 100
```

#### 2. 802.11n Injection with MCS

```bash
# Inject MCS 7 packets with Short GI
./inject_80211 -m n -r 7 -i 1 -t d -e 0 -n 50 -s 1400 -d 50000 mon0
```

#### 3. Beacon Injection

```bash
# Inject beacon frames
./inject_80211 -m a -r 0 -t m -e 8 \
  -a 112233445566 -b 112233445566 \
  -n 10 -s 200 -d 100000 mon0
```

#### 4. RTS/CTS Injection

```bash
# Inject RTS frames
./inject_80211 -m a -r 0 -t c -e B \
  -a 112233445566 -b AABBCCDDEEFF \
  -n 20 -d 50000 mon0

# Inject CTS frames
./inject_80211 -m a -r 0 -t c -e C \
  -a 112233445566 -n 20 -d 50000 mon0
```

#### 5. High-Speed Continuous Injection

```bash
# Maximum rate injection with minimal delay
./inject_80211 -m n -r 7 -i 1 -t d -e 0 \
  -n 10000 -s 1400 -d 1000 mon0
```

#### 6. Custom MAC Addresses

```bash
# Inject packets with specific MAC addresses
./inject_80211 -m a -r 3 -t d -e 0 \
  -a FFFFFFFFFFFF -b 001122334455 \
  -n 100 -s 500 -d 10000 mon0
```

### Fuzzing Capabilities

The inject_80211 tool can be used for protocol fuzzing by combining with scripts:

**Script**: `inject_80211.sh`
```bash
#!/bin/bash
# Example injection script
for i in {0..7}; do
  ./inject_80211 -m a -r $i -t d -e 0 -n 100 -s 1000 -d 10000 mon0
  sleep 1
done
```

### Packet Format

The tool constructs packets with:
1. **Radiotap Header**: Contains transmission parameters
2. **IEEE 802.11 Header**: MAC addresses, frame control, sequence
3. **Payload**: Random or specified data

**Radiotap Header Fields**:
- Timestamp
- Flags
- Rate (for legacy) or MCS (for 802.11n)
- Channel frequency
- Antenna signal/noise
- MCS information (bandwidth, guard interval, rate)

---

## side_ch_ctl - Side Channel Control

`side_ch_ctl` provides access to hardware side channels for register access, CSI capture, and IQ sample capture.

### Location and Build

**Source**: `/user_space/side_ch_ctl_src/side_ch_ctl.c`

**Build**:
```bash
cd /openwifi/user_space/side_ch_ctl_src/
gcc -o side_ch_ctl side_ch_ctl.c
```

**Binary**: `./side_ch_ctl`

### Usage

```bash
./side_ch_ctl <parameter_string> [value_only_flag]
```

### Parameter String Format

The parameter string encodes the operation:

**Format**: `<action><type><index><format><value>`

- **Action**: `w` (write), `r` (read), `g` (get side info)
- **Type**: `h` (hardware), `s` (software)
- **Index**: Register index (0-31)
- **Format**: `d` (decimal), `h` (hexadecimal)
- **Value**: The value to write

### Examples

#### 1. Register Write Operations

```bash
# Write 987 (decimal) to hardware register 3
./side_ch_ctl wh3d987

# Output:
# parse: ret 0
#    tx: action_flag 1 reg_type 1 reg_idx 3 reg_val 987 interval_ms 0
#    rx: size 4 val 987 0x000003db

# Write 0x3db (hex) to software register 19
./side_ch_ctl ws19h3db

# Output:
# parse: ret 0
#    tx: action_flag 1 reg_type 2 reg_idx 19 reg_val 987 interval_ms 0
#    rx: size 4 val 987 0x000003db
```

#### 2. Register Read Operations

```bash
# Read software register 23
./side_ch_ctl rs23

# Output:
# parse: ret 0
#    tx: action_flag 2 reg_type 2 reg_idx 23 reg_val 0 interval_ms 0
#    rx: size 4 val 42 0x0000002a

# Read hardware register 5
./side_ch_ctl rh5

# Value-only output (for scripting)
./side_ch_ctl rh5 1
# Output: 42
```

#### 3. CSI and Side Information Capture

```bash
# Get CSI every 100ms (default)
./side_ch_ctl g

# Output:
# parse: ret 0
#    tx: action_flag 3 reg_type 0 reg_idx 0 reg_val 0 interval_ms 100
# loop 64 side info count 64
# loop 128 side info count 128
# ...

# Get CSI every 400ms
./side_ch_ctl g400

# Output:
# The default 100ms side info getting period is taken!
# parse: ret 0
#    tx: action_flag 3 reg_type 0 reg_idx 0 reg_val 0 interval_ms 400
```

The captured side information is sent to UDP port 4000 at 192.168.10.1 for processing by Python visualization tools.

### Side Channel Data Format

**Side Information Structure**:
- **Header** (2 DMA symbols = 16 bytes):
  - Timestamp (8 bytes)
  - Frequency offset (8 bytes)
- **CSI Data** (56 DMA symbols = 448 bytes):
  - Complex channel estimates for 56 subcarriers
  - I/Q format (16-bit I, 16-bit Q per subcarrier)
- **Equalizer Output** (optional, 52 DMA symbols):
  - Equalized constellation points

### Register Configuration Examples

```bash
# Configure RX gain
./side_ch_ctl wh10d70    # Set RX gain to 70

# Configure TX power
./side_ch_ctl wh20d15    # Set TX power to 15

# Read AGC status
./side_ch_ctl rh15       # Read AGC gain value

# Enable/disable features
./side_ch_ctl ws0d1      # Enable feature in SW reg 0
./side_ch_ctl ws0d0      # Disable feature in SW reg 0
```

---

## Python Visualization Tools

OpenWiFi includes Python tools for real-time visualization of captured CSI and IQ data.

### Location

**Directory**: `/user_space/side_ch_ctl_src/`

**Files**:
- `side_info_display.py`: CSI visualization
- `iq_capture.py`: Single-antenna IQ capture
- `iq_capture_2ant.py`: Dual-antenna IQ capture
- `iq_capture_freq_offset.py`: IQ capture with frequency offset analysis

### Requirements

```bash
pip3 install numpy matplotlib
```

### 1. CSI Visualization - side_info_display.py

Captures and displays Channel State Information in real-time.

**Usage**:
```bash
python3 side_info_display.py [num_eq] [waterfall_flag]
```

**Parameters**:
- `num_eq`: Number of equalizer symbols (default: 8)
  - 8 for CSI + equalizer output
  - 0 for CSI only
- `waterfall_flag`: Any value to enable waterfall plot

**Examples**:

```bash
# Start CSI capture (CSI + equalizer)
python3 side_info_display.py 8
```

**On the OpenWiFi board**, run:
```bash
./side_ch_ctl g100  # Send CSI every 100ms
```

**Output**:
- **Figure 0**: Frequency offset over time
- **Figure 1**: CSI amplitude and phase per subcarrier
- **Figure 2**: Equalizer constellation diagram (I/Q scatter plot)
- **Figure 3** (if waterfall enabled): CSI amplitude and phase waterfall

```bash
# CSI only (no equalizer)
python3 side_info_display.py 0

# CSI with waterfall visualization
python3 side_info_display.py 8 1
```

**Data Storage**:
- Captured data saved to `side_info.txt`
- Format: uint16 values (timestamp, freq_offset, CSI I/Q pairs)

### 2. IQ Capture - iq_capture.py

Captures and visualizes raw IQ samples with AGC and RSSI information.

**Usage**:
```bash
python3 iq_capture.py [iq_len]
```

**Parameters**:
- `iq_len`: Number of IQ samples per capture (default: 8187)
  - Max: 8187 (UDP packet size limit)

**Examples**:

```bash
# Start IQ capture with default length
python3 iq_capture.py

# Output:
# Assume iq_len = 8187! (Max UDP 65507 bytes; (65507/8)-1 = 8187)
```

**On the OpenWiFi board**, configure IQ capture:
```bash
# Set IQ capture length (in number of samples)
./side_ch_ctl wh20d8187

# Enable IQ capture
./side_ch_ctl wh21d1

# Trigger capture on next packet
# Packets will automatically trigger IQ capture
```

**Output**:
- **Figure 0**: I/Q time-domain waveform with status flags
  - Blue: I (In-phase)
  - Red: Q (Quadrature)
  - Black: FCS OK indicator
  - Red dashed: Demodulation active
  - Green: TX RF active
  - Blue dashed: Channel idle
- **Figure 1**: AGC gain and lock status
  - Blue: Gain value
  - Red: Lock status
- **Figure 2**: RSSI over time (uncalibrated)

**Data Storage**:
- Captured data saved to `iq.txt`

**Capture Configuration**:
```bash
# Short capture for header analysis
python3 iq_capture.py 1000

# Full packet capture
python3 iq_capture.py 5000
```

### 3. Dual-Antenna IQ Capture - iq_capture_2ant.py

Captures IQ samples from two antennas simultaneously (for MIMO/diversity analysis).

**Usage**:
```bash
python3 iq_capture_2ant.py [iq_len]
```

**Example**:
```bash
# Start dual-antenna capture
python3 iq_capture_2ant.py 4000
```

**Output**:
- **Figure 0**: Two subplots showing rx0 and rx1 I/Q samples
- Displays timestamp and maximum values
- Data saved to `iq_2ant.txt`

### 4. Frequency Offset Analysis - iq_capture_freq_offset.py

Advanced IQ capture with frequency offset estimation and compensation.

**Usage**:
```bash
python3 iq_capture_freq_offset.py [iq_len]
```

**Features**:
- Automatic frequency offset detection
- Carrier frequency offset (CFO) compensation
- Symbol timing analysis
- Constellation diagram with offset correction

### UDP Configuration

All Python tools listen on UDP port 4000. The side channel data is sent from the OpenWiFi board to the host PC.

**Default settings** (in tools):
```python
UDP_IP = "192.168.10.1"    # Local IP to listen
UDP_PORT = 4000             # Local port to listen
```

**Network Setup**:

On host PC:
```bash
# Set static IP
sudo ifconfig eth0 192.168.10.1 netmask 255.255.255.0

# Verify connection to board
ping 192.168.10.122
```

On OpenWiFi board:
```bash
# Verify route to host
ping 192.168.10.1
```

### Real-Time Visualization Workflow

Complete workflow for real-time CSI monitoring:

**Step 1** - On Host PC:
```bash
cd /openwifi/user_space/side_ch_ctl_src/
python3 side_info_display.py 8
```

**Step 2** - On OpenWiFi board:
```bash
cd /root/openwifi
./side_ch_ctl g100
```

**Step 3** - Generate traffic for CSI capture:
```bash
# On another terminal, send ping packets
ping 192.168.13.2 -i 0.1
```

The CSI will update in real-time on the host PC as packets are transmitted/received.

---

## Configuration Scripts

OpenWiFi includes 59+ shell scripts for system configuration, network setup, and RF parameter tuning.

### Network Mode Configuration

#### 1. Monitor Mode - monitor_ch.sh

Set interface to monitor mode for packet capture.

**Usage**:
```bash
./monitor_ch.sh <interface> <channel>
```

**Example**:
```bash
./monitor_ch.sh sdr0 6

# Output:
# sdr0
# 6
# [interface and mode configuration output]
```

**What it does**:
- Brings interface down
- Sets monitor mode
- Brings interface up
- Sets channel
- Applies optimized AGC settings

#### 2. Ad-Hoc Mode - sdr-ad-hoc-up.sh

Configure ad-hoc (IBSS) network.

**Usage**:
```bash
./sdr-ad-hoc-up.sh <interface> <channel> <ip_address>
```

**Example**:
```bash
# Set up ad-hoc network on channel 6
./sdr-ad-hoc-up.sh sdr0 6 192.168.1.100

# Output:
# sdr0
# 6
# 192.168.1.100
# [configuration output]
```

**ESSID**: Fixed to 'sdr-ad-hoc'

#### 3. Ad-Hoc Join - sdr-ad-hoc-join.sh

Join existing ad-hoc network (similar to sdr-ad-hoc-up.sh).

#### 4. Access Point Mode - fosdem.sh

Start Access Point with DHCP server and web interface.

**Usage**:
```bash
./fosdem.sh
```

**What it does**:
- Stops conflicting services
- Loads driver modules
- Configures sdr0 with IP 192.168.13.1
- Starts ISC DHCP server
- Starts hostapd with configuration from `hostapd-openwifi.conf`
- Starts web server on port 80
- Applies optimized AGC settings

**Configuration File**: `hostapd-openwifi.conf`
```
interface=sdr0
ssid=openwifi
hw_mode=g
channel=6
```

**Alternative** - fosdem-11ag.sh:
- Uses `hostapd-openwifi-11ag.conf` for 802.11a/g mode

### RF Configuration

#### 1. RF Initialization - rf_init.sh

Initialize AD9361 RF transceiver with optimal settings.

**Usage**:
```bash
./rf_init.sh [tx_offset_disable]
```

**Parameters**:
- No argument or 0: Enable TX offset tuning (uses `openwifi_ad9361_fir.ftr`)
- 1: Disable TX offset tuning (uses `openwifi_ad9361_fir_tx_0MHz.ftr`)

**Example**:
```bash
# Initialize with TX offset tuning enabled
./rf_init.sh

# Initialize with TX offset tuning disabled
./rf_init.sh 1
```

**What it configures**:
- RX/TX bandwidth: 17.5 MHz / 37.5 MHz
- Sampling frequency: 40 MHz
- LO frequency: 1 GHz (for both RX and TX)
- FIR filter: Loads filter configuration
- AGC mode: Fast attack (automatic gain control)
- RX gain: 70 dB
- TX gain: -89 dB (ch0), 0 dB (ch1)
- Displays RSSI

**Output**:
```
tx_offset_tuning_enable 1
Found openwifi_ad9361_fir.ftr
...
in_voltage_sampling_frequency: 40000000
in_voltage_rf_bandwidth: 17500000
...
rssi: -30
```

#### 2. 802.11n RF Initialization - rf_init_11n.sh

Similar to rf_init.sh but optimized for 802.11n operation.

**Differences**:
- Uses `openwifi_ad9361_fir_tx_0MHz_11n.ftr` filter
- Optimized for OFDM and HT (High Throughput) modes

#### 3. AGC Settings - agc_settings.sh

Configure AD9361 AGC (Automatic Gain Control) parameters.

**Usage**:
```bash
./agc_settings.sh <0|1>
```

**Parameters**:
- `0`: Apply default AGC settings
- `1`: Apply optimized AGC settings (recommended)

**Example**:
```bash
# Apply optimized AGC settings
./agc_settings.sh 1

# Output:
# Applied optimized AGC settings
```

**What it configures**:
- AGC attack/decay times
- Gain step sizes
- Lock thresholds
- RSSI thresholds

**Optimized vs Default**:
| Register | Default | Optimized |
|----------|---------|-----------|
| 0x15C    | 0x72    | 0x70      |
| 0x106    | 0x72    | 0x77      |
| 0x103    | 0x08    | 0x1C      |
| 0x110    | 0x40    | 0x48      |
| 0x115    | 0x00    | 0x80      |

#### 4. RX Gain Configuration

**Auto Gain** - set_rx_gain_auto.sh:
```bash
./set_rx_gain_auto.sh
```

Enables automatic gain control (fast_attack mode).

**Manual Gain** - set_rx_gain_manual.sh:
```bash
./set_rx_gain_manual.sh <gain_value>
```

Example:
```bash
# Set RX gain to 60 dB
./set_rx_gain_manual.sh 60
```

#### 5. TX Port Configuration - set_tx_port.sh

Select TX output port (A or B).

**Usage**:
```bash
./set_tx_port.sh <port>
```

**Parameters**:
- `A`: Use TX port A
- `B`: Use TX port B

**Example**:
```bash
# Use TX port B
./set_tx_port.sh B
```

#### 6. TX LO Frequency - set_tx_lo.sh

Set TX Local Oscillator frequency (carrier frequency).

**Usage**:
```bash
./set_tx_lo.sh <frequency_hz>
```

**Example**:
```bash
# Set TX LO to 2.437 GHz (channel 6)
./set_tx_lo.sh 2437000000
```

### MAC Layer Configuration

#### 1. Contention Window - cw_max_min_cfg.sh

Configure contention window min/max values.

**Usage**:
```bash
./cw_max_min_cfg.sh <cw_min> <cw_max>
```

**Example**:
```bash
# Set CW_min=15, CW_max=1023 (802.11 defaults)
./cw_max_min_cfg.sh 15 1023
```

#### 2. Disable MAC Features

Disable various MAC layer features for testing:

**Disable DIFS** (DCF Interframe Space):
```bash
./difs_disable.sh
```

**Disable EIFS** (Extended Interframe Space):
```bash
./eifs_disable.sh
./eifs_by_last_rx_fail_disable.sh
./eifs_by_last_tx_fail_disable.sh
```

**Disable NAV** (Network Allocation Vector):
```bash
./nav_disable.sh
```

**Disable CW** (Contention Window):
```bash
./cw_disable.sh
```

**These scripts are useful for**:
- Protocol analysis
- Low-latency experiments
- Custom MAC implementations

#### 3. LBT Threshold - set_lbt_th.sh

Configure Listen-Before-Talk threshold.

**Usage**:
```bash
./set_lbt_th.sh <threshold>
```

**Example**:
```bash
# Set LBT threshold
./set_lbt_th.sh -80
```

### Driver Management

#### 1. Load/Reload Driver - wgd.sh

Comprehensive script for loading/reloading drivers and FPGA images without rebooting.

**Usage**:
```bash
./wgd.sh [test_mode|remote|directory|tar.gz] [test_mode]
```

**Modes**:

**Mode 1** - Load from current directory:
```bash
./wgd.sh
```
Loads .ko files and system_top.bit.bin from current directory with test_mode=0.

**Mode 2** - Load with specific test_mode:
```bash
./wgd.sh 2
```
test_mode is a bitmask for driver behavior.

**Mode 3** - Download from remote and load:
```bash
./wgd.sh remote [target_dir] [test_mode]
```

Example:
```bash
# Download to ./remote_build and load
./wgd.sh remote remote_build 0
```

**Mode 4** - Load from directory:
```bash
./wgd.sh /path/to/driver/dir [test_mode]
```

**Mode 5** - Extract tar.gz and load:
```bash
./wgd.sh openwifi_build.tar.gz [test_mode]
```

**What it does**:
1. Stops conflicting services (hostapd, dhcpd, wpa_supplicant)
2. Unloads sdr module
3. Optionally downloads/reloads FPGA image
4. Initializes RF (calls rf_init_11n.sh)
5. Loads modules in order: tx_intf, rx_intf, openofdm_tx, openofdm_rx, xpu, sdr
6. Applies AGC settings

**Modules loaded**:
- `xilinx_dma.ko`: DMA engine driver
- `tx_intf.ko`: TX interface
- `rx_intf.ko`: RX interface
- `openofdm_tx.ko`: OFDM TX modulator
- `openofdm_rx.ko`: OFDM RX demodulator
- `xpu.ko`: Transmit/Receive Unit
- `sdr.ko`: Main SDR driver (mac80211 interface)

#### 2. FPGA Image Loading - load_fpga_img.sh

Load FPGA bitstream.

**Usage**:
```bash
./load_fpga_img.sh <path_to_bit.bin>
```

**Example**:
```bash
./load_fpga_img.sh system_top.bit.bin
```

#### 3. Populate Files

**populate_driver_userspace.sh**:
Copy drivers and user-space tools to board.

**populate_kernel_image_module_reboot.sh**:
Update kernel image and modules, then reboot.

### Advanced Configuration

#### 1. CSI Fuzzing - csi_fuzzer.sh

Configure CSI modification for testing equalizers and algorithms.

**Usage**:
```bash
./csi_fuzzer.sh <c1_rot90_en> <c1_value> <c2_rot90_en> <c2_value>
```

**Parameters**:
- `c1_rot90_en`: Enable 90-degree rotation for coefficient 1 (0 or 1)
- `c1_value`: Coefficient 1 value (-64 to 63)
- `c2_rot90_en`: Enable 90-degree rotation for coefficient 2 (0 or 1)
- `c2_value`: Coefficient 2 value (-64 to 63)

**Example**:
```bash
# Set CSI fuzzer coefficients
./csi_fuzzer.sh 0 10 1 -20

# Output:
# ./sdrctl dev sdr0 set reg tx_intf 5 524298
```

**Use cases**:
- Test receiver algorithms
- Simulate channel conditions
- Verify CSI processing

#### 2. Restrict Frequency - set_restrict_freq.sh

Restrict operation to specific frequency.

**Usage**:
```bash
./set_restrict_freq.sh <frequency_mhz>
```

#### 3. RX Monitor Configuration

**Monitor all packets**:
```bash
./set_rx_monitor_all.sh
```

**Monitor specific MAC address**:
```bash
./set_rx_target_sender_mac_addr.sh <mac_address>
```

#### 4. Debug Channel Selection

Set debug output channels for logic analyzer/scope:

```bash
./set_dbg_ch0.sh
./set_dbg_ch1.sh
./set_dbg_ch2.sh
```

#### 5. Receiver Phase Offset - receiver_phase_offset_override.sh

Override receiver phase offset for testing.

**Usage**:
```bash
./receiver_phase_offset_override.sh <offset>
```

---

## Performance Testing Tools

### 1. Link Performance Test - link_perf_test.sh

Comprehensive link performance measurement across rates and payload sizes.

**Usage**:
```bash
./link_perf_test.sh
```

**Configuration** (edit script):
```bash
PL_MIN=100          # Minimum payload size
PL_INC=100          # Payload increment
PL_MAX=1500         # Maximum payload size
INTERVAL=0.001      # Packet interval (seconds)
PKT_CNT=700         # Number of packets per test
DEADLINE=1          # Timeout (seconds)
CLIENT_IP="192.168.13.2"  # Target IP
```

**What it tests**:
- 8 data rates: 6, 9, 12, 18, 24, 36, 48, 54 Mbps
- Multiple payload sizes: 100 to 1500 bytes (configurable)
- Measures packet loss and RTT for each combination

**Example Output**:
```
LINK PERFORMANCE TEST
=====================
RATE/PL         100         200         300         400         500
6Mbps       0%,1.2ms    0%,1.5ms    0%,1.8ms    0%,2.1ms    1%,2.4ms
9Mbps       0%,1.1ms    0%,1.3ms    0%,1.6ms    1%,1.9ms    2%,2.2ms
12Mbps      0%,1.0ms    0%,1.2ms    1%,1.5ms    2%,1.8ms    3%,2.1ms
...
```

**Running the test**:

**Step 1** - Configure AP mode:
```bash
./fosdem.sh
```

**Step 2** - Connect client to 'openwifi' network

**Step 3** - Run test:
```bash
./link_perf_test.sh
```

The test automatically:
1. Configures each MCS rate
2. Sends packets at each payload size
3. Measures packet loss and RTT
4. Generates formatted result table

### 2. TX/RX Statistics

#### TX Statistics - tx_stat_show.sh

Display and optionally clear TX statistics.

**Usage**:
```bash
# Show statistics
./tx_stat_show.sh

# Show and clear statistics
./tx_stat_show.sh 1
```

**Output**:
```
+ cat tx_data_pkt_need_ack_num_total
1523
+ cat tx_data_pkt_need_ack_num_total_fail
42
+ cat tx_data_pkt_need_ack_num_retx
187
+ cat tx_data_pkt_need_ack_num_retx_fail
15
+ cat tx_data_pkt_mcs_realtime
7
+ cat tx_data_pkt_fail_mcs_realtime
7
+ cat tx_mgmt_pkt_need_ack_num_total
89
+ cat tx_mgmt_pkt_need_ack_num_total_fail
2
...
```

**Statistics Explained**:
- `tx_data_pkt_need_ack_num_total`: Total data packets sent requiring ACK
- `tx_data_pkt_need_ack_num_total_fail`: Data packets that failed (no ACK)
- `tx_data_pkt_need_ack_num_retx`: Data packets retransmitted
- `tx_data_pkt_need_ack_num_retx_fail`: Retransmissions that failed
- `tx_data_pkt_mcs_realtime`: Current MCS for data packets
- `tx_data_pkt_fail_mcs_realtime`: MCS of last failed data packet
- Similar statistics for management packets

#### RX Statistics - rx_stat_show.sh

Display and optionally clear RX statistics, or calculate PER.

**Usage**:
```bash
# Show statistics
./rx_stat_show.sh

# Show and clear statistics
./rx_stat_show.sh clear

# Calculate PER for target packet count
./rx_stat_show.sh <total_packets>
```

**Output**:
```
+ cat rx_data_pkt_num_total
2456
+ cat rx_data_pkt_num_fail
78
+ cat rx_mgmt_pkt_num_total
345
+ cat rx_mgmt_pkt_num_fail
12
+ cat rx_ack_pkt_num_total
1523
+ cat rx_ack_pkt_num_fail
5
+ cat rx_data_pkt_mcs_realtime
7
+ cat rx_data_pkt_fail_mcs_realtime
7
+ cat rx_mgmt_pkt_mcs_realtime
0
...
```

**PER Calculation Example**:
```bash
# Expected 1000 packets, calculate PER
./rx_stat_show.sh 1000

# Output:
# PCR 9680 / 10000
# PER 320 / 10000
```

PCR = Packet Correct Rate = 96.8%
PER = Packet Error Rate = 3.2%

### 3. TX Priority Queue - tx_prio_queue_show.sh

Display TX queue status for each priority level.

**Usage**:
```bash
./tx_prio_queue_show.sh
```

Shows pending packets in each queue (VO, VI, BE, BK).

### 4. RSSI Monitoring

**OpenWiFi RSSI** - rssi_openwifi_show.sh:
```bash
./rssi_openwifi_show.sh
```

Shows RSSI from OpenWiFi processing.

**AD9361 RSSI** - rssi_ad9361_show.sh:
```bash
./rssi_ad9361_show.sh
```

Shows RSSI from AD9361 RF chip.

**RX Gain** - rx_gain_show.sh:
```bash
./rx_gain_show.sh
```

Shows current RX gain value.

---

## Debugging and Monitoring

### Real-Time Monitoring

#### 1. Enable Statistics - stat_enable.sh

Enable real-time statistics collection.

**Usage**:
```bash
./stat_enable.sh
```

Enables counters for TX/RX statistics that can be read via sysfs or the stat_show scripts.

#### 2. IQ Data Transmission

**Transmit IQ to sysfs**:
```bash
./tx_intf_iq_data_to_sysfs.sh
```

**Send IQ data**:
```bash
./tx_intf_iq_send.sh
```

Useful for testing TX path with known IQ samples.

### System Information

#### 1. Post Configuration - post_config.sh

Display system configuration after driver load.

**Usage**:
```bash
./post_config.sh
```

Shows:
- Loaded modules
- Network interface status
- PHY information
- Channel configuration

#### 2. Calibration Check - check_calib_inf.sh

Check AD9361 calibration status.

**Usage**:
```bash
./check_calib_inf.sh
```

Verifies RF calibration is complete and valid.

### Development Tools

#### 1. Kernel Preparation - prepare_kernel.sh

Prepare kernel for development (kernel headers, build tools).

**Usage**:
```bash
./prepare_kernel.sh
```

#### 2. SD Card Management

**Update SD card boot files** - sdcard_boot_update.sh:
```bash
./sdcard_boot_update.sh
```

**Complete SD card update** - update_sdcard.sh:
```bash
./update_sdcard.sh
```

Comprehensive script for updating SD card with new kernel, drivers, and FPGA images.

#### 3. Boot Binary Generation - boot_bin_gen.sh

Generate BOOT.BIN for Zynq boot.

**Usage**:
```bash
./boot_bin_gen.sh
```

Creates BOOT.BIN from FSBL, bitstream, and U-Boot.

#### 4. Driver Package Generation - drv_and_fpga_package_gen.sh

Create distribution package with drivers and FPGA image.

**Usage**:
```bash
./drv_and_fpga_package_gen.sh
```

Generates tar.gz file with all necessary files.

### File Transfer

#### 1. Transfer to Board - transfer_driver_userspace_to_board.sh

Copy drivers and tools to board via network.

**Usage**:
```bash
./transfer_driver_userspace_to_board.sh <board_ip>
```

**Example**:
```bash
./transfer_driver_userspace_to_board.sh 192.168.10.122
```

#### 2. Transfer Kernel - transfer_kernel_image_module_to_board.sh

Copy kernel image and modules to board.

**Usage**:
```bash
./transfer_kernel_image_module_to_board.sh <board_ip>
```

### Restore Normal Operation - nic_back_to_normal.sh

Restore NIC to normal operation after testing.

**Usage**:
```bash
./nic_back_to_normal.sh
```

Re-enables all MAC features (DIFS, EIFS, NAV, CW, etc.).

---

## Common Workflows

### Workflow 1: Set Up OpenWiFi Access Point

```bash
cd /root/openwifi

# 1. Load drivers and FPGA
./wgd.sh

# 2. Start AP mode
./fosdem.sh

# 3. Monitor statistics
watch -n 1 './tx_stat_show.sh; ./rx_stat_show.sh'
```

### Workflow 2: Monitor Mode Packet Capture

```bash
# 1. Set monitor mode on channel 6
./monitor_ch.sh sdr0 6

# 2. Start Wireshark or tcpdump
wireshark -i sdr0 &

# Or
tcpdump -i sdr0 -w capture.pcap
```

### Workflow 3: Packet Injection Testing

```bash
# 1. Create monitor interface
iw dev sdr0 interface add mon0 type monitor
ifconfig mon0 up

# 2. Inject packets
cd inject_80211
./inject_80211 -m n -r 7 -i 1 -t d -e 0 \
  -n 1000 -s 1000 -d 10000 mon0

# 3. Monitor on another device
# (Use Wireshark to observe injected packets)
```

### Workflow 4: Real-Time CSI Monitoring

**On Host PC** (192.168.10.1):
```bash
cd /openwifi/user_space/side_ch_ctl_src/
python3 side_info_display.py 8 1  # With waterfall
```

**On OpenWiFi Board**:
```bash
cd /root/openwifi

# 1. Ensure network connectivity
ping 192.168.10.1

# 2. Start CSI capture
./side_ch_ctl g100

# 3. Generate traffic (in another terminal)
ping 192.168.13.2 -i 0.1
```

CSI will be visualized in real-time on host PC.

### Workflow 5: Link Performance Testing

```bash
# 1. Set up AP
./fosdem.sh

# 2. Connect client device

# 3. Run performance test
./link_perf_test.sh

# 4. Analyze results
# Results show packet loss and RTT for each rate/size combination
```

### Workflow 6: Network Slicing Configuration

```bash
# Configure two slices for different users

# Slice 0: MAC 11:22:33:44:55:66, active first 5ms of 10ms cycle
./slice_cfg.sh 0 665544332211 10000 0 5000

# Slice 1: MAC AA:BB:CC:DD:EE:FF, active last 5ms of 10ms cycle
./slice_cfg.sh 1 FFEEDDCCBBAA 10000 5000 10000

# Verify configuration
./sdrctl dev sdr0 get slice_total
./sdrctl dev sdr0 get slice_start
./sdrctl dev sdr0 get slice_end
```

### Workflow 7: IQ Capture and Analysis

**On Host PC**:
```bash
python3 iq_capture.py 8187
```

**On OpenWiFi Board**:
```bash
# Configure IQ capture
./side_ch_ctl wh20d8187  # Set capture length
./side_ch_ctl wh21d1     # Enable IQ capture

# Generate packet (IQ will be captured automatically)
ping 192.168.13.2
```

### Workflow 8: Driver Development Iteration

```bash
# 1. Make code changes on development PC

# 2. Build kernel modules
cd /openwifi/kernel_module/
make

# 3. Package and transfer
cd /openwifi/user_space/
./drv_and_fpga_package_gen.sh

# 4. Transfer to board
./transfer_driver_userspace_to_board.sh 192.168.10.122

# 5. On board, reload drivers
cd /root/openwifi
./wgd.sh remote_build

# 6. Test
./fosdem.sh
```

---

## Tips and Best Practices

### 1. Network Configuration

- Always check network connectivity before starting captures:
  ```bash
  ping 192.168.10.1  # Host PC
  ping 192.168.10.122  # OpenWiFi board
  ```

- Ensure no conflicting services:
  ```bash
  killall hostapd wpa_supplicant dhcpd
  ```

### 2. RF Configuration

- Apply optimized AGC settings after any RF configuration:
  ```bash
  ./agc_settings.sh 1
  ```

- Verify RSSI after RF init:
  ```bash
  ./rssi_ad9361_show.sh
  ./rssi_openwifi_show.sh
  ```

### 3. Debugging

- Check driver messages:
  ```bash
  dmesg | tail -50
  ```

- Verify modules loaded:
  ```bash
  lsmod | grep -E "sdr|xpu|openofdm|intf"
  ```

- Check interface status:
  ```bash
  iw dev
  ifconfig sdr0
  ```

### 4. Performance Optimization

- For low latency, disable MAC features selectively:
  ```bash
  ./difs_disable.sh
  ./nav_disable.sh
  ```

- For high throughput, ensure:
  - Optimal RX gain (60-70 dB typical)
  - Good channel conditions (RSSI > -70 dBm)
  - High MCS rates (6-7 for 802.11n)

### 5. Data Capture

- For long captures, increase UDP buffer:
  ```python
  sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8192)
  ```

- Save data for offline analysis:
  - CSI: `side_info.txt`
  - IQ: `iq.txt`, `iq_2ant.txt`

### 6. Troubleshooting

**Problem**: No CSI data received
- **Solution**:
  ```bash
  # Check side_ch_ctl is running
  ps aux | grep side_ch_ctl

  # Check network route
  route -n

  # Verify UDP port not blocked
  netstat -ulnp | grep 4000
  ```

**Problem**: Packet injection fails
- **Solution**:
  ```bash
  # Ensure monitor mode
  iw dev sdr0 info | grep monitor

  # Check interface is up
  ifconfig mon0
  ```

**Problem**: Driver won't load
- **Solution**:
  ```bash
  # Check FPGA loaded
  cat /sys/class/fpga_manager/fpga0/state

  # Verify RF chip detected
  dmesg | grep ad9361

  # Check dependencies
  lsmod | grep mac80211
  ```

---

## Reference Tables

### MCS Rates

| MCS | Modulation | Coding | 20MHz BW | 20MHz BW SGI |
|-----|------------|--------|----------|--------------|
| 0   | BPSK       | 1/2    | 6.5 Mbps | 7.2 Mbps     |
| 1   | QPSK       | 1/2    | 13 Mbps  | 14.4 Mbps    |
| 2   | QPSK       | 3/4    | 19.5 Mbps| 21.7 Mbps    |
| 3   | 16-QAM     | 1/2    | 26 Mbps  | 28.9 Mbps    |
| 4   | 16-QAM     | 3/4    | 39 Mbps  | 43.3 Mbps    |
| 5   | 64-QAM     | 2/3    | 52 Mbps  | 57.8 Mbps    |
| 6   | 64-QAM     | 3/4    | 58.5 Mbps| 65 Mbps      |
| 7   | 64-QAM     | 5/6    | 65 Mbps  | 72.2 Mbps    |

### Legacy Rates (802.11a/g)

| Index | Rate     |
|-------|----------|
| 0     | 6 Mbps   |
| 1     | 9 Mbps   |
| 2     | 12 Mbps  |
| 3     | 18 Mbps  |
| 4     | 24 Mbps  |
| 5     | 36 Mbps  |
| 6     | 48 Mbps  |
| 7     | 54 Mbps  |

### 802.11 Channels (2.4 GHz)

| Channel | Frequency | Typical Use |
|---------|-----------|-------------|
| 1       | 2412 MHz  | Non-overlapping |
| 6       | 2437 MHz  | Non-overlapping |
| 11      | 2462 MHz  | Non-overlapping |

### Register Modules

| Module    | Description                        | Address Space |
|-----------|------------------------------------|---------------|
| rf        | AD9361 RF transceiver              | 0x010000-0x01FFFF |
| rx_intf   | RX interface (DMA, sync)           | 0x020000-0x02FFFF |
| tx_intf   | TX interface (DMA, sync)           | 0x030000-0x03FFFF |
| rx        | RX FPGA (demod, decoder)           | 0x040000-0x04FFFF |
| tx        | TX FPGA (encoder, modulator)       | 0x050000-0x05FFFF |
| xpu       | XPU (MAC, scheduler)               | 0x060000-0x06FFFF |
| drv_rx    | Driver RX state                    | 0x070000-0x07FFFF |
| drv_tx    | Driver TX state                    | 0x080000-0x08FFFF |
| drv_xpu   | Driver XPU state                   | 0x090000-0x09FFFF |

### Sysfs Paths

**Device Path** (statistics, configuration):
```
/sys/devices/platform/fpga-axi@0/fpga-axi@0:sdr/
# or
/sys/devices/soc0/fpga-axi@0/fpga-axi@0:sdr/
```

**AD9361 IIO Path** (RF configuration):
```
/sys/bus/iio/devices/iio:deviceX/
```

**AD9361 Debug Path** (direct register access):
```
/sys/kernel/debug/iio/iio:deviceX/direct_reg_access
```

---

## Script Summary Table

| Script | Purpose | Usage Example |
|--------|---------|---------------|
| `wgd.sh` | Load/reload drivers and FPGA | `./wgd.sh` |
| `fosdem.sh` | Start AP mode | `./fosdem.sh` |
| `monitor_ch.sh` | Set monitor mode | `./monitor_ch.sh sdr0 6` |
| `sdr-ad-hoc-up.sh` | Configure ad-hoc mode | `./sdr-ad-hoc-up.sh sdr0 6 192.168.1.1` |
| `rf_init.sh` | Initialize RF | `./rf_init.sh` |
| `agc_settings.sh` | Configure AGC | `./agc_settings.sh 1` |
| `slice_cfg.sh` | Configure network slice | `./slice_cfg.sh 0 112233 10000 0 5000` |
| `link_perf_test.sh` | Test link performance | `./link_perf_test.sh` |
| `tx_stat_show.sh` | Show TX statistics | `./tx_stat_show.sh` |
| `rx_stat_show.sh` | Show RX statistics | `./rx_stat_show.sh` |
| `csi_fuzzer.sh` | Configure CSI fuzzing | `./csi_fuzzer.sh 0 10 1 -20` |
| `set_rx_gain_auto.sh` | Enable auto RX gain | `./set_rx_gain_auto.sh` |
| `set_rx_gain_manual.sh` | Set manual RX gain | `./set_rx_gain_manual.sh 60` |

---

## Additional Resources

**OpenWiFi Project**:
- GitHub: https://github.com/open-sdr/openwifi
- Documentation: https://github.com/open-sdr/openwifi/tree/master/doc

**802.11 Standards**:
- IEEE 802.11-2020: Wireless LAN Medium Access Control (MAC) and Physical Layer (PHY) Specifications

**AD9361 Documentation**:
- AD9361 Reference Manual: https://www.analog.com/en/products/ad9361.html
- IIO Oscilloscope: https://wiki.analog.com/resources/tools-software/linux-software/iio_oscilloscope

---

## Conclusion

This guide covers the comprehensive suite of OpenWiFi user-space tools. The tools provide complete control over:
- RF configuration and tuning
- MAC layer behavior
- Network modes and topologies
- Performance measurement
- Real-time monitoring and debugging
- Advanced features like network slicing and CSI capture

For additional help, refer to the source code comments and the main OpenWiFi documentation.

**Total Scripts**: 59
**Compiled Tools**: 3 (sdrctl, inject_80211, side_ch_ctl)
**Python Tools**: 4 (side_info_display, iq_capture, iq_capture_2ant, iq_capture_freq_offset)
