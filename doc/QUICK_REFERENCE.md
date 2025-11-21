# openwifi Quick Reference Guide

**Copy-paste ready commands for common openwifi operations**

## 1. Quick Start Commands

### Initial Setup
```bash
# SSH to board (default password: openwifi)
ssh root@192.168.10.122

# Expand SD card filesystem (only once, for SD > 16GB)
raspi-config --expand-rootfs
reboot

# One-time setup (run once per new board)
cd ~/openwifi
./setup_once.sh
reboot
```

### Basic Bring-Up
```bash
# Load driver and start openwifi
cd ~/openwifi
./wgd.sh

# With AMPDU/aggregation enabled
./wgd.sh 1

# Start AP mode (5GHz, channel 44)
./fosdem.sh

# Start AP mode (force 11a/g mode)
./fosdem-11ag.sh
```

### Give Clients Internet Access (on PC)
```bash
# Enable IP forwarding and NAT (replace ethX and NICY with your interface names)
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o NICY -j MASQUERADE
sudo ip route add 192.168.13.0/24 via 192.168.10.122 dev ethX
```

## 2. Common Operations (One-Liners)

### Driver Management
```bash
# Reload driver with test_mode
./wgd.sh 1

# Load driver from specific directory
./wgd.sh /path/to/driver/dir

# Download and load driver from FTP server
./wgd.sh remote

# Unload driver only
sudo rmmod sdr
```

### Network Interface
```bash
# Bring interface up/down
sudo ifconfig sdr0 up
sudo ifconfig sdr0 down

# Set IP address
sudo ifconfig sdr0 192.168.13.1

# Check interface status
ifconfig sdr0
iwconfig sdr0
```

### Channel Operations
```bash
# Change channel (replace 36 with desired channel)
sudo iwconfig sdr0 channel 36

# Set frequency (MHz)
sudo iwconfig sdr0 freq 2412M
```

### Kill Services
```bash
# Stop all openwifi services
killall hostapd
killall wpa_supplicant
killall dhcpd
killall webfsd
```

## 3. Configuration Snippets

### AP Mode (hostapd)
```bash
# Basic AP configuration (edit hostapd-openwifi.conf)
interface=sdr0
ssid=openwifi
hw_mode=a
channel=36
ieee80211n=1
require_ht=1

# Start hostapd
hostapd hostapd-openwifi.conf &
```

### Client Mode (wpa_supplicant)
```bash
# Edit wpa-connect.conf
network={
    ssid="target_network"
    psk="password"
}

# Connect as client
route del default gw 192.168.10.1
wpa_supplicant -i sdr0 -c wpa-connect.conf &
dhclient sdr0
```

### Monitor Mode
```bash
# Enable monitor mode on channel 11
./monitor_ch.sh sdr0 11

# Manual monitor mode setup
sudo ip link set sdr0 down
sudo iwconfig sdr0 mode monitor
sudo ip link set sdr0 up
sudo iwconfig sdr0 channel 11
```

### Ad-hoc Mode
```bash
# Create ad-hoc network on channel 6 with IP
./sdr-ad-hoc-up.sh sdr0 6 192.168.1.10

# Join existing ad-hoc network
./sdr-ad-hoc-join.sh sdr0 6 192.168.1.11
```

## 4. Troubleshooting Quick Fixes

### Common Issues

**Client can't get IP**
```bash
# Restart DHCP server
service isc-dhcp-server restart
rm /var/run/dhcpd.pid
service isc-dhcp-server restart
```

**No space left on device**
```bash
# Clean up logs
systemd-tmpfiles --clean
sudo systemd-tmpfiles --remove
rm /var/log/* -rf

# Add to /etc/systemd/journald.conf
echo "SystemMaxUse=64M" >> /etc/systemd/journald.conf
echo "Storage=volatile" >> /etc/systemd/journald.conf
```

