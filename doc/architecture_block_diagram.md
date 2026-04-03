# VSync Architecture Block Diagram

## アーキテクチャ ブロック図ドキュメント

| 項目 | 詳細 |
|------|------|
| Document ID | ARCH-BD-001 |
| バージョン | 2.0 |
| 日付 | 2026-02-21 |
| プロジェクト | VSync - RISC-V RV32IM Processor with Hardware RTOS |
| ターゲットデバイス | Xilinx Spartan UltraScale+ FPGA |
| 言語 | SystemVerilog (IEEE 1800-2017) |

---

## 1. システム概要 (System Overview)

VSync は FPGA 上に実装するハードウェア RTOS 内蔵 RISC-V RV32IM プロセッサである。
5段パイプライン CPU コア、ハードウェア RTOS エンジン、POSIX ハードウェア抽象化層、
および AXI4/APB バス経由で接続されるペリフェラルから構成される。

### 主要機能
- RISC-V RV32IM (Integer + Multiply/Divide) 5段パイプライン
- ハードウェア RTOS: 優先度ベースプリエンプティブスケジューリング (最大16タスク)
- POSIX 互換ハードウェア層 (ハードウェアによるシステムコールディスパッチ)
- AXI4 → APB バス階層構造
- BRAM ベース命令メモリ (64KB) およびデータメモリ (16KB)
- 外部 HyperRAM サポート
- PLIC + CLINT 割込アーキテクチャ

---

## 2. システム全体ブロック図 (System-Level Block Diagram)

以下の ASCII ブロック図は VSync SoC の全モジュールとその接続関係を示す。
Harvard アーキテクチャを採用し、命令フェッチとデータアクセスを分離している。

```
                                   vsync_top
 ┌──────────────────────────────────────────────────────────────────────────────────────────┐
 │                                                                                          │
 │  ┌─────────────────────────────────────────────────────────────────┐                      │
 │  │                    rv32im_core (5-Stage Pipeline)               │                      │
 │  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                 │                      │
 │  │  │  IF  │→│  ID  │→│  EX  │→│ MEM  │→│  WB  │                 │                      │
 │  │  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘                 │                      │
 │  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │                      │
 │  │  │ Reg File │ │   ALU    │ │  M-Ext   │ │   CSR Unit       │  │                      │
 │  │  │ (x0-x31) │ │          │ │ (MUL/DIV)│ │ (mstatus,mepc,..)│  │                      │
 │  │  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘  │                      │
 │  │  ┌────────────────────┐  ┌────────────────────┐               │                      │
 │  │  │   Hazard Unit      │  │  Branch Predictor  │               │                      │
 │  │  │ (fwd/stall/flush)  │  │  (static/dynamic)  │               │                      │
 │  │  └────────────────────┘  └────────────────────┘               │                      │
 │  └──────┬──────────────┬──────────────┬──────────────┬───────────┘                      │
 │         │imem i/f      │data i/f      │irq i/f       │rtos/posix i/f                    │
 │         │              │              │              │                                    │
 │         ▼              ▼              │              ▼                                    │
 │  ┌────────────┐ ┌────────────┐       │       ┌──────────────┐   ┌──────────────────┐    │
 │  │ bram_imem  │ │axi4_master │       │       │   hw_rtos    │   │ posix_hw_layer   │    │
 │  │ (64KB)     │ │            │       │       │              │◄──│                  │    │
 │  │ BRAM Infer │ │ AW/W/B/    │       │       │ Scheduler    │   │ Syscall Dispatch │    │
 │  │ readmemh   │ │ AR/R ch    │       │       │ TCB Memory   │   │ FD Table Mgmt    │    │
 │  └────────────┘ └──────┬─────┘       │       │ Context Sw   │   │ Periph Access    │    │
 │                        │              │       │ Semaphore    │   └────────┬─────────┘    │
 │                        │              │       │ Mutex        │            │AXI4 Slave     │
 │                        │              │       │ MsgQueue     │            │               │
 │                        │              │       └──────┬───────┘            │               │
 │                        │              │              │AXI4 Slave          │               │
 │                        ▼              │              │                    │               │
 │  ┌─────────────────────────────────────────────────────────────────────────────────┐     │
 │  │                        axi4_interconnect                                        │     │
 │  │                    (1 Master x 5 Slaves, Address Decode)                        │     │
 │  │                                                                                 │     │
 │  │  Slave 0        Slave 1          Slave 2           Slave 3       Slave 4        │     │
 │  │  bram_dmem      hyperram_ctrl    axi4_apb_bridge   hw_rtos       posix_hw_layer │     │
 │  └──┬──────────────┬────────────────┬─────────────────┬──────────────┬─────────────┘     │
 │     │              │                │                  │              │                    │
 │     ▼              ▼                ▼                  │              │                    │
 │  ┌──────────┐ ┌──────────────┐ ┌──────────────┐       │              │                    │
 │  │bram_dmem │ │hyperram_ctrl │ │axi4_apb_     │       │              │                    │
 │  │(16KB)    │ │              │ │   bridge      │       │              │                    │
 │  │BRAM Infer│ │ CS#,CK,CK#  │ │              │       │              │                    │
 │  │          │ │ RWDS,DQ[7:0] │ │ AXI4→APB     │       │              │                    │
 │  └──────────┘ └──────┬───────┘ └──────┬───────┘       │              │                    │
 │                      │ HyperRAM       │ APB Master     │              │                    │
 │                      │ Pins           ▼                │              │                    │
 │                      │   ┌─────────────────────────────────────────────────────────┐      │
 │                      │   │              APB Bus (Peripheral Bus)                   │      │
 │                      │   │                                                         │      │
 │                      │   │  PSEL[0]     PSEL[1]     PSEL[2]     PSEL[3]           │      │
 │                      │   └──┬───────────┬───────────┬───────────┬─────────────────┘      │
 │                      │      │           │           │           │                         │
 │                      │      ▼           ▼           ▼           ▼                         │
 │                      │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐                  │
 │                      │  │uart_apb │ │gpio_apb │ │  plic   │ │  clint  │                  │
 │                      │  │         │ │         │ │         │ │         │                  │
 │                      │  │TX FIFO  │ │Dir Ctrl │ │Priority │ │mtime    │                  │
 │                      │  │RX FIFO  │ │Int Gen  │ │Claim/   │ │mtimecmp │                  │
 │                      │  │Baud Gen │ │         │ │Complete │ │msip     │                  │
 │                      │  └──┬──┬───┘ └──┬──┬───┘ └────┬────┘ └───┬──┬─┘                  │
 │                      │     │  │        │  │          │          │  │                      │
 │                      │     │  │uart_irq│  │gpio_irq  │ext_irq   │  │timer_irq            │
 │                      │     │  │        │  │          │          │  │sw_irq                │
 │                      │     │  │        │  │     ┌────┘     ┌───┘  │                      │
 │                      │     │  │        │  │     │          │      │                      │
 │                      │     │  └────────│──│─────│──────────│──────│──────→ rv32im_core    │
 │                      │     │           │  └─────│──────────│──────│──────→ (irq inputs)   │
 │                      │     │           │        │          │      └──────→                │
 │                      │     │           │        │          │                              │
 │                      │     │           │        │          │timer_tick                    │
 │                      │     │           │        │          └──────────────→ hw_rtos       │
 │                      │     │           │        │                                         │
 │  External Pins       │     │           │        │                                         │
 │  ══════════════      │     │           │        │                                         │
 │     uart_tx  ◄───────│─────┘           │        │                                         │
 │     uart_rx  ────────│─────────────────│────►   │                                         │
 │     gpio[31:0] ◄────►│─────────────────┘        │                                         │
 │     hyper_cs_n ◄─────┘                          │                                         │
 │     hyper_ck   ◄────────                        │                                         │
 │     hyper_ck_n ◄────────                        │                                         │
 │     hyper_rwds ◄───────►                        │                                         │
 │     hyper_dq[7:0]◄────►                         │                                         │
 │     hyper_rst_n ◄──────                         │                                         │
 │     clk_in_p  ──────────────────────────────────────────────────────────►                 │
 │     clk_in_n  ──────────────────────────────────────────────────────────►                 │
 │     rst_n     ──────────────────────────────────────────────────────────►                 │
 └──────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. アドレスマップ (Memory Address Map)

`vsync_pkg.sv` に定義されたアドレスマップに基づく全モジュールのアドレス割り当て。

| モジュール         | ベースアドレス     | エンドアドレス     | サイズ   | バスタイプ    | 備考                        |
|--------------------|-------------------:|-------------------:|---------:|---------------|-----------------------------|
| bram_imem          | `0x0000_0000`      | `0x0000_FFFF`      | 64 KB    | 直結 (Harvard) | 命令メモリ、CPUから直接接続  |
| bram_dmem          | `0x0001_0000`      | `0x0001_3FFF`      | 16 KB    | AXI4 Slave    | データメモリ                 |
| clint              | `0x0200_0000`      | `0x0200_FFFF`      | 64 KB    | APB Slave     | タイマ/ソフトウェア割込      |
| plic               | `0x0C00_0000`      | `0x0C00_0FFF`      | 4 KB     | APB Slave     | 外部割込コントローラ         |
| uart_apb           | `0x1000_0000`      | `0x1000_00FF`      | 256 B    | APB Slave     | UART TX/RX FIFO              |
| gpio_apb           | `0x1000_0100`      | `0x1000_01FF`      | 256 B    | APB Slave     | GPIO 方向制御/割込           |
| hw_rtos            | `0x1100_0000`      | `0x1100_FFFF`      | 64 KB    | AXI4 Slave    | ハードウェアRTOS制御レジスタ |
| posix_hw_layer     | `0x1200_0000`      | `0x1200_FFFF`      | 64 KB    | AXI4 Slave    | POSIX 層 デバッグ/設定       |
| hyperram_ctrl      | `0x2000_0000`      | `0x2FFF_FFFF`      | 256 MB   | AXI4 Slave    | 外部HyperRAM                 |

**アドレスデコード方式:** `axi4_interconnect` 内でアドレス上位ビットにより宛先スレーブを選択する。
APB ペリフェラルへのアクセスは `axi4_apb_bridge` を経由し、APB バス上でアドレスデコードされる。

**posix_hw_layer のアクセス方式について:**
posix_hw_layer は ECALL 命令によるシステムコール経由で主にアクセスされる。
AXI4 Slave インタフェースは FD テーブルや統計情報レジスタへのデバッグ/設定アクセス用である。

---

## 4. モジュール間接続詳細 (Module Interconnection Details)

### 4.1 CPU コア ←→ 命令メモリ (Harvard Architecture, 直結)

命令フェッチは AXI4 バスを経由せず、`bram_imem` に直接接続される。
これにより1サイクルの命令フェッチレイテンシを実現する。

```
  rv32im_core                          bram_imem
  ┌──────────┐                        ┌──────────────┐
  │          │── imem_addr[15:0]  ──→│ addr[15:0]   │
  │   IF     │◄─ imem_rdata[31:0] ───│ rdata[31:0]  │
  │  Stage   │── imem_en          ──→│ en           │
  │          │                        │              │
  └──────────┘                        │  64KB BRAM   │
                                      │  (Single Port│
                                      │   Read Only) │
                                      └──────────────┘
