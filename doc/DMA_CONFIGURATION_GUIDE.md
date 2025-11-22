# OpenWiFi DMA Configuration and AXI Streaming Interfaces Analysis

## Executive Summary

OpenWiFi uses Xilinx AXI DMA IP core with two independent channels:
- **TX DMA (MM2S)**: Scatter-Gather mode for packet transmission (PS → PL)
- **RX DMA (S2MM)**: Cyclic buffer mode for packet reception (PL → PS)
- **Data Width**: 64-bit AXI-Stream (8 bytes per transfer)
- **Clock**: 150 MHz AXI-Lite control clock, DMA operates at ~40 MHz for IQ samples

---

## 1. DMA ARCHITECTURE

### Overview

```
┌────────────────────────────────────────────────────────┐
│           Processing System (ARM Cortex-A9)            │
│  • Linux Kernel DMA Driver (dmaengine subsystem)       │
│  • DMA buffer management (coherent memory)             │
│  • Interrupt handlers (IRQ 30: RX, IRQ 29: TX)         │
└──────────┬──────────────────────────────┬──────────────┘
           │                              │
      AXI-Lite                       AXI-Lite
      Control Bus                    Control Bus
           │                              │
   ┌───────▼──────────────┐      ┌────────▼──────────────┐
   │   TX DMA (MM2S)      │      │   RX DMA (S2MM)       │
   │  (0x80400000-0x8040FF)│      │ (0x80410000-0x8041FF) │
   │  Scatter-Gather      │      │  Cyclic Mode          │
   │  • Control Reg 0x00  │      │  • Control Reg 0x30   │
   │  • Status Reg 0x04   │      │  • Status Reg 0x34    │
   │  • Descriptor 0x08   │      │  • Buffer Addr 0x48   │
   └───────┬──────────────┘      └────────┬──────────────┘
           │                              │
      MM2S AXI-Stream              S2MM AXI-Stream
      64-bit, 40 Msps             64-bit, 40 Msps
           │                              │
┌──────────▼─────────────────────────────▼──────────────┐
│                  FPGA (Programmable Logic)             │
│                                                       │
│  ┌────────────────────────────────────────────────┐  │
│  │              tx_intf Module                    │  │
│  │  • AXI-Lite slave (register control)           │  │
│  │  • S_AXIS (Slave - from DMA)                   │  │
│  │  • M_AXIS (Master - to OFDM TX)                │  │
│  │  • Metadata insertion                          │  │
│  └────────────────────────────────────────────────┘  │
│                                                       │
│  ┌────────────────────────────────────────────────┐  │
│  │              rx_intf Module                    │  │
│  │  • AXI-Lite slave (register control)           │  │
│  │  • S_AXIS (Slave - from OFDM RX)               │  │
│  │  • M_AXIS (Master - to DMA)                    │  │
│  │  • Metadata extraction (TSF, RSSI, rate)       │  │
│  └────────────────────────────────────────────────┘  │
│                                                       │
└────────────────────────────────────────────────────────┘
```

### Key Metrics

| Parameter | Value | Notes |
|-----------|-------|-------|
| TX DMA Clock | ~40 MHz | From FPGA clock |
| RX DMA Clock | ~40 MHz | From FPGA clock |
| AXI-Lite Control Clock | 150 MHz | PS clock |
| Data Width | 64-bit | 8 bytes per transfer |
| DMA Symbols | 8 (default) | 64 bytes per transfer |
| TX Descriptors | 64 (XILINX_DMA_NUM_DESCS) | Scatter-gather chain |
| RX Buffers | 16-64 | Cyclic mode (configurable) |
| Max TX Packet | 8192 bytes | DMA symbol FIFO |
| Max RX Packet | 2048 bytes | Per buffer descriptor |

---

## 2. TX DMA CONFIGURATION (Scatter-Gather Mode)

### Hardware Descriptor Format

**File**: `/driver/xilinx_dma/xilinx_dma.c:218-238`

```c
struct xilinx_axidma_desc_hw {
    u32 next_desc;          // @0x00: Next descriptor pointer (32-bit)
    u32 next_desc_msb;      // @0x04: Next descriptor pointer MSB (64-bit support)
    u32 buf_addr;           // @0x08: Buffer address (32-bit)
    u32 buf_addr_msb;       // @0x0C: Buffer address MSB (64-bit support)
    u32 mcdma_control;      // @0x10: Multi-channel control
    u32 vsize_stride;       // @0x14: Vertical size and stride
    u32 control;            // @0x18: Control field (length + flags)
    u32 status;             // @0x1C: Status field (read-only)
    u32 app[5];             // @0x20-0x30: Application-specific fields
} __aligned(64);            // 64-byte aligned for AXI burst
```

### TX Control Register Fields

**File**: `/driver/xilinx_dma/xilinx_dma.c:59-127`

