# VSync - Hardware RTOS RISC-V Processor with POSIX Support

FPGA向けハードウェアRTOS内蔵・POSIX対応 RISC-V RV32IM プロセッサ SoC

VSync: RISC-**V**ertical **SYNC**: Bridging 5-stage Pipeline to POSIX Realtime OS.

## Overview

VSyncは、リアルタイムOS(RTOS)をハードウェアで実装し、POSIXインターフェースを備えたRISC-V RV32IMプロセッサシステムです。SystemVerilogで記述され、Xilinx Artix UltraScale+ および Artix-7 FPGAをターゲットとしています。

### Key Features

- **RISC-V RV32IM**: 5段パイプライン (Fetch/Decode/Execute/Memory/Writeback)
- **Hardware RTOS**: タスク管理・スケジューリング・コンテキストスイッチをハードウェアで実装
- **POSIX Compatible**: pthread, semaphore, mutex, message queue, file I/O をハードウェアレベルでサポート
- **Bus Architecture**: AXI4 → APB ブリッジによるペリフェラル接続
- **Peripherals**: UART, GPIO, HyperRAM, PLIC, CLINT
- **Memory Protection**: PMP (Physical Memory Protection) ユニット内蔵
- **UART Program Loading**: シェルから `load`/`go` コマンドで UART 経由のプログラムロード・実行が可能

## Prerequisites

### Simulation

- **Icarus Verilog** (iverilog) 12.0 以降 (SystemVerilog 2012 対応)
- **Bash** シェル

```bash
# Ubuntu/Debian
sudo apt install iverilog

# macOS (Homebrew)
brew install icarus-verilog
```

### Software Build

- **RISC-V GCC Toolchain** (`riscv32-unknown-elf-gcc`)

```bash
# Ubuntu/Debian
sudo apt install gcc-riscv64-unknown-elf

# or build from source: https://github.com/riscv-collab/riscv-gnu-toolchain
```

### FPGA Build

- **Xilinx Vivado** 2025.1 以降 (Artix-7 ターゲットの場合)
- **Xilinx Vivado** 2025.2 以降 (Artix UltraScale+ ターゲットの場合)
- Target Devices:
  - `xcau7p-sbvc484-2-i` (Artix UltraScale+) - 50 MHz
  - `xc7a100tcsg324-1` (Digilent Arty-A7) - 25 MHz (MMCM)

## Directory Structure

```
vsync/
├── rtl/                          # RTL ソースコード (35 files)
│   ├── core/                     #   CPU コア・パイプライン
│   │   ├── vsync_pkg.sv         #     グローバルパッケージ (型・定数定義)
│   │   ├── rv32im_core.sv        #     CPU トップモジュール
│   │   ├── fetch_stage.sv        #     IF ステージ
│   │   ├── decode_stage.sv       #     ID ステージ
│   │   ├── execute_stage.sv      #     EX ステージ
│   │   ├── memory_stage.sv       #     MEM ステージ
│   │   ├── writeback_stage.sv    #     WB ステージ
│   │   ├── alu.sv                #     ALU (算術論理演算)
│   │   ├── branch_unit.sv        #     分岐判定ユニット
│   │   ├── multiplier_divider.sv #     乗除算器 (M拡張)
│   │   ├── register_file.sv      #     レジスタファイル (32x32bit)
│   │   ├── hazard_unit.sv        #     ハザード検出・フォワーディング
│   │   ├── csr_unit.sv           #     CSR レジスタ
│   │   ├── exception_unit.sv     #     例外・割り込み処理
│   │   └── immediate_gen.sv      #     即値生成
│   ├── bus/                      #   バスインフラ
│   │   ├── axi4_master.sv        #     AXI4 マスターインターフェース
│   │   ├── axi4_interconnect.sv  #     AXI4 インターコネクト (1-to-N)
│   │   └── axi4_apb_bridge.sv    #     AXI4-APB ブリッジ
│   ├── memory/                   #   メモリコントローラ
│   │   ├── bram_imem.sv          #     命令メモリ (64KB TDP BRAM, デュアルポート)
│   │   ├── bram_dmem.sv          #     データメモリ (16KB BRAM)
│   │   └── hyperram_ctrl.sv      #     HyperRAM コントローラ
│   ├── rtos/                     #   ハードウェア RTOS エンジン
│   │   ├── hw_rtos.sv            #     RTOS トップモジュール
│   │   ├── task_scheduler.sv     #     タスクスケジューラ
│   │   ├── tcb_array.sv          #     タスク制御ブロック配列
│   │   ├── context_switch.sv     #     コンテキストスイッチ
│   │   ├── hw_semaphore.sv       #     ハードウェアセマフォ
│   │   ├── hw_mutex.sv           #     ハードウェアミューテックス
│   │   ├── hw_msgqueue.sv        #     ハードウェアメッセージキュー
│   │   └── pmp_unit.sv           #     物理メモリ保護ユニット
│   ├── posix/                    #   POSIX ハードウェア層
│   │   └── posix_hw_layer.sv     #     ECALL ディスパッチャ・FD管理
│   ├── interrupt/                #   割り込みコントローラ
│   │   ├── plic.sv               #     PLIC (外部割り込み)
│   │   └── clint.sv              #     CLINT (タイマー/SW割り込み)
│   ├── peripherals/              #   周辺ペリフェラル
│   │   ├── uart_apb.sv           #     UART (APBスレーブ)
│   │   └── gpio_apb.sv           #     GPIO (APBスレーブ)
│   └── top/                      #   システムトップ
│       └── vsync_top.sv         #     SoC トップモジュール
├── tb/                           # テストベンチ (30 tests)
│   ├── core/                     #   コアモジュールテスト
│   ├── bus/                      #   バステスト
│   ├── memory/                   #   メモリテスト
│   ├── rtos/                     #   RTOS テスト
│   ├── posix/                    #   POSIX テスト
│   ├── interrupt/                #   割り込みテスト
│   ├── peripherals/              #   ペリフェラルテスト
│   ├── common/                   #   共通テストユーティリティ・BFM
│   └── run_tests.sh              #   テストランナースクリプト
├── sw/                           # ソフトウェア
│   ├── boot/start.S              #   スタートアップコード
│   ├── lib/                      #   POSIX C ライブラリ / HW レジスタ定義
│   │   ├── vsync_posix.h        #     POSIX API ヘッダ
│   │   ├── vsync_posix.c        #     POSIX API 実装
│   │   └── vsync_hw.h           #     ハードウェアレジスタアドレス定義
│   ├── examples/                 #   サンプルアプリケーション
│   │   ├── hello_uart.c          #     UART Hello World
│   │   ├── gpio_blink.c          #     GPIO LED 点滅
│   │   ├── multitask.c           #     マルチタスクデモ
│   │   └── shell.c               #     UART シェル/モニタ
│   ├── linker/vsync.ld          #   リンカスクリプト
│   └── tools/Makefile            #   ビルドシステム
├── fpga/                         # FPGA ビルド環境
│   ├── scripts/                  #   ビルドスクリプト
│   │   ├── Makefile              #     FPGA ビルドシステム (make)
│   │   ├── build.tcl             #     Full Build (synth+impl+XSA)
│   │   ├── impl_design.tcl       #     Implementation (synth+P&R+bit)
│   │   ├── synth_only.tcl        #     Synthesis only
│   │   ├── program.tcl           #     JTAG プログラミング
│   │   └── sim.tcl               #     Vivado xsim シミュレーション
│   ├── constraints/              #   デバイス制約ファイル
│   └── sim/                      #   シミュレーション用トップ
│       ├── sim_top.sv            #     iverilog 用テストベンチ (25MHz)
│       └── xsim_top.sv           #     Vivado xsim 用テストベンチ (100MHz)
└── doc/                          # 設計ドキュメント
    ├── architecture_block_diagram.md
    ├── pipeline_design.md
    ├── rtos_fsm_design.md
    ├── posix_mapping.md
    ├── address_map.md
    ├── module_io_spec.md
    ├── test_plan.md
    └── top_module_review_checklist.md
```