```

| 信号名         | 方向          | ビット幅 | 説明                                    |
|----------------|---------------|----------|-----------------------------------------|
| `imem_addr`    | core → imem   | [15:0]   | 命令アドレス (バイトアドレス, 64KB空間)  |
| `imem_rdata`   | imem → core   | [31:0]   | 命令データ読み出し                       |
| `imem_en`      | core → imem   | 1        | 命令メモリイネーブル                     |

### 4.2 CPU コア ←→ AXI4 Master

CPU コアの MEM ステージからのロード/ストア要求を AXI4 プロトコルに変換する。

```
  rv32im_core                          axi4_master
  ┌──────────┐                        ┌──────────────┐
  │          │── mem_addr[31:0]   ──→│              │──→ AXI4 AW/AR
  │   MEM    │── mem_wdata[31:0]  ──→│  Protocol    │──→ AXI4 W
  │  Stage   │◄─ mem_rdata[31:0]  ───│  Converter   │◄── AXI4 R
  │          │── mem_write        ──→│              │◄── AXI4 B
  │          │── mem_read         ──→│              │
  │          │── mem_size[2:0]    ──→│              │
  │          │◄─ mem_ready        ───│              │
  │          │◄─ mem_error        ───│              │
  └──────────┘                        └──────────────┘
```

| 信号名       | 方向            | ビット幅 | 説明                                      |
|--------------|-----------------|----------|-------------------------------------------|
| `mem_addr`   | core → master   | [31:0]   | データアクセスアドレス                     |
| `mem_wdata`  | core → master   | [31:0]   | 書き込みデータ                             |
| `mem_rdata`  | master → core   | [31:0]   | 読み出しデータ                             |
| `mem_write`  | core → master   | 1        | 書き込みイネーブル                         |
| `mem_read`   | core → master   | 1        | 読み出しイネーブル                         |
| `mem_size`   | core → master   | [2:0]    | アクセスサイズ (byte/half/word, funct3対応) |
| `mem_ready`  | master → core   | 1        | データ転送完了 (パイプラインストール解除)   |
| `mem_error`  | master → core   | 1        | バスエラー応答                             |

### 4.3 AXI4 Interconnect トポロジ

1マスタ、5スレーブ構成。アドレスデコードによりスレーブを選択する。

```
                         axi4_master
                             │
                     AXI4 Master Port (M0)
                             │
                             ▼
  ┌────────────────────────────────────────────────────────────────────┐
  │                      axi4_interconnect                            │
  │                                                                    │
  │  Address Decode Logic:                                             │
  │  ┌─────────────────────────────────────────────────────────────┐   │
  │  │ if addr in [0x0001_0000, 0x0001_3FFF] → Slave 0 (bram_dmem)│   │
  │  │ if addr in [0x2000_0000, 0x2FFF_FFFF] → Slave 1 (hyperram) │   │
  │  │ if addr in APB range                  → Slave 2 (apb_bridge)│   │
  │  │ if addr in [0x1100_0000, 0x1100_FFFF] → Slave 3 (hw_rtos)  │   │
  │  │ if addr in [0x1200_0000, 0x1200_FFFF] → Slave 4 (posix)    │   │
  │  │ else → DECERR                                                │   │
  │  └─────────────────────────────────────────────────────────────┘   │
  │                                                                    │
  │  S0            S1              S2              S3          S4       │
  └──┬─────────────┬───────────────┬───────────────┬──────────┬────────┘
     │             │               │               │          │
     ▼             ▼               ▼               ▼          ▼
  ┌────────┐  ┌──────────┐  ┌────────────┐  ┌─────────┐ ┌───────────┐
  │bram_   │  │hyperram_ │  │axi4_apb_   │  │ hw_rtos │ │posix_hw_  │
  │dmem    │  │ctrl      │  │bridge      │  │ (AXI4   │ │layer      │
  │(AXI4   │  │(AXI4     │  │            │  │  Slave) │ │(AXI4      │
  │ Slave) │  │ Slave)   │  │AXI4→APB    │  │         │ │ Slave)    │
  └────────┘  └──────────┘  └─────┬──────┘  └─────────┘ └───────────┘
                                  │
                                  │ APB Master
                                  ▼
```

**AXI4 Interconnect アドレスデコード規則:**

| スレーブ番号 | 宛先モジュール   | アドレス範囲                        | デコード条件                          |
|:------------:|------------------|--------------------------------------|---------------------------------------|
| S0           | bram_dmem        | `0x0001_0000` - `0x0001_3FFF`        | `addr[31:16] == 16'h0001`             |
| S1           | hyperram_ctrl    | `0x2000_0000` - `0x2FFF_FFFF`        | `addr[31:28] == 4'h2`                 |
| S2           | axi4_apb_bridge  | CLINT/PLIC/UART/GPIO アドレス空間    | APB ペリフェラル範囲に一致            |
| S3           | hw_rtos          | `0x1100_0000` - `0x1100_FFFF`        | `addr[31:16] == 16'h1100`             |
| S4           | posix_hw_layer   | `0x1200_0000` - `0x1200_FFFF`        | `addr[31:16] == 16'h1200`             |

### 4.4 AXI4-to-APB Bridge ←→ APB ペリフェラル

AXI4 バスから APB バスへのプロトコル変換を行い、低速ペリフェラルに接続する。

```
  axi4_apb_bridge
  ┌──────────────────────┐
  │ AXI4 Slave I/F       │
  │         │             │
  │  ┌──────┴──────┐      │
  │  │ Protocol    │      │
  │  │ Converter   │      │
  │  │ AXI4→APB    │      │
  │  └──────┬──────┘      │
  │         │ APB Master  │
  └─────────┼─────────────┘
            │
            ├──── PSEL[0] ──────►┌──────────┐  Base: 0x1000_0000  Size: 256B
            │                    │ uart_apb │
            │                    └──────────┘
            │
            ├──── PSEL[1] ──────►┌──────────┐  Base: 0x1000_0100  Size: 256B
            │                    │ gpio_apb │
            │                    └──────────┘
            │
            ├──── PSEL[2] ──────►┌──────────┐  Base: 0x0C00_0000  Size: 4KB
            │                    │   plic   │
            │                    └──────────┘
            │
            └──── PSEL[3] ──────►┌──────────┐  Base: 0x0200_0000  Size: 64KB
                                 │  clint   │
                                 └──────────┘
```

---

## 5. AXI4 バス信号一覧 (AXI4 Bus Signal Details)

`vsync_pkg.sv` で定義されたパラメータに基づく AXI4 信号仕様。

### 5.1 AXI4 パラメータ

| パラメータ      | 値   | 説明                        |
|-----------------|------|-----------------------------|
| `AXI_ADDR_W`   | 32   | アドレス幅                  |
| `AXI_DATA_W`   | 32   | データ幅                    |
| `AXI_STRB_W`   | 4    | ストローブ幅 (DATA_W / 8)  |
| `AXI_ID_W`     | 4    | トランザクション ID 幅      |
| `AXI_LEN_W`    | 8    | バースト長フィールド幅      |

### 5.2 AXI4 全チャネル信号テーブル