**DNS/Network issues**
```bash
# Fix DNS on board
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# On PC: delete problematic config on SD card
rm /mnt/sdcard/rootfs/etc/network/interfaces.new
```

**DHCP client interfering**
```bash
# Stop DHCP client service
sudo service dhcpcd stop
```

**Viterbi decoder halts (after ~2 hours)**
```bash
# Check if decoder is stuck (output shouldn't be constant)
./sdrctl dev sdr0 get reg rx 20

# Reload FPGA or power cycle board
./load_fpga_img.sh system_top.bit.bin
./wgd.sh
```

**Driver version mismatch**
```bash
# Check git revision
./sdrctl dev sdr0 get reg drv_xpu 7  # Driver
./sdrctl dev sdr0 get reg xpu 63     # FPGA
./sdrctl dev sdr0 get reg rx 31      # RX module
```

## 5. Register Access Shortcuts

### Basic Register Commands
```bash
# Get register value
./sdrctl dev sdr0 get reg MODULE REG_IDX

# Set register value
./sdrctl dev sdr0 set reg MODULE REG_IDX VALUE
```

### Critical Register Quick Access

**RX Sensitivity**
```bash
# Get current threshold (-NdBm)
./sdrctl dev sdr0 get reg drv_rx 0

# Set to -80dBm (receiver won't react below this)
./sdrctl dev sdr0 set reg drv_rx 0 80
```

**TX Rate Override**
```bash
# Get current setting (0=auto)
./sdrctl dev sdr0 get reg drv_tx 0

# Force 24Mbps (non-HT)
./sdrctl dev sdr0 set reg drv_tx 0 8

# Force MCS5 (13Mbps HT)
./sdrctl dev sdr0 set reg drv_tx 1 5

# Restore auto rate control
./sdrctl dev sdr0 set reg drv_tx 0 0
```

**CCA/LBT Threshold**
```bash
# Check current threshold
./set_lbt_th.sh

# Set to -70dBm
./set_lbt_th.sh 70

# Disable CCA (always idle)
./set_lbt_th.sh 1

# Restore auto
./set_lbt_th.sh 0
```

**TX Power/Attenuation**
```bash
# Get TX attenuation (dB*1000)
./sdrctl dev sdr0 get reg rf 0

# Set 3dB attenuation
./sdrctl dev sdr0 set reg rf 0 3000
```

**Frequency Override**
```bash
# Set TX frequency to 3.5GHz
./sdrctl dev sdr0 set reg rf 1 3500

# Set RX frequency to 3.5GHz
./sdrctl dev sdr0 set reg rf 5 3500
```

**Antenna Selection**
```bash
# Select RX antenna (0=ant0, 1=ant1)
./sdrctl dev sdr0 set reg drv_rx 4 0

# Select TX antenna (0=tx1, 1=tx2)
./sdrctl dev sdr0 set reg drv_tx 4 0
```

**RSSI Reading**
```bash
# Read real-time RSSI (xpu register 57)
./rssi_openwifi_show.sh
./rssi_ad9361_show.sh
```

**TSF Timer**
```bash
# Get TSF low 32-bit
./sdrctl dev sdr0 get reg xpu 58

# Get TSF high 32-bit
./sdrctl dev sdr0 get reg xpu 59

# Set TSF (requires high and low values)
./sdrctl dev sdr0 set tsf 0 0
```

## 6. Network Mode Setup Commands

### Access Point (AP)
```bash
cd ~/openwifi
./wgd.sh
ifconfig sdr0 192.168.13.1
rm /var/run/dhcpd.pid
service isc-dhcp-server restart
hostapd hostapd-openwifi.conf &
```

### Station/Client
```bash
cd ~/openwifi
./wgd.sh
route del default gw 192.168.10.1
wpa_supplicant -i sdr0 -c wpa-connect.conf &
dhclient sdr0
```