## Simulation

### Run All Tests

全30テストベンチを一括でコンパイル・実行します:

```bash
./tb/run_tests.sh
```

テスト結果は標準出力に表示され、JSON形式のサマリが `/tmp/vsync_tests/results_summary.json` に保存されます。

### Output Example

```
============================================================
 VSync Test Runner - Sun Feb 22 2026
============================================================

================================================================
 Compiling: tb_alu
================================================================
 [COMPILE OK] tb_alu
----------------------------------------------------------------
 Running: tb_alu (timeout: 60s)
----------------------------------------------------------------
 [PASS] tb_alu (Pass:89 Fail:0)
...

------------------------------------------------------------
 SUMMARY
------------------------------------------------------------
 PASS:          30
 TEST_FAIL:     0
 COMPILE_FAIL:  0
 RUNTIME_FAIL:  0
 Total:         30
============================================================
```

### Individual Test Logs

各テストのログファイルは `/tmp/vsync_tests/` に出力されます:

```bash
# テストログの確認
cat /tmp/vsync_tests/tb_alu.log

# コンパイルログの確認
cat /tmp/vsync_tests/tb_alu_compile.log

# JSON サマリの確認
cat /tmp/vsync_tests/results_summary.json
```

### Run Individual Test Manually

個別のテストベンチを手動でコンパイル・実行することもできます:

```bash
# 1. コンパイル
iverilog -g2012 -DIVERILOG -I rtl/core -I tb/common \
    rtl/core/vsync_pkg.sv \
    rtl/core/alu.sv \
    tb/core/tb_alu.sv \
    -o /tmp/tb_alu_sim

# 2. シミュレーション実行
vvp /tmp/tb_alu_sim

# 3. 波形ファイルが出力された場合 (VCD)
gtkwave tb_alu.vcd
```

### Test Compilation Examples

テストベンチごとに必要なRTLファイルが異なります。以下に代表的な例を示します:

#### ALU 単体テスト (単一モジュール)

```bash
iverilog -g2012 -DIVERILOG -I rtl/core -I tb/common \
    rtl/core/vsync_pkg.sv \
    rtl/core/alu.sv \
    tb/core/tb_alu.sv \
    -o /tmp/tb_alu_sim
vvp /tmp/tb_alu_sim
```

#### パイプライン統合テスト (CPUコア全体)

```bash
iverilog -g2012 -DIVERILOG -I rtl/core -I tb/common \
    rtl/core/vsync_pkg.sv \
    tb/common/clk_rst_gen.sv \
    rtl/core/alu.sv \
    rtl/core/immediate_gen.sv \
    rtl/core/register_file.sv \
    rtl/core/branch_unit.sv \
    rtl/core/decode_stage.sv \
    rtl/core/execute_stage.sv \
    rtl/core/fetch_stage.sv \
    rtl/core/memory_stage.sv \
    rtl/core/writeback_stage.sv \
    rtl/core/hazard_unit.sv \
    rtl/core/csr_unit.sv \
    rtl/core/exception_unit.sv \
    rtl/core/multiplier_divider.sv \
    rtl/core/rv32im_core.sv \
    tb/core/tb_pipeline.sv \
    -o /tmp/tb_pipeline_sim
vvp /tmp/tb_pipeline_sim
```

#### RTOS テスト (ハードウェアRTOSエンジン)

```bash
iverilog -g2012 -DIVERILOG -I rtl/core -I tb/common \
    rtl/core/vsync_pkg.sv \
    tb/common/clk_rst_gen.sv \
    rtl/rtos/task_scheduler.sv \
    rtl/rtos/tcb_array.sv \
    rtl/rtos/context_switch.sv \
    rtl/rtos/hw_semaphore.sv \
    rtl/rtos/hw_mutex.sv \
    rtl/rtos/hw_msgqueue.sv \
    rtl/rtos/pmp_unit.sv \
    rtl/rtos/hw_rtos.sv \
    tb/rtos/test_hw_rtos.sv \
    -o /tmp/test_hw_rtos_sim
vvp /tmp/test_hw_rtos_sim
```

#### POSIX テスト

```bash
iverilog -g2012 -DIVERILOG -I rtl/core -I tb/common \
    rtl/core/vsync_pkg.sv \
    tb/common/clk_rst_gen.sv \
    rtl/posix/posix_hw_layer.sv \
    tb/posix/tb_syscall.sv \
    -o /tmp/tb_syscall_sim
vvp /tmp/tb_syscall_sim
```

### Waveform Viewing

テストベンチは VCD (Value Change Dump) 形式の波形ファイルを出力します。GTKWave で閲覧できます:

```bash
# GTKWave のインストール
sudo apt install gtkwave    # Ubuntu/Debian
brew install gtkwave        # macOS

# 波形表示
gtkwave tb_alu.vcd
```

### Test List