| Channel | Signal    | Width | Direction (M→S) | 説明                                   |
|---------|-----------|-------|------------------|----------------------------------------|
| **AW**  | `awid`    | 4     | M→S              | Write トランザクション ID              |
|         | `awaddr`  | 32    | M→S              | 書き込みアドレス                       |
|         | `awlen`   | 8     | M→S              | バースト長 (転送数 - 1)                |
|         | `awsize`  | 3     | M→S              | 転送サイズ (バイト単位, log2)          |
|         | `awburst` | 2     | M→S              | バーストタイプ (FIXED/INCR/WRAP)       |
|         | `awlock`  | 1     | M→S              | ロックタイプ                           |
|         | `awcache` | 4     | M→S              | メモリタイプ                           |
|         | `awprot`  | 3     | M→S              | プロテクションタイプ                   |
|         | `awvalid` | 1     | M→S              | AW チャネル有効                        |
|         | `awready` | 1     | S→M              | AW チャネルレディ                      |
| **W**   | `wdata`   | 32    | M→S              | 書き込みデータ                         |
|         | `wstrb`   | 4     | M→S              | 書き込みストローブ (バイトイネーブル)  |
|         | `wlast`   | 1     | M→S              | バースト最終転送                       |
|         | `wvalid`  | 1     | M→S              | W チャネル有効                         |
|         | `wready`  | 1     | S→M              | W チャネルレディ                       |
| **B**   | `bid`     | 4     | S→M              | 応答トランザクション ID                |
|         | `bresp`   | 2     | S→M              | 書き込み応答 (OKAY/EXOKAY/SLVERR/DECERR) |
|         | `bvalid`  | 1     | S→M              | B チャネル有効                         |
|         | `bready`  | 1     | M→S              | B チャネルレディ                       |
| **AR**  | `arid`    | 4     | M→S              | Read トランザクション ID               |
|         | `araddr`  | 32    | M→S              | 読み出しアドレス                       |
|         | `arlen`   | 8     | M→S              | バースト長                             |
|         | `arsize`  | 3     | M→S              | 転送サイズ                             |
|         | `arburst` | 2     | M→S              | バーストタイプ                         |
|         | `arlock`  | 1     | M→S              | ロックタイプ                           |
|         | `arcache` | 4     | M→S              | メモリタイプ                           |
|         | `arprot`  | 3     | M→S              | プロテクションタイプ                   |
|         | `arvalid` | 1     | M→S              | AR チャネル有効                        |
|         | `arready` | 1     | S→M              | AR チャネルレディ                      |
| **R**   | `rid`     | 4     | S→M              | 読み出しトランザクション ID            |
|         | `rdata`   | 32    | S→M              | 読み出しデータ                         |
|         | `rresp`   | 2     | S→M              | 読み出し応答                           |
|         | `rlast`   | 1     | S→M              | バースト最終転送                       |
|         | `rvalid`  | 1     | S→M              | R チャネル有効                         |
|         | `rready`  | 1     | M→S              | R チャネルレディ                       |

---

## 6. APB バス ペリフェラル接続 (APB Bus Peripheral Connections)

### 6.1 APB バス共通信号

| 信号名     | 方向              | ビット幅 | 説明                              |
|------------|-------------------|----------|-----------------------------------|
| `paddr`    | bridge → periph   | [31:0]   | APB アドレス                      |
| `psel`     | bridge → periph   | 1        | ペリフェラルセレクト (各1本)      |
| `penable`  | bridge → periph   | 1        | APB イネーブル (2nd cycle)        |
| `pwrite`   | bridge → periph   | 1        | 書き込み方向 (1=Write, 0=Read)    |
| `pwdata`   | bridge → periph   | [31:0]   | 書き込みデータ                    |
| `prdata`   | periph → bridge   | [31:0]   | 読み出しデータ                    |
| `pready`   | periph → bridge   | 1        | ペリフェラルレディ                |
| `pslverr`  | periph → bridge   | 1        | スレーブエラー応答                |

### 6.2 APB ペリフェラルセレクト

| ペリフェラル | psel 信号       | アドレス範囲                        | サイズ  |
|:------------:|-----------------|--------------------------------------|---------|
| uart_apb     | `psel_uart`     | `0x1000_0000` - `0x1000_00FF`        | 256 B   |
| gpio_apb     | `psel_gpio`     | `0x1000_0100` - `0x1000_01FF`        | 256 B   |
| plic         | `psel_plic`     | `0x0C00_0000` - `0x0C00_0FFF`        | 4 KB    |
| clint        | `psel_clint`    | `0x0200_0000` - `0x0200_FFFF`        | 64 KB   |

---

## 7. 割込信号ルーティング (Interrupt Signal Routing)

割込は3系統: 外部割込 (PLIC 経由)、タイマ割込 (CLINT)、ソフトウェア割込 (CLINT)。
RISC-V Privileged Specification v1.12 に準拠する。

### 7.1 割込経路ブロック図

```
  割込ソース                    割込コントローラ                CPUコア
  ────────                    ────────────                   ────────

  uart_apb ── uart_irq ──┐
                          ├──→ ┌──────────┐
  gpio_apb ── gpio_irq ──┘    │   PLIC   │── external_irq ──→ rv32im_core
  (将来:                  ───→ │          │                    (CSR: mip.MEIP)
   QSPI, I2C)                 └──────────┘

                               ┌──────────┐── timer_irq ────→ rv32im_core
                               │  CLINT   │                    (CSR: mip.MTIP)
                               │          │── software_irq ──→ rv32im_core
                               │          │                    (CSR: mip.MSIP)
                               │          │── timer_tick ────→ hw_rtos
                               └──────────┘                    (タイムスライス管理)
```

### 7.2 割込信号一覧

| 信号名          | ソース     | 宛先         | ビット幅 | 説明                                |
|-----------------|------------|--------------|----------|-------------------------------------|
| `uart_irq`      | uart_apb   | plic         | 1        | UART 割込 (TX完了/RX受信/エラー)    |
| `gpio_irq`      | gpio_apb   | plic         | 1        | GPIO 割込 (エッジ/レベル検出)       |
| `external_irq`  | plic       | rv32im_core  | 1        | 外部割込 (Machine External Int)     |
| `timer_irq`     | clint      | rv32im_core  | 1        | タイマ割込 (Machine Timer Int)      |
| `software_irq`  | clint      | rv32im_core  | 1        | ソフトウェア割込 (Machine SW Int)   |
| `timer_tick`    | clint      | hw_rtos      | 1        | タイムスライス用タイマティック      |

### 7.3 PLIC 割込源マッピング

| 割込 ID | ソース       | 優先度レジスタ    | 説明                    |
|:--------:|--------------|-------------------|-------------------------|
| 0        | (Reserved)   | -                 | 割込ID 0 は未使用       |
| 1        | uart_irq     | `priority[1]`     | UART 割込               |
| 2        | gpio_irq     | `priority[2]`     | GPIO 割込               |
| 3-31     | (Reserved)   | -                 | 将来拡張用 (QSPI, I2C) |

### 7.4 割込処理シーケンス (外部割込の場合)

```
  uart_apb          plic              rv32im_core (CSR Unit)
     │                │                       │
  [1]│ uart_irq=1     │                       │
     │───────────────→│                       │
  [2]│                │ priority check         │
     │                │ threshold check        │
     │                │ external_irq=1        │
  [3]│                │──────────────────────→│
     │                │                       │ mip.MEIP = 1
     │                │                       │ mie.MEIE check
     │                │                       │ mstatus.MIE check
  [4]│                │                       │ trap → mtvec
     │                │                       │ mcause = 0x8000000B
     │                │                       │ mepc = current_pc
  [5]│                │   claim (read)         │
     │                │◄──────────────────────│ (ソフトウェアが PLIC claim)
  [6]│                │   complete (write)     │
     │                │◄──────────────────────│ (ソフトウェアが PLIC complete)
     │                │   external_irq=0      │
  [7]│                │──────────────────────→│ MRET → mepc に復帰
```

---

## 8. hw_rtos ←→ rv32im_core 接続詳細 (Hardware RTOS - CPU Core Interface)

ハードウェア RTOS は CPU コアと密結合し、コンテキストスイッチをハードウェアで実行する。
ソフトウェア RTOS と異なり、レジスタの退避/復帰をハードウェアが自動で行うため、
コンテキストスイッチのオーバーヘッドを大幅に削減する。

### 8.1 接続ブロック図

```
  rv32im_core                                              hw_rtos
  ┌────────────────────┐                    ┌────────────────────────────┐
  │                    │                    │                            │
  │  ┌──────────┐      │                    │  ┌───────────┐            │
  │  │ Register │◄─────┼── ctx_reg_wdata ───┼──│ Context   │            │
  │  │ File     │──────┼── ctx_reg_rdata ──→┼──│ Switch    │            │
  │  │ x0-x31   │      │                    │  │ Engine    │            │
  │  └──────────┘      │                    │  └─────┬─────┘            │
  │                    │                    │        │                  │
  │  ┌──────────┐      │                    │  ┌─────┴─────┐            │
  │  │ Program  │◄─────┼── ctx_sw_pc ───────┼──│ TCB       │            │
  │  │ Counter  │──────┼── current_pc ─────→┼──│ Manager   │            │
  │  └──────────┘      │                    │  │ (16 tasks)│            │
  │                    │                    │  └─────┬─────┘            │
  │  ┌──────────┐      │                    │        │                  │
  │  │ Pipeline │◄─────┼── pipeline_flush ──┼──│     │                  │
  │  │ Control  │◄─────┼── pipeline_stall ──┼──│     │                  │
  │  │          │──────┼── pipeline_empty ──┼─→│     │                  │
  │  └──────────┘      │                    │        │                  │
  │                    │                    │  ┌─────┴─────┐            │
  │  ┌──────────┐      │                    │  │ Scheduler │            │
  │  │ CSR Unit │◄─────┼── csr_restore_data─┼──│ (Priority │            │
  │  │          │──────┼── csr_save_data ──→┼──│  Based)   │            │
  │  └──────────┘      │                    │  └───────────┘            │
  │                    │                    │                            │
  └────────────────────┘                    └────────────────────────────┘
```

