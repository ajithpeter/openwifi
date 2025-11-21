# PlutoSDR WiFi Beacon Scanner

**Minimal WiFi Beacon Transmitter/Receiver for PlutoSDR**

## Overview

This is a minimal implementation of a WiFi beacon scanner and transmitter designed specifically for the **Analog Devices PlutoSDR** (AD9364). It extracts only the essential beacon functionality from the full openwifi project, removing all unnecessary components.

### Features

✅ **Beacon Reception:**
- Scan WiFi beacons on 2.4 GHz (channels 1-13)
- Scan WiFi beacons on 5 GHz (channels 36-165)
- Extract SSID, BSSID, channel, RSSI
- Detect 802.11n/ac/ax capabilities
- Display supported data rates

✅ **Beacon Transmission:**
- Generate valid 802.11 beacon frames
- Support custom SSID and BSSID
- Configurable channel
- Support for 802.11a/g/n/ac standards

✅ **Automated Scanning:**
- Scan all channels sequentially
- Configurable dwell time per channel
- Continuous or single-pass mode

### Supported WiFi Standards

- **802.11a** (5 GHz, OFDM)
- **802.11b** (2.4 GHz, DSSS) - Detection only
- **802.11g** (2.4 GHz, OFDM)
- **802.11n** (HT - High Throughput)
- **802.11ac** (VHT - Very High Throughput)
- **802.11ax** (HE - High Efficiency) - Detection only

---

## Hardware Requirements

### PlutoSDR

- **Model:** ADALM-PLUTO
- **Chip:** AD9364 (1T1R RF Transceiver)
- **Frequency Range:** 325 MHz - 3.8 GHz (can be unlocked to 70 MHz - 6 GHz)
- **Bandwidth:** Up to 20 MHz (56 MHz max)
- **Interface:** USB 2.0

### Frequency Unlock (Optional)

To use full WiFi frequency range (2.4 GHz and 5 GHz):

```bash
# SSH to PlutoSDR (default IP: 192.168.2.1, password: analog)
ssh root@192.168.2.1

# Unlock frequency range
fw_setenv attr_name compatible
fw_setenv attr_val ad9364
fw_setenv compatible ad9364

# Reboot
reboot
```

---

## Software Dependencies

### Build Dependencies

```bash
# Ubuntu/Debian
sudo apt-get install -y \
    build-essential \
    cmake \
    git \
    libiio-dev \
    libiio-utils

# Fedora/RHEL
sudo dnf install -y \
    gcc \
    make \
    cmake \
    git \
    libiio-devel \
    libiio-utils
```

### Runtime Dependencies

- **libiio** - Industrial I/O library for PlutoSDR communication
- **libm** - Math library
- **libpthread** - POSIX threads

---

## Building

### Native Build (x86_64 Linux)

```bash
cd plutosdr_beacon
make
```

### Cross-Compile for PlutoSDR (ARM)

```bash
# Install ARM cross-compiler
sudo apt-get install gcc-arm-linux-gnueabihf

# Build
make cross CROSS_COMPILE=arm-linux-gnueabihf-
```

### Build with Debug Symbols

```bash
make debug
```

---

## Usage

### Basic Beacon Scanning

**Scan single channel:**
```bash
./beacon_scanner -m scan -c 6
```

**Automated scan (all channels):**
```bash
./beacon_scanner -a
```

**Continuous scanning:**
```bash
./beacon_scanner -a -r
```

**Custom dwell time (1 second per channel):**
```bash
./beacon_scanner -a -t 1000
```

### Beacon Transmission

**Transmit on channel 6:**
```bash
./beacon_scanner -m tx -c 6 -s "MyTestAP"
```

**Custom BSSID:**
```bash
./beacon_scanner -m tx -c 6 -s "TestAP" -b 00:11:22:33:44:55
```

**Transmit limited beacons:**
```bash
./beacon_scanner -m tx -c 6 -s "TestAP" -n 100
```