```
XILINX_DMA_REG_DMACR (0x0000) - DMA Control Register
  Bit [31:24]: DELAY_CNT (interrupt coalescing delay)
  Bit [23:16]: FRAME_COUNT (interrupt after N frames)
  Bit [14]:    ERR_IRQ (error interrupt enable)
  Bit [13]:    DLY_CNT_IRQ (delay count interrupt enable)
  Bit [12]:    FRM_CNT_IRQ (frame count interrupt enable)
  Bit [11:8]:  MASTER_SHIFT (AXI master width selection)
  Bit [6:5]:   FSYNCSRC (frame sync source)
  Bit [4]:     FRAMECNT_EN (frame count enable)
  Bit [3]:     GENLOCK_EN (genlock enable)
  Bit [2]:     RESET (reset bit)
  Bit [1]:     CIRC_EN (cyclic mode - only for S2MM)
  Bit [0]:     RUNSTOP (run/stop)

XILINX_DMA_REG_DMASR (0x0004) - DMA Status Register
  Bit [15]:    EOL_LATE_ERR
  Bit [14]:    ERR_IRQ
  Bit [13]:    DLY_CNT_IRQ
  Bit [12]:    FRM_CNT_IRQ
  Bit [11]:    SOF_LATE_ERR
  Bit [10]:    SG_DEC_ERR (descriptor decode error)
  Bit [9]:     SG_SLV_ERR (descriptor slave error)
  Bit [8]:     EOF_EARLY_ERR
  Bit [7]:     SOF_EARLY_ERR
  Bit [6]:     DMA_DEC_ERR (DMA decode error)
  Bit [5]:     DMA_SLAVE_ERR
  Bit [4]:     DMA_INT_ERR
  Bit [1]:     IDLE
  Bit [0]:     HALTED

Key Registers for Scatter-Gather:
  0x08 (CURDESC):  Current descriptor address (read-only)
  0x10 (TAILDESC): Tail descriptor address (write to add new descriptors)
  0x28 (BTT):      Bytes To Transfer (for direct mode only)
```

### TX DMA Operation Flow

**File**: `/driver/sdr.c:1270-1450` and `/driver/xilinx_dma/xilinx_dma.c:1876-1975`

```
1. Packet from mac80211
   ↓
2. openwifi_tx() function
   - Get next TX ring buffer descriptor
   - Store packet metadata: prio, length, sequence number
   - DMA map packet buffer to physical address
   ↓
3. dma_prep_slave_sg() preparation
   - Allocate XILINX_DMA_NUM_DESCS (max 255) for packet
   - Each descriptor chains to next via next_desc pointer
   - Set control field: 
     * Bits [31:0]: Transfer length in bytes
     * Bit [26]: EOP (End of Packet)
     * Bit [27]: SOP (Start of Packet)
   ↓
4. dmaengine_submit()
   - Add descriptor to pending list
   - Return DMA cookie for tracking
   ↓
5. dma_async_issue_pending()
   - Move descriptor from pending to active list
   - Write tail descriptor pointer to XILINX_DMA_REG_TAILDESC
   - DMA hardware fetches and executes
   ↓
6. Interrupt on completion (if DLY_CNT_IRQ enabled)
   - Move descriptor to done_list
   - Invoke callback (packet transmitted)
```

### TX Descriptor Chain Example

For a 1500-byte packet with DMA_BD_EOP, DMA_BD_SOP flags:

```
Descriptor[0]:
  next_desc:     &Descriptor[1]
  buf_addr:      0x12345000 (first 1472 bytes)
  control:       1472 | DMA_BD_SOP (Start of Packet)
  
Descriptor[1]:
  next_desc:     NULL or &Descriptor[2]
  buf_addr:      0x12345600
  control:       28 | DMA_BD_EOP (End of Packet)
```

### TX DMA Software Setup

**File**: `/driver/sdr.c:427-450` and `/driver/sdr.h:32-44`

```c
struct openwifi_buffer_descriptor {
    u8 prio;
    u16 len_mpdu;
    u16 seq_no;
    struct sk_buff *skb_linked;
    dma_addr_t dma_mapping_addr;
};

struct openwifi_ring {
    struct openwifi_buffer_descriptor *bds;  // Ring of 64 descriptors
    u32 bd_wr_idx;  // Write index
    u32 bd_rd_idx;  // Read index
};

// TX DMA Configuration
#define NUM_TX_BD 64           // 64 descriptors (1<<6)
#define TX_BD_BUF_SIZE 8192    // Max packet size
```

### Scatter-Gather DMA Registers (TX)

| Register | Address | Purpose |
|----------|---------|---------|
| DMACR | 0x00 | Control: RUNSTOP, RESET, interrupts |
| DMASR | 0x04 | Status: errors, idle, halted |
| CURDESC | 0x08 | Current descriptor pointer (read-only) |
| TAILDESC | 0x10 | Tail descriptor pointer (write new) |
| BTT | 0x28 | Bytes to transfer (not used in SG mode) |

---

## 3. RX DMA CONFIGURATION (Cyclic Buffer Mode)

### RX Cyclic Ring Buffer

**File**: `/driver/sdr.h:137-144` and `/driver/sdr.c:427-445`

```c
#define NUM_RX_BD 64           // 64 or 16 buffers (USE_NEW_RX_INTERRUPT)
#define RX_BD_BUF_SIZE 2048    // 2KB per buffer

// Total cyclic buffer: 64 * 2048 = 128KB (or 16 * 2048 = 32KB)

// RX Cyclic DMA setup
priv->rx_cyclic_buf = dma_zalloc_coherent(
    sizeof(u8) * RX_BD_BUF_SIZE * NUM_RX_BD,
    &priv->rx_cyclic_buf_dma_mapping_addr
);

// Prepare cyclic DMA descriptor
priv->rxd = rx_dev->device_prep_dma_cyclic(
    priv->rx_chan,
    priv->rx_cyclic_buf_dma_mapping_addr,
    RX_BD_BUF_SIZE * NUM_RX_BD,  // Total buffer length (128KB)
    RX_BD_BUF_SIZE,               // Period (2KB per interrupt)
    DMA_DEV_TO_MEM,
    DMA_CTRL_ACK | DMA_PREP_INTERRUPT
);
```