### 8.2 コンテキストスイッチ制御信号

| 信号名             | 方向          | ビット幅 | 説明                                            |
|--------------------|---------------|----------|--------------------------------------------------|
| `ctx_sw_req`       | rtos → core   | 1        | コンテキストスイッチ要求                          |
| `ctx_sw_ack`       | core → rtos   | 1        | コンテキストスイッチ応答 (パイプライン空完了)     |
| `ctx_sw_pc`        | rtos → core   | [31:0]   | 復帰先 PC (次タスクの再開アドレス)                |
| `current_pc`       | core → rtos   | [31:0]   | 現在の PC (退避用)                                |
| `ctx_sw_active`    | rtos → core   | 1        | コンテキストスイッチ実行中フラグ                  |

### 8.3 レジスタ退避/復帰信号

| 信号名              | 方向          | ビット幅 | 説明                                            |
|---------------------|---------------|----------|--------------------------------------------------|
| `ctx_save_en`       | rtos → core   | 1        | レジスタ退避イネーブル                            |
| `ctx_restore_en`    | rtos → core   | 1        | レジスタ復帰イネーブル                            |
| `ctx_reg_addr`      | rtos → core   | [4:0]    | 退避/復帰対象レジスタアドレス (x0-x31)            |
| `ctx_reg_wdata`     | rtos → core   | [31:0]   | レジスタ復帰データ (rtos → register file)         |
| `ctx_reg_rdata`     | core → rtos   | [31:0]   | レジスタ退避データ (register file → rtos)         |

### 8.4 CSR 退避/復帰信号

| 信号名               | 方向          | ビット幅 | 説明                                  |
|----------------------|---------------|----------|----------------------------------------|
| `csr_save_en`        | rtos → core   | 1        | CSR 退避イネーブル                     |
| `csr_restore_en`     | rtos → core   | 1        | CSR 復帰イネーブル                     |
| `csr_save_addr`      | rtos → core   | [11:0]   | 退避対象 CSR アドレス                  |
| `csr_save_data`      | core → rtos   | [31:0]   | CSR 退避データ                         |
| `csr_restore_addr`   | rtos → core   | [11:0]   | 復帰対象 CSR アドレス                  |
| `csr_restore_data`   | rtos → core   | [31:0]   | CSR 復帰データ                         |

### 8.5 パイプライン制御信号

| 信号名             | 方向          | ビット幅 | 説明                                   |
|--------------------|---------------|----------|----------------------------------------|
| `pipeline_flush`   | rtos → core   | 1        | パイプライン全段フラッシュ指示          |
| `pipeline_stall`   | rtos → core   | 1        | パイプライン全段ストール指示            |
| `pipeline_empty`   | core → rtos   | 1        | パイプラインが空であることを示す        |

### 8.6 タスク状態通知信号

| 信号名              | 方向          | ビット幅 | 説明                                              |
|---------------------|---------------|----------|----------------------------------------------------|
| `current_task_id`   | rtos → core   | [3:0]    | 現在実行中タスク ID                                |
| `task_active`       | rtos → core   | 1        | タスクがアクティブであることを示すフラグ            |
| `task_switch_cause` | rtos → core   | [2:0]    | スイッチ原因 (タイムスライス/yield/preempt/block)   |

### 8.7 コンテキストスイッチシーケンス (タイミング図)

```
  CLK  ─┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──
        └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘

  Phase:  │ Drain│  Save Regs (x1-x31: 31cyc)  │Restore│  Resume │
          │Pipeln│  + Save CSRs (mepc etc: ~4c) │Regs   │  New    │
          │ (≤5) │                               │+CSRs  │  Task   │

  ctx_sw_req    ──┐_________________________________
                  └─────────────────────────────────

  pipeline_flush  ──┐
                    └───

  pipeline_stall  ──┐_______________________________
                    └───────────────────────────────

  pipeline_empty        ──┐
                          └──────────────────────────

  ctx_save_en                ┐_______________________┐
                             └───────────────────────└

  ctx_reg_addr               │x1│x2│...│x31│         │x1│x2│...│x31│

  ctx_restore_en                                       ┐___________┐
                                                       └───────────└

  ctx_sw_pc                                            ├─ valid ───┤

  ctx_sw_ack                                                        ┐
                                                                    └
```

**コンテキストスイッチ所要サイクル (概算):**

| フェーズ              | サイクル数 | 説明                                   |
|-----------------------|-----------:|----------------------------------------|
| パイプラインドレイン  | 5 (最大)   | 全ステージの命令完了待ち                |
| レジスタ退避 (x1-x31)| 31         | x0 は常にゼロなので省略                |
| CSR 退避             | 4          | mepc, mstatus, mscratch, mcause        |
| レジスタ復帰 (x1-x31)| 31         | 次タスクのレジスタ復帰                 |
| CSR 復帰             | 4          | mepc, mstatus, mscratch, mcause        |
| パイプライン再開     | 1          | 新 PC からフェッチ開始                  |
| **合計**             | **約76**   | **0.76 us @ 100 MHz**                  |

---

## 9. posix_hw_layer 接続詳細 (POSIX Hardware Layer Interfaces)

`posix_hw_layer` は ECALL 命令によるシステムコールを受け付け、
RTOS 関連のシステムコールを `hw_rtos` モジュールに転送する。

### 9.1 接続ブロック図

```
  rv32im_core                posix_hw_layer                    hw_rtos
  ┌───────────┐             ┌──────────────────┐            ┌──────────────┐
  │           │             │                  │            │              │
  │  ECALL ──┼─ ecall_req─→│ Syscall          │            │              │
  │  a7    ──┼─ ecall_code→│ Dispatcher       │            │              │
  │  a0-a2 ──┼─ syscall_  →│   │              │            │              │
  │   (GPR)  │   args       │   ├─ POSIX I/O   │            │              │
  │           │             │   │  (read/write/│            │              │
  │           │             │   │   open/close) │            │              │
  │           │             │   │              │            │              │
  │  a0 ◄────┼─ syscall_  ←│   ├─ RTOS cmds ──┼─rtos_cmd──→│ Command     │
  │   (ret)  │   retval    │   │  (task/sem/  │ rtos_arg   │ Decoder     │
  │           │             │   │   mutex/msg) │            │   │          │
  │  done ◄──┼─ ecall_done←│   │              │            │   ├→Scheduler│
  │           │             │   └──────────────┤            │   ├→Sem/Mtx  │
  │           │             │                  │            │   ├→MsgQueue │
  │           │             │  FD Table        │            │   └→TCB Mgr  │
  │           │             │  ┌────────────┐  │            │              │
  │           │             │  │[0] stdin   │  │◄──rtos_   ─┤ resp_valid  │
  │           │             │  │[1] stdout  │  │   resp     │ resp_status │
  │           │             │  │[2] stderr  │  │◄──rtos_   ─┤ resp_data   │
  │           │             │  │[3..15] usr │  │   data     │              │
  │           │             │  └────────────┘  │            │              │
  └───────────┘             └──────────────────┘            └──────────────┘
```

### 9.2 posix_hw_layer ←→ rv32im_core 信号一覧

| 信号名           | 方向           | ビット幅   | 説明                                     |
|------------------|----------------|------------|------------------------------------------|
| `ecall_req`      | core → posix   | 1          | ECALL 命令検出通知                        |
| `ecall_code`     | core → posix   | [7:0]      | システムコール番号 (a7 レジスタの値)      |
| `syscall_arg0`   | core → posix   | [31:0]     | システムコール引数 0 (a0)                 |
| `syscall_arg1`   | core → posix   | [31:0]     | システムコール引数 1 (a1)                 |
| `syscall_arg2`   | core → posix   | [31:0]     | システムコール引数 2 (a2)                 |
| `syscall_ret`    | posix → core   | [31:0]     | システムコール戻り値 (a0 に書き戻し)      |
| `syscall_done`   | posix → core   | 1          | システムコール処理完了通知                |
| `syscall_errno`  | posix → core   | [31:0]     | エラー番号 (POSIX errno 互換)             |

### 9.3 posix_hw_layer ←→ hw_rtos 信号一覧

| 信号名              | 方向           | ビット幅 | 説明                                |
|---------------------|----------------|----------|--------------------------------------|
| `rtos_cmd_valid`    | posix → rtos   | 1        | RTOS コマンド有効                    |
| `rtos_cmd`          | posix → rtos   | [7:0]    | RTOS コマンド種別                    |
| `rtos_cmd_arg0`     | posix → rtos   | [31:0]   | コマンド引数 0                       |
| `rtos_cmd_arg1`     | posix → rtos   | [31:0]   | コマンド引数 1                       |
| `rtos_cmd_arg2`     | posix → rtos   | [31:0]   | コマンド引数 2                       |
| `rtos_cmd_ready`    | rtos → posix   | 1        | コマンド受付可能                     |
| `rtos_resp_valid`   | rtos → posix   | 1        | RTOS 応答有効                        |
| `rtos_resp_status`  | rtos → posix   | [7:0]    | 応答ステータス (0=成功, 他=エラー)   |
| `rtos_resp_data`    | rtos → posix   | [31:0]   | 応答データ                           |

