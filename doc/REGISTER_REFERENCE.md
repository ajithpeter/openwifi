# OpenWiFi FPGA Register Reference Guide

This document provides a comprehensive reference for all FPGA module registers in the OpenWiFi project. All registers are 32-bit wide and accessed via AXI-Lite interface.

## Table of Contents

1. [TX Interface Registers](#tx-interface-registers)
2. [RX Interface Registers](#rx-interface-registers)
3. [XPU Registers (Low MAC Controller)](#xpu-registers)
4. [OFDM TX Registers](#ofdm-tx-registers)
5. [OFDM RX Registers](#ofdm-rx-registers)
6. [Side Channel Registers](#side-channel-registers)
7. [Usage with sdrctl](#usage-with-sdrctl)

---

## TX Interface Registers

Module: `tx_intf` (sdr,tx_intf)

### Register Map

| Register Name | Offset | Access | Default Value | Description |
|--------------|--------|--------|---------------|-------------|
| TX_INTF_REG_MULTI_RST | 0x00 | R/W | 0x00000000 | Multi-module reset control |
| TX_INTF_REG_ARBITRARY_IQ | 0x04 | R/W | - | Arbitrary IQ sample control |
| TX_INTF_REG_WIFI_TX_MODE | 0x08 | R/W | 0x00000028 | WiFi TX mode configuration |
| TX_INTF_REG_CTS_TOSELF_CONFIG | 0x10 | R/W | - | CTS-to-self configuration |
| TX_INTF_REG_CSI_FUZZER | 0x14 | R/W | 0x00000000 | CSI fuzzer control |
| TX_INTF_REG_CTS_TOSELF_WAIT_SIFS_TOP | 0x18 | R/W | 0x00A000A0 | CTS-to-self SIFS timing |
| TX_INTF_REG_ARBITRARY_IQ_CTL | 0x1C | R/W | - | Arbitrary IQ control |
| TX_INTF_REG_TX_CONFIG | 0x20 | R/W | - | TX configuration |
| TX_INTF_REG_NUM_DMA_SYMBOL_TO_PS | 0x24 | R/W | 8 | Number of DMA symbols to PS |
| TX_INTF_REG_CFG_DATA_TO_ANT | 0x28 | R/W | 0x00000000 | Data to antenna configuration |
| TX_INTF_REG_S_AXIS_FIFO_TH | 0x2C | R/W | 8192-(210*2) | S_AXIS FIFO threshold |
| TX_INTF_REG_TX_HOLD_THRESHOLD | 0x30 | R/W | 420 | TX hold threshold |
| TX_INTF_REG_BB_GAIN | 0x34 | R/W | 250 | Baseband gain |
| TX_INTF_REG_INTERRUPT_SEL | 0x38 | R/W | 0x00030004 | Interrupt source selection |
| TX_INTF_REG_AMPDU_ACTION_CONFIG | 0x3C | R/W | - | AMPDU action configuration |
| TX_INTF_REG_ANT_SEL | 0x40 | R/W | - | Antenna selection |
| TX_INTF_REG_PHY_HDR_CONFIG | 0x44 | R/W | - | PHY header configuration |
| TX_INTF_REG_S_AXIS_FIFO_NO_ROOM | 0x54 | R/W | - | S_AXIS FIFO no room status |
| TX_INTF_REG_PKT_INFO1 | 0x58 | R/W | - | Packet information 1 |
| TX_INTF_REG_PKT_INFO2 | 0x5C | R/W | - | Packet information 2 |
| TX_INTF_REG_PKT_INFO3 | 0x60 | R/W | - | Packet information 3 |
| TX_INTF_REG_PKT_INFO4 | 0x64 | R/W | - | Packet information 4 |
| TX_INTF_REG_QUEUE_FIFO_DATA_COUNT | 0x68 | R | - | Queue FIFO data count |

### Detailed Register Descriptions

#### TX_INTF_REG_MULTI_RST (0x00)
**Purpose:** Multi-module reset control for TX interface

**Bit Fields:**
- Bit [31:0]: Reset control bits for various TX sub-modules

**Usage:**
```bash
# Reset TX interface
./sdrctl dev sdr0 set reg tx_intf 0 0xFFFFFFFF
./sdrctl dev sdr0 set reg tx_intf 0 0x00000000
```

#### TX_INTF_REG_WIFI_TX_MODE (0x08)
**Purpose:** Configure WiFi TX mode

**Bit Fields:**
- Bit [3]: TX mode bit 0
- Bit [5:4]: TX mode bits [2:1]

**Default:** 0x00000028 (bit3=1, bit5:4=2)

#### TX_INTF_REG_CTS_TOSELF_WAIT_SIFS_TOP (0x18)
**Purpose:** Configure SIFS timing for CTS-to-self

**Bit Fields:**
- Bit [15:0]: 2.4GHz SIFS timing (default: 16*10 = 160, counter at 10MHz)
- Bit [31:16]: 5GHz SIFS timing (default: 16*10 = 160, counter at 10MHz)

**Default:** 0x00A000A0

#### TX_INTF_REG_S_AXIS_FIFO_TH (0x2C)
**Purpose:** Threshold for S_AXIS FIFO to indicate no room for incoming packets

**Bit Fields:**
- Bit [31:0]: FIFO threshold in DMA symbols

**Default:**
- Large FPGA: 8192-(210*2) = 7772
- Small FPGA: 4096-(210*2) = 3676

#### TX_INTF_REG_TX_HOLD_THRESHOLD (0x30)
**Purpose:** Threshold for holding TX transmission

**Default:** 420

#### TX_INTF_REG_BB_GAIN (0x34)
**Purpose:** Baseband gain control for TX path

**Bit Fields:**
- Bit [31:0]: Gain value

**Default:** 250

**Notes:**
- Conservative value to prevent EVM degradation
- 290 works for 11a/g all MCS and 11n MCS 1-7
- 290 destroys 11n MCS 0 long packets due to high PAPR
- 250 is safe for all modes including 11n MCS 0

#### TX_INTF_REG_INTERRUPT_SEL (0x38)
**Purpose:** Select interrupt source

**Bit Fields:**
- Bit [2:0]: Source selection
  - 0: s00_axis_tlast
  - 1: ap_start
  - 2: tx_start_from_acc
  - 3: tx_end_from_acc
  - 4: tx_try_complete from XPU
- Bit [17:16]: Interrupt disable (0x3 = disabled)

**Default:** 0x00030004 (source 4, interrupt disabled)

#### TX_INTF_REG_ANT_SEL (0x40)
**Purpose:** Antenna selection for transmission

**Bit Fields:**
- Bit [0]: Antenna 0 enable
- Bit [1]: Antenna 1 enable
- Bit [4]: Antenna 0 enable (duplicate control)

**Values:**
- 0x01: Antenna 0 only
- 0x02: Antenna 1 only
- 0x11: Both antennas

---

## RX Interface Registers

Module: `rx_intf` (sdr,rx_intf)

### Register Map

| Register Name | Offset | Access | Default Value | Description |
|--------------|--------|--------|---------------|-------------|
| RX_INTF_REG_MULTI_RST | 0x00 | R/W | 0x00000000 | Multi-module reset control |
| RX_INTF_REG_MIXER_CFG | 0x04 | R/W | 0x300200F4 | Mixer configuration (legacy) |
| RX_INTF_REG_INTERRUPT_TEST | 0x08 | R/W | 0x00000100 | Interrupt test control |
| RX_INTF_REG_IQ_SRC_SEL | 0x0C | R/W | - | IQ source selection |
| RX_INTF_REG_IQ_CTRL | 0x10 | R/W | 0x00000000 | IQ control |
| RX_INTF_REG_START_TRANS_TO_PS_MODE | 0x14 | R/W | 0x00010025 | Transfer to PS mode control |
| RX_INTF_REG_START_TRANS_TO_PS | 0x18 | R/W | (1700<<16) | Start transfer to PS |
| RX_INTF_REG_START_TRANS_TO_PS_SRC_SEL | 0x1C | R/W | 0x00000000 | Transfer source selection |
| RX_INTF_REG_NUM_DMA_SYMBOL_TO_PL | 0x20 | R/W | 8 | Number of DMA symbols to PL |
| RX_INTF_REG_NUM_DMA_SYMBOL_TO_PS | 0x24 | R/W | 8 | Number of DMA symbols to PS |
| RX_INTF_REG_CFG_DATA_TO_ANT | 0x28 | R/W | 0x00000100 | Data to antenna configuration |
| RX_INTF_REG_BB_GAIN | 0x2C | R/W | 4 | Baseband gain |
| RX_INTF_REG_TLAST_TIMEOUT_TOP | 0x30 | R/W | 7000 | TLAST timeout threshold |
| RX_INTF_REG_S2MM_INTR_DELAY_COUNT | 0x34 | R/W | 300 | S2MM interrupt delay counter |
| RX_INTF_REG_ANT_SEL | 0x40 | R/W | - | Antenna selection |

### Detailed Register Descriptions

#### RX_INTF_REG_MULTI_RST (0x00)
**Purpose:** Multi-module reset control for RX interface

**Bit Fields:**
- Bit [2]: S_AXIS reset
- Bit [4]: M_AXIS reset
- Bit [31:0]: Reset control bits for various RX sub-modules

**Usage:**
```bash
# Reset RX interface
./sdrctl dev sdr0 set reg rx_intf 0 0xFFFFFFFF
./sdrctl dev sdr0 set reg rx_intf 0 0x00000000
```

#### RX_INTF_REG_MIXER_CFG (0x04)
**Purpose:** Mixer configuration (legacy, mixer removed in current design)

**Note:** This register is kept for compatibility but the mixer functionality has been removed from recent designs.

#### RX_INTF_REG_INTERRUPT_TEST (0x08)
**Purpose:** Control interrupt test mode

**Bit Fields:**
- Bit [8]: Test mode enable (1 = sig_valid and fcs_valid controlled by bit4 and bit0)
- Bit [4]: Signal valid control in test mode
- Bit [0]: FCS valid control in test mode

**Default:** 0x00000100 (test mode disabled)

**Values:**
- 0x000: Normal operation
- 0x100: Test mode, sig and fcs controlled by register
- 0x111: Test mode, sig and fcs high
- 0x110: Test mode, sig high, fcs low
- 0x101: Test mode, sig low, fcs high
- 0x100: Test mode, sig and fcs low

#### RX_INTF_REG_START_TRANS_TO_PS_MODE (0x14)
**Purpose:** Configure M_AXIS transfer mode to PS

**Bit Fields:**
- Bit [2:0]: Transfer trigger source
  - 0: fcs_valid_from_acc
  - 1: sig_valid_from_acc
  - 2: sig_invalid_from_acc
  - 3: start_1trans_s_axis_tlast_trigger
  - 4: start_1trans_s_axis_tready_trigger
  - 5: internal state machine with automatic num_dma_symbol_to_ps
  - 6: start_1trans_monitor_dma_to_ps_start_trigger
  - 7: start_1trans_ext_trigger
- Bit [3]: FCS invalid mode (0 = only fcs_valid, 1 = both fcs_valid and fcs_invalid)
- Bit [4]: num_dma_symbol_to_pl source (0 = from register, 1 = from monitor)
- Bit [5]: num_dma_symbol_to_ps source (0 = from register, 1 = from monitor/auto)
- Bit [6]: HT mode support (0 = non-HT only, 1 = both HT and non-HT)
- Bit [8]: Endless S_AXIS mode
- Bit [9]: Endless M_AXIS mode
- Bit [12]: Direct loopback mode
- Bit [16]: Auto M_AXIS reset enable
- Bit [24]: Disable M_AXIS FIFO reset by FCS invalid
- Bit [29:28]: sig_valid_mode (0 = non-HT, 1 = HT, other = both)

**Default:** 0x00010025 (trigger source 5, automatic num_dma_symbol_to_ps)

#### RX_INTF_REG_START_TRANS_TO_PS (0x18)
**Purpose:** Start transfer to PS and configure max packet length

**Bit Fields:**
- Bit [15:0]: Start transfer trigger (write to start)
- Bit [31:16]: Maximum packet length threshold (default: 1700)

**Default:** (1700<<16)

#### RX_INTF_REG_CFG_DATA_TO_ANT (0x28)
**Purpose:** Configure data path to antenna

**Bit Fields:**
- Bit [4]: Bypass enable
- Bit [8]: Configuration bit

**Default:** 0x00000100

#### RX_INTF_REG_BB_GAIN (0x2C)
**Purpose:** Baseband gain control for RX path

**Default:** 4

#### RX_INTF_REG_TLAST_TIMEOUT_TOP (0x30)
**Purpose:** Timeout threshold for TLAST signal

**Default:** 7000

#### RX_INTF_REG_S2MM_INTR_DELAY_COUNT (0x34)
**Purpose:** Delayed interrupt counter

**Bit Fields:**
- Bit [31:0]: Delay count (counter clock at 10MHz)

**Default:** 300 (30us delay at 10MHz)

#### RX_INTF_REG_ANT_SEL (0x40)
**Purpose:** Antenna selection for reception

**Bit Fields:**
- Bit [0]: Antenna selection (0 = ant0, 1 = ant1)

---

## XPU Registers

Module: `xpu` (sdr,xpu) - Low MAC Controller

### Register Map

| Register Name | Offset | Access | Default Value | Description |
|--------------|--------|--------|---------------|-------------|
| XPU_REG_MULTI_RST | 0x00 | R/W | 0x00000000 | Multi-module reset control |
| XPU_REG_SRC_SEL | 0x04 | R/W | - | Source selection |
| XPU_REG_TSF_LOAD_VAL_LOW | 0x08 | W | - | TSF timer load value (low 32-bit) |
| XPU_REG_TSF_LOAD_VAL_HIGH | 0x0C | W | - | TSF timer load value (high 32-bit) |
| XPU_REG_BAND_CHANNEL | 0x10 | R/W | - | Band and channel configuration |
| XPU_REG_DIFS_ADVANCE | 0x14 | R/W | 0x06A80002 | DIFS advance timing |
| XPU_REG_FORCE_IDLE_MISC | 0x18 | R/W | 0x0400004B | Force idle and misc control |
| XPU_REG_RSSI_DB_CFG | 0x1C | R/W | - | RSSI dB configuration |
| XPU_REG_LBT_TH | 0x20 | R/W | 174 | Listen Before Talk threshold |
| XPU_REG_CSMA_DEBUG | 0x24 | R/W | 0x00000000 | CSMA debug control |
| XPU_REG_BB_RF_DELAY | 0x28 | R/W | 0x10001A09 | Baseband-RF delay timing |
| XPU_REG_ACK_CTL_MAX_NUM_RETRANS | 0x2C | R/W | - | ACK control max retransmissions |
| XPU_REG_AMPDU_ACTION | 0x30 | R/W | - | AMPDU action control |
| XPU_REG_SPI_DISABLE | 0x34 | R/W | - | SPI disable control |
| XPU_REG_RECV_ACK_COUNT_TOP0 | 0x40 | R/W | 0x80023313 | Receive ACK timeout (2.4GHz) |
| XPU_REG_RECV_ACK_COUNT_TOP1 | 0x44 | R/W | 0x80023313 | Receive ACK timeout (5GHz) |
| XPU_REG_SEND_ACK_WAIT_TOP | 0x48 | R/W | 0x00330033 | Send ACK wait timing |
| XPU_REG_CSMA_CFG | 0x4C | R/W | - | CSMA configuration |
| XPU_REG_SLICE_COUNT_TOTAL | 0x50 | R/W | 16 | Time slice total duration |
| XPU_REG_SLICE_COUNT_START | 0x54 | R/W | 0 | Time slice start offset |
| XPU_REG_SLICE_COUNT_END | 0x58 | R/W | 16 | Time slice end offset |
| XPU_REG_CTS_TO_RTS_CONFIG | 0x68 | R/W | 0x000B0000 | CTS to RTS configuration |
| XPU_REG_FILTER_FLAG | 0x6C | R/W | - | Packet filter flags |
| XPU_REG_BSSID_FILTER_LOW | 0x70 | R/W | - | BSSID filter (low 32-bit) |
| XPU_REG_BSSID_FILTER_HIGH | 0x74 | R/W | - | BSSID filter (high 16-bit) |
| XPU_REG_MAC_ADDR_LOW | 0x78 | R/W | - | MAC address (low 32-bit) |
| XPU_REG_MAC_ADDR_HIGH | 0x7C | R/W | - | MAC address (high 16-bit) |
| XPU_REG_TSF_RUNTIME_VAL_LOW | 0xE8 | R | - | TSF timer runtime value (low) |
| XPU_REG_TSF_RUNTIME_VAL_HIGH | 0xEC | R | - | TSF timer runtime value (high) |
| XPU_REG_MAC_ADDR_READ_BACK | 0xF8 | R | - | MAC address read back |
| XPU_REG_FPGA_GIT_REV | 0xFC | R | - | FPGA git revision |

### Detailed Register Descriptions

#### XPU_REG_MULTI_RST (0x00)
**Purpose:** Multi-module reset control for XPU

**Bit Fields:**
- Bit [7]: Reset all slice counters simultaneously
- Bit [31:0]: Reset control bits for various XPU sub-modules

**Usage:**
```bash
# Reset all slice counters
./sdrctl dev sdr0 set reg xpu 0 0x80
./sdrctl dev sdr0 set reg xpu 0 0x00
```

#### XPU_REG_TSF_LOAD_VAL_LOW/HIGH (0x08, 0x0C)
**Purpose:** Load TSF (Timing Synchronization Function) timer value

**Bit Fields:**
- XPU_REG_TSF_LOAD_VAL_LOW [31:0]: Low 32-bit of TSF value
- XPU_REG_TSF_LOAD_VAL_HIGH [30:0]: High 31-bit of TSF value
- XPU_REG_TSF_LOAD_VAL_HIGH [31]: Load trigger (write 1 then 0 to load)

**Usage:**
```bash
# Reset TSF timer to 0
# This is done automatically via XPU_REG_TSF_LOAD_VAL_write() API
```

#### XPU_REG_BAND_CHANNEL (0x10)
**Purpose:** Configure operating band and channel/frequency

**Bit Fields:**
- Bit [15:0]: Channel/Frequency in MHz
- Bit [23:16]: Band selection
  - 0: BAND_900M
  - 1: BAND_2_4GHZ
  - 2: BAND_3_65GHZ
  - 3: BAND_5_0GHZ
  - 4: BAND_5_8GHZ
  - 5: BAND_5_9GHZ
  - 6: BAND_60GHZ
- Bit [24]: Use short slot (0 = long slot, 1 = short slot)

**Usage:**
```bash
# Read current band and channel
./sdrctl dev sdr0 get reg xpu 4
```

#### XPU_REG_DIFS_ADVANCE (0x14)
**Purpose:** Configure DIFS advance timing

**Bit Fields:**
- Bit [15:0]: DIFS advance in microseconds
- Bit [31:16]: Maximum packet length threshold

**Default:** 0x06A80002 (max_len=1700, advance=2us)

#### XPU_REG_FORCE_IDLE_MISC (0x18)
**Purpose:** Force channel idle duration and misc control

**Bit Fields:**
- Bit [15:0]: Force idle duration (in clock cycles)
- Bit [26]: Disable EIFS trigger by last TX fail

**Default:** 0x0400004B (disable EIFS trigger, 75 clock cycles force idle)

**Notes:**
- Compensates for AGC and signal imperfections
- Standard does not require EIFS trigger by TX fail, so bit 26 is set

#### XPU_REG_RSSI_DB_CFG (0x1C)
**Purpose:** Configure RSSI calculation parameters

**Bit Fields:**
- Bit [15:0]: AGC gain delay in samples
- Bit [30:16]: RSSI offset in 0.5dB units
- Bit [31]: Load trigger (write 1 then 0 to load)

**Default:** AGC gain delay=39, RSSI offset=75 (in 0.5dB, total 37.5dB)

**Usage:**
```bash
# Configuration is done via XPU_REG_RSSI_DB_CFG_write() API
```

#### XPU_REG_LBT_TH (0x20)
**Purpose:** Listen Before Talk threshold (CCA threshold)

**Bit Fields:**
- Bit [15:0]: RSSI threshold in 0.5dB units

**Default:** 174 (87dB = -62dBm with typical correction)

**Usage:**
```bash
# Set LBT threshold to specific value (1~2047, 0 = AUTO)
./sdrctl dev sdr0 set reg drv_xpu 0 value

# Get current LBT threshold
./sdrctl dev sdr0 get reg drv_xpu 0
```

#### XPU_REG_CSMA_DEBUG (0x24)
**Purpose:** CSMA debug control

**Default:** 0x00000000 (debug disabled)

#### XPU_REG_BB_RF_DELAY (0x28)
**Purpose:** Configure timing delays between baseband and RF

**Bit Fields:**
- Bit [7:0]: Delay parameter 0
- Bit [15:8]: Delay parameter 1
- Bit [23:16]: Delay parameter 2
- Bit [31:24]: Delay parameter 3

**Default:** 0x10001A09
- From CMW measurement: LO up 1us before packet
- LO down 0.4us after packet
- RF port switches 1.2us before and 0.2us after

#### XPU_REG_ACK_CTL_MAX_NUM_RETRANS (0x2C)
**Purpose:** Maximum number of retransmissions for ACK control

**Bit Fields:**
- Bit [7:0]: Max retransmission count (0 = use mac80211 value, >0 = override)

**Note:** If set > 0, overrides mac80211 retransmission limit

#### XPU_REG_RECV_ACK_COUNT_TOP0 (0x40)
**Purpose:** ACK reception timeout for 2.4GHz

**Bit Fields:**
- Bit [15:0]: ACK wait adjustment (counter at 10MHz)
- Bit [30:16]: ACK timeout value (counter at 10MHz)
- Bit [31]: Enable bit

**Default:** 0x80023313
- Timeout: (51+2+2)*10 + 15 = 565 (300 extra clocks for fake HT detection)
- Adjustment: 10+3 = 13

#### XPU_REG_RECV_ACK_COUNT_TOP1 (0x44)
**Purpose:** ACK reception timeout for 5GHz

**Bit Fields:**
- Same as XPU_REG_RECV_ACK_COUNT_TOP0

**Default:** 0x80023313 (same as 2.4GHz, assuming same SIFS)

#### XPU_REG_SEND_ACK_WAIT_TOP (0x48)
**Purpose:** Wait time before sending ACK

**Bit Fields:**
- Bit [15:0]: 2.4GHz ACK wait time
- Bit [31:16]: 5GHz ACK wait time

**Default:** 0x00330033 (51 for both bands)
- Calculated: (16+25+7-3+8-2) = 51
- Timing calibrated with IQ samples and various optimizations

#### XPU_REG_CSMA_CFG (0x4C)
**Purpose:** CSMA/CA configuration

**Note:** Configured via mac80211 openwifi_conf_tx() for each queue

**Usage:**
```bash
# Get current CSMA config
./sdrctl dev sdr0 get reg xpu 19

# Set CSMA config (gap in microseconds)
# Use OPENWIFI_CMD_SET_GAP/GET_GAP commands
```

#### XPU_REG_SLICE_COUNT_TOTAL/START/END (0x50, 0x54, 0x58)
**Purpose:** Time slicing for multi-queue scheduling

**Bit Fields:**
- Bit [19:0]: Time value in microseconds
- Bit [21:20]: Queue index (0-3)

**Default:**
- TOTAL: 16us per queue
- START: 0us per queue
- END: 16us per queue

**Usage:**
```bash
# Set slice parameters for queue 0
# SLICE_IDX: 0-3 for queues, 4 for reset all
./sdrctl dev sdr0 set slice_idx 0
./sdrctl dev sdr0 set slice_total 1000  # 1000us
./sdrctl dev sdr0 set slice_start 0
./sdrctl dev sdr0 set slice_end 500     # 500us

# Reset all slice counters
./sdrctl dev sdr0 set slice_idx 4
```

#### XPU_REG_CTS_TO_RTS_CONFIG (0x68)
**Purpose:** CTS response to RTS configuration

**Bit Fields:**
- Bit [19:16]: Rate for CTS response (OFDM rate)

**Default:** 0x000B0000 (rate 0xB = 6Mbps OFDM)

#### XPU_REG_FILTER_FLAG (0x6C)
**Purpose:** Packet filtering flags

**Bit Fields:** (based on ieee80211_filter_flags)
- Bit [1]: FIF_ALLMULTI - All multicast
- Bit [2]: FIF_FCSFAIL - FCS failed packets
- Bit [3]: FIF_PLCPFAIL - PLCP failed packets
- Bit [4]: FIF_BCN_PRBRESP_PROMISC - Beacon/probe response promiscuous
- Bit [5]: FIF_CONTROL - Control frames
- Bit [6]: FIF_OTHER_BSS - Other BSS packets
- Bit [7]: FIF_PSPOLL - PS-Poll frames
- Bit [8]: FIF_PROBE_REQ - Probe request frames
- Bit [9]: UNICAST_FOR_US - Unicast for this device
- Bit [10]: BROADCAST_ALL_ONE - Broadcast (FF:FF:FF:FF:FF:FF)
- Bit [11]: BROADCAST_ALL_ZERO - Broadcast (00:00:00:00:00:00)
- Bit [12]: MY_BEACON - Beacon for our BSSID
- Bit [13]: MONITOR_ALL - Monitor mode (all packets)

**Usage:**
```bash
# Get current filter flags
./sdrctl dev sdr0 get reg xpu 27
```

#### XPU_REG_BSSID_FILTER_LOW/HIGH (0x70, 0x74)
**Purpose:** BSSID filter for packet reception

**Bit Fields:**
- XPU_REG_BSSID_FILTER_LOW [31:0]: BSSID bytes [3:0]
- XPU_REG_BSSID_FILTER_HIGH [15:0]: BSSID bytes [5:4]

#### XPU_REG_MAC_ADDR_LOW/HIGH (0x78, 0x7C)
**Purpose:** Device MAC address

**Bit Fields:**
- XPU_REG_MAC_ADDR_LOW [31:0]: MAC address bytes [3:0]
- XPU_REG_MAC_ADDR_HIGH [15:0]: MAC address bytes [5:4]

**Usage:**
```bash
# Read MAC address
./sdrctl dev sdr0 get reg xpu 30  # Low 32-bit
./sdrctl dev sdr0 get reg xpu 31  # High 16-bit
```

#### XPU_REG_TSF_RUNTIME_VAL_LOW/HIGH (0xE8, 0xEC)
**Purpose:** Read current TSF timer value

**Bit Fields:**
- XPU_REG_TSF_RUNTIME_VAL_LOW [31:0]: Low 32-bit of TSF
- XPU_REG_TSF_RUNTIME_VAL_HIGH [31:0]: High 32-bit of TSF

**Usage:**
```bash
# Read TSF timer
./sdrctl dev sdr0 get reg xpu 58  # Low
./sdrctl dev sdr0 get reg xpu 59  # High
```

#### XPU_REG_FPGA_GIT_REV (0xFC)
**Purpose:** FPGA git revision for version identification

**Bit Fields:**
- Bit [31:0]: Git revision hash

**Usage:**
```bash
# Read FPGA version
./sdrctl dev sdr0 get reg xpu 63
```

---

## OFDM TX Registers

Module: `openofdm_tx` (sdr,openofdm_tx)

### Register Map

| Register Name | Offset | Access | Default Value | Description |
|--------------|--------|--------|---------------|-------------|
| OPENOFDM_TX_REG_MULTI_RST | 0x00 | W | 0x00000000 | Multi-module reset control |
| OPENOFDM_TX_REG_INIT_PILOT_STATE | 0x04 | W | 0x0000007F | Initial pilot scrambler state |
| OPENOFDM_TX_REG_INIT_DATA_STATE | 0x08 | W | 0x0000007F | Initial data scrambler state |

### Detailed Register Descriptions

#### OPENOFDM_TX_REG_MULTI_RST (0x00)
**Purpose:** Reset control for OFDM TX module

**Default:** 0x00000000

**Usage:**
```bash
# Reset OFDM TX
./sdrctl dev sdr0 set reg tx 0 0xFFFFFFFF
./sdrctl dev sdr0 set reg tx 0 0x00000000
```

#### OPENOFDM_TX_REG_INIT_PILOT_STATE (0x04)
**Purpose:** Initialize pilot tone scrambler state

**Bit Fields:**
- Bit [6:0]: Initial state for pilot scrambler

**Default:** 0x0000007F

#### OPENOFDM_TX_REG_INIT_DATA_STATE (0x08)
**Purpose:** Initialize data scrambler state

**Bit Fields:**
- Bit [6:0]: Initial state for data scrambler

**Default:** 0x0000007F

**Note:** These scrambler states are part of the 802.11 OFDM PHY specification

---

## OFDM RX Registers

Module: `openofdm_rx` (sdr,openofdm_rx)

### Register Map

| Register Name | Offset | Access | Default Value | Description |
|--------------|--------|--------|---------------|-------------|
| OPENOFDM_RX_REG_MULTI_RST | 0x00 | W | 0x00000000 | Multi-module reset control |
| OPENOFDM_RX_REG_ENABLE | 0x04 | W | 0x00000001 | RX enable control |
| OPENOFDM_RX_REG_POWER_THRES | 0x08 | W | - | Power threshold configuration |
| OPENOFDM_RX_REG_MIN_PLATEAU | 0x0C | W | 100 | Minimum plateau length |
| OPENOFDM_RX_REG_SOFT_DECODING | 0x10 | W | - | Soft decoding configuration |
| OPENOFDM_RX_REG_FFT_WIN_SHIFT | 0x14 | W | - | FFT window shift |
| OPENOFDM_RX_REG_PHASE_OFFSET_ABS_TH | 0x48 | W | 11 | Phase offset threshold |
| OPENOFDM_RX_REG_STATE_HISTORY | 0x50 | R | - | State machine history |

### Detailed Register Descriptions

#### OPENOFDM_RX_REG_MULTI_RST (0x00)
**Purpose:** Reset control for OFDM RX module

**Default:** 0x00000000

**Usage:**
```bash
# Reset OFDM RX
./sdrctl dev sdr0 set reg rx 0 0xFFFFFFFF
./sdrctl dev sdr0 set reg rx 0 0x00000000
```

#### OPENOFDM_RX_REG_ENABLE (0x04)
**Purpose:** Enable/disable RX processing

**Bit Fields:**
- Bit [0]: RX enable
- Bit [1]: Force HT smoothing for better sensitivity

**Default:** 0x00000001 (HT smoothing enabled)

#### OPENOFDM_RX_REG_POWER_THRES (0x08)
**Purpose:** Power threshold for packet detection

**Bit Fields:**
- Bit [15:0]: Power threshold in RSSI half-dB units
- Bit [31:16]: DC running sum threshold

**Default:** (64<<16) | 124
- Power threshold: 124 (based on sensitivity testing)
- DC running sum threshold: 64

**Notes:**
Based on testing:
- FMCOMMS3 @ 2437MHz: -85dBm sensitivity, rssi_half_db = 136
- FMCOMMS3 @ 5180MHz: -84dBm sensitivity, rssi_half_db = 122
- FMCOMMS3 @ 5320MHz: -86dBm sensitivity, rssi_half_db = 124
- Threshold set to 124 for best coverage

**Default RSSI threshold:** -95dBm (lowered from -85dBm due to improved performance)

**Usage:**
```bash
# Set demodulation threshold (0 = use default -95dBm, >0 = override)
./sdrctl dev sdr0 set reg drv_rx 1 85  # Set to -85dBm
./sdrctl dev sdr0 set reg drv_rx 1 0   # Use default
```

#### OPENOFDM_RX_REG_MIN_PLATEAU (0x0C)
**Purpose:** Minimum plateau length for packet detection

**Bit Fields:**
- Bit [31:0]: Minimum plateau samples

**Default:** 100 samples

#### OPENOFDM_RX_REG_SOFT_DECODING (0x10)
**Purpose:** Configure soft decoding and packet length limits

**Bit Fields:**
- Bit [0]: Soft decoding enable (1 = enabled)
- Bit [15:12]: Minimum packet length threshold
- Bit [31:16]: Maximum packet length threshold

**Default:**
- Soft decoding: Enabled (bit 0 = 1)
- Min length: 14 bytes (OPENWIFI_MIN_SIGNAL_LEN_TH)
- Max length: 1700 bytes (OPENWIFI_MAX_SIGNAL_LEN_TH)

**Note:** Packets outside these length bounds trigger early termination

#### OPENOFDM_RX_REG_FFT_WIN_SHIFT (0x14)
**Purpose:** Configure FFT window shift

**Bit Fields:**
- Bit [3:0]: FFT window shift value
- Bit [11:4]: Small EQ output counter threshold

**Default:**
- FFT window shift: 4
- Small EQ counter threshold: 48

#### OPENOFDM_RX_REG_PHASE_OFFSET_ABS_TH (0x48)
**Purpose:** Phase offset absolute threshold

**Bit Fields:**
- Bit [31:0]: Phase offset threshold

**Default:** 11

#### OPENOFDM_RX_REG_STATE_HISTORY (0x50)
**Purpose:** Read receiver state machine history for debugging

**Access:** Read-only

**Usage:**
```bash
# Read RX state history
./sdrctl dev sdr0 get reg rx 20

# Check if Viterbi decoder halted (output should change over time)
./sdrctl dev sdr0 get reg rx 20
```

**Note:** If this register value never changes, the Viterbi decoder may have halted (Xilinx evaluation license timeout)

---

## Side Channel Registers

Module: `side_ch` (sdr,side_ch)

### Register Map

| Register Name | Offset | Access | Default Value | Description |
|--------------|--------|--------|---------------|-------------|
| SIDE_CH_REG_MULTI_RST | 0x00 | W | 0x00000000 | Multi-module reset control |
| SIDE_CH_REG_CONFIG | 0x04 | R/W | 0x00000001 | Side channel configuration |
| SIDE_CH_REG_NUM_DMA_SYMBOL | 0x08 | R/W | - | Number of DMA symbols |
| SIDE_CH_REG_IQ_CAPTURE | 0x0C | R/W | 0 | IQ capture enable |
| SIDE_CH_REG_NUM_EQ | 0x10 | R/W | 8 | Number of equalizer outputs |
| SIDE_CH_REG_FC_TARGET | 0x14 | R/W | - | Frame control target |
| SIDE_CH_REG_ADDR1_TARGET | 0x18 | R/W | - | Address 1 target filter |
| SIDE_CH_REG_ADDR2_TARGET | 0x1C | R/W | - | Address 2 target filter |
| SIDE_CH_REG_IQ_TRIGGER | 0x20 | R/W | 0 | IQ capture trigger mode |
| SIDE_CH_REG_RSSI_TH | 0x24 | R/W | 0 | RSSI threshold for IQ trigger |
| SIDE_CH_REG_GAIN_TH | 0x28 | R/W | - | Gain threshold for IQ trigger |
| SIDE_CH_REG_PRE_TRIGGER_LEN | 0x2C | R/W | 8190 | Pre-trigger buffer length |
| SIDE_CH_REG_IQ_LEN | 0x30 | R/W | 0 | IQ capture length |
| SIDE_CH_REG_M_AXIS_DATA_COUNT | 0x50 | R | - | M_AXIS data count |

### Constants

- **CSI_LEN:** 56 (length of single CSI measurement)
- **EQUALIZER_LEN:** 52 (56-4, four padding values for non-HT)
- **HEADER_LEN:** 2 (timestamp and frequency offset)
- **MAX_NUM_DMA_SYMBOL:** 8192

### Detailed Register Descriptions

#### SIDE_CH_REG_MULTI_RST (0x00)
**Purpose:** Reset control for side channel module

**Default:** 0x00000000

#### SIDE_CH_REG_CONFIG (0x04)
**Purpose:** Configure side channel operation

**Bit Fields:**
- Bit [0]: Enable side channel capture
- Bit [12]: Match frame control
- Bit [13]: Match address 1
- Bit [14]: Match address 2

**Default:** 0x00000001 (allow all packets)

**Special values:**
- 0x7001: Most strict condition (match all filters, prevents capture)
- 0x0001: Allow all packets
- 0x6001: Match addr1 and addr2

**Usage:**
```bash
# Enable CSI capture for all packets
./sdrctl dev sdr0 set reg side_ch 1 0x0001

# Strict filtering (disable)
./sdrctl dev sdr0 set reg side_ch 1 0x7001
```

#### SIDE_CH_REG_NUM_DMA_SYMBOL (0x08)
**Purpose:** Configure number of DMA symbols

**Bit Fields:**
- Bit [15:0]: Number of symbols to PS
- Bit [31:16]: Number of symbols to PL

#### SIDE_CH_REG_IQ_CAPTURE (0x0C)
**Purpose:** Enable IQ sample capture mode

**Bit Fields:**
- Bit [0]: IQ capture enable (0 = CSI mode, 1 = IQ mode)

**Default:** 0 (CSI mode)

**Note:** When IQ capture is enabled, CSI capture is disabled

**Usage:**
Set via module parameter:
```bash
# Load module with IQ capture
insmod side_ch.ko iq_len_init=8187

# Load module with CSI capture (default)
insmod side_ch.ko num_eq_init=8
```

#### SIDE_CH_REG_NUM_EQ (0x10)
**Purpose:** Number of equalizer outputs to capture with CSI

**Bit Fields:**
- Bit [3:0]: Number of equalizer outputs (0-8)

**Default:** 8 (capture CSI + 8×52 equalizer outputs)

**Usage:**
Set via module parameter:
```bash
# Capture CSI + 8 equalizer outputs
insmod side_ch.ko num_eq_init=8

# Capture only CSI
insmod side_ch.ko num_eq_init=0
```

#### SIDE_CH_REG_FC_TARGET (0x14)
**Purpose:** Frame control field target for filtering

**Bit Fields:**
- Bit [15:0]: Frame control value to match

**Usage:**
Used with SIDE_CH_REG_CONFIG bit 12 for selective capture

#### SIDE_CH_REG_ADDR1_TARGET (0x18)
**Purpose:** Address 1 target for filtering (receiver address)

**Bit Fields:**
- Bit [31:0]: Low 32-bit of address 1

**Usage:**
Used with SIDE_CH_REG_CONFIG bit 13 for selective capture

#### SIDE_CH_REG_ADDR2_TARGET (0x1C)
**Purpose:** Address 2 target for filtering (transmitter address)

**Bit Fields:**
- Bit [31:0]: Low 32-bit of address 2

**Usage:**
Used with SIDE_CH_REG_CONFIG bit 14 for selective capture

#### SIDE_CH_REG_IQ_TRIGGER (0x20)
**Purpose:** IQ capture trigger mode selection

**Bit Fields:**
- Bit [3:0]: Trigger mode
  - 0: FCS OK/NOK (both)
  - 10: RSSI threshold

**Default:** 0 (FCS OK/NOK) when IQ capture enabled

**Usage:**
```bash
# Set trigger to RSSI with threshold
./sdrctl dev sdr0 set reg side_ch 8 10
./sdrctl dev sdr0 set reg side_ch 9 <rssi_value>
```

#### SIDE_CH_REG_RSSI_TH (0x24)
**Purpose:** RSSI threshold for IQ trigger mode

**Bit Fields:**
- Bit [31:0]: RSSI threshold value

**Default:** 0

**Note:** Only used when SIDE_CH_REG_IQ_TRIGGER = 10

#### SIDE_CH_REG_PRE_TRIGGER_LEN (0x2C)
**Purpose:** Pre-trigger buffer length for IQ capture

**Bit Fields:**
- Bit [15:0]: Pre-trigger length in samples

**Default:** 8190 (when IQ capture enabled)

#### SIDE_CH_REG_IQ_LEN (0x30)
**Purpose:** Total IQ capture length

**Bit Fields:**
- Bit [15:0]: IQ capture length in samples

**Default:** 0 (disabled)

**Max value:** 8187 samples (limited by UDP packet size of 65507 bytes)

**Usage:**
```bash
# Enable IQ capture with specific length via module param
insmod side_ch.ko iq_len_init=4096
```

#### SIDE_CH_REG_M_AXIS_DATA_COUNT (0x50)
**Purpose:** Read number of data symbols available in M_AXIS

**Access:** Read-only

**Bit Fields:**
- Bit [31:0]: Number of data symbols ready

**Usage:**
Used internally by driver to determine available CSI/IQ data

---

## Usage with sdrctl

The `sdrctl` utility provides a convenient interface to read and write FPGA registers from userspace.

### Basic Syntax

```bash
# Get register value
sdrctl dev sdr0 get reg <module_name> <reg_idx>

# Set register value
sdrctl dev sdr0 set reg <module_name> <reg_idx> <value>
```

### Module Names

| Module Name | Description | Register Category |
|------------|-------------|-------------------|
| tx_intf | TX Interface | TX_INTF_REG_* |
| rx_intf | RX Interface | RX_INTF_REG_* |
| xpu | XPU Low MAC | XPU_REG_* |
| tx | OFDM TX | OPENOFDM_TX_REG_* |
| rx | OFDM RX | OPENOFDM_RX_REG_* |
| side_ch | Side Channel | SIDE_CH_REG_* |
| drv_rx | Driver RX | Software parameters |
| drv_tx | Driver TX | Software parameters |
| drv_xpu | Driver XPU | Software parameters |
| rf | RF (AD9361) | RF parameters |

### Register Index

Register index is calculated as: `reg_idx = offset / 4`

For example:
- TX_INTF_REG_BB_GAIN (offset 0x34) → reg_idx = 13
- XPU_REG_CSMA_CFG (offset 0x4C) → reg_idx = 19
- OPENOFDM_RX_REG_STATE_HISTORY (offset 0x50) → reg_idx = 20

### Common Usage Examples

#### TX Interface

```bash
# Read TX baseband gain
./sdrctl dev sdr0 get reg tx_intf 13

# Set TX baseband gain
./sdrctl dev sdr0 set reg tx_intf 13 250

# Read antenna selection
./sdrctl dev sdr0 get reg tx_intf 16

# Set antenna to ant0 only
./sdrctl dev sdr0 set reg tx_intf 16 1

# Set antenna to both
./sdrctl dev sdr0 set reg tx_intf 16 17
```

#### RX Interface

```bash
# Read RX baseband gain
./sdrctl dev sdr0 get reg rx_intf 11

# Set RX baseband gain
./sdrctl dev sdr0 set reg rx_intf 11 4

# Read antenna selection
./sdrctl dev sdr0 get reg rx_intf 16

# Set antenna to ant1
./sdrctl dev sdr0 set reg rx_intf 16 1
```

#### XPU Registers

```bash
# Read TSF timer (low 32-bit)
./sdrctl dev sdr0 get reg xpu 58

# Read TSF timer (high 32-bit)
./sdrctl dev sdr0 get reg xpu 59

# Read current band and channel
./sdrctl dev sdr0 get reg xpu 4

# Read MAC address (low 32-bit)
./sdrctl dev sdr0 get reg xpu 30

# Read MAC address (high 16-bit)
./sdrctl dev sdr0 get reg xpu 31

# Read FPGA git revision
./sdrctl dev sdr0 get reg xpu 63

# Read current CSMA config
./sdrctl dev sdr0 get reg xpu 19

# Read filter flags
./sdrctl dev sdr0 get reg xpu 27

# Read LBT threshold (via driver wrapper)
./sdrctl dev sdr0 get reg drv_xpu 0

# Set LBT threshold (0 = AUTO, 1-2047 = specific value)
./sdrctl dev sdr0 set reg drv_xpu 0 0    # AUTO mode
./sdrctl dev sdr0 set reg drv_xpu 0 150  # Set to specific value
```

#### OFDM RX

```bash
# Check RX state (check if Viterbi decoder halted)
./sdrctl dev sdr0 get reg rx 20

# Read power threshold
./sdrctl dev sdr0 get reg rx 2

# Set demodulation threshold via driver
./sdrctl dev sdr0 set reg drv_rx 1 85  # -85dBm
./sdrctl dev sdr0 set reg drv_rx 1 0   # Use default (-95dBm)
```

#### RF Control

```bash
# Get TX attenuation
./sdrctl dev sdr0 get reg rf 0

# Set TX attenuation (0-89 dB, in 0.25dB steps)
./sdrctl dev sdr0 set reg rf 0 40  # 40 * 0.25 = 10dB attenuation

# Get TX frequency
./sdrctl dev sdr0 get reg rf 1

# Set TX frequency (MHz)
./sdrctl dev sdr0 set reg rf 1 2437  # 2437 MHz

# Get RX frequency
./sdrctl dev sdr0 get reg rf 5

# Set RX frequency (MHz)
./sdrctl dev sdr0 set reg rf 5 2437  # 2437 MHz

# Set non-standard frequency (after set_restrict_freq.sh)
./sdrctl dev sdr0 set reg rf 1 3500  # 3.5 GHz TX
./sdrctl dev sdr0 set reg rf 5 3500  # 3.5 GHz RX
```

#### Side Channel

```bash
# Enable CSI capture for all packets
./sdrctl dev sdr0 set reg side_ch 1 0x0001

# Disable side channel capture
./sdrctl dev sdr0 set reg side_ch 1 0x7001

# Set IQ trigger mode
./sdrctl dev sdr0 set reg side_ch 8 0   # FCS trigger
./sdrctl dev sdr0 set reg side_ch 8 10  # RSSI trigger

# Set RSSI threshold (for RSSI trigger mode)
./sdrctl dev sdr0 set reg side_ch 9 150
```

#### Time Slicing

```bash
# Select queue/slice (0-3)
./sdrctl dev sdr0 set slice_idx 0

# Set slice parameters for selected queue
./sdrctl dev sdr0 set slice_total 1000  # Total: 1000us
./sdrctl dev sdr0 set slice_start 0     # Start: 0us
./sdrctl dev sdr0 set slice_end 500     # End: 500us

# Get slice parameters
./sdrctl dev sdr0 get slice_total
./sdrctl dev sdr0 get slice_start
./sdrctl dev sdr0 get slice_end

# Reset all slice counters
./sdrctl dev sdr0 set slice_idx 4
```

#### CSMA/CA Gap Configuration

```bash
# Get current CSMA gap
./sdrctl dev sdr0 get gap

# Set CSMA gap (microseconds)
./sdrctl dev sdr0 set gap 9  # 9us gap
```

---

## Register Access Patterns

### Reset Sequence

Most modules use a standard reset sequence:

```c
// Write 0 multiple times
for (i=0; i<8; i++)
    REG_MULTI_RST_write(0);

// Write 0xFFFFFFFF multiple times
for (i=0; i<32; i++)
    REG_MULTI_RST_write(0xFFFFFFFF);

// Write 0 multiple times
for (i=0; i<8; i++)
    REG_MULTI_RST_write(0);
```

Example using sdrctl:
```bash
# Reset sequence for TX interface
for i in {1..8}; do ./sdrctl dev sdr0 set reg tx_intf 0 0; done
for i in {1..32}; do ./sdrctl dev sdr0 set reg tx_intf 0 0xFFFFFFFF; done
for i in {1..8}; do ./sdrctl dev sdr0 set reg tx_intf 0 0; done
```

### Configuration Load Sequence

Some registers require a load sequence (toggle MSB):

**Example: XPU_REG_TSF_LOAD_VAL**
```c
// Write low 32-bit
XPU_REG_TSF_LOAD_VAL_LOW_write(low_value);

// Write high 32-bit with MSB=1
XPU_REG_TSF_LOAD_VAL_HIGH_write(high_value | 0x80000000);

// Write high 32-bit with MSB=0 (load trigger)
XPU_REG_TSF_LOAD_VAL_HIGH_write(high_value & 0x7FFFFFFF);
```

**Example: XPU_REG_RSSI_DB_CFG**
```c
// Write config with MSB=1
XPU_REG_RSSI_DB_CFG_write(0x80000000 | config_value);

// Write config with MSB=0 (load trigger)
XPU_REG_RSSI_DB_CFG_write(config_value);
```

---

## Timing and Calibration Notes

### Clock Domains

- **10MHz counter:** Used for various timing (SIFS, ACK timeouts, etc.)
- **20MHz clock:** Used for sample-level timing in OFDM PHY

### Important Timing Values

**SIFS Timing:**
- 2.4GHz and 5GHz: Both use 16us (assumed same per current implementation)
- Counter runs at 10MHz
- Register value: 16 * 10 = 160 (0xA0)

**ACK Timing:**
- Send ACK wait: 51 counts = (16+25+7-3+8-2)
  - Base: 16us (SIFS)
  - +25us (processing)
  - +7us (IQ timing calibration)
  - -3us (Colvin LLR optimization)
  - +8us (faster DAC interface)
  - -2us (Oct 2024 calibration)

- Receive ACK timeout: (51+2+2)*10 + 15 = 565
  - SIFS + processing
  - +300 clocks for fake HT detection phase
  - +3 after Colvin LLR

**BB-RF Delay:**
- LO up: 1us before packet
- LO down: 0.4us after packet
- RF switch: 1.2us before, 0.2us after

### Sensitivity Calibration

**OPENOFDM_RX_POWER_THRES values based on testing:**

FMCOMMS3:
- 2437MHz: -85dBm sensitivity, rssi_half_db = 136
- 5180MHz: -84dBm sensitivity, rssi_half_db = 122
- 5320MHz: -86dBm sensitivity, rssi_half_db = 124

FMCOMMS2:
- 2437MHz: -80dBm sensitivity, rssi_half_db = 146
- 5180MHz: -83dBm sensitivity, rssi_half_db = 124
- 5320MHz: -86dBm sensitivity, rssi_half_db = 124

**Current thresholds:**
- Default RSSI threshold: -95dBm (improved from -85dBm)
- OPENOFDM_RX_POWER_THRES_INIT: 124

---

## Debugging Tips

### Check if System is Working

```bash
# Check RX state changes (should change over time)
watch -n 1 './sdrctl dev sdr0 get reg rx 20'

# Check TSF timer (should increment)
watch -n 1 './sdrctl dev sdr0 get reg xpu 58'

# Check FPGA version
./sdrctl dev sdr0 get reg xpu 63
```

### Common Issues

**Viterbi Decoder Halted:**
- Symptom: RX state register (rx 20) doesn't change
- Cause: Xilinx evaluation license timeout (~2 hours)
- Solution: Reload FPGA or power cycle

```bash
# Check if decoder halted
val1=$(./sdrctl dev sdr0 get reg rx 20)
sleep 1
val2=$(./sdrctl dev sdr0 get reg rx 20)
if [ "$val1" == "$val2" ]; then
    echo "Warning: RX decoder may be halted"
fi
```

**No Packets Received:**
- Check antenna selection
- Check RX gain settings
- Check frequency configuration
- Check packet filter flags

```bash
# Verify basic RX settings
./sdrctl dev sdr0 get reg rx_intf 16  # Antenna
./sdrctl dev sdr0 get reg rx_intf 11  # BB gain
./sdrctl dev sdr0 get reg xpu 4       # Band/channel
./sdrctl dev sdr0 get reg xpu 27      # Filter flags
```

**TX Not Working:**
- Check antenna selection
- Check TX gain/attenuation
- Check frequency configuration

```bash
# Verify basic TX settings
./sdrctl dev sdr0 get reg tx_intf 16  # Antenna
./sdrctl dev sdr0 get reg tx_intf 13  # BB gain
./sdrctl dev sdr0 get reg rf 0        # RF attenuation
```

---

## Register Categories by Function

### Reset Control
- TX_INTF_REG_MULTI_RST (0x00)
- RX_INTF_REG_MULTI_RST (0x00)
- XPU_REG_MULTI_RST (0x00)
- OPENOFDM_TX_REG_MULTI_RST (0x00)
- OPENOFDM_RX_REG_MULTI_RST (0x00)
- SIDE_CH_REG_MULTI_RST (0x00)

### Gain Control
- TX_INTF_REG_BB_GAIN (0x34) - Default: 250
- RX_INTF_REG_BB_GAIN (0x2C) - Default: 4
- RF attenuation via sdrctl reg rf 0

### Antenna Selection
- TX_INTF_REG_ANT_SEL (0x40)
- RX_INTF_REG_ANT_SEL (0x40)

### Timing Configuration
- TX_INTF_REG_CTS_TOSELF_WAIT_SIFS_TOP (0x18)
- XPU_REG_RECV_ACK_COUNT_TOP0 (0x40)
- XPU_REG_RECV_ACK_COUNT_TOP1 (0x44)
- XPU_REG_SEND_ACK_WAIT_TOP (0x48)
- XPU_REG_DIFS_ADVANCE (0x14)
- XPU_REG_BB_RF_DELAY (0x28)

### Packet Detection and Filtering
- OPENOFDM_RX_REG_POWER_THRES (0x08)
- XPU_REG_LBT_TH (0x20)
- XPU_REG_FILTER_FLAG (0x6C)
- XPU_REG_BSSID_FILTER_LOW/HIGH (0x70, 0x74)

### Side Channel / CSI Capture
- SIDE_CH_REG_CONFIG (0x04)
- SIDE_CH_REG_IQ_CAPTURE (0x0C)
- SIDE_CH_REG_NUM_EQ (0x10)
- SIDE_CH_REG_IQ_LEN (0x30)

### Debug and Status
- OPENOFDM_RX_REG_STATE_HISTORY (0x50)
- XPU_REG_TSF_RUNTIME_VAL_LOW/HIGH (0xE8, 0xEC)
- XPU_REG_FPGA_GIT_REV (0xFC)
- TX_INTF_REG_QUEUE_FIFO_DATA_COUNT (0x68)
- SIDE_CH_REG_M_AXIS_DATA_COUNT (0x50)

---

## References

- **Driver source:** `/driver/hw_def.h` - Register address definitions
- **TX Interface:** `/driver/tx_intf/tx_intf.c`
- **RX Interface:** `/driver/rx_intf/rx_intf.c`
- **XPU:** `/driver/xpu/xpu.c`
- **OFDM TX:** `/driver/openofdm_tx/openofdm_tx.c`
- **OFDM RX:** `/driver/openofdm_rx/openofdm_rx.c`
- **Side Channel:** `/driver/side_ch/side_ch.c`, `/driver/side_ch/side_ch.h`
- **sdrctl interface:** `/driver/sdrctl_intf.c`

---

## Revision History

| Version | Date | Description |
|---------|------|-------------|
| 1.0 | 2025 | Initial comprehensive register reference guide |

---

*This document is part of the OpenWiFi project. For more information, see the main README.md and documentation in /doc/.*
