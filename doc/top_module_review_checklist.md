# Top Module Review Checklist - 4 Top Modules

## Document Information
| Item | Detail |
|------|--------|
| Task ID | VSYNC-QA-PREP-001 |
| Date | 2026-02-21 |
| Reviewer | Lead QA |
| Reference | doc/module_io_spec.md, rtl/core/vsync_pkg.sv |

---

## ⚠ CRITICAL: FINDING-001 - アドレスマップ不一致

**doc/address_map.md (Rev 1.0)** と **vsync_pkg.sv + module_io_spec.md (v1.1)** で
アドレスマップが全面不一致。IMEM以外の全リージョンが不一致。

**正 (レビュー基準)**: `vsync_pkg.sv` / `module_io_spec.md` (v1.1)
**旧 (参照注意)**: `doc/address_map.md` (Rev 1.0) - ペリフェラルレジスタ詳細のみ有効

| Region | 正 (pkg) | 旧 (address_map) |
|--------|----------|------------------|
| DMEM | 0x0001_0000 | 0x1000_0000 |
| CLINT | 0x0200_0000 | 0x4003_0000 |
| PLIC | 0x0C00_0000 | 0x4002_0000 |
| UART | 0x1000_0000 | 0x4000_0000 |
| GPIO | 0x1000_0100 | 0x4001_0000 |
| RTOS | 0x1100_0000 | 0x8000_0000 |
| POSIX | 0x1200_0000 | 0x9000_0000 |

→ Director にエスカレーション済。レビュー時は vsync_pkg.sv の値を基準とすること。

---

## 1. rv32im_core (rtl/core/rv32im_core.sv) - CPUコアトップ

### 1.1 ポート定義チェック

| # | チェック項目 | spec参照 | 状態 |
|---|-------------|---------|------|
| C1-01 | `clk` / `rst_n` 存在・方向(input) | §1.1 | [ ] |
| C1-02 | `imem_addr` output [IMEM_ADDR_W-1:0] = [15:0] | §1.1 | [ ] |
| C1-03 | `imem_rdata` input [XLEN-1:0] = [31:0] | §1.1 | [ ] |
| C1-04 | `imem_en` output 1bit | §1.1 | [ ] |
| C1-05 | `mem_addr` output [XLEN-1:0] = [31:0] | §1.1 | [ ] |
| C1-06 | `mem_wdata` output [XLEN-1:0] | §1.1 | [ ] |
| C1-07 | `mem_read` / `mem_write` output 1bit each | §1.1 | [ ] |
| C1-08 | `mem_size` output [2:0] | §1.1 | [ ] |
| C1-09 | `mem_rdata` input [XLEN-1:0] | §1.1 | [ ] |
| C1-10 | `mem_ready` / `mem_error` input 1bit each | §1.1 | [ ] |
| C1-11 | `external_irq` / `timer_irq` / `software_irq` input 1bit each | §1.1 | [ ] |
| C1-12 | `ctx_switch_req` input, `ctx_switch_ack` output | §1.1 | [ ] |
| C1-13 | `ctx_save_en` output, `ctx_save_reg_idx` output [REG_ADDR_W-1:0] | §1.1 | [ ] |
| C1-14 | `ctx_save_reg_data` output [XLEN-1:0] | §1.1 | [ ] |
| C1-15 | `ctx_save_pc` output [XLEN-1:0] | §1.1 | [ ] |
| C1-16 | `ctx_restore_en` input, `ctx_restore_reg_idx` input [REG_ADDR_W-1:0] | §1.1 | [ ] |
| C1-17 | `ctx_restore_reg_data` input [XLEN-1:0] | §1.1 | [ ] |
| C1-18 | `ctx_restore_pc` input [XLEN-1:0] | §1.1 | [ ] |
| C1-19 | `current_task_id` input [TASK_ID_W-1:0], `task_active` input | §1.1 | [ ] |
| C1-20 | `ecall_req` output, `syscall_num` output [7:0] | §1.1 | [ ] |
| C1-21 | `syscall_arg0/1/2` output [XLEN-1:0] each | §1.1 | [ ] |
| C1-22 | `syscall_ret` input [XLEN-1:0], `syscall_done` input | §1.1 | [ ] |
| C1-23 | Debug interface: `debug_halt_req` in, `debug_halted` out, `debug_pc` out [XLEN-1:0] | §1.1 | [ ] |
| C1-24 | Debug interface: `debug_instr` out [XLEN-1:0], `debug_reg_addr` in [REG_ADDR_W-1:0], `debug_reg_data` out [XLEN-1:0] | §1.1 | [ ] |