### 9.4 RTOS コマンドコード (rtos_cmd エンコーディング)

`vsync_pkg.sv` の `syscall_num_t` に対応する `hw_rtos` 向けコマンド。

| コマンドコード | 名称           | 引数                                    | 説明                     |
|:--------------:|----------------|------------------------------------------|--------------------------|
| `0x01`         | TASK_CREATE    | arg0=entry_pc, arg1=stack_ptr, arg2=pri  | タスク生成               |
| `0x02`         | TASK_EXIT      | (なし)                                   | 現在タスク終了           |
| `0x03`         | TASK_YIELD     | (なし)                                   | 自発的CPU放棄            |
| `0x04`         | TASK_SUSPEND   | arg0=task_id                             | タスク一時停止           |
| `0x05`         | TASK_RESUME    | arg0=task_id                             | タスク再開               |
| `0x10`         | SEM_INIT       | arg0=sem_id, arg1=initial_count          | セマフォ初期化           |
| `0x11`         | SEM_WAIT       | arg0=sem_id                              | セマフォ待ち (P操作)     |
| `0x12`         | SEM_POST       | arg0=sem_id                              | セマフォ通知 (V操作)     |
| `0x20`         | MUTEX_LOCK     | arg0=mutex_id                            | ミューテックスロック     |
| `0x21`         | MUTEX_UNLOCK   | arg0=mutex_id                            | ミューテックスアンロック |
| `0x30`         | MSGQ_SEND      | arg0=queue_id, arg1=msg_ptr, arg2=size   | メッセージ送信           |
| `0x31`         | MSGQ_RECV      | arg0=queue_id, arg1=buf_ptr, arg2=size   | メッセージ受信           |

### 9.5 システムコールフロー (POSIX → RTOS 連携: タスク生成の例)

```
  Software           rv32im_core        posix_hw_layer         hw_rtos
  ─────────          ──────────         ──────────────         ───────
      │                   │                   │                   │
  [1] │ ECALL (a7=128)    │                   │                   │
      │──────────────────→│                   │                   │
      │                   │ ecall_req=1       │                   │
      │                   │ ecall_code=0x80   │                   │
  [2] │                   │──────────────────→│                   │
      │                   │                   │ rtos_cmd_valid=1  │
      │                   │                   │ rtos_cmd=0x01     │
      │                   │                   │ arg0=entry_pc     │
      │                   │                   │ arg1=stack_ptr    │
      │                   │                   │ arg2=priority     │
  [3] │                   │                   │──────────────────→│
      │                   │                   │                   │ (タスク生成処理)
      │                   │                   │                   │ TCBエントリ確保
      │                   │                   │                   │ レディキュー追加
  [4] │                   │                   │ rtos_resp_valid=1 │
      │                   │                   │ rtos_resp_status=0│
      │                   │                   │ rtos_resp_data=   │
      │                   │                   │   task_id         │
      │                   │                   │◄──────────────────│
  [5] │                   │ syscall_done=1    │                   │
      │                   │ syscall_ret=      │                   │
      │                   │   task_id         │                   │
      │                   │◄──────────────────│                   │
  [6] │                   │ (MRET → 復帰)     │                   │
      │◄──────────────────│                   │                   │
      │ a0 = task_id      │                   │                   │
```

---

## 10. クロック・リセット分配 (Clock and Reset Distribution)

### 10.1 クロックドメイン

本設計は単一クロックドメイン (`clk_sys`) を基本とする。
HyperRAM コントローラのみ内部でクロック位相調整を行う。

```
                 ┌────────────────────────────────────────────────┐
  External      │  Xilinx MMCM / PLL                             │
  clk_in_p/n ─→│                                                 │
  (差動入力)    │  clk_sys (100 MHz)  ────→ 全モジュール共通      │
                │  clk_hyper (200 MHz) ──→ hyperram_ctrl 内部    │
                │  clk_hyper_90 (200MHz, 90deg) → hyperram I/O   │
                │  locked ─────────────────→ リセット制御         │
                └────────────────────────────────────────────────┘
```

### 10.2 クロック信号分配表

| クロック名       | 周波数      | 供給先モジュール                                                |
|------------------|-------------|------------------------------------------------------------------|
| `clk_sys`        | 100 MHz     | rv32im_core, hw_rtos, posix_hw_layer, axi4_master,              |
|                  |             | axi4_interconnect, axi4_apb_bridge, bram_imem, bram_dmem,       |
|                  |             | uart_apb, gpio_apb, plic, clint                                  |
| `clk_hyper`      | 200 MHz     | hyperram_ctrl (内部 I/O 用、DDR転送対応)                         |
| `clk_hyper_90`   | 200 MHz     | hyperram_ctrl (90度位相シフト、DDRデータ取得タイミング用)        |

### 10.3 リセット方式

非同期アサート/同期リリース方式を採用する。

```
                         ┌──────────────┐
  外部リセット ──────────→│  Reset       │
  (Active Low)           │  Synchronizer│── rst_n_sync ──→ 全モジュール
  PLL locked  ──────────→│  (2-FF)      │
                         └──────────────┘
```

| リセット信号    | 極性        | 方式           | 説明                                    |
|-----------------|-------------|----------------|-----------------------------------------|
| `rst_n` (外部)  | Active Low  | 非同期          | ボード上のリセットボタン/電源ON         |
| `pll_locked`    | Active High | -              | PLL ロック完了信号                      |
| `rst_n_sync`    | Active Low  | 同期リリース    | clk_sys 同期済みリセット (全モジュールへ)|

**リセットシーケンス:**
1. 外部リセットアサート、または PLL 未ロック → `rst_n_sync` = 0
2. 外部リセットディアサート かつ PLL ロック完了 → 2-FF 同期後 `rst_n_sync` = 1
3. 全モジュールが同時にリセット解除される

---

## 11. hw_rtos 内部構造詳細 (Hardware RTOS Internal Structure)

### 11.1 内部ブロック図

```
  hw_rtos
  ┌──────────────────────────────────────────────────────────────────┐
  │                                                                  │
  │  ┌─────────────────┐      ┌──────────────────────────────────┐  │
  │  │   AXI4 Slave    │      │     Command Decoder              │  │
  │  │   Interface     │      │  (posix_hw_layer からの          │  │
  │  │  (レジスタ      │      │   rtos_cmd を解釈)               │  │
  │  │   アクセス用)   │      └────────┬──────────────────────┬──┘  │
  │  └────────┬────────┘               │                      │     │
  │           │                        ▼                      ▼     │
  │           │              ┌──────────────────┐   ┌────────────┐  │
  │           │              │   Task Scheduler │   │   Sync     │  │
  │           │              │                  │   │ Primitives │  │
  │           │              │ ・Priority-based │   │            │  │
  │           │              │   preemptive     │   │ ┌────────┐ │  │
  │           │              │ ・Round-robin    │   │ │Semaphor│ │  │
  │           │              │   (同一優先度)   │   │ │(8 個)  │ │  │
  │           │              │ ・Ready queue    │   │ └────────┘ │  │
  │           │              │   (ビットマップ) │   │ ┌────────┐ │  │
  │           │              │ ・Time-slice     │   │ │Mutex   │ │  │
  │           │              │   counter        │   │ │(8 個)  │ │  │
  │           │              └────────┬─────────┘   │ └────────┘ │  │
  │           │                       │             │ ┌────────┐ │  │
  │           │                       ▼             │ │MsgQueue│ │  │
  │  ┌────────┴──────────────────────────────────┐  │ │(4 個)  │ │  │
  │  │          TCB Manager                       │  │ └────────┘ │  │
  │  │                                            │  └────────────┘  │
  │  │  TCB[0]  TCB[1]  TCB[2] ... TCB[15]       │                  │
  │  │  ┌─────┐ ┌─────┐ ┌─────┐    ┌──────┐     │                  │
  │  │  │id   │ │id   │ │id   │    │id    │     │                  │
  │  │  │pri  │ │pri  │ │pri  │    │pri   │     │                  │
  │  │  │state│ │state│ │state│    │state │     │                  │
  │  │  │pc   │ │pc   │ │pc   │    │pc    │     │                  │
  │  │  │sp   │ │sp   │ │sp   │    │sp    │     │                  │
  │  │  │slice│ │slice│ │slice│    │slice │     │                  │
  │  │  └─────┘ └─────┘ └─────┘    └──────┘     │                  │
  │  └───────────────────────────────────────────┘                  │
  │                        │                                         │
  │                        ▼                                         │
  │  ┌──────────────────────────────────────┐                       │
  │  │       Context Switch Engine          │                       │
  │  │                                      │                       │
  │  │  ┌────────────┐  ┌────────────────┐  │                       │
  │  │  │ Register   │  │  State Machine │  │                       │
  │  │  │ Save/Load  │  │  (IDLE→DRAIN→  │  │                       │
  │  │  │ Controller │  │   SAVE→LOAD→   │  │                       │
  │  │  │            │  │   RESUME)      │  │                       │
  │  │  └────────────┘  └────────────────┘  │                       │
  │  │                                      │                       │
  │  │  ┌─────────────────────────────────┐ │                       │
  │  │  │ Register File Storage (BRAM)    │ │                       │
  │  │  │ 16 tasks x 32 regs x 32 bits   │ │                       │
  │  │  │ = 2 KB (1 x BRAM36Kb)          │ │                       │
  │  │  └─────────────────────────────────┘ │                       │
  │  └──────────────────────────────────────┘                       │
  │                                                                  │
  │  timer_tick (from CLINT) ──────→ Time-slice counter             │
  │                                                                  │
  └──────────────────────────────────────────────────────────────────┘
```

