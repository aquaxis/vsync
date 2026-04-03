# Address Map Definition

**Target:** Xilinx Spartan UltraScale+
**Architecture:** RISC-V RV32IM
**Address Width:** 32-bit (4 GB address space)
**Data Width:** 32-bit
**Revision:** 2.0
**Status:** Primary reference for RTL implementation

---

## 1. Memory Map Overview

### 1.1 Address Region Summary

| Region | Base Address | End Address | Size | Type | Description |
|--------|-------------|-------------|------|------|-------------|
| Instruction Memory | `0x0000_0000` | `0x0000_FFFF` | 64 KB | BRAM | Read-only during execution, writable for initialization |
| Data Memory | `0x0001_0000` | `0x0001_3FFF` | 16 KB | BRAM | Read/write general-purpose data memory |
| CLINT | `0x0200_0000` | `0x0200_FFFF` | 64 KB | Registers | Core Local Interruptor (RISC-V standard) |
| PLIC | `0x0C00_0000` | `0x0C00_0FFF` | 4 KB | Registers | Platform-Level Interrupt Controller (RISC-V standard) |
| UART | `0x1000_0000` | `0x1000_00FF` | 256 B | APB | UART serial controller |
| GPIO | `0x1000_0100` | `0x1000_01FF` | 256 B | APB | General-purpose I/O |
| RTOS Control | `0x1100_0000` | `0x1100_FFFF` | 64 KB | Registers | Hardware RTOS control registers |
| POSIX Control | `0x1200_0000` | `0x1200_FFFF` | 64 KB | Registers | POSIX hardware abstraction layer registers |
| HyperRAM | `0x2000_0000` | `0x2FFF_FFFF` | 256 MB | External | HyperRAM controller mapped region |

### 1.2 Visual Memory Map

```
  0xFFFF_FFFF +--------------------------+
              |                          |
              |       (Reserved)         |
              |                          |
  0x3000_0000 +--------------------------+
              |   HyperRAM              | 256 MB
  0x2000_0000 +--------------------------+
              |       (Reserved)         |
  0x1300_0000 +--------------------------+
              | POSIX Control Registers  | 64 KB
  0x1200_0000 +--------------------------+
              |       (Reserved)         |
  0x1101_0000 +--------------------------+
              | RTOS Control Registers   | 64 KB
  0x1100_0000 +--------------------------+
              |       (Reserved)         |
  0x1000_0200 +--------------------------+
              |   GPIO (APB)            | 256 B
  0x1000_0100 +--------------------------+
              |   UART (APB)            | 256 B
  0x1000_0000 +--------------------------+
              |                          |
              |       (Reserved)         |
              |                          |
  0x0C00_1000 +--------------------------+
              |   PLIC                  | 4 KB
  0x0C00_0000 +--------------------------+
              |                          |
              |       (Reserved)         |
              |                          |
  0x0201_0000 +--------------------------+
              |   CLINT                 | 64 KB
  0x0200_0000 +--------------------------+
              |                          |
              |       (Reserved)         |
              |                          |
  0x0001_4000 +--------------------------+
              |   Data Memory (BRAM)    | 16 KB
  0x0001_0000 +--------------------------+
              |   Instruction Mem (BRAM)| 64 KB
  0x0000_0000 +--------------------------+
```

---

## 2. AXI4 Address Decode Table

The Instruction Memory (BRAM IMEM) is directly connected to the CPU fetch port and is not routed through the AXI4 interconnect. All other regions are accessed via the AXI4 data port.

The AXI4 interconnect is a 1-Master to 5-Slave address-based router/crossbar. The AXI4-to-APB bridge (Slave M2) further decodes addresses for the CLINT, PLIC, UART, and GPIO peripherals.

| Slave Port | Target | Base Address | End Address | Size | Address Mask | Slave Select Condition |
|-----------|--------|-------------|-------------|------|--------------|----------------------|
| M0 | `bram_dmem` | `0x0001_0000` | `0x0001_3FFF` | 16 KB | `0xFFFF_C000` | `addr[31:14] == 18'h00004` |
| M1 | `hyperram_ctrl` | `0x2000_0000` | `0x2FFF_FFFF` | 256 MB | `0xF000_0000` | `addr[31:28] == 4'h2` |
| M2 | `axi4_apb_bridge` | (multiple) | (multiple) | - | - | See APB Bridge Decode (Section 2.2) |
| M3 | `hw_rtos` | `0x1100_0000` | `0x1100_FFFF` | 64 KB | `0xFFFF_0000` | `addr[31:16] == 16'h1100` |
| M4 | `posix_hw_layer` | `0x1200_0000` | `0x1200_FFFF` | 64 KB | `0xFFFF_0000` | `addr[31:16] == 16'h1200` |

### 2.1 AXI4 Interconnect Parameters

| Parameter | Value |
|-----------|-------|
| Address width | 32 bits |
| Data width | 32 bits |
| ID width | 4 bits |
| Number of masters | 1 (CPU data port) |
| Number of slaves | 5 |
| Burst support | INCR, WRAP (HyperRAM only) |
| Outstanding transactions | 1 (in-order) |

### 2.2 APB Bridge Address Decode

The AXI4-to-APB bridge (Slave M2) accepts transactions destined for the following non-contiguous address regions and routes them to the appropriate APB peripheral.

| APB Slave | PSEL Index | Base Address | End Address | Size | Description |
|-----------|-----------|-------------|-------------|------|-------------|
| CLINT | `psel[0]` | `0x0200_0000` | `0x0200_FFFF` | 64 KB | Core Local Interruptor |
| PLIC | `psel[1]` | `0x0C00_0000` | `0x0C00_0FFF` | 4 KB | Platform-Level Interrupt Controller |
| UART | `psel[2]` | `0x1000_0000` | `0x1000_00FF` | 256 B | UART serial controller |
| GPIO | `psel[3]` | `0x1000_0100` | `0x1000_01FF` | 256 B | General-purpose I/O |

**Note:** The APB bridge address ranges are non-contiguous (following RISC-V standard placement). The interconnect routes any address matching an APB peripheral range to Slave M2.

---

## 3. APB Peripheral Address Assignments

All APB peripherals use 32-bit aligned accesses. Byte-enable strobes are supported but all registers are defined at 32-bit width. Offsets below are relative to each peripheral's base address.

---

### 3.1 UART Registers (Base: `0x1000_0000`)

| Offset | Register Name | R/W | Width | Description |
|--------|--------------|-----|-------|-------------|
| `0x00` | `TX_DATA` | W | 32 | Transmit data register |
| `0x04` | `RX_DATA` | R | 32 | Receive data register |
| `0x08` | `STATUS` | R | 32 | Status register |
| `0x0C` | `CTRL` | R/W | 32 | Control register |
| `0x10` | `BAUD_DIV` | R/W | 32 | Baud rate divisor |
| `0x14` | `FIFO_CTRL` | R/W | 32 | FIFO control |
| `0x18` | `INT_EN` | R/W | 32 | Interrupt enable |
| `0x1C` | `INT_STATUS` | R/W1C | 32 | Interrupt status (write-1-to-clear) |