### Cyclic Descriptor Chain Structure

For 64 buffers of 2048 bytes each, the DMA creates a circular linked list:

```
┌─────────────────────────────────────┐
│  RX Cyclic Buffer (128 KB Total)    │
├─────────────────────────────────────┤
│ Buffer[0] (0x00000-0x07FF) 2KB      │
│ ├─ Descriptor: next_desc = &Desc[1] │
│ │  buf_addr = 0x12340000            │
│ │  control = 2048 | EOP             │
├─────────────────────────────────────┤
│ Buffer[1] (0x08000-0x0FFF) 2KB      │
│ ├─ Descriptor: next_desc = &Desc[2] │
│ │  buf_addr = 0x12340800            │
│ │  control = 2048 | EOP             │
├─────────────────────────────────────┤
│ ...                                 │
├─────────────────────────────────────┤
│ Buffer[63] (0x1F800-0x1FFFF) 2KB    │
│ ├─ Descriptor: next_desc = &Desc[0] │ ◄── Circular\!
│ │  buf_addr = 0x1233F800            │
│ │  control = 2048 | EOP             │
└─────────────────────────────────────┘
```

### RX DMA Operation Flow

**File**: `/driver/xilinx_dma/xilinx_dma.c:1975-2090`

```
1. DMA Initialization
   - Allocate 128KB coherent buffer
   - Create cyclic descriptor chain
   - Enable CIRC_EN flag in DMACR
   ↓
2. DMA Start
   - Write descriptor address to XILINX_DMA_REG_CURDESC
   - Write same address to XILINX_DMA_REG_TAILDESC
   - Set RUNSTOP = 1
   ↓
3. Continuous Reception
   - DMA waits for AXI-Stream M_AXIS from rx_intf
   - Receives IQ samples via TDATA, TVALID, TREADY handshake
   - When packet complete (TLAST from rx_intf):
     * DMA writes to current buffer
     * Advances to next descriptor in chain
   ↓
4. Interrupt Generation
   - Every period_len (2KB) completion:
     * Sets FRM_CNT_IRQ flag
     * Generates IRQ 30
   - Can be delayed by S2MM_INTR_DELAY_COUNT
   ↓
5. Buffer Index Tracking
   - driver tracks: buf_idx (increments per IRQ)
   - Used for cyclic callback: residue = buf_idx * 2048
```

### RX Cyclic Mode Configuration

**File**: `/driver/xilinx_dma/xilinx_dma.c:168,1597-1620`

```c
#define XILINX_DMA_CR_CYCLIC_BD_EN_MASK BIT(4)

// In xilinx_dma_start_transfer():
if (chan->cyclic) {
    reg |= XILINX_DMA_CR_CYCLIC_BD_EN_MASK;  // Enable cyclic mode
    dma_ctrl_write(chan, XILINX_DMA_REG_DMACR, reg);
}

// Cyclic DMA callback
chan->buf_idx++;  // Increments every 2KB reception
if (callback) {
    callback(callback_param);  // Invoke periodic callback
}
```

### RX DMA Interrupt Delay

**File**: `/driver/rx_intf/rx_intf.c:295`

```c
RX_INTF_REG_S2MM_INTR_DELAY_COUNT = 30 * 10  // 30us delay
// Clock: 10 MHz = 100ns per count
// 300 counts = 30 microseconds

// Tuning:
// - Default 300 (30us): Balanced latency vs. overhead
// - Decrease (100): 10us latency, higher interrupt rate
// - Increase (500): 50us latency, fewer interrupts
```

### RX Buffer Configuration Summary

| Parameter | Default | Large FPGA | Small FPGA |
|-----------|---------|-----------|-----------|
| NUM_RX_BD | 64 | 64 | 16 |
| RX_BD_BUF_SIZE | 2048 | 2048 | 2048 |
| Total Memory | 128 KB | 128 KB | 32 KB |
| IRQ Period | 2 KB | 2 KB | 2 KB |
| Interrupt Delay | 30 us | 30 us | 30 us |

---

## 4. AXI STREAM INTERFACES

### Data Path Architecture

```
TX Path:
  PS DMA → MM2S → tx_intf (S_AXIS) → xpu → openofdm_tx → AD9361
         64-bit        64-bit        64-bit

RX Path:
  AD9361 → rx_intf (S_AXIS) → openofdm_rx → xpu → rx_intf (M_AXIS) → S2MM DMA → PS
             64-bit              64-bit       64-bit        64-bit
```

### AXI-Stream Signal Interface

**Standard AXI4-Stream Signals (64-bit data width)**:

```verilog
// Write-side (from source)
output [63:0]  TDATA          // 64-bit data bus
output         TVALID         // Data is valid
input          TREADY         // Destination ready
output         TLAST          // Last beat of packet
output [7:0]   TKEEP          // Byte enables (all 1s = 8 bytes valid)

// Handshaking Protocol
// TRANSFER occurs when: TVALID && TREADY
// In cyclic DMA: TLAST triggers buffer switch + interrupt
```

### tx_intf AXI-Stream Slave (S_AXIS)