### 11.2 hw_rtos パラメータ (`vsync_pkg.sv` より)

| パラメータ           | 値   | 説明                       |
|----------------------|------|----------------------------|
| `MAX_TASKS`          | 16   | 最大タスク数               |
| `TASK_ID_W`          | 4    | タスクID ビット幅          |
| `TASK_PRIORITY_W`    | 4    | 優先度ビット幅 (16レベル) |
| `TIME_SLICE_W`       | 16   | タイムスライスカウンタ幅   |

### 11.3 TCB (Task Control Block) フィールド

`vsync_pkg.sv` の `tcb_t` 構造体に対応する。

| フィールド   | ビット幅                 | 説明                                                    |
|--------------|--------------------------|----------------------------------------------------------|
| `task_id`    | [TASK_ID_W-1:0]          | タスク識別子 (0-15)                                      |
| `priority`   | [TASK_PRIORITY_W-1:0]    | 優先度 (0=最高, 15=最低)                                 |
| `state`      | task_state_t [2:0]       | タスク状態 (READY/RUNNING/BLOCKED/SUSPENDED/DORMANT)     |
| `pc`         | [31:0]                   | プログラムカウンタ退避値                                 |
| `sp`         | [31:0]                   | スタックポインタ退避値                                   |
| `time_slice` | [TIME_SLICE_W-1:0]       | 残りタイムスライス値                                     |
| `valid`      | 1                        | TCB エントリ有効フラグ                                    |

### 11.4 タスク状態遷移

```
                     TASK_CREATE
                         │
                         ▼
  ┌────────────┐   ┌───────────┐   ┌─────────────┐
  │  DORMANT   │──→│  READY    │──→│  RUNNING    │
  │  (3'b100)  │   │  (3'b000) │◄──│  (3'b001)   │
  └────────────┘   └─────┬─────┘   └──────┬──────┘
                         │                 │
                         │    ┌────────────┘
                         │    │ sem_wait / mutex_lock / msgq_recv (リソース不足時)
                         │    ▼
                    ┌──────────┐
                    │ BLOCKED  │
                    │ (3'b010) │
                    └──────────┘
                         │
          sem_post / mutex_unlock / msgq_send
                         │
                         ▼
                    ┌──────────┐
                    │  READY   │ (再びレディキューへ)
                    └──────────┘

  ※ SUSPENDED (3'b011) 状態はデバッグ用途で使用。
     TASK_SUSPEND コマンドにより任意のタスクを一時停止可能。
     TASK_RESUME コマンドにより READY 状態に復帰する。
```

---

## 12. posix_hw_layer 内部構造詳細 (POSIX Hardware Layer Internal Structure)

### 12.1 内部ブロック図

```
  posix_hw_layer
  ┌──────────────────────────────────────────────────────────────┐
  │                                                              │
  │  ┌──────────────────┐       ┌─────────────────────────────┐ │
  │  │  AXI4 Slave I/F  │       │  Syscall Dispatcher         │ │
  │  │ (デバッグ/設定用) │       │                             │ │
  │  └──────────────────┘       │  ecall_req ──→ ┌──────┐     │ │
  │                             │  ecall_code──→ │Decode│     │ │
  │                             │  syscall_args→ │      │     │ │
  │                             │                └──┬───┘     │ │
  │                             │      ┌────────────┼────┐    │ │
  │                             │      ▼            ▼    ▼    │ │
  │                             │  ┌──────┐  ┌──────┐┌─────┐ │ │
  │                             │  │POSIX │  │POSIX ││RTOS │ │ │
  │                             │  │File  │  │Proc  ││ API │ │ │
  │                             │  │I/O   │  │Ctrl  ││Proxy│ │ │
  │                             │  │(r/w/ │  │(exit/││     │ │ │
  │                             │  │ open/│  │ sbrk)││     │ │ │
  │                             │  │close)│  │      ││     │ │ │
  │                             │  └──┬───┘  └──┬───┘└──┬──┘ │ │
  │                             │     │         │       │     │ │
  │                             │     ▼         │       ▼     │ │
  │  ┌──────────────────────┐   │  ┌──────┐     │  rtos_cmd ─┼→│ hw_rtos
  │  │   FD Table            │   │  │Periph│     │  rtos_arg ─┼→│
  │  │                       │   │  │Access│     │            │ │
  │  │  [0] stdin  (UART RX) │   │  │Engine│     │  rtos_resp◄┼─│
  │  │  [1] stdout (UART TX) │   │  └──┬───┘     │            │ │
  │  │  [2] stderr (UART TX) │   │     │         │            │ │
  │  │  [3..15] ユーザ定義   │   │     ▼         ▼            │ │
  │  │                       │   │  ┌──────────────────┐      │ │
  │  │  各エントリ:           │   │  │ Return Value     │      │ │
  │  │   valid, fd_type,     │   │  │ Formatter        │      │ │
  │  │   base_addr, flags    │   │  └────────┬─────────┘      │ │
  │  └──────────────────────┘   │           │                 │ │
  │                             │           ▼                 │ │
  │                             │  syscall_ret ──────────────→│ rv32im_core
  │                             │  syscall_done ─────────────→│
  │                             │  syscall_errno ────────────→│
  │                             └─────────────────────────────┘ │
  └──────────────────────────────────────────────────────────────┘
```

### 12.2 FD テーブル仕様 (`vsync_pkg.sv` より)

| パラメータ    | 値   | 説明                          |
|---------------|------|-------------------------------|
| `MAX_FD`      | 16   | 最大ファイルディスクリプタ数  |
| `FD_WIDTH`    | 4    | FD インデックスビット幅       |

**`fd_entry_t` 構造体:**

| フィールド  | 型 / ビット幅     | 説明                                     |
|-------------|-------------------|------------------------------------------|
| `valid`     | logic             | エントリ有効フラグ                        |
| `fd_type`   | fd_type_t [2:0]   | デバイスタイプ (NONE/UART/GPIO/MEM/PIPE) |
| `base_addr` | logic [31:0]      | デバイスのベースアドレス                  |
| `flags`     | logic [15:0]      | オープンフラグ (O_RDONLY, O_WRONLY 等)    |

**デフォルト FD 割り当て (リセット後):**

| FD 番号 | fd_type        | base_addr        | 用途              |
|:-------:|----------------|------------------|--------------------|
| 0       | FD_TYPE_UART   | `0x1000_0000`    | stdin  (UART RX)   |
| 1       | FD_TYPE_UART   | `0x1000_0000`    | stdout (UART TX)   |
| 2       | FD_TYPE_UART   | `0x1000_0000`    | stderr (UART TX)   |
| 3-15    | FD_TYPE_NONE   | `0x0000_0000`    | 未割当             |

---

## 13. HyperRAM コントローラ接続 (HyperRAM Controller Interface)

### 13.1 外部ピン接続

```
  hyperram_ctrl                              HyperRAM Device
  ┌──────────────┐                          ┌──────────────┐
  │ AXI4 Slave   │                          │              │
  │ Interface    │                          │              │
  │              │── hram_ck    ──────────→ │ CK           │
  │              │── hram_ck_n  ──────────→ │ CK#          │
  │              │── hram_cs_n  ──────────→ │ CS#          │
  │              │── hram_rwds  ◄──────────→│ RWDS         │
  │              │── hram_dq[7:0] ◄────────→│ DQ[7:0]      │
  │              │── hram_reset_n ────────→ │ RESET#       │
  │              │                          │              │
  └──────────────┘                          └──────────────┘
```

| 信号名          | 方向           | ビット幅 | 説明                                 |
|-----------------|----------------|----------|--------------------------------------|
| `hram_ck`       | ctrl → device  | 1        | 差動クロック (正)                    |
| `hram_ck_n`     | ctrl → device  | 1        | 差動クロック (負)                    |
| `hram_cs_n`     | ctrl → device  | 1        | チップセレクト (Active Low)          |
| `hram_rwds`     | bidirectional  | 1        | Read/Write データストローブ          |
| `hram_dq`       | bidirectional  | [7:0]    | データバス (DDR)                     |
| `hram_reset_n`  | ctrl → device  | 1        | デバイスリセット (Active Low)        |

---

## 14. UART ペリフェラル内部構造 (UART APB Peripheral)