### 1.2 サブモジュールインスタンス化チェック

| # | チェック項目 | 状態 |
|---|-------------|------|
| C1-30 | fetch_stage インスタンス存在 & ポート接続正しい | [ ] |
| C1-31 | decode_stage インスタンス存在 & ポート接続正しい | [ ] |
| C1-32 | execute_stage インスタンス存在 & ポート接続正しい | [ ] |
| C1-33 | memory_stage インスタンス存在 & ポート接続正しい | [ ] |
| C1-34 | writeback_stage インスタンス存在 & ポート接続正しい | [ ] |
| C1-35 | register_file インスタンス存在 & ポート接続正しい | [ ] |
| C1-36 | alu インスタンス存在 & ポート接続正しい | [ ] |
| C1-37 | multiplier_divider (M拡張) インスタンス存在 & ポート接続正しい | [ ] |
| C1-38 | csr_unit インスタンス存在 & ポート接続正しい | [ ] |
| C1-39 | hazard_unit インスタンス存在 & ポート接続正しい | [ ] |
| C1-40 | branch_unit インスタンス存在 & ポート接続正しい | [ ] |
| C1-41 | immediate_gen インスタンス存在 & ポート接続正しい | [ ] |
| C1-42 | exception_unit インスタンス存在 & ポート接続正しい | [ ] |

### 1.3 パイプラインレジスタチェック

| # | チェック項目 | 状態 |
|---|-------------|------|
| C1-50 | IF/IDレジスタ型 (if_id_reg_t) 使用 | [ ] |
| C1-51 | ID/EXレジスタ型 (id_ex_reg_t) 使用 | [ ] |
| C1-52 | EX/MEMレジスタ型 (ex_mem_reg_t) 使用 | [ ] |
| C1-53 | MEM/WBレジスタ型 (mem_wb_reg_t) 使用 | [ ] |
| C1-54 | パイプラインフラッシュ信号がhazard_ctrl_tと整合 | [ ] |
| C1-55 | フォワーディングMux制御がhazard_ctrl_t.forward_a/b と整合 | [ ] |

### 1.4 インターフェース整合性チェック

| # | チェック項目 | 状態 |
|---|-------------|------|
| C1-60 | imem信号がbram_imemのダイレクトI/Fと整合 | [ ] |
| C1-61 | mem_* 信号がaxi4_masterのcpu_* 信号と整合 | [ ] |
| C1-62 | ctx_* 信号がhw_rtosのctx_* 信号と方向反転整合 | [ ] |
| C1-63 | ecall/syscall_* 信号がposix_hw_layerと方向反転整合 | [ ] |
| C1-64 | 割り込み入力がPLIC/CLINT出力と整合 | [ ] |

---

## 2. hw_rtos (rtl/rtos/hw_rtos.sv) - RTOSトップ

### 2.1 ポート定義チェック