#### 3.1.1 TX_DATA (Offset `0x00`, Write-only)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [7:0] | `tx_data` | W | `0x00` | Byte to transmit. Write pushes data into the TX FIFO. |
| [31:8] | Reserved | - | `0x000000` | Reserved. Writes ignored. |

#### 3.1.2 RX_DATA (Offset `0x04`, Read-only)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [7:0] | `rx_data` | R | `0x00` | Received byte. Read pops data from the RX FIFO. |
| [31:8] | Reserved | - | `0x000000` | Reserved. Reads as zero. |

#### 3.1.3 STATUS (Offset `0x08`, Read-only)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | `tx_full` | R | `0` | TX FIFO full flag. 1 = FIFO is full, do not write TX_DATA. |
| [1] | `tx_empty` | R | `1` | TX FIFO empty flag. 1 = FIFO is empty. |
| [2] | `rx_full` | R | `0` | RX FIFO full flag. 1 = FIFO is full. |
| [3] | `rx_empty` | R | `1` | RX FIFO empty flag. 1 = no data available. |
| [4] | `tx_busy` | R | `0` | Transmitter busy. 1 = currently shifting out a byte. |
| [5] | `rx_valid` | R | `0` | RX data valid. 1 = at least one byte in RX FIFO. |
| [6] | `overrun` | R | `0` | Overrun error. 1 = RX FIFO was full when new data arrived. |
| [7] | `frame_err` | R | `0` | Framing error. 1 = stop bit not detected. |
| [8] | `parity_err` | R | `0` | Parity error. 1 = parity mismatch detected. |
| [31:9] | Reserved | - | `0` | Reserved. |

#### 3.1.4 CTRL (Offset `0x0C`, Read/Write)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | `tx_en` | R/W | `0` | Transmitter enable. 1 = enabled. |
| [1] | `rx_en` | R/W | `0` | Receiver enable. 1 = enabled. |
| [2] | `parity_en` | R/W | `0` | Parity enable. 1 = parity checking/generation enabled. |
| [3] | `parity_type` | R/W | `0` | Parity type. 0 = even, 1 = odd. |
| [4] | `stop_bits` | R/W | `0` | Stop bits. 0 = 1 stop bit, 1 = 2 stop bits. |
| [6:5] | `data_bits` | R/W | `2'b11` | Data bits. 00 = 5 bits, 01 = 6 bits, 10 = 7 bits, 11 = 8 bits. |
| [7] | `loopback` | R/W | `0` | Loopback mode. 1 = TX output is internally connected to RX input. |
| [31:8] | Reserved | - | `0` | Reserved. |

#### 3.1.5 BAUD_DIV (Offset `0x10`, Read/Write)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [15:0] | `divisor` | R/W | `0x0000` | Baud rate divisor. Baud rate = f_clk / (divisor + 1). |
| [31:16] | Reserved | - | `0x0000` | Reserved. |

#### 3.1.6 FIFO_CTRL (Offset `0x14`, Read/Write)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | `tx_fifo_reset` | W | `0` | TX FIFO reset. Write 1 to flush. Self-clearing. |
| [1] | `rx_fifo_reset` | W | `0` | RX FIFO reset. Write 1 to flush. Self-clearing. |
| [5:2] | `fifo_threshold` | R/W | `4'h8` | FIFO interrupt threshold. Interrupt triggers when RX FIFO level >= threshold. |
| [31:6] | Reserved | - | `0` | Reserved. |

#### 3.1.7 INT_EN (Offset `0x18`, Read/Write)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | `tx_empty_en` | R/W | `0` | TX FIFO empty interrupt enable. |
| [1] | `rx_valid_en` | R/W | `0` | RX data valid interrupt enable. |
| [2] | `rx_full_en` | R/W | `0` | RX FIFO full interrupt enable. |
| [3] | `overrun_en` | R/W | `0` | Overrun error interrupt enable. |
| [4] | `frame_err_en` | R/W | `0` | Framing error interrupt enable. |
| [5] | `parity_err_en` | R/W | `0` | Parity error interrupt enable. |
| [6] | `tx_done_en` | R/W | `0` | TX complete interrupt enable. |
| [7] | `rx_threshold_en` | R/W | `0` | RX FIFO threshold interrupt enable. |
| [31:8] | Reserved | - | `0` | Reserved. |

#### 3.1.8 INT_STATUS (Offset `0x1C`, Read / Write-1-to-Clear)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | `tx_empty_int` | R/W1C | `0` | TX FIFO empty interrupt pending. |
| [1] | `rx_valid_int` | R/W1C | `0` | RX data valid interrupt pending. |
| [2] | `rx_full_int` | R/W1C | `0` | RX FIFO full interrupt pending. |
| [3] | `overrun_int` | R/W1C | `0` | Overrun error interrupt pending. |
| [4] | `frame_err_int` | R/W1C | `0` | Framing error interrupt pending. |
| [5] | `parity_err_int` | R/W1C | `0` | Parity error interrupt pending. |
| [6] | `tx_done_int` | R/W1C | `0` | TX complete interrupt pending. |
| [7] | `rx_threshold_int` | R/W1C | `0` | RX FIFO threshold interrupt pending. |
| [31:8] | Reserved | - | `0` | Reserved. |

---

### 3.2 GPIO Registers (Base: `0x1000_0100`)

GPIO width: 32 pins (active pin count is implementation-defined).

| Offset | Register Name | R/W | Width | Description |
|--------|--------------|-----|-------|-------------|
| `0x00` | `GPIO_IN` | R | 32 | Input data (read-only) |
| `0x04` | `GPIO_OUT` | R/W | 32 | Output data |
| `0x08` | `GPIO_DIR` | R/W | 32 | Direction control |
| `0x0C` | `GPIO_INT_EN` | R/W | 32 | Interrupt enable (per-pin) |
| `0x10` | `GPIO_INT_TYPE` | R/W | 32 | Interrupt type |
| `0x14` | `GPIO_INT_POL` | R/W | 32 | Interrupt polarity |
| `0x18` | `GPIO_INT_STATUS` | R/W1C | 32 | Interrupt status (write-1-to-clear) |
| `0x1C` | `GPIO_INT_RAW` | R | 32 | Raw interrupt status |

#### 3.2.1 GPIO_IN (Offset `0x00`, Read-only)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | `pin_in` | R | `0x00000000` | Sampled value of GPIO pins. Each bit corresponds to one pin. Reflects the external pin state regardless of direction setting. |