```
  uart_apb
  ┌──────────────────────────────────────────────┐
  │  APB Slave I/F                               │
  │       │                                      │
  │  ┌────┴────┐                                 │
  │  │Register │  ・TX_DATA / RX_DATA            │
  │  │ Map     │  ・STATUS (TX_FULL, RX_EMPTY,..)│
  │  │         │  ・CTRL (Baud, Parity, Stop,..) │
  │  │         │  ・IRQ_EN / IRQ_STAT            │
  │  └────┬────┘                                 │
  │       │                                      │
  │  ┌────┴─────────┐   ┌────────────────────┐   │
  │  │  TX Path     │   │  RX Path           │   │
  │  │  ┌────────┐  │   │  ┌────────┐        │   │
  │  │  │TX FIFO │  │   │  │RX FIFO │        │   │
  │  │  │(16deep)│  │   │  │(16deep)│        │   │
  │  │  └───┬────┘  │   │  └───┬────┘        │   │
  │  │      ▼       │   │      ▲             │   │
  │  │  ┌────────┐  │   │  ┌───┴────┐        │   │    外部ピン
  │  │  │TX Shift│  │   │  │RX Shift│◄───────┼───┼── uart_rx
  │  │  │Register│  │   │  │Register│        │   │
  │  │  └───┬────┘  │   │  └────────┘        │   │
  │  └──────┼───────┘   └────────────────────┘   │
  │         └─────────────────────────────────────┼──→ uart_tx
  │                                              │
  │  uart_irq ──────────────────────────────────→│──→ plic
  │  (TX空/RX受信/RXオーバーラン/フレームエラー) │
  └──────────────────────────────────────────────┘
```

---

## 15. GPIO ペリフェラル内部構造 (GPIO APB Peripheral)

```
  gpio_apb
  ┌───────────────────────────────────────────┐
  │  APB Slave I/F                            │
  │       │                                   │
  │  ┌────┴────┐                              │
  │  │Register │  ・GPIO_DATA   (R/W)        │
  │  │ Map     │  ・GPIO_DIR    (R/W)        │     外部ピン
  │  │         │  ・GPIO_IRQ_EN (R/W)        │
  │  │         │  ・GPIO_IRQ_STAT(R/W1C)     │
  │  │         │  ・GPIO_IRQ_EDGE(R/W)       │
  │  └────┬────┘                              │
  │       │                                   │
  │  ┌────┴────────────────┐                  │
  │  │  Direction Control  │                  │
  │  │  (per-bit)          │                  │
  │  │  0=Input, 1=Output  │◄───────────────►│──► gpio[31:0]
  │  └─────────────────────┘                  │
  │                                           │
  │  ┌─────────────────────┐                  │
  │  │  Interrupt Detect   │                  │
  │  │  (Edge / Level)     │                  │
  │  │  per-bit enable     │                  │
  │  └────────┬────────────┘                  │
  │           │                               │
  │  gpio_irq ───────────────────────────────→│──→ plic
  └───────────────────────────────────────────┘
```

---

## 16. 全モジュール間接続サマリテーブル (Complete Interconnection Summary)

### 16.1 直結信号 (Non-bus Direct Connections)

| ソース        | 宛先           | 信号名              | 幅      | 説明                              |
|---------------|----------------|---------------------|---------|-----------------------------------|
| rv32im_core   | bram_imem      | `imem_addr`         | 16      | 命令フェッチアドレス              |
| bram_imem     | rv32im_core    | `imem_rdata`        | 32      | 命令読み出しデータ                |
| rv32im_core   | bram_imem      | `imem_en`           | 1       | 命令メモリイネーブル              |
| rv32im_core   | axi4_master    | `mem_addr`          | 32      | データメモリアドレス              |
| rv32im_core   | axi4_master    | `mem_wdata`         | 32      | データ書き込みデータ              |
| rv32im_core   | axi4_master    | `mem_read`          | 1       | メモリ読み出し要求                |
| rv32im_core   | axi4_master    | `mem_write`         | 1       | メモリ書き込み要求                |
| rv32im_core   | axi4_master    | `mem_size`          | 3       | アクセスサイズ (byte/half/word)   |
| axi4_master   | rv32im_core    | `mem_rdata`         | 32      | データ読み出しデータ              |
| axi4_master   | rv32im_core    | `mem_ready`         | 1       | メモリアクセス完了                |
| axi4_master   | rv32im_core    | `mem_error`         | 1       | メモリアクセスエラー              |
| plic          | rv32im_core    | `external_irq`      | 1       | 外部割込 → CPU                    |
| clint         | rv32im_core    | `timer_irq`         | 1       | タイマ割込 → CPU                  |
| clint         | rv32im_core    | `software_irq`      | 1       | ソフトウェア割込 → CPU            |
| clint         | hw_rtos        | `timer_tick`         | 1       | RTOS タイムスライス用ティック     |
| uart_apb      | plic           | `uart_irq`          | 1       | UART 割込源                       |
| gpio_apb      | plic           | `gpio_irq`          | 1       | GPIO 割込源                       |
| hw_rtos       | rv32im_core    | `ctx_sw_req`        | 1       | コンテキストスイッチ要求          |
| rv32im_core   | hw_rtos        | `ctx_sw_ack`        | 1       | コンテキストスイッチ応答          |
| hw_rtos       | rv32im_core    | `ctx_sw_pc`         | 32      | 復帰先 PC                         |
| rv32im_core   | hw_rtos        | `current_pc`        | 32      | 現在 PC 退避                      |
| hw_rtos       | rv32im_core    | `ctx_sw_active`     | 1       | スイッチ実行中フラグ              |
| hw_rtos       | rv32im_core    | `ctx_save_en`       | 1       | レジスタ退避イネーブル            |
| hw_rtos       | rv32im_core    | `ctx_restore_en`    | 1       | レジスタ復帰イネーブル            |
| hw_rtos       | rv32im_core    | `ctx_reg_addr`      | 5       | 退避/復帰レジスタアドレス         |
| hw_rtos       | rv32im_core    | `ctx_reg_wdata`     | 32      | レジスタ復帰データ                |
| rv32im_core   | hw_rtos        | `ctx_reg_rdata`     | 32      | レジスタ退避データ                |
| hw_rtos       | rv32im_core    | `csr_save_en`       | 1       | CSR 退避イネーブル                |
| hw_rtos       | rv32im_core    | `csr_restore_en`    | 1       | CSR 復帰イネーブル                |
| hw_rtos       | rv32im_core    | `csr_save_addr`     | 12      | CSR 退避アドレス                  |
| rv32im_core   | hw_rtos        | `csr_save_data`     | 32      | CSR 退避データ                    |
| hw_rtos       | rv32im_core    | `csr_restore_addr`  | 12      | CSR 復帰アドレス                  |
| hw_rtos       | rv32im_core    | `csr_restore_data`  | 32      | CSR 復帰データ                    |
| hw_rtos       | rv32im_core    | `pipeline_flush`    | 1       | パイプラインフラッシュ            |
| hw_rtos       | rv32im_core    | `pipeline_stall`    | 1       | パイプラインストール              |
| rv32im_core   | hw_rtos        | `pipeline_empty`    | 1       | パイプライン空通知                |
| hw_rtos       | rv32im_core    | `current_task_id`   | 4       | 現在タスクID                      |
| hw_rtos       | rv32im_core    | `task_active`       | 1       | タスクアクティブフラグ            |
| rv32im_core   | posix_hw_layer | `ecall_req`         | 1       | ECALL 検出通知                    |
| rv32im_core   | posix_hw_layer | `ecall_code`        | 8       | システムコール番号 (a7)           |
| rv32im_core   | posix_hw_layer | `syscall_arg0`      | 32      | システムコール引数 0 (a0)         |
| rv32im_core   | posix_hw_layer | `syscall_arg1`      | 32      | システムコール引数 1 (a1)         |
| rv32im_core   | posix_hw_layer | `syscall_arg2`      | 32      | システムコール引数 2 (a2)         |
| posix_hw_layer| rv32im_core    | `syscall_ret`       | 32      | システムコール戻り値              |
| posix_hw_layer| rv32im_core    | `syscall_done`      | 1       | システムコール完了通知            |
| posix_hw_layer| rv32im_core    | `syscall_errno`     | 32      | エラー番号                        |
| posix_hw_layer| hw_rtos        | `rtos_cmd_valid`    | 1       | RTOS コマンド有効                 |
| posix_hw_layer| hw_rtos        | `rtos_cmd`          | 8       | RTOS コマンド種別                 |
| posix_hw_layer| hw_rtos        | `rtos_cmd_arg0`     | 32      | コマンド引数 0                    |
| posix_hw_layer| hw_rtos        | `rtos_cmd_arg1`     | 32      | コマンド引数 1                    |
| posix_hw_layer| hw_rtos        | `rtos_cmd_arg2`     | 32      | コマンド引数 2                    |
| hw_rtos       | posix_hw_layer | `rtos_cmd_ready`    | 1       | コマンド受付可能                  |
| hw_rtos       | posix_hw_layer | `rtos_resp_valid`   | 1       | RTOS 応答有効                     |
| hw_rtos       | posix_hw_layer | `rtos_resp_status`  | 8       | 応答ステータス                    |
| hw_rtos       | posix_hw_layer | `rtos_resp_data`    | 32      | 応答データ                        |

### 16.2 AXI4 バス接続