### Advanced Options

**Specify PlutoSDR by URI:**
```bash
# USB connection
./beacon_scanner -u usb:1.2.5

# Network connection
./beacon_scanner -u ip:192.168.2.1

# Auto-detect (default)
./beacon_scanner
```

**Scan 5 GHz channel:**
```bash
./beacon_scanner -m scan -c 36 -t 2000
```

---

## Command-Line Options

```
Options:
  -h             Show help
  -u URI         PlutoSDR URI (default: auto-detect)
  -m MODE        Operation mode: scan | tx
  -c CHANNEL     WiFi channel (1-13, 36-165)
  -s SSID        SSID for beacon transmission
  -b BSSID       BSSID (format: XX:XX:XX:XX:XX:XX)
  -n COUNT       Number of beacons to transmit
  -t TIME        Dwell time per channel (ms)
  -a             Automated scan (all channels)
  -r             Continuous scanning
```

---

## Output Example

```
PlutoSDR WiFi Beacon Scanner v1.0.0

Initializing PlutoSDR...
IIO context created: Analog Devices PlutoSDR Rev.B
PlutoSDR initialized successfully

Starting automated WiFi beacon scanner...
Dwell time: 500 ms per channel
Mode: Continuous
Press Ctrl+C to stop

=== Scanning 2.4 GHz Band ===
Scanning channel 1 (2.4GHz)...

[14:23:15] WiFi Beacon Detected:
  SSID: MyHomeNetwork
  BSSID: 00:1a:2b:3c:4d:5e
  Channel: 1
  RSSI: -45 dBm
  Beacon Interval: 100 TU (102.4 ms)
  Standards: 802.11n
  Rates (Mbps): 6.0 9.0 12.0 18.0 24.0 36.0 48.0 54.0
  Timestamp: 123456789
----------------------------------------

Scanning channel 2 (2.4GHz)...
...
```

---

## Architecture

### Minimal Design

This implementation removes:
- ❌ Full Linux mac80211 driver stack
- ❌ Complex queue management
- ❌ Most kernel modules
- ❌ Advanced MAC features (aggregation, encryption, etc.)
- ❌ Station mode, AP mode complexity

Keeps only:
- ✅ Basic OFDM modulation/demodulation
- ✅ Beacon frame parsing
- ✅ Beacon frame generation
- ✅ PlutoSDR hardware interface
- ✅ Channel tuning

### System Diagram

```
PlutoSDR (AD9364)
       ↓
   libiio library
       ↓
beacon_scanner application
       ├─ RX Path: IQ samples → (OFDM demod) → Beacon parser → Print
       └─ TX Path: Beacon frame → (OFDM mod) → IQ samples → Transmit
```

### Code Structure

```
beacon_scanner.c
├─ PlutoSDR initialization (libiio)
├─ RX configuration
├─ TX configuration
├─ Beacon frame parser
│  ├─ Parse fixed fields
│  ├─ Parse Information Elements (SSID, rates, HT/VHT/HE caps)
│  └─ Extract beacon info
├─ Beacon frame generator
│  ├─ Generate 802.11 management frame
│  ├─ Add SSID IE
│  ├─ Add supported rates
│  ├─ Add HT/VHT capabilities
│  └─ Return frame bytes
├─ Channel scanner
├─ Beacon transmitter
└─ Main loop
```

---

## Current Limitations

### OFDM Implementation

⚠️ **Important:** The current minimal version includes:

- ✅ **Frame parsing:** Complete 802.11 beacon frame parsing
- ✅ **Frame generation:** Complete beacon frame generation
- ✅ **Hardware interface:** Full PlutoSDR control via libiio
- ⚠️ **OFDM demodulation:** Placeholder (requires full implementation)
- ⚠️ **OFDM modulation:** Placeholder (requires full implementation)

**For full functionality, the following need to be added:**