| # | Test Name | Category | Description |
|---|-----------|----------|-------------|
| 1 | tb_alu | Core | ALU 全演算テスト |
| 2 | tb_rv32i_alu | Core | RV32I ALU パイプラインテスト |
| 3 | tb_register_file | Core | レジスタファイル R/W テスト |
| 4 | tb_multiplier_divider | Core | M拡張 乗除算テスト |
| 5 | tb_pipeline | Core | 5段パイプライン統合テスト |
| 6 | tb_csr | Core | CSR レジスタ操作テスト |
| 7 | tb_exception | Core | 例外・割り込み処理テスト |
| 8 | tb_rv32i_branch | Core | 分岐命令テスト |
| 9 | tb_rv32i_loadstore | Core | ロード/ストア命令テスト |
| 10 | tb_rv32m | Core | M拡張命令テスト |
| 11 | tb_axi4_protocol | Bus | AXI4 プロトコルテスト |
| 12 | tb_axi4_apb_bridge | Bus | AXI4-APB ブリッジテスト |
| 13 | tb_bram | Memory | BRAM メモリテスト |
| 14 | tb_hyperram | Memory | HyperRAM コントローラテスト |
| 15 | tb_uart | Peripheral | UART TX/RX テスト |
| 16 | tb_gpio | Peripheral | GPIO I/O テスト |
| 17 | tb_plic | Interrupt | PLIC 割り込みテスト |
| 18 | tb_clint | Interrupt | CLINT タイマーテスト |
| 19 | tb_task_mgmt | RTOS | タスク管理テスト |
| 20 | tb_scheduler | RTOS | スケジューラテスト |
| 21 | tb_context_switch | RTOS | コンテキストスイッチテスト |
| 22 | tb_semaphore | RTOS | セマフォテスト |
| 23 | tb_mutex | RTOS | ミューテックステスト |
| 24 | tb_msgqueue | RTOS | メッセージキューテスト |
| 25 | tb_pmp | RTOS | メモリ保護テスト |
| 26 | test_hw_rtos | RTOS | RTOS 統合テスト |
| 27 | tb_syscall | POSIX | システムコールテスト |
| 28 | tb_pthread | POSIX | pthread テスト |
| 29 | tb_fd | POSIX | ファイルディスクリプタテスト |
| 30 | tb_timer | POSIX | タイマーテスト |
| 31 | test_rv32im_core | Integration | CPUコア統合テスト |

### SoC System-Level Simulation (sim_top)

`fpga/sim/sim_top.sv` は `vsync_top` (SoC全体) をインスタンスし、25MHz クロック・リセットシーケンスを生成するシステムレベルシミュレーション用テストベンチです。`IMEM_INIT_FILE` パラメータで指定した hex ファイルを IMEM にロードして CPU を起動します。

#### 任意のファームウェアで SoC を起動する

```bash
cd fpga/sim

# 1. ファームウェアの hex ファイルを firmware.hex としてコピー
#    例: UART シェル
cp ../../sw/tools/build/shell.hex firmware.hex

#    例: hello_uart
cp ../../sw/tools/build/hello_uart.hex firmware.hex

# 2. コンパイル
iverilog -g2012 -DIVERILOG -I../../rtl/core -o sim_top.vvp \
    ../../rtl/core/vsync_pkg.sv \
    ../../rtl/core/alu.sv \
    ../../rtl/core/immediate_gen.sv \
    ../../rtl/core/register_file.sv \
    ../../rtl/core/branch_unit.sv \
    ../../rtl/core/decode_stage.sv \
    ../../rtl/core/execute_stage.sv \
    ../../rtl/core/fetch_stage.sv \
    ../../rtl/core/memory_stage.sv \
    ../../rtl/core/writeback_stage.sv \
    ../../rtl/core/hazard_unit.sv \
    ../../rtl/core/csr_unit.sv \
    ../../rtl/core/exception_unit.sv \
    ../../rtl/core/multiplier_divider.sv \
    ../../rtl/core/rv32im_core.sv \
    ../../rtl/bus/axi4_master.sv \
    ../../rtl/bus/axi4_interconnect.sv \
    ../../rtl/bus/axi4_apb_bridge.sv \
    ../../rtl/memory/bram_imem.sv \
    ../../rtl/memory/bram_dmem.sv \
    ../../rtl/memory/hyperram_ctrl.sv \
    ../../rtl/peripherals/uart_apb.sv \
    ../../rtl/peripherals/gpio_apb.sv \
    ../../rtl/interrupt/plic.sv \
    ../../rtl/interrupt/clint.sv \
    ../../rtl/rtos/task_scheduler.sv \
    ../../rtl/rtos/tcb_array.sv \
    ../../rtl/rtos/context_switch.sv \
    ../../rtl/rtos/hw_semaphore.sv \
    ../../rtl/rtos/hw_mutex.sv \
    ../../rtl/rtos/hw_msgqueue.sv \
    ../../rtl/rtos/pmp_unit.sv \
    ../../rtl/rtos/hw_rtos.sv \
    ../../rtl/posix/posix_hw_layer.sv \
    ../../rtl/top/vsync_top.sv \
    sim_top.sv

# 3. シミュレーション実行
vvp sim_top.vvp

# 4. 波形確認
gtkwave sim_top.vcd
```

> **Note**: デフォルトでは 5,000 サイクル (50μs) で終了します。長時間の実行が必要な場合は `sim_top.sv` の `TIMEOUT_NS` やサイクル数を調整してください。

#### UART シェルの load/go シミュレーション

UART シェル経由でプログラムをロードし `go` で実行する流れは、主に **FPGA 実機** での使用を想定しています。RTL シミュレーションでは UART のビットタイミング (115200 baud @ 25MHz = **1ビットあたり 217 クロックサイクル**) のため、1コマンドの送受信だけで数十万サイクルが必要になり、非常に低速です。

**load/go の動作原理:**

```
┌──────────┐  UART TX   ┌────────────────────┐
│ ホストPC  │──────────►│ uart_apb (RX FIFO)  │
│ (minicom) │           └─────────┬──────────┘
└──────────┘                     │ APB → AXI4 Bus
                                 ▼
                          ┌──────────────┐
                          │ IMEM (64KB)  │  Port B: データバス経由書込み
                          │ TDP BRAM     │
                          └──────┬───────┘
                          Port A │ 命令フェッチ
                          ┌──────▼───────┐
                          │  RV32IM CPU  │  "go" → ここから実行開始
                          └──────────────┘
```

1. シェルが `load` コマンドを受信 → ロードモードに入る
2. ホストからの各 hex ワードを `REG32(addr) = val` で IMEM (Port B) に書き込み
3. `go` コマンドで割り込みを無効化し、`((void (*)(void))addr)()` でジャンプ
4. CPU は Port A から新プログラムの命令をフェッチして実行開始

**テスト方法の選択ガイド:**

| 方法 | 速度 | 用途 |
|------|------|------|
| `firmware.hex` を直接ロード (sim_top) | ◎ 高速 | ファームウェアの動作検証・デバッグ |
| UART shell load/go (FPGA 実機) | ○ 実時間 | 実機でのプログラムロード・動的入替え |
| UART shell load/go (RTL シミュレーション) | △ 非常に低速 | シェル自体のデバッグ (必要時のみ) |