#### 3.2.2 GPIO_OUT (Offset `0x04`, Read/Write)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | `pin_out` | R/W | `0x00000000` | Output value driven on GPIO pins. Only effective for pins configured as outputs (GPIO_DIR bit = 1). |

#### 3.2.3 GPIO_DIR (Offset `0x08`, Read/Write)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | `dir` | R/W | `0x00000000` | Per-pin direction. 0 = input, 1 = output. Reset default is all inputs. |

#### 3.2.4 GPIO_INT_EN (Offset `0x0C`, Read/Write)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | `int_en` | R/W | `0x00000000` | Per-pin interrupt enable. 1 = interrupt enabled for this pin. |

#### 3.2.5 GPIO_INT_TYPE (Offset `0x10`, Read/Write)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | `int_type` | R/W | `0x00000000` | Per-pin interrupt type. 0 = level-sensitive, 1 = edge-sensitive. |

#### 3.2.6 GPIO_INT_POL (Offset `0x14`, Read/Write)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | `int_pol` | R/W | `0x00000000` | Per-pin interrupt polarity. For level mode: 0 = active-low, 1 = active-high. For edge mode: 0 = falling edge, 1 = rising edge. |

#### 3.2.7 GPIO_INT_STATUS (Offset `0x18`, Write-1-to-Clear)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | `int_status` | R/W1C | `0x00000000` | Per-pin interrupt status. Reads as 1 if the interrupt condition is detected and enabled. Write 1 to the corresponding bit to clear. |

#### 3.2.8 GPIO_INT_RAW (Offset `0x1C`, Read-only)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | `int_raw` | R | `0x00000000` | Per-pin raw interrupt status before masking by GPIO_INT_EN. Useful for polling. |

---

### 3.3 PLIC Registers (Base: `0x0C00_0000`)

Follows the RISC-V Platform-Level Interrupt Controller specification. Single hart (context 0). Up to 16 external interrupt sources (source 0 is reserved / no interrupt).

**IRQ Source Assignments:** Bit 1 = UART interrupt, Bit 2 = GPIO interrupt. See Appendix A for full wiring.

**Note:** This implementation uses a compact 4 KB layout that maps the standard PLIC registers into the available space. Source count is limited to 16 to fit within the region.

| Offset Range | Register Group | Description |
|-------------|---------------|-------------|
| `0x000` - `0x03C` | Priority | Source priority registers (sources 0-15) |
| `0x100` - `0x103` | Pending | Interrupt pending bits |
| `0x200` - `0x203` | Enable | Interrupt enable bits (context 0) |
| `0x300` | Threshold | Priority threshold (context 0) |
| `0x304` | Claim/Complete | Claim/Complete (context 0) |

#### 3.3.1 Priority Registers (Offset `0x000` - `0x03C`)

Each source has a 4-byte priority register. Source 0 is hardwired to 0 (reserved).

| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| `0x000` | `PRIORITY_SRC0` | R | Reserved, reads as 0 |
| `0x004` | `PRIORITY_SRC1` | R/W | Priority of source 1 (UART) |
| `0x008` | `PRIORITY_SRC2` | R/W | Priority of source 2 (GPIO) |
| ... | ... | ... | ... |
| `0x03C` | `PRIORITY_SRC15` | R/W | Priority of source 15 |

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [2:0] | `priority` | R/W | `0` | Priority level. 0 = disabled, 1 = lowest, 7 = highest. |
| [31:3] | Reserved | - | `0` | Reserved. |

#### 3.3.2 Pending Bits (Offset `0x100`)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | Reserved | R | `0` | Source 0 is reserved. Always reads 0. |
| [15:1] | `pending` | R | `0` | One bit per source. 1 = interrupt pending for that source. Read-only; set by hardware, cleared by claim. |
| [31:16] | Reserved | - | `0` | Reserved. |

#### 3.3.3 Enable Bits - Context 0 (Offset `0x200`)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | Reserved | R | `0` | Source 0 is reserved. |
| [15:1] | `enable` | R/W | `0` | One bit per source. 1 = interrupt source enabled for context 0. |
| [31:16] | Reserved | - | `0` | Reserved. |

#### 3.3.4 Priority Threshold - Context 0 (Offset `0x300`)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [2:0] | `threshold` | R/W | `0` | Priority threshold. Only interrupts with priority strictly greater than this value are forwarded to the hart. |
| [31:3] | Reserved | - | `0` | Reserved. |

#### 3.3.5 Claim/Complete - Context 0 (Offset `0x304`)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [3:0] | `claim_complete` | R/W | `0` | Read: returns the ID of the highest-priority pending interrupt (claim). Write: signals completion of the interrupt with the written ID. |
| [31:4] | Reserved | - | `0` | Reserved. |

---

### 3.4 CLINT Registers (Base: `0x0200_0000`)

Follows the RISC-V Core Local Interruptor specification. Single-hart system. Provides machine-mode software interrupt and timer functionality.

| Offset | Register Name | R/W | Width | Description |
|--------|--------------|-----|-------|-------------|
| `0x0000` | `MSIP` | R/W | 32 | Machine Software Interrupt Pending |
| `0x4000` | `MTIMECMP_LO` | R/W | 32 | Machine Timer Compare (lower 32 bits) |
| `0x4004` | `MTIMECMP_HI` | R/W | 32 | Machine Timer Compare (upper 32 bits) |
| `0xBFF8` | `MTIME_LO` | R/W | 32 | Machine Timer (lower 32 bits) |
| `0xBFFC` | `MTIME_HI` | R/W | 32 | Machine Timer (upper 32 bits) |

**Note:** The CLINT region is allocated 64 KB (`0x0200_0000` - `0x0200_FFFF`) which accommodates the standard RISC-V CLINT register offsets up to `0xBFFC`. All offsets fit within the 64 KB window.

#### 3.4.1 MSIP (Offset `0x0000`)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | `msip` | R/W | `0` | Machine software interrupt pending for hart 0. Writing 1 asserts the software interrupt; writing 0 de-asserts it. Maps to `mip.MSIP`. |
| [31:1] | Reserved | - | `0` | Reserved. Writes ignored, reads as 0. |

#### 3.4.2 MTIMECMP_LO (Offset `0x4000`)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | `mtimecmp_lo` | R/W | `0xFFFFFFFF` | Lower 32 bits of the 64-bit timer compare value. Timer interrupt is asserted when `mtime >= mtimecmp`. Reset to max value to prevent spurious interrupts at boot. |

#### 3.4.3 MTIMECMP_HI (Offset `0x4004`)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | `mtimecmp_hi` | R/W | `0xFFFFFFFF` | Upper 32 bits of the 64-bit timer compare value. |

#### 3.4.4 MTIME_LO (Offset `0xBFF8`)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | `mtime_lo` | R/W | `0x00000000` | Lower 32 bits of the 64-bit real-time counter. Increments at a fixed frequency. Writable for calibration. |

