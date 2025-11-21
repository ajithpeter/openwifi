# OpenWiFi RF Frontend and SDR Implementation Guide

**Comprehensive RF/SDR Documentation**
**Version:** 1.5.0+
**Last Updated:** 2025-11-21

---

## Table of Contents

1. [Overview](#overview)
2. [RF Frontend Architecture](#rf-frontend-architecture)
3. [AD9361 Transceiver](#ad9361-transceiver)
4. [Frequency Configuration](#frequency-configuration)
5. [Gain Control](#gain-control)
6. [Calibration](#calibration)
7. [Sample Rate Architecture](#sample-rate-architecture)
8. [Filtering](#filtering)
9. [ADC/DAC Interfaces](#adcdac-interfaces)
10. [Advanced RF Configuration](#advanced-rf-configuration)
11. [Troubleshooting](#troubleshooting)

---

## Overview

OpenWiFi uses the **Analog Devices AD9361** RF Agile Transceiver as its RF frontend, providing:

- **Frequency Range:** 70 MHz to 6 GHz
- **Instantaneous Bandwidth:** Up to 56 MHz
- **Sample Rate:** 40 Msps (configurable)
- **Resolution:** 12-bit ADC/DAC
- **Channels:** 2 TX, 2 RX (single channel used by default)
- **Interface:** Parallel LVDS digital interface to FPGA

### System Block Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Antenna                                 │
└──────────────────────┬──────────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────────┐
│                   AD9361 RF Frontend                            │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  RX Path:                                                  │ │
│  │  Antenna → LNA → Mixer → LPF → VGA → ADC (12-bit)        │ │
│  │                    ▲                                       │ │
│  │                    │                                       │ │
│  │              RX LO Synthesizer                             │ │
│  │                 (70 MHz - 6 GHz)                          │ │
│  │                                                            │ │
│  │  TX Path:                                                  │ │
│  │  DAC (12-bit) → LPF → Mixer → PA → Antenna               │ │
│  │                        ▲                                   │ │
│  │                        │                                   │ │
│  │              TX LO Synthesizer                             │ │
│  │                 (47 MHz - 6 GHz)                          │ │
│  │                                                            │ │
│  │  AGC: Automatic Gain Control                              │ │
│  │  FIR: 128-tap programmable filters                        │ │
│  │  CTRL: SPI control interface                              │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────┬──────────────────────────────────────────┘
                       │ LVDS (40 Msps IQ samples)
┌──────────────────────▼──────────────────────────────────────────┐
│                  FPGA (Zynq PL)                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  RX: AD9361 → rx_intf → openofdm_rx → xpu → DMA → PS     │ │
│  │  TX: PS → DMA → xpu → openofdm_tx → tx_intf → AD9361     │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────┬──────────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────────┐
│              Linux Driver (ARM CPU)                             │
│  • AD9361 control via IIO subsystem                            │
│  • Frequency tuning via clock framework                        │
│  • Gain control (manual/auto AGC)                              │
│  • Calibration triggers                                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## RF Frontend Architecture

### Hardware Platforms

OpenWiFi supports multiple hardware platforms with AD9361:

| Board | FPGA | AD9361 Variant | Frequency | License |
|-------|------|----------------|-----------|---------|
| ADRV9364-Z7020 | Zynq-7020 | AD9364 (1T1R) | 70M-6G | No |
| ADRV9361-Z7035 | Zynq-7035 | AD9361 (2T2R) | 70M-6G | Yes |
| ANTSDR | Zynq-7020 | AD9361 (2T2R) | 70M-6G | No |
| ANTSDR E200 | Zynq-7020 | AD9361 (2T2R) | 70M-6G | No |
| ZC706 + FMCOMMS2 | Zynq-7045 | AD9361 (2T2R) | 70M-6G | Yes |
| ZED + FMCOMMS2 | Zynq-7020 | AD9361 (2T2R) | 70M-6G | No |
| SDRPI | Zynq-7020 | AD9361 (2T2R) | 70M-6G | No |

### Control Interfaces

**1. Linux IIO (Industrial I/O) Subsystem**

Location: `/sys/bus/iio/devices/iio:device*/`

```bash
# Find AD9361 device
cd /sys/bus/iio/devices/
ls -d iio\:device* | while read dev; do
    if [ -f "$dev/name" ]; then
        name=$(cat "$dev/name")
        if [ "$name" = "ad9361-phy" ]; then
            echo "AD9361 at $dev"
        fi
    fi
done
```

**2. Clock Framework**

File: `/home/user/openwifi/driver/sdr.c` (lines 261-302)

```c
// TX/RX LO frequency control via clock framework
struct ad9361_rf_phy {
    struct clk *clks[NUM_AD9361_CLKS];
    // clks[TX_RFPLL] = TX LO synthesizer
    // clks[RX_RFPLL] = RX LO synthesizer
};

// Set TX LO frequency
clk_set_rate(priv->ad9361_phy->clks[TX_RFPLL],
             (((u64)1000000ull) * ((u64)actual_tx_lo)) >> 1);

// Set RX LO frequency
clk_set_rate(priv->ad9361_phy->clks[RX_RFPLL],
             (((u64)1000000ull) * ((u64)actual_rx_lo)) >> 1);
```

**3. SPI Control (Fast TX/RX Switching)**

The FPGA can directly control AD9361 TX LO enable via SPI for fast turnaround (0.6 µs).

File: `/home/user/openwifi/driver/hw_def.h` (lines 420-425)

```c
#define XPU_REG_SPI_DISABLE_ADDR (29*4)  // Disable FPGA SPI control
```

---

## AD9361 Transceiver

### Key Specifications

| Parameter | Value | Notes |
|-----------|-------|-------|
| Frequency Range | 70 MHz - 6 GHz | Wideband operation |
| Bandwidth | 200 kHz - 56 MHz | Programmable |
| Sample Rate | 2.083 - 61.44 Msps | Configurable |
| ADC Resolution | 12-bit | |
| DAC Resolution | 12-bit | |
| TX Power | Up to 7 dBm | Board dependent |
| RX Noise Figure | <3 dB | Typical |
| AGC Range | 90+ dB | |
| Channels | 2 TX, 2 RX | Independent |

### Block Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         AD9361                                  │
│                                                                 │
│  RX1 Input ───► LNA ───► Mixer ───► Baseband Filter ───► ADC  │
│                           ▲                                │    │
│  RX2 Input ───► LNA ───┐  │         ┌──────────────────┐  │    │
│                        │  │         │  Digital         │  │    │
│                        │  └─────────┤  Filtering       │◄─┤    │
│                        │            │  (128-tap FIR)   │  │    │
│                        │            │                  │  │    │
│                        │            │  AGC             │  │    │
│                        │            │  DC Offset       │  │    │
│                        │            │  Quadrature      │  │    │
│                        │            │  Correction      │  │    │
│                        │            └──────────────────┘  │    │
│                        │                   │              │    │
│  TX1 Output ◄── PA ◄── Mixer ◄── Baseband Filter ◄── DAC ◄┤    │
│                           ▲                                │    │
│  TX2 Output ◄── PA ◄──┐   │                                │    │
│                       │   │                                │    │
│                       │   │    PLL/Synthesizer             │    │
│                       │   └────────(RX/TX LO)──────────────┤    │
│                       │                                         │
│  ┌─────────────────┐  │  SPI Control Interface                 │
│  │ Reference Clock │  │  ────────────────────────────────────► │
│  │ (40 MHz)        │  │  Digital I/Q Interface (LVDS)          │
│  └─────────────────┘  │  ◄────────────────────────────────────┤
│                       │                                         │
└───────────────────────┴─────────────────────────────────────────┘
```

### Operating Modes

OpenWiFi uses **FDD (Frequency Division Duplex)** mode with same TX/RX frequency:
- TX LO = RX LO = Channel center frequency
- No frequency offset (better EVM performance)
- Fast TX/RX turnaround via FPGA SPI control

---

## Frequency Configuration

### Channel Tuning

**File:** `/home/user/openwifi/driver/sdr.c` (lines 261-302)

```c
static void ad9361_rf_set_channel(struct ieee80211_hw *dev,
                                  struct ieee80211_conf *conf)
{
    struct openwifi_priv *priv = dev->priv;
    u32 center_freq_MHz = conf->chandef.chan->center_freq;
    u32 actual_rx_lo, actual_tx_lo;
    u32 diff_tx_lo;

    // Calculate LO frequencies (with offset if configured)
    actual_rx_lo = center_freq_MHz - priv->rx_freq_offset_to_lo_MHz;
    actual_tx_lo = center_freq_MHz - priv->tx_freq_offset_to_lo_MHz;

    printk("%s: center_freq %d MHz. actual_tx_lo %d actual_rx_lo %d\n",
           sdr_compatible_str, center_freq_MHz, actual_tx_lo, actual_rx_lo);

    // Set TX LO frequency
    clk_set_rate(priv->ad9361_phy->clks[TX_RFPLL],
                 (((u64)1000000ull) * ((u64)actual_tx_lo)) >> 1);

    // Set RX LO frequency
    clk_set_rate(priv->ad9361_phy->clks[RX_RFPLL],
                 (((u64)1000000ull) * ((u64)actual_rx_lo)) >> 1);

    // TX quadrature calibration if frequency change > 100 MHz
    diff_tx_lo = (actual_tx_lo > priv->last_tx_quad_cal_lo) ?
                 (actual_tx_lo - priv->last_tx_quad_cal_lo) :
                 (priv->last_tx_quad_cal_lo - actual_tx_lo);

    if (diff_tx_lo > 100) {
        ad9361_tx_calibration(priv, actual_tx_lo);
    }

    // Update RX configuration (RSSI correction, LBT threshold)
    openwifi_rf_rx_update_after_tuning(priv, actual_rx_lo);

    // Write band and channel info to XPU
    xpu_api->XPU_REG_BAND_CHANNEL_write((priv->band << 16) |
                                        conf->chandef.chan->hw_value);
}
```

### Supported Bands

**File:** `/home/user/openwifi/driver/sdr.h` (lines 167-197)

```c
// 2.4 GHz Band (802.11g)
static struct ieee80211_channel openwifi_2GHz_channels[] = {
    { .band = NL80211_BAND_2GHZ, .center_freq = 2412, .hw_value = 1 },   // Ch 1
    { .band = NL80211_BAND_2GHZ, .center_freq = 2417, .hw_value = 2 },   // Ch 2
    // ... channels 3-11
    { .band = NL80211_BAND_2GHZ, .center_freq = 2462, .hw_value = 11 },  // Ch 11
    { .band = NL80211_BAND_2GHZ, .center_freq = 2467, .hw_value = 12 },  // Ch 12
    { .band = NL80211_BAND_2GHZ, .center_freq = 2472, .hw_value = 13 },  // Ch 13
};

// 5 GHz Band (802.11a)
static struct ieee80211_channel openwifi_5GHz_channels[] = {
    // UNII-1 (5.15-5.25 GHz)
    { .band = NL80211_BAND_5GHZ, .center_freq = 5180, .hw_value = 36 },
    { .band = NL80211_BAND_5GHZ, .center_freq = 5200, .hw_value = 40 },
    { .band = NL80211_BAND_5GHZ, .center_freq = 5220, .hw_value = 44 },
    { .band = NL80211_BAND_5GHZ, .center_freq = 5240, .hw_value = 48 },

    // UNII-2 (5.25-5.35 GHz)
    { .band = NL80211_BAND_5GHZ, .center_freq = 5260, .hw_value = 52,
      .flags = IEEE80211_CHAN_RADAR },  // DFS required
    // ... more DFS channels

    // UNII-3 (5.725-5.825 GHz)
    { .band = NL80211_BAND_5GHZ, .center_freq = 5745, .hw_value = 149 },
    // ... channels up to 165
};
```

### Manual Frequency Control

**Using standard Linux tools:**

```bash
# Set channel (standard method)
iw dev sdr0 set channel 44  # 5 GHz channel 44 (5.220 GHz)
iwconfig sdr0 channel 11     # 2.4 GHz channel 11 (2.462 GHz)
```

**Direct frequency control (for research):**

```bash
# Lock to specific frequency (bypass Linux channel scan)
./set_restrict_freq.sh 5200  # Lock to 5.2 GHz

# Set arbitrary TX/RX frequency (70 MHz - 6 GHz)
./sdrctl dev sdr0 set reg rf 1 5200  # TX LO = 5.2 GHz
./sdrctl dev sdr0 set reg rf 5 5200  # RX LO = 5.2 GHz

# Sub-GHz operation (802.11ah research)
./sdrctl dev sdr0 set reg rf 1 900   # TX LO = 900 MHz
./sdrctl dev sdr0 set reg rf 5 900   # RX LO = 900 MHz
```

### Frequency Offset Tuning

**Zero-offset mode (default, recommended):**
- TX LO = RX LO = Channel frequency
- Better EVM and spectrum mask compliance
- No DC offset issues

**Offset mode (for specific use cases):**

File: `/home/user/openwifi/user_space/rf_init.sh`

```bash
# Set TX frequency offset (in MHz)
export tx_freq_offset_to_lo_MHz=0

# Set RX frequency offset (in MHz)
export rx_freq_offset_to_lo_MHz=0
```

---

## Gain Control

### Automatic Gain Control (AGC)

**Modes:**

1. **fast_attack** (default): Optimized for WiFi bursts
2. **slow_attack**: For narrowband signals
3. **manual**: User-controlled fixed gain

### AGC Configuration

**File:** `/home/user/openwifi/user_space/rf_init.sh`

```bash
# Set AGC mode via IIO
cd /sys/bus/iio/devices/iio:device1

# Fast attack (WiFi optimized)
echo fast_attack > in_voltage0_gain_control_mode
echo fast_attack > in_voltage1_gain_control_mode

# Manual mode
echo manual > in_voltage0_gain_control_mode
echo 70 > in_voltage0_hardwaregain  # Set gain in dB (0-73 dB range)
```

### AGC Register Tuning

**File:** `/home/user/openwifi/user_space/agc_settings.sh`

```bash
#!/bin/bash

cd /sys/kernel/debug/iio/iio:device1

# Optimized AGC settings for WiFi
echo 0x15C 0x70 > direct_reg_access  # AGC gain table configuration
echo 0x106 0x77 > direct_reg_access  # AGC gain control
echo 0x103 0x1C > direct_reg_access  # AGC threshold
echo 0x101 0x0C > direct_reg_access  # AGC lock level
echo 0x110 0x48 > direct_reg_access  # AGC attack delay
echo 0x114 0xb0 > direct_reg_access  # Gain table step size
echo 0x115 0x80 > direct_reg_access  # Gain table configuration
echo 0x13A 0x00 > direct_reg_access  # AGC peak wait time
echo 0x13B 0x30 > direct_reg_access  # AGC gain update counter
echo 0x138 0x00 > direct_reg_access  # AGC lock level fine
echo 0x13C 0x2B > direct_reg_access  # AGC gain increase/decrease
```

**Apply optimized settings:**

```bash
# Default AGC (mode 0)
./agc_settings.sh 0

# Optimized AGC (mode 1, recommended for WiFi)
./agc_settings.sh 1
```

### Manual Gain Control

**File:** `/home/user/openwifi/user_space/set_rx_gain_manual.sh`

```bash
#!/bin/bash

gain_dB=$1  # Range: 0-73 dB

cd /sys/bus/iio/devices/iio:device1

# Switch to manual mode
echo manual > in_voltage0_gain_control_mode

# Set gain
echo $gain_dB > in_voltage0_hardwaregain

echo "RX gain set to $gain_dB dB (manual mode)"
```

**Usage:**

```bash
# Set RX gain to 50 dB
./set_rx_gain_manual.sh 50

# Switch back to auto
./set_rx_gain_auto.sh
```

### TX Power Control

**File:** `/home/user/openwifi/driver/sdr.c` (lines 126-163)

```c
#define AD9361_RADIO_ON_TX_ATT  0       // 0 dB attenuation (radio on)
#define AD9361_RADIO_OFF_TX_ATT 89750   // 89.75 dB attenuation (radio off)

inline int openwifi_is_radio_enabled(struct openwifi_priv *priv)
{
    u32 tx_atten_mdb = 0;

    // Read TX attenuation from AD9361
    ad9361_get_tx_atten(priv->ad9361_phy, 1, &tx_atten_mdb);

    return (tx_atten_mdb < 50000);  // < 50 dB = radio on
}

static void openwifi_rfkill_poll(struct ieee80211_hw *hw)
{
    struct openwifi_priv *priv = hw->priv;
    bool radio_enabled = openwifi_is_radio_enabled(priv);

    wiphy_rfkill_set_hw_state(hw->wiphy, !radio_enabled);
}
```

**Manual TX Power:**

```bash
# Read current TX attenuation (milli-dB)
cd /sys/bus/iio/devices/iio:device1
cat out_voltage0_hardwaregain

# Set TX attenuation (0 = max power, higher = lower power)
# Range: 0-89750 milli-dB (0-89.75 dB)
echo 3000 > out_voltage0_hardwaregain  # -3 dB from max
```

### RSSI Reading

**Real-time RSSI:**

```bash
# Read RSSI from AD9361
cd /sys/bus/iio/devices/iio:device1
cat in_voltage0_rssi

# Or use script
./rssi_ad9361_show.sh
```

**RSSI from OpenWiFi (corrected):**

```bash
# Read RSSI with frequency-dependent correction
./rssi_openwifi_show.sh

# Or via sysfs
cat /sys/devices/platform/fpga-axi@0/fpga-axi@0:sdr/rx_stat | grep rssi
```

---

## Calibration

### TX Quadrature Calibration

**Automatic Calibration:**

File: `/home/user/openwifi/driver/sdr.c` (lines 209-228)

```c
inline void ad9361_tx_calibration(struct openwifi_priv *priv, u32 actual_tx_lo)
{
    u32 spi_disable;

    priv->last_tx_quad_cal_lo = actual_tx_lo;

    printk("%s ad9361_tx_calibration: freq %d MHz\n",
           sdr_compatible_str, actual_tx_lo);

    // Disable FPGA SPI to avoid conflicts
    spi_disable = xpu_api->XPU_REG_SPI_DISABLE_read();
    xpu_api->XPU_REG_SPI_DISABLE_write(1);

    // Execute TX quadrature calibration
    ad9361_do_calib_run(priv->ad9361_phy, TX_QUAD_CAL,
                        (int)priv->ad9361_phy->state->last_tx_quad_cal_phase);

    // Restore FPGA SPI state
    xpu_api->XPU_REG_SPI_DISABLE_write(spi_disable);
}
```

**Trigger:** Automatically when frequency change > 100 MHz

**Manual Calibration:**

```bash
# Trigger TX calibration via register access
cd /sys/kernel/debug/iio/iio:device1
echo 0x16A 0x55 > direct_reg_access  # Trigger TX quad cal
```

### RX Calibration and RSSI Correction

**File:** `/home/user/openwifi/driver/sdr.c` (lines 230-253)

```c
inline void openwifi_rf_rx_update_after_tuning(struct openwifi_priv *priv,
                                                u32 actual_rx_lo)
{
    int auto_lbt_th, receiver_rssi_dbm_th, receiver_rssi_th;
    int fpga_lbt_th;

    // Get frequency-dependent RSSI correction
    priv->rssi_correction = rssi_correction_lookup_table(actual_rx_lo);

    printk("%s rx_freq %dM rssi_correction %d\n",
           sdr_compatible_str, actual_rx_lo, priv->rssi_correction);

    // Update LBT (Listen Before Talk) threshold
    auto_lbt_th = rssi_dbm_to_rssi_half_db(-62, priv->rssi_correction);
    fpga_lbt_th = (priv->use_short_slot ? auto_lbt_th : 0);
    xpu_api->XPU_REG_LBT_TH_write(fpga_lbt_th);

    // Update receiver power threshold
    receiver_rssi_dbm_th = OPENOFDM_RX_RSSI_DBM_TH_DEFAULT;  // -95 dBm
    receiver_rssi_th = rssi_dbm_to_rssi_half_db(receiver_rssi_dbm_th,
                                                 priv->rssi_correction);
    openofdm_rx_api->OPENOFDM_RX_REG_POWER_THRES_write(
        (OPENOFDM_RX_DC_RUNNING_SUM_TH_INIT << 16) | receiver_rssi_th
    );
}
```

**RSSI Correction Table:**

File: `/home/user/openwifi/driver/sdr.c` (lines 187-207)

```c
inline int rssi_correction_lookup_table(u32 freq_MHz)
{
    int rssi_correction;

    if (freq_MHz <= 2484) {          // 2.4 GHz
        rssi_correction = 153;
    } else if (freq_MHz <= 5240) {   // 5 GHz low (5.15-5.24 GHz)
        rssi_correction = 145;
    } else if (freq_MHz <= 5320) {   // 5 GHz mid (5.25-5.32 GHz)
        rssi_correction = 145;
    } else {                          // 5 GHz high (5.5-5.9 GHz)
        rssi_correction = 145;
    }

    return rssi_correction;
}
```

**Empirical Correction Values:**

These values were measured during system characterization and compensate for:
- RF path losses
- AGC behavior
- Frequency-dependent antenna characteristics
- Board-specific effects

---

## Sample Rate Architecture

### Sample Rate Chain

```
AD9361 ADC/DAC: 40 Msps (IQ)
        │
        │ LVDS Digital Interface
        ▼
FPGA rx_intf/tx_intf: 40 Msps
        │
        │ Decimation (RX) / Interpolation (TX)
        ▼
FPGA Baseband (openofdm_tx/rx): 20 Msps
        │
        │ OFDM Processing (64-point FFT/IFFT)
        ▼
    WiFi Signal
```

### Configuration

**File:** `/home/user/openwifi/user_space/rf_init.sh`

```bash
cd /sys/bus/iio/devices/iio:device1

# RX Sampling frequency
echo 40000000 > in_voltage_sampling_frequency

# TX Sampling frequency
echo 40000000 > out_voltage_sampling_frequency

# Baseband sample rate (internal to AD9361)
# This is automatically configured by the driver
```

**Why 40 Msps?**

- Nyquist: 20 MHz bandwidth × 2 = 40 Msps minimum
- Provides guard bands for filtering
- Standard rate for 802.11 20 MHz channels
- Matches FPGA clock generation capabilities

**Baseband Decimation/Interpolation:**

Inside FPGA, samples are processed at 20 Msps:
- **RX:** 40 Msps → decimation by 2 → 20 Msps
- **TX:** 20 Msps → interpolation by 2 → 40 Msps

**Benefit:** Lower clock rate in baseband reduces FPGA resource usage and power.

---

## Filtering

### FIR Filter Configuration

AD9361 has 128-tap programmable FIR filters for TX and RX paths.

**Filter Files:**

- `/home/user/openwifi/user_space/openwifi_ad9361_fir.ftr` - Standard filter
- `/home/user/openwifi/user_space/openwifi_ad9361_fir_tx_0MHz.ftr` - Zero offset TX
- `/home/user/openwifi/user_space/openwifi_ad9361_fir_tx_0MHz_11n.ftr` - 802.11n optimized
- `/home/user/openwifi/user_space/openwifi_ad9361_fir_tx_0MHz_11n_narrow1.ftr` - Narrow band

**Filter File Format:**

```
TX 3 GAIN 0 INT 1
RX 3 GAIN -6 DEC 1
RTX 1280000000 160000000 80000000 40000000 40000000 40000000
RRX 1280000000 160000000 80000000 40000000 40000000 40000000
BWTX 35301580
BWRX 20172411
# 128 coefficients follow (integer format)
-63
-55
# ... (128 total)
```

**Loading Filters:**

File: `/home/user/openwifi/user_space/rf_init.sh`

```bash
cd /sys/bus/iio/devices/iio:device1

# Load FIR filter coefficients
fir_filename="/root/openwifi/openwifi_ad9361_fir_tx_0MHz_11n.ftr"
cat $fir_filename > filter_fir_config

# Enable RX FIR
echo 1 > in_voltage_filter_fir_en

# Enable TX FIR (configurable)
tx_fir_enable=1
echo $tx_fir_enable > out_voltage_filter_fir_en

echo "FIR filters loaded and enabled"
```

### Bandwidth Configuration

**File:** `/home/user/openwifi/user_space/rf_init.sh`

```bash
cd /sys/bus/iio/devices/iio:device1

# RX RF bandwidth (analog)
echo 17500000 > in_voltage_rf_bandwidth   # 17.5 MHz

# TX RF bandwidth (analog)
echo 37500000 > out_voltage_rf_bandwidth  # 37.5 MHz

# For 802.11n mode (narrower, better adjacent channel rejection)
# echo 25200000 > in_voltage_rf_bandwidth
# echo 25200000 > out_voltage_rf_bandwidth
```

**Bandwidth Selection:**

| Mode | RX BW | TX BW | Notes |
|------|-------|-------|-------|
| Standard 11a/g | 17.5 MHz | 37.5 MHz | Good sensitivity |
| 802.11n | 25.2 MHz | 25.2 MHz | Better adjacent channel |
| Narrowband | 10 MHz | 10 MHz | Research use |

---

## ADC/DAC Interfaces

### Digital Interface

**AD9361 ↔ FPGA:**

- **Type:** Parallel LVDS
- **Data Rate:** 40 Msps (DDR)
- **Word Length:** 12-bit I + 12-bit Q
- **Format:** Frame pulse + data lines
- **Latency:** <100 ns

### Data Format

**IQ Sample Structure:**

```
┌─────────────────────────────────────┐
│  Sample (64-bit in FPGA)            │
├──────────────────┬──────────────────┤
│ I (16-bit)       │ Q (16-bit)       │
│ Sign-extended    │ Sign-extended    │
│ from 12-bit      │ from 12-bit      │
└──────────────────┴──────────────────┘
```

**FPGA Interface:**

File: `/home/user/openwifi/driver/hw_def.h`

```c
// RX/TX use 8 bytes per symbol (64-bit)
#define RX_INTF_NUM_BYTE_PER_DMA_SYMBOL  8
#define TX_INTF_NUM_BYTE_PER_DMA_SYMBOL  8

// Each symbol contains one I/Q sample pair
```

### Baseband Gain (Digital)

**RX Path:**

File: `/home/user/openwifi/driver/rx_intf/rx_intf.c`

```c
// Default RX baseband gain: 4 (left shift by 4 bits)
#define RX_INTF_BB_GAIN_DEFAULT  4

rx_intf_api->RX_INTF_REG_BB_GAIN_write(RX_INTF_BB_GAIN_DEFAULT);
```

**TX Path:**

File: `/home/user/openwifi/driver/tx_intf/tx_intf.c` (line 347)

```c
// TX baseband gain: 250 (optimized for EVM)
// Lower values = lower PAPR but may clip
// Higher values = higher PAPR, may degrade EVM
tx_intf_api->TX_INTF_REG_BB_GAIN_write(250);
```

**Manual Adjustment:**

```bash
# Read current gains
./sdrctl dev sdr0 get reg rx_intf 11  # RX BB gain
./sdrctl dev sdr0 get reg tx_intf 13  # TX BB gain

# Adjust if needed
./sdrctl dev sdr0 set reg rx_intf 11 6   # RX gain = 6
./sdrctl dev sdr0 set reg tx_intf 13 300 # TX gain = 300
```

---

## Advanced RF Configuration

### Antenna Selection

OpenWiFi supports antenna switching for boards with multiple antenna ports.

**File:** `/home/user/openwifi/driver/sdr.c` (lines 1483-1568)

```c
static int openwifi_set_antenna(struct ieee80211_hw *dev, u32 tx_ant, u32 rx_ant)
{
    struct openwifi_priv *priv = dev->priv;

    // tx_ant: bitmap (bit 0 = ANT1, bit 1 = ANT2)
    // rx_ant: bitmap

    // Configure AD9361 TX path
    if (tx_ant & 0x1) {
        ad9361_set_tx_atten(priv->ad9361_phy, 0, true, true);  // TX1 on
    } else {
        ad9361_set_tx_atten(priv->ad9361_phy, 89750, true, true);  // TX1 off
    }

    // Configure AD9361 RX path
    struct ad9361_ctrl_outs ctrl_out;
    ctrl_out.en_mask = AD9361_CTRL_OUT_EN_MASK;
    ctrl_out.index = (rx_ant & 0x1) ? AD9361_CTRL_OUT_INDEX_ANT0 :
                                       AD9361_CTRL_OUT_INDEX_ANT1;
    ad9361_ctrl_outs_setup(priv->ad9361_phy, &ctrl_out);

    return 0;
}
```

**Usage:**

```bash
# Set TX antenna
iw dev sdr0 set txq be txop_limit 1  # TX antenna 1

# Or via register (tx_intf)
./sdrctl dev sdr0 set reg tx_intf 16 0  # ANT0
./sdrctl dev sdr0 set reg tx_intf 16 1  # ANT1
./sdrctl dev sdr0 set reg tx_intf 16 3  # Both (CDD mode)
```

### Fast TX/RX Turnaround

**FPGA SPI Control:**

The FPGA can directly control AD9361 TX LO enable/disable via SPI for fast switching:

- **Turnaround Time:** 0.6 µs (600 ns)
- **Purpose:** Self-interference suppression
- **Benefit:** Achieves 10 µs SIFS timing

**File:** `/home/user/openwifi/driver/xpu/xpu.c`

```c
// FPGA controls AD9361 TX LO via SPI during TX/RX transitions
// Software disables this during calibration to avoid conflicts
xpu_api->XPU_REG_SPI_DISABLE_write(1);  // Disable for calibration
// ... perform calibration ...
xpu_api->XPU_REG_SPI_DISABLE_write(0);  // Re-enable for normal operation
```

### External Reference Clock

Some boards support external reference input for frequency synchronization.

**Example: E310v2 Board**

File: `/home/user/openwifi/kernel_boot/boards/e310v2/README.md`

```
External reference input: 10 MHz
GPS: u-blox timing GPS
VCXO: Temperature-compensated crystal oscillator
```

**Configuration:**

```bash
# Enable external reference (board-specific)
cd /sys/kernel/debug/iio/iio:device1
echo 0x009 0x03 > direct_reg_access  # Use external reference
```

---

## Troubleshooting

### No RF Output

**Diagnosis:**

```bash
# 1. Check TX attenuation
cd /sys/bus/iio/devices/iio:device1
cat out_voltage0_hardwaregain
# Should be < 50000 milli-dB for active transmission

# 2. Check TX LO frequency
cat out_altvoltage1_TX_LO_frequency
# Should match channel frequency

# 3. Check TX enable
cat out_altvoltage1_TX_LO_powerdown
# Should be 0 (not powered down)

# 4. Verify FPGA TX interface
./sdrctl dev sdr0 get reg tx_intf 0
# Bit 0 should be 0 (not in reset)
```

**Solutions:**

```bash
# Reset RF initialization
./rf_init.sh

# Force TX power
echo 0 > /sys/bus/iio/devices/iio:device1/out_voltage0_hardwaregain

# Reload driver
./wgd.sh
```

### Poor RX Sensitivity

**Diagnosis:**

```bash
# 1. Check RX gain
cd /sys/bus/iio/devices/iio:device1
cat in_voltage0_hardwaregain

# 2. Check AGC mode
cat in_voltage0_gain_control_mode

# 3. Check RSSI
cat in_voltage0_rssi

# 4. Check power threshold
./sdrctl dev sdr0 get reg rx 2
```

**Solutions:**

```bash
# Use optimized AGC settings
./agc_settings.sh 1

# Lower power threshold (more sensitive)
./sdrctl dev sdr0 set reg rx 2 100

# Increase RX gain manually
./set_rx_gain_manual.sh 70

# Check antenna connection
./rssi_ad9361_show.sh  # Should show reasonable RSSI with nearby TX
```

### Frequency Offset Issues

**Symptoms:**
- High packet error rate
- Phase offset warnings in logs
- Sync failures

**Diagnosis:**

```bash
# Check phase offset from receiver
./sdrctl dev sdr0 get reg rx 20
# Look for freq_offset_locked flag

# Check frequency offset in IQ capture
cd /root/openwifi/side_ch_ctl_src
./side_ch_ctl freq_chan num_eq  # Monitor freq offset
```

**Solutions:**

```bash
# 1. Verify reference clock
cd /sys/bus/iio/devices/iio:device1
cat in_voltage0_sampling_frequency
# Should be 40000000

# 2. Trigger TX calibration
# Change frequency by >100 MHz to force recalibration
iw dev sdr0 set channel 36
iw dev sdr0 set channel 64

# 3. Check temperature
cat /sys/class/thermal/thermal_zone0/temp
# High temperature can cause drift

# 4. Use external reference if available
# (board-specific)
```

### Poor TX EVM

**Diagnosis:**

```bash
# Check TX BB gain
./sdrctl dev sdr0 get reg tx_intf 13
# Default: 250

# Check TX attenuation
cd /sys/bus/iio/devices/iio:device1
cat out_voltage0_hardwaregain
```

**Solutions:**

```bash
# Adjust TX BB gain
# Lower values = better EVM, but may clip with high PAPR
./sdrctl dev sdr0 set reg tx_intf 13 200  # Try 200

# Reduce TX power
echo 3000 > /sys/bus/iio/devices/iio:device1/out_voltage0_hardwaregain

# Trigger TX calibration
iw dev sdr0 set channel 36
sleep 1
iw dev sdr0 set channel 44  # Force >100 MHz change
```

### Self-Interference

**Symptoms:**
- High noise floor
- Desensitization
- Phantom packet detections

**Solutions:**

```bash
# 1. Verify fast TX/RX switching is enabled
./sdrctl dev sdr0 get reg xpu 29
# Should be 0 (FPGA SPI control enabled)

# 2. Increase physical separation
# Use separate TX/RX antennas if available

# 3. Adjust LBT threshold
./sdrctl dev sdr0 set reg drv_xpu 0 -55  # Lower = more conservative

# 4. Check RF shielding
# Ensure proper board grounding and shielding
```

---

## Performance Benchmarks

### Measured Performance

| Parameter | Value | Conditions |
|-----------|-------|------------|
| **TX EVM** | -38 dB | MCS 7, 5 GHz |
| **RX Sensitivity (MCS 0)** | -92 dBm | BPSK 1/2, PER < 10% |
| **RX Sensitivity (MCS 7)** | -73 dBm | 64-QAM 5/6, PER < 10% |
| **TX Power** | 0-7 dBm | Board dependent |
| **Frequency Accuracy** | ±20 ppm | With 40 MHz XTAL |
| **Phase Noise** | <-85 dBc/Hz @ 100 kHz | Typical |
| **Adjacent Channel Rejection** | 40 dB | 5 GHz, 20 MHz offset |

### Optimization Tips

**For Maximum Throughput:**
```bash
# Enable AMPDU
./wgd.sh 1

# Use MCS 7
./sdrctl dev sdr0 set reg drv_tx 1 11

# Optimize AGC
./agc_settings.sh 1
```

**For Maximum Range:**
```bash
# Use MCS 0
./sdrctl dev sdr0 set reg drv_tx 0 0

# Maximum RX gain
./set_rx_gain_manual.sh 73

# Maximum TX power
echo 0 > /sys/bus/iio/devices/iio:device1/out_voltage0_hardwaregain
```

**For Best Reliability:**
```bash
# Moderate MCS
./sdrctl dev sdr0 set reg drv_tx 0 4  # 24 Mbps

# Auto AGC
./set_rx_gain_auto.sh

# Standard TX power
echo 2000 > /sys/bus/iio/devices/iio:device1/out_voltage0_hardwaregain
```

---

## References

### Source Files

- Main driver: `/home/user/openwifi/driver/sdr.c`
- RF init script: `/home/user/openwifi/user_space/rf_init.sh`
- AGC settings: `/home/user/openwifi/user_space/agc_settings.sh`
- TX interface: `/home/user/openwifi/driver/tx_intf/tx_intf.c`
- RX interface: `/home/user/openwifi/driver/rx_intf/rx_intf.c`

### AD9361 Documentation

- [AD9361 Product Page](https://www.analog.com/en/products/ad9361.html)
- [AD9361 Reference Manual UG-570](https://www.analog.com/media/en/technical-documentation/user-guides/AD9361_Reference_Manual_UG-570.pdf)
- [Linux IIO Driver](https://wiki.analog.com/resources/tools-software/linux-drivers/iio-transceiver/ad9361)

### Related Guides

- [ARCHITECTURE.md](/doc/ARCHITECTURE.md) - System architecture
- [PHY_MAC_GUIDE.md](/doc/PHY_MAC_GUIDE.md) - PHY/MAC layers
- [PERFORMANCE_TUNING.md](/doc/PERFORMANCE_TUNING.md) - Optimization
- [TROUBLESHOOTING_GUIDE.md](/doc/TROUBLESHOOTING_GUIDE.md) - Debug procedures

---

**Document Version:** 1.0
**Last Updated:** 2025-11-21
**License:** AGPL-3.0-or-later
