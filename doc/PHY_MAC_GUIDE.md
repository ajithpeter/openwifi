# OpenWiFi PHY and MAC Layer Implementation Guide

**Comprehensive PHY/MAC Documentation**
**Version:** 1.5.0+
**Last Updated:** 2025-11-21

---

## Table of Contents

1. [Overview](#overview)
2. [PHY Layer Architecture](#phy-layer-architecture)
3. [MAC Layer Architecture](#mac-layer-architecture)
4. [OFDM Implementation](#ofdm-implementation)
5. [Channel Coding](#channel-coding)
6. [Synchronization](#synchronization)
7. [CSMA/CA Engine](#csmaca-engine)
8. [Frame Processing](#frame-processing)
9. [Timing and Coordination](#timing-and-coordination)
10. [Advanced Features](#advanced-features)

---

## Overview

OpenWiFi implements a complete IEEE 802.11a/g/n PHY and MAC layer stack using a **split architecture**:

- **PHY Layer**: Primarily in FPGA hardware (openofdm_tx, openofdm_rx modules)
- **High MAC**: Linux mac80211 subsystem (software)
- **Low MAC**: FPGA hardware (xpu module for time-critical operations)

### Supported Standards

| Standard | Frequency | Rates | Status |
|----------|-----------|-------|--------|
| 802.11a | 5 GHz | 6, 9, 12, 18, 24, 36, 48, 54 Mbps | ✅ Full support |
| 802.11g | 2.4 GHz | 6, 9, 12, 18, 24, 36, 48, 54 Mbps | ✅ Full support |
| 802.11n | 2.4/5 GHz | MCS 0-7 (up to 72.2 Mbps) | ✅ Single stream |
| 802.11b | 2.4 GHz | 1, 2, 5.5, 11 Mbps | ❌ Not supported |

---

## PHY Layer Architecture

### Layer Structure

```
┌─────────────────────────────────────────────────────────────┐
│                   PHY LAYER (FPGA)                          │
│                                                             │
│  Transmit Path:                  Receive Path:             │
│  ┌──────────────┐                ┌──────────────┐          │
│  │ Scrambler    │                │ Descrambler  │          │
│  │ ┌──────────┐ │                │ ┌──────────┐ │          │
│  │ │ LFSR     │ │                │ │ LFSR     │ │          │
│  │ │ G(x)=x⁷+x⁴+1│              │ │ Inverse  │ │          │
│  │ └──────────┘ │                │ └──────────┘ │          │
│  └──────┬───────┘                └──────▲───────┘          │
│         │                               │                   │
│  ┌──────▼───────┐                ┌──────┴───────┐          │
│  │ Conv Encoder │                │ Viterbi Dec  │          │
│  │ K=7, R=1/2   │                │ Soft/Hard    │          │
│  │ Puncturing   │                │ De-puncture  │          │
│  └──────┬───────┘                └──────▲───────┘          │
│         │                               │                   │
│  ┌──────▼───────┐                ┌──────┴───────┐          │
│  │ Interleaver  │                │ Deinterleaver│          │
│  │ Block size:  │                │              │          │
│  │ NCBPS/NBPSC  │                │              │          │
│  └──────┬───────┘                └──────▲───────┘          │
│         │                               │                   │
│  ┌──────▼───────┐                ┌──────┴───────┐          │
│  │ QAM Mapper   │                │ QAM Demapper │          │
│  │ BPSK/QPSK/   │                │ + Equalizer  │          │
│  │ 16-QAM/64-QAM│                │              │          │
│  └──────┬───────┘                └──────▲───────┘          │
│         │                               │                   │
│  ┌──────▼───────┐                ┌──────┴───────┐          │
│  │ Pilot Insert │                │ FFT 64-point │          │
│  │ 4 pilots     │                │ + Chan Est   │          │
│  └──────┬───────┘                └──────▲───────┘          │
│         │                               │                   │
│  ┌──────▼───────┐                ┌──────┴───────┐          │
│  │ IFFT 64-point│                │ Sync Long    │          │
│  │              │                │ (Chan Est)   │          │
│  └──────┬───────┘                └──────▲───────┘          │
│         │                               │                   │
│  ┌──────▼───────┐                ┌──────┴───────┐          │
│  │ Add CP       │                │ Sync Short   │          │
│  │ GI: 0.8/3.2μs│                │ (Detection)  │          │
│  └──────┬───────┘                └──────▲───────┘          │
│         │                               │                   │
│  ┌──────▼───────┐                       │                   │
│  │ Add Preamble │                       │                   │
│  │ Short + Long │                       │                   │
│  └──────┬───────┘                       │                   │
│         │                               │                   │
└─────────┼───────────────────────────────┼───────────────────┘
          │                               │
          ▼                               ▼
    IQ Samples                      IQ Samples
    @ 20 Msps                       @ 20 Msps
```

### Key Components

#### 1. **OFDM Parameters**

**File:** `/home/user/openwifi/driver/hw_def.h`

```c
// FFT Configuration
#define OPENOFDM_RX_FFT_WIN_SHIFT_DEFAULT 4  // Line 241
#define OPENOFDM_RX_MIN_PLATEAU_DEFAULT 100   // Line 240

// Subcarrier allocation (802.11a/g)
// Total: 64 subcarriers
// Data: 48 subcarriers
// Pilots: 4 subcarriers (indices: -21, -7, 7, 21)
// DC null: 1 (index 0)
// Guard bands: 11 (upper and lower)

// 802.11n extends to 52 data+pilot subcarriers
```

#### 2. **Modulation Schemes**

| Modulation | Bits/Symbol | Code Rate | Data Rate (20 MHz) |
|------------|-------------|-----------|-------------------|
| BPSK | 1 | 1/2 | 6 Mbps |
| BPSK | 1 | 3/4 | 9 Mbps |
| QPSK | 2 | 1/2 | 12 Mbps |
| QPSK | 2 | 3/4 | 18 Mbps |
| 16-QAM | 4 | 1/2 | 24 Mbps |
| 16-QAM | 4 | 3/4 | 36 Mbps |
| 64-QAM | 6 | 2/3 | 48 Mbps |
| 64-QAM | 6 | 3/4 | 54 Mbps |

**802.11n HT-MCS:**

| MCS | Modulation | Code Rate | GI=800ns | GI=400ns |
|-----|------------|-----------|----------|----------|
| 0 | BPSK | 1/2 | 6.5 Mbps | 7.2 Mbps |
| 1 | QPSK | 1/2 | 13 Mbps | 14.4 Mbps |
| 2 | QPSK | 3/4 | 19.5 Mbps | 21.7 Mbps |
| 3 | 16-QAM | 1/2 | 26 Mbps | 28.9 Mbps |
| 4 | 16-QAM | 3/4 | 39 Mbps | 43.3 Mbps |
| 5 | 64-QAM | 2/3 | 52 Mbps | 57.8 Mbps |
| 6 | 64-QAM | 3/4 | 58.5 Mbps | 65 Mbps |
| 7 | 64-QAM | 5/6 | 65 Mbps | 72.2 Mbps |

---

## OFDM Implementation

### Transmitter (openofdm_tx)

**Location:** `/home/user/openwifi/driver/openofdm_tx/openofdm_tx.c`

**Hardware Initialization:**

```c
// File: /home/user/openwifi/driver/openofdm_tx/openofdm_tx.c
// Lines: 90-91

static inline u32 hw_init(enum openofdm_tx_mode mode)
{
    // Initialize pilot scrambler state
    openofdm_tx_api->OPENOFDM_TX_REG_PILOT_SCRAM_STATE_write(0x7F);

    // Initialize data scrambler state
    openofdm_tx_api->OPENOFDM_TX_REG_DATA_SCRAM_STATE_write(0x7F);

    return 0;
}
```

**Scrambler Polynomial:** G(x) = x⁷ + x⁴ + 1

**Register Definitions:**

```c
// File: /home/user/openwifi/driver/hw_def.h
// Lines: 282-303

#define OPENOFDM_TX_REG_MULTI_RST_ADDR         (0*4)
#define OPENOFDM_TX_REG_PILOT_SCRAM_STATE_ADDR (1*4)
#define OPENOFDM_TX_REG_DATA_SCRAM_STATE_ADDR  (2*4)
```

### Receiver (openofdm_rx)

**Location:** `/home/user/openwifi/driver/openofdm_rx/openofdm_rx.c`

**Power Threshold Configuration:**

```c
// File: /home/user/openwifi/driver/openofdm_rx/openofdm_rx.c
// Lines: 97-108

#define OPENOFDM_RX_POWER_THRES_INIT        124
#define OPENOFDM_RX_DC_RUNNING_SUM_TH_INIT  64
#define OPENOFDM_RX_MIN_PLATEAU_INIT        100
#define OPENOFDM_RX_FFT_WIN_SHIFT_INIT      4

static inline u32 hw_init(enum openofdm_rx_mode mode)
{
    // Set power threshold (default: 124 corresponds to ~-86 dBm)
    openofdm_rx_api->OPENOFDM_RX_REG_POWER_THRES_write(
        (OPENOFDM_RX_DC_RUNNING_SUM_TH_INIT << 16) |
        OPENOFDM_RX_POWER_THRES_INIT
    );

    // Configure soft decoding and packet length limits
    openofdm_rx_api->OPENOFDM_RX_REG_SOFT_DECODING_write(
        (OPENWIFI_MAX_SIGNAL_LEN_TH << 16) |  // 1700 bytes
        (OPENWIFI_MIN_SIGNAL_LEN_TH << 12) |  // 14 bytes
        1  // Enable soft decoding
    );

    // Set minimum plateau for sync short detection
    openofdm_rx_api->OPENOFDM_RX_REG_MIN_PLATEAU_write(
        OPENOFDM_RX_MIN_PLATEAU_INIT
    );

    // Set FFT window shift
    openofdm_rx_api->OPENOFDM_RX_REG_FFT_WIN_SHIFT_write(
        OPENOFDM_RX_FFT_WIN_SHIFT_INIT
    );

    return 0;
}
```

**Key Registers:**

```c
// File: /home/user/openwifi/driver/hw_def.h
// Lines: 211-280

#define OPENOFDM_RX_REG_POWER_THRES_ADDR         (2*4)
#define OPENOFDM_RX_REG_MIN_PLATEAU_ADDR         (3*4)
#define OPENOFDM_RX_REG_SOFT_DECODING_ADDR       (4*4)
#define OPENOFDM_RX_REG_FFT_WIN_SHIFT_ADDR       (5*4)
#define OPENOFDM_RX_REG_PHASE_OFFSET_TH_ADDR     (11*4)
#define OPENOFDM_RX_REG_STATE_HISTORY_ADDR       (20*4)

// Thresholds
#define OPENOFDM_RX_RSSI_DBM_TH_DEFAULT          -95
#define OPENOFDM_RX_PHASE_OFFSET_ABS_TH          11
#define OPENOFDM_RX_SMALL_EQ_OUT_COUNTER_TH      48
```

---

## Channel Coding

### Convolutional Encoding

**Parameters:**
- **Constraint Length (K):** 7
- **Mother Code Rate:** 1/2
- **Generator Polynomials:**
  - G0 = 133₈ (octal) = 1011011₂
  - G1 = 171₈ (octal) = 1111001₂

**Code Rates via Puncturing:**

| Code Rate | Puncturing Pattern |
|-----------|-------------------|
| 1/2 | None (both outputs kept) |
| 2/3 | [1 1 0 1] |
| 3/4 | [1 1 0 1 1 0] |
| 5/6 | [1 1 0 1 1 0 1 0 1 1 0 1] |

### Viterbi Decoder

**Implementation:** Xilinx IP Core (requires license)

**File:** `/home/user/openwifi/driver/openofdm_rx/openofdm_rx.c`

**Configuration:**

```c
// Soft-decision Viterbi decoding
// Bit 0 = 1: soft decoding enabled
// Bit 0 = 0: hard decoding

// Enable soft decoding (better performance)
openofdm_rx_api->OPENOFDM_RX_REG_SOFT_DECODING_write(
    (max_signal_len_th << 16) |
    (min_signal_len_th << 12) |
    1  // Soft decoding enable
);
```

**Known Issue:** Xilinx evaluation license causes decoder to halt after ~2 hours.

**Recovery:**
```bash
# Check decoder status
./sdrctl dev sdr0 get reg rx 20

# Reload FPGA if stuck
./load_fpga_img.sh
```

### Interleaving

**Purpose:** Distribute burst errors across multiple codewords

**Block Size:** Depends on modulation (NCBPS = Number of Coded Bits Per Symbol)

| Modulation | NCBPS | NBPSC | Interleaver Size |
|------------|-------|-------|------------------|
| BPSK | 48 | 1 | 48 |
| QPSK | 96 | 2 | 96 |
| 16-QAM | 192 | 4 | 192 |
| 64-QAM | 288 | 6 | 288 |

**Implementation:** Hardware in openofdm_tx/rx modules (not user-configurable)

---

## Synchronization

### Frame Detection Pipeline

```
IQ Samples @ 20 Msps
         │
         ▼
┌─────────────────────┐
│ Power Detection     │
│ - Threshold: 124    │  ← Configurable
│ - Window: 16 samples│
└─────────┬───────────┘
          │ Trigger
          ▼
┌─────────────────────┐
│ Sync Short          │
│ - Auto-correlation  │
│ - Plateau detection │  ← Min plateau: 100
│ - Freq offset est   │
└─────────┬───────────┘
          │ Confirm
          ▼
┌─────────────────────┐
│ Sync Long           │
│ - Cross-correlation │
│ - Channel estimation│
│ - FFT window timing │  ← FFT shift: 4
└─────────┬───────────┘
          │ Synchronized
          ▼
┌─────────────────────┐
│ SIGNAL Field Decode │
│ - Rate extraction   │
│ - Length extraction │
│ - Parity check      │
└─────────┬───────────┘
          │ Valid
          ▼
     Data Demod
```

### Power Threshold Tuning

**File:** `/home/user/openwifi/driver/sdr.c` (lines 230-253)

```c
// RSSI-based threshold calculation
inline void openwifi_rf_rx_update_after_tuning(struct openwifi_priv *priv,
                                                u32 actual_rx_lo)
{
    int receiver_rssi_dbm_th = OPENOFDM_RX_RSSI_DBM_TH_DEFAULT;  // -95 dBm
    int receiver_rssi_th;

    // Get frequency-dependent RSSI correction
    priv->rssi_correction = rssi_correction_lookup_table(actual_rx_lo);

    // Convert dBm to half-dB units with correction
    receiver_rssi_th = rssi_dbm_to_rssi_half_db(receiver_rssi_dbm_th,
                                                 priv->rssi_correction);

    // Write to FPGA
    openofdm_rx_api->OPENOFDM_RX_REG_POWER_THRES_write(
        (OPENOFDM_RX_DC_RUNNING_SUM_TH_INIT << 16) | receiver_rssi_th
    );
}
```

**RSSI Correction Table:**

```c
// File: /home/user/openwifi/driver/sdr.c (lines 187-207)

inline int rssi_correction_lookup_table(u32 freq_MHz)
{
    int rssi_correction;

    if (freq_MHz <= 2484) {          // 2.4 GHz
        rssi_correction = 153;
    } else if (freq_MHz <= 5240) {   // 5 GHz low
        rssi_correction = 145;
    } else if (freq_MHz <= 5320) {   // 5 GHz mid
        rssi_correction = 145;
    } else {                          // 5 GHz high
        rssi_correction = 145;
    }

    return rssi_correction;
}
```

**Manual Tuning:**

```bash
# Read current power threshold
./sdrctl dev sdr0 get reg rx 2

# Set power threshold (value in half-dB units)
# Lower value = more sensitive (may increase false detections)
# Higher value = less sensitive (may miss weak signals)
./sdrctl dev sdr0 set reg rx 2 100  # More sensitive
./sdrctl dev sdr0 set reg rx 2 150  # Less sensitive
```

### FFT Window Positioning

**Purpose:** Align FFT window to minimize inter-symbol interference

**Default Shift:** 4 samples (out of 64-point FFT)

```bash
# Read current FFT window shift
./sdrctl dev sdr0 get reg rx 5

# Adjust FFT window shift (0-31 range)
./sdrctl dev sdr0 set reg rx 5 6   # Shift by 6 samples
```

### Channel Estimation

**Method:** Long training symbols (LTS) based estimation

**Implementation:** Per-subcarrier complex channel response

**Equalizer:** Single-tap frequency-domain equalizer

---

## MAC Layer Architecture

### Split MAC Design

```
┌─────────────────────────────────────────────────────────────┐
│                    HIGH MAC (Software)                      │
│                  Linux mac80211 Subsystem                   │
│                                                             │
│  • Management frames (beacon, probe, auth, assoc)          │
│  • Association and authentication state machines           │
│  • Rate control (Minstrel/Minstrel-HT)                     │
│  • Encryption (WPA/WPA2 in software)                       │
│  • Fragmentation and reassembly                            │
│  • A-MPDU aggregation management                           │
│  • QoS queue mapping                                       │
└──────────────────────┬──────────────────────────────────────┘
                       │ ieee80211_ops interface
┌──────────────────────▼──────────────────────────────────────┐
│              openwifi Driver (sdr.c)                        │
│                                                             │
│  • Packet TX/RX processing                                 │
│  • DMA buffer management                                   │
│  • Ring buffer management (4 queues)                       │
│  • Interrupt handling                                      │
│  • RF control (AD9361)                                     │
│  • Statistics collection                                   │
└──────────────────────┬──────────────────────────────────────┘
                       │ Register writes + DMA
┌──────────────────────▼──────────────────────────────────────┐
│                  LOW MAC (FPGA - xpu)                       │
│                                                             │
│  • CSMA/CA state machine (µs precision)                    │
│  • SIFS/DIFS/Backoff timing (achieves 10 µs SIFS)         │
│  • ACK generation and detection                            │
│  • CTS/RTS handling                                        │
│  • Frame filtering (MAC address, BSSID, type)              │
│  • TSF timer (64-bit, 1 µs resolution)                     │
│  • Time slicing for network slicing                        │
└─────────────────────────────────────────────────────────────┘
```

**Rationale:** Hardware handles time-critical operations that software cannot meet (SIFS timing requirement of 16 µs).

---

## CSMA/CA Engine

### State Machine (FPGA xpu Module)

**File:** `/home/user/openwifi/driver/xpu/xpu.c`

```
         ┌─────────────┐
    ┌────│    IDLE     │◄────────────────┐
    │    └──────┬──────┘                 │
    │           │ TX Request             │
    │           ▼                        │
    │    ┌─────────────┐                │
    │    │ CCA Check   │                │
    │    └──────┬──────┘                │
    │           │                        │
    │      Busy │ Clear                 │
    │    ┌──────▼──────┐                │
    │    │ Channel     │                │
    │    │ Busy        │                │
    │    └──────┬──────┘                │
    │           │ Clear                 │
    │           ▼                        │
    │    ┌─────────────┐                │
    ├────┤ DIFS Wait   │                │
    │    └──────┬──────┘                │
    │           │                        │
    │      Busy │ Complete              │
    │    ┌──────▼──────┐                │
    │    │  Backoff    │                │
    │    │  Counter    │                │
    │    └──────┬──────┘                │
    │           │ Zero                  │
    │           ▼                        │
    │    ┌─────────────┐                │
    │    │ Transmit    │                │
    │    └──────┬──────┘                │
    │           │                        │
    │      Need ACK?                    │
    │           │ Yes                   │
    │           ▼                        │
    │    ┌─────────────┐                │
    │    │ Wait ACK    │                │
    │    └──────┬──────┘                │
    │           │                        │
    │     ACK   │ Timeout               │
    │    ┌──────▼──────┐                │
    │    │ Retry?      │                │
    │    └──────┬──────┘                │
    │           │ Yes                   │
    └───────────┘      │ No/Max retries
                       └─────────────────►
```

### Timing Parameters

**File:** `/home/user/openwifi/driver/xpu/xpu.c` (lines 320-360)

```c
static inline u32 hw_init(enum xpu_mode mode, u32 tsf_val)
{
    // SIFS: 16 µs (10 µs in clock units)
    // ACK wait timeout configuration
    // For 5 GHz: (51+2+2)*10 + 15 = 565 clock cycles
    xpu_api->XPU_REG_ACK_WAIT_TIMEOUT_write(
        (0 << 24) |        // Top threshold
        ((51+2+2) << 16) | // Config for ACK timeout
        (25 << 8) |        // SIFS + 7 us
        (16+25+7-3+8-2)    // ACK calibrated timing
    );

    // BB-RF delay calibration
    xpu_api->XPU_REG_BB_RF_DELAY_write(
        (16 << 24) |  // tx_rf_delay2
        (0 << 16) |   // tx_rf_delay1
        (26 << 8) |   // rx_rf_delay
        9             // bb_delay
    );

    // DIFS advance timing
    xpu_api->XPU_REG_DIFS_ADVANCE_write(2);  // 2 µs advance

    // Forced idle after RX
    xpu_api->XPU_REG_FORCE_IDLE_AFTER_RX_write(75);  // 75 clock cycles

    return 0;
}
```

**Key Timing Constants:**

| Parameter | Value | Notes |
|-----------|-------|-------|
| SIFS | 16 µs | 802.11a/g/n standard |
| DIFS | 34 µs | SIFS + 2×Slot |
| Slot Time (5 GHz) | 9 µs | |
| Slot Time (2.4 GHz) | 20 µs | |
| ACK Timeout | ~55 µs | Configurable |

### CCA (Clear Channel Assessment)

**LBT Threshold Configuration:**

```c
// File: /home/user/openwifi/driver/sdr.c (lines 230-253)

// Set LBT threshold to -62 dBm (auto mode)
auto_lbt_th = rssi_dbm_to_rssi_half_db(-62, priv->rssi_correction);
xpu_api->XPU_REG_LBT_TH_write(
    (auto_lbt_th << 16) | fpga_lbt_th
);
```

**Manual Configuration:**

```bash
# Read current LBT threshold
./sdrctl dev sdr0 get reg xpu 8

# Set LBT threshold (half-dB units)
# Lower = more conservative (waits for clearer channel)
# Higher = more aggressive (transmits with more interference)
./sdrctl dev sdr0 set reg drv_xpu 0 -62  # -62 dBm threshold
```

### Contention Window

**Configuration per Queue:**

**File:** `/home/user/openwifi/driver/sdr.c` (lines 2006-2041)

```c
static int openwifi_conf_tx(struct ieee80211_hw *dev,
                           struct ieee80211_vif *vif, u16 queue,
                           const struct ieee80211_tx_queue_params *params)
{
    u8 cw_min_exp, cw_max_exp;
    u32 reg_val;

    // Convert CW values to exponents
    // CW_min and CW_max are (2^exp - 1)
    cw_min_exp = log2val(params->cw_min + 1);
    cw_max_exp = log2val(params->cw_max + 1);

    // Pack into register (8 bits per queue)
    reg_val = (cw_min_exp | (cw_max_exp << 4)) << (queue * 8);

    // Write to XPU CSMA_CFG register
    xpu_api->XPU_REG_CSMA_CFG_write(reg_val);

    return 0;
}
```

**Default CW Values (802.11e EDCA):**

| Queue | AC | CW_min | CW_max | Purpose |
|-------|----|--------|--------|---------|
| 0 | VO (Voice) | 3 | 7 | Lowest latency |
| 1 | VI (Video) | 7 | 15 | Low latency |
| 2 | BE (Best Effort) | 15 | 1023 | Normal data |
| 3 | BK (Background) | 15 | 1023 | Bulk data |

**Manual Configuration:**

```bash
# Configure CW for specific queue using iw
iw dev sdr0 set txq be cw_min 15 cw_max 1023 aifs 3

# Or via xpu register (advanced)
./sdrctl dev sdr0 set reg xpu 19 0x43   # CW_min=3, CW_max=4 (2^4-1=15)
```

---

## Frame Processing

### Transmission Flow

**File:** `/home/user/openwifi/driver/sdr.c` (lines 975-1481)

```c
static void openwifi_tx(struct ieee80211_hw *dev,
                       struct ieee80211_tx_control *control,
                       struct sk_buff *skb)
{
    struct openwifi_priv *priv = dev->priv;
    struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
    struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)skb->data;

    // 1. Parse TX info from mac80211
    u8 rate_idx = info->control.rates[0].idx;
    bool is_ht = (info->control.rates[0].flags & IEEE80211_TX_RC_MCS);
    bool short_gi = (info->control.rates[0].flags & IEEE80211_TX_RC_SHORT_GI);
    u8 retry_limit = info->control.rates[0].count - 1;

    // 2. Calculate PHY parameters
    u32 phy_hdr_config = calculate_phy_header(rate_idx, is_ht,
                                               skb->len, short_gi);

    // 3. Handle A-MPDU aggregation
    if (info->flags & IEEE80211_TX_CTL_AMPDU) {
        add_mpdu_delimiter(skb);
    }

    // 4. Select queue based on priority
    u8 prio = skb->priority & 7;
    u8 queue_idx = queue_mapping[prio];

    // 5. Ring buffer management
    struct openwifi_ring *ring = &priv->tx_ring[queue_idx];
    if (ring_full(ring)) {
        ieee80211_stop_queue(dev, prio);
        return TX_BUSY;
    }

    // 6. DMA mapping
    dma_addr_t dma_addr = dma_map_single(priv->tx_chan->device->dev,
                                         skb->data, skb->len,
                                         DMA_TO_DEVICE);

    // 7. Configure FPGA registers
    tx_intf_api->TX_INTF_REG_PHY_HDR_CONFIG_write(phy_hdr_config);
    tx_intf_api->TX_INTF_REG_TX_CONFIG_write(tx_config);
    tx_intf_api->TX_INTF_REG_ANT_SEL_write(antenna_selection);

    // 8. Trigger DMA
    trigger_tx_dma(priv, dma_addr, skb->len);

    // 9. Update statistics
    priv->stat.tx_data_pkt_total++;
}
```

### Reception Flow

**File:** `/home/user/openwifi/driver/sdr.c` (lines 464-659)

```c
static irqreturn_t openwifi_rx_interrupt(int irq, void *dev_id)
{
    struct ieee80211_hw *dev = dev_id;
    struct openwifi_priv *priv = dev->priv;
    u8 *cyclic_buf = priv->rx_cyclic_buf;

    // Scan cyclic DMA buffer for packets
    for (int i = 0; i < NUM_RX_BD; i++) {
        u8 *pkt = cyclic_buf + (i * RX_BD_BUF_SIZE);

        // 1. Check packet exists flag
        u16 pkt_exist = *((u16 *)(pkt + 10));
        if (!(pkt_exist & 0x8000))
            continue;

        // 2. Parse metadata
        u64 tsf = *((u64 *)pkt);
        u16 rssi_half_db = *((u16 *)(pkt + 8));
        u16 agc_gain = *((u16 *)(pkt + 10)) & 0xFF;
        u16 pkt_len = *((u16 *)(pkt + 12));
        u8 rate_idx = *(pkt + 14);
        u8 ht_flag = *(pkt + 15) & 0x80;

        // 3. Validate packet
        if (pkt_len < 14 || pkt_len > 1600)
            continue;

        // 4. Convert RSSI
        int signal_dbm = rssi_half_db_to_rssi_dbm(rssi_half_db,
                                                   priv->rssi_correction);

        // 5. Allocate sk_buff
        struct sk_buff *skb = dev_alloc_skb(pkt_len + 64);
        skb_put(skb, pkt_len);
        memcpy(skb->data, pkt + 16, pkt_len);

        // 6. Fill RX status
        struct ieee80211_rx_status *status = IEEE80211_SKB_CB(skb);
        status->mactime = tsf;
        status->flag = RX_FLAG_MACTIME_START;
        status->freq = priv->actual_rx_freq;
        status->band = priv->band;
        status->signal = signal_dbm;
        status->rate_idx = rate_idx;
        if (ht_flag)
            status->encoding = RX_ENC_HT;

        // 7. Pass to mac80211
        ieee80211_rx_irqsafe(dev, skb);

        // 8. Update statistics
        priv->stat.rx_data_pkt_total++;

        // 9. Clear packet exists flag
        *((u16 *)(pkt + 10)) &= 0x7FFF;
    }

    return IRQ_HANDLED;
}
```

---

## Timing and Coordination

### TSF Timer

**64-bit Timer with 1 µs Resolution**

**File:** `/home/user/openwifi/driver/sdr.c` (lines 2087-2131)

```c
static u64 openwifi_get_tsf(struct ieee80211_hw *dev,
                           struct ieee80211_vif *vif)
{
    u32 tsft_low  = xpu_api->XPU_REG_TSF_RUNTIME_VAL_LOW_read();
    u32 tsft_high = xpu_api->XPU_REG_TSF_RUNTIME_VAL_HIGH_read();

    return ((u64)tsft_low) | (((u64)tsft_high) << 32);
}

static void openwifi_set_tsf(struct ieee80211_hw *dev,
                             struct ieee80211_vif *vif, u64 tsf)
{
    u32 tsf_low = (u32)(tsf & 0xFFFFFFFF);
    u32 tsf_high = (u32)(tsf >> 32);

    xpu_api->XPU_REG_TSF_LOAD_VAL_LOW_write(tsf_low);
    xpu_api->XPU_REG_TSF_LOAD_VAL_HIGH_write(tsf_high);
    xpu_api->XPU_REG_TSF_LOAD_VAL_write(1);  // Trigger load
}

static void openwifi_reset_tsf(struct ieee80211_hw *dev,
                               struct ieee80211_vif *vif)
{
    openwifi_set_tsf(dev, vif, 0);
}
```

**Usage:**

```bash
# Read TSF timer
./sdrctl dev sdr0 get reg xpu 58   # Low 32 bits
./sdrctl dev sdr0 get reg xpu 59   # High 32 bits

# Reset TSF timer
./sdrctl dev sdr0 set reg xpu 2 0  # Low bits
./sdrctl dev sdr0 set reg xpu 3 0  # High bits
./sdrctl dev sdr0 set reg xpu 4 1  # Trigger load
```

### ACK Handling

**Automatic ACK Generation (FPGA)**

When a packet is received and filtering passes:
1. XPU checks if ACK is required (non-broadcast, data/management frame)
2. Generates ACK frame automatically
3. Transmits ACK after SIFS (16 µs)
4. No software intervention

**ACK Reception:**

After TX, hardware waits for ACK:
1. SIFS period: 16 µs
2. ACK timeout: Configurable (default ~55 µs)
3. Result reported via TX interrupt

**Configuration:**

```bash
# Read ACK timeout configuration
./sdrctl dev sdr0 get reg xpu 14

# Adjust ACK wait timeout (expert use only)
# Register format: [31:24]=top_th, [23:16]=config, [15:8]=sifs_adj, [7:0]=calibrated
./sdrctl dev sdr0 set reg xpu 14 0x00370919
```

---

## Advanced Features

### A-MPDU Aggregation

**Maximum AMPDU Size:** 4 MPDUs (limited by buffer)

**Enabling:**

```bash
# Load driver with test_mode=1 to enable AMPDU
./wgd.sh 1

# Or manually
insmod sdr.ko test_mode=1
```

**MPDU Delimiter Format:**

```c
// File: /home/user/openwifi/driver/sdr.c (lines 975-1100)

struct mpdu_delim {
    u16 mpdu_len : 12;  // MPDU length
    u8  sig : 4;        // Signature (0xF)
    u8  delim_crc : 8;  // CRC-8 of delimiter
    u8  reserved : 8;   // Reserved
} __packed;  // Total: 4 bytes
```

**Block ACK:**

```c
// File: /home/user/openwifi/driver/sdr.c (lines 2087-2131)

static int openwifi_ampdu_action(struct ieee80211_hw *dev,
                                 struct ieee80211_vif *vif,
                                 struct ieee80211_ampdu_params *params)
{
    switch (params->action) {
    case IEEE80211_AMPDU_TX_START:
        // Start aggregation session
        return IEEE80211_AMPDU_TX_START_IMMEDIATE;

    case IEEE80211_AMPDU_TX_OPERATIONAL:
        // Configure buffer size
        u16 buf_size = 4;  // Max 4 MPDUs
        params->buf_size = buf_size;
        break;

    case IEEE80211_AMPDU_RX_START:
        // RX aggregation (limited support)
        break;
    }

    return 0;
}
```

### Network Slicing (Time Division)

**Concept:** Divide airtime into time slices, assign MAC addresses to specific slices

**Configuration per Queue:**

```bash
# Configure slice parameters for queue 0
QUEUE=0
TOTAL_US=1000      # Total cycle time in microseconds
START_US=0         # Start time for this slice
END_US=400         # End time for this slice
MAC="00:11:22:33:44:55"

# Set total cycle time
./sdrctl dev sdr0 set reg xpu 46 $((($QUEUE << 20) | $TOTAL_US))

# Set start time
./sdrctl dev sdr0 set reg xpu 47 $((($QUEUE << 20) | $START_US))

# Set end time
./sdrctl dev sdr0 set reg xpu 48 $((($QUEUE << 20) | $END_US))

# Assign MAC address to this slice
./sdrctl dev sdr0 set addr $MAC $QUEUE
```

**Use Case:** Wireless Time-Sensitive Networking (TSN), guaranteed airtime for industrial IoT

### Frame Filtering

**File:** `/home/user/openwifi/driver/sdr.c` (lines 2050-2085)

```c
static void openwifi_configure_filter(struct ieee80211_hw *dev,
                                      unsigned int changed_flags,
                                      unsigned int *total_flags,
                                      u64 multicast)
{
    u32 filter_flag = 0;

    // Unicast for us
    if (*total_flags & FIF_UNICAST)
        filter_flag |= UNICAST_FOR_US;

    // Broadcast
    if (*total_flags & FIF_BROADCAST)
        filter_flag |= (BROADCAST_ALL_ONE | BROADCAST_ALL_ZERO);

    // Beacon for our BSS
    filter_flag |= MY_BEACON;

    // Monitor mode (promiscuous)
    if (*total_flags & FIF_OTHER_BSS)
        filter_flag |= MONITOR_ALL;

    // Write to FPGA
    xpu_api->XPU_REG_FILTER_FLAG_write(filter_flag);
}
```

**Filter Flags:**

```c
// File: /home/user/openwifi/driver/hw_def.h (lines 400-410)

#define UNICAST_FOR_US       (1 << 9)
#define BROADCAST_ALL_ONE    (1 << 10)
#define BROADCAST_ALL_ZERO   (1 << 11)
#define MY_BEACON            (1 << 12)
#define MONITOR_ALL          (1 << 13)
#define HIGH_PRIORITY_DISCARD (1 << 14)
```

---

## Performance Characteristics

### Measured Throughput

| Scenario | TCP | UDP | Notes |
|----------|-----|-----|-------|
| Single stream | 40-50 Mbps | 50 Mbps | Without aggregation |
| With A-MPDU | 45-55 Mbps | 55 Mbps | Experimental |
| Theoretical (MCS 7) | 65 Mbps | 65 Mbps | Perfect conditions |

### Latency Breakdown

**TX Path:**
- Software (sdr.c): 10-50 µs
- DMA transfer: 2-5 µs
- Queue wait (CSMA): 0-500 µs
- OFDM modulation: 5-20 µs
- Air time: 20-1000 µs
- **Total:** 50 µs - 1.6 ms

**RX Path:**
- OFDM demod: 20-50 µs
- DMA transfer: 2-5 µs
- Interrupt latency: 1-10 µs
- Software: 10-50 µs
- **Total:** 35-115 µs

### Sensitivity

| MCS | Modulation | Code Rate | Sensitivity |
|-----|------------|-----------|-------------|
| 0 | BPSK | 1/2 | -92 dBm |
| 1 | QPSK | 1/2 | -89 dBm |
| 2 | QPSK | 3/4 | -87 dBm |
| 3 | 16-QAM | 1/2 | -84 dBm |
| 4 | 16-QAM | 3/4 | -81 dBm |
| 5 | 64-QAM | 2/3 | -78 dBm |
| 6 | 64-QAM | 3/4 | -76 dBm |
| 7 | 64-QAM | 5/6 | -73 dBm |

---

## Troubleshooting

### Common Issues

**1. No RX Packets**

```bash
# Check RX statistics
cat /sys/devices/platform/fpga-axi@0/fpga-axi@0:sdr/rx_stat

# Check power threshold
./sdrctl dev sdr0 get reg rx 2

# Lower threshold to be more sensitive
./sdrctl dev sdr0 set reg rx 2 100
```

**2. Poor TX Performance**

```bash
# Check TX statistics
cat /sys/devices/platform/fpga-axi@0/fpga-axi@0:sdr/tx_stat

# Check BB gain
./sdrctl dev sdr0 get reg tx_intf 13

# Adjust if needed (default: 250)
./sdrctl dev sdr0 set reg tx_intf 13 300
```

**3. Viterbi Decoder Halt**

```bash
# Check decoder state (should change every reception)
./sdrctl dev sdr0 get reg rx 20

# If stuck, reload FPGA
./load_fpga_img.sh
```

**4. High Packet Error Rate**

```bash
# Check RSSI
./rssi_openwifi_show.sh

# Check AGC gain
./rx_gain_show.sh

# Adjust RX gain if needed
./set_rx_gain_manual.sh 50  # 0-73 dB
```

---

## References

### Source Files

- Main driver: `/home/user/openwifi/driver/sdr.c`
- XPU controller: `/home/user/openwifi/driver/xpu/xpu.c`
- OFDM RX: `/home/user/openwifi/driver/openofdm_rx/openofdm_rx.c`
- OFDM TX: `/home/user/openwifi/driver/openofdm_tx/openofdm_tx.c`
- Hardware defs: `/home/user/openwifi/driver/hw_def.h`

### IEEE Standards

- IEEE 802.11-2016: WiFi standard
- IEEE 802.11n-2009: High Throughput amendments
- IEEE 802.11e: QoS enhancements

### External Documentation

- [Linux mac80211](https://wireless.wiki.kernel.org/en/developers/documentation/mac80211)
- [OFDM Tutorial](https://www.mathworks.com/help/comm/ug/ofdm-modulation.html)
- [Viterbi Decoding](https://en.wikipedia.org/wiki/Viterbi_decoder)

---

**Document Version:** 1.0
**Last Updated:** 2025-11-21
**License:** AGPL-3.0-or-later