#### 3.4.5 MTIME_HI (Offset `0xBFFC`)

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [31:0] | `mtime_hi` | R/W | `0x00000000` | Upper 32 bits of the 64-bit real-time counter. |

**Implementation Note:** To read the full 64-bit `mtime` atomically on an RV32 system, software must use the standard read sequence: read `mtime_hi`, read `mtime_lo`, re-read `mtime_hi`, and retry if the upper half changed.

---

## 4. RISC-V CSR Address List (Privilege Spec v1.12)

All CSRs are accessed via the `csrrw`, `csrrs`, `csrrc`, `csrrwi`, `csrrsi`, `csrrci` instructions. This implementation supports Machine mode only (M-mode).

### 4.1 Machine-Level CSRs

| CSR Address | Name | R/W | Description |
|-------------|------|-----|-------------|
| `0x300` | `mstatus` | R/W | Machine status register |
| `0x301` | `misa` | R | ISA and extensions (read-only in this implementation) |
| `0x304` | `mie` | R/W | Machine interrupt enable |
| `0x305` | `mtvec` | R/W | Machine trap-handler base address |
| `0x340` | `mscratch` | R/W | Machine scratch register for trap handlers |
| `0x341` | `mepc` | R/W | Machine exception program counter |
| `0x342` | `mcause` | R/W | Machine trap cause |
| `0x343` | `mtval` | R/W | Machine trap value (bad address or instruction) |
| `0x344` | `mip` | R/W | Machine interrupt pending |
| `0xF11` | `mvendorid` | R | Vendor ID (read-only, 0 for non-commercial) |
| `0xF12` | `marchid` | R | Architecture ID (read-only) |
| `0xF13` | `mimpid` | R | Implementation ID (read-only) |
| `0xF14` | `mhartid` | R | Hardware thread ID (read-only, 0 for single-hart) |

#### 4.1.1 mstatus (CSR `0x300`) Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | Reserved | - | `0` | Reserved (UIE in User mode, not implemented). |
| [2:1] | Reserved | - | `0` | Reserved. |
| [3] | `MIE` | R/W | `0` | Machine interrupt enable. 1 = interrupts enabled globally. |
| [6:4] | Reserved | - | `0` | Reserved. |
| [7] | `MPIE` | R/W | `0` | Machine previous interrupt enable. Saved value of MIE on trap entry. |
| [10:8] | Reserved | - | `0` | Reserved. |
| [12:11] | `MPP` | R/W | `2'b11` | Machine previous privilege mode. Always `2'b11` (M-mode) in M-mode-only implementation. |
| [16:13] | `FS` | R/W | `2'b00` | Floating-point status. `00` = Off. Not used in RV32IM (no F extension). |
| [31:17] | Reserved | - | `0` | Reserved for future use. SD bit at [31] reads as 0. |

#### 4.1.2 misa (CSR `0x301`) Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [25:0] | `Extensions` | R | `0x0000_1100` | Extension flags. Bit 8 (I) = 1, Bit 12 (M) = 1. Indicates RV32IM. |
| [31:30] | `MXL` | R | `2'b01` | Machine XLEN. `01` = 32-bit. |
| [29:26] | Reserved | - | `0` | Reserved. |

#### 4.1.3 mie (CSR `0x304`) Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [2:0] | Reserved | - | `0` | Reserved (User/Supervisor software interrupt enables). |
| [3] | `MSIE` | R/W | `0` | Machine software interrupt enable. |
| [6:4] | Reserved | - | `0` | Reserved (User/Supervisor timer interrupt enables). |
| [7] | `MTIE` | R/W | `0` | Machine timer interrupt enable. |
| [10:8] | Reserved | - | `0` | Reserved (User/Supervisor external interrupt enables). |
| [11] | `MEIE` | R/W | `0` | Machine external interrupt enable. |
| [31:12] | Reserved | - | `0` | Reserved for platform-defined interrupts. |

#### 4.1.4 mip (CSR `0x344`) Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [2:0] | Reserved | - | `0` | Reserved. |
| [3] | `MSIP` | R | `0` | Machine software interrupt pending. Reflects CLINT `msip` register. |
| [6:4] | Reserved | - | `0` | Reserved. |
| [7] | `MTIP` | R | `0` | Machine timer interrupt pending. Asserted when `mtime >= mtimecmp`. |
| [10:8] | Reserved | - | `0` | Reserved. |
| [11] | `MEIP` | R | `0` | Machine external interrupt pending. Reflects PLIC output. |
| [31:12] | Reserved | - | `0` | Reserved. |

#### 4.1.5 mtvec (CSR `0x305`) Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [1:0] | `MODE` | R/W | `2'b00` | Trap vector mode. `00` = Direct (all traps go to BASE). `01` = Vectored (exceptions go to BASE, interrupts go to BASE + 4 * cause). |
| [31:2] | `BASE` | R/W | `0` | Trap vector base address (4-byte aligned). The two LSBs are part of MODE, so BASE is effectively `{mtvec[31:2], 2'b00}`. |

#### 4.1.6 mcause (CSR `0x342`) Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [30:0] | `Exception Code` | R/W | `0` | Encodes the cause of the trap. See exception code table below. |
| [31] | `Interrupt` | R/W | `0` | 1 = trap caused by interrupt. 0 = trap caused by exception. |

**Exception Codes (Interrupt = 0):**

| Code | Description |
|------|-------------|
| 0 | Instruction address misaligned |
| 1 | Instruction access fault |
| 2 | Illegal instruction |
| 3 | Breakpoint |
| 4 | Load address misaligned |
| 5 | Load access fault |
| 6 | Store/AMO address misaligned |
| 7 | Store/AMO access fault |
| 11 | Environment call from M-mode |

**Interrupt Codes (Interrupt = 1):**

| Code | Description |
|------|-------------|
| 3 | Machine software interrupt |
| 7 | Machine timer interrupt |
| 11 | Machine external interrupt |

---

### 4.2 PMP CSRs (Physical Memory Protection)

PMP provides per-region access control. This implementation supports up to 16 PMP regions.