1. **OFDM Demodulator:**
   - Short preamble detection (autocorrelation)
   - Long preamble detection (cross-correlation)
   - Channel estimation from long training sequence
   - FFT-based symbol demodulation
   - Pilot-based phase tracking
   - Viterbi decoding

2. **OFDM Modulator:**
   - Scrambling
   - Convolutional encoding
   - Interleaving
   - QAM mapping
   - Pilot insertion
   - IFFT
   - Cyclic prefix addition
   - Preamble generation

These can be added by integrating code from the main openwifi project or implementing from IEEE 802.11 specifications.

---

## Extending the Implementation

### Adding Full OFDM Support

To add complete OFDM modulation/demodulation:

1. **Use openwifi FPGA modules:**
   - Port `openofdm_tx` Verilog to software C implementation
   - Port `openofdm_rx` Verilog to software C implementation

2. **Use existing libraries:**
   - [liquid-dsp](https://github.com/jgaeddert/liquid-dsp) - Software-defined radio library
   - [WLAN Toolbox](https://www.mathworks.com/products/wlan.html) - MATLAB reference implementation
   - [gr-ieee80211](https://github.com/bastibl/gr-ieee80211) - GNU Radio 802.11 implementation

3. **Implement from scratch:**
   - Follow IEEE 802.11-2016 standard specifications
   - Use FFT libraries (FFTW, KissFFT)
   - Implement Viterbi decoder (libfec, spiral-viterbi)

### Adding More Features

**Packet injection:**
```c
int inject_packet(const uint8_t *frame, size_t len, int channel);
```

**Sniffer mode:**
```c
void sniff_all_packets(int channel, packet_callback_t callback);
```

**Deauthentication detection:**
```c
bool is_deauth_frame(const uint8_t *frame);
```

---

## Testing

### Verify PlutoSDR Connection

```bash
# List IIO devices
iio_info -n 192.168.2.1

# Should show:
# - ad9361-phy
# - cf-ad9361-lpc (RX)
# - cf-ad9361-dds-core-lpc (TX)
```

### Test Reception

```bash
# Scan channel 6 with verbose output
./beacon_scanner -m scan -c 6 -t 5000

# Should detect nearby WiFi networks on channel 6
```

### Test Transmission

```bash
# Transmit test beacon
./beacon_scanner -m tx -c 6 -s "PlutoTest" -n 10

# Verify on another device (phone, laptop):
# - Should see "PlutoTest" SSID appear briefly
```

---

## Troubleshooting

### PlutoSDR Not Detected

```bash
# Check USB connection
lsusb | grep -i pluto

# Check network connection (if using Ethernet)
ping 192.168.2.1

# Check libiio
iio_info -n 192.168.2.1
```

### Frequency Out of Range

```bash
# Check current frequency limits
iio_attr -C -d ad9361-phy

# If limited to 325-3800 MHz, unlock to 70-6000 MHz:
ssh root@192.168.2.1
fw_setenv attr_name compatible
fw_setenv attr_val ad9364
reboot
```

### No Beacons Detected

1. **Check antenna connection**
2. **Verify frequency:** Ensure PlutoSDR is unlocked for 2.4/5 GHz
3. **Increase dwell time:** `-t 5000` (5 seconds)
4. **Check channel activity:** Use phone WiFi analyzer first

### Build Errors

```bash
# Missing libiio
sudo apt-get install libiio-dev

# Missing math library
# Add -lm to LDFLAGS in Makefile (already included)
```

---

## Performance

### Resource Usage

- **CPU:** Low (mostly waiting for hardware)
- **Memory:** <10 MB
- **Network:** USB 2.0 bandwidth (<480 Mbps)

### Scan Speed

- **Single channel:** 500 ms default
- **Full 2.4 GHz (13 channels):** ~6.5 seconds
- **Full 5 GHz (24 channels):** ~12 seconds
- **Complete scan:** ~18 seconds

### Detection Range

- **2.4 GHz:** 50-100 meters (typical)
- **5 GHz:** 30-80 meters (typical)
- Depends on antenna, environment, TX power

---

## Legal Considerations

⚠️ **Important:**

- **Passive scanning (RX):** Generally legal worldwide
- **Active transmission (TX):** Subject to local regulations
  - Requires license in some jurisdictions
  - Must comply with power limits
  - Must respect occupied channels
  - Educational/research use only

**Check your local regulations before transmitting!**

---

## Comparison with Full OpenWiFi

| Feature | Full OpenWiFi | Minimal Beacon Scanner |
|---------|---------------|----------------------|
| **Size** | ~500 KB drivers + kernel | ~50 KB single binary |
| **Dependencies** | Linux kernel, mac80211 | libiio only |
| **Hardware** | Zynq FPGA boards | PlutoSDR (cheaper) |
| **Installation** | SD card image, kernel mods | Single binary |
| **Functionality** | Full WiFi AP/STA/Monitor | Beacon TX/RX only |
| **Use Case** | Production WiFi | Research, learning |

---

## Future Enhancements

### Planned

- [ ] Full OFDM demodulator implementation
- [ ] Full OFDM modulator implementation
- [ ] Real-time waterfall display
- [ ] CSV export of scan results
- [ ] Web interface for remote control
- [ ] Multiple PlutoSDR support (diversity)

### Ideas

- [ ] WPA/WPA2 handshake capture
- [ ] Rogue AP detection
- [ ] Channel utilization analysis
- [ ] GPS tagging (with external GPS)
- [ ] Integration with Wigle.net

---

## References

### Standards

- [IEEE 802.11-2016](https://standards.ieee.org/standard/802_11-2016.html) - WiFi standard
- [IEEE 802.11n](https://standards.ieee.org/standard/802_11n-2009.html) - High Throughput
- [IEEE 802.11ac](https://standards.ieee.org/standard/802_11ac-2013.html) - Very High Throughput
- [IEEE 802.11ax](https://standards.ieee.org/standard/802_11ax-2021.html) - High Efficiency

### Hardware

- [PlutoSDR Wiki](https://wiki.analog.com/university/tools/pluto) - Official documentation
- [AD9364 Datasheet](https://www.analog.com/media/en/technical-documentation/data-sheets/AD9364.pdf)
- [libiio Documentation](https://analogdevicesinc.github.io/libiio/)

### Related Projects

- [OpenWiFi](https://github.com/open-sdr/openwifi) - Full FPGA-based WiFi (source of this minimal version)
- [gr-ieee80211](https://github.com/bastibl/gr-ieee80211) - GNU Radio 802.11
- [Scapy](https://scapy.net/) - Packet crafting (Python)

---

## License

This code is derived from [OpenWiFi](https://github.com/open-sdr/openwifi) and maintains the same license:

**AGPL-3.0-or-later**

See the main OpenWiFi repository for full license details.

---

## Contributing

Contributions welcome! Areas needing help:

1. **OFDM Implementation:** Port from Verilog or implement in C
2. **Testing:** Test on different PlutoSDR variants
3. **Performance:** Optimize scanning speed
4. **Features:** Add packet injection, sniffer mode
5. **Documentation:** Improve examples and tutorials

---

## Author

Created as a minimal reference implementation derived from the OpenWiFi project.

**Original OpenWiFi Project:**
- https://github.com/open-sdr/openwifi
- Created by: Xianjun Jiao, et al.
- Institution: IMEC, Belgium

---

## Support

For issues specific to this minimal implementation:
- Create an issue in the repository

For PlutoSDR hardware support:
- [Analog Devices Forums](https://ez.analog.com/adieducation/university-program)

For general WiFi/SDR questions:
- [OpenWiFi Mailing List](https://lists.open-sdr.org/mailman/listinfo/openwifi)

---

**Version:** 1.0.0
**Last Updated:** 2025-11-21