**推奨**: シミュレーションでプログラムをテストする場合は、テスト対象プログラムの hex ファイルを `firmware.hex` として直接 IMEM にロードする方法が最も効率的です。

```bash
# 例: multitask プログラムを SoC 上で実行
cd fpga/sim
cp ../../sw/tools/build/multitask.hex firmware.hex
vvp sim_top.vvp
```

#### FPGA 実機での UART シェル使用

FPGA に shell ファームウェアを書き込んだ状態で、ホスト PC からターミナルソフトで接続します:

```bash
# minicom で接続
minicom -b 115200 -D /dev/ttyUSB0

# screen で接続
screen /dev/ttyUSB0 115200

# picocom で接続
picocom -b 115200 /dev/ttyUSB0
```

接続後、`load` → hex データ送信 → `go` の操作で新しいプログラムをロード・実行できます:

```
vsync> load
Loading to 0x00000000 ... (empty line or '.' to end)
00000297
01028293
00500313
006282B3
.
Loaded 4 words (16 bytes) to 0x00000000 - 0x0000000C

vsync> go
Jumping to 0x00000000 ...
```

Python スクリプトによる自動送信も可能です (`serial` モジュール使用):

```python
import serial, time

ser = serial.Serial('/dev/ttyUSB0', 115200, timeout=1)

# load コマンド送信
ser.write(b'load\r')
time.sleep(0.1)

# hex ファイルを1行ずつ送信
with open('build/hello_uart.hex', 'r') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('//'):
            ser.write((line + '\r').encode())
            time.sleep(0.01)

# ロード終了 → 実行
ser.write(b'.\r')
time.sleep(0.1)
ser.write(b'go\r')
```

> **注意**: `go` コマンド実行後は shell に戻れません（ロードしたプログラムが shell 領域を上書きするため）。リセットで shell に復帰します。

## Software Build

### Toolchain Setup

VSync のソフトウェアは RISC-V RV32IM ベアメタル環境向けにクロスコンパイルします。

#### RISC-V GCC ツールチェインのインストール

```bash
# Ubuntu/Debian (パッケージマネージャ)
sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf

# macOS (Homebrew)
brew tap riscv-software-src/riscv
brew install riscv-tools

# ソースからビルド (riscv32-unknown-elf ターゲット)
git clone https://github.com/riscv-collab/riscv-gnu-toolchain
cd riscv-gnu-toolchain
./configure --prefix=/opt/riscv --with-arch=rv32im --with-abi=ilp32
make
export PATH=/opt/riscv/bin:$PATH
```

#### ツールチェイン確認

```bash
riscv32-unknown-elf-gcc --version
# riscv32-unknown-elf-gcc (GCC) x.x.x

# riscv64 版でも rv32im ターゲットでコンパイル可能
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 --version
```

> **Note**: `riscv64-unknown-elf-gcc` がインストールされている場合、`sw/tools/Makefile` の `PREFIX` を `riscv64-unknown-elf-` に変更するか、`make PREFIX=riscv64-unknown-elf-` で指定してください。

### Build Flow

ソフトウェアのコンパイルは以下のフローで行われます:

```
 ソースファイル                     共通ファイル
 ┌──────────────┐    ┌──────────────────────────────────┐
 │ examples/    │    │ boot/start.S   (スタートアップ)   │
 │  hello_uart.c│    │ lib/vsync_posix.c (POSIX API)    │
 │  gpio_blink.c│    │ lib/vsync_posix.h (ヘッダ)       │
 │  multitask.c │    │ lib/vsync_hw.h    (HWレジスタ)   │
 │  shell.c     │    │ linker/vsync.ld   (リンカスクリプト)│
 └──────┬───────┘    └──────────┬───────────────────────┘
        │                       │
        └───────────┬───────────┘
                    │
                    ▼
     ┌──────────────────────────────┐
     │  riscv32-unknown-elf-gcc    │
     │  -march=rv32im -mabi=ilp32  │
     │  -Os -nostdlib -ffreestanding│
     │  -T vsync.ld -nostartfiles  │
     └──────────────┬──────────────┘
                    │
                    ▼
              ┌──────────┐
              │ .elf     │  ELF 実行可能ファイル
              └────┬─────┘
                   │
          ┌────────┼────────┐
          ▼        ▼        ▼
     ┌────────┐ ┌──────┐ ┌──────┐
     │ .hex   │ │ .bin │ │ .dump│
     │ Verilog│ │Binary│ │逆asm │
     │ HEX   │ │      │ │      │
     └────────┘ └──────┘ └──────┘
       │            │
       │            └──→ SPI フラッシュ書き込み用
       └──────────────→ $readmemh で IMEM にロード
                        (シミュレーション / FPGA BRAM初期化)
```

各プログラムは `start.S` (スタートアップコード) + `vsync_posix.c` (POSIX ライブラリ) + アプリケーション `.c` ファイルの3つを一括でコンパイル・リンクします。標準ライブラリ (libc) は使用しません。

### Quick Start

```bash
# 0. ツールチェインの PATH 設定 (未設定の場合)
#    インストール先に応じてパスを変更してください
export PATH=/opt/riscv32im/bin:$PATH

# 1. ビルドディレクトリへ移動
cd sw/tools

# 2. 全プログラムをビルド
make all

# 3. ビルド結果確認
ls -la build/
# build/hello_uart.elf  build/hello_uart.hex  build/hello_uart.bin
# build/gpio_blink.elf  build/gpio_blink.hex  build/gpio_blink.bin
# build/multitask.elf   build/multitask.hex   build/multitask.bin
# build/shell.elf       build/shell.hex       build/shell.bin

# 4. コードサイズ確認
riscv32-unknown-elf-size build/*.elf
```

### Build Commands

```bash
cd sw/tools

# 全プログラムビルド
make all

# 個別ビルド
make hello_uart   # UART出力サンプル
make gpio_blink   # GPIO LED点滅サンプル
make multitask    # マルチタスクサンプル
make shell        # UART シェル/モニタ

# 逆アセンブリ生成
make dump         # build/*.dump

# クリーン
make clean

# ツールチェインプレフィックス変更 (riscv64版使用時)
make PREFIX=riscv64-unknown-elf- all

# ヘルプ
make help
```

### Compilation Details

#### コンパイラフラグ

| Flag | Description |
|------|-------------|
| `-march=rv32im` | RV32IM 命令セット (整数 + 乗除算 M拡張) |
| `-mabi=ilp32` | ILP32 ABI (int/long/pointer = 32-bit) |
| `-Os` | サイズ最適化 |
| `-nostdlib` | 標準ライブラリをリンクしない |
| `-ffreestanding` | フリースタンディング環境 (OS なし) |
| `-fno-builtin` | GCC 組み込み関数を使用しない |
| `-ffunction-sections` | 関数ごとにセクション分割 (未使用関数の削除用) |
| `-fdata-sections` | データごとにセクション分割 (未使用データの削除用) |