| CSR Address | Name | R/W | Description |
|-------------|------|-----|-------------|
| `0x3A0` | `pmpcfg0` | R/W | PMP configuration for regions 0-3 |
| `0x3A1` | `pmpcfg1` | R/W | PMP configuration for regions 4-7 |
| `0x3A2` | `pmpcfg2` | R/W | PMP configuration for regions 8-11 |
| `0x3A3` | `pmpcfg3` | R/W | PMP configuration for regions 12-15 |
| `0x3B0` | `pmpaddr0` | R/W | PMP address register 0 |
| `0x3B1` | `pmpaddr1` | R/W | PMP address register 1 |
| `0x3B2` | `pmpaddr2` | R/W | PMP address register 2 |
| `0x3B3` | `pmpaddr3` | R/W | PMP address register 3 |
| `0x3B4` | `pmpaddr4` | R/W | PMP address register 4 |
| `0x3B5` | `pmpaddr5` | R/W | PMP address register 5 |
| `0x3B6` | `pmpaddr6` | R/W | PMP address register 6 |
| `0x3B7` | `pmpaddr7` | R/W | PMP address register 7 |
| `0x3B8` | `pmpaddr8` | R/W | PMP address register 8 |
| `0x3B9` | `pmpaddr9` | R/W | PMP address register 9 |
| `0x3BA` | `pmpaddr10` | R/W | PMP address register 10 |
| `0x3BB` | `pmpaddr11` | R/W | PMP address register 11 |
| `0x3BC` | `pmpaddr12` | R/W | PMP address register 12 |
| `0x3BD` | `pmpaddr13` | R/W | PMP address register 13 |
| `0x3BE` | `pmpaddr14` | R/W | PMP address register 14 |
| `0x3BF` | `pmpaddr15` | R/W | PMP address register 15 |

#### pmpcfg Byte Layout (each pmpcfg register holds 4 region configs)

Each byte within a `pmpcfg` register controls one PMP region:

| Bits | Field | Description |
|------|-------|-------------|
| [0] | `R` | Read permission. 1 = read allowed. |
| [1] | `W` | Write permission. 1 = write allowed. |
| [2] | `X` | Execute permission. 1 = execute allowed. |
| [4:3] | `A` | Address matching mode. `00` = OFF, `01` = TOR, `10` = NA4, `11` = NAPOT. |
| [6:5] | Reserved | Reserved, reads as 0. |
| [7] | `L` | Lock bit. 1 = PMP entry is locked and cannot be modified until reset. |

---

### 4.3 Performance Counter CSRs

| CSR Address | Name | R/W | Description |
|-------------|------|-----|-------------|
| `0xB00` | `mcycle` | R/W | Machine cycle counter (lower 32 bits) |
| `0xB02` | `minstret` | R/W | Machine instructions retired counter (lower 32 bits) |
| `0xB80` | `mcycleh` | R/W | Machine cycle counter (upper 32 bits) |
| `0xB82` | `minstreth` | R/W | Machine instructions retired counter (upper 32 bits) |

**Note:** On RV32, the full 64-bit counters are accessed as pairs of 32-bit CSRs. Software must use the standard double-read sequence to avoid tearing: read high, read low, re-read high, retry if high changed.

---

### 4.4 Custom CSRs

Custom CSRs are allocated in the machine-mode read/write custom space (`0x7C0`-`0x7FF`) and machine-mode read-only custom space (`0xFC0`-`0xFFF`).

| CSR Address | Name | R/W | Description |
|-------------|------|-----|-------------|
| `0x7C0` | `mrtos_ctrl` | R/W | RTOS hardware acceleration control. Bit 0: enable HW scheduler. Bit 1: enable HW context switch. |
| `0x7C1` | `mrtos_status` | R | RTOS hardware status. Bit 0: scheduler active. Bit 1: context switch in progress. Bits [7:4]: current task ID. |
| `0x7C2` | `mposix_ctrl` | R/W | POSIX hardware layer control. Bit 0: enable syscall translation. Bit 1: enable FD table. |
| `0x7C3` | `mposix_status` | R | POSIX hardware layer status. Bit 0: syscall busy. Bits [15:8]: last errno. |

---

## 5. RTOS Control Register Address Map (Base: `0x1100_0000`)

All RTOS registers are accessed via memory-mapped I/O over the AXI4 bus. 32-bit aligned accesses only.

---

### 5.1 Task Management Registers (`0x1100_0000` - `0x1100_00FF`)

| Offset | Register Name | R/W | Width | Reset | Description |
|--------|--------------|-----|-------|-------|-------------|
| `0x000` | `TASK_CREATE` | W | 32 | - | Task creation trigger. Write `0x01` to create a task using parameters set in `0x004`-`0x010`. |
| `0x004` | `TASK_CREATE_ENTRY` | R/W | 32 | `0x00000000` | Entry point address for the new task. |
| `0x008` | `TASK_CREATE_STACK` | R/W | 32 | `0x00000000` | Initial stack pointer for the new task. |
| `0x00C` | `TASK_CREATE_PRIORITY` | R/W | 32 | `0x00000000` | Priority for the new task. Bits [3:0] used; 0 = lowest, 15 = highest. |
| `0x010` | `TASK_CREATE_STACK_SIZE` | R/W | 32 | `0x00000000` | Stack size in bytes for the new task. |
| `0x014` | `TASK_CREATE_RESULT` | R | 32 | `0x00000000` | Result of task creation. Bits [7:0]: assigned task ID. Bit [31]: error flag (1 = failure). |
| `0x018` | `TASK_DELETE` | W | 32 | - | Delete task. Write the task ID to delete it. |
| `0x01C` | `TASK_SUSPEND` | W | 32 | - | Suspend task. Write the task ID to suspend it. |
| `0x020` | `TASK_RESUME` | W | 32 | - | Resume task. Write the task ID to resume it. |
| `0x024` | `TASK_STATUS` | R | 32 | `0x00000000` | Task status. Write task ID to `TCB_TASK_SELECT` first, then read here. See encoding below. |
| `0x028` | `CURRENT_TASK_ID` | R | 32 | `0x00000000` | ID of the currently running task. Bits [7:0]: task ID. |
| `0x02C` | `TASK_PRIORITY_SET` | W | 32 | - | Set task priority. Bits [7:0]: task ID. Bits [11:8]: new priority. |
| `0x030` | `TASK_YIELD` | W | 32 | - | Force task yield. Write any non-zero value to trigger a context switch to the next ready task. |

#### TASK_STATUS Encoding

| Bits | Field | Description |
|------|-------|-------------|
| [2:0] | `state` | Task state. `000` = IDLE, `001` = READY, `010` = RUNNING, `011` = BLOCKED, `100` = SUSPENDED, `101` = TERMINATED. |
| [6:3] | `priority` | Current priority of the task. |
| [7] | `valid` | 1 = task ID is valid (task exists). |
| [31:8] | Reserved | Reserved. |

---

### 5.2 Scheduler Control Registers (`0x1100_0100` - `0x1100_01FF`)

| Offset | Register Name | R/W | Width | Reset | Description |
|--------|--------------|-----|-------|-------|-------------|
| `0x100` | `SCHED_CTRL` | R/W | 32 | `0x00000000` | Scheduler control register. |
| `0x104` | `SCHED_STATUS` | R | 32 | `0x00000000` | Scheduler status register. |
| `0x108` | `TIME_SLICE_DEFAULT` | R/W | 32 | `0x00000064` | Default time slice in timer ticks (reset: 100). |
| `0x10C` | `TICK_COUNT` | R | 32 | `0x00000000` | System tick counter. Increments on each timer interrupt. |
| `0x110` | `TASK_COUNT` | R | 32 | `0x00000000` | Number of active tasks (all states except TERMINATED). |
| `0x114` | `READY_QUEUE_HEAD` | R | 32 | `0x00000000` | Task ID at the head of the ready queue. |