| # | チェック項目 | spec参照 | 状態 |
|---|-------------|---------|------|
| C2-01 | `clk` / `rst_n` 存在・方向(input) | §2.1 | [ ] |
| C2-02 | `scheduler_en` input, `schedule_policy` input [1:0] | §2.1 | [ ] |
| C2-03 | `current_task_id` output [TASK_ID_W-1:0], `next_task_id` output [TASK_ID_W-1:0] | §2.1 | [ ] |
| C2-04 | `task_active` output | §2.1 | [ ] |
| C2-05 | `ctx_switch_req` output, `ctx_switch_ack` input | §2.1 | [ ] |
| C2-06 | `ctx_save_en/reg_idx/reg_data/pc` input from CPU | §2.1 | [ ] |
| C2-07 | `ctx_restore_en/reg_idx/reg_data/pc` output to CPU | §2.1 | [ ] |
| C2-08 | `timer_tick` input from CLINT | §2.1 | [ ] |
| C2-09 | `rtos_task_create` input, `rtos_task_create_pc/sp` input [XLEN-1:0] | §2.1 | [ ] |
| C2-10 | `rtos_task_create_prio` input [TASK_PRIORITY_W-1:0] | §2.1 | [ ] |
| C2-11 | `rtos_task_create_done` output, `rtos_task_create_id` output [TASK_ID_W-1:0] | §2.1 | [ ] |
| C2-12 | `rtos_task_exit` / `rtos_task_yield` input | §2.1 | [ ] |
| C2-13 | `rtos_sem_op` input [1:0], `rtos_sem_id` input [2:0], `rtos_sem_value` input [7:0] | §2.1 | [ ] |
| C2-14 | `rtos_sem_done` / `rtos_sem_result` output | §2.1 | [ ] |
| C2-15 | `rtos_mutex_op` input [1:0], `rtos_mutex_id` input [2:0] | §2.1 | [ ] |
| C2-16 | `rtos_mutex_done` / `rtos_mutex_result` output | §2.1 | [ ] |
| C2-17 | `rtos_msgq_op` input [1:0], `rtos_msgq_id` input [1:0], `rtos_msgq_data` input [XLEN-1:0] | §2.1 | [ ] |
| C2-18 | `rtos_msgq_done/result/success` output | §2.1 | [ ] |
| C2-19 | AXI4 Slave (AXI4-Lite) 全18信号完備 (AW/W/B/AR/R) | §2.1 | [ ] |

### 2.2 サブモジュールインスタンス化チェック

| # | チェック項目 | 状態 |
|---|-------------|------|
| C2-30 | task_scheduler インスタンス存在 & ポート接続正しい | [ ] |
| C2-31 | tcb_array インスタンス存在 & ポート接続正しい | [ ] |
| C2-32 | context_switch インスタンス存在 & ポート接続正しい | [ ] |
| C2-33 | hw_semaphore インスタンス存在 & ポート接続正しい | [ ] |
| C2-34 | hw_mutex インスタンス存在 & ポート接続正しい | [ ] |
| C2-35 | hw_msgqueue インスタンス存在 & ポート接続正しい | [ ] |
| C2-36 | pmp_unit インスタンス存在 & ポート接続正しい | [ ] |

### 2.3 インターフェース整合性チェック

| # | チェック項目 | 状態 |
|---|-------------|------|
| C2-40 | ctx_* 信号がrv32im_coreと方向反転整合 | [ ] |
| C2-41 | rtos_* 信号がposix_hw_layerの出力と方向一致 | [ ] |
| C2-42 | timer_tick がCLINTのtick出力と接続 | [ ] |
| C2-43 | AXI4 SlaveがAXI4 interconnectのスレーブポートと接続 | [ ] |
| C2-44 | task_active/current_task_idがrv32im_coreに正しく出力 | [ ] |

### 2.4 追加注意事項 (tester_2 発見)

| # | チェック項目 | 状態 |
|---|-------------|------|
| C2-50 | context_switch: cpu_reg_*/cpu_pc (内部名) → ctx_save_*/ctx_restore_* (外部名) 変換レイヤー正しく実装 | [ ] |
| C2-51 | hw_semaphore: task_priorities入力がtcb_array.all_prioと接続 | [ ] |
| C2-52 | hw_mutex: prio_boost_*がtcb_arrayへの優先度継承書き戻しパスと接続 | [ ] |
| C2-53 | AXI4-Lite: awprot/arprotの有無がspec定義(18信号)と一致 | [ ] |

---

## 3. posix_hw_layer (rtl/posix/posix_hw_layer.sv) - POSIXハードウェア層

### 3.1 ポート定義チェック