**File**: `/driver/hw_def.h:35-133`

```c
// TX FIFO Configuration
#define TX_INTF_NUM_BYTE_PER_DMA_SYMBOL (64/8)  // 8 bytes
#define TX_INTF_NUM_BYTE_PER_DMA_SYMBOL_IN_BITS 3  // log2(8)

// Register: TX_INTF_REG_S_AXIS_FIFO_TH (0x2C)
// Purpose: Flow control threshold
// Default: 8192 - (210*2) = 7772 symbols (61KB)
// Large FPGA: 8192 max symbols in FIFO
// Small FPGA: 4096 max symbols in FIFO

// Register: TX_INTF_REG_TX_HOLD_THRESHOLD (0x30)
// Purpose: Hold TX transmission when FIFO below threshold
// Default: 420 symbols (3360 bytes)

// Flow Control:
// - When FIFO level < S_AXIS_FIFO_TH:
//   DMA can continue writing
// - When FIFO level >= threshold:
//   Set signal "no_room_from_tx_intf" → DMA TREADY = 0
// - Backpressure flows to PS
```

### rx_intf AXI-Stream Master (M_AXIS)

**File**: `/driver/hw_def.h:135-210` and `/driver/rx_intf/rx_intf.c:171-334`

```c
// Register: RX_INTF_REG_START_TRANS_TO_PS_MODE (0x14)
// Bit [2:0]: Transfer trigger source
//   0: fcs_valid_from_acc (FCS valid from openofdm_rx)
//   1: sig_valid_from_acc (Signal detected)
//   2: sig_invalid_from_acc
//   3: S_AXIS TLAST trigger
//   4: S_AXIS TREADY trigger
//   5: Automatic (based on signal field parsing)
//   6: Monitor DMA start trigger
//   7: External trigger

// Bit [5]: num_dma_symbol_to_ps source
//   0 = from register
//   1 = automatic (recommended)

// Register: RX_INTF_REG_NUM_DMA_SYMBOL_TO_PS (0x24)
// Purpose: Number of 64-bit symbols to transfer per packet
// Default: 8 (64 bytes header/metadata per packet)

// Metadata Prepended to RX Packets:
// [0-7]:   TSF Timestamp (64-bit)
// [8-9]:   RSSI (half-dB units) + AGC status
// [10-11]: AGC status + packet exist flag
// [12-13]: Packet length
// [14-15]: Rate index + HT flags
// [16+]:   802.11 frame data (FCS already verified)

// Register: RX_INTF_REG_TLAST_TIMEOUT_TOP (0x30)
// Purpose: Timeout for incomplete packets
// Default: 7000 (700us at 10MHz clock)
// If TLAST not seen for 700us → force end of transfer

// Register: RX_INTF_REG_S2MM_INTR_DELAY_COUNT (0x34)
// Purpose: Interrupt coalescing delay
// Default: 300 (30us delay at 10MHz)
```

### Handshaking Protocol

**Valid Transfer Sequence**:

```
Cycle:    0       1       2       3       4
TVALID:   ───╮───╮───╮───╮───╮
             │   │   │   │   │
TREADY:   ───╮───╮───╮───╮───╮
             │   │   │   │   │
TDATA:    [AA] [BB] [CC] [DD] [EE]
             │   │   │   │   │
           Transfer on every cycle (TVALID && TREADY)

With backpressure:
Cycle:    0       1   2       3
TVALID:   ───╮───╮───────╮───╮
             │   │       │   │
TREADY:   ───╮───────────╮───╮
             │   0   0   │   │
TDATA:    [AA] [BB] [BB] [CC] [DD]
             │   │   │   │   │
           Transfer   Stall   Transfer
```

### AXI Stream Data Width

```
Single AXI-Stream Beat (64-bit):

┌───────────────────────────────────────┐
│    AXI-Stream Data (1 beat)           │
├───────────────────────────────────────┤
│ Byte 0 | Byte 1 | ... | Byte 7       │  TDATA[63:0]
│ ⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻⁻ TKEEP[7:0] (all 1s)
│         1 clock cycle                │  Clock
└───────────────────────────────────────┘

Throughput:
- 64 bits per clock
- 40 MHz = 40 * 64 Mbps = 2.56 Gbps
- Sufficient for 20 MHz IQ samples (2 x 20 = 40 Msps @ 32 bits = 1.28 Gbps)
```

---

## 5. BUFFER MANAGEMENT

### Ring Buffer Structure

**File**: `/driver/sdr.h:46-53` and `/driver/sdr.c:346`

```c
struct openwifi_ring {
    struct openwifi_buffer_descriptor *bds;
    u32 bd_wr_idx;  // Write index (kernel writes next packet here)
    u32 bd_rd_idx;  // Read index (IRQ processes from here)
    int stop_flag;  // -1: normal, >=0: queue X is full
};

// Allocation
priv->tx_ring = kmalloc(
    sizeof(struct openwifi_buffer_descriptor) * NUM_TX_BD,
    GFP_KERNEL
);

// Ring operations
#define RING_ROOM_THRESHOLD (2 + MAX_NUM_SW_QUEUE)  // = 6
#define NUM_TX_BD 64

// Room check before adding packet
ring_room = (ring->bd_rd_idx + NUM_TX_BD - ring->bd_wr_idx) % NUM_TX_BD;
if (ring_room < RING_ROOM_THRESHOLD) {
    set_stop_flag(queue_idx);  // Stop this queue
}
```