#### SCHED_CTRL Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | `sched_en` | R/W | `0` | Scheduler enable. 1 = scheduler is active and will perform context switches. |
| [2:1] | `policy` | R/W | `00` | Scheduling policy. `00` = Round-Robin, `01` = Priority-based preemptive, `10` = Priority with Round-Robin within same priority, `11` = Reserved. |
| [3] | `preempt_en` | R/W | `0` | Preemption enable. 1 = higher-priority tasks preempt lower-priority ones. |
| [31:4] | Reserved | - | `0` | Reserved. |

#### SCHED_STATUS Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | `active` | R | `0` | 1 = scheduler is currently active. |
| [1] | `ctx_switch` | R | `0` | 1 = context switch is in progress. |
| [2] | `idle` | R | `0` | 1 = no ready tasks; running idle task. |
| [7:3] | `ready_count` | R | `0` | Number of tasks in the READY state. |
| [31:8] | Reserved | - | `0` | Reserved. |

---

### 5.3 Semaphore Control Registers (`0x1100_0200` - `0x1100_02FF`)

| Offset | Register Name | R/W | Width | Reset | Description |
|--------|--------------|-----|-------|-------|-------------|
| `0x200` | `SEM_CREATE` | W | 32 | - | Create semaphore. Bits [15:0]: initial count. Write triggers creation. |
| `0x204` | `SEM_CREATE_RESULT` | R | 32 | `0x00000000` | Created semaphore ID. Bits [7:0]: sem ID. Bit [31]: error flag. |
| `0x208` | `SEM_DELETE` | W | 32 | - | Delete semaphore. Write semaphore ID. |
| `0x20C` | `SEM_WAIT` | W | 32 | - | Wait (decrement) on semaphore. Write semaphore ID. Blocks calling task if count is 0. |
| `0x210` | `SEM_POST` | W | 32 | - | Post (increment) semaphore. Write semaphore ID. Unblocks a waiting task if any. |
| `0x214` | `SEM_STATUS` | R | 32 | `0x00000000` | Semaphore status. Set `SEM_VALUE` first with target sem ID for reads. |
| `0x218` | `SEM_VALUE` | R/W | 32 | `0x00000000` | Write: select semaphore ID for status read. Read: current count of the selected semaphore. |

#### SEM_STATUS Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [15:0] | `count` | R | `0` | Current semaphore count. |
| [23:16] | `waiters` | R | `0` | Number of tasks blocked waiting on this semaphore. |
| [30:24] | Reserved | - | `0` | Reserved. |
| [31] | `valid` | R | `0` | 1 = semaphore ID is valid. |

---

### 5.4 Mutex Control Registers (`0x1100_0300` - `0x1100_03FF`)

| Offset | Register Name | R/W | Width | Reset | Description |
|--------|--------------|-----|-------|-------|-------------|
| `0x300` | `MTX_CREATE` | W | 32 | - | Create mutex. Write any value to trigger creation. |
| `0x304` | `MTX_CREATE_RESULT` | R | 32 | `0x00000000` | Created mutex ID. Bits [7:0]: mutex ID. Bit [31]: error flag. |
| `0x308` | `MTX_DELETE` | W | 32 | - | Delete mutex. Write mutex ID. |
| `0x30C` | `MTX_LOCK` | W | 32 | - | Lock mutex. Write mutex ID. Blocks calling task if already locked by another task. |
| `0x310` | `MTX_UNLOCK` | W | 32 | - | Unlock mutex. Write mutex ID. Only the owning task may unlock. |
| `0x314` | `MTX_STATUS` | R | 32 | `0x00000000` | Mutex status for the mutex ID last written to `MTX_LOCK` or `MTX_TRYLOCK`. |
| `0x318` | `MTX_TRYLOCK` | W | 32 | - | Try lock (non-blocking). Write mutex ID. Check `MTX_STATUS` for result. |

#### MTX_STATUS Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | `locked` | R | `0` | 1 = mutex is currently locked. |
| [8:1] | `owner` | R | `0` | Task ID of the mutex owner (valid only when locked = 1). |
| [16:9] | `waiters` | R | `0` | Number of tasks blocked waiting on this mutex. |
| [30:17] | Reserved | - | `0` | Reserved. |
| [31] | `valid` | R | `0` | 1 = mutex ID is valid. |

---

### 5.5 Message Queue Control Registers (`0x1100_0400` - `0x1100_04FF`)

| Offset | Register Name | R/W | Width | Reset | Description |
|--------|--------------|-----|-------|-------|-------------|
| `0x400` | `MQ_CREATE` | W | 32 | - | Create message queue. Write any value to trigger creation using parameters at `0x404` and `0x408`. |
| `0x404` | `MQ_CREATE_DEPTH` | R/W | 32 | `0x00000010` | Queue depth (number of messages). Default 16. |
| `0x408` | `MQ_CREATE_MSG_SIZE` | R/W | 32 | `0x00000004` | Message size in bytes. Default 4. Maximum 32. |
| `0x40C` | `MQ_CREATE_RESULT` | R | 32 | `0x00000000` | Created queue ID. Bits [7:0]: queue ID. Bit [31]: error flag. |
| `0x410` | `MQ_DELETE` | W | 32 | - | Delete queue. Write queue ID. |
| `0x414` | `MQ_SEND` | W | 32 | - | Send message. Write queue ID. Data must be pre-loaded in `MQ_SEND_DATA`. |
| `0x418` | `MQ_SEND_DATA` | W | 32 | - | Message data word to send. For messages larger than 4 bytes, write multiple times before triggering `MQ_SEND`. |
| `0x41C` | `MQ_RECEIVE` | W | 32 | - | Receive message. Write queue ID. Result available in `MQ_RECEIVE_DATA`. Blocks if queue is empty. |
| `0x420` | `MQ_RECEIVE_DATA` | R | 32 | `0x00000000` | Received message data. Read after `MQ_RECEIVE` completes. |
| `0x424` | `MQ_STATUS` | R | 32 | `0x00000000` | Queue status for the last accessed queue ID. |

#### MQ_STATUS Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [7:0] | `count` | R | `0` | Number of messages currently in the queue. |
| [15:8] | `free_space` | R | `0` | Number of free message slots remaining. |
| [23:16] | `msg_size` | R | `0` | Configured message size in bytes. |
| [30:24] | Reserved | - | `0` | Reserved. |
| [31] | `valid` | R | `0` | 1 = queue ID is valid. |

---