| # | チェック項目 | spec参照 | 状態 |
|---|-------------|---------|------|
| C3-01 | `clk` / `rst_n` 存在・方向(input) | §3.1 | [ ] |
| C3-02 | `ecall_req` input, `syscall_num` input [7:0] | §3.1 | [ ] |
| C3-03 | `syscall_arg0/1/2` input [XLEN-1:0] each | §3.1 | [ ] |
| C3-04 | `syscall_ret` output [XLEN-1:0], `syscall_done` output | §3.1 | [ ] |
| C3-05 | `rtos_task_create` output, `rtos_task_create_pc/sp` output [XLEN-1:0] | §3.1 | [ ] |
| C3-06 | `rtos_task_create_prio` output [TASK_PRIORITY_W-1:0] | §3.1 | [ ] |
| C3-07 | `rtos_task_create_done` input, `rtos_task_create_id` input [TASK_ID_W-1:0] | §3.1 | [ ] |
| C3-08 | `rtos_task_exit` / `rtos_task_yield` output | §3.1 | [ ] |
| C3-09 | `rtos_sem_op` output [1:0], `rtos_sem_id` output [2:0], `rtos_sem_value` output [7:0] | §3.1 | [ ] |
| C3-10 | `rtos_sem_done/result` input | §3.1 | [ ] |
| C3-11 | `rtos_mutex_op` output [1:0], `rtos_mutex_id` output [2:0] | §3.1 | [ ] |
| C3-12 | `rtos_mutex_done/result` input | §3.1 | [ ] |
| C3-13 | `rtos_msgq_op` output [1:0], `rtos_msgq_id` output [1:0], `rtos_msgq_data` output [XLEN-1:0] | §3.1 | [ ] |
| C3-14 | `rtos_msgq_done/result/success` input | §3.1 | [ ] |
| C3-15 | `periph_addr/wdata` output [XLEN-1:0], `periph_read/write` output | §3.1 | [ ] |
| C3-16 | `periph_rdata` input [XLEN-1:0], `periph_ready` input | §3.1 | [ ] |
| C3-17 | AXI4 Slave (AXI4-Lite) 全18信号完備 (AW/W/B/AR/R) | §3.1 | [ ] |

### 3.2 Syscall Dispatch Logic チェック

| # | チェック項目 | 状態 |
|---|-------------|------|
| C3-30 | syscall_num_t enum値とsyscall_numの分岐が整合 | [ ] |
| C3-31 | Thread Management (0x00-0x0F) → rtos_task_create/exit/yield正しくマッピング | [ ] |
| C3-32 | Mutex (0x10-0x1F) → rtos_mutex_op正しくマッピング | [ ] |
| C3-33 | Semaphore (0x20-0x2F) → rtos_sem_op正しくマッピング | [ ] |
| C3-34 | MsgQ (0x30-0x3F) → rtos_msgq_op正しくマッピング | [ ] |
| C3-35 | Timer/Clock (0x40-0x4F) 適切に処理 | [ ] |
| C3-36 | File I/O (0x50-0x5F) → periph_* 経由で処理 | [ ] |
| C3-37 | Signal (0x60-0x6F) 適切に処理 | [ ] |
| C3-38 | System (0x70-0x7F) 適切に処理 | [ ] |
| C3-39 | 未定義syscall番号 → POSIX_ENOSYS返却 | [ ] |

### 3.3 インターフェース整合性チェック

| # | チェック項目 | 状態 |
|---|-------------|------|
| C3-50 | ecall/syscall_* がrv32im_coreと方向反転整合 | [ ] |
| C3-51 | rtos_* がhw_rtosのinputと方向反転整合 | [ ] |
| C3-52 | periph_* がAPBブリッジ経由でペリフェラルに接続可能 | [ ] |
| C3-53 | FDテーブル(fd_entry_t)がvsync_pkg定義と一致 | [ ] |
| C3-54 | AXI4 SlaveがAXI4 interconnectのスレーブポートと接続 | [ ] |

---

## 4. vsync_top (rtl/top/vsync_top.sv) - システムトップ