### Monitor Mode
```bash
cd ~/openwifi
./wgd.sh
./monitor_ch.sh sdr0 11
```

### Ad-hoc Network
```bash
# Node 1 (creates network)
cd ~/openwifi
./wgd.sh
./sdr-ad-hoc-up.sh sdr0 6 192.168.1.10

# Node 2 (joins network)
cd ~/openwifi
./wgd.sh
./sdr-ad-hoc-join.sh sdr0 6 192.168.1.11
```

## 7. Performance Testing Commands

### iperf Tests
```bash
# On board (server)
iperf -s

# On client (TCP test)
iperf -c 192.168.13.1 -t 60 -i 1

# On client (UDP test, 50Mbps)
iperf -c 192.168.13.1 -u -b 50M -t 60
```

### Link Performance Test
```bash
# On board (requires client at 192.168.13.2)
cd ~/openwifi
./link_perf_test.sh
```

### Ping Tests
```bash
# Basic ping
ping -c 100 192.168.13.2

# Ping with specific payload size
ping -c 100 -s 1400 192.168.13.2

# Flood ping (careful!)
sudo ping -f 192.168.13.2
```

### Packet Injection
```bash
# Build inject tool
cd ~/openwifi/inject_80211
make

# Inject packets (monitor mode required)
./inject_80211 sdr0 -r 6 -n 100
```

## 8. Monitoring Commands

### Enable Debug Printing
```bash
# Enable all debug messages (TX/RX)
./sdrctl dev sdr0 set reg drv_tx 7 3
./sdrctl dev sdr0 set reg drv_rx 7 3

# Error messages only
./sdrctl dev sdr0 set reg drv_tx 7 1
./sdrctl dev sdr0 set reg drv_rx 7 1

# View messages
dmesg -w
```

**Debug bit meanings:**
- bit0: error messages
- bit1: unicast packet info
- bit2: broadcast packet info
- bit3: queue management info

### Traffic Monitoring
```bash
# tcpdump on openwifi interface
tcpdump -i sdr0 -n

# Wireshark (if X11 available)
wireshark -i sdr0

# Show TX statistics
./tx_stat_show.sh

# Show RX statistics
./rx_stat_show.sh

# Show TX priority queues
./tx_prio_queue_show.sh

# Monitor RX gain
./rx_gain_show.sh
```

### CSI (Chip State Information) Monitoring
```bash
# On board
cd ~/openwifi
./wgd.sh
./monitor_ch.sh sdr0 11
insmod side_ch.ko
./side_ch_ctl g

# On PC (not in SSH)
cd openwifi/user_space/side_ch_ctl_src
python3 side_info_display.py
```

### IQ Sample Capture
```bash
# Enable IQ capture
./sdrctl dev sdr0 set reg rx_intf 7 1

# Capture and save
cd side_ch_ctl_src
./side_ch_ctl g
```

### System Status
```bash
# Check loaded modules
lsmod | grep -E "sdr|80211|ad9361"

# Check driver version
modinfo sdr

# Check FPGA queue length (reg 26)
./sdrctl dev sdr0 get reg tx_intf 26

# Check if queue is almost full (reg 21)
./sdrctl dev sdr0 get reg tx_intf 21

# Monitor CSMA/channel state (reg 57)
watch -n 0.5 "./sdrctl dev sdr0 get reg xpu 57"
```

## 9. File Locations Reference

### On Board Paths
```
/root/openwifi/                          # Main openwifi directory
├── *.ko                                 # Driver modules
├── system_top.bit.bin                   # FPGA bitstream
├── sdrctl                               # Control utility
├── hostapd-openwifi.conf                # AP config
├── wpa-connect.conf                     # Client config
├── wgd.sh                               # Load driver script
├── fosdem.sh                            # Start AP script
├── monitor_ch.sh                        # Monitor mode script
├── sdr-ad-hoc-up.sh                     # Ad-hoc mode script
├── sdrctl_src/                          # sdrctl source
├── side_ch_ctl_src/                     # CSI/IQ tools
└── inject_80211/                        # Packet injection tool

/sys/bus/iio/devices/iio:deviceX/        # AD9361 RF control
├── in_voltage0_hardwaregain             # RX gain
├── in_voltage0_gain_control_mode        # manual/auto
└── in_voltage_rf_bandwidth              # RF bandwidth

/sys/kernel/debug/openwifi/              # Debug info (if available)
```