#### リンカフラグ

| Flag | Description |
|------|-------------|
| `-T vsync.ld` | VSync 用リンカスクリプト |
| `-nostartfiles` | デフォルトのスタートアップファイルを使用しない |
| `-Wl,--gc-sections` | 未使用セクションをガベージコレクション |

#### 手動コンパイル (Makefile を使わない場合)

```bash
# 1. コンパイル + リンク → ELF
riscv32-unknown-elf-gcc \
    -march=rv32im -mabi=ilp32 -Os \
    -nostdlib -ffreestanding -fno-builtin \
    -ffunction-sections -fdata-sections \
    -T sw/linker/vsync.ld -nostartfiles \
    -Wl,--gc-sections \
    -o build/hello_uart.elf \
    sw/boot/start.S \
    sw/lib/vsync_posix.c \
    sw/examples/hello_uart.c

# 2. ELF → Verilog HEX (シミュレーション / BRAM 初期化用)
riscv32-unknown-elf-objcopy -O verilog build/hello_uart.elf build/hello_uart.hex

# 3. ELF → Binary (SPI フラッシュ書き込み用)
riscv32-unknown-elf-objcopy -O binary build/hello_uart.elf build/hello_uart.bin

# 4. 逆アセンブリ (デバッグ用)
riscv32-unknown-elf-objdump -d -S build/hello_uart.elf > build/hello_uart.dump
```

### Memory Layout

リンカスクリプト (`sw/linker/vsync.ld`) で定義されるメモリレイアウト:

```
 アドレス空間                              セクション配置
 ┌──────────────────────┐ 0x0000_0000
 │                      │  .text.init  ← _start (エントリポイント)
 │  IMEM (64KB)         │  .text       ← アプリケーションコード
 │  命令メモリ (rx)     │  .rodata     ← 読み取り専用データ (文字列等)
 │                      │  .data (LMA) ← 初期値データの ROM 側コピー
 ├──────────────────────┤ 0x0001_0000
 │                      │  .data (VMA) ← 初期値付きグローバル変数
 │  DMEM (16KB)         │  .bss        ← ゼロ初期化グローバル変数
 │  データメモリ (rwx)  │  .stack (4KB)← スタック領域
 │                      │  .heap  (4KB)← ヒープ領域
 ├──────────────────────┤ 0x0001_4000
 │        ...           │
 ├──────────────────────┤ 0x2000_0000
 │  HyperRAM (256MB)    │  (将来拡張用)
 │  外部メモリ (rwx)    │
 └──────────────────────┘ 0x3000_0000
```

#### スタートアップシーケンス (`boot/start.S`)

1. 割り込み無効化 (`csrci mstatus, 0x8`)
2. スタックポインタ初期化 (SP = `0x00013FFC`)
3. グローバルポインタ初期化 (GP = `__global_pointer$`)
4. トラップベクタ設定 (`mtvec` = `_trap_handler`)
5. BSS セクションゼロクリア (`_bss_start` → `_bss_end`)
6. `.data` セクション初期化 (ROM→RAM コピー: `_data_load` → `_data_start`)
7. Hart ID 取得 (`a0` = `mhartid`)
8. 割り込み有効化 (`csrsi mstatus, 0x8`)
9. `main()` 呼び出し
10. `main()` 復帰後: `pthread_exit(0)` syscall で終了

### Build Output

ビルド成果物は `sw/tools/build/` に出力されます:

| File | Format | Description | 用途 |
|------|--------|-------------|------|
| `*.elf` | ELF | 実行可能ファイル | `objdump` による解析、デバッグ |
| `*.hex` | Verilog HEX | `$readmemh` 互換 | シミュレーション IMEM ロード、FPGA BRAM 初期化 |
| `*.bin` | Raw Binary | フラットバイナリ | SPI フラッシュ書き込み |
| `*.dump` | Text | 逆アセンブリ (`make dump` で生成) | デバッグ、コード検証 |

### Writing Your Own Program

#### 最小限のプログラム

```c
/* my_app.c */
#include "../lib/vsync_posix.h"

int main(void)
{
    /* UART デバイスを開く */
    int fd = open(FD_TYPE_UART, 0);
    if (fd < 0) return -1;

    /* メッセージ送信 */
    const char msg[] = "Hello from my app!\n";
    write(fd, msg, sizeof(msg) - 1);

    /* デバイスを閉じる */
    close(fd);
    return 0;
}
```

#### ビルド方法

```bash
# 方法1: Makefile に追加
# sw/tools/Makefile の EXAMPLES に追加:
#   EXAMPLES = hello_uart gpio_blink multitask shell my_app
# ソースファイルを sw/examples/my_app.c に配置して:
cd sw/tools && make my_app

# 方法2: 手動コンパイル
riscv32-unknown-elf-gcc \
    -march=rv32im -mabi=ilp32 -Os \
    -nostdlib -ffreestanding -fno-builtin \
    -ffunction-sections -fdata-sections \
    -T sw/linker/vsync.ld -nostartfiles -Wl,--gc-sections \
    -o build/my_app.elf \
    sw/boot/start.S sw/lib/vsync_posix.c sw/examples/my_app.c

riscv32-unknown-elf-objcopy -O verilog build/my_app.elf build/my_app.hex
```

#### シミュレーションで実行

```bash
# コンパイルした hex をシミュレーションで実行
cp sw/tools/build/my_app.hex fpga/sim/firmware.hex
cd fpga/sim
iverilog -g2012 -DIVERILOG -I../../rtl/core -o sim_top.vvp \
    ../../rtl/core/vsync_pkg.sv \
    ../../rtl/core/alu.sv \
    ../../rtl/core/immediate_gen.sv \
    ../../rtl/core/register_file.sv \
    ../../rtl/core/branch_unit.sv \
    ../../rtl/core/decode_stage.sv \
    ../../rtl/core/execute_stage.sv \
    ../../rtl/core/fetch_stage.sv \
    ../../rtl/core/memory_stage.sv \
    ../../rtl/core/writeback_stage.sv \
    ../../rtl/core/hazard_unit.sv \
    ../../rtl/core/csr_unit.sv \
    ../../rtl/core/exception_unit.sv \
    ../../rtl/core/multiplier_divider.sv \
    ../../rtl/core/rv32im_core.sv \
    ../../rtl/bus/axi4_master.sv \
    ../../rtl/bus/axi4_interconnect.sv \
    ../../rtl/bus/axi4_apb_bridge.sv \
    ../../rtl/memory/bram_imem.sv \
    ../../rtl/memory/bram_dmem.sv \
    ../../rtl/memory/hyperram_ctrl.sv \
    ../../rtl/peripherals/uart_apb.sv \
    ../../rtl/peripherals/gpio_apb.sv \
    ../../rtl/interrupt/plic.sv \
    ../../rtl/interrupt/clint.sv \
    ../../rtl/rtos/tcb_array.sv \
    ../../rtl/rtos/task_scheduler.sv \
    ../../rtl/rtos/context_switch.sv \
    ../../rtl/rtos/hw_semaphore.sv \
    ../../rtl/rtos/hw_mutex.sv \
    ../../rtl/rtos/hw_msgqueue.sv \
    ../../rtl/rtos/pmp_unit.sv \
    ../../rtl/rtos/hw_rtos.sv \
    ../../rtl/posix/posix_hw_layer.sv \
    ../../rtl/top/vsync_top.sv \
    sim_top.sv
vvp sim_top.vvp
gtkwave sim_top.vcd
```

