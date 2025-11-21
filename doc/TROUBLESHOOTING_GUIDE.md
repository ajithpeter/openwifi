# OpenWiFi Troubleshooting Guide

**Comprehensive Troubleshooting and Debugging Reference**
**Version:** 1.5.0+
**Last Updated:** 2025-11-21
**Maintained by:** OpenWiFi Community

---

## Table of Contents

1. [Common Issues and Solutions](#common-issues-and-solutions)
   - [Build Errors](#build-errors)
   - [Boot Failures](#boot-failures)
   - [Driver Loading Problems](#driver-loading-problems)
   - [Network Connectivity Issues](#network-connectivity-issues)
   - [RF Problems](#rf-problems)
   - [Performance Issues](#performance-issues)
2. [Diagnostic Procedures](#diagnostic-procedures)
   - [Log Analysis](#log-analysis)
   - [Register Reading](#register-reading)
   - [Statistics Monitoring](#statistics-monitoring)
   - [IQ/CSI Capture for Debugging](#iqcsi-capture-for-debugging)
3. [Known Issues](#known-issues)
4. [Board-Specific Issues](#board-specific-issues)
5. [Recovery Procedures](#recovery-procedures)
   - [FPGA Reload](#fpga-reload)
   - [Driver Restart](#driver-restart)
   - [Full System Recovery](#full-system-recovery)
6. [Debug Techniques](#debug-techniques)
   - [Kernel Debugging](#kernel-debugging)
   - [FPGA Debugging](#fpga-debugging)
   - [RF Debugging](#rf-debugging)
7. [Common Error Messages](#common-error-messages)
8. [Quick Reference Commands](#quick-reference-commands)

---

## Common Issues and Solutions

### Build Errors

#### Issue: Kernel Module Build Fails with Symbol Errors

**Symptoms:**
```
ERROR: modpost: "ieee80211_tx_status_irqsafe" [/path/to/sdr.ko] undefined!
ERROR: modpost: "ieee80211_rx_irqsafe" [/path/to/sdr.ko] undefined!
```

**Cause:** Kernel source mismatch between build machine and target board.

**Solution:**
```bash
# On build machine:
cd openwifi/user_space
./prepare_kernel.sh $XILINX_DIR ARCH_BIT
# For Zynq 7000: ARCH_BIT=32
# For Zynq MPSoC: ARCH_BIT=64

# Rebuild driver
cd ../driver
./make_all.sh $XILINX_DIR ARCH_BIT

# Copy to board
scp `find ./ -name \*.ko` root@192.168.10.122:openwifi/

# If still having issues, update kernel on board:
# Copy kernel image to BOOT partition
# adi-linux/arch/arm/boot/uImage (32bit)
# adi-linux-64/arch/arm64/boot/Image (64bit)
```

#### Issue: GCC Plugin Configuration During Kernel Build

**Symptoms:**
```
GCC plugins (GCC_PLUGINS) [Y/n/?] (NEW)
STACKPROTECTOR_PER_TASK [Y/n/?] (NEW)
```

**Cause:** Kernel configuration update requires new settings.

**Solution:**
Always select **'n'** (no) or weakest options when prompted during kernel compilation. These options can cause compilation failures.

#### Issue: Missing libidn.so.11 During boot_bin_gen.sh

**Symptoms:**
```
error while loading shared libraries: libidn.so.11
```

**Solution:**
```bash
# Create symbolic link to newer version
sudo ln -s /usr/lib/x86_64-linux-gnu/libidn.so.12.6.3 /usr/lib/x86_64-linux-gnu/libidn.so.11

# Verify actual version in your system first
ls -la /usr/lib/x86_64-linux-gnu/libidn.so*
```

#### Issue: FPGA Build Tool License Error

**Symptoms:**
```
ERROR: [Common 17-69] Command failed: Vivado license error
```

**Solution:**
- For small boards (zed, adrv9364z7020, zc702, antsdr, etc.), NO Vivado license needed
- For large boards (zc706, zcu102, adrv9361z7035), Vivado license required
- Check board compatibility in README.md

---

### Boot Failures

#### Issue: Cannot SSH to Board After First Boot

**Symptoms:**
- Board powers on but SSH connection refused
- Network connection not established

**Diagnostic Steps:**
```bash
# 1. Check network configuration on PC
ip addr show
# PC should have IP 192.168.10.1

# 2. Check if board is reachable
ping 192.168.10.122

# 3. Use UART console to debug
# Connect to /dev/ttyUSB0 or /dev/ttyCH341USB0
# Baud rate: 115200
screen /dev/ttyUSB0 115200
# or
minicom -D /dev/ttyUSB0
```

**Solutions:**

1. **Delete interfaces.new file** (Ubuntu 22.04 issue):
```bash
# On SD card (mount on PC), delete:
# /etc/network/interfaces.new
```

2. **Check UART console for boot messages:**
   - Look for kernel panic
   - Check for filesystem mount errors
   - Verify device tree loading

3. **Verify SD card integrity:**
```bash
# Reflash with different tool:
# - gnome-disks
# - Startup Disk Creator
# - win32diskimager
```

#### Issue: EXT4-fs Error on Boot

**Symptoms:**
```
EXT4-fs error (device mmcblk0p2): ext4_lookup:1700: inode #2: comm systemd
Kernel panic - not syncing: VFS: Unable to mount root fs
```

**Cause:** SD card compatibility or flashing issue.

**Solution 1 (General boards):**
- Try different SD card flashing tool
- Use different SD card (Class 10 recommended)
- Verify SD card is not corrupted

**Solution 2 (ZCU102 specific):**
Add to devicetree (mmc or sdhci entry):
```
xlnx,has-cd = <0x1>;
xlnx,has-power = <0x0>;
xlnx,has-wp = <0x1>;
disable-wp;
no-1-8-v;
broken-cd;
xlnx,mio-bank = <1>;
sdhci-caps-mask = <0 0x200000>;
sdhci-caps = <0 0>;
max-frequency = <19000000>;
```

#### Issue: SPI Flash Boot Configuration

**Symptoms:**
- Board boots from SPI flash with wrong configuration
- Cannot load kernel from SD card

**Solution:**
```bash
# Interrupt boot at U-Boot prompt (press Enter during boot)
Zynq> env default -a
## Resetting to default environment
Zynq> saveenv
Saving Environment to SPI Flash...
SF: Detected n25q256a with page size 256 Bytes, erase size 4 KiB, total 32 MiB
Erasing SPI flash...Writing to SPI flash...done
Zynq> reset
```

#### Issue: FMCOMMS Board EEPROM Corruption

**Symptoms:**
- Linux crashes when FMCOMMS board attached
- Boot failure on ZCU102 with FMCOMMS2/3/4

**Diagnostic:**
```bash
# On a working platform (zed/zc706/etc):
git clone https://github.com/analogdevicesinc/fru_tools.git
cd fru_tools/
make
find /sys -name eeprom
# Example: /sys/devices/soc0/fpga-axi@0/41620000.i2c/i2c-0/0-0050/eeprom
./fru-dump -i /sys/devices/soc0/fpga-axi@0/41620000.i2c/i2c-0/0-0050/eeprom -b
```

**If error shows:**
```
FRU Version number mismatch 0xff should be 0x01
```

**Solution:**
```bash
# Reprogram EEPROM (FMCOMMS4 example)
./fru-dump -i ./masterfiles/AD-FMCOMMS4-EBZ-FRU.bin \
  -o /sys/devices/soc0/fpga-axi@0/41620000.i2c/i2c-0/0-0050/eeprom

# Reboot and verify
./fru-dump -i /sys/devices/soc0/fpga-axi@0/41620000.i2c/i2c-0/0-0050/eeprom -b
```

#### Issue: No Space Left on Device

**Symptoms:**
```
systemd-journald[5694]: Failed to open system journal: No space left on device
```

**Solution:**
```bash
# Clean up logs
systemd-tmpfiles --clean
sudo systemd-tmpfiles --remove
rm /var/log/* -rf
apt --autoremove purge rsyslog

# Limit journal size - add to /etc/systemd/journald.conf:
SystemMaxUse=64M
Storage=volatile
RuntimeMaxUse=64M
ForwardToConsole=no
ForwardToWall=no

# Expand filesystem if SD card > 16GB
raspi-config --expand-rootfs
reboot
```

---

### Driver Loading Problems

#### Issue: Driver Fails to Load - Module Version Mismatch

**Symptoms:**
```
insmod: ERROR: could not insert module sdr.ko: Invalid module format
dmesg: disagrees about version of symbol module_layout
```

**Cause:** Driver compiled for different kernel version.

**Solution:**
```bash
# Check kernel version
uname -r

# On build machine, ensure kernel source matches
cd openwifi/user_space
./prepare_kernel.sh $XILINX_DIR ARCH_BIT

# Rebuild all drivers
cd ../driver
./make_all.sh $XILINX_DIR ARCH_BIT

# Copy to board
scp `find ./ -name \*.ko` root@192.168.10.122:openwifi/
```

#### Issue: xilinx_dma.ko Load Failure

**Symptoms:**
```
insmod: ERROR: could not insert module xilinx_dma.ko
```

**Diagnostic:**
```bash
# Check dmesg
dmesg | tail -50

# Verify device tree
ls /sys/devices/platform/fpga-axi@0/
```

**Solution:**
- Verify FPGA image is loaded
- Check device tree matches FPGA design
- Ensure correct board configuration in BOOT partition

#### Issue: ad9361 Driver Not Found

**Symptoms:**
```
ERROR: could not find ad9361 device
```

**Solution:**
```bash
# ad9361 driver should be built into kernel
# Verify AD9361 is detected:
ls /sys/bus/iio/devices/
# Should show iio:device0, iio:device1, etc.

# Check AD9361 initialization
dmesg | grep ad9361

# If not found, check RF board connection
# Power cycle the board
```

#### Issue: mac80211 Module Issues

**Symptoms:**
```
ERROR: could not insert module sdr.ko: Unknown symbol in module
```

**Solution:**
```bash
# Ensure mac80211 is loaded
sudo modprobe mac80211
lsmod | grep mac80211

# Load openwifi modules in correct order:
sudo insmod xilinx_dma.ko
sudo modprobe mac80211
sudo insmod sdr.ko
```

#### Issue: wgd.sh Cannot Load Driver

**Symptoms:**
```
./wgd.sh
sdr is not loaded!
```

**Diagnostic:**
```bash
# Check dmesg for errors
dmesg | tail -100

# Verify all .ko files present
ls -la *.ko

# Check permissions
ls -la *.ko
# Should be readable
```

**Solution:**
```bash
# Manual load to see error
sudo insmod xilinx_dma.ko
sudo modprobe mac80211
sudo insmod sdr.ko

# If FPGA not loaded, load it first:
./load_fpga_img.sh system_top.bit.bin

# Then reload driver
./wgd.sh
```

---

### Network Connectivity Issues

#### Issue: sdr0 Interface Does Not Come Up

**Symptoms:**
```
ifconfig sdr0
sdr0: error fetching interface information: Device not found
```

**Diagnostic:**
```bash
# Check if driver loaded
lsmod | grep sdr

# Check dmesg for errors
dmesg | grep -i "sdr\|openwifi"

# Check mac80211 registration
iw dev
```

**Solution:**
```bash
# Reload driver
cd ~/openwifi
./wgd.sh

# Check if interface appears
iw dev
ifconfig -a

# Bring up interface
ifconfig sdr0 up
```

#### Issue: Cannot Connect as Client to AP

**Symptoms:**
- wpa_supplicant fails to connect
- Authentication timeout

**Diagnostic:**
```bash
# Check interface is up
ifconfig sdr0 up

# Test scan
iw dev sdr0 scan | grep SSID

# Check wpa_supplicant log
wpa_supplicant -i sdr0 -c wpa-connect.conf -dd
```

**Solution:**

1. **Check channel compatibility:**
```bash
# OpenWiFi only supports OFDM rates (no 11b)
# Ensure AP is on supported channel
iw list | grep -A 15 "Frequencies:"
```

2. **Verify wpa-connect.conf:**
```bash
# Example configuration
network={
    ssid="YourSSID"
    psk="YourPassword"
    key_mgmt=WPA-PSK
}
```

3. **Check frequency restrictions:**
```bash
# Remove any frequency restrictions
./set_restrict_freq.sh 0
```

4. **For 11b incompatibility:**
```bash
# Use patched wpa_supplicant on client side
cd openwifi/user_space
sudo apt-get install libssl1.0-dev
./build_wpa_supplicant_wo11b.sh
```

#### Issue: Client Cannot Get IP from OpenWiFi AP

**Symptoms:**
- Client connects but no IP assigned
- DHCP timeout

**Solution:**
```bash
# On board, restart DHCP server
service isc-dhcp-server restart

# Check DHCP server status
systemctl status isc-dhcp-server

# Verify DHCP configuration
cat /etc/dhcp/dhcpd.conf

# Check network interface
ifconfig sdr0
# Should have IP 192.168.13.1
```

#### Issue: DNS Resolution Failure

**Symptoms:**
```
ping: unknown host google.com
```

**Solution:**
```bash
# Change nameserver in /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# Configure NAT on PC for internet access
# On PC:
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o NICY -j MASQUERADE
sudo ip route add 192.168.13.0/24 via 192.168.10.122 dev ethX
# ethX: PC NIC to board, NICY: PC NIC to internet
```

#### Issue: Low Throughput / Poor Performance

**Symptoms:**
- iperf shows < 10 Mbps
- Packet loss > 10%

**Diagnostic:**
```bash
# Check current rate adaptation
./tx_stat_show.sh
./rx_stat_show.sh

# Check RSSI
./rssi_openwifi_show.sh
./rssi_ad9361_show.sh

# Monitor statistics
./stat_enable.sh
./rx_stat_show.sh
./tx_stat_show.sh
```

**Solution:**

1. **Enable AMPDU aggregation:**
```bash
./wgd.sh 1  # Enable test_mode with AMPDU
```

2. **Check TX power:**
```bash
./sdrctl dev sdr0 get reg rf 0
# Increase if needed (default 0dB attenuation)
```

3. **Optimize RX gain:**
```bash
# Check current AGC gain
./stat_enable.sh
./rx_gain_show.sh
# Adjust if needed
```

4. **Check channel conditions:**
```bash
# Monitor channel in real-time
./monitor_ch.sh sdr0 44  # Channel 44 (5GHz)
tcpdump -i sdr0 -n
```

---

### RF Problems

#### Issue: No RF Output / Cannot Detect Signal

**Symptoms:**
- Spectrum analyzer shows no signal
- No packets transmitted

**Diagnostic:**
```bash
# Check TX path is enabled
./set_tx_lo.sh
./set_tx_port.sh

# Check TX power configuration
./sdrctl dev sdr0 get reg rf 0

# Check AD9361 status
cd /sys/bus/iio/devices/iio:device1/
cat in_voltage_rf_bandwidth
cat out_altvoltage0_TX_LO_frequency
```

**Solution:**

1. **Enable TX LO:**
```bash
./set_tx_lo.sh 1
./set_tx_port.sh 1

# Or disable automatic control:
./sdrctl dev sdr0 set reg xpu 13 1
```

2. **Check antenna selection:**
```bash
# Set TX antenna
./sdrctl dev sdr0 set reg drv_tx 4 0  # TX1
# or
./sdrctl dev sdr0 set reg drv_tx 4 1  # TX2
```

3. **Verify frequency tuning:**
```bash
# Check current frequency
./sdrctl dev sdr0 get reg rf 1  # TX freq
./sdrctl dev sdr0 get reg rf 5  # RX freq
```

#### Issue: High TX EVM / Spectrum Mask Failure

**Symptoms:**
- Poor signal quality
- Failed modulation tests

**Diagnostic:**
```bash
# Check TX digital gain
./sdrctl dev sdr0 get reg tx_intf 13

# Check TX I/Q sample rate
./sdrctl dev sdr0 get reg tx_intf 10
```

**Solution:**

1. **Adjust TX digital gain:**
```bash
# Try different values (around 1000-3000 range typical)
./sdrctl dev sdr0 set reg tx_intf 13 2500
# WARNING: Too high value hurts EVM
```

2. **Check calibration:**
```bash
# If frequency change > 100MHz, recalibration triggered
# Force calibration by changing frequency:
iw dev sdr0 set freq 5180
sleep 2
iw dev sdr0 set freq 5220
```

#### Issue: Poor RX Sensitivity

**Symptoms:**
- Cannot receive weak signals
- High packet error rate

**Diagnostic:**
```bash
# Check RX gain mode
# Should be in AGC auto mode normally

# Check receiver sensitivity threshold
./sdrctl dev sdr0 get reg drv_rx 0
```

**Solution:**

1. **Verify AGC is enabled:**
```bash
./set_rx_gain_auto.sh
```

2. **Adjust receiver sensitivity:**
```bash
# Lower threshold for better sensitivity (careful of noise)
./sdrctl dev sdr0 set reg drv_rx 0 90
# Default threshold around 70 (-70dBm)
```

3. **Check power trigger threshold:**
```bash
# Check FPGA RX trigger
./sdrctl dev sdr0 get reg rx 2
# Adjust if needed (bit10-0 for trigger level)
```

4. **Check antenna:**
```bash
# Switch RX antenna
./sdrctl dev sdr0 set reg drv_rx 4 0  # RX1
# or
./sdrctl dev sdr0 set reg drv_rx 4 1  # RX2
```

#### Issue: Frequency Offset / Timing Issues

**Symptoms:**
- Packet decode failures
- Poor CSI quality

**Diagnostic:**
```bash
# Capture IQ for frequency offset analysis
cd ~/openwifi
insmod side_ch.ko iq_len_init=8187
./side_ch_ctl wh3h01
./side_ch_ctl g

# On PC:
cd openwifi/user_space/side_ch_ctl_src
python3 iq_capture_freq_offset.py 8187
```

**Solution:**

1. **Override frequency offset estimation:**
```bash
# If Python calculated offset differs from FPGA
./receiver_phase_offset_override.sh VALUE
# VALUE from Python analysis
```

2. **Check AD9361 reference clock:**
```bash
# Verify crystal frequency
cat /sys/bus/iio/devices/iio:device1/xo_correction
```

#### Issue: Self-Interference / TX Leakage

**Symptoms:**
- Cannot receive while transmitting
- AGC saturation

**Solution:**

1. **Verify TX/RX isolation:**
```bash
# RX should be muted during TX (default behavior)
./sdrctl dev sdr0 get reg xpu 1
# bit0 should be 0 for auto control

# To unmute RX during TX (for self-IQ capture):
./sdrctl dev sdr0 set reg xpu 1 1
```

2. **Cable connection caution:**
   - When connecting two boards via cable
   - Use high TX attenuation (20dB+):
```bash
# Set before connecting cable!
./sdrctl dev sdr0 set reg rf 0 20000
# Or use init_tx_att parameter
insmod sdr.ko init_tx_att=20000
```

---

### Performance Issues

#### Issue: Viterbi Decoder Halts (Xilinx Evaluation License)

**Symptoms:**
- After ~2 hours, reception stops
- Register 20 value doesn't change

**Diagnostic:**
```bash
# Check if decoder is stuck
watch -n 1 './sdrctl dev sdr0 get reg rx 20'
# If value never changes, decoder is halted
```

**Solution:**
```bash
# Method 1: Reload FPGA only
./load_fpga_img.sh system_top.bit.bin
sleep 2
./wgd.sh

# Method 2: Full driver/FPGA reload
./wgd.sh

# Method 3: Power cycle board
```

#### Issue: High CPU Usage

**Symptoms:**
- CPU at 100%
- System sluggish

**Diagnostic:**
```bash
top
# Check which process consuming CPU

# Check interrupt rate
cat /proc/interrupts | grep sdr
watch -n 1 'cat /proc/interrupts | grep sdr'
```

**Solution:**

1. **Reduce packet rate:**
```bash
# In monitor mode, filter packets
./monitor_ch.sh sdr0 44
# Add BPF filter
tcpdump -i sdr0 'not type ctl'  # Filter control packets
```

2. **Disable unnecessary printing:**
```bash
./sdrctl dev sdr0 set reg drv_tx 7 1  # Only errors
./sdrctl dev sdr0 set reg drv_rx 7 1
```

3. **Check for packet storms:**
```bash
# Monitor packet rate
ifconfig sdr0
# Watch RX packets counter
```

#### Issue: Buffer Overflow / DMA Errors

**Symptoms:**
```
dmesg: DMA timeout
dmesg: FPGA queue full
```

**Diagnostic:**
```bash
# Check FPGA queue status
./sdrctl dev sdr0 get reg tx_intf 21  # no_room_flag
./sdrctl dev sdr0 get reg tx_intf 26  # queue length

# Check TX priority queue stats
./tx_prio_queue_show.sh
```

**Solution:**

1. **Adjust queue thresholds:**
```bash
# Increase FIFO almost full threshold
./sdrctl dev sdr0 set reg tx_intf 11 100
```

2. **Reduce traffic load:**
```bash
# Limit rate
tc qdisc add dev sdr0 root tbf rate 10mbit burst 32kbit latency 400ms
```

#### Issue: Packet Loss / Retransmissions

**Diagnostic:**
```bash
./stat_enable.sh
./tx_stat_show.sh
./rx_stat_show.sh

# Check retransmission statistics
# tx_data_pkt_need_ack_num_retx shows retransmission distribution
```

**Solution:**

1. **Adjust CCA threshold:**
```bash
# Check current threshold
./set_lbt_th.sh
# Adjust (e.g., -70dBm)
./set_lbt_th.sh 70
```

2. **Tune CSMA parameters:**
```bash
# Disable NAV/DIFS/CW for testing
./nav_disable.sh 1
./difs_disable.sh 1
./cw_disable.sh 1

# Re-enable for normal operation
./nav_disable.sh 0
./difs_disable.sh 0
./cw_disable.sh 0
```

3. **Adjust retry limit:**
```bash
# In driver openwifi_tx(), modify:
# retry_limit_hw_value = ...
# Or use FPGA register override
./sdrctl dev sdr0 set reg xpu 11 9  # bit3=1, bit2-0=1 (max 1 retx)
```

---

## Diagnostic Procedures

### Log Analysis

#### Enable Kernel Message Logging

```bash
# Enable dmesg output from driver
./sdrctl dev sdr0 set reg drv_tx 7 3  # error + regular unicast
./sdrctl dev sdr0 set reg drv_rx 7 3

# Bit meanings:
# bit0: error messages
# bit1: regular messages for unicast
# bit2: regular messages for broadcast
# bit3: queue stop/wake-up messages

# View logs
dmesg | tail -100
dmesg -w  # Follow mode

# Save logs
dmesg > /tmp/openwifi_debug.log
```

#### Understanding TX Log Messages

Example:
```
sdr,sdr openwifi_tx: 70B RC0 10M FC0040 DI0000 ADDRffffffffffff/6655443322aa/ffffffffffff flag4001201e QoS00 SC20_1 retr1 ack0 prio0 q0 wr19 rd18
```

Interpretation:
- **70B**: Packet size (70 bytes)
- **RC0**: Rate control flag (0 = auto)
- **10M**: Rate (1Mbps, converted to 6M for OFDM)
- **FC0040**: Frame Control (type/subtype/flags)
- **ADDR**: addr1/addr2/addr3 (target/source/BSSID)
- **SC20_1**: Sequence number 20, set by driver
- **retr1**: No retransmission needed (retr6 = max 6 attempts)
- **ack0**: No ACK needed (ack1 = needs ACK)
- **prio0**: Priority queue 0 (VO)
- **q0**: FPGA queue 0
- **wr19 rd18**: Write/read index

#### Understanding TX Interrupt Messages

Example:
```
sdr,sdr openwifi_tx_interrupt: tx_result [nof_retx 1 pass 1] SC20 prio0 q0 wr20 rd19 num_slot0 cw0
```

Interpretation:
- **nof_retx 1**: Total transmissions = 1
- **pass 1**: ACK received (0 = failed)
- **SC20**: Sequence number
- **num_slot**: Backoff slots waited
- **cw0**: Contention window (6 = size 64)

#### Understanding RX Log Messages

Example:
```
sdr,sdr openwifi_rx: 270B ht0aggr0/0 sgi0 240M FC0080 DI0000 ADDRffffffffffff/00c88b113f5f/00c88b113f5f SC2133 fcs1 buf_idx10 -78dBm
```

Interpretation:
- **270B**: Packet size
- **ht0**: Legacy (non-HT) packet
- **aggr0/0**: Not AMPDU / not last in AMPDU
- **sgi0**: Normal GI (1 = short GI)
- **240M**: Rate 24Mbps
- **FC0080**: Frame Control
- **SC2133**: Sequence number
- **fcs1**: FCS valid (0 = CRC error)
- **buf_idx10**: DMA buffer index
- **-78dBm**: Signal strength

#### System Logs

```bash
# Check system logs
journalctl -u isc-dhcp-server  # DHCP server
journalctl -u hostapd          # hostapd (if using systemd)
journalctl -xe                 # Recent system errors

# Kernel ring buffer
dmesg -T  # With timestamps

# Network manager logs
journalctl -u NetworkManager
```

---

### Register Reading

#### Read All Key Registers

```bash
# Create diagnostic register dump script
cat > /tmp/dump_registers.sh << 'EOF'
#!/bin/bash
echo "=== Driver Registers ==="
echo "TX rate control:"
./sdrctl dev sdr0 get reg drv_tx 0
echo "RX sensitivity threshold:"
./sdrctl dev sdr0 get reg drv_rx 0
echo "LBT threshold:"
./sdrctl dev sdr0 get reg drv_xpu 0

echo ""
echo "=== RF Registers ==="
echo "TX attenuation:"
./sdrctl dev sdr0 get reg rf 0
echo "TX frequency:"
./sdrctl dev sdr0 get reg rf 1
echo "RX frequency:"
./sdrctl dev sdr0 get reg rf 5

echo ""
echo "=== FPGA XPU Registers ==="
echo "Band/Channel:"
./sdrctl dev sdr0 get reg xpu 4
echo "CCA threshold:"
./sdrctl dev sdr0 get reg xpu 8
echo "RSSI/channel state:"
./sdrctl dev sdr0 get reg xpu 57
echo "TSF low:"
./sdrctl dev sdr0 get reg xpu 58
echo "TSF high:"
./sdrctl dev sdr0 get reg xpu 59
echo "Git revision:"
./sdrctl dev sdr0 get reg xpu 63

echo ""
echo "=== RX Registers ==="
echo "RX trigger threshold:"
./sdrctl dev sdr0 get reg rx 2
echo "FFT window shift:"
./sdrctl dev sdr0 get reg rx 5
echo "PHY state history:"
./sdrctl dev sdr0 get reg rx 20
echo "Phase offset:"
./sdrctl dev sdr0 get reg rx 21

echo ""
echo "=== TX Registers ==="
echo "Queue length:"
./sdrctl dev sdr0 get reg tx_intf 26
echo "Digital gain:"
./sdrctl dev sdr0 get reg tx_intf 13

echo ""
echo "=== RX Interface ==="
echo "Digital gain:"
./sdrctl dev sdr0 get reg rx_intf 11
EOF

chmod +x /tmp/dump_registers.sh
/tmp/dump_registers.sh > /tmp/register_dump.txt
cat /tmp/register_dump.txt
```

#### Register Reading for Specific Issues

**Check if receiver is working:**
```bash
# PHY state should change when packets arrive
watch -n 0.5 './sdrctl dev sdr0 get reg rx 20'
# Last digit should vary (not stuck at 3)
```

**Check TX queue status:**
```bash
# Monitor queue length and no_room_flag
watch -n 0.2 './sdrctl dev sdr0 get reg tx_intf 26'
```

**Check RSSI real-time:**
```bash
./rssi_openwifi_show.sh
./rssi_ad9361_show.sh
```

**Check TSF timer:**
```bash
# TSF should be incrementing
watch -n 1 './sdrctl dev sdr0 get reg xpu 58'
```

---

### Statistics Monitoring

#### Enable and View Statistics

```bash
# Enable statistics
./stat_enable.sh

# View TX statistics
./tx_stat_show.sh
# Shows:
# - tx_data_pkt_need_ack_num_total
# - tx_data_pkt_need_ack_num_total_fail
# - tx_data_pkt_need_ack_num_retx (array)
# - tx_data_pkt_mcs_realtime
# - Same for management packets

# View RX statistics
./rx_stat_show.sh
# Shows:
# - rx_data_pkt_num_total
# - rx_data_pkt_num_fail
# - rx_data_pkt_mcs_realtime
# - rx_data_pkt_fail_mcs_realtime
# - AGC gain values

# View queue statistics
./tx_prio_queue_show.sh
# Shows per-queue:
# - tx_prio_num, tx_prio_interrupt_num
# - tx_prio_stop/wakeup_num
# - tx_queue_num, tx_queue_interrupt_num

# View RX gain
./rx_gain_show.sh

# Clear statistics
./tx_stat_show.sh clear
./rx_stat_show.sh clear
./tx_prio_queue_show.sh clear
```

#### Calculate Packet Error Rate

```bash
# Send known number of packets from peer
# Then on receiver:
./rx_stat_show.sh 30000  # 30000 packets sent
# Shows PER calculation
```

#### Filter Statistics by MAC Address

```bash
# Monitor specific peer
./set_rx_target_sender_mac_addr.sh c83caf93
# For MAC: 00:80:c8:3c:af:93

# Show all (no filter)
./set_rx_target_sender_mac_addr.sh 0

# Check current filter
./set_rx_target_sender_mac_addr.sh
```

#### Monitor ACK Packets

```bash
# Enable ACK monitoring
./set_rx_monitor_all.sh

# Disable
./set_rx_monitor_all.sh 0
```

#### Continuous Monitoring Script

```bash
cat > /tmp/monitor_stats.sh << 'EOF'
#!/bin/bash
while true; do
  clear
  date
  echo "=== TX Statistics ==="
  ./tx_stat_show.sh
  echo ""
  echo "=== RX Statistics ==="
  ./rx_stat_show.sh
  echo ""
  echo "=== Queue Status ==="
  ./tx_prio_queue_show.sh
  sleep 2
done
EOF

chmod +x /tmp/monitor_stats.sh
/tmp/monitor_stats.sh
```

---

### IQ/CSI Capture for Debugging

#### Capture IQ Samples for Analysis

**Basic IQ Capture:**
```bash
# On board:
cd ~/openwifi
./wgd.sh
./monitor_ch.sh sdr0 44  # Or active channel

# Load side_ch module with IQ capture
insmod side_ch.ko iq_len_init=8187
# For small FPGA (zed, adrv9364z7020): iq_len_init=4095

# Configure IQ capture
./side_ch_ctl wh3h01  # Enable IQ capture from AD9361

# For small FPGA only:
./side_ch_ctl wh11d4094  # Set pre-trigger length

# Start capture
./side_ch_ctl g

# On PC:
cd openwifi/user_space/side_ch_ctl_src
python3 iq_capture.py 8187
# For small FPGA: python3 iq_capture.py 4095
```

**Frequency Offset Analysis:**
```bash
# On board:
insmod side_ch.ko iq_len_init=1500
./side_ch_ctl wh11d1497  # Pre-trigger length
./side_ch_ctl wh8d8      # Trigger on long preamble
./side_ch_ctl g0         # Start capture

# On PC:
python3 iq_capture_freq_offset.py 1500
# Compares FPGA vs Python frequency offset estimation
```

**Trigger Conditions for IQ Capture:**
```bash
# Set trigger condition:
./side_ch_ctl wh8dN

# N values:
# 0: FCS result (any)
# 1: FCS pass
# 2: FCS fail
# 3: TX IQ start
# 4: SIGNAL pass
# 5: SIGNAL fail
# 8: Long preamble detected
# 9: Short preamble detected
# 10: RSSI above threshold
# 12: AGC lock to unlock
# 13: AGC unlock to lock
# 22: TX started (needs ACK)
# 23: TX done (needs ACK)

# Set RSSI threshold for trigger 10/11:
./side_ch_ctl wh9d500  # Threshold 500

# Set AGC threshold for trigger 14/15:
./side_ch_ctl wh10d50  # Threshold 50
```

**FPGA Loopback IQ Capture:**
```bash
# Internal FPGA loopback test
insmod side_ch.ko iq_len_init=8187
./sdrctl dev sdr0 set reg xpu 13 1  # TX LO always on
./side_ch_ctl wh11d100  # Pre-trigger 100 samples
./side_ch_ctl wh8d3     # Trigger on TX start
./side_ch_ctl wh5h4     # FPGA internal loopback
./side_ch_ctl g0

# On PC:
python3 iq_capture.py 8187

# On board, send test IQ:
./tx_intf_iq_data_to_sysfs.sh
./tx_intf_iq_send.sh
```

#### Capture CSI for Channel Analysis

**Basic CSI Capture:**
```bash
# On board:
cd ~/openwifi
./wgd.sh
./monitor_ch.sh sdr0 11  # Busy channel

# Load side_ch for CSI (no iq_len_init parameter!)
insmod side_ch.ko
./side_ch_ctl g

# On PC:
cd openwifi/user_space/side_ch_ctl_src
python3 side_info_display.py
# Shows frequency offset, channel response, equalizer
```

**Filter CSI by Packet Conditions:**
```bash
# Capture only from specific source MAC
./side_ch_ctl wh1h4001  # Enable addr2 match
./side_ch_ctl wh7h01ece28f  # Last 32 bits of MAC
./side_ch_ctl g

# Capture specific frame control
./side_ch_ctl wh1h1001  # Enable FC match
./side_ch_ctl wh5hFC_VALUE  # FC in hex
./side_ch_ctl g

# Capture specific target address (addr1)
./side_ch_ctl wh1h2001  # Enable addr1 match
./side_ch_ctl wh6hADDR  # Last 32 bits
./side_ch_ctl g

# Combined conditions (FC + addr1):
./side_ch_ctl wh1h3001
./side_ch_ctl g
```

**Adjust Capture Interval:**
```bash
# Default 100ms interval
./side_ch_ctl g

# Custom interval (N ms):
./side_ch_ctl g500  # 500ms interval
```

**Configure Number of Equalizer Outputs:**
```bash
# Load with fewer equalizer samples
insmod side_ch.ko num_eq_init=3

# Update Python script:
python3 side_info_display.py 3

# Update MATLAB script:
# Set num_eq = 3 in test_side_info_file_display.m
```

#### Post-Processing Captured Data

**MATLAB Analysis:**
```matlab
% For IQ data
cd openwifi/user_space/side_ch_ctl_src
% Edit iq_len in test_iq_file_display.m
test_iq_file_display

% For CSI data
% Edit num_eq in test_side_info_file_display.m
test_side_info_file_display

% SNR analysis from IQ
show_iq_snr(mat_file_name)
% Identify middle value from plot
show_iq_snr(mat_file_name, middle_value)
```

**Map IQ/CSI to WiFi Packets:**
- Capture simultaneously with tcpdump/wireshark
- Match using TSF timestamp
- TSF is same 64-bit timer for both
- Example:
```bash
# Terminal 1 - Packet capture
tcpdump -i sdr0 -w /tmp/packets.pcap

# Terminal 2 - IQ/CSI capture
./side_ch_ctl g
# On PC: python3 iq_capture.py 8187

# Analyze timestamps in both captures
```

---

## Known Issues

### Network Issues in Quick Start (Ubuntu 22.04)

**Problem:** Cannot SSH to board after first boot.

**Solution:**
1. Delete `/etc/network/interfaces.new` on SD card
2. Use UART console to debug boot process
3. Check PC network configuration (should have 192.168.10.1)

### EXT4-fs Error on Rootfs

**Problem:** Boot fails with EXT4 filesystem errors.

**Solution:**
1. Try different SD card flashing tool:
   - gnome-disks
   - Startup Disk Creator
   - win32diskimager
2. Use different SD card (Class 10)
3. For ZCU102: Add special device tree settings (see Boot Failures section)

### ANTSDR E200 UART Console Issue

**Problem:** Cannot see UART console on `/dev/ttyUSB0` or `/dev/ttyCH341USB0`.

**Solution:**
```bash
# Remove conflicting driver
sudo apt remove brltty
```

### Client Cannot Get IP from DHCP

**Problem:** Client connects to openwifi AP but no IP assigned.

**Solution:**
```bash
# On board:
service isc-dhcp-server restart

# Re-connect from client
```

### Disk Full - No Space Left

**Problem:** System logs fill disk.

**Solution:**
```bash
systemd-tmpfiles --clean
sudo systemd-tmpfiles --remove
rm /var/log/* -rf
apt --autoremove purge rsyslog

# Add to /etc/systemd/journald.conf:
# SystemMaxUse=64M
# Storage=volatile
# RuntimeMaxUse=64M
```

### DNS Resolution Failure

**Problem:** Cannot resolve hostnames.

**Solution:**
```bash
# Change DNS server in /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

### FMCOMMS Board EEPROM Issue

**Problem:** Linux crashes with FMCOMMS board on ZCU102.

**Solution:** Reprogram EEPROM (see Boot Failures section).

### SPI Flash Boot Issue

**Problem:** Board boots with wrong SPI flash configuration.

**Solution:** Reset U-Boot environment to defaults (see Boot Failures section).

### Viterbi Decoder Halt (Eval License)

**Problem:** After ~2 hours, reception stops (Xilinx eval license limit).

**Detection:**
```bash
./sdrctl dev sdr0 get reg rx 20
# If value never changes, decoder halted
```

**Solution:** Reload FPGA or power cycle board.

### 11b Incompatibility

**Problem:** Cannot connect to 802.11b devices or APs.

**Reason:** OpenWiFi only supports OFDM (no 11b DSSS/CCK).

**Solutions:**
- **As AP:** Use hostapd-openwifi.conf with supported_rates/basic_rates configured for OFDM only
- **As Client:** Use patched wpa_supplicant:
```bash
cd openwifi/user_space
sudo apt-get install libssl1.0-dev
./build_wpa_supplicant_wo11b.sh
```

### ANTSDR RF Switch Fixed Range

**Problem:** ANTSDR RF switch fixed in 3-6GHz range, isolates <3GHz.

**Workaround:** Hardware modification or future device tree control.

---

## Board-Specific Issues

### ZC706 / ZC702

**FPGA License:** ZC706 needs Vivado license; ZC702 does not.

**Common Issues:**
- Ensure FMCOMMS board EEPROM is valid
- Check FMC connector seating

### ZED Board

**Small FPGA Limitations:**
- IQ capture: max 4095 samples
- Pre-trigger: max 4094

**Memory:** 512MB RAM - may need to limit logs.

### ADRV9364Z7020 / ADRV9361Z7035

**TX Power Issue (5GHz):**
- ADRV9361Z7035 has ultra-low TX power in 5GHz
- **Solution:** Move very close to client in 5GHz, or use 2.4GHz

**FPGA Size:**
- ADRV9364Z7020: Small (same limits as ZED)
- ADRV9361Z7035: Large (needs license)

### ANTSDR / ANTSDR E200

**RF Switch:** Fixed at high band (3-6GHz), isolates <3GHz.

**E200 Ethernet:** Ethernet on PL side (different from standard).

**UART Issue:** Remove `brltty` package if UART not working.

### SDRPI

**Form Factor:** Raspberry Pi size, limited heat dissipation.

**Cooling:** Ensure adequate cooling for continuous operation.

### ZCU102 (Zynq MPSoC)

**Boot Issues:** May need device tree modifications (see Boot Failures).

**64-bit:** Use ARCH_BIT=64 for compilation.

**License:** Requires Vivado license.

### NeptuneSDR / LibreSDR

**Status:** Unofficial support - community driven.

**Differences:** May have board-specific device tree requirements.

---

## Recovery Procedures

### FPGA Reload

#### Method 1: Use load_fpga_img.sh (Preferred)

```bash
cd ~/openwifi

# Load FPGA image
./load_fpga_img.sh system_top.bit.bin

# Verify loading
dmesg | tail -20
# Should show FPGA configuration success

# Reload driver
./wgd.sh
```

#### Method 2: Use wgd.sh with FPGA Image

```bash
# Place system_top.bit.bin in same directory as wgd.sh
cd ~/openwifi
ls -la system_top.bit.bin

# Load both FPGA and driver
./wgd.sh

# wgd.sh auto-detects and loads FPGA if .bit.bin present
```

#### Method 3: Load from Different Directory

```bash
# Store FPGA variants in different directories
mkdir -p ~/openwifi_v1
cp system_top.bit.bin ~/openwifi_v1/
cp *.ko ~/openwifi_v1/

# Load specific variant
cd ~/openwifi
./wgd.sh ~/openwifi_v1/
```

#### Method 4: Load from Package File

```bash
# Use packaged driver+FPGA
./wgd.sh ./drv_and_fpga_v1.tar.gz

# Package will be unpacked and loaded automatically
```

#### Verify FPGA Loading

```bash
# Check FPGA git revision
./sdrctl dev sdr0 get reg xpu 63
./sdrctl dev sdr0 get reg rx 31
./sdrctl dev sdr0 get reg tx 20

# Check if FPGA modules responding
./sdrctl dev sdr0 get reg xpu 58  # TSF should increment
./sdrctl dev sdr0 get reg rx 20   # RX state should vary
```

---

### Driver Restart

#### Quick Driver Reload

```bash
cd ~/openwifi
./wgd.sh

# Or with test_mode:
./wgd.sh 1  # Enable AMPDU
```

#### Manual Driver Reload

```bash
# Unload modules
sudo rmmod sdr
sudo rmmod xilinx_dma

# Reload
sudo insmod xilinx_dma.ko
sudo modprobe mac80211
sudo insmod sdr.ko

# Verify
lsmod | grep sdr
dmesg | tail -50
```

#### Reload with Debug Enabled

```bash
# Unload first
sudo rmmod sdr

# Load with debug
sudo insmod sdr.ko test_mode=1
# test_mode=1 enables AMPDU

# Enable dmesg printing
./sdrctl dev sdr0 set reg drv_tx 7 3
./sdrctl dev sdr0 set reg drv_rx 7 3

# Monitor
dmesg -w
```

#### Driver Reload Script for Testing

```bash
cat > /tmp/reload_driver.sh << 'EOF'
#!/bin/bash
set -x
cd ~/openwifi

# Unload
sudo rmmod sdr 2>/dev/null
sudo rmmod xilinx_dma 2>/dev/null
sleep 1

# Reload
sudo insmod xilinx_dma.ko
sudo modprobe mac80211
sudo insmod sdr.ko $@

# Check
lsmod | grep sdr
if [ $? -eq 0 ]; then
  echo "Driver loaded successfully"
  dmesg | tail -20
else
  echo "Driver load FAILED"
  dmesg | tail -50
  exit 1
fi
EOF

chmod +x /tmp/reload_driver.sh

# Use:
/tmp/reload_driver.sh
# or with arguments:
/tmp/reload_driver.sh test_mode=1
```

---

### Full System Recovery

#### Level 1: Soft Reset (No Reboot)

```bash
# Stop all services
killall hostapd wpa_supplicant dhclient 2>/dev/null

# Reload FPGA and driver
cd ~/openwifi
./wgd.sh

# Restart services
./fosdem.sh  # For AP mode
# or
./wgd.sh && route del default gw 192.168.10.1 && \
  wpa_supplicant -i sdr0 -c wpa-connect.conf -B && \
  dhclient sdr0
```

#### Level 2: Network Stack Reset

```bash
# Remove interface
ifconfig sdr0 down

# Reload driver
cd ~/openwifi
sudo rmmod sdr
sudo rmmod xilinx_dma
./wgd.sh

# Reconfigure
./fosdem.sh
```

#### Level 3: Complete Driver/FPGA Reload

```bash
# Stop everything
killall hostapd wpa_supplicant dhclient dnsmasq 2>/dev/null
ifconfig sdr0 down 2>/dev/null

# Unload all
sudo rmmod sdr side_ch 2>/dev/null
sudo rmmod xilinx_dma 2>/dev/null

# Reload FPGA
cd ~/openwifi
./load_fpga_img.sh system_top.bit.bin
sleep 2

# Reload driver
./wgd.sh

# Restart services
./fosdem.sh
```

#### Level 4: System Reboot

```bash
# Clean reboot
sudo sync
sudo reboot

# After boot:
cd ~/openwifi
./wgd.sh
./fosdem.sh
```

#### Level 5: SD Card Reflash

**When needed:**
- Corrupted filesystem
- Cannot boot
- Persistent unexplained issues

**Procedure:**
1. Download latest image from openwifi repo
2. Flash to SD card using appropriate tool
3. Configure BOOT partition for your board
4. Boot and run setup_once.sh

```bash
# After first boot:
ssh root@192.168.10.122
cd openwifi
./setup_once.sh
# Reboot
sudo reboot

# After reboot:
cd openwifi
./wgd.sh
./fosdem.sh
```

#### Emergency UART Access

**If SSH not working:**
1. Connect UART cable to board
2. Open serial terminal on PC:
```bash
screen /dev/ttyUSB0 115200
# or
minicom -D /dev/ttyUSB0 -b 115200
```
3. Power cycle board
4. Watch boot messages for errors
5. Login via UART (root/openwifi)
6. Debug and fix issues

**Common UART fixes:**
```bash
# Fix network
ifconfig eth0 192.168.10.122 netmask 255.255.255.0 up

# Fix permissions
chmod +x ~/openwifi/*.sh

# Check disk space
df -h
# Clean if needed (see "No space left" issue)

# Check services
systemctl status isc-dhcp-server
systemctl status hostapd
```

---

## Debug Techniques

### Kernel Debugging

#### Enable Verbose Driver Output

```bash
# Maximum verbosity
./sdrctl dev sdr0 set reg drv_tx 7 15  # All messages
./sdrctl dev sdr0 set reg drv_rx 7 15

# Monitor in real-time
dmesg -wT

# Save to file
dmesg > /tmp/openwifi_kernel_debug.log

# Filter for specific events
dmesg | grep -i "openwifi_tx:"
dmesg | grep -i "openwifi_rx:"
dmesg | grep -i "openwifi_tx_interrupt:"
dmesg | grep -i "WARNING"
```

#### Trace Specific Packet

```bash
# Enable unicast printing
./sdrctl dev sdr0 set reg drv_tx 7 3
./sdrctl dev sdr0 set reg drv_rx 7 3

# Send specific packet (known MAC/sequence)
# Watch for sequence number in logs
dmesg -w | grep "SC[0-9]"
```

#### Debug Rate Adaptation

```bash
# Force specific rate
./sdrctl dev sdr0 set reg drv_tx 0 8  # 24Mbps non-HT
./sdrctl dev sdr0 set reg drv_tx 1 8  # 39Mbps HT

# Check what rate is actually used
./stat_enable.sh
./tx_stat_show.sh
# Check tx_data_pkt_mcs_realtime

# Re-enable Linux control
./sdrctl dev sdr0 set reg drv_tx 0 0
./sdrctl dev sdr0 set reg drv_tx 1 0
```

#### Debug AMPDU / Aggregation

```bash
# Enable AMPDU
./wgd.sh 1

# Check aggregation in RX logs
dmesg -w | grep "aggr"
# Look for: ht1aggr1/1 (HT, aggr, last in aggr)

# Check TX aggregation status
./sdrctl dev sdr0 get reg tx_intf 15
```

#### Kernel Function Tracing

```bash
# Enable function tracing (if kernel supports)
echo function > /sys/kernel/debug/tracing/current_tracer
echo openwifi_tx > /sys/kernel/debug/tracing/set_ftrace_filter
echo 1 > /sys/kernel/debug/tracing/tracing_on

# Read trace
cat /sys/kernel/debug/tracing/trace

# Disable
echo 0 > /sys/kernel/debug/tracing/tracing_on
```

#### Memory Leak Detection

```bash
# Check kernel memory
cat /proc/meminfo

# Monitor slab
watch -n 1 'cat /proc/slabinfo | head -20'

# Check for DMA leaks
cat /proc/vmallocinfo | grep dma
```

---

### FPGA Debugging

#### Check FPGA Module Status

```bash
# XPU status
./sdrctl dev sdr0 get reg xpu 57  # RSSI + channel state
./sdrctl dev sdr0 get reg xpu 58  # TSF low (should increment)
./sdrctl dev sdr0 get reg xpu 59  # TSF high

# RX status
./sdrctl dev sdr0 get reg rx 20   # PHY state (should vary)
./sdrctl dev sdr0 get reg rx 21   # Frequency offset + channel

# TX status
./sdrctl dev sdr0 get reg tx_intf 26  # Queue lengths
./sdrctl dev sdr0 get reg tx_intf 21  # no_room flags
```

#### Debug CSMA/CA State Machine

```bash
# Check CCA threshold
./sdrctl dev sdr0 get reg xpu 8

# Check channel idle detection
./sdrctl dev sdr0 get reg xpu 57
# Parse bits for idle/busy state

# Disable CSMA for testing
./nav_disable.sh 1
./difs_disable.sh 1
./cw_disable.sh 1

# Test transmission
# ...

# Re-enable
./nav_disable.sh 0
./difs_disable.sh 0
./cw_disable.sh 0
```

#### Debug Packet Filter

```bash
# Check current filter config
./sdrctl dev sdr0 get reg xpu 27

# Disable filtering (monitor mode)
./monitor_ch.sh sdr0 44

# Check BSSID filter
./sdrctl dev sdr0 get reg xpu 28  # BSSID low
./sdrctl dev sdr0 get reg xpu 29  # BSSID high
```

#### Debug TX Queue Operation

```bash
# Monitor queue in real-time
watch -n 0.1 './sdrctl dev sdr0 get reg tx_intf 26'
# Should show queue filling and draining

# Check almost-full threshold
./sdrctl dev sdr0 get reg tx_intf 11

# Check no-room flags
watch -n 0.1 './sdrctl dev sdr0 get reg tx_intf 21'
```

#### Debug RX DMA

```bash
# Check DMA control
./sdrctl dev sdr0 get reg rx_intf 5

# Check FIFO status
./sdrctl dev sdr0 get reg rx_intf 10

# Check interrupt enable
./sdrctl dev sdr0 get reg rx_intf 2
# 0 = enabled, 256 = disabled
```

#### FPGA Register Monitoring Script

```bash
cat > /tmp/monitor_fpga.sh << 'EOF'
#!/bin/bash
while true; do
  clear
  date
  echo "=== TSF Timer ==="
  echo -n "Low:  "
  ./sdrctl dev sdr0 get reg xpu 58
  echo -n "High: "
  ./sdrctl dev sdr0 get reg xpu 59

  echo ""
  echo "=== RX Status ==="
  echo -n "PHY State: "
  ./sdrctl dev sdr0 get reg rx 20
  echo -n "Phase Offset: "
  ./sdrctl dev sdr0 get reg rx 21

  echo ""
  echo "=== TX Queue ==="
  echo -n "Queue Lengths: "
  ./sdrctl dev sdr0 get reg tx_intf 26
  echo -n "No Room Flags: "
  ./sdrctl dev sdr0 get reg tx_intf 21

  echo ""
  echo "=== Channel State ==="
  ./sdrctl dev sdr0 get reg xpu 57

  sleep 0.5
done
EOF

chmod +x /tmp/monitor_fpga.sh
/tmp/monitor_fpga.sh
```

#### Use ILA for Deep FPGA Debug

For FPGA developers:

1. **Add ILA to design:**
   - Probe signals in xpu.v, tx_intf.v, rx_intf.v
   - Key signals: state machines, DMA handshakes, packet boundaries

2. **Trigger ILA from software:**
```bash
# Set trigger register
./sdrctl dev sdr0 set reg rx_intf 1 1  # Trigger bit
```

3. **Capture and analyze in Vivado**
   - See: https://github.com/open-sdr/openwifi-hw/issues/39

---

### RF Debugging

#### Check AD9361 Status

```bash
# Navigate to AD9361 IIO directory
cd /sys/bus/iio/devices/iio:device1/

# Check key parameters
cat in_voltage_rf_bandwidth
# Should be: 20000000 (20MHz for WiFi)

cat in_voltage_sampling_frequency
# Should be: 40000000 (40Msps)

cat out_voltage_sampling_frequency
# Should be: 40000000

cat out_altvoltage0_TX_LO_frequency
# Current TX frequency (Hz)

cat out_altvoltage1_RX_LO_frequency
# Current RX frequency (Hz)

# Check gain settings
cat in_voltage0_hardwaregain
cat out_voltage0_hardwaregain
```

#### Monitor RSSI

```bash
# OpenWiFi RSSI (calibrated)
./rssi_openwifi_show.sh

# AD9361 raw RSSI
./rssi_ad9361_show.sh

# Both should correlate
# Continuous monitoring:
while true; do
  echo -n "OpenWiFi: "
  ./rssi_openwifi_show.sh
  echo -n "AD9361:   "
  ./rssi_ad9361_show.sh
  sleep 0.5
done
```

#### Debug AGC

```bash
# Check AGC mode
cd /sys/bus/iio/devices/iio:device1/
cat in_voltage0_gain_control_mode
# Should be: slow_attack (AGC enabled)

# Switch to manual mode for testing
./set_rx_gain_manual.sh 30  # 30dB

# Monitor actual gain from received packets
./stat_enable.sh
./rx_gain_show.sh
# Shows AGC gain for received packets

# Note: Reported gain has offset:
# 14dB offset @ 5220MHz
# 5dB offset @ 2.4GHz

# Return to auto
./set_rx_gain_auto.sh
```

#### Test TX Output Power

**Using Spectrum Analyzer:**
1. Connect TX antenna port to spectrum analyzer
2. Use 30dB+ attenuation
3. Generate continuous transmission:
```bash
./monitor_ch.sh sdr0 44
# Use packet injection to send continuous packets
cd user_space/inject_80211
./inject_80211.sh
```

**Adjust TX attenuation:**
```bash
# Increase attenuation (reduce power)
./sdrctl dev sdr0 set reg rf 0 10000  # 10dB

# Check digital gain
./sdrctl dev sdr0 get reg tx_intf 13

# Adjust digital gain (careful!)
./sdrctl dev sdr0 set reg tx_intf 13 2000
```

#### Debug TX/RX Frequency Offset

```bash
# Capture IQ with frequency offset analysis
insmod side_ch.ko iq_len_init=1500
./side_ch_ctl wh11d1497
./side_ch_ctl wh8d8  # Trigger on preamble
./side_ch_ctl g0

# On PC:
python3 iq_capture_freq_offset.py 1500
# Shows FPGA estimated vs actual (Python) offset

# If large difference, override FPGA estimation:
./receiver_phase_offset_override.sh PYTHON_VALUE
```

#### Cable Test Between Two Boards

**Setup:**
```bash
# Board 1 (Transmitter):
cd ~/openwifi
./wgd.sh
./set_restrict_freq.sh 5220  # Prevent freq changes
./sdrctl dev sdr0 set reg rf 0 30000  # 30dB attenuation!
# Wait for AP setup
# Then connect cable TX1 -> RX1 of Board 2

# Board 2 (Receiver):
cd ~/openwifi
./wgd.sh
./set_restrict_freq.sh 5220
./set_rx_gain_manual.sh 20  # Manual gain
# Configure as client and connect
```

**WARNING:**
- Always set high TX attenuation (20dB+) before connecting cable
- Do NOT connect during initialization (AD9361 calibration has high TX power)
- Use good quality cables and attenuators

#### Debug TX LO Control

```bash
# Check if TX LO automatically controlled
./set_tx_lo.sh
./set_tx_port.sh

# Disable auto control (LO always on)
./sdrctl dev sdr0 set reg xpu 13 1

# Check with spectrum analyzer:
# LO should be always on now

# Re-enable auto control
./sdrctl dev sdr0 set reg xpu 13 0
```

#### External Reference Clock

Some boards support external reference clock for AD9361:

```bash
cd /sys/bus/iio/devices/iio:device1/
# Check if external ref supported
cat xo_correction

# May need device tree modification for external ref
```

---

## Common Error Messages

### Driver/Kernel Errors

| Error Message | Cause | Solution |
|---------------|-------|----------|
| `disagrees about version of symbol module_layout` | Kernel version mismatch | Recompile driver with matching kernel |
| `Unknown symbol in module` | Missing dependency | Load mac80211: `modprobe mac80211` |
| `could not insert module: Invalid module format` | Wrong architecture | Check ARCH_BIT (32 vs 64) |
| `DMA timeout` | FPGA not responding | Reload FPGA image |
| `WARNING: openwifi_tx wr idx out of range` | Buffer overflow | Check TX queue status, reduce load |
| `WARNING: openwifi_tx_interrupt rd idx mismatch` | Driver/FPGA sync issue | Reload driver and FPGA |

### FPGA Errors

| Error Message | Cause | Solution |
|---------------|-------|----------|
| `FPGA configuration failed` | FPGA image load failed | Check .bit.bin file, reload |
| `RX state stuck at 3` | Viterbi decoder halted | Reload FPGA (eval license timeout) |
| `TX queue full` | Packets not being transmitted | Check CSMA settings, reload driver |
| `FPGA register access timeout` | FPGA not responding | Check clocking, reload FPGA |

### Network Errors

| Error Message | Cause | Solution |
|---------------|-------|----------|
| `Authentication timeout` | No ACK from AP | Check channel, distance, tx power |
| `DHCP timeout` | DHCP server not running | `service isc-dhcp-server restart` |
| `Cannot get IP` | Network configuration issue | Check routing, NAT on PC |
| `Destination Host Unreachable` | Routing problem | Check routes and gateway |

### Build Errors

| Error Message | Cause | Solution |
|---------------|-------|----------|
| `gcc: error: unrecognized command line option` | GCC version issue | Use gcc version matching kernel |
| `ERROR: modpost: undefined symbol` | Missing kernel config | Recompile kernel with proper config |
| `fatal: Not a git repository` | Missing git info | Initialize git or ignore version |

---

## Quick Reference Commands

### Essential Status Checks

```bash
# Driver loaded?
lsmod | grep sdr

# Interface exists?
iw dev

# Interface up?
ifconfig sdr0

# Is FPGA working?
./sdrctl dev sdr0 get reg xpu 58  # TSF incrementing?
./sdrctl dev sdr0 get reg rx 20   # RX state varying?

# Current frequency?
iw dev sdr0 info | grep channel

# Statistics
./stat_enable.sh
./tx_stat_show.sh
./rx_stat_show.sh
```

### Quick Fixes

```bash
# Full reload
cd ~/openwifi && ./wgd.sh && ./fosdem.sh

# Restart DHCP
service isc-dhcp-server restart

# Clear logs
systemd-tmpfiles --clean

# Fix network on PC
sudo ip route add 192.168.13.0/24 via 192.168.10.122 dev ethX

# Enable internet sharing (PC)
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
```

### Debug Commands

```bash
# Enable debug output
./sdrctl dev sdr0 set reg drv_tx 7 3
./sdrctl dev sdr0 set reg drv_rx 7 3
dmesg -w

# Dump all registers
./sdrctl dev sdr0 get reg xpu 63  # FPGA version
./sdrctl dev sdr0 get reg drv_xpu 7  # Driver version

# Check chip state
./rssi_openwifi_show.sh
./rx_gain_show.sh

# Packet capture
tcpdump -i sdr0 -n

# IQ/CSI capture
insmod side_ch.ko iq_len_init=8187
./side_ch_ctl wh3h01 && ./side_ch_ctl g
```

### Performance Tuning

```bash
# Enable AMPDU
./wgd.sh 1

# Optimize CCA
./set_lbt_th.sh 70  # -70dBm

# Set fixed rate (testing)
./sdrctl dev sdr0 set reg drv_tx 1 8  # 39Mbps

# Adjust TX power
./sdrctl dev sdr0 set reg rf 0 0  # Full power
./sdrctl dev sdr0 set reg rf 0 10000  # 10dB attenuation
```

### Recovery Commands

```bash
# Soft recovery
cd ~/openwifi && ./wgd.sh

# Hard recovery
sudo rmmod sdr xilinx_dma
cd ~/openwifi
./load_fpga_img.sh system_top.bit.bin
./wgd.sh

# System reboot
sudo reboot

# Emergency via UART
screen /dev/ttyUSB0 115200
```

---

## Additional Resources

### Documentation

- **Main README:** `/doc/README.md`
- **Application Notes:** `/doc/app_notes/`
- **Known Issues:** `/doc/known_issue/notter.md`
- **Architecture:** `/doc/ARCHITECTURE.md`

### Online Resources

- **GitHub Repository:** https://github.com/open-sdr/openwifi
- **Hardware Repository:** https://github.com/open-sdr/openwifi-hw
- **Mailing List:** https://lists.ugent.be/wws/subscribe/openwifi
- **Image Downloads:** https://users.ugent.be/~xjiao/
- **Project Website:** https://openwifi.tech

### Getting Help

1. Check this troubleshooting guide
2. Review known issues in documentation
3. Search GitHub issues: https://github.com/open-sdr/openwifi/issues
4. Ask on mailing list
5. Open new GitHub issue with:
   - Board type
   - Software version (git revision)
   - Full error messages
   - Steps to reproduce
   - Output of diagnostic commands

---

**Document Version:** 1.0
**Last Updated:** 2025-11-21
**Maintained by:** OpenWiFi Community

For updates and corrections, please contribute to:
https://github.com/open-sdr/openwifi