### Boot Partition (SD Card)
```
BOOT/
├── BOOT.BIN                             # FPGA + bootloader
├── uImage or Image                      # Kernel
├── devicetree.dtb                       # Device tree
└── openwifi/BOARD_NAME/                 # Board-specific files
```

### Important Config Files
```
/etc/network/interfaces                  # Network config
/etc/dhcp/dhcpd.conf                     # DHCP server config
/etc/hostapd/hostapd.conf                # Alternative hostapd config
/etc/wpa_supplicant/wpa_supplicant.conf  # Alternative wpa config
```

## 10. Important Parameters Table

### Module Names for sdrctl
| Module      | Description                        | Access |
|-------------|------------------------------------|--------|
| drv_rx      | Driver RX functionality            | R/W    |
| drv_tx      | Driver TX functionality            | R/W    |
| drv_xpu     | Driver XPU control                 | R/W    |
| rf          | AD9361 RF frontend                 | R/W    |
| rx_intf     | FPGA RX interface                  | R/W    |
| tx_intf     | FPGA TX interface                  | R/W    |
| rx          | FPGA OFDM receiver                 | R/W    |
| tx          | FPGA OFDM transmitter              | R/W    |
| xpu         | FPGA MAC processor                 | R/W    |

### TX Rate Values (drv_tx reg 0 - non-HT)
| Value | Rate   | Value | Rate   |
|-------|--------|-------|--------|
| 0     | Auto   | 8     | 24M    |
| 4     | 6M     | 9     | 36M    |
| 5     | 9M     | 10    | 48M    |
| 6     | 12M    | 11    | 54M    |
| 7     | 18M    |       |        |

### TX Rate Values (drv_tx reg 1 - HT)
| Value | Rate (20MHz) | Value | Rate (20MHz, short GI) |
|-------|--------------|-------|------------------------|
| 0     | Auto         | 20    | +16 for short GI       |
| 4     | 6.5M (MCS0)  | 21    | 13M (MCS1) short GI    |
| 5     | 13M (MCS1)   | 22    | 19.5M (MCS2) short GI  |
| 6     | 19.5M (MCS2) | 23    | 26M (MCS3) short GI    |
| 7     | 26M (MCS3)   | 24    | 39M (MCS4) short GI    |
| 8     | 39M (MCS4)   | 25    | 52M (MCS5) short GI    |
| 9     | 52M (MCS5)   | 26    | 58.5M (MCS6) short GI  |
| 10    | 58.5M (MCS6) | 27    | 65M (MCS7) short GI    |
| 11    | 65M (MCS7)   |       |                        |

### Frequency Bands and Channels
| Band  | Frequency Range | Common Channels       |
|-------|-----------------|----------------------|
| 2.4GHz| 2412-2484 MHz  | 1-13 (1-11 in US)    |
| 5GHz  | 5150-5825 MHz  | 36, 40, 44, 48, etc. |

### Channel Numbers to Frequency
```
Channel 1   = 2412 MHz
Channel 6   = 2437 MHz
Channel 11  = 2462 MHz
Channel 36  = 5180 MHz
Channel 44  = 5220 MHz
Channel 149 = 5745 MHz
```

### CW (Contention Window) Values
| CW Value | Actual CW Size | Slots Range |
|----------|----------------|-------------|
| 0        | 1              | 0           |
| 1        | 2              | 0-1         |
| 2        | 4              | 0-3         |
| 3        | 8              | 0-7         |
| 4        | 16             | 0-15        |
| 5        | 32             | 0-31        |
| 6        | 64             | 0-63        |

