# OpenWiFi Driver API Reference

This document provides a comprehensive reference for all driver APIs in the OpenWiFi software-defined radio (SDR) WiFi implementation. OpenWiFi provides a complete IEEE 802.11 a/g/n/ax compatible WiFi implementation using FPGA and Linux mac80211 subsystem.

**Authors:** Xianjun Jiao, Michael Mehari, Wei Liu
**License:** AGPL-3.0-or-later
**Organization:** UGent

## Table of Contents

1. [Main Driver API (ieee80211_ops)](#main-driver-api)
2. [Component Driver APIs](#component-driver-apis)
   - [TX Interface Driver API](#tx-interface-driver-api)
   - [RX Interface Driver API](#rx-interface-driver-api)
   - [XPU Driver API](#xpu-driver-api)
   - [OpenOFDM TX Driver API](#openofdm-tx-driver-api)
   - [OpenOFDM RX Driver API](#openofdm-rx-driver-api)
   - [Side Channel Driver API](#side-channel-driver-api)
3. [Data Structures](#data-structures)
4. [DMA Interfaces](#dma-interfaces)
5. [Interrupt Handlers](#interrupt-handlers)
6. [Sysfs Attributes](#sysfs-attributes)
7. [Testmode Commands](#testmode-commands)

---

## Main Driver API (ieee80211_ops)

**Location:** `/home/user/openwifi/driver/sdr.c` (lines 2133-2153)

The main driver exports the standard IEEE 802.11 mac80211 operations structure to the Linux kernel. This is the primary interface between the OpenWiFi driver and the Linux wireless subsystem.

### Structure Definition

```c
static const struct ieee80211_ops openwifi_ops = {
    .tx                = openwifi_tx,
    .start             = openwifi_start,
    .stop              = openwifi_stop,
    .add_interface     = openwifi_add_interface,
    .remove_interface  = openwifi_remove_interface,
    .config            = openwifi_config,
    .set_antenna       = openwifi_set_antenna,
    .get_antenna       = openwifi_get_antenna,
    .bss_info_changed  = openwifi_bss_info_changed,
    .conf_tx           = openwifi_conf_tx,
    .prepare_multicast = openwifi_prepare_multicast,
    .configure_filter  = openwifi_configure_filter,
    .rfkill_poll       = openwifi_rfkill_poll,
    .get_tsf           = openwifi_get_tsf,
    .set_tsf           = openwifi_set_tsf,
    .reset_tsf         = openwifi_reset_tsf,
    .set_rts_threshold = openwifi_set_rts_threshold,
    .ampdu_action      = openwifi_ampdu_action,
    .testmode_cmd      = openwifi_testmode_cmd,
};
```

### API Functions

#### openwifi_tx()
**Location:** sdr.c (referenced at line 2134)
**Signature:** `static void openwifi_tx(struct ieee80211_hw *dev, struct ieee80211_tx_control *control, struct sk_buff *skb)`

**Purpose:** Transmit a WiFi frame.

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `control`: TX control information
- `skb`: Socket buffer containing the frame to transmit

**Behavior:**
- Processes outgoing frames from mac80211
- Adds frames to appropriate TX queue based on priority
- Performs DMA mapping for transmission
- Handles TX ring buffer management
- Configures FPGA TX interface for packet transmission

---

#### openwifi_start()
**Location:** sdr.c (referenced at line 2135)
**Signature:** `static int openwifi_start(struct ieee80211_hw *dev)`

**Purpose:** Start the WiFi hardware.

**Parameters:**
- `dev`: IEEE 802.11 hardware device

**Returns:** 0 on success, negative error code on failure

**Behavior:**
- Initializes all FPGA modules (TX/RX interfaces, XPU, OFDM modules)
- Sets up DMA channels for TX and RX
- Configures hardware queues
- Enables interrupts
- Initializes RF frontend

---

#### openwifi_stop()
**Location:** sdr.c (referenced at line 2136)
**Signature:** `static void openwifi_stop(struct ieee80211_hw *dev)`

**Purpose:** Stop the WiFi hardware.

**Parameters:**
- `dev`: IEEE 802.11 hardware device

**Behavior:**
- Disables interrupts
- Stops DMA transfers
- Frees TX/RX ring buffers
- Puts FPGA modules into reset state

---

#### openwifi_add_interface()
**Location:** sdr.c (referenced at line 2137)
**Signature:** `static int openwifi_add_interface(struct ieee80211_hw *dev, struct ieee80211_vif *vif)`

**Purpose:** Add a virtual interface (e.g., STA, AP).

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `vif`: Virtual interface to add

**Returns:** 0 on success, negative error code on failure

**Behavior:**
- Validates interface type (STA, AP, MESH_POINT)
- Allocates virtual interface structure
- Configures MAC address filter
- Supports up to MAX_NUM_VIF (4) virtual interfaces

---

#### openwifi_remove_interface()
**Location:** sdr.c (referenced at line 2138)
**Signature:** `static void openwifi_remove_interface(struct ieee80211_hw *dev, struct ieee80211_vif *vif)`

**Purpose:** Remove a virtual interface.

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `vif`: Virtual interface to remove

**Behavior:**
- Cancels beacon work for AP mode
- Frees virtual interface structure
- Updates MAC address filter

---

#### openwifi_config()
**Location:** sdr.c (referenced at line 2139)
**Signature:** `static int openwifi_config(struct ieee80211_hw *dev, u32 changed)`

**Purpose:** Configure hardware based on configuration changes.

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `changed`: Bitmask indicating what changed

**Returns:** 0 on success, negative error code on failure

**Behavior:**
- Handles channel changes (IEEE80211_CONF_CHANGE_CHANNEL)
- Tunes RF frontend to new frequency
- Configures TX/RX frequency offsets
- Performs TX quadrature calibration when needed
- Updates RSSI correction values

---

#### openwifi_set_antenna()
**Location:** sdr.c (lines ~92, referenced at line 2140)
**Signature:** `static int openwifi_set_antenna(struct ieee80211_hw *dev, u32 tx_ant, u32 rx_ant)`

**Purpose:** Configure antenna selection.

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `tx_ant`: TX antenna mask
- `rx_ant`: RX antenna mask

**Returns:** 0 on success, negative error code on failure

**Behavior:**
- Sets antenna configuration for TX and RX
- Updates hardware registers
- Supports ANT0, ANT1, or BOTH configurations

---

#### openwifi_get_antenna()
**Location:** sdr.c (lines ~93, referenced at line 2141)
**Signature:** `static int openwifi_get_antenna(struct ieee80211_hw *dev, u32 *tx_ant, u32 *rx_ant)`

**Purpose:** Retrieve current antenna configuration.

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `tx_ant`: Pointer to store TX antenna mask
- `rx_ant`: Pointer to store RX antenna mask

**Returns:** 0 on success, negative error code on failure

---

#### openwifi_bss_info_changed()
**Location:** sdr.c (referenced at line 2142)
**Signature:** `static void openwifi_bss_info_changed(struct ieee80211_hw *dev, struct ieee80211_vif *vif, struct ieee80211_bss_conf *info, u32 changed)`

**Purpose:** Handle BSS information changes.

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `vif`: Virtual interface
- `info`: BSS configuration
- `changed`: Bitmask of changed parameters

**Behavior:**
- Updates BSSID filter
- Handles beacon enable/disable
- Configures slot time (short/long)
- Updates basic rate set

---

#### openwifi_conf_tx()
**Location:** sdr.c (referenced at line 2143)
**Signature:** `static int openwifi_conf_tx(struct ieee80211_hw *dev, struct ieee80211_vif *vif, u16 queue, const struct ieee80211_tx_queue_params *params)`

**Purpose:** Configure TX queue parameters (EDCA).

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `vif`: Virtual interface
- `queue`: Queue index (0-3)
- `params`: Queue parameters (AIFS, CW min/max, TXOP)

**Returns:** 0 on success, negative error code on failure

**Behavior:**
- Configures CSMA/CA parameters for each AC
- Sets AIFS, contention window, and TXOP limits
- Updates XPU CSMA configuration registers

---

#### openwifi_configure_filter()
**Location:** sdr.c (referenced at line 2145)
**Signature:** `static void openwifi_configure_filter(struct ieee80211_hw *dev, unsigned int changed_flags, unsigned int *total_flags, u64 multicast)`

**Purpose:** Configure packet filtering.

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `changed_flags`: Changed filter flags
- `total_flags`: Total filter flags
- `multicast`: Multicast filter

**Behavior:**
- Configures hardware packet filter
- Supports FIF_ALLMULTI, FIF_BCN_PRBRESP_PROMISC, FIF_CONTROL, etc.
- Updates XPU filter flag register

---

#### openwifi_rfkill_poll()
**Location:** sdr.c (lines 151-163, referenced at line 2146)
**Signature:** `void openwifi_rfkill_poll(struct ieee80211_hw *hw)`

**Purpose:** Poll RF kill switch status.

**Parameters:**
- `hw`: IEEE 802.11 hardware device

**Behavior:**
- Checks RF frontend TX attenuation to determine radio status
- Updates rfkill state in mac80211
- Polls radio on/off state

---

#### openwifi_get_tsf()
**Location:** sdr.c (referenced at line 2147)
**Signature:** `static u64 openwifi_get_tsf(struct ieee80211_hw *dev, struct ieee80211_vif *vif)`

**Purpose:** Get hardware TSF (Timing Synchronization Function) timer value.

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `vif`: Virtual interface

**Returns:** 64-bit TSF value in microseconds

**Behavior:**
- Reads TSF low and high registers from XPU
- Returns combined 64-bit timestamp

---

#### openwifi_set_tsf()
**Location:** sdr.c (referenced at line 2148)
**Signature:** `static void openwifi_set_tsf(struct ieee80211_hw *dev, struct ieee80211_vif *vif, u64 tsf)`

**Purpose:** Set hardware TSF timer value.

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `vif`: Virtual interface
- `tsf`: 64-bit TSF value to set

**Behavior:**
- Writes TSF value to XPU registers
- Used for TSF synchronization in BSS

---

#### openwifi_reset_tsf()
**Location:** sdr.c (referenced at line 2149)
**Signature:** `static void openwifi_reset_tsf(struct ieee80211_hw *dev, struct ieee80211_vif *vif)`

**Purpose:** Reset hardware TSF timer to zero.

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `vif`: Virtual interface

**Behavior:**
- Resets TSF to 0
- Used when starting a new IBSS or leaving BSS

---

#### openwifi_set_rts_threshold()
**Location:** sdr.c (referenced at line 2150)
**Signature:** `static int openwifi_set_rts_threshold(struct ieee80211_hw *dev, u32 value)`

**Purpose:** Set RTS/CTS threshold.

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `value`: RTS threshold in bytes

**Returns:** 0 on success

**Behavior:**
- Currently a placeholder (RTS/CTS not fully implemented in hardware)
- Future implementation will configure RTS threshold

---

#### openwifi_ampdu_action()
**Location:** sdr.c (lines 2086-2131, referenced at line 2151)
**Signature:** `static int openwifi_ampdu_action(struct ieee80211_hw *dev, struct ieee80211_vif *vif, struct ieee80211_ampdu_params *params)`

**Purpose:** Handle A-MPDU aggregation actions.

**Parameters:**
- `dev`: IEEE 802.11 hardware device
- `vif`: Virtual interface
- `params`: AMPDU parameters (action, station, TID, etc.)

**Returns:** 0 on success, -EOPNOTSUPP for unsupported actions

**Behavior:**
- Handles TX_START, TX_STOP, TX_OPERATIONAL actions
- Handles RX_START, RX_STOP actions
- Configures buffer size, AMPDU density, and max bytes
- Updates TX interface AMPDU configuration

---

#### openwifi_testmode_cmd()
**Location:** sdr.c (sdrctl_intf.c lines 5-150+, referenced at line 2152)
**Signature:** `static int openwifi_testmode_cmd(struct ieee80211_hw *hw, struct ieee80211_vif *vif, void *data, int len)`

**Purpose:** Handle testmode commands from user space (via sdrctl utility).

**Parameters:**
- `hw`: IEEE 802.11 hardware device
- `vif`: Virtual interface
- `data`: Command data
- `len`: Data length

**Returns:** 0 on success, negative error code on failure

**Behavior:**
- Provides user-space access to hardware registers
- Supports commands for: GAP, SLICE configuration, register R/W
- Used by sdrctl utility for hardware control
- See [Testmode Commands](#testmode-commands) section for details

---

## Component Driver APIs

OpenWiFi is modular with separate driver modules for each FPGA component. Each component exports an API structure that the main driver uses.

### TX Interface Driver API

**Location:** `/home/user/openwifi/driver/tx_intf/tx_intf.c`, API definition in `/home/user/openwifi/driver/hw_def.h` (lines 81-133)

**Exported Symbol:** `tx_intf_api` (line 229)

The TX interface handles packet transmission, DMA from PS to PL, and baseband signal formatting.

#### Structure Definition

```c
struct tx_intf_driver_api {
    u32 (*hw_init)(enum tx_intf_mode mode, u32 tx_config, u32 num_dma_symbol_to_ps, enum openwifi_fpga_type fpga_type);

    u32 (*reg_read)(u32 reg);
    void (*reg_write)(u32 reg, u32 value);

    // Register-specific read functions
    u32 (*TX_INTF_REG_MULTI_RST_read)(void);
    u32 (*TX_INTF_REG_ARBITRARY_IQ_read)(void);
    u32 (*TX_INTF_REG_WIFI_TX_MODE_read)(void);
    u32 (*TX_INTF_REG_CTS_TOSELF_CONFIG_read)(void);
    u32 (*TX_INTF_REG_CSI_FUZZER_read)(void);
    u32 (*TX_INTF_REG_CTS_TOSELF_WAIT_SIFS_TOP_read)(void);
    u32 (*TX_INTF_REG_ARBITRARY_IQ_CTL_read)(void);
    u32 (*TX_INTF_REG_TX_CONFIG_read)(void);
    u32 (*TX_INTF_REG_NUM_DMA_SYMBOL_TO_PS_read)(void);
    u32 (*TX_INTF_REG_CFG_DATA_TO_ANT_read)(void);
    u32 (*TX_INTF_REG_S_AXIS_FIFO_TH_read)(void);
    u32 (*TX_INTF_REG_TX_HOLD_THRESHOLD_read)(void);
    u32 (*TX_INTF_REG_INTERRUPT_SEL_read)(void);
    u32 (*TX_INTF_REG_AMPDU_ACTION_CONFIG_read)(void);
    u32 (*TX_INTF_REG_BB_GAIN_read)(void);
    u32 (*TX_INTF_REG_ANT_SEL_read)(void);
    u32 (*TX_INTF_REG_PHY_HDR_CONFIG_read)(void);
    u32 (*TX_INTF_REG_S_AXIS_FIFO_NO_ROOM_read)(void);
    u32 (*TX_INTF_REG_PKT_INFO1_read)(void);
    u32 (*TX_INTF_REG_PKT_INFO2_read)(void);
    u32 (*TX_INTF_REG_PKT_INFO3_read)(void);
    u32 (*TX_INTF_REG_PKT_INFO4_read)(void);
    u32 (*TX_INTF_REG_QUEUE_FIFO_DATA_COUNT_read)(void);

    // Register-specific write functions
    void (*TX_INTF_REG_MULTI_RST_write)(u32 value);
    void (*TX_INTF_REG_ARBITRARY_IQ_write)(u32 value);
    void (*TX_INTF_REG_WIFI_TX_MODE_write)(u32 value);
    void (*TX_INTF_REG_CTS_TOSELF_CONFIG_write)(u32 value);
    void (*TX_INTF_REG_CSI_FUZZER_write)(u32 value);
    void (*TX_INTF_REG_CTS_TOSELF_WAIT_SIFS_TOP_write)(u32 value);
    void (*TX_INTF_REG_ARBITRARY_IQ_CTL_write)(u32 value);
    void (*TX_INTF_REG_TX_CONFIG_write)(u32 value);
    void (*TX_INTF_REG_NUM_DMA_SYMBOL_TO_PS_write)(u32 value);
    void (*TX_INTF_REG_CFG_DATA_TO_ANT_write)(u32 value);
    void (*TX_INTF_REG_S_AXIS_FIFO_TH_write)(u32 value);
    void (*TX_INTF_REG_TX_HOLD_THRESHOLD_write)(u32 value);
    void (*TX_INTF_REG_INTERRUPT_SEL_write)(u32 value);
    void (*TX_INTF_REG_AMPDU_ACTION_CONFIG_write)(u32 value);
    void (*TX_INTF_REG_BB_GAIN_write)(u32 value);
    void (*TX_INTF_REG_ANT_SEL_write)(u32 value);
    void (*TX_INTF_REG_PHY_HDR_CONFIG_write)(u32 value);
    void (*TX_INTF_REG_S_AXIS_FIFO_NO_ROOM_write)(u32 value);
    void (*TX_INTF_REG_PKT_INFO1_write)(u32 value);
    void (*TX_INTF_REG_PKT_INFO2_write)(u32 value);
    void (*TX_INTF_REG_PKT_INFO3_write)(u32 value);
    void (*TX_INTF_REG_PKT_INFO4_write)(u32 value);
};
```

#### Key Functions

##### hw_init()
**Location:** tx_intf.c (lines 231-363)

**Signature:** `u32 hw_init(enum tx_intf_mode mode, u32 tx_config, u32 num_dma_symbol_to_ps, enum openwifi_fpga_type fpga_type)`

**Parameters:**
- `mode`: TX interface mode (AXIS_LOOP_BACK, BW_20MHZ_AT_0MHZ_ANT0, BW_20MHZ_AT_N_10MHZ_ANT0, etc.)
- `tx_config`: TX configuration value
- `num_dma_symbol_to_ps`: Number of DMA symbols
- `fpga_type`: FPGA type (SMALL_FPGA or LARGE_FPGA)

**Returns:** 0 on success, error code on failure

**Purpose:** Initialize TX interface hardware with specified mode and configuration.

**Behavior:**
- Resets TX interface module
- Configures mixer for frequency offset
- Sets antenna selection
- Configures FIFO thresholds (8192 for LARGE_FPGA, 4096 for SMALL_FPGA)
- Sets baseband gain to 250 (optimized for all MCS rates)
- Configures CTS-to-self and SIFS timing

**Usage Example:**
```c
err = tx_intf_api->hw_init(TX_INTF_BW_20MHZ_AT_0MHZ_ANT0, 8, 8, SMALL_FPGA);
```

##### Register Access Functions
All register access follows this pattern:

**reg_read/reg_write:**
```c
u32 value = tx_intf_api->reg_read(TX_INTF_REG_TX_CONFIG_ADDR);
tx_intf_api->reg_write(TX_INTF_REG_TX_CONFIG_ADDR, value);
```

**Named register functions:**
```c
u32 config = tx_intf_api->TX_INTF_REG_TX_CONFIG_read();
tx_intf_api->TX_INTF_REG_TX_CONFIG_write(new_config);
```

#### Register Map

| Register | Address | Purpose |
|----------|---------|---------|
| MULTI_RST | 0x00 | Multi-module reset control |
| ARBITRARY_IQ | 0x04 | Arbitrary IQ data input |
| WIFI_TX_MODE | 0x08 | WiFi TX mode configuration |
| CTS_TOSELF_CONFIG | 0x10 | CTS-to-self configuration |
| CSI_FUZZER | 0x14 | CSI fuzzing control |
| CTS_TOSELF_WAIT_SIFS_TOP | 0x18 | CTS-to-self SIFS timing |
| ARBITRARY_IQ_CTL | 0x1C | Arbitrary IQ control |
| TX_CONFIG | 0x20 | TX configuration |
| NUM_DMA_SYMBOL_TO_PS | 0x24 | DMA symbol count |
| CFG_DATA_TO_ANT | 0x28 | Data to antenna config |
| S_AXIS_FIFO_TH | 0x2C | FIFO threshold |
| TX_HOLD_THRESHOLD | 0x30 | TX hold threshold |
| BB_GAIN | 0x34 | Baseband gain (set to 250) |
| INTERRUPT_SEL | 0x38 | Interrupt source selection |
| AMPDU_ACTION_CONFIG | 0x3C | A-MPDU configuration |
| ANT_SEL | 0x40 | Antenna selection |
| PHY_HDR_CONFIG | 0x44 | PHY header configuration |
| S_AXIS_FIFO_NO_ROOM | 0x54 | FIFO no-room status |
| PKT_INFO1-4 | 0x58-0x64 | Packet information |
| QUEUE_FIFO_DATA_COUNT | 0x68 | Queue FIFO data count |

---

### RX Interface Driver API

**Location:** `/home/user/openwifi/driver/rx_intf/rx_intf.c`, API definition in `/home/user/openwifi/driver/hw_def.h` (lines 171-209)

**Exported Symbol:** `rx_intf_api` (line 169)

The RX interface handles packet reception, DMA from PL to PS, and baseband signal processing.

#### Structure Definition

```c
struct rx_intf_driver_api {
    u32 io_start;
    u32 base_addr;

    u32 (*hw_init)(enum rx_intf_mode mode, u32 num_dma_symbol_to_pl, u32 num_dma_symbol_to_ps);

    u32 (*reg_read)(u32 reg);
    void (*reg_write)(u32 reg, u32 value);

    u32 (*RX_INTF_REG_MULTI_RST_read)(void);
    u32 (*RX_INTF_REG_MIXER_CFG_read)(void);
    u32 (*RX_INTF_REG_IQ_SRC_SEL_read)(void);
    u32 (*RX_INTF_REG_IQ_CTRL_read)(void);
    u32 (*RX_INTF_REG_START_TRANS_TO_PS_MODE_read)(void);
    u32 (*RX_INTF_REG_START_TRANS_TO_PS_read)(void);
    u32 (*RX_INTF_REG_START_TRANS_TO_PS_SRC_SEL_read)(void);
    u32 (*RX_INTF_REG_NUM_DMA_SYMBOL_TO_PL_read)(void);
    u32 (*RX_INTF_REG_NUM_DMA_SYMBOL_TO_PS_read)(void);
    u32 (*RX_INTF_REG_CFG_DATA_TO_ANT_read)(void);
    u32 (*RX_INTF_REG_ANT_SEL_read)(void);
    u32 (*RX_INTF_REG_INTERRUPT_TEST_read)(void);

    void (*RX_INTF_REG_MULTI_RST_write)(u32 value);
    void (*RX_INTF_REG_MIXER_CFG_write)(u32 value);
    void (*RX_INTF_REG_IQ_SRC_SEL_write)(u32 value);
    void (*RX_INTF_REG_IQ_CTRL_write)(u32 value);
    void (*RX_INTF_REG_START_TRANS_TO_PS_MODE_write)(u32 value);
    void (*RX_INTF_REG_START_TRANS_TO_PS_write)(u32 value);
    void (*RX_INTF_REG_START_TRANS_TO_PS_SRC_SEL_write)(u32 value);
    void (*RX_INTF_REG_NUM_DMA_SYMBOL_TO_PL_write)(u32 value);
    void (*RX_INTF_REG_NUM_DMA_SYMBOL_TO_PS_write)(u32 value);
    void (*RX_INTF_REG_CFG_DATA_TO_ANT_write)(u32 value);
    void (*RX_INTF_REG_BB_GAIN_write)(u32 value);
    void (*RX_INTF_REG_ANT_SEL_write)(u32 value);
    void (*RX_INTF_REG_INTERRUPT_TEST_write)(u32 value);

    void (*RX_INTF_REG_M_AXIS_RST_write)(u32 value);
    void (*RX_INTF_REG_S2MM_INTR_DELAY_COUNT_write)(u32 value);
    void (*RX_INTF_REG_TLAST_TIMEOUT_TOP_write)(u32 value);
};
```

#### Key Functions

##### hw_init()
**Location:** rx_intf.c (lines 171-342)

**Signature:** `u32 hw_init(enum rx_intf_mode mode, u32 num_dma_symbol_to_pl, u32 num_dma_symbol_to_ps)`

**Parameters:**
- `mode`: RX interface mode (AXIS_LOOP_BACK, BW_20MHZ_AT_0MHZ_ANT0, etc.)
- `num_dma_symbol_to_pl`: Number of DMA symbols to PL
- `num_dma_symbol_to_ps`: Number of DMA symbols to PS

**Returns:** 0 on success, error code on failure

**Purpose:** Initialize RX interface hardware with specified mode.

**Behavior:**
- Sets TLAST timeout to 7000
- Resets RX interface module
- Holds M_AXIS in reset (released in openwifi_start)
- Configures mixer for frequency offset (no longer used in new design)
- Sets interrupt delay to 30*10 (300us with 10MHz clock)
- Configures transfer mode (bit5=1 for automatic packet length detection)
- Sets max packet length threshold
- Configures baseband gain to 4
- Supports loopback mode for testing

**Usage Example:**
```c
err = rx_intf_api->hw_init(RX_INTF_BW_20MHZ_AT_0MHZ_ANT0, 8, 8);
```

##### RX_INTF_REG_M_AXIS_RST_write()
**Location:** rx_intf.c (lines 91-103)

**Signature:** `void RX_INTF_REG_M_AXIS_RST_write(u32 value)`

**Parameters:**
- `value`: 0 to release reset, non-zero to hold in reset

**Purpose:** Control M_AXIS reset independently from other reset signals.

**Behavior:**
- Reads current MULTI_RST register
- Sets/clears bit 4 based on value
- Writes back modified register

#### Register Map

| Register | Address | Purpose |
|----------|---------|---------|
| MULTI_RST | 0x00 | Multi-module reset control (bit4: M_AXIS reset) |
| MIXER_CFG | 0x04 | Mixer configuration (deprecated in new design) |
| INTERRUPT_TEST | 0x08 | Interrupt test control |
| IQ_SRC_SEL | 0x0C | IQ source selection |
| IQ_CTRL | 0x10 | IQ control |
| START_TRANS_TO_PS_MODE | 0x14 | Transfer mode config (bit5: auto length detect) |
| START_TRANS_TO_PS | 0x18 | Start transfer to PS (max pkt len in bits 31:16) |
| START_TRANS_TO_PS_SRC_SEL | 0x1C | Transfer source selection |
| NUM_DMA_SYMBOL_TO_PL | 0x20 | DMA symbol count to PL |
| NUM_DMA_SYMBOL_TO_PS | 0x24 | DMA symbol count to PS |
| CFG_DATA_TO_ANT | 0x28 | Data to antenna config (bit8: bypass enable) |
| BB_GAIN | 0x2C | Baseband gain (set to 4) |
| TLAST_TIMEOUT_TOP | 0x30 | TLAST timeout (set to 7000) |
| S2MM_INTR_DELAY_COUNT | 0x34 | Interrupt delay (set to 300) |
| ANT_SEL | 0x40 | Antenna selection |

---

### XPU Driver API

**Location:** `/home/user/openwifi/driver/xpu/xpu.c`, API definition in `/home/user/openwifi/driver/hw_def.h` (lines 357-462)

**Exported Symbol:** `xpu_api` (line 275)

The XPU (MAC Processing Unit) implements low-level MAC functionality including CSMA/CA, ACK handling, TSF timer, and packet filtering.

#### Structure Definition

```c
struct xpu_driver_api {
    u32 (*hw_init)(enum xpu_mode mode);

    u32 (*reg_read)(u32 reg);
    void (*reg_write)(u32 reg, u32 value);

    void (*XPU_REG_MULTI_RST_write)(u32 value);
    u32  (*XPU_REG_MULTI_RST_read)(void);

    void (*XPU_REG_SRC_SEL_write)(u32 value);
    u32  (*XPU_REG_SRC_SEL_read)(void);

    void (*XPU_REG_RECV_ACK_COUNT_TOP0_write)(u32 value);
    u32  (*XPU_REG_RECV_ACK_COUNT_TOP0_read)(void);

    void (*XPU_REG_RECV_ACK_COUNT_TOP1_write)(u32 value);
    u32  (*XPU_REG_RECV_ACK_COUNT_TOP1_read)(void);

    void (*XPU_REG_SEND_ACK_WAIT_TOP_write)(u32 value);
    u32  (*XPU_REG_SEND_ACK_WAIT_TOP_read)(void);

    void (*XPU_REG_CTS_TO_RTS_CONFIG_write)(u32 value);
    u32  (*XPU_REG_CTS_TO_RTS_CONFIG_read)(void);

    void (*XPU_REG_FILTER_FLAG_write)(u32 value);
    u32  (*XPU_REG_FILTER_FLAG_read)(void);

    void (*XPU_REG_MAC_ADDR_LOW_write)(u32 value);
    u32  (*XPU_REG_MAC_ADDR_LOW_read)(void);

    void (*XPU_REG_MAC_ADDR_HIGH_write)(u32 value);
    u32  (*XPU_REG_MAC_ADDR_HIGH_read)(void);

    void (*XPU_REG_BSSID_FILTER_LOW_write)(u32 value);
    u32  (*XPU_REG_BSSID_FILTER_LOW_read)(void);

    void (*XPU_REG_BSSID_FILTER_HIGH_write)(u32 value);
    u32  (*XPU_REG_BSSID_FILTER_HIGH_read)(void);

    void (*XPU_REG_BAND_CHANNEL_write)(u32 value);
    u32  (*XPU_REG_BAND_CHANNEL_read)(void);

    void (*XPU_REG_DIFS_ADVANCE_write)(u32 value);
    u32  (*XPU_REG_DIFS_ADVANCE_read)(void);

    void (*XPU_REG_FORCE_IDLE_MISC_write)(u32 value);
    u32  (*XPU_REG_FORCE_IDLE_MISC_read)(void);

    u32  (*XPU_REG_TSF_RUNTIME_VAL_LOW_read)(void);
    u32  (*XPU_REG_TSF_RUNTIME_VAL_HIGH_read)(void);

    void (*XPU_REG_TSF_LOAD_VAL_LOW_write)(u32 value);
    void (*XPU_REG_TSF_LOAD_VAL_HIGH_write)(u32 value);
    void (*XPU_REG_TSF_LOAD_VAL_write)(u32 high_value, u32 low_value);

    void (*XPU_REG_LBT_TH_write)(u32 value);
    u32  (*XPU_REG_LBT_TH_read)(void);

    void (*XPU_REG_RSSI_DB_CFG_write)(u32 value);
    u32  (*XPU_REG_RSSI_DB_CFG_read)(void);

    void (*XPU_REG_CSMA_DEBUG_write)(u32 value);
    u32  (*XPU_REG_CSMA_DEBUG_read)(void);

    void (*XPU_REG_CSMA_CFG_write)(u32 value);
    u32  (*XPU_REG_CSMA_CFG_read)(void);

    void (*XPU_REG_SLICE_COUNT_TOTAL_write)(u32 value);
    void (*XPU_REG_SLICE_COUNT_START_write)(u32 value);
    void (*XPU_REG_SLICE_COUNT_END_write)(u32 value);

    u32 (*XPU_REG_SLICE_COUNT_TOTAL_read)(void);
    u32 (*XPU_REG_SLICE_COUNT_START_read)(void);
    u32 (*XPU_REG_SLICE_COUNT_END_read)(void);

    void (*XPU_REG_BB_RF_DELAY_write)(u32 value);

    void (*XPU_REG_ACK_CTL_MAX_NUM_RETRANS_write)(u32 value);
    u32  (*XPU_REG_ACK_CTL_MAX_NUM_RETRANS_read)(void);

    void (*XPU_REG_SPI_DISABLE_write)(u32 value);
    u32  (*XPU_REG_SPI_DISABLE_read)(void);

    void (*XPU_REG_AMPDU_ACTION_write)(u32 value);
    u32  (*XPU_REG_AMPDU_ACTION_read)(void);

    void (*XPU_REG_MAC_ADDR_write)(u8 *mac_addr);
};
```

#### Key Functions

##### hw_init()
**Location:** xpu.c (lines 277-403)

**Signature:** `u32 hw_init(enum xpu_mode mode)`

**Parameters:**
- `mode`: XPU mode (XPU_TEST or XPU_NORMAL)

**Returns:** 0 on success, error code on failure

**Purpose:** Initialize XPU (MAC processing unit) hardware.

**Behavior:**
- Performs multi-stage reset
- Configures CTS-to-RTS response rate (6M, 0xB)
- Sets BB-RF delay timing (calibrated for proper RF switching)
- Configures time slicing for 4 hardware queues (16us total)
- Sets RSSI AGC gain delay (39 samples) and offset (75*2)
- Sets LBT threshold (87*2 = -62dBm)
- Configures force idle duration (75) to handle AGC imperfections
- Sets SIFS timing (16+25+7-3+8-2 for both 2.4GHz and 5GHz)
- Configures ACK timeout (51+2+2)*10 + 15 with extra margin
- Sets DIFS advance (2us) and max packet length threshold

**Usage Example:**
```c
err = xpu_api->hw_init(XPU_NORMAL);
```

##### XPU_REG_TSF_LOAD_VAL_write()
**Location:** xpu.c (lines 169-173)

**Signature:** `void XPU_REG_TSF_LOAD_VAL_write(u32 high_value, u32 low_value)`

**Parameters:**
- `high_value`: High 32 bits of TSF
- `low_value`: Low 32 bits of TSF

**Purpose:** Set the 64-bit TSF timer value atomically.

**Behavior:**
- Writes low value first
- Writes high value with MSB set (triggers load)
- Writes high value with MSB clear (completes load)

**Usage Example:**
```c
xpu_api->XPU_REG_TSF_LOAD_VAL_write(0, 0); // Reset TSF to 0
```

##### XPU_REG_MAC_ADDR_write()
**Location:** xpu.c (lines 255-265)

**Signature:** `void XPU_REG_MAC_ADDR_write(u8 *mac_addr)`

**Parameters:**
- `mac_addr`: Pointer to 6-byte MAC address array

**Purpose:** Set the device MAC address for filtering.

**Behavior:**
- Writes MAC address low 32 bits
- Writes MAC address high 16 bits
- MAC address filter is always enabled

**Usage Example:**
```c
u8 mac[6] = {0x66, 0x55, 0x44, 0x33, 0x22, 0x11};
xpu_api->XPU_REG_MAC_ADDR_write(mac);
```

#### Register Map

| Register | Address | Purpose |
|----------|---------|---------|
| MULTI_RST | 0x00 | Multi-module reset (bit7: slice counter sync reset) |
| SRC_SEL | 0x04 | Source selection |
| TSF_LOAD_VAL_LOW | 0x08 | TSF load value low 32 bits |
| TSF_LOAD_VAL_HIGH | 0x0C | TSF load value high 32 bits (MSB triggers load) |
| BAND_CHANNEL | 0x10 | Band (bit16-23), slot time (bit24), frequency MHz |
| DIFS_ADVANCE | 0x14 | DIFS advance in us (bits 0-15), max pkt len (16-31) |
| FORCE_IDLE_MISC | 0x18 | Force idle duration (bits 0-25), eifs disable (bit26) |
| RSSI_DB_CFG | 0x1C | AGC gain delay (0-15), RSSI offset (16-31), load (bit31) |
| LBT_TH | 0x20 | Listen-before-talk threshold in rssi_half_db |
| CSMA_DEBUG | 0x24 | CSMA debug control |
| BB_RF_DELAY | 0x28 | BB-RF timing delays (4 bytes) |
| ACK_CTL_MAX_NUM_RETRANS | 0x2C | Max retransmission count |
| AMPDU_ACTION | 0x30 | A-MPDU action control |
| SPI_DISABLE | 0x34 | Disable FPGA SPI access to AD9361 |
| RECV_ACK_COUNT_TOP0 | 0x40 | ACK timeout for 2.4GHz (bit31: enable, 16-30: cycles, 0-15: adj) |
| RECV_ACK_COUNT_TOP1 | 0x44 | ACK timeout for 5GHz |
| SEND_ACK_WAIT_TOP | 0x48 | SIFS timing (high 16: 5GHz, low 16: 2.4GHz) |
| CSMA_CFG | 0x4C | CSMA/CA configuration (AIFS, CW, TXOP) |
| SLICE_COUNT_TOTAL | 0x50 | Time slice total duration (bits 0-19), queue idx (20-21) |
| SLICE_COUNT_START | 0x54 | Time slice start time |
| SLICE_COUNT_END | 0x58 | Time slice end time |
| CTS_TO_RTS_CONFIG | 0x68 | CTS-to-RTS response rate |
| FILTER_FLAG | 0x6C | Packet filter flags (see hw_def.h lines 308-322) |
| BSSID_FILTER_LOW | 0x70 | BSSID filter low 32 bits |
| BSSID_FILTER_HIGH | 0x74 | BSSID filter high 16 bits |
| MAC_ADDR_LOW | 0x78 | MAC address low 32 bits |
| MAC_ADDR_HIGH | 0x7C | MAC address high 16 bits |
| TSF_RUNTIME_VAL_LOW | 0xE8 | TSF runtime value low 32 bits |
| TSF_RUNTIME_VAL_HIGH | 0xEC | TSF runtime value high 32 bits |
| FPGA_GIT_REV | 0xFC | FPGA git revision |

#### Filter Flags

The XPU supports these filter flags (from hw_def.h):

```c
#define FIF_ALLMULTI          (1<<1)  // Multicast packets
#define FIF_BCN_PRBRESP_PROMISC (1<<4)  // Beacons/probe responses
#define FIF_CONTROL           (1<<5)  // Control frames
#define FIF_OTHER_BSS         (1<<6)  // Other BSS packets
#define FIF_PSPOLL            (1<<7)  // PS-Poll frames
#define FIF_PROBE_REQ         (1<<8)  // Probe requests
#define UNICAST_FOR_US        (1<<9)  // Unicast for our MAC
#define BROADCAST_ALL_ONE     (1<<10) // Broadcast FF:FF:FF:FF:FF:FF
#define BROADCAST_ALL_ZERO    (1<<11) // Broadcast 00:00:00:00:00:00
#define MY_BEACON             (1<<12) // Our beacon (matching BSSID)
#define MONITOR_ALL           (1<<13) // Monitor mode (all packets)
```

---

### OpenOFDM TX Driver API

**Location:** `/home/user/openwifi/driver/openofdm_tx/openofdm_tx.c`, API definition in `/home/user/openwifi/driver/hw_def.h` (lines 294-303)

**Exported Symbol:** `openofdm_tx_api` (line 60)

The OpenOFDM TX module implements the OFDM transmitter including scrambling, coding, interleaving, modulation, and IFFT.

#### Structure Definition

```c
struct openofdm_tx_driver_api {
    u32 (*hw_init)(enum openofdm_tx_mode mode);

    u32 (*reg_read)(u32 reg);
    void (*reg_write)(u32 reg, u32 value);

    void (*OPENOFDM_TX_REG_MULTI_RST_write)(u32 value);
    void (*OPENOFDM_TX_REG_INIT_PILOT_STATE_write)(u32 value);
    void (*OPENOFDM_TX_REG_INIT_DATA_STATE_write)(u32 value);
};
```

#### Key Functions

##### hw_init()
**Location:** openofdm_tx.c (lines 62-95)

**Signature:** `u32 hw_init(enum openofdm_tx_mode mode)`

**Parameters:**
- `mode`: OpenOFDM TX mode (OPENOFDM_TX_TEST or OPENOFDM_TX_NORMAL)

**Returns:** 0 on success, error code on failure

**Purpose:** Initialize OpenOFDM TX module.

**Behavior:**
- Performs multi-stage reset
- Initializes scrambler state for pilot (0x7F)
- Initializes scrambler state for data (0x7F)

**Usage Example:**
```c
err = openofdm_tx_api->hw_init(OPENOFDM_TX_NORMAL);
```

#### Register Map

| Register | Address | Purpose |
|----------|---------|---------|
| MULTI_RST | 0x00 | Multi-module reset control |
| INIT_PILOT_STATE | 0x04 | Initial scrambler state for pilots (0x7F) |
| INIT_DATA_STATE | 0x08 | Initial scrambler state for data (0x7F) |

---

### OpenOFDM RX Driver API

**Location:** `/home/user/openwifi/driver/openofdm_rx/openofdm_rx.c`, API definition in `/home/user/openwifi/driver/hw_def.h` (lines 265-280)

**Exported Symbol:** `openofdm_rx_api` (line 72)

The OpenOFDM RX module implements the OFDM receiver including synchronization, channel estimation, equalization, demodulation, and decoding.

#### Structure Definition

```c
struct openofdm_rx_driver_api {
    u32 (*hw_init)(enum openofdm_rx_mode mode);

    u32 (*reg_read)(u32 reg);
    void (*reg_write)(u32 reg, u32 value);

    u32 (*OPENOFDM_RX_REG_STATE_HISTORY_read)(void);

    void (*OPENOFDM_RX_REG_MULTI_RST_write)(u32 value);
    void (*OPENOFDM_RX_REG_ENABLE_write)(u32 value);
    void (*OPENOFDM_RX_REG_POWER_THRES_write)(u32 value);
    void (*OPENOFDM_RX_REG_MIN_PLATEAU_write)(u32 value);
    void (*OPENOFDM_RX_REG_SOFT_DECODING_write)(u32 value);
    void (*OPENOFDM_RX_REG_FFT_WIN_SHIFT_write)(u32 value);
    void (*OPENOFDM_RX_REG_PHASE_OFFSET_ABS_TH_write)(u32 value);
};
```

#### Key Functions

##### hw_init()
**Location:** openofdm_rx.c (lines 74-121)

**Signature:** `u32 hw_init(enum openofdm_rx_mode mode)`

**Parameters:**
- `mode`: OpenOFDM RX mode (OPENOFDM_RX_TEST or OPENOFDM_RX_NORMAL)

**Returns:** 0 on success, error code on failure

**Purpose:** Initialize OpenOFDM RX module.

**Behavior:**
- Enables HT smoothing (bit1) for better sensitivity
- Sets minimum plateau duration (OPENOFDM_RX_MIN_PLATEAU_INIT = 100)
- Enables soft decoding with min/max packet length thresholds
- Configures FFT window shift (OPENOFDM_RX_FFT_WIN_SHIFT_INIT = 4)
- Sets equalizer output counter threshold (48)
- Sets phase offset absolute threshold (11)
- Performs multi-stage reset
- Power threshold configured separately (not in hw_init to avoid inconsistency)

**Usage Example:**
```c
err = openofdm_rx_api->hw_init(OPENOFDM_RX_NORMAL);
```

##### OPENOFDM_RX_REG_POWER_THRES_write()
**Location:** openofdm_rx.c (line 49-51)

**Signature:** `void OPENOFDM_RX_REG_POWER_THRES_write(u32 value)`

**Parameters:**
- `value`: Power threshold configuration
  - Bits 0-15: Power threshold in rssi_half_db units
  - Bits 16-31: DC running sum threshold (default 64)

**Purpose:** Set receiver power detection threshold.

**Behavior:**
- Configures the minimum signal strength for packet detection
- Default power threshold: OPENOFDM_RX_POWER_THRES_INIT (124, equivalent to -95dBm after RSSI correction)
- Values dynamically set based on channel and RSSI correction in `openwifi_rf_rx_update_after_tuning()`

**Usage Example:**
```c
// Set threshold dynamically based on channel
int receiver_rssi_th = rssi_dbm_to_rssi_half_db(-85, priv->rssi_correction);
openofdm_rx_api->OPENOFDM_RX_REG_POWER_THRES_write((64<<16) | receiver_rssi_th);
```

#### Register Map

| Register | Address | Purpose |
|----------|---------|---------|
| MULTI_RST | 0x00 | Multi-module reset control |
| ENABLE | 0x04 | Enable control (bit1: force HT smoothing) |
| POWER_THRES | 0x08 | Power threshold (0-15), DC sum threshold (16-31) |
| MIN_PLATEAU | 0x0C | Minimum plateau duration (100) |
| SOFT_DECODING | 0x10 | Soft decoding (bit0), min pkt len (12-15), max pkt len (16-31) |
| FFT_WIN_SHIFT | 0x14 | FFT window shift (0-3), EQ counter threshold (4-11) |
| PHASE_OFFSET_ABS_TH | 0x48 | Phase offset absolute threshold (11) |
| STATE_HISTORY | 0x50 | Receiver state machine history (read-only) |

#### Important Constants

From hw_def.h lines 228-263:

```c
#define OPENOFDM_RX_POWER_THRES_INIT          124  // Initial power threshold
#define OPENOFDM_RX_RSSI_DBM_TH_DEFAULT       -95  // Default RSSI threshold in dBm
#define OPENOFDM_RX_DC_RUNNING_SUM_TH_INIT    64   // DC running sum threshold
#define OPENOFDM_RX_MIN_PLATEAU_INIT          100  // Minimum plateau duration
#define OPENOFDM_RX_FFT_WIN_SHIFT_INIT        4    // FFT window shift
#define OPENOFDM_RX_SMALL_EQ_OUT_COUNTER_TH   48   // Equalizer output counter threshold
#define OPENOFDM_RX_PHASE_OFFSET_ABS_TH       11   // Phase offset absolute threshold
#define OPENWIFI_MAX_SIGNAL_LEN_TH            1700 // Max packet length threshold
#define OPENWIFI_MIN_SIGNAL_LEN_TH            14   // Min packet length threshold
```

---

### Side Channel Driver API

**Location:** `/home/user/openwifi/driver/side_ch/side_ch.c`

**Note:** The side channel driver does NOT export a structured API like other components. Instead, it provides CSI (Channel State Information) and IQ capture functionality via netlink sockets.

#### Architecture

The side channel driver:
1. Captures CSI/IQ data from FPGA
2. Transfers data via DMA to kernel space
3. Sends data to user space via netlink socket
4. Used by `side_ch_ctl` user-space utility

#### Netlink Interface

**Location:** side_ch.c (lines 434-519)

##### Action Commands

```c
#define ACTION_INVALID       0
#define ACTION_REG_WRITE     1
#define ACTION_REG_READ      2
#define ACTION_SIDE_INFO_GET 3
```

##### Message Format

Commands from user space include:
- `action_flag`: Action to perform
- `reg_type`: Register type (hardware or software)
- `reg_idx`: Register index
- `reg_val`: Register value (for write operations)

##### side_ch_nl_recv_msg()
**Location:** side_ch.c (lines 446-519)

**Purpose:** Handle netlink messages from user space.

**Behavior:**
- ACTION_SIDE_INFO_GET: Retrieves CSI/IQ data via DMA and sends to user space
- ACTION_REG_READ: Reads hardware register
- ACTION_REG_WRITE: Writes hardware register
- Returns results via netlink reply

#### DMA Functions

##### get_side_info()
**Location:** side_ch.c (lines 347-431)

**Purpose:** Retrieve CSI or IQ capture data via DMA.

**Parameters:**
- `num_eq`: Number of equalizer outputs to capture (0-8)
- `iq_len`: IQ capture length (0 for CSI mode, >0 for IQ mode)

**Returns:** Size of captured data on success, negative error code on failure

**Behavior:**
- Checks DMA completion status
- Calculates number of DMA symbols based on mode:
  - CSI mode: HEADER_LEN + CSI_LEN + num_eq * EQUALIZER_LEN
  - IQ mode: 1 + iq_len
- Sets up DMA transfer from FPGA to kernel buffer
- Waits for transfer completion (100ms timeout)
- Returns buffer size for netlink transmission

#### Module Parameters

**Location:** side_ch.c (lines 32-39)

```c
module_param(num_eq_init, int, 0);
MODULE_PARM_DESC(num_eq_init, "num_eq_init. 0~8. number of equalizer output (52 each) appended to CSI");

module_param(iq_len_init, int, 0);
MODULE_PARM_DESC(iq_len_init, "iq_len_init. if iq_len_init>0, iq capture enabled, csi disabled");
```

**Usage:**
```bash
insmod side_ch.ko num_eq_init=8 iq_len_init=0    # CSI mode with 8 EQ outputs
insmod side_ch.ko num_eq_init=0 iq_len_init=1024  # IQ capture mode, 1024 samples
```

#### Register Map

**Location:** side_ch.h (lines 15-29)

| Register | Address | Purpose |
|----------|---------|---------|
| MULTI_RST | 0x00 | Multi-module reset control |
| CONFIG | 0x04 | Configuration (bit0: enable, bit12: FC match, bit13/14: addr match) |
| NUM_DMA_SYMBOL | 0x08 | DMA symbol count (low 16: to PS, high 16: to PL) |
| IQ_CAPTURE | 0x0C | IQ capture enable |
| NUM_EQ | 0x10 | Number of equalizer outputs (0-8) |
| FC_TARGET | 0x14 | Frame control target for filtering |
| ADDR1_TARGET | 0x18 | Address 1 target for filtering (low 32 bits) |
| ADDR2_TARGET | 0x1C | Address 2 target for filtering (low 32 bits) |
| IQ_TRIGGER | 0x20 | IQ trigger condition (0: fcs ok/nok, 10: RSSI based) |
| RSSI_TH | 0x24 | RSSI threshold for IQ trigger |
| GAIN_TH | 0x28 | AGC gain threshold |
| PRE_TRIGGER_LEN | 0x2C | Pre-trigger buffer length (default 8190) |
| IQ_LEN | 0x30 | IQ capture length (max 8187 for UDP compatibility) |
| M_AXIS_DATA_COUNT | 0x50 | M_AXIS FIFO data count (read-only) |

#### Constants

**Location:** side_ch.h (lines 9-14)

```c
#define CSI_LEN 56              // Length of single CSI (56 symbols = 56*8 = 448 bytes)
#define EQUALIZER_LEN (56-4)    // Length of equalizer output (52 symbols)
#define HEADER_LEN 2            // Timestamp and frequency offset
#define MAX_NUM_DMA_SYMBOL 8192 // Maximum DMA buffer size
```

---

## Data Structures

### Core Structures

#### openwifi_priv
**Location:** sdr.h (lines 446-530)

Main private driver data structure containing all driver state.

```c
struct openwifi_priv {
    struct platform_device       *pdev;
    struct ieee80211_vif         *vif[MAX_NUM_VIF];  // Up to 4 virtual interfaces

    const struct openwifi_rf_ops *rf;                // RF operations (AD9361 or RFSoC)
    enum openwifi_hardware_type  hardware_type;      // ZYNQ_AD9361, ZYNQMP_AD9361, RFSOC4X2
    enum openwifi_fpga_type      fpga_type;         // SMALL_FPGA or LARGE_FPGA

    struct cf_axi_dds_state      *dds_st;           // DAC channel
    struct axiadc_state          *adc_st;           // ADC channel
    struct ad9361_rf_phy         *ad9361_phy;       // AD9361 chip driver
    struct ctrl_outs_control     ctrl_out;          // Control outputs

    int rx_freq_offset_to_lo_MHz;                   // RX LO offset
    int tx_freq_offset_to_lo_MHz;                   // TX LO offset
    u32 rf_bw;                                      // RF bandwidth
    u32 actual_rx_lo;                               // Actual RX LO frequency
    u32 actual_tx_lo;                               // Actual TX LO frequency
    u32 last_tx_quad_cal_lo;                        // Last TX quadrature cal frequency

    struct ieee80211_rate           rates_2GHz[12];
    struct ieee80211_rate           rates_5GHz[12];
    struct ieee80211_channel        channels_2GHz[13];
    struct ieee80211_channel        channels_5GHz[11];
    struct ieee80211_supported_band band_2GHz;
    struct ieee80211_supported_band band_5GHz;

    bool rfkill_off;                                // RFkill state
    u8   runtime_tx_ant_cfg;                        // TX antenna config
    u8   runtime_rx_ant_cfg;                        // RX antenna config
    int  rssi_correction;                           // Dynamic RSSI correction

    enum rx_intf_mode     rx_intf_cfg;              // RX interface mode
    enum tx_intf_mode     tx_intf_cfg;              // TX interface mode
    enum openofdm_rx_mode openofdm_rx_cfg;          // OpenOFDM RX mode
    enum openofdm_tx_mode openofdm_tx_cfg;          // OpenOFDM TX mode
    enum xpu_mode         xpu_cfg;                  // XPU mode

    int irq_rx;                                     // RX interrupt number
    int irq_tx;                                     // TX interrupt number

    // RX DMA
    u8                             *rx_cyclic_buf;
    dma_addr_t                     rx_cyclic_buf_dma_mapping_addr;
    struct dma_chan                *rx_chan;
    struct dma_async_tx_descriptor *rxd;
    dma_cookie_t                   rx_cookie;

    // TX DMA
    struct openwifi_ring           tx_ring[MAX_NUM_SW_QUEUE];  // 4 TX rings
    struct scatterlist             tx_sg;
    struct dma_chan                *tx_chan;
    struct dma_async_tx_descriptor *txd;
    dma_cookie_t                   tx_cookie;

    u32 slice_idx;                                  // Time slice index
    u32 dest_mac_addr_queue_map[MAX_NUM_HW_QUEUE]; // MAC to queue mapping
    u8  mac_addr[ETH_ALEN];                         // Device MAC address
    u16 seqno;                                      // Sequence number

    bool use_short_slot;                            // Short slot time
    u8   band;                                      // Current band
    u32  ampdu_reference;                           // AMPDU reference

    u32 drv_rx_reg_val[MAX_NUM_DRV_REG];           // Driver RX registers
    u32 drv_tx_reg_val[MAX_NUM_DRV_REG];           // Driver TX registers
    u32 drv_xpu_reg_val[MAX_NUM_DRV_REG];          // Driver XPU registers
    int rf_reg_val[MAX_NUM_RF_REG];                // RF registers
    int last_auto_fpga_lbt_th;                     // Last auto LBT threshold

    struct bin_attribute bin_iq;                    // Binary IQ attribute
    u32                  tx_intf_arbitrary_iq[512]; // Arbitrary IQ buffer
    u16                  tx_intf_arbitrary_iq_num;  // Number of IQ samples
    u8                   tx_intf_iq_ctl;           // IQ control

    struct openwifi_stat stat;                      // Statistics
    spinlock_t lock;                                // Driver lock
};
```

#### openwifi_ring
**Location:** sdr.h (lines 46-53)

TX ring buffer descriptor.

```c
struct openwifi_ring {
    struct openwifi_buffer_descriptor *bds;  // Buffer descriptors
    u32 bd_wr_idx;                           // Write index
    u32 bd_rd_idx;                           // Read index
    int stop_flag;                           // Stop flag (-1: run, >=0: stop due to queue full)
};
```

#### openwifi_buffer_descriptor
**Location:** sdr.h (lines 32-44)

TX buffer descriptor for each packet.

```c
struct openwifi_buffer_descriptor {
    u8 prio;                    // Priority (0-3)
    u16 len_mpdu;               // MPDU length
    u16 seq_no;                 // Sequence number
    struct sk_buff *skb_linked; // Linked socket buffer
    dma_addr_t dma_mapping_addr;// DMA mapping address
} __packed;
```

#### openwifi_vif
**Location:** sdr.h (lines 55-63)

Virtual interface structure.

```c
struct openwifi_vif {
    struct ieee80211_hw *dev;           // Hardware device
    int idx;                            // VIF index
    struct delayed_work beacon_work;    // Beacon work (for AP mode)
    bool enable_beacon;                 // Beacon enable flag
};
```

#### openwifi_stat
**Location:** sdr.h (lines 379-443)

Driver statistics structure.

```c
struct openwifi_stat {
    u32 stat_enable;                                // Statistics enable flag

    // TX priority queue statistics
    u32 tx_prio_num[MAX_NUM_SW_QUEUE];
    u32 tx_prio_interrupt_num[MAX_NUM_SW_QUEUE];
    u32 tx_prio_stop0_fake_num[MAX_NUM_SW_QUEUE];
    u32 tx_prio_stop0_real_num[MAX_NUM_SW_QUEUE];
    u32 tx_prio_stop1_num[MAX_NUM_SW_QUEUE];
    u32 tx_prio_wakeup_num[MAX_NUM_SW_QUEUE];

    // TX hardware queue statistics
    u32 tx_queue_num[MAX_NUM_HW_QUEUE];
    u32 tx_queue_interrupt_num[MAX_NUM_HW_QUEUE];
    u32 tx_queue_stop0_fake_num[MAX_NUM_HW_QUEUE];
    u32 tx_queue_stop0_real_num[MAX_NUM_HW_QUEUE];
    u32 tx_queue_stop1_num[MAX_NUM_HW_QUEUE];
    u32 tx_queue_wakeup_num[MAX_NUM_HW_QUEUE];

    // TX data packet statistics
    u32 tx_data_pkt_need_ack_num_total;
    u32 tx_data_pkt_need_ack_num_total_fail;
    u32 tx_data_pkt_need_ack_num_retx[6];
    u32 tx_data_pkt_need_ack_num_retx_fail[6];
    u32 tx_data_pkt_mcs_realtime;
    u32 tx_data_pkt_fail_mcs_realtime;

    // TX management packet statistics
    u32 tx_mgmt_pkt_need_ack_num_total;
    u32 tx_mgmt_pkt_need_ack_num_total_fail;
    u32 tx_mgmt_pkt_need_ack_num_retx[3];
    u32 tx_mgmt_pkt_need_ack_num_retx_fail[3];
    u32 tx_mgmt_pkt_mcs_realtime;
    u32 tx_mgmt_pkt_fail_mcs_realtime;

    // RX statistics
    u32 rx_target_sender_mac_addr;
    u32 rx_data_ok_agc_gain_value_realtime;
    u32 rx_data_fail_agc_gain_value_realtime;
    u32 rx_mgmt_ok_agc_gain_value_realtime;
    u32 rx_mgmt_fail_agc_gain_value_realtime;
    u32 rx_ack_ok_agc_gain_value_realtime;

    u32 rx_monitor_all;
    u32 rx_data_pkt_num_total;
    u32 rx_data_pkt_num_fail;
    u32 rx_mgmt_pkt_num_total;
    u32 rx_mgmt_pkt_num_fail;
    u32 rx_ack_pkt_num_total;
    u32 rx_ack_pkt_num_fail;

    u32 rx_data_pkt_mcs_realtime;
    u32 rx_data_pkt_fail_mcs_realtime;
    u32 rx_mgmt_pkt_mcs_realtime;
    u32 rx_mgmt_pkt_fail_mcs_realtime;
    u32 rx_ack_pkt_mcs_realtime;

    u32 restrict_freq_mhz;
    u32 csma_cfg0;
    u32 cw_max_min_cfg;

    u32 dbg_ch0;
    u32 dbg_ch1;
    u32 dbg_ch2;
};
```

### Enumerations

#### openwifi_hardware_type
**Location:** hw_def.h (lines 9-14)

```c
enum openwifi_hardware_type {
    ZYNQ_AD9361 = 0,      // Zynq 7000 with AD9361
    ZYNQMP_AD9361 = 1,    // Zynq UltraScale+ with AD9361
    RFSOC4X2 = 2,         // RFSoC 4x2
    UNKNOWN_HARDWARE,
};
```

#### openwifi_fpga_type
**Location:** hw_def.h (lines 16-19)

```c
enum openwifi_fpga_type {
    SMALL_FPGA = 0,  // 4096 DMA symbols (e.g., xc7z020)
    LARGE_FPGA = 1,  // 8192 DMA symbols (e.g., xc7z045)
};
```

#### tx_intf_mode
**Location:** hw_def.h (lines 66-76)

```c
enum tx_intf_mode {
    TX_INTF_AXIS_LOOP_BACK = 0,
    TX_INTF_BYPASS,
    TX_INTF_BW_20MHZ_AT_0MHZ_ANT0,
    TX_INTF_BW_20MHZ_AT_0MHZ_ANT1,
    TX_INTF_BW_20MHZ_AT_0MHZ_ANT_BOTH,
    TX_INTF_BW_20MHZ_AT_N_10MHZ_ANT0,  // -10MHz offset
    TX_INTF_BW_20MHZ_AT_P_10MHZ_ANT0,  // +10MHz offset
    TX_INTF_BW_20MHZ_AT_N_10MHZ_ANT1,
    TX_INTF_BW_20MHZ_AT_P_10MHZ_ANT1,
};
```

#### rx_intf_mode
**Location:** hw_def.h (lines 158-167)

```c
enum rx_intf_mode {
    RX_INTF_AXIS_LOOP_BACK = 0,
    RX_INTF_BYPASS,
    RX_INTF_BW_20MHZ_AT_0MHZ_ANT0,
    RX_INTF_BW_20MHZ_AT_0MHZ_ANT1,
    RX_INTF_BW_20MHZ_AT_N_10MHZ_ANT0,
    RX_INTF_BW_20MHZ_AT_N_10MHZ_ANT1,
    RX_INTF_BW_20MHZ_AT_P_10MHZ_ANT0,
    RX_INTF_BW_20MHZ_AT_P_10MHZ_ANT1,
};
```

---

## DMA Interfaces

OpenWiFi uses Xilinx DMA for data transfer between Processing System (PS) and Programmable Logic (PL).

### RX DMA (Cyclic Mode)

**Location:** sdr.c (lines 427-449)

#### rx_dma_setup()

**Signature:** `static int rx_dma_setup(struct ieee80211_hw *dev)`

**Purpose:** Set up cyclic DMA for RX path (FPGA to PS).

**Parameters:**
- `dev`: IEEE 802.11 hardware device

**Returns:** 0 on success, -1 on error

**Behavior:**
- Allocates cyclic RX buffer (NUM_RX_BD * RX_BD_BUF_SIZE)
- Prepares cyclic DMA descriptor
- Submits DMA transaction
- Starts DMA engine
- Used for continuous reception of packets

**Configuration:**
- Buffer size: RX_BD_BUF_SIZE (2048 bytes)
- Number of buffers: NUM_RX_BD (16 or 64 depending on USE_NEW_RX_INTERRUPT)
- DMA direction: DMA_DEV_TO_MEM
- Mode: Cyclic (continuous)

**Usage:**
```c
err = rx_dma_setup(dev);
```

### TX DMA (Scatter-Gather Mode)

TX DMA is set up per-packet in the `openwifi_tx()` function. It uses scatter-gather mode for efficient packet transmission.

#### TX DMA Setup (in openwifi_tx)

**Process:**
1. Get packet from mac80211
2. Map packet to DMA address
3. Store in TX ring buffer descriptor
4. Configure DMA scatter-gather descriptor
5. Submit DMA transaction
6. Fire TX start trigger

**Configuration:**
- Buffer size: TX_BD_BUF_SIZE (8192 bytes)
- Number of descriptors: NUM_TX_BD (64)
- DMA direction: DMA_MEM_TO_DEV
- Mode: Scatter-gather (one transaction per packet)

### DMA Ring Buffer Management

#### openwifi_init_tx_ring()
**Location:** sdr.c (lines 338-362)

**Purpose:** Initialize TX ring buffer for a specific queue.

**Behavior:**
- Allocates buffer descriptors
- Initializes indices (wr_idx, rd_idx)
- Sets stop_flag to -1 (running)

#### openwifi_free_tx_ring()
**Location:** sdr.c (lines 364-393)

**Purpose:** Free TX ring buffer and unmap DMA.

**Behavior:**
- Unmaps all pending DMA transactions
- Frees buffer descriptors
- Checks for inconsistencies (warnings printed)

#### openwifi_init_rx_ring()
**Location:** sdr.c (lines 395-416)

**Purpose:** Initialize RX cyclic buffer.

**Behavior:**
- Allocates coherent DMA memory
- Clears packet existence flags
- Used with cyclic DMA mode

#### openwifi_free_rx_ring()
**Location:** sdr.c (lines 418-425)

**Purpose:** Free RX cyclic buffer.

---

## Interrupt Handlers

### openwifi_rx_interrupt()

**Location:** sdr.c (lines 464-659)

**Signature:** `static irqreturn_t openwifi_rx_interrupt(int irq, void *dev_id)`

**Purpose:** Handle RX packet reception interrupts.

**Parameters:**
- `irq`: Interrupt number
- `dev_id`: Device ID (struct ieee80211_hw *)

**Returns:** IRQ_HANDLED

**Behavior:**

1. **Packet Detection:**
   - Scans RX cyclic buffer for new packets
   - Checks packet existence flag (agc_status_and_pkt_exist_flag)
   - Supports both old (single buffer check) and new (all buffer scan) interrupt modes

2. **Packet Parsing:**
   - Extracts timestamp (TSF low/high)
   - Reads RSSI (rssi_half_db)
   - Parses packet length, rate index
   - Determines HT/aggregation flags
   - Checks FCS validity

3. **Packet Processing:**
   - Allocates sk_buff
   - Copies packet data
   - Populates rx_status structure:
     - Signal strength (RSSI converted to dBm)
     - MCS/rate information
     - Timestamp
     - Channel/band
     - HT/aggregation flags
   - Submits to mac80211

4. **Statistics Update:**
   - Increments counters based on packet type (data/mgmt/ACK)
   - Tracks success/failure rates
   - Records real-time MCS values
   - Updates AGC gain values

5. **Buffer Management:**
   - Clears packet existence flag
   - Manages multiple packets in interrupt (up to 8)

**Statistics Collected:**
- rx_monitor_all, rx_data_pkt_num_total, rx_data_pkt_num_fail
- rx_mgmt_pkt_num_total, rx_mgmt_pkt_num_fail
- rx_ack_pkt_num_total, rx_ack_pkt_num_fail
- rx_data_pkt_mcs_realtime, rx_data_pkt_fail_mcs_realtime
- rx_mgmt_pkt_mcs_realtime, rx_mgmt_pkt_fail_mcs_realtime
- rx_ack_pkt_mcs_realtime
- AGC gain values for data/mgmt/ACK packets

### openwifi_tx_interrupt()

**Location:** sdr.c (lines 661-800+)

**Signature:** `static irqreturn_t openwifi_tx_interrupt(int irq, void *dev_id)`

**Purpose:** Handle TX completion interrupts.

**Parameters:**
- `irq`: Interrupt number
- `dev_id`: Device ID (struct ieee80211_hw *)

**Returns:** IRQ_HANDLED

**Behavior:**

1. **TX Completion Processing:**
   - Reads packet information from TX interface registers
   - Determines success/failure from PKT_INFO registers
   - Identifies packet type (data/management/ACK)

2. **Buffer Cleanup:**
   - Unmaps DMA memory
   - Frees sk_buff
   - Updates TX ring buffer read index
   - Cleans up completed descriptors

3. **Status Reporting:**
   - Populates ieee80211_tx_info
   - Reports ACK received/not received
   - Reports retry count
   - Calls ieee80211_tx_status() to report to mac80211

4. **Queue Management:**
   - Checks queue fill level
   - Wakes stopped queues if space available
   - Updates queue stop/wake statistics

5. **Statistics Update:**
   - Increments TX counters
   - Tracks success/failure by retry count
   - Records real-time MCS values
   - Updates retransmission statistics

**Statistics Collected:**
- tx_prio_interrupt_num, tx_queue_interrupt_num
- tx_data_pkt_need_ack_num_total, tx_data_pkt_need_ack_num_total_fail
- tx_data_pkt_need_ack_num_retx[6], tx_data_pkt_need_ack_num_retx_fail[6]
- tx_mgmt_pkt_need_ack_num_total, tx_mgmt_pkt_need_ack_num_total_fail
- tx_mgmt_pkt_need_ack_num_retx[3], tx_mgmt_pkt_need_ack_num_retx_fail[3]
- tx_data_pkt_mcs_realtime, tx_data_pkt_fail_mcs_realtime
- tx_mgmt_pkt_mcs_realtime, tx_mgmt_pkt_fail_mcs_realtime
- Queue wake/stop statistics

**Interrupt Configuration:**

Interrupts are registered in `openwifi_dev_probe()`:
```c
request_irq(priv->irq_rx, openwifi_rx_interrupt, IRQF_SHARED, "sdr,rx_intf", dev);
request_irq(priv->irq_tx, openwifi_tx_interrupt, IRQF_SHARED, "sdr,tx_intf", dev);
```

---

## Sysfs Attributes

Sysfs attributes provide user-space access to driver statistics and configuration.

**Location:** `/home/user/openwifi/driver/sysfs_intf.c`

**Base Path:** `/sys/devices/platform/fpga-axi@0/[device]/`

### Statistics Attributes

All statistics attributes support read and write (to reset).

#### TX Statistics

| Attribute | Description |
|-----------|-------------|
| `stat_enable` | Enable/disable statistics collection |
| `tx_prio_queue` | TX priority queue statistics (4 queues) |
| `tx_data_pkt_need_ack_num_total` | Total data packets requiring ACK |
| `tx_data_pkt_need_ack_num_total_fail` | Failed data packets requiring ACK |
| `tx_data_pkt_need_ack_num_retx` | Data packets by retry count (0-5) |
| `tx_data_pkt_need_ack_num_retx_fail` | Failed data packets by retry count |
| `tx_data_pkt_mcs_realtime` | Real-time TX data packet MCS |
| `tx_data_pkt_fail_mcs_realtime` | Real-time failed TX data packet MCS |
| `tx_mgmt_pkt_need_ack_num_total` | Total management packets requiring ACK |
| `tx_mgmt_pkt_need_ack_num_total_fail` | Failed management packets requiring ACK |
| `tx_mgmt_pkt_need_ack_num_retx` | Management packets by retry count (0-2) |
| `tx_mgmt_pkt_need_ack_num_retx_fail` | Failed management packets by retry count |
| `tx_mgmt_pkt_mcs_realtime` | Real-time TX management packet MCS |
| `tx_mgmt_pkt_fail_mcs_realtime` | Real-time failed TX management packet MCS |

#### RX Statistics

| Attribute | Description |
|-----------|-------------|
| `rx_target_sender_mac_addr` | Target sender MAC address for filtering |
| `rx_monitor_all` | Total monitored packets |
| `rx_data_pkt_num_total` | Total received data packets |
| `rx_data_pkt_num_fail` | Failed data packets (FCS error) |
| `rx_mgmt_pkt_num_total` | Total received management packets |
| `rx_mgmt_pkt_num_fail` | Failed management packets |
| `rx_ack_pkt_num_total` | Total received ACK packets |
| `rx_ack_pkt_num_fail` | Failed ACK packets |
| `rx_data_pkt_mcs_realtime` | Real-time RX data packet MCS |
| `rx_data_pkt_fail_mcs_realtime` | Real-time failed RX data packet MCS |
| `rx_mgmt_pkt_mcs_realtime` | Real-time RX management packet MCS |
| `rx_mgmt_pkt_fail_mcs_realtime` | Real-time failed RX management packet MCS |
| `rx_ack_pkt_mcs_realtime` | Real-time RX ACK packet MCS |
| `rx_data_ok_agc_gain_value_realtime` | AGC gain for successful data packets |
| `rx_data_fail_agc_gain_value_realtime` | AGC gain for failed data packets |
| `rx_mgmt_ok_agc_gain_value_realtime` | AGC gain for successful management packets |
| `rx_mgmt_fail_agc_gain_value_realtime` | AGC gain for failed management packets |
| `rx_ack_ok_agc_gain_value_realtime` | AGC gain for successful ACK packets |

### Binary Attributes

#### tx_intf_bin_iq

**Location:** sysfs_intf.c (lines 69-137)

**Purpose:** Upload/download arbitrary IQ samples for TX.

**Read Operation:**
- Returns number of IQ samples
- Returns I samples (space-separated)
- Returns Q samples (space-separated)

**Write Operation (Binary Mode):**
- Accepts binary IQ data (4 bytes per IQ sample)
- Format: I (16-bit) | Q (16-bit) in each 32-bit word
- Maximum 512 IQ samples

**Usage:**
```bash
# Write IQ samples
cat iq_samples.bin > /sys/devices/.../tx_intf_bin_iq

# Read IQ samples
cat /sys/devices/.../tx_intf_bin_iq
```

### Configuration Attributes

#### tx_intf_iq_ctl

**Location:** sysfs_intf.c (lines 139-170)

**Purpose:** Control arbitrary IQ transmission.

**Write Operation:**
- Switches TX to IQ mode
- Sends configured IQ samples
- Returns to normal mode

**Usage:**
```bash
# Trigger IQ transmission
echo 1 > /sys/devices/.../tx_intf_iq_ctl
```

### Attribute Groups

**Location:** sysfs_intf.c (lines 171-177, 1188-1233)

Attributes are organized into groups:

```c
static struct attribute *tx_intf_attributes[] = {
    &dev_attr_tx_intf_iq_ctl.attr,
    NULL,
};

static struct attribute *openwifi_sysfs_entries[] = {
    &dev_attr_stat_enable.attr,
    &dev_attr_tx_prio_queue.attr,
    // ... (all statistics attributes)
    NULL,
};
```

Registered in driver probe:
```c
sysfs_create_group(&pdev->dev.kobj, &tx_intf_attribute_group);
sysfs_create_group(&pdev->dev.kobj, &openwifi_attribute_group);
sysfs_create_bin_file(&pdev->dev.kobj, &priv->bin_iq);
```

---

## Testmode Commands

Testmode commands provide advanced hardware control via the `sdrctl` user-space utility.

**Location:** `/home/user/openwifi/driver/sdrctl_intf.c`

**Interface:** nl80211 testmode

### Command Structure

Commands use nl80211 testmode with these attributes:

```c
enum {
    OPENWIFI_ATTR_CMD,           // Command type
    OPENWIFI_ATTR_GAP,          // CSMA gap value
    OPENWIFI_ATTR_SLICE_IDX,    // Time slice index
    OPENWIFI_ATTR_ADDR,         // MAC address
    OPENWIFI_ATTR_SLICE_TOTAL,  // Slice total duration
    OPENWIFI_ATTR_SLICE_START,  // Slice start time
    OPENWIFI_ATTR_SLICE_END,    // Slice end time
    // ... (many more)
};
```

### Available Commands

#### CSMA/CA Configuration

**OPENWIFI_CMD_SET_GAP / OPENWIFI_CMD_GET_GAP**

**Location:** sdrctl_intf.c (lines 26-40)

**Purpose:** Configure CSMA/CA parameters (AIFS, contention window, TXOP).

**Parameters:**
- GAP value: 32-bit configuration
  - Bits vary by queue configuration

**Usage:**
```c
// Set CSMA gap
iw dev wlan0 testmode set_gap 0x12345678

// Get CSMA gap
iw dev wlan0 testmode get_gap
```

#### Time Slicing

**OPENWIFI_CMD_SET_SLICE_IDX / OPENWIFI_CMD_GET_SLICE_IDX**

**Location:** sdrctl_intf.c (lines 41-62)

**Purpose:** Select which hardware queue (time slice) to configure.

**Parameters:**
- slice_idx: 0-3 for queue selection, MAX_NUM_HW_QUEUE to reset all

**OPENWIFI_CMD_SET_SLICE_TOTAL / OPENWIFI_CMD_GET_SLICE_TOTAL**

**Location:** sdrctl_intf.c (lines 89-109)

**Purpose:** Set total duration of time slice.

**Parameters:**
- slice_total: Duration in microseconds

**OPENWIFI_CMD_SET_SLICE_START / OPENWIFI_CMD_GET_SLICE_START**

**Location:** sdrctl_intf.c (lines 111-131)

**Purpose:** Set start time of time slice.

**Parameters:**
- slice_start: Start time in microseconds

**OPENWIFI_CMD_SET_SLICE_END / OPENWIFI_CMD_GET_SLICE_END**

**Location:** sdrctl_intf.c (lines 133-153)

**Purpose:** Set end time of time slice.

**Parameters:**
- slice_end: End time in microseconds

**Usage:**
```bash
# Select queue 0
sdrctl dev wlan0 set slice_idx 0

# Configure time slice (16us total, 0-16us active)
sdrctl dev wlan0 set slice_total 16
sdrctl dev wlan0 set slice_start 0
sdrctl dev wlan0 set slice_end 16
```

#### MAC Address Mapping

**OPENWIFI_CMD_SET_ADDR / OPENWIFI_CMD_GET_ADDR**

**Location:** sdrctl_intf.c (lines 63-87)

**Purpose:** Map destination MAC address to hardware queue.

**Parameters:**
- addr: Low 32 bits of destination MAC address

**Behavior:**
- Associates MAC address with current slice_idx
- Used for per-destination queue scheduling

**Usage:**
```bash
# Map MAC to queue 0
sdrctl dev wlan0 set slice_idx 0
sdrctl dev wlan0 set addr 0x44332211
```

#### Register Access

The testmode interface supports many register read/write commands for:
- RF registers (frequency, gain, attenuation)
- TX/RX interface registers
- XPU registers
- OpenOFDM TX/RX registers
- Driver registers (configuration, thresholds)

Commands follow pattern:
- `set_<register>`: Write register
- `get_<register>`: Read register

**Categories (from hw_def.h lines 81-92):**
```c
enum sdrctl_reg_cat {
    SDRCTL_REG_CAT_RF,        // RF frontend registers
    SDRCTL_REG_CAT_RX_INTF,   // RX interface registers
    SDRCTL_REG_CAT_TX_INTF,   // TX interface registers
    SDRCTL_REG_CAT_RX,        // OpenOFDM RX registers
    SDRCTL_REG_CAT_TX,        // OpenOFDM TX registers
    SDRCTL_REG_CAT_XPU,       // XPU registers
    SDRCTL_REG_CAT_DRV_RX,    // Driver RX registers
    SDRCTL_REG_CAT_DRV_TX,    // Driver TX registers
    SDRCTL_REG_CAT_DRV_XPU,   // Driver XPU registers
};
```

### Using sdrctl Utility

The `sdrctl` user-space utility provides convenient access to testmode commands:

```bash
# RF configuration
sdrctl dev wlan0 set rf_freq_mhz 2412
sdrctl dev wlan0 set rf_tx_gain 30
sdrctl dev wlan0 set rf_rx_gain 70

# Driver registers
sdrctl dev wlan0 get drv_rx_demod_th
sdrctl dev wlan0 set drv_xpu_lbt_th 62

# Hardware registers
sdrctl dev wlan0 get reg XPU 0x50  # Read XPU register at offset 0x50
sdrctl dev wlan0 set reg XPU 0x4C 0x12345678  # Write XPU register
```

---

## Constants and Definitions

### Buffer Sizes

```c
#define NUM_TX_BD 64              // Number of TX buffer descriptors (2^6)
#define NUM_RX_BD 16              // Number of RX buffer descriptors (normal)
#define NUM_RX_BD 64              // Number of RX buffer descriptors (new interrupt mode)

#define TX_BD_BUF_SIZE 8192       // TX buffer size
#define RX_BD_BUF_SIZE 2048       // RX buffer size
```

### Queue Configuration

```c
#define MAX_NUM_HW_QUEUE 4        // Number of hardware queues
#define MAX_NUM_SW_QUEUE 4        // Number of software queues
#define MAX_NUM_VIF 4             // Maximum virtual interfaces
```

### Packet Limits

```c
#define OPENWIFI_MAX_SIGNAL_LEN_TH 1700  // Max packet length threshold
#define OPENWIFI_MIN_SIGNAL_LEN_TH 14    // Min packet length threshold
```

### Timing Constants

All timing calibrated for 10MHz clock unless noted.

```c
// SIFS timing (from xpu.c line 391)
// 16 (standard) + 25 (platform specific) + 7 (timing adjustment)
// - 3 (Colvin LLR) + 8 (new DAC intf) - 2 (calibration)
#define SIFS_TIMING ((16+25+7-3+8-2)<<16)|((16+25+7-3+8-2)<<0)

// ACK timeout (from xpu.c line 392)
// (51 + 2 + 2) * 10 + 15
// 51us: standard ACK timeout
// +2us: device delay margin
// +2us: additional margin
// *10: 10MHz clock
// +15: extra clock cycles for HT detection
#define ACK_TIMEOUT_2_4GHZ ((51+2+2)*10 + 15)
#define ACK_TIMEOUT_5GHZ   ((51+2+2)*10 + 15)
```

---

## Usage Examples

### Basic Initialization Sequence

```c
// 1. Initialize component drivers
tx_intf_api->hw_init(TX_INTF_BW_20MHZ_AT_0MHZ_ANT0, 8, 8, SMALL_FPGA);
rx_intf_api->hw_init(RX_INTF_BW_20MHZ_AT_0MHZ_ANT0, 8, 8);
xpu_api->hw_init(XPU_NORMAL);
openofdm_tx_api->hw_init(OPENOFDM_TX_NORMAL);
openofdm_rx_api->hw_init(OPENOFDM_RX_NORMAL);

// 2. Set MAC address
u8 mac_addr[6] = {0x66, 0x55, 0x44, 0x33, 0x22, 0x11};
xpu_api->XPU_REG_MAC_ADDR_write(mac_addr);

// 3. Configure filter
xpu_api->XPU_REG_FILTER_FLAG_write(
    UNICAST_FOR_US | BROADCAST_ALL_ONE | MY_BEACON
);

// 4. Set antenna
openwifi_set_antenna(dev, 0x1, 0x1);  // ANT0 for both TX and RX

// 5. Setup DMA
openwifi_init_rx_ring(priv);
rx_dma_setup(dev);

for (i = 0; i < MAX_NUM_SW_QUEUE; i++)
    openwifi_init_tx_ring(priv, i);

// 6. Enable interrupts
request_irq(priv->irq_rx, openwifi_rx_interrupt, IRQF_SHARED, "sdr,rx_intf", dev);
request_irq(priv->irq_tx, openwifi_tx_interrupt, IRQF_SHARED, "sdr,tx_intf", dev);

// 7. Start RF
ad9361_rf_set_channel(dev, &conf);
```

### Transmit a Packet

```c
// Called by mac80211
void openwifi_tx(struct ieee80211_hw *dev,
                 struct ieee80211_tx_control *control,
                 struct sk_buff *skb)
{
    struct openwifi_priv *priv = dev->priv;
    struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)skb->data;
    struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);

    // 1. Determine priority/queue
    u8 prio = skb->priority & 0x3;  // 0-3
    int queue_idx = prio;

    // 2. Get TX ring
    struct openwifi_ring *ring = &priv->tx_ring[queue_idx];

    // 3. Check space
    if (ring_is_full(ring)) {
        ieee80211_stop_queue(dev, queue_idx);
        return;
    }

    // 4. Map packet to DMA
    dma_addr_t dma_addr = dma_map_single(
        priv->tx_chan->device->dev,
        skb->data, skb->len, DMA_TO_DEVICE
    );

    // 5. Add to ring
    u32 bd_idx = ring->bd_wr_idx;
    ring->bds[bd_idx].skb_linked = skb;
    ring->bds[bd_idx].dma_mapping_addr = dma_addr;
    ring->bds[bd_idx].len_mpdu = skb->len;
    ring->bd_wr_idx = (bd_idx + 1) % NUM_TX_BD;

    // 6. Configure and submit DMA
    // ... (DMA setup code)

    // 7. Trigger TX
    tx_intf_api->TX_INTF_REG_PKT_INFO1_write(pkt_info);
}
```

### Receive a Packet

```c
// Called by RX interrupt
static irqreturn_t openwifi_rx_interrupt(int irq, void *dev_id)
{
    struct ieee80211_hw *dev = dev_id;
    struct openwifi_priv *priv = dev->priv;

    // 1. Scan RX buffers for packets
    for (int i = 0; i < NUM_RX_BD; i++) {
        u8 *pdata = priv->rx_cyclic_buf + i * RX_BD_BUF_SIZE;
        u16 pkt_flag = (*((u16*)(pdata + 10)));

        if (pkt_flag == 0)  // No packet
            continue;

        // 2. Parse packet header (added by FPGA)
        u32 tsft_low = (*((u32*)(pdata + 0)));
        u32 tsft_high = (*((u32*)(pdata + 4)));
        u16 rssi_half_db = (*((u16*)(pdata + 8)));
        u16 len = (*((u16*)(pdata + 12)));
        u8 rate_idx = pdata[14];
        u8 fcs_ok = pdata[15] & 0x1;

        // 3. Allocate sk_buff
        struct sk_buff *skb = dev_alloc_skb(len + 2);
        skb_reserve(skb, 2);  // Align IP header

        // 4. Copy packet data (after our header)
        memcpy(skb_put(skb, len), pdata + 16, len);

        // 5. Fill RX status
        struct ieee80211_rx_status *rx_status = IEEE80211_SKB_RXCB(skb);
        memset(rx_status, 0, sizeof(*rx_status));

        rx_status->mactime = (u64)tsft_high << 32 | tsft_low;
        rx_status->signal = rssi_half_db_to_rssi_dbm(rssi_half_db, priv->rssi_correction);
        rx_status->freq = priv->actual_rx_lo;
        rx_status->band = priv->band;

        if (fcs_ok)
            rx_status->flag |= RX_FLAG_DECRYPTED;  // No FCS in skb
        else
            rx_status->flag |= RX_FLAG_FAILED_FCS_CRC;

        // Set rate
        if (rate_idx < 12)
            rx_status->rate_idx = rate_idx;  // Legacy rate
        else {
            rx_status->flag |= RX_FLAG_HT;
            rx_status->rate_idx = rate_idx - 12;  // HT MCS
        }

        // 6. Submit to mac80211
        ieee80211_rx_irqsafe(dev, skb);

        // 7. Clear packet flag
        (*((u16*)(pdata + 10))) = 0;
    }

    return IRQ_HANDLED;
}
```

### Configure Channel

```c
static int openwifi_config(struct ieee80211_hw *dev, u32 changed)
{
    struct openwifi_priv *priv = dev->priv;

    if (changed & IEEE80211_CONF_CHANGE_CHANNEL) {
        struct ieee80211_conf *conf = &dev->conf;
        u32 center_freq = conf->chandef.chan->center_freq;

        // 1. Calculate LO frequencies
        u32 rx_lo = center_freq - priv->rx_freq_offset_to_lo_MHz;
        u32 tx_lo = center_freq - priv->tx_freq_offset_to_lo_MHz;

        // 2. Tune RF frontend
        clk_set_rate(priv->ad9361_phy->clks[TX_RFPLL],
                     (u64)tx_lo * 1000000 / 2);
        clk_set_rate(priv->ad9361_phy->clks[RX_RFPLL],
                     (u64)rx_lo * 1000000 / 2);

        priv->actual_tx_lo = tx_lo;
        priv->actual_rx_lo = rx_lo;
        priv->band = freq_MHz_to_band(rx_lo);

        // 3. Calibrate if frequency change > 100MHz
        u32 freq_diff = abs(priv->last_tx_quad_cal_lo - tx_lo);
        if (freq_diff > 100)
            ad9361_tx_calibration(priv, tx_lo);

        // 4. Update RSSI correction and thresholds
        openwifi_rf_rx_update_after_tuning(priv, rx_lo);

        // 5. Update XPU band/channel
        xpu_api->XPU_REG_BAND_CHANNEL_write(
            (priv->use_short_slot << 24) |
            (priv->band << 16) |
            rx_lo
        );
    }

    return 0;
}
```

### Access Statistics via Sysfs

```bash
# Enable statistics
echo 1 > /sys/devices/platform/fpga-axi@0/83c00000.sdr/stat_enable

# Read TX statistics
cat /sys/devices/platform/fpga-axi@0/83c00000.sdr/tx_data_pkt_need_ack_num_total
cat /sys/devices/platform/fpga-axi@0/83c00000.sdr/tx_data_pkt_need_ack_num_total_fail

# Read RX statistics
cat /sys/devices/platform/fpga-axi@0/83c00000.sdr/rx_data_pkt_num_total
cat /sys/devices/platform/fpga-axi@0/83c00000.sdr/rx_data_pkt_mcs_realtime

# Reset statistics
echo 0 > /sys/devices/platform/fpga-axi@0/83c00000.sdr/tx_data_pkt_need_ack_num_total
```

### CSI Capture via Side Channel

```c
// User space code using side_ch_ctl
#include <sys/socket.h>
#include <linux/netlink.h>

#define NETLINK_USER 31
#define ACTION_SIDE_INFO_GET 3

int sock_fd = socket(PF_NETLINK, SOCK_RAW, NETLINK_USER);

struct sockaddr_nl src_addr = {0};
src_addr.nl_family = AF_NETLINK;
src_addr.nl_pid = getpid();
bind(sock_fd, (struct sockaddr*)&src_addr, sizeof(src_addr));

struct sockaddr_nl dest_addr = {0};
dest_addr.nl_family = AF_NETLINK;
dest_addr.nl_pid = 0;  // Kernel

// Prepare message
struct nlmsghdr *nlh = (struct nlmsghdr *)malloc(NLMSG_SPACE(MAX_PAYLOAD));
nlh->nlmsg_len = NLMSG_SPACE(MAX_PAYLOAD);
nlh->nlmsg_pid = getpid();
nlh->nlmsg_flags = 0;

u32 *cmd = (u32 *)NLMSG_DATA(nlh);
cmd[0] = ACTION_SIDE_INFO_GET;
cmd[1] = 0;  // reg_type (unused for get_side_info)
cmd[2] = 0;  // reg_idx (unused)
cmd[3] = 0;  // reg_val (unused)

// Send request
struct iovec iov = {nlh, nlh->nlmsg_len};
struct msghdr msg = {&dest_addr, sizeof(dest_addr), &iov, 1, NULL, 0, 0};
sendmsg(sock_fd, &msg, 0);

// Receive CSI data
recvmsg(sock_fd, &msg, 0);
u8 *csi_data = NLMSG_DATA(nlh);
int csi_size = nlh->nlmsg_len - NLMSG_HDRLEN;

// Parse CSI: Header (2 symbols) + CSI (56 symbols) + EQ (52*num_eq symbols)
// Each symbol = 8 bytes (complex IQ)
```

---

## Error Codes

Common error codes returned by driver functions:

| Code | Meaning |
|------|---------|
| 0 | Success |
| -EINVAL | Invalid argument |
| -ENOMEM | Out of memory |
| -EBUSY | Device busy |
| -EOPNOTSUPP | Operation not supported |
| -EIO | I/O error |
| -ETIMEDOUT | Timeout |
| -EPROBE_DEFER | Probe deferred (waiting for resources) |

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-11-21 | Initial comprehensive API reference |

---

## References

1. **OpenWiFi Project:** https://github.com/open-sdr/openwifi
2. **Linux mac80211 Documentation:** https://www.kernel.org/doc/html/latest/driver-api/80211/index.html
3. **IEEE 802.11 Standard:** IEEE Std 802.11-2020
4. **AD9361 RF Transceiver:** Analog Devices AD9361 datasheet
5. **Xilinx DMA:** Xilinx DMA/Bridge Subsystem for PCI Express

---

**End of API Reference**