### 5.6 TCB Access Registers (`0x1100_0500` - `0x1100_05FF`)

These registers provide read access to the Task Control Block (TCB) of any task. First write the target task ID to `TCB_TASK_SELECT`, then read the desired fields.

| Offset | Register Name | R/W | Width | Reset | Description |
|--------|--------------|-----|-------|-------|-------------|
| `0x500` | `TCB_TASK_SELECT` | R/W | 32 | `0x00000000` | Write target task ID (bits [7:0]) to select a TCB for inspection. |
| `0x504` | `TCB_TASK_ID` | R | 32 | `0x00000000` | Selected task's ID. Mirrors the value written to `TCB_TASK_SELECT` if valid. |
| `0x508` | `TCB_STATE` | R | 32 | `0x00000000` | Selected task's state. Encoding: `0` = IDLE, `1` = READY, `2` = RUNNING, `3` = BLOCKED, `4` = SUSPENDED, `5` = TERMINATED. |
| `0x50C` | `TCB_PRIORITY` | R | 32 | `0x00000000` | Selected task's current priority. Bits [3:0]. |
| `0x510` | `TCB_SP` | R | 32 | `0x00000000` | Selected task's saved stack pointer. |
| `0x514` | `TCB_PC` | R | 32 | `0x00000000` | Selected task's saved program counter (resume address). |
| `0x518` | `TCB_TIME_SLICE` | R | 32 | `0x00000000` | Selected task's remaining time slice in ticks. |
| `0x51C` | `TCB_BLOCKED_ON` | R | 32 | `0x00000000` | Resource the task is blocked on. See encoding below. |
| `0x520` | `TCB_REG_SAVE_ADDR` | R | 32 | `0x00000000` | Base address of the register save area in memory for this task. |

#### TCB_BLOCKED_ON Encoding

| Bits | Field | Description |
|------|-------|-------------|
| [3:0] | `type` | Block type. `0000` = not blocked, `0001` = semaphore, `0010` = mutex, `0011` = message queue receive, `0100` = message queue send, `0101` = sleep/delay, `0110` = thread join. |
| [11:4] | `resource_id` | ID of the blocking resource (semaphore ID, mutex ID, queue ID, or target thread ID). |
| [31:12] | Reserved | Reserved. |

---

## 6. POSIX Control Register Address Map (Base: `0x1200_0000`)

The POSIX hardware layer translates POSIX-like system calls into hardware RTOS operations and peripheral I/O. Registers are accessed via memory-mapped I/O.

---

### 6.1 Syscall Interface Registers (`0x1200_0000` - `0x1200_00FF`)

The syscall interface provides a register-based mechanism for invoking POSIX-compatible system calls. Software writes the syscall number and arguments, then triggers execution by writing to `SYSCALL_NUM`. The hardware translates supported syscalls into corresponding RTOS or peripheral operations.

| Offset | Register Name | R/W | Width | Reset | Description |
|--------|--------------|-----|-------|-------|-------------|
| `0x000` | `SYSCALL_NUM` | R/W | 32 | `0x00000000` | Syscall number. Writing this register triggers syscall execution. |
| `0x004` | `SYSCALL_ARG0` | R/W | 32 | `0x00000000` | Argument 0 (corresponds to register `a0`). |
| `0x008` | `SYSCALL_ARG1` | R/W | 32 | `0x00000000` | Argument 1 (corresponds to register `a1`). |
| `0x00C` | `SYSCALL_ARG2` | R/W | 32 | `0x00000000` | Argument 2 (corresponds to register `a2`). |
| `0x010` | `SYSCALL_ARG3` | R/W | 32 | `0x00000000` | Argument 3 (corresponds to register `a3`). |
| `0x014` | `SYSCALL_ARG4` | R/W | 32 | `0x00000000` | Argument 4 (corresponds to register `a4`). |
| `0x018` | `SYSCALL_ARG5` | R/W | 32 | `0x00000000` | Argument 5 (corresponds to register `a5`). |
| `0x01C` | `SYSCALL_RET` | R | 32 | `0x00000000` | Return value of the last completed syscall. |
| `0x020` | `SYSCALL_STATUS` | R | 32 | `0x00000000` | Syscall status register. |
| `0x024` | `SYSCALL_ERRNO` | R | 32 | `0x00000000` | Error number (POSIX errno) from the last syscall. 0 = no error. |

#### SYSCALL_STATUS Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | `busy` | R | `0` | 1 = syscall is currently being processed. Software must poll or wait for this to clear before reading results. |
| [1] | `done` | R | `0` | 1 = syscall has completed. Cleared when a new syscall is triggered. |
| [2] | `error` | R | `0` | 1 = last syscall returned an error. Check `SYSCALL_ERRNO` for the error code. |
| [31:3] | Reserved | - | `0` | Reserved. |

#### Supported Syscall Numbers

| Number | Name | Arguments | Description |
|--------|------|-----------|-------------|
| `1` | `write` | `ARG0` = fd, `ARG1` = buf_addr, `ARG2` = count | Write to a file descriptor. |
| `2` | `read` | `ARG0` = fd, `ARG1` = buf_addr, `ARG2` = count | Read from a file descriptor. |
| `3` | `open` | `ARG0` = peripheral_type, `ARG1` = config | Open a file descriptor. |
| `4` | `close` | `ARG0` = fd | Close a file descriptor. |
| `10` | `pthread_create` | `ARG0` = entry, `ARG1` = stack, `ARG2` = priority | Create a thread. |
| `11` | `pthread_exit` | `ARG0` = retval | Exit current thread. |
| `12` | `pthread_join` | `ARG0` = thread_id | Join a thread. |
| `20` | `sem_init` | `ARG0` = initial_value | Initialize a semaphore. |
| `21` | `sem_wait` | `ARG0` = sem_id | Wait on a semaphore. |
| `22` | `sem_post` | `ARG0` = sem_id | Post a semaphore. |
| `30` | `usleep` | `ARG0` = microseconds | Sleep for specified microseconds. |

---

### 6.2 File Descriptor Table Registers (`0x1200_0100` - `0x1200_01FF`)

The hardware file descriptor (FD) table maps integer file descriptors to physical peripherals. FD 0 (stdin), FD 1 (stdout), and FD 2 (stderr) are pre-assigned to UART by default.

