# OpenWiFi Performance Tuning Guide

## Table of Contents

1. [Introduction](#introduction)
2. [Performance Bottleneck Analysis](#performance-bottleneck-analysis)
3. [TX Path Optimization](#tx-path-optimization)
4. [RX Path Optimization](#rx-path-optimization)
5. [Queue Management Tuning](#queue-management-tuning)
6. [DMA Optimization](#dma-optimization)
7. [Interrupt Tuning](#interrupt-tuning)
8. [RF Frontend Optimization](#rf-frontend-optimization)
9. [FPGA Parameter Tuning](#fpga-parameter-tuning)
10. [Rate Adaptation](#rate-adaptation)
11. [Aggregation Tuning](#aggregation-tuning)
12. [Power Management](#power-management)
13. [Measurement and Profiling Tools](#measurement-and-profiling-tools)

---

## Introduction

This guide provides comprehensive information for optimizing the performance of OpenWiFi SDR platforms. OpenWiFi implements a full IEEE 802.11 a/g/n MAC/PHY stack with FPGA acceleration, allowing fine-grained control over all performance-critical parameters.

### Performance Considerations

OpenWiFi performance is primarily determined by:
- **TX throughput**: Limited by DMA bandwidth, FIFO size, and queue management
- **RX sensitivity**: Determined by AGC, power thresholds, and demodulation parameters
- **Latency**: Affected by interrupt handling, DMA buffer sizes, and queue scheduling
- **Reliability**: Influenced by timing calibration, retransmission limits, and carrier sensing

---

## Performance Bottleneck Analysis

### Critical Code Paths

#### TX Path Bottlenecks
```
Location: driver/sdr.c:openwifi_tx() (lines 975-1000+)
Key operations:
1. SKB allocation and DMA mapping
2. Ring buffer descriptor management
3. MPDU delimiter and CRC generation
4. FIFO space checking and queue management
5. DMA submission to FPGA

Typical latency: 20-50us per packet
Bottleneck: Ring buffer full conditions and DMA FIFO congestion
```

#### RX Path Bottlenecks
```
Location: driver/sdr.c:openwifi_rx_interrupt() (lines 464-659)
Key operations:
1. Interrupt handling and buffer scanning
2. Packet validation (length, rate, FCS)
3. SKB allocation and data copy
4. RX status preparation
5. Submission to mac80211

Typical latency: 10-30us per packet
Bottleneck: Cyclic buffer overflow and interrupt coalescing
```

#### DMA Transfer Bottlenecks
```
Location: driver/xilinx_dma/xilinx_dma.c
Key parameters:
- Scatter-Gather descriptors
- Burst size and alignment
- Cache coherency operations
- Interrupt delay and threshold

Typical throughput: 200-400 Mbps (depends on buffer configuration)
Bottleneck: Memory bandwidth and cache line bouncing
```

### Performance Monitoring Points

Use these registers to identify bottlenecks:

```c
// TX interface monitoring
TX_INTF_REG_QUEUE_FIFO_DATA_COUNT  // FIFO occupancy per queue
TX_INTF_REG_S_AXIS_FIFO_NO_ROOM    // FIFO overflow flags

// XPU monitoring
XPU_REG_CSMA_DEBUG                 // CSMA/CA contention stats
XPU_REG_SLICE_COUNT_TOTAL/START/END // Time slice allocation

// Statistics via sysfs
/sys/devices/platform/sdr/tx_prio_queue      // Queue statistics
/sys/devices/platform/sdr/tx_data_pkt_*      // TX success/failure rates
/sys/devices/platform/sdr/rx_data_pkt_*      // RX success/failure rates
```

---

## TX Path Optimization

### FIFO Configuration

**Location**: `driver/tx_intf/tx_intf.c:hw_init()` (lines 231-250)

#### FIFO Threshold Settings

The S-AXIS FIFO threshold determines when to stop accepting new packets:

```c
// For LARGE FPGA (MAX_NUM_DMA_SYMBOL = 8192)
TX_INTF_REG_S_AXIS_FIFO_TH = 8192 - (210*2) = 7772

// For SMALL FPGA (MAX_NUM_DMA_SYMBOL = 4096)
TX_INTF_REG_S_AXIS_FIFO_TH = 4096 - (210*2) = 3676
```

**Tuning Guidelines:**
- **Higher throughput**: Decrease threshold (e.g., `8192 - (210*5)`) to accept more packets
  - Risk: FIFO overflow if packets arrive faster than transmission
- **Lower latency**: Increase threshold to stop accepting packets earlier
  - Risk: Underutilization of FIFO capacity
- **Default**: `(210*2)` provides room for 2 maximum-sized packets per queue

**Modification**: Edit line 247 or 250 in `driver/tx_intf/tx_intf.c` and recompile driver.

### Baseband Gain

**Location**: `driver/tx_intf/tx_intf.c:hw_init()` (line 347)

```c
TX_INTF_REG_BB_GAIN = 250
```

**Critical Parameter**: This controls the digital scaling before DAC output.

**Test Results** (documented in code comments, lines 327-346):
```
5220 MHz:
  BB_GAIN  Power    EVM
  400      -6.0dBm  -34/-35dB
  350      -7.2dBm  -34/-35/-36dB
  300      -8.5dBm  -35/-36/-37dB

2437 MHz:
  BB_GAIN  Power    EVM
  400      -3.2dBm  -36/-37dB
  350      -4.4dBm  -37/-38/-39dB
  300      -5.7dBm  -39/-40dB
  <290     varying  -40/-41/-42dB (excellent EVM)
```

**Tuning Guidelines:**
- **Default 250**: Conservative setting, works for all MCS rates including 11n MCS 0
- **Increase to 290**: Better EVM for 11a/g and 11n MCS 1-7
  - Risk: High PAPR (Peak-to-Average Power Ratio) destroys 11n MCS 0 long packets
- **Decrease to 200**: Reduce power if interfering with other devices
- **Range**: 100-400 (hardware enforced limits)

**Modification**: Edit line 347 in `driver/tx_intf/tx_intf.c`.

### TX Hold Threshold

**Location**: `driver/tx_intf/tx_intf.c:hw_init()` (line 321)

```c
TX_INTF_REG_TX_HOLD_THRESHOLD = 420
```

This controls when to start transmitting after packet arrival (in clock cycles at 200MHz = 2.1us).

**Tuning Guidelines:**
- **Default 420 (2.1us)**: Ensures adequate data buffering
- **Decrease (300-400)**: Lower latency for real-time applications
  - Risk: Underrun if DMA can't keep up
- **Increase (500-600)**: More reliable transmission in high-load scenarios
  - Risk: Increased latency

### Ring Buffer Configuration

**Location**: `driver/sdr.h` (lines 134-141)

```c
#define NUM_TX_BD 64              // Number of TX buffer descriptors
#define TX_BD_BUF_SIZE 8192       // Size of each TX buffer
#define RING_ROOM_THRESHOLD 6     // (2+MAX_NUM_SW_QUEUE) free slots required
```

**Buffer Descriptor Count** (`NUM_TX_BD`):
- **Default 64**: Balanced between memory usage and queue depth
- **Increase to 128**: Better for bursty traffic, more buffering
  - Requires FPGA modification (align with `tx_intf_s_axis.v`)
  - Risk: Higher memory consumption
- **Decrease to 32**: Lower memory footprint
  - Risk: More frequent queue stops

**Room Threshold** (`RING_ROOM_THRESHOLD`):
- Determines when to stop Linux TX queues
- Default: 6 = 2 + 4 queues (room for one packet per queue + 2 extra)
- **Increase**: More conservative, stops queues earlier
- **Decrease**: More aggressive, risks FIFO overflow

### DMA Symbol Configuration

**Location**: `driver/tx_intf/tx_intf.c:hw_init()` (line 319)

```c
TX_INTF_REG_NUM_DMA_SYMBOL_TO_PS = num_dma_symbol_to_ps  // Default: 8
```

Each DMA symbol is 64 bits (8 bytes). This determines the granularity of DMA transfers.

**Tuning Guidelines:**
- **Default 8**: 64 bytes per transfer
- **Increase (16-32)**: Larger DMA bursts, better throughput
  - Risk: Higher latency for short packets
- **Decrease (4-6)**: Lower latency
  - Risk: More DMA overhead, lower throughput

### Antenna Selection

**Location**: `driver/tx_intf/tx_intf.c:hw_init()` (lines 258-298)

```c
TX_INTF_BW_20MHZ_AT_0MHZ_ANT0      // Antenna 0 only
TX_INTF_BW_20MHZ_AT_0MHZ_ANT1      // Antenna 1 only
TX_INTF_BW_20MHZ_AT_0MHZ_ANT_BOTH  // Both antennas (diversity/MIMO)
```

**Runtime Control**:
```bash
# Set via sdrctl or directly
echo "0x11" > /sys/kernel/debug/ieee80211/phy0/sdr/tx_intf_cfg
```

---

## RX Path Optimization

### Power Threshold Configuration

**Location**: `driver/openofdm_rx/openofdm_rx.c:hw_init()` (lines 97-103)

```c
OPENOFDM_RX_POWER_THRES_INIT = 124
OPENOFDM_RX_DC_RUNNING_SUM_TH_INIT = 64
```

**Power Threshold** determines packet detection sensitivity:

```c
// Sensitivity test results documented in driver/hw_def.h (lines 228-250)
// FMCOMMS3 @ 2437 MHz: -85dBm (rssi_half_db = 136, threshold = 118)
// FMCOMMS3 @ 5320 MHz: -86dBm (rssi_half_db = 124)
// FMCOMMS2 @ 2437 MHz: -80dBm (rssi_half_db = 146)
// FMCOMMS2 @ 5320 MHz: -86dBm (rssi_half_db = 124)
```

**Tuning Guidelines:**
- **Default 124**: Based on 5 GHz sensitivity measurements
- **Decrease (100-120)**: Better sensitivity, lower detection threshold
  - Risk: More false alarms, noise packets
  - Use case: Long-range communication
- **Increase (130-150)**: Fewer false alarms, higher SNR required
  - Risk: Miss weak signals
  - Use case: High-interference environment

**Runtime Control via RSSI dBm threshold**:
```bash
# Set receiver demodulation threshold via sdrctl
sdrctl dev wlan0 set reg drv_rx 0 85  # -85 dBm threshold
```

The driver automatically converts dBm to power threshold using `rssi_correction`:
```c
// Location: driver/sdr.c:openwifi_rf_rx_update_after_tuning() (lines 244-247)
receiver_rssi_dbm_th = (priv->drv_rx_reg_val[0] == 0 ?
                        OPENOFDM_RX_RSSI_DBM_TH_DEFAULT :
                        -priv->drv_rx_reg_val[0]);
receiver_rssi_th = rssi_dbm_to_rssi_half_db(receiver_rssi_dbm_th,
                                             priv->rssi_correction);
```

### Minimum Plateau Configuration

**Location**: `driver/openofdm_rx/openofdm_rx.c:hw_init()` (line 105)

```c
OPENOFDM_RX_MIN_PLATEAU_INIT = 100
```

This determines the minimum length of constant power for packet detection.

**Tuning Guidelines:**
- **Default 100**: Standard 802.11 preamble detection
- **Increase (120-150)**: More robust against false positives
  - Risk: May miss packets with poor preambles
- **Decrease (80-90)**: Detect packets with shorter preambles
  - Risk: More false alarms

### FFT Window Shift

**Location**: `driver/openofdm_rx/openofdm_rx.c:hw_init()` (line 107)

```c
OPENOFDM_RX_FFT_WIN_SHIFT_INIT = 4
OPENOFDM_RX_SMALL_EQ_OUT_COUNTER_TH = 48
```

**FFT Window Shift** controls the timing offset for FFT computation:

**Tuning Guidelines:**
- **Default 4**: Standard timing offset
- **Increase (5-6)**: For multipath environments, wider timing window
- **Decrease (3)**: For LOS environments, tighter timing
- **Range**: 0-7 (hardware constraint)

### RX Buffer Configuration

**Location**: `driver/sdr.h` (lines 137-141)

```c
#define NUM_RX_BD 64              // With USE_NEW_RX_INTERRUPT
#define NUM_RX_BD 16              // Without (legacy)
#define RX_BD_BUF_SIZE 2048       // Size of each RX buffer
```

**Buffer Descriptor Count** (`NUM_RX_BD`):
- **Default 64**: Modern interrupt-driven mode (recommended)
- **Legacy 16**: Polling mode (legacy, less efficient)
- **Increase to 128**: Better for high packet rate environments
  - Risk: Higher memory consumption
- **Trade-off**: Each buffer is 2KB, so 64 buffers = 128KB total

**Buffer Size** (`RX_BD_BUF_SIZE`):
- **Default 2048**: Sufficient for maximum 802.11 frame size
- **Do not decrease**: Will cause packet truncation
- **Can increase**: Useful for capturing extra metadata, but wasteful

### Interrupt Delay Configuration

**Location**: `driver/rx_intf/rx_intf.c:hw_init()` (line 295)

```c
RX_INTF_REG_S2MM_INTR_DELAY_COUNT = 30*10  // 30us delay
```

This controls interrupt coalescing for RX packets.

**Tuning Guidelines:**
- **Default 300 (30us @ 10MHz clock)**: Balanced latency/overhead
- **Decrease (100-200)**: Lower latency for real-time applications
  - Effect: 10-20us latency, higher interrupt rate
  - Use case: VoIP, gaming, control loops
- **Increase (500-1000)**: Lower CPU overhead for bulk transfers
  - Effect: 50-100us latency, fewer interrupts
  - Use case: File transfer, video streaming

**Runtime Modification**:
```bash
# Requires direct register access
echo "100" > /sys/kernel/debug/ieee80211/phy0/sdr/rx_intf/intr_delay
```

### TLAST Timeout

**Location**: `driver/rx_intf/rx_intf.c:hw_init()` (line 177)

```c
RX_INTF_REG_TLAST_TIMEOUT_TOP = 7000
```

This sets the maximum time to wait for packet completion (in 10MHz clock cycles = 700us).

**Tuning Guidelines:**
- **Default 7000 (700us)**: Handles maximum packet size at lowest rate
- **Decrease (5000)**: Faster timeout for shorter packets
  - Risk: May timeout legitimate long packets at low rates
- **Increase (10000)**: More tolerance for very long packets
  - Risk: Longer delay before error recovery

### Packet Length Limits

**Location**: `driver/hw_def.h` (lines 260-263)

```c
#define OPENWIFI_MAX_SIGNAL_LEN_TH 1700  // Maximum packet length
#define OPENWIFI_MIN_SIGNAL_LEN_TH 14    // Minimum packet length (4 bytes for CRC32)
```

These are enforced in both openofdm_rx and rx_intf.

**Tuning Guidelines:**
- **MAX_SIGNAL_LEN_TH**:
  - Default 1700: Slightly above maximum 802.11 MSDU
  - Increase: Allow malformed/test packets
  - Decrease: Reject extra-long packets early
- **MIN_SIGNAL_LEN_TH**:
  - Default 14: Minimum for CRC validation
  - Do not decrease below 14

### Baseband Gain

**Location**: `driver/rx_intf/rx_intf.c:hw_init()` (line 326)

```c
RX_INTF_REG_BB_GAIN = 4
```

This controls digital gain after ADC (in bits to shift left).

**Tuning Guidelines:**
- **Default 4**: 16x gain (2^4)
- **Increase (5-6)**: More digital gain, better for weak signals
  - Risk: Overflow/saturation with strong signals
- **Decrease (2-3)**: Less gain, better dynamic range
  - Risk: Reduced sensitivity

---

## Queue Management Tuning

### Queue Architecture

OpenWiFi implements a multi-queue system:
- **4 Linux software queues** (AC_VO, AC_VI, AC_BE, AC_BK)
- **4 FPGA hardware queues** (priority-based scheduling)
- **Ring buffer** per software queue (default 64 descriptors)

**Location**: `driver/sdr.c:openwifi_tx()` and interrupt handlers

### Queue Mapping

**Location**: `driver/sdr.c` (queue_idx calculation in TX path)

```c
// Linux priority to queue index mapping
// prio 0 (BE) -> queue_idx 0
// prio 1 (BK) -> queue_idx 1
// prio 2 (VI) -> queue_idx 2
// prio 3 (VO) -> queue_idx 3
```

### CSMA/CA Configuration

**Location**: `driver/xpu/xpu.c:hw_init()` (lines 384-388)

```c
XPU_REG_CSMA_CFG = configured_per_queue_by_mac80211
// Bit layout:
// [3:0]   - CW_min exponent
// [7:4]   - CW_max exponent
// [15:8]  - AIFSN
// [23:16] - Slot time
```

**Linux configures via**: `openwifi_conf_tx()` callback

**Manual tuning**:
```bash
# Example: Aggressive settings for VO queue (lower contention)
# CW_min=3 (2^3-1=7), CW_max=4 (2^4-1=15), AIFSN=2, slot=9us
sdrctl dev wlan0 set reg xpu 19 0x00090204
```

**Guidelines:**
- **CW_min/max**: Smaller values = more aggressive, higher collision risk
- **AIFSN**: Smaller values = higher priority, less wait time
- **Standard values**:
  - VO: CW_min=3, CW_max=4, AIFSN=2
  - VI: CW_min=3, CW_max=4, AIFSN=2
  - BE: CW_min=4, CW_max=10, AIFSN=3
  - BK: CW_min=4, CW_max=10, AIFSN=7

### Time Slice Allocation

**Location**: `driver/xpu/xpu.c:hw_init()` (lines 340-345)

```c
// Each queue gets a time slice for transmission
for (i=0; i<4; i++) {
  XPU_REG_SLICE_COUNT_TOTAL_write((i<<20)|16);  // Total 16us
  XPU_REG_SLICE_COUNT_START_write((i<<20)|0);   // Start 0us
  XPU_REG_SLICE_COUNT_END_write((i<<20)|16);    // End 16us
}
```

**Default**: All queues open all the time (0-16us = always available)

**Custom scheduling**:
```c
// Example: Give VO more time
XPU_REG_SLICE_COUNT_TOTAL_write((3<<20)|20);  // VO: 20us total
XPU_REG_SLICE_COUNT_START_write((3<<20)|0);
XPU_REG_SLICE_COUNT_END_write((3<<20)|20);

// Restrict BE
XPU_REG_SLICE_COUNT_TOTAL_write((0<<20)|10);  // BE: 10us total
XPU_REG_SLICE_COUNT_START_write((0<<20)|0);
XPU_REG_SLICE_COUNT_END_write((0<<20)|10);
```

**Use case**: QoS-aware time-division scheduling

### Queue Stop/Wake Mechanism

**Location**: `driver/sdr.c:openwifi_tx()` (queue stop logic)

Queue stop conditions:
1. **FIFO full**: `(dma_fifo_no_room_flag & (1<<prio)) != 0`
2. **Hardware queue full**: `hw_queue_len[queue] >= NUM_TX_BD - RING_ROOM_THRESHOLD`

**Monitoring**:
```bash
# Check queue statistics
cat /sys/devices/platform/sdr/tx_prio_queue
# Output format per queue:
# tx_num interrupt_num stop0_fake stop0_real stop1 wakeup ...
```

**Tuning `RING_ROOM_THRESHOLD`**:
- Located in `driver/sdr.h` line 133
- Default: 6 (2 + 4 queues)
- **Increase (8-10)**: More conservative, stops queues earlier
  - Pro: Prevents overflow
  - Con: Underutilizes capacity
- **Decrease (4)**: More aggressive
  - Pro: Higher throughput
  - Con: Risk of overflow in burst scenarios

---

## DMA Optimization

### DMA Channel Configuration

**Location**: `driver/xilinx_dma/xilinx_dma.c`

#### Cyclic Mode (RX)

OpenWiFi RX uses **cyclic DMA** mode:

```c
// Location: driver/sdr.c:rx_dma_setup() (line 431)
priv->rxd = rx_dev->device_prep_dma_cyclic(
    priv->rx_chan,
    priv->rx_cyclic_buf_dma_mapping_addr,
    RX_BD_BUF_SIZE * NUM_RX_BD,  // Total buffer size
    RX_BD_BUF_SIZE,               // Period size (per-buffer)
    DMA_DEV_TO_MEM,
    DMA_CTRL_ACK | DMA_PREP_INTERRUPT
);
```

**Key Parameters:**
- **Buffer count**: `NUM_RX_BD` (64 default)
- **Buffer size**: `RX_BD_BUF_SIZE` (2048 default)
- **Total memory**: 64 * 2048 = 128 KB

**Optimization:**
- **Increase NUM_RX_BD**: Better for high packet rates
  - Pro: More buffering, fewer overruns
  - Con: Higher memory usage
- **Decrease RX_BD_BUF_SIZE**: If max packet size is smaller
  - Pro: More buffers for same memory
  - Con: Cannot receive full-sized frames

#### Scatter-Gather Mode (TX)

OpenWiFi TX uses **on-demand SG-DMA**:

```c
// Location: driver/sdr.c:openwifi_tx()
// Each TX packet gets its own DMA descriptor
dma_mapping_addr = dma_map_single(priv->tx_chan->device->dev,
                                   dma_buf, len, DMA_MEM_TO_DEV);
```

**Optimization:**
- **Descriptor caching**: Pre-allocate descriptors for hot path
- **Coalescing**: Submit multiple descriptors together
  - Currently: One descriptor per packet
  - Improvement: Batch multiple packets before `dmaengine_submit()`

### DMA Interrupt Configuration

**Location**: `driver/xilinx_dma/xilinx_dma.c` (DMACR register fields)

```c
#define XILINX_DMA_DMACR_DELAY_MAX 0xff
#define XILINX_DMA_DMACR_DELAY_SHIFT 24
#define XILINX_DMA_DMACR_FRAME_COUNT_MAX 0xff
#define XILINX_DMA_DMACR_FRAME_COUNT_SHIFT 16
```

**Interrupt coalescing**: Reduce interrupt rate by batching completions

```c
// Pseudo-code for tuning (not directly exposed)
DMACR = (delay_count << 24) | (frame_count << 16) | other_bits;

// Example values:
delay_count = 10;   // Wait up to 10 * clock_period before interrupt
frame_count = 4;    // Or wait for 4 frames, whichever comes first
```

**For OpenWiFi:**
- RX: Use `RX_INTF_REG_S2MM_INTR_DELAY_COUNT` instead (easier)
- TX: Interrupts are critical for queue management, keep responsive

### Cache Coherency

**Location**: `driver/sdr.c:openwifi_init_rx_ring()` (line 400)

```c
priv->rx_cyclic_buf = dma_alloc_coherent(
    priv->rx_chan->device->dev,
    RX_BD_BUF_SIZE * NUM_RX_BD,
    &priv->rx_cyclic_buf_dma_mapping_addr,
    GFP_KERNEL
);
```

**dma_alloc_coherent** ensures CPU and DMA see consistent memory.

**Alternatives for advanced users:**
- **Non-coherent** + explicit `dma_sync_*()`: Lower overhead, manual cache ops
  - Pro: Faster DMA setup
  - Con: Must carefully sync before/after DMA
  - Requires architecture support

### DMA Burst Size

**Location**: FPGA configuration (not directly in driver)

The Xilinx DMA IP core is configured in Vivado with:
- **Burst length**: 16, 32, 64, 128 beats
- **Data width**: 32, 64, 128, 256 bits

**OpenWiFi typically uses:**
- **64-bit data width** (8 bytes)
- **16-beat bursts** (128 bytes per burst)

**To optimize:**
1. Modify FPGA configuration in Vivado
2. Increase burst length (e.g., 32 beats = 256 bytes)
   - Pro: Better memory bandwidth utilization
   - Con: Higher latency per transaction
3. Match software buffer alignment
   - Ensure `RX_BD_BUF_SIZE` and `TX_BD_BUF_SIZE` are burst-aligned

---

## Interrupt Tuning

### Interrupt Handling Architecture

OpenWiFi uses two primary interrupts:
- **RX interrupt**: `irq_rx` - triggered by packet reception
- **TX interrupt**: `irq_tx` - triggered by transmission completion

**Handlers**: `openwifi_rx_interrupt()` and `openwifi_tx_interrupt()` in `driver/sdr.c`

### RX Interrupt Optimization

**Location**: `driver/sdr.c:openwifi_rx_interrupt()` (lines 464-659)

#### Batch Processing

```c
#ifdef USE_NEW_RX_INTERRUPT
  for (i=0; i<NUM_RX_BD; i++) {
    // Process all packets in cyclic buffer
  }
#else
  while(1) {
    // Process packets until buffer empty
  }
#endif
```

**USE_NEW_RX_INTERRUPT** mode (recommended):
- Processes all available packets in one interrupt
- More efficient for high packet rates
- Requires `NUM_RX_BD 64` (vs. 16 in legacy mode)

**To enable**:
```c
// In driver/sdr.h (line 137)
#define USE_NEW_RX_INTERRUPT
```

#### Interrupt Delay

Already covered in [RX Path Optimization](#interrupt-delay-configuration):
```c
RX_INTF_REG_S2MM_INTR_DELAY_COUNT = 30*10  // 30us @ 10MHz
```

**Additional tuning:**
- **Real-time systems**: Decrease to 10us (value 100)
- **Throughput-oriented**: Increase to 100us (value 1000)

#### NAPI Considerations

OpenWiFi does **not** currently use NAPI (New API) for interrupt mitigation. All packets are processed in hard IRQ context.

**Potential optimization**:
- Implement NAPI-style polling for RX
- Move packet processing to softirq context
- Trade-off: Slightly higher latency, much lower IRQ overhead

### TX Interrupt Optimization

**Location**: `driver/sdr.c:openwifi_tx_interrupt()` (lines 661-849)

#### Interrupt Source Selection

**Location**: `driver/tx_intf/tx_intf.c:hw_init()` (lines 322-323)

```c
TX_INTF_REG_INTERRUPT_SEL = 0x4;      // Enable, source: tx_try_complete
TX_INTF_REG_INTERRUPT_SEL = 0x30004;  // Disable interrupt
```

**Interrupt sources** (bits 2:0):
- 0: `s00_axis_tlast`
- 1: `ap_start`
- 2: `tx_start_from_acc`
- 3: `tx_end_from_acc`
- 4: `tx_try_complete from xpu` (default, recommended)

**Bit 16-17**: Disable flags (0x3 to disable)

**Tuning:**
- Default (0x4): Interrupt on transmission attempt completion
- Alternative (0x3): Interrupt on TX end (earlier, but less info available)

#### Batch Completion Processing

The TX interrupt handler processes multiple completed packets:

```c
while(1) {
  reg_val1 = tx_intf_api->TX_INTF_REG_PKT_INFO1_read();
  if (reg_val1 != 0xFFFFFFFF) {
    // Process completion info
    pkt_cnt = (reg_val2 & 0x3F);
    for(i = 1; i <= pkt_cnt; i++) {
      // Report to mac80211
    }
  } else break;
}
```

**Performance:** Loop count typically 1, occasionally 2-3 in high load.

**Warning logging** (line 844):
```c
if (loop_count != 1)
  printk("WARNING loop_count %d\n", loop_count);
```

### Interrupt Affinity

**CPU pinning for interrupts:**

```bash
# Find IRQ numbers
cat /proc/interrupts | grep -E 'sdr|dma'

# Pin RX IRQ to CPU 0
echo 1 > /proc/irq/<rx_irq_number>/smp_affinity

# Pin TX IRQ to CPU 1
echo 2 > /proc/irq/<tx_irq_number>/smp_affinity
```

**Benefits:**
- Reduce cache thrashing
- Separate RX and TX processing
- Lower interrupt latency

**For Zynq (dual-core Cortex-A9):**
```bash
# Balance interrupts across both cores
echo 1 > /proc/irq/<rx_irq>/smp_affinity   # CPU0
echo 2 > /proc/irq/<tx_irq>/smp_affinity   # CPU1
```

### Interrupt Rate Monitoring

**sysfs statistics:**
```bash
# Monitor interrupt rates
cat /sys/devices/platform/sdr/tx_prio_queue
# Column 2: interrupt_num per queue

# Check interrupt counts
cat /proc/interrupts | grep sdr
```

**Ideal rates:**
- RX: 1000-10000 interrupts/sec (depends on traffic)
- TX: Similar, slightly lower
- High rates (>20000): Consider increasing coalescing delay

---

## RF Frontend Optimization

### AD9361 Configuration

OpenWiFi supports Analog Devices AD9361 transceiver for both Zynq and ZynqMP platforms.

**Location**: `driver/sdr.c:ad9361_rf_set_channel()` (lines 261-302)

### TX Calibration

**Location**: `driver/sdr.c:ad9361_tx_calibration()` (lines 209-228)

```c
void ad9361_tx_calibration(struct openwifi_priv *priv, u32 actual_tx_lo) {
  xpu_api->XPU_REG_SPI_DISABLE_write(1);  // Disable FPGA SPI
  ad9361_do_calib_run(priv->ad9361_phy, TX_QUAD_CAL,
                      priv->ad9361_phy->state->last_tx_quad_cal_phase);
  xpu_api->XPU_REG_SPI_DISABLE_write(spi_disable);  // Restore
}
```

**Calibration triggers**:
- Frequency change > 100 MHz
- Initial power-on
- Temperature change (not auto-triggered)

**Tuning:**
- **Increase threshold** (line 296): `if (diff_tx_lo > 200)` for less frequent calibration
  - Pro: Faster channel switching
  - Con: Slightly worse IQ imbalance correction
- **Force manual calibration**:
  ```bash
  sdrctl dev wlan0 set reg rf_tx 1 <freq_MHz>  # Force TX LO change
  ```

### RX Gain Control

**Location**: AGC is handled by AD9361 automatically, but thresholds are configurable.

**RSSI Correction:**
```c
// Location: driver/sdr.c:rssi_correction_lookup_table() (lines 187-207)
// Frequency-dependent RSSI offset calibration
if (freq_MHz <= 2484)      rssi_correction = 153;  // 2.4 GHz
else if (freq_MHz <= 5240) rssi_correction = 145;  // Low 5 GHz
else if (freq_MHz <= 5320) rssi_correction = 145;  // Mid 5 GHz
else                       rssi_correction = 145;  // High 5 GHz
```

**These values are empirically determined** for FMCOMMS2/3 boards.

**Custom calibration:**
1. Use a calibrated signal generator at target frequency
2. Measure reported RSSI vs. actual power
3. Adjust `rssi_correction` values in code

**Runtime RSSI reporting:**
```bash
# Check current RSSI correction
cat /sys/kernel/debug/ieee80211/phy0/sdr/rssi_correction
```

### TX Attenuation

**Location**: RF frontend attenuation is controlled by `ad9361_set_tx_atten()`.

**Initial setting:**
```bash
# At module load (insmod parameter)
insmod openwifi.ko init_tx_att=3000  # 3 dB attenuation
```

**Runtime control:**
```bash
# Via sdrctl
sdrctl dev wlan0 set reg rf_tx 0 5000  # 5 dB attenuation

# Direct SPI access (advanced)
# Requires understanding of AD9361 register map
```

**Tuning guidelines:**
- **Default 0**: Maximum TX power
- **Increase (3000-10000)**: Reduce interference, regulatory compliance
- **Typical values**:
  - Indoor: 3000-6000 (3-6 dB)
  - Outdoor: 0-3000 (0-3 dB)
  - Conductive test: 10000-20000 (10-20 dB)

### RX/TX LO Frequency Offset

**Purpose**: Avoid DC offset and IQ imbalance issues by offsetting LO from channel center.

**Location**: `driver/sdr.c` (initialized in probe function)

```c
priv->rx_freq_offset_to_lo_MHz = 0;   // or ±10 MHz for 40 MHz bandwidth
priv->tx_freq_offset_to_lo_MHz = 0;
```

**Configuration** (platform-dependent):
- **20 MHz BW**: 0 MHz offset (direct conversion)
- **40 MHz BW**: ±10 MHz offset (with digital mixer compensation)

**Mode selection:**
```c
// TX modes (driver/hw_def.h lines 66-76)
TX_INTF_BW_20MHZ_AT_0MHZ_ANT0      // Direct, no offset
TX_INTF_BW_20MHZ_AT_N_10MHZ_ANT0   // -10 MHz offset
TX_INTF_BW_20MHZ_AT_P_10MHZ_ANT0   // +10 MHz offset

// RX modes (driver/hw_def.h lines 158-167)
RX_INTF_BW_20MHZ_AT_0MHZ_ANT0
RX_INTF_BW_20MHZ_AT_N_10MHZ_ANT0
RX_INTF_BW_20MHZ_AT_P_10MHZ_ANT0
```

**Tuning:**
- Most setups: Use 0 MHz offset
- If DC offset visible: Switch to ±10 MHz mode
  - Requires FPGA to support mixer compensation
  - Check `rx_intf_fo_mapping[]` and `tx_intf_fo_mapping[]` arrays

### RF Bandwidth

**Location**: Configured during AD9361 initialization

```c
priv->rf_bw = 20000000;  // 20 MHz (default for 802.11a/g/n)
```

**Typical values:**
- **20 MHz**: Standard 802.11a/g/n operation
- **40 MHz**: For 40 MHz channel bonding (requires FPGA support)

**Modify** (requires AD9361 reconfiguration and FPGA changes):
1. Change `priv->rf_bw` in driver
2. Ensure FPGA design supports target bandwidth
3. Adjust decimation/interpolation rates accordingly

### Antenna Diversity

**Runtime configuration:**
```bash
# Set TX antenna (bitmask: bit0=ANT0, bit1=ANT1)
iw dev wlan0 set antenna 1 1  # TX on ANT0, RX on ANT0
iw dev wlan0 set antenna 2 2  # TX on ANT1, RX on ANT1
iw dev wlan0 set antenna 3 3  # TX and RX on both (diversity)
```

**Implementation**: `openwifi_set_antenna()` in `driver/sdr.c`

---

## FPGA Parameter Tuning

### XPU (MAC Controller) Parameters

**Location**: `driver/xpu/xpu.c:hw_init()`

#### SIFS and Timing

**Location**: `driver/xpu/xpu.c:hw_init()` (lines 391-397)

```c
// SIFS configuration (assuming 2.4 and 5 GHz have same SIFS)
XPU_REG_SEND_ACK_WAIT_TOP =
  ((16+25+7-3+8-2)<<16) | ((16+25+7-3+8-2)<<0);  // Both bands

// ACK reception timeout
XPU_REG_RECV_ACK_COUNT_TOP0 =
  (1<<31) | (((51+2+2)*10 + 15)<<16) | (10+3);  // 2.4 GHz

XPU_REG_RECV_ACK_COUNT_TOP1 =
  (1<<31) | (((51+2+2)*10 + 15)<<16) | (10+3);  // 5 GHz
```

**Breakdown:**
- `SEND_ACK_WAIT_TOP`: SIFS duration in us (51us default)
  - 16us: Preamble + signal
  - 25us: Processing delay
  - 7us: Timing adjustment
  - -3us: LLR correction
  - 8us: New DAC interface speedup
  - -2us: 2024 Oct calibration
- `RECV_ACK_COUNT_TOP`: ACK timeout in 100ns units
  - (51+2+2)*10 = 550 clocks base
  - +15: Extra margin for HT detection
  - +3: LLR correction

**Tuning for faster turnaround:**
```c
// Aggressive SIFS (48us instead of 51us)
XPU_REG_SEND_ACK_WAIT_TOP = (48<<16) | (48<<0);
```
- Pro: Faster throughput
- Con: May violate 802.11 timing, compatibility issues

**Tuning for robust operation:**
```c
// Conservative timeouts (add 100 clocks = 10us margin)
XPU_REG_RECV_ACK_COUNT_TOP0 = (1<<31) | (((51+2+2)*10 + 15 + 100)<<16) | (10+3);
```
- Pro: More tolerant of slow responders
- Con: Slower error recovery

#### DIFS and Slot Time

**Location**: `driver/xpu/xpu.c:hw_init()` (line 399)

```c
XPU_REG_DIFS_ADVANCE = (OPENWIFI_MAX_SIGNAL_LEN_TH<<16) | 2;  // 2us advance
```

- **Low 16 bits**: DIFS advance in microseconds
- **High 16 bits**: Maximum signal length threshold (1700 bytes)

**802.11 standard:**
- DIFS = SIFS + 2*SlotTime
- SlotTime: 9us (5 GHz), 20us (2.4 GHz long slot), 9us (2.4 GHz short slot)

**Current setting**: 2us advance (added to standard DIFS)

**Tuning:**
- **Increase (3-5us)**: More conservative, less collisions
- **Decrease (0-1us)**: More aggressive, higher throughput
- **Should not exceed** slot time, or violates standard

#### BB/RF Delay Calibration

**Location**: `driver/xpu/xpu.c:hw_init()` (line 338)

```c
XPU_REG_BB_RF_DELAY = (16<<24) | (0<<16) | (26<<8) | 9;
```

**Bit layout:**
- [31:24] = 16: LO up time before packet (1.6us @ 10MHz)
- [23:16] = 0: LO down time after packet
- [15:8] = 26: RF port switch-on time (2.6us)
- [7:0] = 9: RF port switch-off time (0.9us)

**Purpose**: Synchronize baseband data with RF frontend switching.

**Calibration method:**
1. Use spectrum analyzer with trigger mode
2. Observe RF on/off timing relative to baseband symbols
3. Adjust values to minimize transition artifacts

**Typical range:**
- LO up: 10-20 (1-2us)
- LO down: 0-10 (0-1us)
- Port switch: 20-30 (2-3us)

#### Retransmission Limits

**Location**: `driver/xpu/xpu.c:hw_init()` (line 335)

```c
// Commented out, defaults to mac80211 control
// XPU_REG_ACK_CTL_MAX_NUM_RETRANS = 3;
```

**If enabled**: Overrides mac80211 retry limits with fixed value.

**Runtime control** (mac80211):
```bash
# Set retry limits via iw
iw dev wlan0 set retry short 7 long 4
```

**For testing:**
```c
// Force specific retry count (uncomment line 335)
XPU_REG_ACK_CTL_MAX_NUM_RETRANS = 5;  // 5 retries max
```

#### LBT (Listen Before Talk) Threshold

**Location**: `driver/xpu/xpu.c:hw_init()` (lines 376-378)

```c
rssi_half_db_th = 87<<1;  // -62dBm equivalent
XPU_REG_LBT_TH = rssi_half_db_th;
```

**Purpose**: Carrier sense threshold for CSMA/CA.

**Tuning:**
```c
// More sensitive (detect weaker signals as busy)
rssi_half_db_th = 90<<1;  // ~-60dBm

// Less sensitive (more aggressive transmission)
rssi_half_db_th = 82<<1;  // ~-65dBm
```

**Runtime control:**
```bash
sdrctl dev wlan0 set reg drv_xpu 0 62  # Set to -62 dBm
# 0 = auto mode, uses default based on frequency
```

**Guidelines:**
- **Dense networks**: Increase sensitivity (higher threshold value in half-dB)
- **Isolated links**: Decrease sensitivity for spatial reuse
- **Regulatory**: Some regions mandate maximum sensitivity

#### Force Idle Duration

**Location**: `driver/xpu/xpu.c:hw_init()` (line 382)

```c
XPU_REG_FORCE_IDLE_MISC = (1<<26) | 75;  // 75 clocks = 7.5us
```

- **Low 16 bits**: Force idle duration after packet (10MHz clock)
- **Bit 26**: Disable EIFS trigger by last TX fail (set to 1)

**Purpose**: Give AGC time to settle after strong signal.

**Tuning:**
- **Default 75 (7.5us)**: Adequate for most scenarios
- **Increase (100-150)**: For environments with strong adjacent signals
- **Decrease (50)**: For fast turnaround, risks AGC issues

### OpenOFDM RX Parameters

Already covered in detail in [RX Path Optimization](#rx-path-optimization). Summary of key registers:

```c
OPENOFDM_RX_REG_POWER_THRES      // Packet detection threshold
OPENOFDM_RX_REG_MIN_PLATEAU      // Minimum plateau length
OPENOFDM_RX_REG_FFT_WIN_SHIFT    // FFT window timing
OPENOFDM_RX_REG_SOFT_DECODING    // Enable soft-decision Viterbi
OPENOFDM_RX_REG_PHASE_OFFSET_ABS_TH  // Phase offset threshold
```

### OpenOFDM TX Parameters

**Location**: `driver/openofdm_tx/openofdm_tx.c:hw_init()`

Minimal configuration (mostly FPGA-hardcoded):

```c
OPENOFDM_TX_REG_MULTI_RST         // Reset
OPENOFDM_TX_REG_INIT_PILOT_STATE  // Pilot scrambler state (optional)
OPENOFDM_TX_REG_INIT_DATA_STATE   // Data scrambler state (optional)
```

**OpenOFDM TX is largely self-contained** in FPGA, minimal driver tuning needed.

---

## Rate Adaptation

### Rate Control Algorithm

**Location**: Uses **Linux mac80211 Minstrel** rate control by default.

**Alternative**: Minstrel-HT for 802.11n (automatically selected if HT enabled)

### Forcing Fixed Rates

**Location**: `driver/sdr.c` (check `DRV_TX_REG_IDX_RATE*` registers)

**Via iw command:**
```bash
# Disable rate control, use fixed rate
iw dev wlan0 set bitrates legacy-5 6 9 12 18 24 36 48 54
iw dev wlan0 set bitrates legacy-2.4 1 2 5.5 11 6 9 12 18 24 36 48 54

# Force specific rate (11a)
iw dev wlan0 set bitrates legacy-5 54

# Force HT MCS
iw dev wlan0 set bitrates ht-mcs-5 7  # MCS 7 only
```

**Via sdrctl:**
```bash
# Check current rate settings
sdrctl dev wlan0 get reg drv_tx 0  # Legacy rate override
sdrctl dev wlan0 get reg drv_tx 1  # HT rate override

# Force rates (0 = auto, non-zero = force)
sdrctl dev wlan0 set reg drv_tx 0 11  # Force 54 Mbps (11a MCS 11)
sdrctl dev wlan0 set reg drv_tx 1 7   # Force HT MCS 7
```

**Rate index mapping**:
```c
// Location: driver/sdr.h wifi_rate_table[] (line 342)
// Index: 0-3 (unused), 4-11 (11a rates 6-54M), 12-19 (11n MCS0-7)
// 4:6M, 5:9M, 6:12M, 7:18M, 8:24M, 9:36M, 10:48M, 11:54M
// 12:6.5M(MCS0), ..., 19:65M(MCS7)
```

### Rate Statistics

**Monitor via sysfs:**
```bash
# Get real-time TX rate
cat /sys/devices/platform/sdr/tx_data_pkt_mcs_realtime
# Output: rate in Mbps (e.g., "54M")

# Get RX rate
cat /sys/devices/platform/sdr/rx_data_pkt_mcs_realtime
```

### Minstrel Tuning

**Minstrel parameters** (Linux kernel, not OpenWiFi-specific):

```bash
# Sampling interval (default 50ms)
echo 100 > /sys/kernel/debug/ieee80211/phy0/rc/minstrel_ht/update_interval

# Enable/disable HT rates
iw dev wlan0 set bitrates ht-mcs-5 0 1 2 3 4 5 6 7  # All MCS
```

**For OpenWiFi specifics:**
- Short GI support: Enabled via `test_mode` module parameter
- Rate fallback: Handled by mac80211 based on TX status reports

### Rate Adaptation for Specific Use Cases

#### Maximum Throughput
```bash
# Force highest rate, disable fallback
iw dev wlan0 set bitrates ht-mcs-5 7  # MCS 7 only (65 Mbps)
# Or legacy
iw dev wlan0 set bitrates legacy-5 54
```

#### Maximum Range
```bash
# Force lowest rate for better sensitivity
iw dev wlan0 set bitrates legacy-5 6  # 6 Mbps BPSK
```

#### Balanced
```bash
# Enable subset of rates
iw dev wlan0 set bitrates ht-mcs-5 0 1 2 3 4 5  # MCS 0-5
```

---

## Aggregation Tuning

### A-MPDU Configuration

**Enable/Disable at module load:**
```bash
insmod openwifi.ko test_mode=1  # Bit 0: Enable aggregation
insmod openwifi.ko test_mode=0  # Disable aggregation
```

**Location**: `driver/sdr.c` (lines 108-111)
```c
static int test_mode = 0;
static bool AGGR_ENABLE = false;  // Parsed from test_mode bit 0
```

### Aggregation Parameters

**Maximum A-MPDU length** (mac80211 reports to AP):

```c
// Location: driver/sdr.c:openwifi_dev_probe()
// In HT capabilities
dev->wiphy->bands[NL80211_BAND_5GHZ]->ht_cap.ampdu_factor = IEEE80211_HT_MAX_AMPDU_64K;
dev->wiphy->bands[NL80211_BAND_5GHZ]->ht_cap.ampdu_density = IEEE80211_HT_MPDU_DENSITY_8;
```

**Tuning:**
- **AMPDU_factor**: IEEE80211_HT_MAX_AMPDU_8K, 16K, 32K, **64K** (default)
- **AMPDU_density**: Time between MPDUs (0=no restriction, ..., 7=16us)

**Modify** (requires driver recompile):
```c
// Change to 32K max
dev->wiphy->bands[NL80211_BAND_5GHZ]->ht_cap.ampdu_factor =
    IEEE80211_HT_MAX_AMPDU_32K;
```

### MPDU Delimiter

**Location**: `driver/sdr.c:gen_mpdu_delim_crc()` (lines 868-888)

Each MPDU in an A-MPDU has a 4-byte delimiter:
```
[0-1]: Reserved + MPDU length (12 bits)
[2]:   Delimiter CRC (8 bits)
[3]:   Delimiter signature (0x4E)
```

**Padding** (line 1200+): Ensures 4-byte alignment.

**Tuning**: Normally not needed, but for debugging:
```c
// Add extra padding for testing
len_mpdu_delim_pad += 4;  // Extra 4 bytes between MPDUs
```

### Aggregation Control Registers

**FPGA registers**:
```c
// TX interface aggregation config
TX_INTF_REG_AMPDU_ACTION_CONFIG = ...;  // (not actively used in current code)

// XPU aggregation reference
XPU_REG_AMPDU_ACTION = ...;  // Tracks aggregation state
```

**Currently**: Aggregation is primarily software-controlled in driver, FPGA handles framing.

### Block Ack Window

**Location**: `driver/sdr.c:openwifi_tx_interrupt()` (lines 761-768)

```c
// Parse block ack bitmap (64-bit)
blk_ack_bitmap = (TX_INTF_REG_PKT_INFO3_read() |
                 ((u64)TX_INTF_REG_PKT_INFO4_read())<<32);

start_idx = (seq_no >= blk_ack_ssn) ?
            (seq_no - blk_ack_ssn) :
            (seq_no + ((~blk_ack_ssn + 1) & 0x0FFF));
tx_fail = (((blk_ack_bitmap >> start_idx) & 0x1) == 0);
```

**Block ack window size**: 64 (hardware-limited by 64-bit register)

**IEEE 802.11n standard**: Supports up to 64 MPDUs in flight.

**Performance impact:**
- Larger window: Better throughput in lossy channels
- Smaller window: Less buffering, lower latency
- **OpenWiFi fixed at 64**: Good balance

### Aggregation Throughput Optimization

**Best practices:**

1. **Enable aggregation**:
   ```bash
   insmod openwifi.ko test_mode=1
   ```

2. **Use HT rates** (aggregation only works with HT):
   ```bash
   iw dev wlan0 set bitrates ht-mcs-5 0 1 2 3 4 5 6 7
   ```

3. **Increase FIFO threshold** (see [TX Path](#tx-path-optimization)):
   ```c
   TX_INTF_REG_S_AXIS_FIFO_TH = 8192 - (210*5);  // More room
   ```

4. **Monitor aggregation statistics**:
   ```bash
   cat /sys/devices/platform/sdr/tx_data_pkt_need_ack_num_total
   # Compare aggregated vs. non-aggregated throughput
   ```

5. **Optimize Block Ack timeout** (if implementing):
   - Currently uses immediate Block Ack
   - Delayed Block Ack could reduce overhead in some scenarios

---

## Power Management

### RSSI-Based Power Saving

**Location**: `driver/sdr.c:openwifi_rf_rx_update_after_tuning()` (lines 230-253)

OpenWiFi uses RSSI thresholds for:
1. **Carrier sensing** (LBT)
2. **Packet detection**
3. **Link quality estimation**

**Tuning for power saving:**
- Higher thresholds = receiver ignores weak signals = less processing
- Trade-off: Reduced range

### AGC Power Consumption

**AD9361 AGC modes** (not directly controlled by driver, set in FPGA):
- **Slow AGC**: Lower power, slower adaptation
- **Fast AGC**: Higher power, faster adaptation

**OpenWiFi default**: Fast AGC for responsiveness.

**To optimize**: Modify AD9361 configuration in FPGA design.

### TX Power Control

**Location**: Already covered in [RF Frontend Optimization](#tx-attenuation)

**Dynamic TX power** (not currently implemented):
```c
// Pseudo-code for future enhancement
if (rssi_of_peer > threshold_high) {
  reduce_tx_power();  // Peer is close, save power
} else if (rssi_of_peer < threshold_low) {
  increase_tx_power();  // Peer is far, need more power
}
```

**Implementation**: Requires periodic peer RSSI monitoring and `ad9361_set_tx_atten()` calls.

### Sleep Modes

**IEEE 802.11 Power Save Mode**: Supported by mac80211, not OpenWiFi-specific.

**Enable power save**:
```bash
iw dev wlan0 set power_save on
```

**OpenWiFi considerations:**
- Driver does not implement custom PS logic
- Relies on mac80211 for beacon filtering, PS-Poll, etc.
- **FPGA remains always-on** (no low-power mode for FPGA itself)

### Clock Gating (Advanced)

**Potential optimization** (requires FPGA modification):
- Gate clocks to unused modules (e.g., TX path when only RX active)
- Reduce FPGA power consumption by 20-30%
- **Not currently implemented** in standard OpenWiFi FPGA design

**Example** (Verilog pseudo-code):
```verilog
// Gate TX clock when not transmitting
assign tx_clk_en = (tx_enable | tx_pkt_pending);
assign tx_clk_gated = tx_clk & tx_clk_en;
```

---

## Measurement and Profiling Tools

### Built-in Statistics (sysfs)

**Location**: `driver/sysfs_intf.c`

#### Enable Statistics Collection
```bash
echo 1 > /sys/devices/platform/sdr/stat_enable
```

#### TX Statistics
```bash
# Overall TX stats
cat /sys/devices/platform/sdr/tx_data_pkt_need_ack_num_total       # Total TX packets
cat /sys/devices/platform/sdr/tx_data_pkt_need_ack_num_total_fail  # Failed packets

# Retransmission distribution
cat /sys/devices/platform/sdr/tx_data_pkt_need_ack_num_retx
# Output: "n0 n1 n2 n3 n4 n5" (count of packets with 0, 1, ..., 5 retries)

cat /sys/devices/platform/sdr/tx_data_pkt_need_ack_num_retx_fail
# Failed packets by retry count

# Real-time rate
cat /sys/devices/platform/sdr/tx_data_pkt_mcs_realtime  # Current TX MCS

# Queue statistics
cat /sys/devices/platform/sdr/tx_prio_queue
# Format per queue (4 lines):
# tx_num intr_num stop0_fake stop0_real stop1 wakeup tx_q_num tx_q_intr ...
```

#### RX Statistics
```bash
# Overall RX stats
cat /sys/devices/platform/sdr/rx_data_pkt_num_total      # Total RX packets
cat /sys/devices/platform/sdr/rx_data_pkt_num_fail       # Failed FCS

# Real-time rate
cat /sys/devices/platform/sdr/rx_data_pkt_mcs_realtime

# AGC gain values (last packet)
cat /sys/devices/platform/sdr/rx_data_ok_agc_gain_value_realtime
cat /sys/devices/platform/sdr/rx_data_fail_agc_gain_value_realtime
```

#### Management Frame Statistics
```bash
cat /sys/devices/platform/sdr/tx_mgmt_pkt_need_ack_num_total
cat /sys/devices/platform/sdr/rx_mgmt_pkt_num_total
# Similar structure to data packet stats
```

#### Reset Statistics
```bash
echo 0 > /sys/devices/platform/sdr/tx_data_pkt_need_ack_num_total
echo 0 > /sys/devices/platform/sdr/tx_prio_queue  # Resets all queue stats
```

### Register Access (sdrctl)

**Location**: `user_space/sdrctl_src/`

**Installation**:
```bash
cd user_space/sdrctl_src
make
sudo make install
```

**Usage**:
```bash
# Read registers
sdrctl dev wlan0 get reg rx_intf 1      # RX interface register 1
sdrctl dev wlan0 get reg tx_intf 8      # TX config register
sdrctl dev wlan0 get reg xpu 19         # CSMA config
sdrctl dev wlan0 get reg openofdm_rx 2  # Power threshold

# Write registers
sdrctl dev wlan0 set reg openofdm_rx 2 130  # Set power threshold
sdrctl dev wlan0 set reg xpu 8 174          # Set LBT threshold

# Register categories
# - rf_rx, rf_tx: RF frontend
# - rx_intf, tx_intf: Interface modules
# - openofdm_rx, openofdm_tx: PHY modules
# - xpu: MAC controller
# - drv_rx, drv_tx, drv_xpu: Driver-level settings
```

**Register map**: Defined in `driver/sdrctl_intf.c`

### Packet Injection and Monitoring

**Location**: `user_space/inject_80211/`

**Purpose**: Inject custom 802.11 frames, monitor with radiotap headers.

**Build**:
```bash
cd user_space/inject_80211
make
```

**Usage**:
```bash
# Inject beacon frames
./inject_80211 wlan0 ../inject_80211/beacon_11a_ch44.txt r300

# Monitor mode (capture radiotap)
./inject_80211 wlan0 mon
```

**Supported features**:
- Custom frame injection (any 802.11 frame type)
- Rate control per packet (via radiotap)
- Radiotap header parsing (RX)

### Performance Benchmarking

#### Throughput Testing
```bash
# Server side (AP mode)
iperf3 -s

# Client side (STA mode)
iperf3 -c <AP_IP> -t 60 -i 1 -P 4  # 4 parallel streams, 60 seconds

# UDP throughput
iperf3 -c <AP_IP> -u -b 100M -t 60
```

**Expected results** (with optimal tuning):
- TCP throughput: 40-60 Mbps (single stream)
- UDP throughput: 60-80 Mbps
- With aggregation: 80-100 Mbps

#### Latency Testing
```bash
# Ping test
ping -c 100 -i 0.01 <peer_IP>

# Expected RTT:
# - Minimum: 1-2 ms
# - Average: 2-5 ms
# - With tuning: <1 ms achievable
```

#### Packet Error Rate
```bash
# Enable statistics
echo 1 > /sys/devices/platform/sdr/stat_enable

# Generate traffic
iperf3 -c <peer> -t 60

# Check error rate
total=$(cat /sys/devices/platform/sdr/tx_data_pkt_need_ack_num_total)
fail=$(cat /sys/devices/platform/sdr/tx_data_pkt_need_ack_num_total_fail)
echo "scale=4; $fail / $total * 100" | bc  # PER percentage
```

### Kernel Tracing

**ftrace** for detailed timing analysis:
```bash
# Enable function tracing
echo function > /sys/kernel/debug/tracing/current_tracer
echo openwifi_tx > /sys/kernel/debug/tracing/set_ftrace_filter
echo 1 > /sys/kernel/debug/tracing/tracing_on

# Generate traffic
ping <peer> -c 10

# View trace
cat /sys/kernel/debug/tracing/trace

# Disable
echo 0 > /sys/kernel/debug/tracing/tracing_on
```

### DMA Performance Monitoring

**Check DMA status**:
```bash
cat /proc/interrupts | grep dma
# Look for RX/TX DMA interrupt rates

dmesg | grep -i dma
# Check for DMA errors, buffer issues
```

### FPGA Utilization (Vivado)

**Generate reports** (if rebuilding FPGA):
```tcl
# In Vivado TCL console
report_utilization -file util.rpt
report_timing -file timing.rpt
report_power -file power.rpt
```

**Key metrics**:
- LUT utilization: <80% for good timing closure
- FF utilization: Typically 30-50%
- BRAM usage: Critical, limited resource
- DSP slices: Used by CORDIC, FFT

### Debugging Tools

**dmesg filtering**:
```bash
# RX/TX debug messages (if enabled in driver)
dmesg | grep "openwifi_rx:"
dmesg | grep "openwifi_tx:"

# Filter by log level
dmesg -l err,warn  # Errors and warnings only
```

**Network statistics** (Linux standard):
```bash
# Interface stats
ip -s link show wlan0

# Detailed wireless stats
cat /proc/net/wireless

# mac80211 debugging
echo 0x1 > /sys/kernel/debug/ieee80211/phy0/sdr/log_level
# (If implemented in driver)
```

---

## Quick Reference Tables

### Register Summary

| Register | Address | Default | Purpose | Tuning Range |
|----------|---------|---------|---------|--------------|
| TX_INTF_REG_BB_GAIN | 13*4 | 250 | TX baseband gain | 100-400 |
| TX_INTF_REG_S_AXIS_FIFO_TH | 11*4 | 7772/3676 | TX FIFO threshold | ±20% |
| TX_INTF_REG_TX_HOLD_THRESHOLD | 12*4 | 420 | TX start delay (200MHz) | 300-600 |
| RX_INTF_REG_BB_GAIN | 11*4 | 4 | RX baseband gain (bits) | 2-6 |
| RX_INTF_REG_S2MM_INTR_DELAY | 13*4 | 300 | RX interrupt delay (10MHz) | 100-1000 |
| RX_INTF_REG_TLAST_TIMEOUT | 12*4 | 7000 | RX packet timeout (10MHz) | 5000-10000 |
| OPENOFDM_RX_REG_POWER_THRES | 2*4 | 124 | RX power threshold | 100-150 |
| OPENOFDM_RX_REG_MIN_PLATEAU | 3*4 | 100 | RX plateau length | 80-150 |
| OPENOFDM_RX_REG_FFT_WIN_SHIFT | 5*4 | 4 | RX FFT window shift | 3-6 |
| XPU_REG_LBT_TH | 8*4 | 174 | Carrier sense threshold | 150-200 |
| XPU_REG_SEND_ACK_WAIT_TOP | 18*4 | 51 | SIFS duration (us) | 48-54 |
| XPU_REG_FORCE_IDLE_MISC | 6*4 | 75 | Post-RX idle (10MHz) | 50-150 |

### Performance Tuning Presets

#### Maximum Throughput
```bash
# Driver parameters
insmod openwifi.ko test_mode=1  # Enable aggregation

# Registers (via sdrctl)
sdrctl dev wlan0 set reg tx_intf 11 8192-420   # Lower FIFO threshold (accept more)
sdrctl dev wlan0 set reg tx_intf 13 290        # Higher BB gain (better EVM)
sdrctl dev wlan0 set reg rx_intf 13 500        # Higher RX interrupt delay (batch)

# Rate control
iw dev wlan0 set bitrates ht-mcs-5 7           # Force MCS 7
```

#### Maximum Range/Sensitivity
```bash
# Driver parameters
insmod openwifi.ko init_tx_att=0  # Maximum TX power

# Registers
sdrctl dev wlan0 set reg openofdm_rx 2 100     # Lower power threshold
sdrctl dev wlan0 set reg drv_rx 0 95           # -95 dBm RX threshold
sdrctl dev wlan0 set reg xpu 8 180             # Lower LBT threshold

# Rate control
iw dev wlan0 set bitrates legacy-5 6           # Lowest rate (6 Mbps)
```

#### Minimum Latency
```bash
# Registers
sdrctl dev wlan0 set reg tx_intf 12 300        # Lower TX hold threshold
sdrctl dev wlan0 set reg rx_intf 13 100        # Lower RX interrupt delay (10us)
sdrctl dev wlan0 set reg xpu 5 2               # Lower DIFS advance

# Disable aggregation
insmod openwifi.ko test_mode=0

# Fixed rate (less variability)
iw dev wlan0 set bitrates ht-mcs-5 4
```

#### Robust/Reliable
```bash
# Registers
sdrctl dev wlan0 set reg xpu 18 52             # Longer SIFS (tolerance)
sdrctl dev wlan0 set reg xpu 6 100             # Longer force idle
sdrctl dev wlan0 set reg openofdm_rx 3 120     # Higher min plateau

# Retries
iw dev wlan0 set retry short 7 long 7

# Conservative rates
iw dev wlan0 set bitrates ht-mcs-5 0 1 2 3 4
```

### Common Issues and Solutions

| Issue | Symptom | Likely Cause | Solution |
|-------|---------|--------------|----------|
| Low throughput | <20 Mbps TCP | FIFO threshold too high | Decrease TX_INTF_REG_S_AXIS_FIFO_TH |
| Frequent queue stops | Many stop/wake cycles | Ring buffer too small | Increase NUM_TX_BD or RING_ROOM_THRESHOLD |
| High packet loss | >10% PER | LBT threshold too low | Increase XPU_REG_LBT_TH |
| RX sensitivity poor | Miss packets at -80dBm | Power threshold too high | Decrease OPENOFDM_RX_REG_POWER_THRES |
| TX power too high | Interfering with others | TX attenuation too low | Increase init_tx_att |
| High latency | >10ms RTT | Interrupt coalescing | Decrease RX_INTF_REG_S2MM_INTR_DELAY_COUNT |
| EVM poor | <-30dB | BB gain too high | Decrease TX_INTF_REG_BB_GAIN |
| Timing errors | ACK timeouts | SIFS misconfigured | Calibrate XPU_REG_SEND_ACK_WAIT_TOP |
| FIFO overflow | dmesg errors | DMA too slow | Check DMA burst size, memory bandwidth |
| False alarms | High RX fail count | Power threshold too low | Increase OPENOFDM_RX_REG_POWER_THRES |

---

## Appendix: Code Locations Reference

### Key Driver Files

```
driver/sdr.c                      # Main driver, TX/RX interrupt handlers
driver/sdr.h                      # Data structures, constants
driver/hw_def.h                   # Hardware register definitions
driver/tx_intf/tx_intf.c          # TX interface control
driver/rx_intf/rx_intf.c          # RX interface control
driver/openofdm_rx/openofdm_rx.c  # RX PHY configuration
driver/openofdm_tx/openofdm_tx.c  # TX PHY configuration
driver/xpu/xpu.c                  # MAC controller (XPU) configuration
driver/xilinx_dma/xilinx_dma.c    # DMA engine driver
driver/sysfs_intf.c               # Sysfs statistics interface
driver/sdrctl_intf.c              # Register access interface
```

### Critical Function Reference

```c
// TX path
openwifi_tx()                     # sdr.c:975
openwifi_tx_interrupt()           # sdr.c:661
tx_intf_api->hw_init()            # tx_intf.c:231

// RX path
openwifi_rx_interrupt()           # sdr.c:464
rx_intf_api->hw_init()            # rx_intf.c:171

// PHY configuration
openofdm_rx_api->hw_init()        # openofdm_rx.c:74
openofdm_tx_api->hw_init()        # openofdm_tx.c:74

// MAC configuration
xpu_api->hw_init()                # xpu.c:277

// RF control
ad9361_rf_set_channel()           # sdr.c:261
ad9361_tx_calibration()           # sdr.c:209
openwifi_rf_rx_update_after_tuning()  # sdr.c:230

// DMA setup
rx_dma_setup()                    # sdr.c:427
```

### Register Access Functions

```c
// TX interface
TX_INTF_REG_BB_GAIN_write()
TX_INTF_REG_S_AXIS_FIFO_TH_write()
TX_INTF_REG_QUEUE_FIFO_DATA_COUNT_read()

// RX interface
RX_INTF_REG_BB_GAIN_write()
RX_INTF_REG_S2MM_INTR_DELAY_COUNT_write()
RX_INTF_REG_TLAST_TIMEOUT_TOP_write()

// OpenOFDM RX
OPENOFDM_RX_REG_POWER_THRES_write()
OPENOFDM_RX_REG_MIN_PLATEAU_write()
OPENOFDM_RX_REG_FFT_WIN_SHIFT_write()

// XPU
XPU_REG_LBT_TH_write()
XPU_REG_SEND_ACK_WAIT_TOP_write()
XPU_REG_CSMA_CFG_write()
XPU_REG_SLICE_COUNT_*_write()
```

---

## Conclusion

This guide provides comprehensive tuning information for OpenWiFi performance optimization. The parameters should be adjusted based on:

- **Application requirements**: Throughput vs. latency vs. range
- **Environment**: Indoor vs. outdoor, interference levels
- **Hardware platform**: FPGA size, AD9361 vs. RFSoC, etc.
- **Regulatory constraints**: TX power, channel usage

**Always test thoroughly after changes**, as improper tuning can lead to:
- Reduced performance
- Increased error rates
- Regulatory violations
- Hardware damage (excessive TX power)

For questions and support, refer to:
- [OpenWiFi GitHub Issues](https://github.com/open-sdr/openwifi/issues)
- [OpenWiFi Documentation](https://github.com/open-sdr/openwifi/tree/master/doc)

**Document Version**: 1.0 (2025)
**Last Updated**: Based on OpenWiFi commit with ARCHITECTURE.md
