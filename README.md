# ZynqFlow — 8-Lane INT8 SIMD Streaming Accelerator with AXI DMA on Zynq-7020

![Language](https://img.shields.io/badge/RTL-Verilog--2001-blue.svg)
![FPGA](https://img.shields.io/badge/FPGA-Zynq--7020%20(XC7Z020)-orange.svg)
![Board](https://img.shields.io/badge/Board-Digilent%20ZedBoard-green.svg)
![Interface](https://img.shields.io/badge/Interface-AXI4--Stream%20%7C%20AXI4--Lite-purple.svg)
![Status](https://img.shields.io/badge/Status-Hardware%20Verified%20(23.2x%20Speedup)-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)

ZynqFlow is a hardware-verified Zynq PS–PL streaming system that accelerates 8-parallel signed INT8 vector math per 64-bit AXI4-Stream beat. The system uses an AMD AXI DMA engine to move data between DDR3 memory and a custom Verilog accelerator (StreamOps), with memory-mapped AXI4-Lite configuration and performance monitoring driven by the dual ARM Cortex-A9 processor.

---

## ⚡ Headline Benchmark Result

On a **1 MiB INT8 vector workload** (1,048,576 elements), the StreamOps accelerator + DMA engine completed the end-to-end transfer and processing in **4 ms** (~250 MB/s), compared to **93 ms** (~10 MB/s) on the ARM Cortex-A9 CPU, achieving a verified **23.2× hardware speedup**.

<p align="center">
  <img src="docs/images/uart_hardware_benchmark.png" alt="ZedBoard Hardware UART Test Output" width="820">
</p>
<p align="center"><em>Figure 1: Live ZedBoard UART terminal log showing 100% verification pass across all 7 SIMD math modes and 23.2x speedup benchmark.</em></p>

---

## 📸 Physical Hardware & Vivado Block Design

<p align="center">
  <img src="docs/images/zedboard_setup.jpeg" alt="ZedBoard Hardware Setup" width="700"><br>
  <em>Figure 2: ZynqFlow running live on physical Digilent ZedBoard (Zynq-7020) hardware with active DONE LED.</em>
</p>

<br>

<p align="center">
  <img src="docs/images/vivado_block_design.png" alt="Vivado Block Design System Diagram" width="900"><br>
  <em>Figure 3: Complete Vivado IP Integrator Block Design showing Zynq PS7, AXI DMA v7.1, Interconnects, and custom StreamOps IP core.</em>
</p>

---

## 📋 Project at a Glance

| Property | Specification |
| :--- | :--- |
| **FPGA Target** | Xilinx Zynq-7020 (`xc7z020clg484-1`) on Digilent ZedBoard |
| **Host System** | Dual ARM Cortex-A9 @ 667 MHz with 512 MB DDR3 RAM |
| **Accelerator Core** | `StreamOps` 8-Lane INT8 SIMD Data Processor |
| **Data Path Width** | 64-bit AXI4-Stream (8 parallel INT8 elements / beat) |
| **Control Interface** | AXI4-Lite Slave mapped at `0x40000000` |
| **DMA Engine** | AMD AXI DMA v7.1 (Direct / Simple Mode, 23-bit length counter) |
| **System Clock** | 100 MHz (`FCLK_CLK0`) |
| **RTL Resource Cost** | **784 LUTs (1.47%)**, **348 FFs (0.33%)**, **0 BRAM**, **0 DSP** |
| **Full Implementation** | **3,472 LUTs (6.53%)**, **4,095 FFs (3.85%)**, **3 BRAM Tiles** |
| **RTL Verification** | 23 directed & randomized simulation test cases (10,000+ beats) |
| **Hardware Verification** | 100 consecutive 1 MiB DMA stress transfers with 0 mismatches |

---

## 📐 System Architecture & Data Pipeline

```
                 Zynq-7020 Processing System (PS)
    ┌─────────────────────────────────────────────────────────┐
    │  ARM Cortex-A9 CPU              DDR3 Memory (512 MB)     │
    └──────────────┬───────────────────────────▲──────────────┘
                   │ M_AXI_GP0                 │ S_AXI_HP0
                   │ (Control @ 0x40000000)    │ (Data Streaming)
                   ▼                           │
          AXI Interconnect             AXI Interconnect
            /          \                       │
           /            \                      │
          ▼              ▼                     │
   AXI DMA Ctrl    StreamOps Regs              │
   (0x40400000)     (0x40000000)               │
                                               ▼
                                         AXI DMA Engine
                                           (MM2S / S2MM)
                                          /           \
                           AXI4-Stream   /             \  AXI4-Stream
                             (MM2S 64b) /               \ (S2MM 64b)
                                       ▼                 \
                          ┌───────────────────────────────┴─┐
                          │    StreamOps Accelerator IP    │
                          │   8x INT8 SIMD Pipelines        │
                          └─────────────────────────────────┘
```

### End-to-End Data Pipeline Steps:
1. **Buffer Allocation**: ARM Cortex-A9 allocates source `TX` (0x01000000) and destination `RX` (0x01200000) buffers in DDR3.
2. **Cache Coherency**: ARM flushes CPU L1/L2 cache lines (`Xil_DCacheFlushRange`) for the source buffer.
3. **Accelerator Setup**: ARM configures StreamOps operation mode, immediates, and clamp bounds via AXI4-Lite.
4. **DMA Trigger**: ARM programs AXI DMA S2MM (receiver) first, followed by MM2S (transmitter).
5. **Memory Streaming**: AXI DMA reads source buffer from DDR3 via High-Performance Port 0 (`S_AXI_HP0`).
6. **SIMD Acceleration**: StreamOps transforms 8 signed INT8 values per 100 MHz clock cycle in a single-stage backpressure-safe pipeline.
7. **Destination Write**: AXI DMA writes output stream back to DDR3 via `S_AXI_HP0`.
8. **Cache Invalidation**: ARM invalidates destination cache lines (`Xil_DCacheInvalidateRange`) and verifies output array against C Golden Model.

---

## ⚙️ Custom StreamOps Accelerator Core

The custom accelerator core consist of 4 modular Verilog files located in [`rtl/`](rtl/):

- [`streamops_lane.v`](rtl/streamops_lane.v): Single signed INT8 combinational arithmetic unit.
- [`streamops_axis.v`](rtl/streamops_axis.v): 64-bit AXI4-Stream datapath instantiating 8 SIMD lanes in parallel with hardware event counters.
- [`streamops_axil_regs.v`](rtl/streamops_axil_regs.v): AXI4-Lite slave register file providing software control & hardware performance counters.
- [`streamops_top.v`](rtl/streamops_top.v): Top-level wrapper module for Vivado IP packaging.

### Supported SIMD Operations

| Mode ID | Name | Mathematical Expression | Parameter Inputs | Saturation / Boundary Behavior |
| :---: | :--- | :--- | :--- | :--- |
| `0` | **BYPASS** | $y = x$ | None | Pure passthrough |
| `1` | **RELU** | $y = \max(x, 0)$ | None | Clamps negative values to `0` |
| `2` | **ADD_SAT** | $y = \text{saturate}(x + \text{imm8})$ | `imm8` (signed INT8) | Clamps overflow to `+127` and underflow to `-128` |
| `3` | **CLAMP** | $y = \text{clamp}(x, \text{lo}, \text{hi})$ | `clamp_lo`, `clamp_hi` | Clamps input to specified $[ \text{lo}, \text{hi} ]$ range |
| `4` | **ABS** | $y = \vert x \vert$ | None | Saturates `-128` to `+127` (prevents 8-bit signed overflow) |
| `5` | **THRESHOLD** | $y = (x \ge \text{imm8}) ? +127 : 0$ | `imm8` (signed INT8) | Binary mask generation (`+127` or `0`) |
| `6` | **XOR** | $y = x \oplus \text{imm8}$ | `imm8` (byte mask) | Bitwise logical XOR |

---

## 📑 AXI4-Lite Register Map (`0x40000000`)

| Byte Offset | Register | Access | Bitfields & Description |
| :---: | :--- | :---: | :--- |
| `0x00` | **CTRL** | R/W | `bit[0]`: Enable accelerator, `bit[1]`: Clear performance counters, `bit[2]`: Soft reset |
| `0x04` | **MODE** | R/W | `bits[2:0]`: Operation selector (0: BYPASS, 1: RELU, 2: ADD_SAT, 3: CLAMP, 4: ABS, 5: THRESHOLD, 6: XOR) |
| `0x08` | **IMM8** | R/W | `bits[7:0]`: Signed 8-bit immediate value for `ADD_SAT`, `THRESHOLD`, and `XOR` |
| `0x0C` | **CLAMP** | R/W | `bits[7:0]`: `clamp_lo` bound, `bits[15:8]`: `clamp_hi` bound |
| `0x10` | **STATUS** | RO | `bit[0]`: Enable, `bit[1]`: `s_axis_tready`, `bit[2]`: `m_axis_tvalid` |
| `0x14` | **INPUT_BEATS** | RO | 32-bit hardware counter of total accepted input AXI-Stream beats |
| `0x18` | **OUTPUT_BEATS** | RO | 32-bit hardware counter of total transferred output AXI-Stream beats |
| `0x1C` | **STALL_CYCLES** | RO | 32-bit counter of cycles stalled by downstream backpressure (`TVALID && !TREADY`) |
| `0x20` | **FRAME_COUNT** | RO | 32-bit hardware counter of completed frames (`TLAST` handshakes) |
| `0x24` | **ACTIVE_CYCLES** | RO | 32-bit counter of clock cycles spent processing active frames |
| `0x28` | **VERSION** | RO | Constant `0x00010000` (Version 1.0 hardware ID) |

---

## 🧪 RTL Verification & Simulation

A comprehensive self-checking testbench is provided in [`tb/tb_streamops.v`](tb/tb_streamops.v) alongside AXI-Stream Source ([`axis_source_bfm.v`](tb/axis_source_bfm.v)) and Sink ([`axis_sink_bfm.v`](tb/axis_sink_bfm.v)) Bus Functional Models.

### Verification Highlights:
- **23 Directed & Randomized Test Cases**: Tests edge cases (-128, -127, -1, 0, 1, 126, 127) for all 7 modes.
- **Randomized Backpressure Testing**: Simulates random producer `TVALID` gaps and consumer `TREADY` stalls.
- **Protocol Compliance**: Asserts that `m_axis_tdata`, `m_axis_tkeep`, and `m_axis_tlast` remain rock-solid during downstream stall cycles without losing or corrupting beats.
- **10,000+ Beat Stress Verification**: 100% data verification against Python golden reference model ([`streamops_model.py`](tools/streamops_model.py)).

---

## 📊 Resource Utilization & Implementation

Synthesized and implemented for **Xilinx Zynq-7020 (xc7z020clg484-1)** at **100 MHz (`FCLK_CLK0`)**:

### 1. Custom StreamOps IP (Standalone Synthesis)
| Resource | Used | Available | Utilization % |
| :--- | :---: | :---: | :---: |
| **Slice LUTs** | **784** | 53,200 | **1.47%** |
| **Slice Registers (FF)** | **348** | 106,400 | **0.33%** |
| **Block RAM (BRAM)** | **0** | 140 | **0.00%** |
| **DSP Blocks** | **0** | 220 | **0.00%** |
| **Inferred Latches** | **0** | — | **0 (Clean)** |

### 2. Full System Implementation (`zynqflow_bd_wrapper` Placed)
| Component / Module | Slice LUTs | Slice Registers (FFs) | BRAM Tiles | Utilization % |
| :--- | :---: | :---: | :---: | :---: |
| **StreamOps Accelerator IP** | 784 | 348 | 0 | LUT: 1.47% |
| **AMD AXI DMA v7.1** | 1,803 | 2,404 | 3 | LUT: 3.39% |
| **AXI Interconnects & Peripherals** | 885 | 1,343 | 0 | LUT: 1.67% |
| **Total System** | **3,472** | **4,095** | **3** | **LUT: 6.53% \| FF: 3.85%** |

*Raw Implementation Report Archived at [`results/implementation/utilization_placed.rpt`](results/implementation/utilization_placed.rpt)*

---

## 📂 Repository Structure

```
ZynqFlow/
├── README.md                           Project documentation
├── LICENSE                             MIT License
├── rtl/                                Custom Verilog-2001 RTL Sources
│   ├── streamops_lane.v                INT8 SIMD arithmetic processing lane
│   ├── streamops_axis.v                64-bit 8-lane AXI4-Stream datapath
│   ├── streamops_axil_regs.v           AXI4-Lite control & performance counters
│   └── streamops_top.v                 Top-level IP wrapper module
├── tb/                                 Self-checking Verilog Simulation Environment
│   ├── tb_streamops.v                  23-test self-checking testbench
│   ├── axis_source_bfm.v               AXI4-Stream master BFM with random TVALID gaps
│   └── axis_sink_bfm.v                 AXI4-Stream slave BFM with random TREADY stalls
├── vivado/                             Reproducible Vivado Build Scripts
│   ├── create_bd.tcl                   Tcl script generating initial Block Design
│   └── block_c.tcl                     Complete Tcl script packaging custom IP & building bitstream
├── software/                           Bare-metal C Application for Vitis
│   └── main.c                          Full hardware test suite & CPU-vs-FPGA benchmark
├── docs/                               Documentation & Images
│   └── images/                         High-resolution screenshots and board photos
└── results/                            Archived Empirical Evidence
    ├── uart_hardware_benchmark.log     Raw terminal benchmark output log
    └── utilization_placed.rpt          Vivado post-implementation utilization report
```

---

## 🛠️ Reproducing ZynqFlow

### Prerequisites
- **AMD Vivado 2022.1** (or compatible version)
- **AMD Vitis 2022.1**
- **Digilent ZedBoard** (Zynq-7020) + 12V DC Power Adapter + 2x Micro-USB cables

### 1. Build Hardware Bitstream & Export XSA (Vivado)
Open Vivado Tcl Console in the project directory and execute:
```tcl
source vivado/block_c.tcl
```
*This script packages `StreamOps` as a custom Vivado IP, instantiates Zynq PS + AXI DMA + StreamOps in the block design, runs synthesis & implementation, generates the bitstream, and exports `zynqflow_bd_wrapper.xsa`.*

### 2. Build & Run Application (Vitis)
1. Launch **Vitis 2022.1** and set workspace to `vitis_ws`.
2. Create Application Project from exported platform `zynqflow_bd_wrapper.xsa`.
3. Add source file [`software/main.c`](software/main.c).
4. Verify Board Support Package (BSP) `stdin`/`stdout` is assigned to `ps7_uart_1`.
5. Connect ZedBoard UART to PC (`115200` baud, 8N1) and click **Run / Launch Hardware**.

---

## 💡 Key Design Decisions & Technical Insights

1. **Why 64-bit AXI4-Stream?**
   A 64-bit stream width perfectly accommodates 8 parallel INT8 values per beat, matching the native AXI DMA bus width and maximizing burst throughput without data packing overhead.
2. **Cache Coherency Management**:
   The ARM Cortex-A9 uses L1/L2 data caching. Explicitly calling `Xil_DCacheFlushRange` before DMA MM2S transfers guarantees DMA reads updated DDR data, while `Xil_DCacheInvalidateRange` after DMA S2MM prevents CPU from reading stale cache lines.
3. **AXI DMA Length Register Extension**:
   Configured `c_sg_length_width = 23` in AXI DMA settings to allow single contiguous transfers up to **8 MB** (overcoming the default 14-bit 16 KB limitation).
4. **Single-Stage Pipeline Backpressure**:
   The datapath implements a single-stage holding register with `can_accept = !out_valid || m_axis_tready`. This ensures zero performance penalty during ready cycles while preventing any data corruption during backpressure stalls.

---

## 📜 License
This project is licensed under the [MIT License](LICENSE).