### TX Ring Buffer Flow

```
Linux mac80211              DMA Engine              TX Interrupt Handler
     │                           │                          │
     ├─ openwifi_tx()            │                          │
     │  ├─ Get bd_wr_idx         │                          │
     │  ├─ Fill descriptor       │                          │
     │  │  ├─ prio               │                          │
     │  │  ├─ len_mpdu           │                          │
     │  │  ├─ seq_no             │                          │
     │  │  ├─ skb_linked         │                          │
     │  │  └─ dma_mapping_addr   │                          │
     │  ├─ dma_prep_slave_sg()───┼──────────────────┐       │
     │  ├─ dmaengine_submit()─────┼──────────────────┼───┐   │
     │  │                         │                  │   │   │
     │  └─ dma_async_issue_pending() ─────┐         │   │   │
     │                           │         │         │   │   │
     │                           ├─ Write TAILDESC  │   │   │
     │                           ├─ DMA reads desc  │   │   │
     │                           ├─ Fetch from buf  │   │   │
     │                           ├─ Send via AXI-S  │   │   │
     │                           ├─ Complete desc───┼───┼──→├─ IRQ handler
     │                           │                  │   │   │  ├─ bd_rd_idx++
     │                           │                  │   │   │  ├─ Free skb
     │                           │                  │   │   │  ├─ Update stats
     │                           │                  │   │   │  └─ Wake queue
     │                           │                  │   │   │
     └─ Update bd_wr_idx─────────┼──────────────────┼───┴───┘
        (circular: % NUM_TX_BD)  │                  │
```

### RX Cyclic Buffer Flow

```
DMA Receive                   RX Interrupt Handler              openwifi_rx()
     │                               │                              │
     ├─ Receive IQ samples           │                              │
     │  via AXI-Stream (S_AXIS)       │                              │
     │  from rx_intf                 │                              │
     │                               │                              │
     ├─ TLAST from rx_intf           │                              │
     │  (packet complete)            │                              │
     │                               │                              │
     ├─ Write to rx_cyclic_buf[idx]  │                              │
     ├─ Move to next buffer          │                              │
     ├─ buf_idx++                    │                              │
     │                               │                              │
     ├─ Interrupt after 2KB──────────┼──────────────────┐            │
     │  (FRM_CNT_IRQ)                │                 │            │
     │                               ├─ For each desc │            │
     │                               │  in [0..buf_idx]│            │
     │                               │  ├─ Parse metadata           │
     │                               │  ├─ TSF, RSSI, rate, length  │
     │                               │  ├─ Validate FCS             │
     │                               │  ├─ Allocate skb             │
     │                               │  ├─ Copy to skb              │
     │                               │  └─ ieee80211_rx_irqsafe()───┼───┐
     │                               │  │  └─ Queue for processing  │   │
     │                               │  └─ Clear pkt_exist flag     │   │
     │                               │                             │   │
     │                               └─ Return (buf_idx reset)     │   │
     │                                                             │   │
     │                                                 mac80211    │   │
     │                                                 subsystem   │   │
     │                                                    │        │   │
     └────────────────────────────────────────────────────┼────────┘   │
                                                          │            │
                                                    Network stack      │
                                                    Application        │
```

### Descriptor Chain for Scatter-Gather

**File**: `/driver/xilinx_dma/xilinx_dma.c:1950-1975`

```c
// For each scatterlist entry
for_each_sg(sgl, sg, sg_len, i) {
    // Break large transfers into chunks
    while (sg_used < sg_dma_len(sg)) {
        // Get free segment from pre-allocated pool
        segment = xilinx_axidma_alloc_tx_segment(chan);
        
        // Calculate transfer size
        copy = min_t(size_t,
                     sg_dma_len(sg) - sg_used,
                     chan->xdev->max_buffer_len);
        
        hw = &segment->hw;
        hw->buf_addr = sg_dma_address(sg) + sg_used;
        hw->control = copy;  // Byte count
        
        if (i == 0 && sg_used == 0)
            hw->control |= XILINX_DMA_BD_SOP;  // Start
        if (i == sg_len - 1 && sg_used + copy >= sg_dma_len(sg))
            hw->control |= XILINX_DMA_BD_EOP;  // End
        
        sg_used += copy;
    }
}

// Chain setup
for each descriptor in chain:
    descriptor[n].next_desc = physical_address(&descriptor[n+1])
descriptor[last].next_desc = NULL or &descriptor[next_chain]
```

---

## 6. PERFORMANCE CHARACTERISTICS

### Throughput Analysis

| Path | Bandwidth | Samples/sec | Notes |
|------|-----------|------------|-------|
| TX DMA (MM2S) | 2.56 Gbps | 40 M @ 64-bit | Sufficient for OFDM TX |
| RX DMA (S2MM) | 2.56 Gbps | 40 M @ 64-bit | From rx_intf metadata |
| TX Peak | ~600 Mbps | Max throughput achieved | 20 MHz bandwidth |
| RX Peak | ~600 Mbps | Max throughput achieved | 20 MHz bandwidth |

### Latency Characteristics

**File**: `/doc/ARCHITECTURE.md:398-402`