#### FPGA 実機で実行

```bash
# 方法1: BRAM 初期化 (make build で shell.hex を IMEM にロード)
cd fpga/scripts
make build

# 方法2: UART シェル経由でプログラムをロード
# (FPGA に shell ファームウェアが書き込まれている状態で)
# ターミナルソフトで接続 → load → hex 送信 → go
```

#### プログラミング上の注意

- **標準ライブラリなし**: `printf()`, `malloc()`, `memcpy()` 等は使用不可。POSIX API (`vsync_posix.h`) またはハードウェアレジスタ直接アクセス (`vsync_hw.h`) を使用
- **IMEM サイズ制限**: コード + 読み取り専用データ + `.data` 初期値が合計 64KB 以内
- **DMEM サイズ制限**: グローバル変数 + スタック (4KB) + ヒープ (4KB) が合計 16KB 以内
- **エントリポイント**: `main()` 関数を定義すること (`start.S` から呼び出される)
- **復帰処理**: `main()` から `return` すると `pthread_exit(0)` が自動実行される

### Example Programs

| Program | Description |
|---------|-------------|
| `hello_uart.c` | UART経由で "Hello VSync!" メッセージを送信 |
| `gpio_blink.c` | GPIO LEDを500msec間隔で点滅 |
| `multitask.c` | 2タスク生成、セマフォで同期 |
| `shell.c` | UART対話シェル/モニタプログラム (load/go によるプログラムローディング対応) |

### UART Shell / Monitor

`shell.c` は UART (115200 8N1) 経由でプロセッサを対話的に操作できるシェルプログラムです。メモリ読み書き、RTOS 状態監視、GPIO 制御などデバッグ・モニタリング機能に加え、`load`/`go` コマンドによる UART 経由のプログラムロード・実行機能を提供します。

```bash
cd sw/tools
make shell
# build/shell.hex を FPGA の IMEM にロードして使用
```

ターミナルソフト (minicom, screen, TeraTerm 等) で UART に接続すると、以下のプロンプトが表示されます:

```
========================================
  VSync Monitor Shell v1.0
  RISC-V RV32IM Hardware RTOS Processor
  UART: 115200 8N1
========================================
Type 'help' for command list.

vsync>
```

#### Shell Commands

| Command | Syntax | Description |
|---------|--------|-------------|
| `help` | `help` | コマンド一覧表示 |
| `peek` | `peek <addr> [count]` | メモリ読み出し (hex アドレス、最大16ワード) |
| `poke` | `poke <addr> <value>` | メモリ書き込み (hex アドレス・値、書き込み後リードバック表示) |
| `load` | `load [addr]` | UART 経由で hex ワードを受信しメモリに書き込み (デフォルト: IMEM先頭) |
| `go` | `go [addr]` | 指定アドレスにジャンプして実行 (デフォルト: IMEM先頭) |
| `rtos` | `rtos` | RTOS スケジューラ状態表示 (FSM, タスク数, タイムスライス等) |
| `gpio` | `gpio` | GPIO 全レジスタ表示 |
| `gpio read` | `gpio read` | GPIO 入力値表示 |
| `gpio write` | `gpio write <val>` | GPIO 出力値設定 (hex) |
| `gpio dir` | `gpio dir <mask>` | GPIO 方向設定 (hex, 1=出力) |
| `uart` | `uart` | UART ステータス・制御レジスタ表示 |
| `info` | `info` | システム情報 (メモリマップ) |
| `uptime` | `uptime` | 稼働時間 (CLINT mtime から計算、HH:MM:SS 表示) |

#### Usage Examples

```
vsync> peek 10000000 4
0x10000000: 0x00000000
0x10000004: 0x00000000
0x10000008: 0x0000000A
0x1000000C: 0x0000000C

vsync> gpio dir 000F
GPIO DIR <- 0x0000000F

vsync> gpio write 0005
GPIO OUT <- 0x00000005

vsync> rtos
=== RTOS Scheduler State ===
  Scheduler Enable : ON
  Current Task ID  : 0
  Task Count       : 1 / 16
  FSM State        : IDLE (0)
  ...

vsync> uptime
Uptime: 00:01:23
Ticks : 0x00000001_D5C31A00
```

#### UART Program Loading

`load` / `go` コマンドにより、UART 経由で新しいプログラムを IMEM にロードし実行できます。
IMEM はデュアルポート TDP BRAM として実装されており、CPU の命令フェッチ (Port A) と同時にデータバス経由の読み書き (Port B) が可能です。

**ロード手順:**

1. ホスト PC でプログラムを `$readmemh` 互換の hex 形式に変換
2. シェルの `load` コマンドでロードモードに入る
3. 1行1ワード (8桁 hex) でデータを送信
4. 空行または `.` で終了
5. `go` コマンドでロードしたプログラムを実行

```
vsync> load
Loading to 0x00000000 ... (empty line or '.' to end)
00000297
01028293
00500313
006282B3
.
Loaded 4 words (16 bytes) to 0x00000000 - 0x0000000C

vsync> go
Jumping to 0x00000000 ...
```

**データ形式:**
- 各行は 8桁の hex ワード (例: `DEADBEEF`)
- `0x` プレフィックス付きも可 (例: `0xDEADBEEF`)
- `#` で始まる行はコメントとしてスキップ
- `@` で始まる行もスキップ (アドレスマーカー用)
- 空行または `.` でロード終了

**ホスト側の送信例 (Python):**

```python
import serial
import time

ser = serial.Serial('/dev/ttyUSB0', 115200, timeout=1)

# load コマンド送信
ser.write(b'load\r')
time.sleep(0.1)

# hex ファイルを1行ずつ送信
with open('build/program.hex', 'r') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('//'):
            ser.write((line + '\r').encode())
            time.sleep(0.01)

# ロード終了
ser.write(b'.\r')
time.sleep(0.1)

# 実行
ser.write(b'go\r')
```