### Default Timing Parameters (microseconds)
| Parameter    | 2.4GHz | 5GHz | Adjustable |
|--------------|--------|------|------------|
| SIFS         | 10     | 10   | Yes (xpu)  |
| DIFS         | 34     | 34   | Yes (xpu)  |
| Slot time    | 9      | 9    | Yes (xpu)  |
| OFDM symbol  | 4      | 4    | Yes (xpu)  |

### Performance Expectations
| Metric              | Best Case       | Notes                    |
|---------------------|-----------------|--------------------------|
| TCP throughput      | 40-50 Mbps     | With AMPDU aggregation   |
| UDP throughput      | 50 Mbps        | With AMPDU aggregation   |
| EVM                 | -38 dB         | FMCOMMS2, 2.4GHz        |
| MCS0 sensitivity    | -92 dBm        | Cable and OTA test       |
| MCS7 sensitivity    | -73 dBm        | Cable and OTA test       |
| SIFS achievement    | 10 μs          | HW/FPGA implementation   |

### Quick Command Syntax Reference
```bash
# sdrctl syntax
./sdrctl dev sdr0 {get|set} {reg|para} MODULE [REG_IDX] [VALUE]

# TSF syntax (needs two values)
./sdrctl dev sdr0 set tsf HIGH_TSF LOW_TSF

# Slice configuration
./sdrctl dev sdr0 set slice_idx 0
./sdrctl dev sdr0 set addr MAC_ADDR_LOW32
./sdrctl dev sdr0 set slice_total MICROSECONDS
./sdrctl dev sdr0 set slice_start MICROSECONDS
./sdrctl dev sdr0 set slice_end MICROSECONDS
./sdrctl dev sdr0 set slice_idx 4  # Sync all slices
```

## Additional Tips

### Restrict Frequency
```bash
# Lock to specific frequency (5220MHz = channel 44)
./set_restrict_freq.sh 5220

# Remove restriction
./set_restrict_freq.sh 0
```

### RX Gain Control
```bash
# Auto gain control
./set_rx_gain_auto.sh

# Manual gain (0-73 dB)
./set_rx_gain_manual.sh 40
```

### Advanced CSMA Control
```bash
# Disable NAV
./nav_disable.sh 1

# Disable DIFS
./difs_disable.sh 1

# Disable EIFS
./eifs_disable.sh 1

# Disable CW (contention window)
./cw_disable.sh 1

# Re-enable (use 0)
./nav_disable.sh 0
```

### Retransmission Control
```bash
# Check current ACK/retransmission config
./sdrctl dev sdr0 get reg xpu 11

# Disable ACK TX (monitor mode)
./sdrctl dev sdr0 set reg xpu 11 16

# Override max retransmissions to 1
./sdrctl dev sdr0 set reg xpu 11 9
```

---

## Useful Links
- Main documentation: `/home/user/openwifi/doc/README.md`
- App notes: `/home/user/openwifi/doc/app_notes/`
- Known issues: `/home/user/openwifi/doc/known_issue/notter.md`
- Project repository: https://github.com/open-sdr/openwifi
- Hardware repository: https://github.com/open-sdr/openwifi-hw

## Important Notes
1. **Always follow local spectrum regulations** or use cable/chamber for testing
2. Viterbi decoder halts after ~2 hours (Xilinx eval license) - power cycle or reload FPGA
3. Default board IP: 192.168.10.122 (PC should be 192.168.10.1)
4. Default AP IP: 192.168.13.1 (clients get 192.168.13.x)
5. Default password: openwifi
6. For ADRV9361-Z7035: very low TX power in 5GHz - move CLOSER!

---
*openwifi - Open-source IEEE 802.11/Wi-Fi baseband chip/FPGA design*