```
RX Path Latency:
  ├─ OFDM demodulation (FPGA): 20-50 μs
  ├─ DMA transfer: 2-5 μs  (2048 bytes @ 2.56 Gbps)
  ├─ Interrupt latency: 10-30 μs
  └─ Total: 32-85 μs

TX Path Latency:
  ├─ DMA fetch: 1-3 μs (8192 bytes FIFO pre-fetch)
  ├─ tx_intf processing: 5-10 μs
  ├─ OFDM encoding: 20-50 μs
  └─ Total: 26-63 μs
```

### Buffer Occupancy and Flow Control

**File**: `/driver/tx_intf/tx_intf.c:246-250`

```c
// TX FIFO thresholds (tuned for stability)
if (fpga_type == LARGE_FPGA) {
    TX_INTF_REG_S_AXIS_FIFO_TH = 8192 - (210*2);  // 7772
    // Stops when FIFO >= 7772 symbols (61.4 KB)
} else {
    TX_INTF_REG_S_AXIS_FIFO_TH = 4096 - (210*2);  // 3676
    // Stops when FIFO >= 3676 symbols (29.4 KB)
}

// Room calculation
u32 fifo_room = (S_AXIS_FIFO_TH - current_level);
if (fifo_room < 1500 bytes) {
    // Pause new TX submissions
    queue_stop();
}
```

### Interrupt Coalescing (RX)

```c
// Default: 30us delay between interrupts
S2MM_INTR_DELAY_COUNT = 300 counts @ 10MHz = 30 microseconds

// Tuning impact:
100us:  Lower latency (10 interrupts/ms), higher CPU load
300us:  Balanced (3 interrupts/ms), default
500us:  Lower CPU (2 interrupts/ms), higher latency
```

---

## 7. DMA REGISTER SETTINGS & CONFIGURATION

### TX DMA (MM2S) Register Map

```
Address  Register         Access  Purpose
─────────────────────────────────────────────────────────────
0x00     DMACR           R/W     Control: RUNSTOP, RESET, IRQ enables
0x04     DMASR           R       Status: errors, idle, halted
0x08     CURDESC         R       Current descriptor pointer
0x10     TAILDESC        W       Tail descriptor pointer (issue new)
0x28     BTT             W       Bytes to transfer (not used in SG)

Key Control Bits:
  [0]:   RUNSTOP         1 = running, 0 = stopped
  [2]:   RESET           1 = reset (auto-clear)
  [12]:  FRM_CNT_IRQ     Frame count interrupt enable
  [13]:  DLY_CNT_IRQ     Delay count interrupt enable
  [14]:  ERR_IRQ         Error interrupt enable
```

### RX DMA (S2MM) Register Map

```
Address  Register         Access  Purpose
─────────────────────────────────────────────────────────────
0x30     DMACR           R/W     Control: RUNSTOP, RESET, CIRC_EN
0x34     DMASR           R       Status: errors, idle, halted
0x38     CURDESC         R       Current descriptor pointer
0x40     TAILDESC        W       Tail descriptor pointer
0x48     BUFFER_ADDR     W       Current buffer address (direct mode)

Key Control Bits:
  [0]:   RUNSTOP         1 = running, 0 = stopped
  [1]:   CIRC_EN         1 = cyclic mode (must be set for RX)
  [2]:   RESET           1 = reset (auto-clear)
  [12]:  FRM_CNT_IRQ     Frame count interrupt enable
  [13]:  DLY_CNT_IRQ     Delay count interrupt enable
  [14]:  ERR_IRQ         Error interrupt enable
```

### TX Interface Registers

**File**: `/driver/hw_def.h:35-133`

```
tx_intf Base Address: 0x83c00000 (64KB region)

Register                                Address  Default   Purpose
────────────────────────────────────────────────────────────────────
TX_INTF_REG_MULTI_RST                  0x00     0x00000000  Reset control
TX_INTF_REG_ARBITRARY_IQ                0x04                Arbitrary IQ
TX_INTF_REG_WIFI_TX_MODE                0x08     0x00000028  TX mode
TX_INTF_REG_CTS_TOSELF_CONFIG           0x10                CTS-to-self
TX_INTF_REG_CSI_FUZZER                  0x14     0x00000000  CSI fuzzer
TX_INTF_REG_CTS_TOSELF_WAIT_SIFS_TOP    0x18     0x00A000A0  SIFS timing
TX_INTF_REG_ARBITRARY_IQ_CTL            0x1C                IQ control
TX_INTF_REG_TX_CONFIG                   0x20                TX config
TX_INTF_REG_NUM_DMA_SYMBOL_TO_PS        0x24     8           Symbols/trans
TX_INTF_REG_CFG_DATA_TO_ANT             0x28     0x00000000  Antenna config
TX_INTF_REG_S_AXIS_FIFO_TH              0x2C     7772/3676   FIFO threshold
TX_INTF_REG_TX_HOLD_THRESHOLD           0x30     420         Hold threshold
TX_INTF_REG_BB_GAIN                     0x34     250         Baseband gain
TX_INTF_REG_INTERRUPT_SEL               0x38     0x00030004  IRQ source
TX_INTF_REG_AMPDU_ACTION_CONFIG         0x3C                A-MPDU config
TX_INTF_REG_ANT_SEL                     0x40                Antenna select
TX_INTF_REG_PHY_HDR_CONFIG              0x44                PHY header
TX_INTF_REG_S_AXIS_FIFO_NO_ROOM         0x54                FIFO status
TX_INTF_REG_PKT_INFO[1-4]               0x58-0x64             Packet info
TX_INTF_REG_QUEUE_FIFO_DATA_COUNT       0x68                Queue count
```

