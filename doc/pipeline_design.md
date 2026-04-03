# パイプラインステージ詳細設計

| 項目 | 内容 |
|---|---|
| ドキュメントID | TASK-LD004 |
| バージョン | 1.0 |
| 作成日 | 2026-02-21 |
| 対象モジュール | rv32im_core |
| ISA | RISC-V RV32IM (Integer + Multiply/Divide) |
| パイプライン段数 | 5段 (IF → ID → EX → MEM → WB) |

---

## 目次

1. [5段パイプライン各段の処理内容](#1-5段パイプライン各段の処理内容)
2. [パイプラインレジスタ定義](#2-パイプラインレジスタ定義)
3. [ハザード検出ロジック](#3-ハザード検出ロジック)
4. [データフォワーディングパス](#4-データフォワーディングパス)
5. [分岐予測・フラッシュ制御](#5-分岐予測フラッシュ制御)
6. [例外/割り込みのパイプライン挿入ポイント](#6-例外割り込みのパイプライン挿入ポイント)

---

## 1. 5段パイプライン各段の処理内容

### パイプライン概要図

```
    +--------+    +--------+    +--------+    +--------+    +--------+
    |   IF   |--->|   ID   |--->|   EX   |--->|  MEM   |--->|   WB   |
    | Fetch  |    | Decode |    |Execute |    | Memory |    |Write-  |
    |        |    |        |    |        |    | Access |    | back   |
    +--------+    +--------+    +--------+    +--------+    +--------+
         |             |             |             |             |
     [IF/ID reg]  [ID/EX reg]  [EX/MEM reg] [MEM/WB reg]       |
         |             |             |             |             |
         |<--- Forwarding Path (EX→EX, MEM→EX) ---|-------------|
         |             |             |
         |<--- Hazard Detection ---->|
         |             |
         |<--- Flush/Stall Control --|
```

### 1.1 IF (Instruction Fetch) ステージ

#### 機能概要
プログラムカウンタ(PC)が指すアドレスから命令メモリ(BRAM)を読み出し、次のPCを計算する。

#### PC管理

| PC更新条件 | PCソース | 優先度 |
|---|---|---|
| 例外/割り込み発生 | mtvec (ベクタテーブル) | 最高 (1) |
| MRET命令実行 | mepc (退避PC) | 高 (2) |
| RTOSコンテキストスイッチ | RTOS復帰PC | 高 (3) |
| 分岐予測ミス (EX段確定) | 分岐先アドレス / PC+4 | 中 (4) |
| 分岐予測 (taken予測) | 予測分岐先 | 低 (5) |
| 通常 | PC + 4 | 最低 (6) |

```
PC更新MUX:
                         +-----+
  PC + 4 -------------->|     |
  branch_predict_target->| MUX |--> next_pc --> PC Register
  branch_actual_target ->|     |
  rtos_restore_pc ------>|     |
  mepc ----------------->|     |
  mtvec ---------------->|     |
                         +-----+
                            ^
                            |
                      pc_sel[2:0] (優先度エンコード)
```

#### 命令メモリアクセス
- BRAM同期読み出し (1サイクルレイテンシ)
- アドレス: `pc[15:0]` (64KB命令メモリ = 16ビットアドレス)
- ワード境界アクセス: `pc[1:0]` が `2'b00` であることを前提 (ミスアラインは例外)
- 読み出しデータ: 32ビット命令

#### 分岐予測器入力
- 命令アドレス(PC)を分岐予測器に入力
- 予測結果に基づき次PCを選択
- 詳細は [5. 分岐予測・フラッシュ制御](#5-分岐予測フラッシュ制御) を参照

#### RTOS割り込みによるPC変更
- `rtos_ctx_switch_req` 信号がアサートされた場合、RTOSから提供される復帰PCに切り替え
- コンテキストスイッチ中はパイプラインストール

#### IF段出力
- `pc`: 現在のプログラムカウンタ値
- `instruction`: BRAMから読み出した32ビット命令
- `valid`: 命令の有効性 (フラッシュ時は0)
- `predicted_taken`: 分岐予測結果
- `predicted_target`: 予測分岐先アドレス

---

### 1.2 ID (Instruction Decode) ステージ

#### 機能概要
IF段から受け取った命令をデコードし、レジスタファイルの読み出し、即値生成、制御信号生成を行う。

#### 命令デコード (RV32IM全命令)

| 命令型 | opcode [6:0] | 対象命令 |
|---|---|---|
| R型 | `0110011` | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU |
| I型 | `0010011` | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI |
| I型 (Load) | `0000011` | LB, LH, LW, LBU, LHU |
| I型 (JALR) | `1100111` | JALR |
| S型 | `0100011` | SB, SH, SW |
| B型 | `1100011` | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| U型 | `0110111` | LUI |
| U型 | `0010111` | AUIPC |
| J型 | `1101111` | JAL |
| SYSTEM | `1110011` | ECALL, EBREAK, MRET, CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI |
| FENCE | `0001111` | FENCE (NOP扱い) |

#### レジスタファイル読み出し
- 32本 x 32ビット汎用レジスタ (x0〜x31)
- x0は常に0を返す (ハードワイヤド)
- 2ポート読み出し (rs1, rs2) + 1ポート書き込み (rd)
- 読み出しはID段の前半、書き込みはWB段の前半 (同一サイクルでの読み書きは書き込み優先: Write-First方式)

```
レジスタファイル:
  rs1_addr [4:0] = instruction[19:15]
  rs2_addr [4:0] = instruction[24:20]
  rd_addr  [4:0] = instruction[11:7]

  rs1_data [31:0] = (rs1_addr == 5'b0) ? 32'b0 : regfile[rs1_addr]
  rs2_data [31:0] = (rs2_addr == 5'b0) ? 32'b0 : regfile[rs2_addr]
```

#### 即値生成 (Immediate Generator)

| 命令型 | 即値ビットフィールド | 符号拡張 |
|---|---|---|
| I型 | `{inst[31], inst[30:20]}` → 符号拡張32ビット | inst[31] |
| S型 | `{inst[31], inst[30:25], inst[11:7]}` → 符号拡張32ビット | inst[31] |
| B型 | `{inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}` → 符号拡張32ビット | inst[31] |
| U型 | `{inst[31:12], 12'b0}` | - |
| J型 | `{inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}` → 符号拡張32ビット | inst[31] |

#### 制御信号生成

| 制御信号 | ビット幅 | 説明 |
|---|---|---|
| `alu_op` | [3:0] | ALU演算種別 (ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU) |
| `alu_src_a` | [1:0] | ALU入力A選択 (RS1 / PC / 0) |
| `alu_src_b` | [1:0] | ALU入力B選択 (RS2 / IMM / 4) |
| `mem_read` | [0:0] | メモリ読み出し有効 |
| `mem_write` | [0:0] | メモリ書き込み有効 |
| `mem_size` | [1:0] | メモリアクセスサイズ (Byte/Half/Word) |
| `mem_unsigned` | [0:0] | 符号なしロード |
| `reg_write` | [0:0] | レジスタ書き込み有効 |
| `wb_sel` | [1:0] | 書き戻しデータ選択 (ALU / MEM / PC+4 / CSR) |
| `branch_op` | [2:0] | 分岐条件種別 (BEQ/BNE/BLT/BGE/BLTU/BGEU) |
| `is_branch` | [0:0] | 分岐命令フラグ |
| `is_jal` | [0:0] | JAL命令フラグ |
| `is_jalr` | [0:0] | JALR命令フラグ |
| `csr_op` | [1:0] | CSR操作種別 (NONE/RW/RS/RC) |
| `csr_addr` | [11:0] | CSRアドレス |
| `csr_imm` | [0:0] | CSR即値モード (CSRRWI/CSRRSI/CSRRCI) |
| `is_ecall` | [0:0] | ECALL命令検出 |
| `is_ebreak` | [0:0] | EBREAK命令検出 |
| `is_mret` | [0:0] | MRET命令検出 |
| `is_mul_div` | [0:0] | M拡張命令フラグ |
| `mul_div_op` | [2:0] | 乗除算種別 (MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU) |
| `illegal_instr` | [0:0] | 不正命令検出 |

#### ハザード検出ユニット入力
- `id_rs1_addr`, `id_rs2_addr`: ID段のソースレジスタアドレス
- `ex_rd_addr`, `ex_mem_read`: EX段の宛先レジスタおよびメモリ読み出しフラグ
- ロード使用ハザード検出時: IF段とID段をストール、EX段にNOP(バブル)挿入

#### ECALL命令検出 → POSIX syscallトリガ
- `opcode == 7'b1110011` かつ `funct3 == 3'b000` かつ `instruction[31:20] == 12'b0`
- `is_ecall` 信号をアサート → 例外処理パスへ
- ECALLは同期例外として処理 (mcause = 11: Environment call from M-mode)

---

### 1.3 EX (Execute) ステージ

#### 機能概要
ALU演算、乗除算、分岐条件判定、メモリアドレス計算を実行する。

#### ALU演算

| alu_op | 演算 | 動作 |
|---|---|---|
| 4'b0000 | ADD | rs1 + op2 |
| 4'b0001 | SUB | rs1 - op2 |
| 4'b0010 | AND | rs1 & op2 |
| 4'b0011 | OR | rs1 \| op2 |
| 4'b0100 | XOR | rs1 ^ op2 |
| 4'b0101 | SLL | rs1 << op2[4:0] |
| 4'b0110 | SRL | rs1 >> op2[4:0] (論理) |
| 4'b0111 | SRA | rs1 >>> op2[4:0] (算術) |
| 4'b1000 | SLT | (rs1 < op2) ? 1 : 0 (符号付き) |
| 4'b1001 | SLTU | (rs1 < op2) ? 1 : 0 (符号なし) |
| 4'b1010 | LUI_PASS | op2 パススルー (LUI用) |

```
ALU入力MUX:
  alu_in_a = (alu_src_a == RS1)  ? fwd_rs1_data :
             (alu_src_a == PC)   ? id_ex_pc     :
                                   32'b0;

  alu_in_b = (alu_src_b == RS2)  ? fwd_rs2_data :
             (alu_src_b == IMM)  ? id_ex_imm    :
                                   32'd4;  // JAL/JALR: PC+4計算用
```

#### 乗算器/除算器 (M拡張)

| mul_div_op | 命令 | 動作 | レイテンシ |
|---|---|---|---|
| 3'b000 | MUL | rs1 × rs2 下位32ビット | 3サイクル |
| 3'b001 | MULH | signed(rs1) × signed(rs2) 上位32ビット | 3サイクル |
| 3'b010 | MULHSU | signed(rs1) × unsigned(rs2) 上位32ビット | 3サイクル |
| 3'b011 | MULHU | unsigned(rs1) × unsigned(rs2) 上位32ビット | 3サイクル |
| 3'b100 | DIV | signed(rs1) ÷ signed(rs2) 商 | 34サイクル |
| 3'b101 | DIVU | unsigned(rs1) ÷ unsigned(rs2) 商 | 34サイクル |
| 3'b110 | REM | signed(rs1) ÷ signed(rs2) 剰余 | 34サイクル |
| 3'b111 | REMU | unsigned(rs1) ÷ unsigned(rs2) 剰余 | 34サイクル |

- 乗算器: 3段パイプライン化 (DSPスライス推論)
- 除算器: 逐次除算方式 (1ビット/サイクル、34サイクル)
- 乗除算実行中はパイプラインストール (`mul_div_busy` 信号)
- 除算のエッジケース:
  - ゼロ除算: 商 = -1 (DIV) / 0xFFFFFFFF (DIVU), 剰余 = 被除数
  - オーバーフロー (DIV: -2^31 ÷ -1): 商 = -2^31, 剰余 = 0

#### 分岐条件判定・分岐先計算

| branch_op | 条件 | 判定式 |
|---|---|---|
| BEQ | 等しい | rs1 == rs2 |
| BNE | 等しくない | rs1 != rs2 |
| BLT | 小さい (符号付き) | $signed(rs1) < $signed(rs2) |
| BGE | 以上 (符号付き) | $signed(rs1) >= $signed(rs2) |
| BLTU | 小さい (符号なし) | rs1 < rs2 |
| BGEU | 以上 (符号なし) | rs1 >= rs2 |

```
分岐先アドレス:
  branch_target = id_ex_pc + id_ex_imm       // B型: PC + offset
  jal_target    = id_ex_pc + id_ex_imm       // JAL: PC + offset
  jalr_target   = (fwd_rs1_data + id_ex_imm) & ~32'b1  // JALR: (rs1 + offset) & ~1
```

#### アドレス計算 (ロード/ストア)
```
mem_addr = fwd_rs1_data + id_ex_imm    // ベースアドレス + オフセット
```

#### データフォワーディングMUX
- 詳細は [4. データフォワーディングパス](#4-データフォワーディングパス) を参照
- `fwd_rs1_data`, `fwd_rs2_data` はフォワーディング後の値

#### CSR読み出し
- CSRファイルへの読み出し要求 (csr_addr → csr_rdata)
- CSR操作結果計算:
  - CSRRW: 新値 = rs1
  - CSRRS: 新値 = csr_rdata | rs1
  - CSRRC: 新値 = csr_rdata & ~rs1
  - CSRRxI: rs1の代わりにzimm (instruction[19:15]のゼロ拡張)

#### EX段出力
- `alu_result`: ALU演算結果 / メモリアドレス / 分岐先アドレス
- `rs2_data`: ストアデータ (フォワーディング済み)
- `branch_taken`: 分岐成立フラグ
- `branch_target`: 分岐先アドレス
- `csr_wdata`: CSR書き込みデータ
- `csr_rdata`: CSR読み出しデータ
- 各制御信号 (パイプラインレジスタ経由で伝搬)

---

### 1.4 MEM (Memory Access) ステージ

#### 機能概要
データメモリへのロード/ストアアクセスをAXI4マスタインターフェース経由で実行する。

#### AXI4マスタへのメモリアクセス要求

```
AXI4アクセス制御:
  axi_arvalid = ex_mem_mem_read   // 読み出し要求
  axi_awvalid = ex_mem_mem_write  // 書き込み要求
  axi_araddr  = ex_mem_alu_result // 読み出しアドレス
  axi_awaddr  = ex_mem_alu_result // 書き込みアドレス
  axi_arsize  = ex_mem_mem_size   // アクセスサイズ
  axi_awsize  = ex_mem_mem_size   // アクセスサイズ
```

- AXI4バストランザクション完了まで (`axi_rvalid` または `axi_bvalid`) パイプラインストール
- BRAMアクセス時は1サイクル (AXI4スレーブがBRAMの場合)
- HyperRAMアクセス時は複数サイクル

#### ロード命令のデータ整形

| 命令 | mem_size | mem_unsigned | 動作 |
|---|---|---|---|
| LB | 2'b00 | 0 | バイト読み出し、符号拡張32ビット |
| LBU | 2'b00 | 1 | バイト読み出し、ゼロ拡張32ビット |
| LH | 2'b01 | 0 | ハーフワード読み出し、符号拡張32ビット |
| LHU | 2'b01 | 1 | ハーフワード読み出し、ゼロ拡張32ビット |
| LW | 2'b10 | 0 | ワード読み出し |

```
ロードデータ整形:
  byte_sel  = alu_result[1:0]
  half_sel  = alu_result[1]

  // バイトアクセス
  byte_data = axi_rdata >> (byte_sel * 8) & 8'hFF
  lb_data   = {{24{byte_data[7]}}, byte_data}
  lbu_data  = {24'b0, byte_data}

  // ハーフワードアクセス
  half_data = axi_rdata >> (half_sel * 16) & 16'hFFFF
  lh_data   = {{16{half_data[15]}}, half_data}
  lhu_data  = {16'b0, half_data}

  // ワードアクセス
  lw_data   = axi_rdata
```

#### ストア命令のデータ/ストローブ生成

| 命令 | mem_size | wstrb生成 | wdata生成 |
|---|---|---|---|
| SB | 2'b00 | `4'b0001 << byte_sel` | `rs2_data[7:0] << (byte_sel * 8)` |
| SH | 2'b01 | `4'b0011 << (half_sel * 2)` | `rs2_data[15:0] << (half_sel * 16)` |
| SW | 2'b10 | `4'b1111` | `rs2_data[31:0]` |

#### CSR書き込み
- EX段で計算されたCSR書き込みデータを実際にCSRファイルに書き込み
- CSR書き込みはMEM段で実施 (副作用のコミットポイント)

#### 例外検出

| 例外 | 検出条件 | mcause値 |
|---|---|---|
| ロードアドレスミスアライン | LH/LHU: addr[0]!=0, LW: addr[1:0]!=0 | 4 |
| ストアアドレスミスアライン | SH: addr[0]!=0, SW: addr[1:0]!=0 | 6 |
| ロードアクセスフォルト | AXI4応答エラー (RRESP!=OKAY) | 5 |
| ストアアクセスフォルト | AXI4応答エラー (BRESP!=OKAY) | 7 |

#### MEM段出力
- `mem_rdata`: メモリ読み出しデータ (整形済み)
- `alu_result`: ALU演算結果 (パススルー)
- `csr_rdata`: CSR読み出しデータ (パススルー)
- `exception`: 例外検出フラグ
- `exception_cause`: 例外要因コード

---

### 1.5 WB (Writeback) ステージ

#### 機能概要
演算結果またはメモリ読み出しデータをレジスタファイルに書き戻す。

#### 書き戻しデータ選択

| wb_sel | ソース | 対象命令 |
|---|---|---|
| 2'b00 | ALU結果 (`alu_result`) | R型, I型(算術), LUI, AUIPC |
| 2'b01 | メモリ読み出しデータ (`mem_rdata`) | LB, LBU, LH, LHU, LW |
| 2'b10 | PC + 4 (`pc_plus4`) | JAL, JALR |
| 2'b11 | CSR読み出しデータ (`csr_rdata`) | CSRRW, CSRRS, CSRRC, CSRRxI |

```
wb_data = (wb_sel == 2'b00) ? alu_result :
          (wb_sel == 2'b01) ? mem_rdata  :
          (wb_sel == 2'b10) ? pc_plus4   :
                              csr_rdata;

reg_write_en = mem_wb_reg_write && mem_wb_valid && (mem_wb_rd != 5'b0);
```

#### レジスタファイルへの書き込み
- 書き込み条件: `reg_write_en == 1` かつ `rd != x0`
- WB段の前半で書き込み、ID段の後半で読み出し (同一サイクルの場合)
- x0への書き込みは無視される

---

## 2. パイプラインレジスタ定義

### 2.1 IF/ID パイプラインレジスタ

| フィールド名 | ビット幅 | 説明 |
|---|---|---|
| `pc` | [31:0] | プログラムカウンタ |
| `instruction` | [31:0] | フェッチした命令 |
| `valid` | [0:0] | 有効フラグ (フラッシュ時0) |
| `predicted_taken` | [0:0] | 分岐予測結果 (taken=1) |
| `predicted_target` | [31:0] | 予測分岐先アドレス |
| `exception` | [0:0] | IF段での例外検出フラグ |
| `exception_cause` | [3:0] | 例外要因 (命令アクセスフォルト等) |
| **合計** | **103ビット** | |

#### 制御
- ストール条件: `hazard_stall` (ロード使用ハザード) または `mul_div_busy` または `axi_stall`
- フラッシュ条件: `branch_mispredict` または `exception_taken` または `rtos_ctx_switch`
- フラッシュ時: `valid <= 0`

### 2.2 ID/EX パイプラインレジスタ

| フィールド名 | ビット幅 | 説明 |
|---|---|---|
| `pc` | [31:0] | プログラムカウンタ |
| `rs1_data` | [31:0] | レジスタrs1読み出しデータ |
| `rs2_data` | [31:0] | レジスタrs2読み出しデータ |
| `imm` | [31:0] | 即値 (符号拡張済み) |
| `rd` | [4:0] | 宛先レジスタアドレス |
| `rs1_addr` | [4:0] | ソースレジスタ1アドレス (フォワーディング用) |
| `rs2_addr` | [4:0] | ソースレジスタ2アドレス (フォワーディング用) |
| `alu_op` | [3:0] | ALU演算種別 |
| `alu_src_a` | [1:0] | ALU入力A選択 |
| `alu_src_b` | [1:0] | ALU入力B選択 |
| `mem_read` | [0:0] | メモリ読み出し有効 |
| `mem_write` | [0:0] | メモリ書き込み有効 |
| `mem_size` | [1:0] | メモリアクセスサイズ |
| `mem_unsigned` | [0:0] | 符号なしロードフラグ |
| `reg_write` | [0:0] | レジスタ書き込み有効 |
| `wb_sel` | [1:0] | 書き戻しデータ選択 |
| `branch_op` | [2:0] | 分岐条件種別 |
| `is_branch` | [0:0] | 分岐命令フラグ |
| `is_jal` | [0:0] | JAL命令フラグ |
| `is_jalr` | [0:0] | JALR命令フラグ |
| `csr_op` | [1:0] | CSR操作種別 |
| `csr_addr` | [11:0] | CSRアドレス |
| `csr_imm` | [0:0] | CSR即値モードフラグ |
| `is_ecall` | [0:0] | ECALL検出フラグ |
| `is_ebreak` | [0:0] | EBREAK検出フラグ |
| `is_mret` | [0:0] | MRET検出フラグ |
| `is_mul_div` | [0:0] | M拡張命令フラグ |
| `mul_div_op` | [2:0] | 乗除算種別 |
| `illegal_instr` | [0:0] | 不正命令検出フラグ |
| `valid` | [0:0] | 有効フラグ |
| `predicted_taken` | [0:0] | 分岐予測結果 (パススルー) |
| `predicted_target` | [31:0] | 予測分岐先アドレス (パススルー) |
| **合計** | **約215ビット** | |

#### 制御
- ストール条件: `mul_div_busy` または `axi_stall`
- フラッシュ条件: `branch_mispredict` または `exception_taken` または `rtos_ctx_switch`
- バブル挿入: `hazard_stall` 時 (全制御信号を0にクリア、`valid <= 0`)

### 2.3 EX/MEM パイプラインレジスタ

| フィールド名 | ビット幅 | 説明 |
|---|---|---|
| `pc` | [31:0] | プログラムカウンタ |
| `alu_result` | [31:0] | ALU演算結果 / メモリアドレス |
| `rs2_data` | [31:0] | ストアデータ (フォワーディング済み) |
| `rd` | [4:0] | 宛先レジスタアドレス |
| `mem_read` | [0:0] | メモリ読み出し有効 |
| `mem_write` | [0:0] | メモリ書き込み有効 |
| `mem_size` | [1:0] | メモリアクセスサイズ |
| `mem_unsigned` | [0:0] | 符号なしロードフラグ |
| `reg_write` | [0:0] | レジスタ書き込み有効 |
| `wb_sel` | [1:0] | 書き戻しデータ選択 |
| `csr_wdata` | [31:0] | CSR書き込みデータ |
| `csr_addr` | [11:0] | CSRアドレス |
| `csr_op` | [1:0] | CSR操作種別 |
| `csr_rdata` | [31:0] | CSR読み出しデータ |
| `exception` | [0:0] | 例外検出フラグ |
| `exception_cause` | [3:0] | 例外要因コード |
| `valid` | [0:0] | 有効フラグ |
| **合計** | **約192ビット** | |

#### 制御
- ストール条件: `axi_stall` (AXI4トランザクション待ち)
- フラッシュ条件: `exception_taken` (MEM段以降の例外)

### 2.4 MEM/WB パイプラインレジスタ

| フィールド名 | ビット幅 | 説明 |
|---|---|---|
| `pc` | [31:0] | プログラムカウンタ (デバッグ用) |
| `rd` | [4:0] | 宛先レジスタアドレス |
| `wb_data` | [31:0] | 書き戻しデータ (選択済み) |
| `reg_write` | [0:0] | レジスタ書き込み有効 |
| `valid` | [0:0] | 有効フラグ |
| **合計** | **71ビット** | |

#### 制御
- この段のフラッシュは不要 (コミット済み)

---

## 3. ハザード検出ロジック

### 3.1 データハザード (RAW: Read After Write)

#### フォワーディングで解決可能なケース

```
ケース1: EX→EXフォワーディング
  条件: ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs1 or id_ex_rs2)
  解決: EX/MEMレジスタのalu_resultをEX段入力にフォワーディング
  ペナルティ: 0サイクル

ケース2: MEM→EXフォワーディング
  条件: mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs1 or id_ex_rs2)
        && !(ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs1 or id_ex_rs2))
  解決: MEM/WBレジスタのwb_dataをEX段入力にフォワーディング
  ペナルティ: 0サイクル
```

#### ロード使用ハザード (Load-Use Hazard)

```
検出条件:
  id_ex_mem_read && (id_ex_rd != 0) &&
  (id_ex_rd == if_id_rs1 || id_ex_rd == if_id_rs2)

対処:
  1. IF段: ストール (PCを保持、IF/IDレジスタを保持)
  2. ID段: ストール (ID/EXレジスタを保持)
  3. EX段: バブル挿入 (ID/EXレジスタの制御信号をNOPに)
  ペナルティ: 1サイクル

パイプライン動作:
  サイクル n  : IF  ID  EX  MEM  WB    ← LW x1, 0(x2) がEX段
  サイクル n+1: IF  ID  --  MEM  WB    ← ADD x3, x1, x4 がID段(ストール), バブル挿入
  サイクル n+2: IF  ID  EX  --   WB    ← LWのMEM→EXフォワーディングで解決
```

### 3.2 制御ハザード (分岐)

#### 分岐ペナルティ
- 分岐解決: EX段 (パイプライン2段目で分岐先確定)
- 分岐予測ミス時のペナルティ: **2サイクル** (IF段とID段の命令をフラッシュ)
- 無条件ジャンプ (JAL): ID段でターゲット計算可能だが、統一的にEX段で解決

#### パイプラインフラッシュ

```
分岐ミスプレディクション検出 (EX段):
  branch_mispredict = (is_branch && (branch_taken != predicted_taken)) ||
                      (is_branch && branch_taken && (branch_target != predicted_target)) ||
                      is_jal || is_jalr  // JAL/JALRは常にフラッシュ (予測なし時)

フラッシュ動作:
  1. IF/IDレジスタ: valid <= 0 (無効化)
  2. ID/EXレジスタ: valid <= 0 (無効化)
  3. PC: branch_target (taken時) or pc+4 (not taken時) にリダイレクト
```

### 3.3 構造ハザード

#### メモリポート競合
- **Harvard Architecture** (命令メモリとデータメモリが分離) により回避
  - 命令フェッチ: `bram_imem` (命令BRAM、64KB)
  - データアクセス: `bram_dmem` / `HyperRAM` (AXI4バス経由)
- 命令フェッチとデータアクセスが同時に発生しても競合しない

#### 乗除算器の構造ハザード
- 乗除算器は1つのみ (共有リソース)
- 乗除算実行中に後続の乗除算命令が到着: パイプラインストール
- `mul_div_busy` 信号でIF〜EX段をストール

---

## 4. データフォワーディングパス

### 4.1 フォワーディングユニット

```
フォワーディングユニット (Forwarding Unit):

入力:
  id_ex_rs1_addr  [4:0]  // EX段のrs1アドレス
  id_ex_rs2_addr  [4:0]  // EX段のrs2アドレス
  ex_mem_rd       [4:0]  // EX/MEMレジスタのrdアドレス
  ex_mem_reg_write       // EX/MEMレジスタのreg_write
  mem_wb_rd       [4:0]  // MEM/WBレジスタのrdアドレス
  mem_wb_reg_write       // MEM/WBレジスタのreg_write

出力:
  forward_a       [1:0]  // rs1のフォワーディング制御
  forward_b       [1:0]  // rs2のフォワーディング制御
```

### 4.2 EX→EXフォワーディング (EX/MEM → EX段入力)

```
条件 (forward_a):
  if (ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs1_addr))
    forward_a = 2'b10;  // EX/MEMレジスタのalu_resultを使用

条件 (forward_b):
  if (ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs2_addr))
    forward_b = 2'b10;  // EX/MEMレジスタのalu_resultを使用

データパス:
  EX/MEM.alu_result → EX段ALU入力MUX
```

### 4.3 MEM→EXフォワーディング (MEM/WB → EX段入力)

```
条件 (forward_a):
  if (mem_wb_reg_write && (mem_wb_rd != 0) &&
      !(ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs1_addr)) &&
      (mem_wb_rd == id_ex_rs1_addr))
    forward_a = 2'b01;  // MEM/WBレジスタのwb_dataを使用

条件 (forward_b):
  if (mem_wb_reg_write && (mem_wb_rd != 0) &&
      !(ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs2_addr)) &&
      (mem_wb_rd == id_ex_rs2_addr))
    forward_b = 2'b01;  // MEM/WBレジスタのwb_dataを使用

データパス:
  MEM/WB.wb_data → EX段ALU入力MUX
```

### 4.4 フォワーディングMUX制御

```
  forward_a / forward_b:
    2'b00 : レジスタファイル読み出し値 (id_ex_rs1_data / id_ex_rs2_data)
    2'b01 : MEM/WBステージのwb_data (MEM→EXフォワーディング)
    2'b10 : EX/MEMステージのalu_result (EX→EXフォワーディング)

MUX:
                         +-----+
  id_ex_rs1_data ------>|     |
  mem_wb_wb_data ------>| MUX |---> fwd_rs1_data --> ALU_in_A MUX
  ex_mem_alu_result --->|     |
                         +-----+
                            ^
                            |
                       forward_a[1:0]
```

### 4.5 フォワーディング優先度

1. **EX→EX (最高優先度)**: 最新の結果を優先
   - 例: `ADD x1, x2, x3` → `ADD x4, x1, x5` → `ADD x6, x1, x7`
   - 2番目のADDの結果がEX/MEMにある場合、3番目のADDはEX/MEMのalu_resultを使用
2. **MEM→EX**: EX→EXが適用されない場合のみ
3. **レジスタファイル (最低優先度)**: フォワーディング不要な場合

---

## 5. 分岐予測・フラッシュ制御

### 5.1 分岐予測方式

#### 静的分岐予測 (BTFN: Backward Taken, Forward Not Taken)

```
予測ロジック (IF段):
  if (is_branch_instruction) begin
    if (branch_offset < 0)    // 後方分岐 (ループ)
      predicted_taken = 1;     // taken と予測
      predicted_target = pc + branch_offset;
    else                       // 前方分岐
      predicted_taken = 0;     // not taken と予測
  end else begin
    predicted_taken = 0;
  end
```

- **後方分岐 (branch_offset < 0)**: ループのバックエッジとして taken 予測
- **前方分岐 (branch_offset >= 0)**: not taken 予測 (通常のフォールスルー)
- JAL: 常に taken (無条件ジャンプ、ID段で判定可能)
- JALR: 予測なし (常にミス、2サイクルペナルティ)

> 注: 初期実装は静的予測。パフォーマンス要件に応じて動的予測 (BHT/BTB) に拡張可能。

#### 分岐命令のIF段での早期検出

```
// IF段で命令の下位ビットから分岐命令を早期識別
is_branch_instruction = (instruction[6:0] == 7'b1100011);  // B型
branch_offset_sign    = instruction[31];  // B型即値の符号ビット

// 簡易分岐先計算 (IF段)
branch_predict_target = pc + {{20{instruction[31]}}, instruction[7],
                              instruction[30:25], instruction[11:8], 1'b0};
```

### 5.2 分岐解決タイミング

- 分岐条件判定: **EX段** (ALUでの比較結果)
- 分岐先アドレス計算: **EX段**
- 分岐解決のレイテンシ: PCから2サイクル後

```
タイミング:
  サイクル 1: IF  ← 分岐命令フェッチ + 予測
  サイクル 2: ID  ← デコード
  サイクル 3: EX  ← 分岐条件判定 (ここで予測の正否が確定)
```

### 5.3 ミスプレディクション時のパイプラインフラッシュ

```
ミスプレディクション検出 (EX段):
  // 分岐命令の場合
  branch_mispredict = id_ex_valid && (
    (id_ex_is_branch && (branch_taken != id_ex_predicted_taken)) ||
    (id_ex_is_branch && branch_taken && (branch_target != id_ex_predicted_target))
  );

  // JAL/JALRは初期実装では常にnot-taken予測のためフラッシュ
  jal_flush  = id_ex_valid && id_ex_is_jal;
  jalr_flush = id_ex_valid && id_ex_is_jalr;

  flush = branch_mispredict || jal_flush || jalr_flush;

フラッシュ動作:
  1. IF/ID.valid <= 0   // IF段の命令を無効化
  2. ID/EX.valid <= 0   // ID段の命令を無効化
  3. next_pc <= correct_target  // 正しいPCにリダイレクト

correct_target:
  - branch taken:     branch_target (pc + offset)
  - branch not taken: id_ex_pc + 4
  - JAL:              jal_target
  - JALR:             jalr_target
```

### 5.4 パイプラインフラッシュ回路

```
           +--------+    +--------+    +--------+    +--------+    +--------+
           |   IF   |--->|   ID   |--->|   EX   |--->|  MEM   |--->|   WB   |
           +--------+    +--------+    +--------+    +--------+    +--------+
                |              |              |
               flush_if      flush_id     (判定元)
                ^              ^              |
                |              |              |
                +--------------+----- flush --+

flush_if:  IF/IDレジスタのvalidを0にクリア
flush_id:  ID/EXレジスタのvalidを0にクリア (または全制御信号を0にクリア)
```

---

## 6. 例外/割り込みのパイプライン挿入ポイント

### 6.1 同期例外

| 例外 | 検出段 | mcause | 説明 |
|---|---|---|---|
| 命令アドレスミスアライン | IF | 0 | PC[1:0] != 0 (RV32では通常発生しない) |
| 命令アクセスフォルト | IF | 1 | 命令メモリ範囲外アクセス |
| 不正命令 | ID | 2 | デコード不可能な命令 |
| EBREAK | ID | 3 | ブレークポイント例外 |
| ロードアドレスミスアライン | EX | 4 | LH/LW のアドレスアライメント違反 |
| ロードアクセスフォルト | MEM | 5 | データ読み出しエラー |
| ストアアドレスミスアライン | EX | 6 | SH/SW のアドレスアライメント違反 |
| ストアアクセスフォルト | MEM | 7 | データ書き込みエラー |
| ECALL (M-mode) | ID | 11 | システムコール |

### 6.2 非同期割り込み

| 割り込み | ソース | mip/mieビット | mcause |
|---|---|---|---|
| ソフトウェア割り込み (MSI) | CLINT | mip.MSIP / mie.MSIE | 0x80000003 |
| タイマ割り込み (MTI) | CLINT | mip.MTIP / mie.MTIE | 0x80000007 |
| 外部割り込み (MEI) | PLIC | mip.MEIP / mie.MEIE | 0x8000000B |

#### 割り込み受付条件
```
interrupt_pending = mstatus.MIE && (
  (mip.MSIP && mie.MSIE) ||  // ソフトウェア割り込み
  (mip.MTIP && mie.MTIE) ||  // タイマ割り込み
  (mip.MEIP && mie.MEIE)     // 外部割り込み
);
```

#### 割り込み優先度 (RISC-V特権仕様準拠)
1. MEI (外部割り込み) - 最高
2. MSI (ソフトウェア割り込み)
3. MTI (タイマ割り込み) - 最低

### 6.3 例外/割り込み発生時のパイプライン処理

#### 例外処理シーケンス

```
例外/割り込み処理フロー:

1. 例外/割り込みの検出
   - 同期例外: 各段で検出、パイプラインに沿って伝搬
   - 非同期割り込み: WB段コミット時に受付判定

2. パイプラインフラッシュ
   - 例外発生命令より後の全命令をフラッシュ
   - 例外発生命令自体はコミットしない (副作用なし)

3. CSR更新 (1サイクル)
   - mepc  <= 例外発生命令のPC (同期例外)
              または次に実行すべき命令のPC (非同期割り込み)
   - mcause <= 例外/割り込み要因コード
   - mtval  <= 追加情報 (不正命令の命令コード、ミスアラインアドレス等)
   - mstatus.MPIE <= mstatus.MIE  // 割り込み有効状態を退避
   - mstatus.MIE  <= 0            // 割り込み禁止

4. PCリダイレクト
   - mtvec.MODE == 0 (Direct):   PC <= mtvec.BASE
   - mtvec.MODE == 1 (Vectored): PC <= mtvec.BASE + (mcause * 4)
     ※ Vectoredモードは割り込みのみ適用、例外はBASEに遷移
```

#### 進行中命令のコミット/フラッシュ制御

```
例外発生時のパイプライン状態管理:

同期例外 (ID段で検出: 不正命令, ECALL, EBREAK):
  IF/ID: フラッシュ (valid <= 0)
  ID/EX: フラッシュ (バブル挿入)
  EX/MEM〜WB: 先行命令は正常コミット

同期例外 (EX段で検出: アドレスミスアライン):
  IF/ID: フラッシュ
  ID/EX: フラッシュ
  EX/MEM: 例外命令をフラッシュ (valid <= 0)
  MEM/WB: 先行命令は正常コミット

同期例外 (MEM段で検出: アクセスフォルト):
  IF/ID〜EX/MEM: 全フラッシュ
  MEM/WB: 例外命令をフラッシュ

非同期割り込み:
  - WB段でコミットする命令まで正常完了させる
  - 次のIF段から割り込みハンドラにリダイレクト
  - IF/ID〜ID/EX: フラッシュ
  - mepc <= WB段完了命令のPC + 4 (次に実行すべき命令)
```

#### 精密例外 (Precise Exception) の保証
- 例外発生命令より前の全命令は正常コミット
- 例外発生命令および後続命令は全てフラッシュ (副作用なし)
- mepcには例外発生命令のPCが正確に記録される

### 6.4 CSR更新詳細

#### mepc (Machine Exception Program Counter)
```
同期例外: mepc <= 例外発生命令のPC
非同期割り込み: mepc <= 次に実行すべき命令のPC
  (WB段で最後にコミットした命令のPC + 4、またはIF段のPC)
```

#### mcause (Machine Cause Register)
```
mcause[31]   = interrupt (1: 割り込み, 0: 例外)
mcause[30:0] = exception_code
```

#### mtval (Machine Trap Value)
```
不正命令例外: mtval <= 命令コード (instruction)
アドレスミスアライン: mtval <= ミスアラインアドレス
アクセスフォルト: mtval <= フォルトアドレス
その他: mtval <= 0
```

### 6.5 mtvec (Machine Trap-Vector Base Address)

```
mtvec構成:
  mtvec[31:2] = BASE (ベクタテーブルベースアドレス、4バイト境界)
  mtvec[1:0]  = MODE

MODE = 0 (Direct):
  全ての例外/割り込み → BASE にジャンプ
  ソフトウェアがmcauseを読んでディスパッチ

MODE = 1 (Vectored):
  例外     → BASE にジャンプ
  割り込み → BASE + (cause * 4) にジャンプ
  各割り込み要因ごとに異なるハンドラエントリ
```

### 6.6 MRET命令による復帰

```
MRET命令実行時の動作 (ID段で検出):
  1. パイプラインフラッシュ (IF/ID, ID/EXを無効化)
  2. CSR復帰:
     - mstatus.MIE  <= mstatus.MPIE  // 割り込み有効状態を復帰
     - mstatus.MPIE <= 1
  3. PCリダイレクト:
     - next_pc <= mepc  // 退避していたPCに復帰
```

### 6.7 例外/割り込みとRTOSの連携

```
割り込み/例外処理とRTOSの関係:

1. タイマ割り込み (CLINT → mip.MTIP):
   → 割り込みハンドラ → RTOSタイムスライス更新
   → プリエンプション判定 → 必要に応じてコンテキストスイッチ

2. ECALL (POSIXシステムコール):
   → 例外ハンドラ → posix_hw_layerへディスパッチ
   → ハードウェアオペレーション実行
   → 結果をa0に設定 → mepc+4に復帰

3. RTOSコンテキストスイッチ:
   → rtos_ctx_switch_req信号アサート
   → パイプライン完全フラッシュ
   → レジスタ退避/復帰 (RTOSハードウェアが実行)
   → 復帰PC設定 → パイプライン再開
```

---

## 付録A: パイプライン制御信号サマリ

| 信号名 | 方向 | 説明 |
|---|---|---|
| `stall_if` | Hazard Unit → IF | IF段ストール |
| `stall_id` | Hazard Unit → ID | ID段ストール |
| `stall_ex` | Hazard Unit → EX | EX段ストール (乗除算/AXI待ち) |
| `stall_mem` | Hazard Unit → MEM | MEM段ストール (AXI待ち) |
| `flush_if_id` | Control → IF/ID reg | IF/IDレジスタフラッシュ |
| `flush_id_ex` | Control → ID/EX reg | ID/EXレジスタフラッシュ |
| `flush_ex_mem` | Control → EX/MEM reg | EX/MEMレジスタフラッシュ |
| `bubble_id_ex` | Hazard Unit → ID/EX reg | ID/EXにNOPバブル挿入 |
| `branch_mispredict` | EX段 → Control | 分岐予測ミス |
| `exception_taken` | Exception Unit → Control | 例外受付 |
| `interrupt_taken` | Interrupt Unit → Control | 割り込み受付 |
| `mul_div_busy` | EX段 → Hazard Unit | 乗除算器ビジー |
| `axi_stall` | AXI Master → Hazard Unit | AXI4トランザクション待ち |
| `rtos_ctx_switch_req` | hw_rtos → Control | コンテキストスイッチ要求 |
| `rtos_ctx_switch_ack` | Control → hw_rtos | コンテキストスイッチ確認 |

## 付録B: パイプラインタイミング例

### 通常実行 (ハザードなし)
```
命令:        サイクル1  サイクル2  サイクル3  サイクル4  サイクル5  サイクル6  サイクル7
INST 1:        IF        ID        EX        MEM       WB
INST 2:                  IF        ID        EX        MEM       WB
INST 3:                            IF        ID        EX        MEM       WB
```

### ロード使用ハザード (1サイクルストール)
```
命令:        サイクル1  サイクル2  サイクル3  サイクル4  サイクル5  サイクル6  サイクル7
LW x1,0(x2):  IF        ID        EX        MEM       WB
ADD x3,x1,x4:           IF        ID        stall     EX        MEM       WB
INST 3:                            IF        stall     ID        EX        MEM ...
```

### 分岐ミスプレディクション (2サイクルペナルティ)
```
命令:        サイクル1  サイクル2  サイクル3  サイクル4  サイクル5  サイクル6
BEQ (taken):   IF        ID        EX        MEM       WB
INST A:                  IF        ID(flush)  -         -
INST B:                            IF(flush)  -         -
Branch target:                                IF        ID        EX ...
```

### 例外処理 (ECALL)
```
命令:        サイクル1  サイクル2  サイクル3  サイクル4  サイクル5  サイクル6
ECALL:         IF        ID        flush     -         -
INST after:              IF        flush     -         -
Handler:                           -         IF        ID        EX ...
(mepc, mcause, mstatus更新はサイクル3で実施)
```