> **注意**: `go` コマンドは割り込みを無効化してから指定アドレスにジャンプします。ロードしたプログラムが shell 自身の IMEM 領域を上書きするため、復帰はできません（リセットで shell に戻ります）。

#### Hardware Header

`sw/lib/vsync_hw.h` は全ペリフェラルのMMIOレジスタアドレスを定義した共有ヘッダです。シェル以外のアプリケーションでも直接ハードウェアレジスタにアクセスする際に利用できます:

```c
#include "vsync_hw.h"

// 直接レジスタアクセス
uint32_t status = REG32(UART_BASE + UART_STATUS);
REG32(GPIO_BASE + GPIO_OUT) = 0xFF;
```

### POSIX API

`sw/lib/vsync_posix.h` で以下のPOSIX APIが利用できます:

```c
#include "vsync_posix.h"

// Thread
pthread_create(&tid, NULL, func, arg);
pthread_exit(NULL);
pthread_join(tid, NULL);
pthread_yield();

// Mutex
pthread_mutex_lock(&mtx);
pthread_mutex_unlock(&mtx);

// Semaphore
sem_wait(&sem);
sem_post(&sem);

// Message Queue
mq_send(mqd, msg, len, prio);
mq_receive(mqd, msg, len, &prio);

// Timer
nanosleep(&ts, NULL);

// File I/O
int fd = open("/dev/uart0", O_RDWR);
write(fd, buf, len);
read(fd, buf, len);
close(fd);
```

## FPGA Build

### Target Devices

本プロジェクトは2つのFPGAプラットフォームに対応しています:

| Item | Artix UltraScale+ | Arty-A7 (Artix-7) |
|------|-------------------|-------------------|
| **Device** | `xcau7p-sbvc484-2-i` | `xc7a100tcsg324-1` |
| **Board** | - | Digilent Arty-A7-100T |
| **Clock** | 50 MHz | 25 MHz (MMCM) |
| **Vivado** | 2025.2 | 2025.1 (*) |
| **Process** | 16nm UltraScale+ | 28nm 7-series |
| **I/O** | UART, GPIO (16-bit), HyperRAM, JTAG | UART (USB), GPIO (Pmod), HyperRAM, JTAG |

> (*) Vivado 2025.2 には Artix-7 (7-series) デバイスが含まれていないため、Arty-A7 ターゲットには Vivado 2025.1 を使用します。

### Vivado Build (Make)

`fpga/scripts/Makefile` を使用して、`make` コマンドで Vivado ビルドを実行できます:

```bash
cd fpga/scripts

# Full Implementation: 合成 + 配置配線 + Bitstream生成 (デフォルト)
make

# Synthesis only (合成のみ、素早い検証用)
make synth

# Full Build: 合成 + Implementation + Bitstream + XSA export
make build

# JTAG経由で Arty-A7 に書き込み
make program

# ビルド成果物を削除
make clean

# ターゲット一覧表示
make help
```

#### Make Targets

| Target | Description | TCL Script |
|--------|-------------|------------|
| `make impl` | 合成 + P&R + Bitstream (デフォルト) | impl_design.tcl |
| `make synth` | 合成のみ (素早い検証用) | synth_only.tcl |
| `make build` | Full Build + XSA export (Vitis用) | build.tcl |
| `make program` | JTAG経由でArty-A7に書き込み | program.tcl |
| `make clean` | ビルド成果物を削除 | - |
| `make help` | ターゲット一覧表示 | - |

### Vivado Simulation (xsim)

Vivado xsim を使用した behavioral シミュレーションを実行できます。iverilog シミュレーションと異なり、MMCME2_BASE 等の Xilinx プリミティブの振る舞いモデルが利用可能です。

| Target | Description |
|--------|-------------|
| `make sim` | Vivado xsim バッチシミュレーション (コンソール実行) |
| `make sim-gui` | Vivado xsim GUI シミュレーション (波形ビューワ付き) |

```bash
cd fpga/scripts

# バッチシミュレーション
make sim

# GUI シミュレーション (Vivado 波形ビューワ付き)
make sim-gui
```

#### iverilog vs Vivado xsim

| 項目 | iverilog (sim_top.sv) | Vivado xsim (xsim_top.sv) |
|------|----------------------|---------------------------|
| クロック | 25 MHz (40 ns) | 100 MHz (10 ns) |
| MMCM | バイパス (`IVERILOG` define) | unisim モデル使用 |
| リセット解除 | 固定サイクル後 | MMCM lock 待ち |
| 実行サイクル | 5,000 cycles | 10,000 cycles |
| タイムアウト | 100 us | 500 us |
| Xilinx プリミティブ | 未対応 | MMCME2_BASE, BUFG 等対応 |
| 必要ツール | iverilog | Xilinx Vivado |

> **Note**: xsim シミュレーションには Xilinx Vivado のインストールが必要です。iverilog テスト (`./tb/run_tests.sh`) は引き続き Vivado なしで実行可能です。

#### Vivado パスの指定

デフォルトでは `vivado` コマンドが PATH 上にあることを前提とします。
パスを明示する場合は `VIVADO` 変数を指定してください:

```bash
make VIVADO=/opt/Xilinx/Vivado/2025.1/bin/vivado impl
```

#### TCL スクリプト直接実行

`make` を使わず TCL スクリプトを直接実行することも可能です:

```bash
cd fpga/scripts

# Synthesis only (合成のみ)
vivado -mode batch -nolog -nojournal -source synth_only.tcl

# Full Implementation (合成 + 配置配線 + Bitstream生成)
vivado -mode batch -nolog -nojournal -source impl_design.tcl
```

### Implementation Results

#### Artix UltraScale+ (xcau7p @ 50 MHz)

| Metric | Value | Status |
|--------|-------|--------|
| Post-route WNS (Setup) | +4.648 ns | **MET** |
| Post-route WHS (Hold) | +0.017 ns | **MET** |

| Resource | Used | Available | Util% |
|----------|------|-----------|-------|
| CLB LUTs | 13,417 | 37,440 | 35.84% |
| CLB Registers | 23,915 | 74,880 | 31.94% |
| Block RAM (36Kb) | 20 | 108 | 18.52% |
| DSP48E2 | 12 | 216 | 5.56% |

#### Arty-A7 (xc7a100t @ 25 MHz)

| Metric | Value | Status |
|--------|-------|--------|
| Post-route WNS (Setup) | +0.450 ns | **MET** |
| Post-route WHS (Hold) | +0.059 ns | **MET** |