### RX Interface Registers

**File**: `/driver/hw_def.h:135-209`

```
rx_intf Base Address: 0x83c20000 (64KB region)

Register                                Address  Default      Purpose
─────────────────────────────────────────────────────────────────────────
RX_INTF_REG_MULTI_RST                  0x00     0x00000000   Reset control
RX_INTF_REG_MIXER_CFG                  0x04     0x300200F4   Mixer (legacy)
RX_INTF_REG_INTERRUPT_TEST              0x08     0x00000100   Interrupt test
RX_INTF_REG_IQ_SRC_SEL                 0x0C                  IQ source select
RX_INTF_REG_IQ_CTRL                     0x10     0x00000000   IQ control
RX_INTF_REG_START_TRANS_TO_PS_MODE     0x14     0x00010025   Transfer mode
RX_INTF_REG_START_TRANS_TO_PS          0x18     (1700<<16)   Trigger + max len
RX_INTF_REG_START_TRANS_TO_PS_SRC_SEL  0x1C     0x00000000   Source select
RX_INTF_REG_NUM_DMA_SYMBOL_TO_PL       0x20     8            Symbols to PL
RX_INTF_REG_NUM_DMA_SYMBOL_TO_PS       0x24     8            Symbols to PS
RX_INTF_REG_CFG_DATA_TO_ANT            0x28     0x00000100   Antenna config
RX_INTF_REG_BB_GAIN                     0x2C     4            Baseband gain
RX_INTF_REG_TLAST_TIMEOUT_TOP          0x30     7000         TLAST timeout
RX_INTF_REG_S2MM_INTR_DELAY_COUNT      0x34     300          Interrupt delay
RX_INTF_REG_ANT_SEL                     0x40                 Antenna select
```

---

## 8. SOFTWARE DRIVER DMA CODE REFERENCES

### Key Files and Functions

| File | Function | Purpose |
|------|----------|---------|
| `/driver/sdr.c` | `openwifi_tx()` | TX packet submission |
| `/driver/sdr.c` | `openwifi_tx_interrupt()` | TX completion handler |
| `/driver/sdr.c` | `openwifi_rx_interrupt()` | RX packet processing |
| `/driver/sdr.c` | `rx_dma_setup()` | Initialize RX cyclic DMA |
| `/driver/sdr.h` | `openwifi_ring` | TX ring buffer struct |
| `/driver/xilinx_dma/xilinx_dma.c` | `xilinx_dma_prep_slave_sg()` | TX SG preparation |
| `/driver/xilinx_dma/xilinx_dma.c` | `xilinx_dma_prep_dma_cyclic()` | RX cyclic prep |
| `/driver/xilinx_dma/xilinx_dma.c` | `xilinx_dma_start_transfer()` | DMA start |
| `/driver/tx_intf/tx_intf.c` | `hw_init()` | TX interface init |
| `/driver/rx_intf/rx_intf.c` | `hw_init()` | RX interface init |

### TX DMA Submission Code

**File**: `/driver/sdr.c:1270-1450`

```c
static int openwifi_tx(struct ieee80211_hw *dev, struct ieee80211_tx_control *control,
                       struct sk_buff *skb)
{
    // 1. Get next TX ring position
    u32 bd_wr_idx = ring->bd_wr_idx;
    struct openwifi_buffer_descriptor *bd = &ring->bds[bd_wr_idx];
    
    // 2. Calculate DMA symbols needed
    u32 num_dma_symbol = (len_psdu >> TX_INTF_NUM_BYTE_PER_DMA_SYMBOL_IN_BITS) +
                         ((len_psdu & (TX_INTF_NUM_BYTE_PER_DMA_SYMBOL - 1)) \!= 0);
    
    // 3. DMA map packet
    bd->dma_mapping_addr = dma_map_single(NULL, skb->data, skb->len, DMA_TO_DEVICE);
    
    // 4. Prepare scatter-gather DMA descriptors
    struct sg_table sgtab;
    sg_alloc_table(&sgtab, 1, GFP_ATOMIC);
    sg_set_buf(sgtab.sgl, skb->data, skb->len);
    dma_map_sg(NULL, sgtab.sgl, 1, DMA_TO_DEVICE);
    
    // 5. Submit DMA transfer
    txd = priv->tx_chan->device->device_prep_slave_sg(
        priv->tx_chan,
        sgtab.sgl,
        sgtab.nents,
        DMA_MEM_TO_DEV,
        DMA_CTRL_ACK | DMA_PREP_INTERRUPT
    );
    
    // 6. Get DMA cookie for tracking
    priv->tx_cookie = dmaengine_submit(txd);
    
    // 7. Issue pending to hardware
    dma_async_issue_pending(priv->tx_chan);
    
    // 8. Update write pointer
    ring->bd_wr_idx = (bd_wr_idx + 1) % NUM_TX_BD;
}
```

### RX Cyclic DMA Setup

**File**: `/driver/sdr.c:427-445`