### 4.1 ポート定義チェック

| # | チェック項目 | spec参照 | 状態 |
|---|-------------|---------|------|
| C4-01 | `clk` / `rst_n` 存在・方向(input) | §14.1 | [ ] |
| C4-02 | パラメータ `IMEM_INIT_FILE`, `GPIO_WIDTH` | §14.2 | [ ] |
| C4-03 | `uart_tx` output, `uart_rx` input | §14.1 | [ ] |
| C4-04 | `gpio_io` inout [GPIO_WIDTH-1:0] | §14.1 | [ ] |
| C4-05 | `hyper_cs_n/ck/ck_n/rst_n` output | §14.1 | [ ] |
| C4-06 | `hyper_rwds` inout, `hyper_dq` inout [7:0] | §14.1 | [ ] |
| C4-07 | JTAG: `jtag_tck/tms/tdi/trst_n` input, `jtag_tdo` output | §14.1 | [ ] |

### 4.2 全モジュールインスタンス化チェック (13モジュール)

| # | インスタンス名 | モジュール | 状態 |
|---|--------------|----------|------|
| C4-10 | u_cpu | rv32im_core | [ ] |
| C4-11 | u_rtos | hw_rtos | [ ] |
| C4-12 | u_posix | posix_hw_layer | [ ] |
| C4-13 | u_axi_master | axi4_master | [ ] |
| C4-14 | u_axi_xbar | axi4_interconnect | [ ] |
| C4-15 | u_apb_bridge | axi4_apb_bridge | [ ] |
| C4-16 | u_imem | bram_imem | [ ] |
| C4-17 | u_dmem | bram_dmem | [ ] |
| C4-18 | u_hyperram | hyperram_ctrl | [ ] |
| C4-19 | u_uart | uart_apb | [ ] |
| C4-20 | u_gpio | gpio_apb | [ ] |
| C4-21 | u_plic | plic | [ ] |
| C4-22 | u_clint | clint | [ ] |

### 4.3 内部配線整合性チェック (クリティカル接続)

| # | チェック項目 | 状態 |
|---|-------------|------|
| C4-30 | リセット同期回路 (2段FF非同期アサート/同期デアサート) 実装 | [ ] |
| C4-31 | sys_rst_nが全サブモジュールのrst_nに接続 | [ ] |
| C4-32 | rv32im_core.imem_* ↔ bram_imem 直結 | [ ] |
| C4-33 | rv32im_core.mem_* ↔ axi4_master.cpu_* 接続 | [ ] |
| C4-34 | axi4_master.m_axi_* ↔ axi4_interconnect スレーブポート接続 | [ ] |
| C4-35 | axi4_interconnect マスターポート → bram_dmem, hyperram_ctrl, hw_rtos, posix_hw_layer, axi4_apb_bridge | [ ] |
| C4-36 | axi4_apb_bridge → uart_apb, gpio_apb, plic, clint (APBバス) | [ ] |
| C4-37 | rv32im_core.ctx_* ↔ hw_rtos.ctx_* 方向正しく接続 | [ ] |
| C4-38 | rv32im_core.ecall/syscall_* ↔ posix_hw_layer 方向正しく接続 | [ ] |
| C4-39 | posix_hw_layer.rtos_* ↔ hw_rtos.rtos_* 方向正しく接続 | [ ] |
| C4-40 | plic.external_irq → rv32im_core.external_irq | [ ] |
| C4-41 | clint.timer_irq → rv32im_core.timer_irq | [ ] |
| C4-42 | clint.software_irq → rv32im_core.software_irq | [ ] |
| C4-43 | clint.timer_tick → hw_rtos.timer_tick | [ ] |
| C4-44 | uart_apb.irq → plic_irq_sources[1] (ビットマッピング) | [ ] |
| C4-45 | gpio_apb.irq → plic_irq_sources[2] (ビットマッピング) | [ ] |
| C4-46 | GPIO tri-state: gpio_io ↔ gpio_i/gpio_o/gpio_oe 正しくバッファ実装 | [ ] |
| C4-47 | HyperRAM inout信号が正しくhyperram_ctrlと接続 | [ ] |

