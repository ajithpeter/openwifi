# OpenWiFi System Architecture Guide

**Comprehensive Architecture Documentation**
**Version:** 1.5.0+
**Last Updated:** 2025-11-21
**Maintained by:** OpenWiFi Community

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Architecture Layers](#architecture-layers)
3. [Repository Structure](#repository-structure)
4. [Component Diagram](#component-diagram)
5. [Data Flow Diagrams](#data-flow-diagrams)
6. [Module Interactions](#module-interactions)
7. [Hardware/Software Boundaries](#hardwaresoftware-boundaries)
8. [Key Design Decisions](#key-design-decisions)
9. [Performance Characteristics](#performance-characteristics)
10. [References](#references)

---

## System Overview

OpenWiFi is a **complete open-source IEEE 802.11a/g/n WiFi implementation** using Software Defined Radio (SDR) technology. It consists of:

- **FPGA-based PHY layer** (Physical Layer DSP)
- **Linux kernel drivers** (MAC layer and control)
- **User-space tools** (Configuration and monitoring)
- **AD9361 RF frontend** (70 MHz - 6 GHz transceiver)

### Key Features

- Full IEEE 802.11a/g/n compliance
- Linux mac80211 subsystem integration
- Real-time Channel State Information (CSI) capture
- Packet injection and monitoring capabilities
- Time-Sensitive Networking (TSN) support
- Network slicing with microsecond-level time control
- Support for 13+ hardware platforms

---

## Architecture Layers

### Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    LAYER 3: USER SPACE                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   hostapd    │  │     sdrctl   │  │  inject_80211│          │
│  │ wpa_supplicant│  │  side_ch_ctl │  │Python tools  │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                  │                   │
│         └─────────────────┼──────────────────┘                   │
│                          │                                       │
│                   nl80211/cfg80211/netlink                       │
└─────────────────────────┼───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                  LAYER 2: LINUX KERNEL                          │
│  ┌───────────────────────────────────────────────────┐          │
│  │          mac80211 SoftMAC Subsystem               │          │
│  │    (Management, Authentication, Association)      │          │
│  └─────────────────────┬─────────────────────────────┘          │
│                        │ ieee80211_ops                           │
│  ┌─────────────────────▼─────────────────────────────┐          │
│  │          openwifi Driver (sdr.c)                  │          │
│  │  ┌──────────────────────────────────────────┐     │          │
│  │  │ TX/RX Packet Processing                  │     │          │
│  │  │ Ring Buffer Management                   │     │          │
│  │  │ Interrupt Handlers                       │     │          │
│  │  │ RF Control (AD9361)                      │     │          │
│  │  └──────────────────────────────────────────┘     │          │
│  └─────────┬──────┬──────┬──────┬──────┬─────────────┘          │
│            │      │      │      │      │                         │
│  ┌─────────▼──┐ ┌─▼────┐┌─▼──┐┌─▼───┐┌─▼────┐┌────────┐        │
│  │  tx_intf   │ │rx_intf││xpu ││o_tx ││o_rx  ││side_ch │        │
│  │  Driver    │ │Driver ││Drv ││Drv  ││Driver││Driver  │        │
│  └─────┬──────┘ └──┬────┘└──┬─┘└──┬──┘└───┬──┘└───┬────┘        │
│        │           │        │     │       │       │              │
│        └───────────┴────────┴─────┴───────┴───────┘              │
│                          │                                        │
│                  AXI-Lite (MMIO) + DMA                           │
└──────────────────────────┼────────────────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────────────┐
│              LAYER 1: FPGA (Programmable Logic)                │
│  ╔══════════════════════════════════════════════════════════╗  │
│  ║  ┌────────────┐  ┌────────────┐  ┌────────────┐         ║  │
│  ║  │  tx_intf   │  │  rx_intf   │  │    xpu     │         ║  │
│  ║  │   Module   │  │   Module   │  │ (Low MAC)  │         ║  │
│  ║  │ (AXI-Lite) │  │ (AXI-Lite) │  │ CSMA/CA    │         ║  │
│  ║  └─────┬──────┘  └──────┬─────┘  │ TSF Timer  │         ║  │
│  ║        │                │        └──────┬─────┘         ║  │
│  ║  ┌─────▼─────┐    ┌─────▼─────┐  ┌─────▼─────┐         ║  │
│  ║  │openofdm_tx│    │openofdm_rx│  │  side_ch  │         ║  │
│  ║  │  OFDM TX  │    │  OFDM RX  │  │ CSI/IQ    │         ║  │
│  ║  │ - Scramble│    │ - Sync    │  │ Monitor   │         ║  │
│  ║  │ - Encode  │    │ - FFT     │  └───────────┘         ║  │
│  ║  │ - IFFT    │    │ - Viterbi │                        ║  │
│  ║  │ - Pilots  │    │ - Demod   │                        ║  │
│  ║  └─────┬─────┘    └─────┬─────┘                        ║  │
│  ║        │                │                               ║  │
│  ║        │    AXI-Stream (IQ Samples @ 40 Msps)          ║  │
│  ║        └────────────────┴───────────────────────────┐  ║  │
│  ╚═════════════════════════════════════════════════════│══╝  │
└────────────────────────────────────────────────────────│─────┘
                                                         │
┌────────────────────────────────────────────────────────▼─────┐
│              LAYER 0: RF FRONTEND (AD9361)                    │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  AD9361 Wideband RF Agile Transceiver                  │  │
│  │  - Frequency: 70 MHz - 6 GHz                           │  │
│  │  - Sample Rate: 40 Msps                                │  │
│  │  - 12-bit ADC/DAC                                      │  │
│  │  - Automatic Gain Control (AGC)                        │  │
│  │  - SPI control from FPGA                               │  │
│  └────────────────────┬───────────────────────────────────┘  │
└───────────────────────┼──────────────────────────────────────┘
                        │
                   ┌────▼────┐
                   │ Antenna │
                   └─────────┘
```

---

## Repository Structure

### Directory Organization

```
/home/user/openwifi/
│
├── README.md                    # Main project documentation
├── LICENSE                      # AGPL-3.0-or-later
├── CONTRIBUTING.md              # Contribution guidelines
├── openwifi-arch.jpg            # Architecture diagram
│
├── driver/                      # Linux kernel drivers (117KB sdr.c)
│   ├── sdr.c                    # Main driver (2760 lines)
│   ├── sdr.h                    # Data structures
│   ├── hw_def.h                 # FPGA register definitions
│   ├── sysfs_intf.c             # Sysfs interface
│   ├── sdrctl_intf.c            # User control interface
│   ├── Makefile                 # Top-level build
│   ├── make_all.sh              # Build script
│   │
│   ├── tx_intf/                 # TX interface driver
│   ├── rx_intf/                 # RX interface driver
│   ├── xpu/                     # MAC controller driver
│   ├── openofdm_tx/             # OFDM TX driver
│   ├── openofdm_rx/             # OFDM RX driver
│   ├── side_ch/                 # Side channel driver
│   └── xilinx_dma/              # DMA engine driver
│
├── kernel_boot/                 # Boot files and configs
│   ├── kernel_config            # 32-bit kernel config
│   ├── kernel_config_zynqmp     # 64-bit kernel config
│   ├── build_boot_bin.sh        # BOOT.BIN generation
│   ├── boards/                  # Board-specific configs
│   │   ├── zc706_fmcs2/
│   │   ├── adrv9364z7020/
│   │   ├── antsdr/
│   │   └── ... (13 boards total)
│   └── patches/                 # Kernel patches
│
├── user_space/                  # User space tools (64 scripts)
│   ├── wgd.sh                   # Driver loader
│   ├── fosdem.sh                # AP mode launcher
│   ├── monitor_ch.sh            # Monitor mode
│   ├── sdrctl_src/              # Control utility
│   ├── inject_80211/            # Packet injection
│   ├── side_ch_ctl_src/         # CSI capture (Python)
│   ├── fast_reg_log/            # Register logging
│   ├── arbitrary_iq_gen/        # IQ generation
│   └── webserver/               # Web interface
│
├── doc/                         # Documentation (939KB)
│   ├── README.md                # Technical architecture
│   ├── publications.md          # 100+ research papers
│   ├── videos.md                # Video tutorials
│   ├── app_notes/               # 21 application notes
│   │   ├── csi.md
│   │   ├── iq.md
│   │   ├── inject_80211.md
│   │   └── ...
│   └── known_issue/             # Troubleshooting
│
├── adi-linux/                   # Analog Devices kernel (32-bit)
└── adi-linux-64/                # Analog Devices kernel (64-bit)
```

### Key Files Reference

| Component | Location | Purpose |
|-----------|----------|---------|
| Main Driver | `/driver/sdr.c` | ieee80211_ops implementation |
| Register Defs | `/driver/hw_def.h` | FPGA register map |
| TX Interface | `/driver/tx_intf/tx_intf.c` | TX DMA and control |
| RX Interface | `/driver/rx_intf/rx_intf.c` | RX DMA and control |
| MAC Controller | `/driver/xpu/xpu.c` | CSMA/CA engine |
| Control Tool | `/user_space/sdrctl_src/sdrctl.c` | Register access |
| CSI Capture | `/user_space/side_ch_ctl_src/` | Python tools |

---

## Component Diagram

### FPGA Module Interconnections

```
┌───────────────────────────────────────────────────────────────────┐
│                         FPGA (Zynq PL)                            │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    AXI Interconnect                          │ │
│  │      (ARM CPU ↔ FPGA Modules via AXI-Lite)                  │ │
│  └──┬────┬────┬────┬────┬────┬──────────────────────────────┬──┘ │
│     │    │    │    │    │    │                              │    │
│  0x83c0 │ 0x83c2│ 0x83c3│ 0x83c4│                           │    │
│     │  0x83c1 │ 0x83c3 │    │                               │    │
│  ┌──▼─────┐ ┌─▼────┐ ┌─▼────┐ ┌──▼─────┐ ┌──▼─────┐ ┌──────▼──┐ │
│  │tx_intf │ │rx_intf│ │o_tx  │ │o_rx    │ │  xpu   │ │ side_ch │ │
│  │        │ │       │ │      │ │        │ │        │ │         │ │
│  │Reg:64KB│ │Reg:   │ │Reg:  │ │Reg:    │ │Reg:    │ │Reg:     │ │
│  │        │ │64KB   │ │64KB  │ │64KB    │ │64KB    │ │64KB     │ │
│  └───┬────┘ └───┬───┘ └───┬──┘ └───┬────┘ └────┬───┘ └────┬────┘ │
│      │          │         │        │           │          │      │
│      │  AXI-Stream 64-bit Data Path (IQ Samples @ 20 MHz) │      │
│      │          │         │        │           │          │      │
│  ┌───▼──────────▼─────────▼────────▼───────────▼──────────▼────┐ │
│  │                                                              │ │
│  │  TX Path:                  RX Path:                         │ │
│  │  PS→DMA→tx_intf→xpu→o_tx   o_rx→xpu→rx_intf→DMA→PS        │ │
│  │           ↓                  ↑                              │ │
│  │        TX FIFO             RX Sync                          │ │
│  │        (4 queues)          Detection                        │ │
│  │                                                              │ │
│  └───┬────────────────────────────────────┬────────────────────┘ │
│      │                                    │                      │
│  ┌───▼────────────────────────────────────▼────────────────────┐ │
│  │            Xilinx DMA (AXI DMA Engine)                      │ │
│  │  - TX: Scatter-Gather (MM2S)                                │ │
│  │  - RX: Cyclic Buffer (S2MM)                                 │ │
│  │  - Interrupt generation on completion                       │ │
│  └───┬────────────────────────────────────┬────────────────────┘ │
│      │                                    │                      │
└──────┼────────────────────────────────────┼──────────────────────┘
       │                                    │
  ┌────▼────────────────────────────────────▼────┐
  │     Processing System (ARM CPU)              │
  │     - Linux kernel drivers                   │
  │     - DMA buffer management                  │
  │     - Interrupt handling                     │
  └──────────────────────────────────────────────┘
```

### Register Address Map

| Module | Base Address | Size | Purpose |
|--------|-------------|------|---------|
| tx_intf | 0x83c00000 | 64KB | TX interface control |
| tx_intf (openofdm_tx) | 0x83c10000 | 64KB | OFDM transmitter |
| rx_intf | 0x83c20000 | 64KB | RX interface control |
| openofdm_rx | 0x83c30000 | 64KB | OFDM receiver |
| xpu | 0x83c40000 | 64KB | MAC controller |
| side_ch | 0x83c50000 | 64KB | Side channel |
| TX DMA | 0x80400000 | 64KB | TX DMA engine |
| RX DMA | 0x80410000 | 64KB | RX DMA engine |

---

## Data Flow Diagrams

### Receive (RX) Data Path

```
Antenna
   │
   ▼
┌──────────────────────────────────────────────────────────┐
│ AD9361 RF Frontend                                       │
│ • RX LO tuning                                           │
│ • AGC (Automatic Gain Control)                           │
│ • ADC: 12-bit @ 40 Msps                                  │
│ • I/Q samples output                                     │
└──────────────┬───────────────────────────────────────────┘
               │ LVDS Interface (40 Msps IQ)
               ▼
┌──────────────────────────────────────────────────────────┐
│ FPGA: rx_intf Module                                     │
│ • Antenna selection (ANT0/ANT1)                          │
│ • Digital gain (BB_GAIN = 4, left shift 4 bits)          │
│ • Decimation: 40 Msps → 20 Msps                          │
└──────────────┬───────────────────────────────────────────┘
               │ AXI-Stream (20 Msps IQ, 64-bit)
               ▼
┌──────────────────────────────────────────────────────────┐
│ FPGA: openofdm_rx Module                                 │
│ ┌────────────────────────────────────────────────────┐   │
│ │ 1. Sync Short Detection                            │   │
│ │    - Power threshold (default: 124)                │   │
│ │    - Plateau detection (min: 100)                  │   │
│ │    - Phase offset tracking                         │   │
│ │                                                     │   │
│ │ 2. Sync Long (Channel Estimation)                  │   │
│ │    - FFT window positioning (shift: 4)             │   │
│ │    - Long training symbols                         │   │
│ │                                                     │   │
│ │ 3. SIGNAL Field Decode                             │   │
│ │    - Rate, length extraction                       │   │
│ │    - Parity check                                  │   │
│ │                                                     │   │
│ │ 4. Data Demodulation                               │   │
│ │    - 64-point FFT                                  │   │
│ │    - Equalization (single-tap, per subcarrier)     │   │
│ │    - QAM demapping (BPSK/QPSK/16-QAM/64-QAM)       │   │
│ │                                                     │   │
│ │ 5. Viterbi Decoding                                │   │
│ │    - Constraint length K=7                         │   │
│ │    - Code rates: 1/2, 2/3, 3/4, 5/6                │   │
│ │    - Soft/hard decision                            │   │
│ │                                                     │   │
│ │ 6. Descrambling & CRC                              │   │
│ │    - LFSR descrambler                              │   │
│ │    - CRC-32 validation                             │   │
│ └────────────────────────────────────────────────────┘   │
└──────────────┬───────────────────────────────────────────┘
               │ Valid 802.11 Packet
               ▼
┌──────────────────────────────────────────────────────────┐
│ FPGA: rx_intf DMA Preparation                            │
│ • Prepend metadata:                                      │
│   [0-7]:   TSF timestamp (64-bit)                        │
│   [8-9]:   RSSI (half-dB units)                          │
│   [10-11]: AGC status + packet exist flag                │
│   [12-13]: Packet length                                 │
│   [14-15]: Rate index + HT flags                         │
│   [16+]:   802.11 frame data                             │
│ • DMA transfer to cyclic buffer                          │
└──────────────┬───────────────────────────────────────────┘
               │ DMA (S2MM - Stream to Memory Mapped)
               ▼
┌──────────────────────────────────────────────────────────┐
│ ARM CPU: RX Cyclic Buffer                                │
│ • 16 or 64 buffer descriptors                            │
│ • Each buffer: 2048 bytes                                │
│ • Total: 32KB or 128KB                                   │
└──────────────┬───────────────────────────────────────────┘
               │ RX Interrupt (IRQ 30)
               ▼
┌──────────────────────────────────────────────────────────┐
│ Kernel: openwifi_rx_interrupt()                          │
│ File: /driver/sdr.c (lines 464-659)                      │
│                                                           │
│ for each packet in buffer:                               │
│   1. Check packet_exist flag                             │
│   2. Parse metadata (TSF, RSSI, rate, length)            │
│   3. Validate: length, rate index, FCS                   │
│   4. Convert RSSI: half_dB → dBm (with correction)       │
│   5. Allocate sk_buff                                    │
│   6. Fill ieee80211_rx_status:                           │
│      - band, freq, signal, rate_idx                      │
│      - flag: RX_FLAG_MACTIME_START, etc.                 │
│   7. Copy packet data to skb                             │
│   8. ieee80211_rx_irqsafe(hw, skb)                       │
│   9. Update statistics                                   │
│  10. Clear packet_exist flag                             │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────┐
│ mac80211 Subsystem                                       │
│ • Frame type dispatch (data/mgmt/ctl)                    │
│ • Decryption (if enabled)                                │
│ • Defragmentation                                        │
│ • Duplicate detection                                    │
│ • A-MPDU reordering                                      │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────┐
│ Network Stack                                            │
│ • IP layer processing                                    │
│ • TCP/UDP handling                                       │
│ • Socket delivery                                        │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
         Application
```

**Typical RX Latency Breakdown:**
- OFDM demodulation (FPGA): 20-50 μs
- DMA transfer: 2-5 μs
- Interrupt latency: 1-10 μs
- Kernel processing: 10-50 μs
- **Total: ~35-115 μs**

### Transmit (TX) Data Path

```
Application
   │
   ▼
┌──────────────────────────────────────────────────────────┐
│ Network Stack                                            │
│ • TCP/UDP → IP → 802.3 frame                             │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────┐
│ mac80211 Subsystem                                       │
│ • Encryption (if configured)                             │
│ • Fragmentation                                          │
│ • A-MPDU aggregation                                     │
│ • Rate control                                           │
│ • QoS queue mapping                                      │
│ • 802.11 header generation                               │
└──────────────┬───────────────────────────────────────────┘
               │ ieee80211_ops->tx
               ▼
┌──────────────────────────────────────────────────────────┐
│ Kernel: openwifi_tx()                                    │
│ File: /driver/sdr.c (lines 975-1481)                     │
│                                                           │
│ 1. Parse TX info from mac80211                           │
│    - Rate: legacy (6-54 Mbps) or HT-MCS (0-7)            │
│    - GI: long (800ns) or short (400ns)                   │
│    - Retry limit, RTS/CTS                                │
│                                                           │
│ 2. Calculate PHY parameters                              │
│    - Duration field (for NAV)                            │
│    - PLCP header (rate, length)                          │
│                                                           │
│ 3. Handle A-MPDU aggregation                             │
│    - Add 4-byte MPDU delimiter                           │
│    - Calculate delimiter CRC                             │
│    - Pad to 4-byte boundary                              │
│                                                           │
│ 4. Select TX queue (0-3) based on priority               │
│                                                           │
│ 5. Ring buffer management                                │
│    - Check space: bd_wr_idx vs bd_rd_idx                 │
│    - If full: stop queue, return TX_BUSY                 │
│                                                           │
│ 6. Configure FPGA registers                              │
│    - PHY_HDR_CONFIG: rate, MCS, length, GI               │
│    - TX_CONFIG: retry, CTS, RTS, ACK policy              │
│    - ANT_SEL: antenna selection, CDD                     │
│    - CTS_TOSELF_CONFIG: protection                       │
│                                                           │
│ 7. DMA mapping                                           │
│    - dma_map_single(skb->data, len, DMA_TO_DEVICE)       │
│    - Store in buffer descriptor                          │
│                                                           │
│ 8. Trigger DMA                                           │
│    - Scatter-gather descriptor setup                     │
│    - dma_async_issue_pending()                           │
└──────────────┬───────────────────────────────────────────┘
               │ DMA (MM2S - Memory Mapped to Stream)
               ▼
┌──────────────────────────────────────────────────────────┐
│ FPGA: tx_intf Module (4 Priority Queues)                 │
│                                                           │
│  Queue 0 (Voice)     ┌──────┐                            │
│  ──────────────────> │ FIFO │ ──┐                        │
│                      └──────┘   │                        │
│  Queue 1 (Video)     ┌──────┐   │                        │
│  ──────────────────> │ FIFO │ ──┤                        │
│                      └──────┘   │  Arbiter               │
│  Queue 2 (BE)        ┌──────┐   │    │                   │
│  ──────────────────> │ FIFO │ ──┤    ▼                   │
│                      └──────┘   │  To XPU                │
│  Queue 3 (BK)        ┌──────┐   │                        │
│  ──────────────────> │ FIFO │ ──┘                        │
│                      └──────┘                             │
│                                                           │
│ • FIFO depth: 4096 (small) or 8192 (large) symbols       │
│ • Backpressure: S_AXIS_FIFO_NO_ROOM signal               │
│ • BB_GAIN: 250 (optimized for EVM)                       │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────┐
│ FPGA: xpu Module (MAC Controller)                        │
│                                                           │
│ CSMA/CA State Machine:                                   │
│                                                           │
│  IDLE ──> CCA Check ──> DIFS Wait ──> Backoff ──> TX     │
│                │                                    │     │
│                │ Busy                               │     │
│                └────────────────────────────────────┘     │
│                                                           │
│ • Listen Before Talk (LBT) threshold: -62 dBm            │
│ • DIFS: 34 μs (OFDM)                                     │
│ • Slot time: 9 μs (5 GHz) or 20 μs (2.4 GHz)            │
│ • Contention window: CW_min to CW_max                    │
│ • Random backoff: uniform(0, CW-1)                       │
│ • Retry management: exponential backoff                  │
│                                                           │
│ After TX:                                                │
│ • SIFS wait (16 μs)                                      │
│ • ACK timeout monitoring                                 │
│ • Result: ACK received or timeout                        │
└──────────────┬───────────────────────────────────────────┘
               │ Transmit trigger
               ▼
┌──────────────────────────────────────────────────────────┐
│ FPGA: openofdm_tx Module                                 │
│ ┌────────────────────────────────────────────────────┐   │
│ │ 1. Scrambler                                       │   │
│ │    - Pseudo-random sequence (initial: 0x7F)        │   │
│ │                                                     │   │
│ │ 2. Convolutional Encoder                           │   │
│ │    - Constraint length K=7                         │   │
│ │    - Rate 1/2 mother code                          │   │
│ │    - Puncturing for 2/3, 3/4, 5/6                  │   │
│ │                                                     │   │
│ │ 3. Interleaver                                     │   │
│ │    - Block interleaver (IEEE 802.11 spec)          │   │
│ │                                                     │   │
│ │ 4. QAM Mapper                                      │   │
│ │    - BPSK, QPSK, 16-QAM, 64-QAM                    │   │
│ │                                                     │   │
│ │ 5. Pilot Insertion                                 │   │
│ │    - 4 pilot subcarriers (±7, ±21)                 │   │
│ │    - Polarity sequence                             │   │
│ │                                                     │   │
│ │ 6. 64-point IFFT                                   │   │
│ │    - 52 data/pilot subcarriers                     │   │
│ │    - DC null, guard bands                          │   │
│ │                                                     │   │
│ │ 7. Cyclic Prefix Addition                          │   │
│ │    - Short CP: 0.8 μs (16 samples)                 │   │
│ │    - Long CP: 3.2 μs (64 samples - legacy)         │   │
│ │                                                     │   │
│ │ 8. Preamble Prepending                             │   │
│ │    - Short training symbols (10x 0.8 μs)           │   │
│ │    - Long training symbols (2x 3.2 μs + GI)        │   │
│ │    - SIGNAL field (legacy) or HT-SIG (11n)         │   │
│ └────────────────────────────────────────────────────┘   │
└──────────────┬───────────────────────────────────────────┘
               │ IQ samples (20 Msps)
               ▼
┌──────────────────────────────────────────────────────────┐
│ FPGA: tx_intf Output Stage                               │
│ • Antenna selection / CDD                                │
│ • Digital gain (BB_GAIN = 250)                           │
│ • Interpolation: 20 Msps → 40 Msps                       │
└──────────────┬───────────────────────────────────────────┘
               │ LVDS Interface (40 Msps IQ)
               ▼
┌──────────────────────────────────────────────────────────┐
│ AD9361 RF Frontend                                       │
│ • DAC: 12-bit @ 40 Msps                                  │
│ • TX LO tuning                                           │
│ • TX attenuation control                                 │
│ • PA enable/disable                                      │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
           Antenna
               │
               ▼ (After transmission)
┌──────────────────────────────────────────────────────────┐
│ TX Completion Interrupt (IRQ 34)                         │
│                                                           │
│ Kernel: openwifi_tx_interrupt()                          │
│ File: /driver/sdr.c (lines 661-849)                      │
│                                                           │
│ 1. Read TX result from FPGA (XPU registers)              │
│    - ACK received? (yes/no)                              │
│    - Retry count                                         │
│    - Block ACK bitmap (for A-MPDU)                       │
│                                                           │
│ 2. Find corresponding skb in ring buffer                 │
│    - Match queue index and descriptor                    │
│                                                           │
│ 3. DMA unmap                                             │
│    - dma_unmap_single()                                  │
│                                                           │
│ 4. Update ieee80211_tx_info                              │
│    - status.rates[].count = retry + 1                    │
│    - status.flags = IEEE80211_TX_STAT_ACK (if ACK)       │
│    - status.ampdu_len, ampdu_ack_len (for A-MPDU)        │
│                                                           │
│ 5. Report to mac80211                                    │
│    - ieee80211_tx_status_irqsafe(hw, skb)                │
│                                                           │
│ 6. Update statistics                                     │
│    - TX success/failure counters                         │
│    - Per-rate statistics                                 │
│                                                           │
│ 7. Wake stopped queue (if needed)                        │
│    - Check ring buffer space                             │
│    - ieee80211_wake_queue()                              │
└──────────────────────────────────────────────────────────┘
```

**Typical TX Latency Breakdown:**
- Kernel processing: 10-50 μs
- DMA transfer: 2-5 μs
- Queue wait: 0-500 μs (depends on CSMA/CA)
- OFDM modulation: 5-20 μs
- Air time: 20-1000 μs (depends on rate and length)
- ACK wait: 16 μs (SIFS) + 20 μs (ACK PHY)
- **Total: ~50 μs - 1.6 ms**

---

## Module Interactions

### Driver-to-Driver Communication

**API Export Pattern:**

Each FPGA interface driver exports a function pointer structure:

```c
// In tx_intf.c
struct tx_intf_driver_api tx_intf_driver_api_inst = {
    .hw_init = hw_init,
    .reg_read = reg_read,
    .reg_write = reg_write,
    .TX_INTF_REG_TX_CONFIG_write = TX_INTF_REG_TX_CONFIG_write,
    // ... 20+ more functions
};
struct tx_intf_driver_api *tx_intf_api = &tx_intf_driver_api_inst;
EXPORT_SYMBOL(tx_intf_api);
```

**Main driver usage:**

```c
// In sdr.c
extern struct tx_intf_driver_api *tx_intf_api;
extern struct rx_intf_driver_api *rx_intf_api;
extern struct xpu_driver_api *xpu_api;
extern struct openofdm_tx_driver_api *openofdm_tx_api;
extern struct openofdm_rx_driver_api *openofdm_rx_api;

// Usage example
tx_intf_api->TX_INTF_REG_TX_CONFIG_write(tx_config);
xpu_api->XPU_REG_FILTER_FLAG_write(filter_flag);
```

### Software-to-FPGA Communication

**1. Register Access (Control Plane):**

```c
// Memory-mapped I/O (each driver)
static void __iomem *base_addr;

static inline u32 reg_read(u32 reg) {
    return ioread32(base_addr + reg);
}

static inline void reg_write(u32 reg, u32 value) {
    iowrite32(value, base_addr + reg);
}
```

**2. DMA (Data Plane):**

TX (Scatter-Gather):
```c
sg_init_table(&tx_sg, 1);
sg_dma_address(&tx_sg) = dma_addr;
sg_dma_len(&tx_sg) = len;

txd = tx_chan->device->device_prep_slave_sg(
    tx_chan, &tx_sg, 1, DMA_MEM_TO_DEV, flags, NULL);

tx_cookie = txd->tx_submit(txd);
dma_async_issue_pending(tx_chan);
```

RX (Cyclic Buffer):
```c
rxd = rx_chan->device->device_prep_dma_cyclic(
    rx_chan,
    dma_addr,
    total_size,
    period_size,
    DMA_DEV_TO_MEM,
    flags);

rx_cookie = rxd->tx_submit(rxd);
dma_async_issue_pending(rx_chan);
```

**3. Interrupts:**

```c
// Registration
irq_rx = irq_of_parse_and_map(dev->of_node, 1);
request_irq(irq_rx, openwifi_rx_interrupt,
            IRQF_SHARED, "sdr,rx_pkt_intr", dev);

// Handler
static irqreturn_t openwifi_rx_interrupt(int irq, void *dev_id) {
    // Process RX packets
    return IRQ_HANDLED;
}
```

### User-to-Driver Communication

**1. nl80211 Testmode (sdrctl):**

```
sdrctl → netlink → cfg80211 → mac80211 → openwifi_testmode_cmd()
```

**2. Sysfs:**

```bash
# Read statistics
cat /sys/devices/.../sdr/rx_stat
cat /sys/devices/.../sdr/tx_stat

# Write arbitrary IQ
echo "data" > /sys/devices/.../sdr/arbitrary_iq
```

**3. Standard Tools:**

```bash
ifconfig sdr0 up
iwconfig sdr0 channel 44
iw dev sdr0 scan
```

---

## Hardware/Software Boundaries

### Responsibility Division

| Layer | Component | Responsibilities |
|-------|-----------|------------------|
| **Hardware (FPGA)** | openofdm_rx | OFDM demodulation, sync, Viterbi |
| | openofdm_tx | OFDM modulation, encoding |
| | xpu | CSMA/CA, TSF timer, ACK, frame filtering |
| | rx_intf | RX DMA, gain control, antenna select |
| | tx_intf | TX DMA, queue management, antenna select |
| | side_ch | CSI/IQ capture |
| **Software (ARM)** | sdr.c | Packet TX/RX, ring buffers, rate control coord |
| | mac80211 | Mgmt frames, authentication, encryption |
| | User space | Configuration, monitoring, applications |

### Critical Timing Requirements

**Hardware (FPGA) handles:**
- SIFS timing: 16 μs ± 1 μs ✓ (achieved: 10 μs)
- ACK generation: < 10 μs ✓
- CSMA/CA backoff: μs precision ✓
- TSF timer: 1 μs resolution ✓

**Software (ARM) handles:**
- Management frames: ms timescale
- Association/authentication: ms-second timescale
- Rate adaptation: per-packet or slower

---

## Key Design Decisions

### 1. Split MAC Architecture

**Decision:** High MAC in software (mac80211), Low MAC in FPGA (xpu)

**Rationale:**
- Flexibility for high-level protocols
- Hardware speed for time-critical operations
- Standard Linux WiFi compatibility

### 2. Cyclic RX Buffer

**Decision:** Continuous circular DMA buffer for RX

**Rationale:**
- Eliminates buffer allocation overhead
- Predictable memory usage
- Supports high packet rate

### 3. Multi-Queue TX

**Decision:** 4 hardware queues with priority

**Rationale:**
- QoS support (voice, video, best effort, background)
- Airtime fairness
- Network slicing capability

### 4. Direct FPGA Control of AD9361 TX LO

**Decision:** FPGA controls TX LO via SPI (0.6 μs turnaround)

**Rationale:**
- Fast TX/RX switching
- Self-interference suppression
- Meet SIFS timing requirements

### 5. Zero-Offset Tuning

**Decision:** TX LO = RX LO = center frequency

**Rationale:**
- Better EVM performance
- Simplified DC offset handling
- Improved spectrum mask compliance

### 6. Baseband Clock from AD9361

**Decision:** FPGA clock derived from AD9361

**Rationale:**
- Zero clock drift between RF and baseband
- Eliminates frequency offset accumulation
- Simplified synchronization

---

## Performance Characteristics

### Measured Performance

| Metric | Value | Notes |
|--------|-------|-------|
| **TX Throughput** | 40-50 Mbps (TCP) | Iperf measurement |
| | 50 Mbps (UDP) | With aggregation |
| **RX Sensitivity** | -92 dBm @ MCS0 | BPSK 1/2 |
| | -73 dBm @ MCS7 | 64-QAM 5/6 |
| **EVM** | -38 dB | Transmitter quality |
| **SIFS** | 10 μs | Spec: 10 μs, achieved |
| **TSF Resolution** | 1 μs | 64-bit counter |
| **ACK Turnaround** | 16-20 μs | SIFS + processing |
| **Sample Rate** | 40 Msps (RF) | AD9361 ↔ FPGA |
| | 20 Msps (BB) | FPGA baseband |

### Bottlenecks and Limitations

**Current Limitations:**

1. **Viterbi Decoder:**
   - Xilinx eval license: stops after ~2 hours
   - Requires FPGA reload
   - Full license available for purchase

2. **AMPDU Aggregation:**
   - Maximum 4 MPDUs per A-MPDU
   - Experimental support
   - Limited by buffer size

3. **No MIMO:**
   - Single antenna TX/RX
   - Can switch between antennas
   - No spatial multiplexing

4. **20 MHz Bandwidth Only:**
   - No 40 MHz support
   - Limited to 72.2 Mbps theoretical

5. **No Hardware Encryption:**
   - Encryption in software (mac80211)
   - Performance impact

### Scalability

**Supported Concurrent Operations:**
- Up to 4 virtual interfaces (VIFs)
- 4 TX queues with independent scheduling
- Network slicing: 16 time slices
- CSI capture: Up to 8 equalizer outputs

---

## References

### Related Documentation

- [Main README](/README.md) - Project overview and quick start
- [Technical README](/doc/README.md) - Driver and FPGA details
- [Build Guide](/doc/BUILD_GUIDE.md) - Compilation instructions
- [PHY/MAC Guide](/doc/PHY_MAC_GUIDE.md) - PHY and MAC layer details
- [RF/SDR Guide](/doc/RF_SDR_GUIDE.md) - RF frontend configuration
- [API Reference](/doc/API_REFERENCE.md) - Complete API documentation

### External Resources

- [OpenWiFi Hardware (FPGA)](https://github.com/open-sdr/openwifi-hw) - Verilog/VHDL sources
- [IEEE 802.11-2016](https://standards.ieee.org/standard/802_11-2016.html) - WiFi standard
- [Linux mac80211](https://wireless.wiki.kernel.org/en/developers/documentation/mac80211) - Kernel subsystem
- [AD9361 Datasheet](https://www.analog.com/en/products/ad9361.html) - RF transceiver

### Publications

See [publications.md](/doc/publications.md) for 100+ research papers using openwifi.

---

**Document Version:** 1.0
**Last Updated:** 2025-11-21
**Contributors:** OpenWiFi community analysis
**License:** AGPL-3.0-or-later