| Offset | Register Name | R/W | Width | Reset | Description |
|--------|--------------|-----|-------|-------|-------------|
| `0x100` | `FD_OPEN` | W | 32 | - | Open a new file descriptor. Bits [3:0]: peripheral type. Bits [15:4]: peripheral config. |
| `0x104` | `FD_CLOSE` | W | 32 | - | Close a file descriptor. Write the FD number to close. |
| `0x108` | `FD_READ` | R/W | 32 | `0x00000000` | Read from FD. Write: set target FD number. Read: returns read data byte. |
| `0x10C` | `FD_WRITE` | W | 32 | - | Write to FD. Bits [7:0]: data byte. Bits [15:8]: FD number. |
| `0x110` | `FD_STATUS` | R | 32 | `0x00000000` | FD status for the last accessed FD. |
| `0x114` | `FD_TABLE_BASE` | R | 32 | `0x00000000` | Base address of the internal FD table (for debug/direct access). |
| `0x118` | `FD_COUNT` | R | 32 | `0x00000003` | Number of currently open file descriptors. Reset default is 3 (stdin, stdout, stderr). |
| `0x11C` | `FD_MAX` | R | 32 | `0x00000010` | Maximum number of supported file descriptors. Fixed at 16. |

#### FD_OPEN Peripheral Type Encoding

| Type [3:0] | Peripheral | Description |
|------------|-----------|-------------|
| `0x0` | None | Reserved / invalid. |
| `0x1` | UART | Serial port. Config bits select baud rate index. |
| `0x2` | GPIO | GPIO pin. Config bits select pin number. |
| `0x3` | HyperRAM | Memory-mapped file. Config bits select offset. |
| `0x4`-`0xF` | Reserved | Reserved for future peripherals. |

#### FD_STATUS Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [0] | `open` | R | `0` | 1 = file descriptor is open. |
| [1] | `readable` | R | `0` | 1 = file descriptor supports read operations. |
| [2] | `writable` | R | `0` | 1 = file descriptor supports write operations. |
| [3] | `eof` | R | `0` | 1 = end-of-file or end-of-stream condition. |
| [4] | `error` | R | `0` | 1 = I/O error occurred on this FD. |
| [7:5] | Reserved | - | `0` | Reserved. |
| [11:8] | `periph_type` | R | `0` | Peripheral type this FD is bound to. |
| [31:12] | Reserved | - | `0` | Reserved. |

---

### 6.3 Process/Thread Control Registers (`0x1200_0200` - `0x1200_02FF`)

These registers provide POSIX-compatible thread management by translating operations into RTOS task management calls.

| Offset | Register Name | R/W | Width | Reset | Description |
|--------|--------------|-----|-------|-------|-------------|
| `0x200` | `THREAD_CREATE` | W | 32 | - | Create a new thread. Write triggers creation using arguments from syscall ARG registers. Internally maps to RTOS `TASK_CREATE`. |
| `0x204` | `THREAD_EXIT` | W | 32 | - | Exit the current thread. Bits [31:0]: exit/return value. Maps to RTOS `TASK_DELETE` on the current task. |
| `0x208` | `THREAD_JOIN` | W | 32 | - | Join (wait for) a thread. Write the thread ID. Blocks the calling task until the target thread terminates. |
| `0x20C` | `THREAD_DETACH` | W | 32 | - | Detach a thread. Write the thread ID. Detached threads release resources automatically on exit. |
| `0x210` | `THREAD_SELF` | R | 32 | `0x00000000` | Get current thread ID. Returns the RTOS task ID of the calling thread. |
| `0x214` | `THREAD_STATUS` | R | 32 | `0x00000000` | Thread status for the last referenced thread. |

#### THREAD_STATUS Bit-Field Definition

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| [2:0] | `state` | R | `0` | Thread state. Same encoding as RTOS task state: `0` = IDLE, `1` = READY, `2` = RUNNING, `3` = BLOCKED, `4` = SUSPENDED, `5` = TERMINATED. |
| [3] | `detached` | R | `0` | 1 = thread is detached. |
| [4] | `joinable` | R | `0` | 1 = another thread is waiting to join this thread. |
| [12:5] | `thread_id` | R | `0` | Thread/task ID. |
| [31:13] | Reserved | - | `0` | Reserved. |

---

## Appendix A: Interrupt Wiring

| PLIC Source | IRQ Number | Source | Description |
|-------------|-----------|--------|-------------|
| 0 | - | Reserved | No interrupt (hardwired to 0) |
| 1 | IRQ1 | UART | UART interrupt (any enabled UART event) |
| 2 | IRQ2 | GPIO | GPIO interrupt (any enabled GPIO pin event) |
| 3 | IRQ3 | HW RTOS | RTOS event (task completion, sync primitive event) |
| 4 | IRQ4 | POSIX Layer | POSIX syscall completion |
| 5-15 | IRQ5-15 | Reserved | Reserved for future use |

**Note:** The PLIC supports 16 interrupt sources (`irq_sources[15:0]`), with source 0 reserved (hardwired to 0). Bit 1 = UART IRQ, Bit 2 = GPIO IRQ.

---

## Appendix B: Reset Values Summary

| Register / Region | Reset Behavior |
|-------------------|---------------|
| Instruction Memory (BRAM) | Loaded from external source during initialization |
| Data Memory (BRAM) | Zero-initialized |
| All UART registers | As specified per register; TX/RX disabled at reset |
| GPIO_DIR | `0x00000000` (all inputs) |
| PLIC priorities | `0` (all disabled) |
| PLIC enables | `0` (all disabled) |
| CLINT mtimecmp | `0xFFFFFFFF_FFFFFFFF` (no spurious timer interrupt) |
| CLINT mtime | `0x00000000_00000000` |
| mstatus | `0x00001800` (MPP = M-mode) |
| mtvec | `0x00000000` |
| RTOS scheduler | Disabled at reset |
| POSIX layer | Disabled at reset |
| FD table | FD 0/1/2 mapped to UART |

---

## Appendix C: Address Space Utilization Notes

1. **Instruction Memory** is mapped at address `0x0000_0000` so that the reset vector (`mtvec` default) points to the start of instruction memory.
2. **Data Memory** is placed at `0x0001_0000` (immediately following IMEM in the address space) providing clear separation from instruction memory while keeping the two close together for efficient address decoding.
3. **CLINT** at `0x0200_0000` follows the RISC-V standard CLINT base address. The 64 KB allocation accommodates standard CLINT register offsets (up to `0xBFFC`).
4. **PLIC** at `0x0C00_0000` follows the RISC-V standard PLIC base address. The compact 4 KB allocation supports 16 interrupt sources.
5. **UART** and **GPIO** at `0x1000_0000` and `0x1000_0100` are placed contiguously in the peripheral I/O region. Each uses only 256 B, reflecting the actual register footprint.
6. **RTOS** and **POSIX** control registers at `0x1100_0000` and `0x1200_0000` are placed adjacent to the peripheral region, providing hardware acceleration interfaces close to the peripherals they control.
7. **HyperRAM** at `0x2000_0000` allows up to 256 MB of external memory for data, heap, or code overlay.
8. All unused address ranges return a bus error (AXI DECERR response) on access.
9. **Instruction Memory** is directly connected to the CPU fetch port and is not routed through the AXI4 interconnect. The AXI4 interconnect handles data-path access to all other regions.