### 4.4 アドレスマップ整合性チェック

| # | チェック項目 | 期待値 | 状態 |
|---|-------------|-------|------|
| C4-50 | IMEM base/end | 0x0000_0000 / 0x0000_FFFF | [ ] |
| C4-51 | DMEM base/end | 0x0001_0000 / 0x0001_3FFF | [ ] |
| C4-52 | CLINT base/end | 0x0200_0000 / 0x0200_FFFF | [ ] |
| C4-53 | PLIC base/end | 0x0C00_0000 / 0x0C00_0FFF | [ ] |
| C4-54 | UART base/end | 0x1000_0000 / 0x1000_00FF | [ ] |
| C4-55 | GPIO base/end | 0x1000_0100 / 0x1000_01FF | [ ] |
| C4-56 | HW_RTOS base/end | 0x1100_0000 / 0x1100_FFFF | [ ] |
| C4-57 | POSIX base/end | 0x1200_0000 / 0x1200_FFFF | [ ] |
| C4-58 | HyperRAM base/end | 0x2000_0000 / 0x2FFF_FFFF | [ ] |
| C4-59 | axi4_interconnect のデコーダがアドレスマップと一致 | | [ ] |

---

## 5. vsync_pkg.sv POSIX定義 追加確認

| # | チェック項目 | 状態 |
|---|-------------|------|
| P-01 | ADDR_POSIX_BASE = 32'h1200_0000 定義存在 | [x] CONFIRMED |
| P-02 | ADDR_POSIX_END = 32'h1200_FFFF 定義存在 | [x] CONFIRMED |
| P-03 | syscall_num_t enum: Thread (0x00-0x07) 8種 | [x] CONFIRMED |
| P-04 | syscall_num_t enum: Mutex (0x10-0x14) 5種 | [x] CONFIRMED |
| P-05 | syscall_num_t enum: Semaphore (0x20-0x26) 7種 | [x] CONFIRMED |
| P-06 | syscall_num_t enum: MsgQ (0x30-0x35) 6種 | [x] CONFIRMED |
| P-07 | syscall_num_t enum: Timer (0x40-0x46) 7種 | [x] CONFIRMED |
| P-08 | syscall_num_t enum: File I/O (0x50-0x55) 6種 | [x] CONFIRMED |
| P-09 | syscall_num_t enum: Signal (0x60-0x64) 5種 | [x] CONFIRMED |
| P-10 | syscall_num_t enum: System (0x70-0x73) 4種 | [x] CONFIRMED |
| P-11 | SYSCALL_*_BASE カテゴリ範囲定数存在 (8種) | [x] CONFIRMED |
| P-12 | POSIX_E* エラーコード定義 (7種) | [x] CONFIRMED |
| P-13 | fd_type_t / fd_entry_t 構造体定義 | [x] CONFIRMED |
| P-14 | MAX_FD = 16, FD_WIDTH = 4 パラメータ定義 | [x] CONFIRMED |

---

## 6. 共通チェック (全モジュール共通)

| # | チェック項目 | 状態 |
|---|-------------|------|
| G-01 | `import vsync_pkg::*;` が全モジュールに存在 | [ ] |
| G-02 | パラメータ参照名がvsync_pkg定義と完全一致 | [ ] |
| G-03 | 型名参照がvsync_pkg定義と完全一致 | [ ] |
| G-04 | 未接続ポート (floating wire) なし | [ ] |
| G-05 | 幅ミスマッチ (width mismatch) なし | [ ] |
| G-06 | 方向ミスマッチ (direction mismatch) なし | [ ] |
| G-07 | sensitivity list適切 (always_ff @posedge clk) | [ ] |
| G-08 | コーディング規約準拠 (命名規則、インデント等) | [ ] |
| G-09 | コンパイルエラーなし (Icarus Verilog / Verilator lint) | [ ] |
| G-10 | Verilator -Wall でwarningゼロ | [ ] |