| Master       | Slave            | アドレス範囲                    | サイズ  | 説明                    |
|--------------|------------------|---------------------------------|---------|--------------------------|
| axi4_master  | bram_dmem        | `0x0001_0000` - `0x0001_3FFF`   | 16 KB   | データメモリ             |
| axi4_master  | hyperram_ctrl    | `0x2000_0000` - `0x2FFF_FFFF`   | 256 MB  | 外部 HyperRAM            |
| axi4_master  | axi4_apb_bridge  | (APB ペリフェラル範囲)          | -       | APB ペリフェラルへの中継 |
| axi4_master  | hw_rtos          | `0x1100_0000` - `0x1100_FFFF`   | 64 KB   | RTOS レジスタ            |
| axi4_master  | posix_hw_layer   | `0x1200_0000` - `0x1200_FFFF`   | 64 KB   | POSIX レジスタ           |

### 16.3 APB バス接続

| Slave     | PSEL       | ベースアドレス   | サイズ  | 説明                        |
|-----------|------------|------------------|---------|-----------------------------|
| uart_apb  | `PSEL[0]`  | `0x1000_0000`    | 256 B   | UART コントローラ           |
| gpio_apb  | `PSEL[1]`  | `0x1000_0100`    | 256 B   | GPIO コントローラ           |
| plic      | `PSEL[2]`  | `0x0C00_0000`    | 4 KB    | Platform-Level Interrupt Ctrl |
| clint     | `PSEL[3]`  | `0x0200_0000`    | 64 KB   | Core Local Interruptor      |

---

## 17. トップモジュール外部ポート一覧 (vsync_top External Ports)

| ポート名        | 方向    | ビット幅 | 説明                              |
|-----------------|---------|----------|-----------------------------------|
| `clk_in_p`      | input   | 1        | 差動クロック入力 (正)             |
| `clk_in_n`      | input   | 1        | 差動クロック入力 (負)             |
| `rst_n`         | input   | 1        | 外部リセット (Active Low)         |
| `uart_tx`       | output  | 1        | UART 送信データ                   |
| `uart_rx`       | input   | 1        | UART 受信データ                   |
| `gpio`          | inout   | [31:0]   | GPIO 双方向ポート                 |
| `hram_ck`       | output  | 1        | HyperRAM クロック (正)            |
| `hram_ck_n`     | output  | 1        | HyperRAM クロック (負)            |
| `hram_cs_n`     | output  | 1        | HyperRAM チップセレクト           |
| `hram_rwds`     | inout   | 1        | HyperRAM データストローブ         |
| `hram_dq`       | inout   | [7:0]    | HyperRAM データバス               |
| `hram_reset_n`  | output  | 1        | HyperRAM リセット                 |
| `jtag_tck`      | input   | 1        | JTAG clock (将来予定, optional)   |
| `jtag_tms`      | input   | 1        | JTAG mode select (optional)       |
| `jtag_tdi`      | input   | 1        | JTAG data in (optional)           |
| `jtag_tdo`      | output  | 1        | JTAG data out (optional)          |
| `jtag_trst_n`   | input   | 1        | JTAG reset (optional)             |

---

## 18. モジュール階層まとめ (Module Hierarchy Summary)

```
vsync_top
├── clk_rst_gen (MMCM/PLL + Reset Synchronizer)
├── rv32im_core
│   ├── fetch_stage
│   ├── decode_stage
│   ├── execute_stage (ALU + M-extension MUL/DIV)
│   ├── memory_stage
│   ├── writeback_stage
│   ├── register_file (x0-x31)
│   ├── csr_unit (mstatus, mepc, mcause, mtvec, mie, mip, etc.)
│   └── hazard_unit (forwarding + stall + flush control)
├── hw_rtos
│   ├── command_decoder
│   ├── scheduler (priority-based preemptive + round-robin)
│   ├── tcb_manager (16 task entries)
│   ├── context_switch_engine (register save/restore via BRAM)
│   └── sync_primitives
│       ├── semaphore_unit (8 semaphores)
│       ├── mutex_unit (8 mutexes)
│       └── msgqueue_unit (4 message queues)
├── posix_hw_layer
│   ├── syscall_dispatcher
│   ├── fd_table (16 entries)
│   └── periph_access_engine
├── axi4_master
├── axi4_interconnect (1M x 5S)
│   └── address_decoder
├── axi4_apb_bridge
├── bram_imem (64KB, BRAM inferred)
├── bram_dmem (16KB, BRAM inferred, AXI4 slave)
├── hyperram_ctrl (AXI4 slave, CDC included)
├── uart_apb (APB slave)
│   ├── uart_tx_fifo (16-deep)
│   ├── uart_rx_fifo (16-deep)
│   ├── uart_tx_shift_reg
│   ├── uart_rx_shift_reg
│   └── baud_rate_gen
├── gpio_apb (APB slave)
│   ├── direction_control (per-bit)
│   └── interrupt_detect (edge/level, per-bit enable)
├── plic (APB slave)
│   ├── priority_comparator
│   ├── interrupt_gateway
│   └── claim_complete_logic
└── clint (APB slave)
    ├── mtime_counter (64-bit)
    ├── mtimecmp_register (64-bit)
    └── msip_register
```

---

## 19. FPGA リソース概算 (FPGA Resource Estimation)

| モジュール          | LUT (概算) | FF (概算) | BRAM (36Kb) | 備考                      |
|---------------------|:----------:|:---------:|:-----------:|----------------------------|
| rv32im_core         | ~3,000     | ~2,000    | 0           | 5段パイプライン + CSR      |
| hw_rtos             | ~2,500     | ~1,500    | 1           | TCBレジスタ退避用BRAM      |
| posix_hw_layer      | ~800       | ~500      | 0           | FDテーブルはFFで実装       |
| axi4_master         | ~300       | ~200      | 0           |                            |
| axi4_interconnect   | ~1,000     | ~500      | 0           | 5スレーブデコーダ          |
| axi4_apb_bridge     | ~200       | ~100      | 0           |                            |
| bram_imem           | ~50        | ~10       | 18          | 64KB = 18 x BRAM36Kb      |
| bram_dmem           | ~50        | ~10       | 5           | 16KB = 5 x BRAM36Kb       |
| hyperram_ctrl       | ~500       | ~300      | 0           | DDR I/O + FSM              |
| uart_apb            | ~300       | ~200      | 0           | TX/RX FIFO (分散RAM)      |
| gpio_apb            | ~200       | ~100      | 0           |                            |
| plic                | ~400       | ~200      | 0           |                            |
| clint               | ~200       | ~150      | 0           | 64bit タイマカウンタ       |
| clk_rst_gen         | ~50        | ~20       | 0           | MMCM + 2-FF sync           |
| **合計**            | **~9,550** | **~5,790**| **24**      |                            |

---

## 20. 設計制約・注意事項 (Design Constraints and Notes)

1. **単一クロックドメイン:** 主系統は `clk_sys` ドメインで動作する。HyperRAM 物理インタフェースのみ別クロックドメインとし、内部に CDC 同期回路を配置する。

2. **BRAM 推論:** `bram_imem` および `bram_dmem` は Xilinx 推奨の BRAM 推論パターンを使用する:
   - `logic [31:0] mem [0:SIZE-1]` 配列宣言
   - `always_ff @(posedge clk)` 同期 read/write
   - `$readmemh()` による初期化

3. **AXI4 プロトコル準拠:** 全チャネルで VALID/READY ハンドシェイクを実装する。バースト転送 (INCR, WRAP) をサポートする。AXI4-Lite 簡略化は行わない。

4. **命令メモリアクセス:** `bram_imem` は `rv32im_core` に直結 (AXI4 バス非経由) とし、バスレイテンシなしの1サイクル命令フェッチを実現する。

5. **データメモリアクセス:** 全データアクセスは `axi4_master` → `axi4_interconnect` を経由し、BRAM/HyperRAM/ペリフェラルに対する統一アドレス空間を提供する。

6. **RTOS コンテキストスイッチ:** `hw_rtos` は `rv32im_core` への直結信号によりコンテキストスイッチを要求する。バスを経由しないため最小レイテンシを実現する。レジスタ退避/復帰は専用ワイドインタフェースを使用する。

7. **POSIX システムコール処理:** ECALL 命令は `rv32im_core` で検出され、直結信号で `posix_hw_layer` にディスパッチされる。POSIX 層は RTOS 操作またはペリフェラルアクセスに変換する。

8. **割込アーキテクチャ:** RISC-V Privileged Specification v1.12 に準拠する:
   - 外部割込 → PLIC → CPU (`external_irq`)
   - タイマ割込 → CLINT → CPU (`timer_irq`)
   - ソフトウェア割込 → CLINT → CPU (`software_irq`)
   - CLINT の `timer_tick` は `hw_rtos` にも供給し、タイムスライス管理に使用する。

9. **アドレスマップ参照:** 全アドレスは `vsync_pkg.sv` で定義される。全モジュール間で一貫性を保つこと。詳細アドレスマップは `doc/address_map.md` を参照。

10. **将来拡張:** APB バスおよび PLIC は PSEL 線と割込源の追加により、QSPI/I2C 等のペリフェラルを拡張可能である。

---

*本ドキュメントは RTL 実装チームが直接参照することを前提に作成されている。*
*各モジュールの詳細レジスタマップ、ステートマシン仕様、テストベンチ仕様は別途ドキュメントを参照のこと。*
*`vsync_pkg.sv` に定義されたパラメータおよび型定義との整合性を常に維持すること。*