| Resource | Used | Available | Util% |
|----------|------|-----------|-------|
| Slice LUTs | 13,598 | 63,400 | 21.45% |
| Slice Registers | 23,916 | 126,800 | 18.86% |
| Block RAM (36Kb) | 20 | 135 | 14.81% |
| DSP48E1 | 12 | 240 | 5.00% |

> **Note**: RTLは推論記述 (inference) を使用しているため、BRAM/DSP/CARRY はデバイスファミリ間で自動変換されます (例: DSP48E2 ↔ DSP48E1, RAMB36E2 ↔ RAMB36E1, CARRY8 ↔ CARRY4)。

### Build Output

成果物は `fpga/scripts/output_impl/` に出力されます:

| File | Description |
|------|-------------|
| `vsync_top.bit` | FPGA ビットストリーム |
| `vsync_top.bin` | SPI フラッシュバイナリ |
| `post_route_timing.rpt` | タイミングレポート |
| `post_route_utilization.rpt` | リソース使用率レポート |
| `post_route_drc.rpt` | DRC チェックレポート |

### Arty-A7 Pin Mapping

| Signal | Pin | Description |
|--------|-----|-------------|
| Clock (100MHz osc) | E3 | オンボードオシレータ → MMCM で 25 MHz に分周 |
| Reset | D9 | BTN0 (プッシュボタン) |
| UART TX | D10 | USB-UART (FTDI) |
| UART RX | A9 | USB-UART (FTDI) |
| GPIO[0:7] | G13,B11,A11,D12,D13,B18,A18,K16 | Pmod JA |
| GPIO[8:15] | E15,E16,D15,C15,J17,J18,K15,J15 | Pmod JB |

## Architecture

```
                         VSync SoC
  ┌──────────────────────────────────────────────────────────┐
  │                                                          │
  │  ┌─────────────┐    Port A   ┌──────────────┐           │
  │  │  RV32IM CPU │◄───(fetch)──│ IMEM (64KB)  │           │
  │  │  5-Stage    │             │ Dual-Port    │           │
  │  │  Pipeline   │             │ TDP BRAM     │           │
  │  └──────┬──────┘             └──────┬───────┘           │
  │         │                    Port B │(data bus R/W)     │
  │  ┌──────▼──────┐                    │                   │
  │  │ AXI4 Master │                    │                   │
  │  └──────┬──────┘                    │                   │
  │         │                           │                   │
  │  ┌──────▼───────────────────────────┼────────────┐      │
  │  │         AXI4 Interconnect (1-to-6)            │      │
  │  └──┬────┬────┬──────┬──────┬───────┘────────────┘      │
  │     │    │    │      │      │                           │
  │     ▼    │    ▼      ▼      ▼                           │
  │   DMEM   │  HyperRAM RTOS  POSIX                       │
  │  (16KB)  │   Ctrl   Engine Layer                       │
  │          ▼                                             │
  │    ┌───────────┐                                       │
  │    │AXI4→APB   │                                       │
  │    │  Bridge   │                                       │
  │    └──┬──┬──┬──┘                                       │
  │       │  │  │         ┌──────────┐                     │
  │       ▼  ▼  ▼         │  CLINT   │◄─ APB              │
  │    UART GPIO PLIC     │  Timer   │                     │
  │                       └──────────┘                     │
  │                                                        │
  │  ┌─────────────────────────────────────────┐           │
  │  │  Hardware RTOS Engine                   │           │
  │  │  ┌──────────┐ ┌───────────┐ ┌────────┐ │           │
  │  │  │Scheduler │ │Context SW │ │TCB Array│ │           │
  │  │  └──────────┘ └───────────┘ └────────┘ │           │
  │  │  ┌──────────┐ ┌───────────┐ ┌────────┐ │           │
  │  │  │Semaphore │ │  Mutex    │ │MsgQueue│ │           │
  │  │  └──────────┘ └───────────┘ └────────┘ │           │
  │  │  ┌──────────┐                          │           │
  │  │  │   PMP    │                          │           │
  │  │  └──────────┘                          │           │
  │  └─────────────────────────────────────────┘           │
  └────────────────────────────────────────────────────────┘
```

### AXI4 Interconnect Slave Mapping

| Index | Slave | Address Range |
|-------|-------|---------------|
| [0] | DMEM (AXI-to-BRAM bridge) | `0x0001_0000` - `0x0001_3FFF` |
| [1] | HyperRAM Controller | `0x2000_0000` - `0x2FFF_FFFF` |
| [2] | APB Bridge (CLINT/PLIC/UART/GPIO) | 複数レンジ |
| [3] | Hardware RTOS Engine | `0x1100_0000` - `0x1100_FFFF` |
| [4] | POSIX Hardware Layer | `0x1200_0000` - `0x1200_FFFF` |
| [5] | IMEM (AXI-to-BRAM bridge) | `0x0000_0000` - `0x0000_FFFF` |

### Memory Map

| Address Range | Size | Peripheral |
|---------------|------|------------|
| `0x0000_0000` - `0x0000_FFFF` | 64KB | Instruction Memory (IMEM) |
| `0x0001_0000` - `0x0001_3FFF` | 16KB | Data Memory (DMEM) |
| `0x0200_0000` - `0x0200_FFFF` | 64KB | CLINT |
| `0x0C00_0000` - `0x0C00_0FFF` | 4KB | PLIC |
| `0x1000_0000` - `0x1000_00FF` | 256B | UART |
| `0x1000_0100` - `0x1000_01FF` | 256B | GPIO |
| `0x1100_0000` - `0x1100_FFFF` | 64KB | Hardware RTOS |
| `0x1200_0000` - `0x1200_FFFF` | 64KB | POSIX Layer |
| `0x2000_0000` - `0x2FFF_FFFF` | 256MB | HyperRAM |

## Documentation

設計ドキュメントは `doc/` ディレクトリにあります:

| Document | Description |
|----------|-------------|
| [architecture_block_diagram.md](doc/architecture_block_diagram.md) | システムアーキテクチャ ブロック図 |
| [pipeline_design.md](doc/pipeline_design.md) | 5段パイプライン設計・ハザード処理 |
| [rtos_fsm_design.md](doc/rtos_fsm_design.md) | RTOS ステートマシン設計 |
| [posix_mapping.md](doc/posix_mapping.md) | POSIX API → ハードウェアマッピング |
| [address_map.md](doc/address_map.md) | メモリアドレスマップ |
| [module_io_spec.md](doc/module_io_spec.md) | モジュール I/O 仕様 |
| [test_plan.md](doc/test_plan.md) | テスト計画・カバレッジ |
| [top_module_review_checklist.md](doc/top_module_review_checklist.md) | システム統合チェックリスト |

## License

This project is provided as-is for educational and research purposes.