```c
static int rx_dma_setup(struct ieee80211_hw *dev)
{
    // Allocate cyclic buffer (128KB for 64 x 2KB buffers)
    priv->rx_cyclic_buf = dma_zalloc_coherent(
        sizeof(u8) * RX_BD_BUF_SIZE * NUM_RX_BD,
        &priv->rx_cyclic_buf_dma_mapping_addr,
        GFP_KERNEL
    );
    
    // Prepare cyclic DMA descriptor chain
    // DMA will continuously write to this buffer in a circular fashion
    priv->rxd = rx_dev->device_prep_dma_cyclic(
        priv->rx_chan,
        priv->rx_cyclic_buf_dma_mapping_addr,
        RX_BD_BUF_SIZE * NUM_RX_BD,  // Total length (128KB)
        RX_BD_BUF_SIZE,               // Period (2KB per interrupt)
        DMA_DEV_TO_MEM,
        DMA_CTRL_ACK | DMA_PREP_INTERRUPT
    );
    
    // Submit descriptor
    priv->rx_cookie = dmaengine_submit(priv->rxd);
    dma_async_issue_pending(priv->rx_chan);
}
```

### RX Interrupt Handler

**File**: `/driver/sdr.c:464-659`

```c
static irqreturn_t openwifi_rx_interrupt(int irq, void *dev_id)
{
    // Process received packets from cyclic buffer
    for (i = 0; i < NUM_RX_BD; i++) {
        u8 *rxbuf = priv->rx_cyclic_buf + (i * RX_BD_BUF_SIZE);
        
        // Parse metadata from rx_intf
        u64 tsf = *(u64*)(rxbuf + 0);      // TSF timestamp
        u16 rssi = *(u16*)(rxbuf + 8);     // RSSI
        u16 len = *(u16*)(rxbuf + 12);     // Packet length
        u8 rate = *(u8*)(rxbuf + 14);      // Rate index
        
        // Validate packet
        if (\!check_fcs(rxbuf + 16, len - 4)) {
            continue;
        }
        
        // Allocate and fill sk_buff
        struct sk_buff *skb = dev_alloc_skb(len);
        skb_put_data(skb, rxbuf + 16, len - 4);
        
        // Fill RX status
        ieee80211_rx_status *status = IEEE80211_SKB_RXCB(skb);
        status->mactime = tsf;
        status->signal = rssi_to_dbm(rssi);
        status->rate_idx = rate;
        
        // Pass to mac80211
        ieee80211_rx_irqsafe(priv->hw, skb);
    }
}
```

---

## 9. COMPLETE DMA FILE STRUCTURE

```
/home/user/openwifi/driver/
├── sdr.c                          # Main driver (2760 lines)
│   ├── openwifi_tx()              # TX packet submission
│   ├── openwifi_tx_interrupt()    # TX completion
│   ├── openwifi_rx_interrupt()    # RX processing
│   └── rx_dma_setup()             # RX DMA init
│
├── sdr.h                          # Data structures (18KB)
│   ├── openwifi_buffer_descriptor # TX ring entry
│   ├── openwifi_ring              # TX ring buffer
│   ├── NUM_TX_BD (64)
│   ├── NUM_RX_BD (16-64)
│   ├── RX_BD_BUF_SIZE (2048)
│   └── TX_BD_BUF_SIZE (8192)
│
├── hw_def.h                       # FPGA registers (18KB)
│   ├── TX interface registers
│   ├── RX interface registers
│   ├── XPU (MAC) registers
│   └── DMA symbol configuration
│
├── xilinx_dma/
│   └── xilinx_dma.c               # AXI DMA driver (34KB)
│       ├── xilinx_axidma_desc_hw  # Descriptor struct
│       ├── xilinx_dma_prep_slave_sg()      # TX SG prep
│       ├── xilinx_dma_prep_dma_cyclic()    # RX cyclic prep
│       ├── xilinx_dma_chan_handle_cyclic() # RX callback
│       └── xilinx_dma_start_transfer()     # Start DMA
│
├── tx_intf/
│   └── tx_intf.c                  # TX interface driver
│       ├── TX_INTF_REG_* registers
│       ├── FIFO flow control
│       └── hw_init()
│
└── rx_intf/
    └── rx_intf.c                  # RX interface driver
        ├── RX_INTF_REG_* registers
        ├── Metadata configuration
        ├── TLAST timeout
        └── hw_init()
```

---

## 10. CRITICAL PERFORMANCE INSIGHTS

### DMA Throughput Bottlenecks

1. **TX Path**:
   - DMA FIFO threshold: 8192 symbols (large FPGA) or 4096 (small)
   - Once full, backpressure stops new submissions
   - OFDM TX encoding: 20-50 us per packet
   - Throughput limited by RF: ~600 Mbps @ 20 MHz

2. **RX Path**:
   - Cyclic buffer: 128 KB total (64 x 2 KB buffers)
   - Interrupt every 2 KB completion
   - IRQ delay: 30 us (300 counts @ 10 MHz)
   - Processing latency: ~32-85 us total

3. **Flow Control**:
   - TX backpressure when FIFO >= threshold
   - RX always receives (drops old data if overrun)
   - No explicit RX flow control to device

### Memory Requirements

```
TX Ring:        64 descriptors x metadata = ~2 KB
RX Cyclic:      128 KB (64 x 2 KB buffers)
TX SG Descs:    255 max x 64 bytes = ~16 KB
RX SG Descs:    1 cyclic x 64 bytes = 64 bytes
────────────────────────────────────────────
Total:          ~148 KB coherent DMA memory
```

---

## References

- Xilinx AXI DMA IP Core documentation
- OpenWiFi GitHub repository
- Linux dmaengine subsystem
- IEEE 802.11a/g/n standard

