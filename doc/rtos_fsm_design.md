# ハードウェアRTOS状態遷移設計

| 項目 | 内容 |
|---|---|
| ドキュメントID | TASK-LD005 |
| バージョン | 1.0 |
| 作成日 | 2026-02-21 |
| 対象モジュール | hw_rtos |
| 最大タスク数 | 256 (パラメータ化: MAX_TASKS) |
| スケジューリング | 優先度ベース + ラウンドロビン (同優先度) |
| 優先度レベル | 16段階 (0=最高, 15=最低) |

---

## 目次

1. [タスクスケジューラFSM状態遷移](#1-タスクスケジューラfsm状態遷移)
2. [タスク状態管理 (5状態)](#2-タスク状態管理-5状態)
3. [コンテキストスイッチシーケンス](#3-コンテキストスイッチシーケンス)
4. [TCBレジスタ構成](#4-tcbレジスタ構成)
5. [セマフォ/ミューテックス取得・解放FSM](#5-セマフォミューテックス取得解放fsm)
6. [メッセージキュー送信・受信FSM](#6-メッセージキュー送信受信fsm)
7. [PMP設定管理](#7-pmp設定管理)

---

## 1. タスクスケジューラFSM状態遷移

### 1.1 FSM状態定義

| 状態名 | エンコード | 説明 |
|---|---|---|
| `S_IDLE` | 4'b0000 | スケジューラ非アクティブ、トリガ待ち |
| `S_SCAN_READY` | 4'b0001 | Readyキューのスキャン (最高優先度タスク検索) |
| `S_COMPARE_PRIORITY` | 4'b0010 | 現タスクとの優先度比較 |
| `S_PREEMPT_CHECK` | 4'b0011 | プリエンプション判定 |
| `S_CONTEXT_SAVE` | 4'b0100 | 現タスクのコンテキスト退避 |
| `S_CONTEXT_LOAD` | 4'b0101 | 次タスクのコンテキスト復帰 |
| `S_DISPATCH` | 4'b0110 | タスクディスパッチ (CPU再開) |
| `S_TIMER_UPDATE` | 4'b0111 | タイムスライス更新 |
| `S_TASK_CREATE` | 4'b1000 | 新規タスク生成 |
| `S_TASK_EXIT` | 4'b1001 | タスク終了処理 |
| `S_BLOCK_TASK` | 4'b1010 | タスクのブロック処理 |
| `S_UNBLOCK_TASK` | 4'b1011 | タスクのアンブロック処理 |

### 1.2 スケジューリングポリシー

#### 優先度ベーススケジューリング
- 16段階の優先度 (0=最高, 15=最低)
- 常に最高優先度のReadyタスクを実行
- 同優先度タスクはラウンドロビンで順番に実行

#### Readyキュー構造
```
優先度ビットマップ (16ビット):
  ready_bitmap[15:0]  // ビットi=1: 優先度iにReadyタスクが存在

各優先度のReadyキュー (リンクリスト):
  ready_head[0..15]   // 各優先度キューの先頭タスクID
  ready_tail[0..15]   // 各優先度キューの末尾タスクID

最高優先度検索:
  highest_ready_prio = CLZ(ready_bitmap)  // Count Leading Zeros
  → ハードウェアで1サイクルで最高優先度を特定
```

### 1.3 プリエンプティブスケジューリングのトリガ条件

| トリガ | 説明 | 発生元 |
|---|---|---|
| タイマ割り込み | タイムスライス満了 | CLINT (mip.MTIP) |
| タスク生成 | 新タスクが現タスクより高優先度 | pthread_create syscall |
| タスク終了 | 現タスクが終了 | pthread_exit syscall |
| セマフォ/ミューテックス解放 | 待ちタスクのウェイクアップ | sem_post / mutex_unlock |
| タスクのブロック | 現タスクがリソース待ちに入る | sem_wait / mutex_lock / mq_receive |
| 明示的yield | タスクがCPU使用権を放棄 | sched_yield syscall |

### 1.4 状態遷移図

```
                        タイマ割り込み / タスク生成 /
                        タスク終了 / リソース解放 /
                        ブロック / yield
                              |
                              v
    +--------+          +----------+
    |  IDLE  |--------->| TIMER_   |
    |        |  timer   | UPDATE   |
    +--------+  irq     +----------+
       ^  |                   |
       |  |   task_create     | タイムスライス更新完了
       |  +----------+       v
       |             |  +------------+
       |             +->| SCAN_READY |<---------+
       |                +------------+          |
       |                      |                 |
       |                      | 最高優先度タスク発見
       |                      v                 |
       |              +---------------+         |
       |              | COMPARE_      |         |
       |              | PRIORITY      |         |
       |              +---------------+         |
       |                 |          |           |
       |        同優先度 |          | 異なる優先度
       |        or 低い  |          |           |
       |                 |          v           |
       |                 |  +-------------+     |
       |                 |  | PREEMPT_    |     |
       |                 |  | CHECK       |     |
       |                 |  +-------------+     |
       |                 |     |        |       |
       |    プリエンプト  |     |不要    | 必要  |
       |    不要         |     |        |       |
       |                 v     v        v       |
       |              +--------+  +-----------+ |
       |              |DISPATCH|  | CONTEXT_  | |
       |              |(現タスク|  | SAVE      | |
       |              | 継続)  |  +-----------+ |
       |              +--------+       |        |
       |                 |             v        |
       |                 |       +-----------+  |
       |                 |       | CONTEXT_  |  |
       |                 |       | LOAD      |  |
       |                 |       +-----------+  |
       |                 |             |        |
       |                 |             v        |
       |                 |       +-----------+  |
       |                 +------>| DISPATCH  |--+
       |                         | (新タスク) |
       |                         +-----------+
       |                              |
       +------------------------------+
                  完了
```

### 1.5 状態遷移詳細

#### S_IDLE → S_TIMER_UPDATE
```
条件: timer_irq == 1 (タイマ割り込み受信)
動作: タイムスライスカウンタのデクリメント開始
```

#### S_IDLE → S_SCAN_READY
```
条件: schedule_trigger == 1
  (タスク生成/終了/ブロック/アンブロック/yield)
動作: ready_bitmapから最高優先度を検索
```

#### S_TIMER_UPDATE → S_SCAN_READY
```
条件: 常に (タイムスライス更新後)
動作:
  - current_task.time_slice -= 1
  - if (time_slice == 0):
      current_task.time_slice = current_task.time_slice_reload
      タスクをReadyキューの末尾に移動 (ラウンドロビン)
  - スキャン開始
```

#### S_SCAN_READY → S_COMPARE_PRIORITY
```
条件: ready_bitmap != 0 (Readyタスクが存在)
動作: highest_ready_prio = CLZ(ready_bitmap)
      next_task_id = ready_head[highest_ready_prio]
```

#### S_SCAN_READY → S_IDLE
```
条件: ready_bitmap == 0 (Readyタスクなし)
動作: アイドルタスク (タスクID=0) を実行
```

#### S_COMPARE_PRIORITY → S_PREEMPT_CHECK
```
条件: next_task_id != current_task_id
動作: 優先度比較結果を保持
```

#### S_COMPARE_PRIORITY → S_DISPATCH
```
条件: next_task_id == current_task_id (現タスク継続)
動作: ディスパッチ処理へ (コンテキストスイッチ不要)
```

#### S_PREEMPT_CHECK → S_CONTEXT_SAVE
```
条件: next_task_prio < current_task_prio (プリエンプション必要)
      || current_task_blocked || current_task_terminated
動作: コンテキスト退避開始
```

#### S_PREEMPT_CHECK → S_DISPATCH
```
条件: next_task_prio >= current_task_prio && !current_task_blocked
      (プリエンプション不要)
動作: 現タスク継続
```

#### S_CONTEXT_SAVE → S_CONTEXT_LOAD
```
条件: save_done == 1 (コンテキスト退避完了)
動作: 次タスクTCBの読み出し開始
```

#### S_CONTEXT_LOAD → S_DISPATCH
```
条件: load_done == 1 (コンテキスト復帰完了)
動作: ディスパッチ処理
```

#### S_DISPATCH → S_IDLE
```
条件: 常に
動作:
  - current_task_id <= next_task_id
  - CPU再開信号アサート
  - タイマ割り込みクリア
```

---

## 2. タスク状態管理 (5状態)

### 2.1 タスク状態定義

| 状態 | エンコード | 説明 |
|---|---|---|
| **Ready** | 3'b000 | 実行可能。Readyキュー内に配置。 |
| **Running** | 3'b001 | CPU上で実行中。同時に1タスクのみ。 |
| **Blocked** | 3'b010 | リソース待ち (セマフォ/ミューテックス/メッセージ/sleep)。 |
| **Suspended** | 3'b011 | 明示的に一時停止。resume要求で復帰可能。 |
| **Terminated** | 3'b100 | 実行終了。join待ちタスクへの通知後、TCB解放可能。 |

### 2.2 タスク状態遷移図

```
                   pthread_create
                        |
                        v
                  +-----------+
          +------>|   Ready   |<------+
          |       +-----------+       |
          |         |       ^         |
          |  スケジュール  |  プリエンプト  |
          |  選択    |       |  (yield/    |
          |         v       |  タイムスライス|
          |       +-----------+  満了)   |
          |       |  Running  |---------+
          |       +-----------+
          |         |    |    |
          |    sem_wait/ |    | pthread_exit
          |   mutex_lock |    |
          |   mq_receive |    v
          |   nanosleep  |  +-----------+
          |         |    |  |Terminated |
          |         v    |  +-----------+
          |    +---------+
          |    | Blocked |
          |    +---------+
          |       |    ^
    sem_post/     |    | suspend (from Blocked)
   mutex_unlock/  |    |
   mq_send/       |    v
   timer_expire   | +----------+
          |       | |Suspended |
          +-------+ +----------+
                       ^    |
                       |    | resume
               suspend |    |
              (from    |    v
               Ready)  +----+---> Ready
                             (resume)

  +-----------+    +-----------+    +-----------+
  |  Blocked  |--->| Suspended |    |           |
  +-----------+    +-----------+    | Ready     |---> suspend ---> Suspended
  suspend中に                       |           |
  リソース確保                       +-----------+
  → Suspended維持                       ^
  resume後Ready                         |
                                    resume (from Suspended)
```

### 2.3 状態遷移条件一覧

| 遷移元 | 遷移先 | トリガ条件 | 動作 |
|---|---|---|---|
| (生成) | Ready | pthread_create | TCB初期化、Readyキュー追加 |
| Ready | Running | スケジューラ選択 | コンテキスト復帰、CPU実行開始 |
| Running | Ready | タイムスライス満了 / yield / プリエンプト | コンテキスト退避、Readyキュー末尾追加 |
| Running | Blocked | sem_wait(cnt=0) / mutex_lock(locked) / mq_receive(empty) / nanosleep | コンテキスト退避、待ちキューに追加 |
| Running | Suspended | 自タスクsuspend | コンテキスト退避 |
| Running | Terminated | pthread_exit | リソース解放、join待ちタスク通知 |
| Blocked | Ready | リソース確保 (sem_post / mutex_unlock / mq_send / timer_expire) | 待ちキューから除去、Readyキュー追加 |
| Blocked | Suspended | 外部からsuspend | 待ちキューから除去、suspend_reason記録 |
| Suspended | Ready | resume (元がReady/Running) | Readyキュー追加 |
| Suspended | Blocked | resume (元がBlocked) | 待ちキューに再追加 |

---

## 3. コンテキストスイッチシーケンス

### 3.1 詳細ステップ (サイクル精度)

```
サイクル  動作                                          信号
------  ----------------------------------------      ------------------
  0     RTOS: コンテキストスイッチ要求アサート          ctx_switch_req = 1
  1     CPU: パイプラインフラッシュ開始                  pipeline_flush = 1
  2     CPU: パイプラインフラッシュ完了                  flush_done = 1
  3     CPU→RTOS: PC退避                              save_pc = current_pc
  4     CPU→RTOS: mstatus CSR退避                     save_csr = mstatus
  5-36  CPU→RTOS: 汎用レジスタ退避 (x1〜x31)          save_reg[n] = x[n]
        1サイクルにつき1レジスタ、32サイクル             (x0はスキップ可、31サイクルに短縮可)
 37     RTOS: 現タスクTCB更新                          tcb_write = 1
        (state, sp, pc, time_slice)
 38     RTOS: PMP設定退避                              pmp_save = 1
 39-40  RTOS: 次タスクTCB読み出し                      tcb_read = 1
        (task_id, state, sp, pc, time_slice_reload)   (2サイクル: BRAMレイテンシ)
 41     RTOS: 次タスクPMP設定復帰                      pmp_load = 1
 42     RTOS→CPU: mstatus CSR復帰                     load_csr = saved_mstatus
 43-74  RTOS→CPU: 汎用レジスタ復帰 (x1〜x31)          load_reg[n] = saved_x[n]
        1サイクルにつき1レジスタ、32サイクル
 75     RTOS→CPU: PC復帰                              load_pc = saved_pc
 76     RTOS: コンテキストスイッチ完了信号              ctx_switch_done = 1
 77     CPU: パイプライン再開                           pipeline_resume = 1
        IF段から復帰PCでフェッチ開始
```

### 3.2 最悪ケースサイクル数見積もり

| フェーズ | サイクル数 | 説明 |
|---|---|---|
| スイッチ要求〜フラッシュ | 2 | パイプラインフラッシュ |
| PC/CSR退避 | 2 | PC + mstatus |
| レジスタ退避 (x1-x31) | 31 | 1レジスタ/サイクル |
| TCB更新 (現タスク) | 1 | BRAM書き込み |
| PMP退避 | 1 | PMP設定保存 |
| TCB読み出し (次タスク) | 2 | BRAM読み出し (レイテンシ) |
| PMP復帰 | 1 | PMP設定復帰 |
| CSR復帰 | 1 | mstatus復帰 |
| レジスタ復帰 (x1-x31) | 31 | 1レジスタ/サイクル |
| PC復帰 + 完了 | 2 | PC設定 + 完了信号 |
| パイプライン再開 | 1 | IF段再開 |
| **合計** | **約75サイクル** | |

> 注: バースト転送やレジスタバンク方式を採用することで、退避/復帰を高速化可能 (将来最適化)。
> レジスタバンク方式: 各タスクに専用レジスタセットを持たせ、バンク切り替えのみ (2-3サイクル)。ただしFPGAリソース消費が大きい。

### 3.3 コンテキストスイッチ信号インターフェース

| 信号名 | 方向 | ビット幅 | 説明 |
|---|---|---|---|
| `ctx_switch_req` | RTOS→CPU | 1 | コンテキストスイッチ要求 |
| `ctx_switch_ack` | CPU→RTOS | 1 | 要求受付確認 |
| `ctx_switch_done` | RTOS→CPU | 1 | コンテキストスイッチ完了 |
| `pipeline_flush_done` | CPU→RTOS | 1 | パイプラインフラッシュ完了 |
| `save_reg_data` | CPU→RTOS | 32 | レジスタ退避データ |
| `save_reg_addr` | RTOS→CPU | 5 | 退避対象レジスタ番号 |
| `save_reg_valid` | RTOS→CPU | 1 | レジスタ退避有効 |
| `load_reg_data` | RTOS→CPU | 32 | レジスタ復帰データ |
| `load_reg_addr` | RTOS→CPU | 5 | 復帰対象レジスタ番号 |
| `load_reg_valid` | RTOS→CPU | 1 | レジスタ復帰有効 |
| `save_pc` | CPU→RTOS | 32 | 退避PC |
| `load_pc` | RTOS→CPU | 32 | 復帰PC |
| `save_csr` | CPU→RTOS | 32 | 退避CSR (mstatus) |
| `load_csr` | RTOS→CPU | 32 | 復帰CSR (mstatus) |

---

## 4. TCBレジスタ構成

### 4.1 TCBフィールド定義

| フィールド名 | ビット範囲 | ビット幅 | 説明 |
|---|---|---|---|
| `task_id` | [7:0] | 8 | タスクID (0〜255、0=アイドルタスク) |
| `priority` | [3:0] | 4 | 優先度 (0=最高, 15=最低) |
| `state` | [2:0] | 3 | タスク状態 (Ready/Running/Blocked/Suspended/Terminated) |
| `sp` | [31:0] | 32 | スタックポインタ |
| `pc` | [31:0] | 32 | プログラムカウンタ (退避時) |
| `time_slice` | [15:0] | 16 | タイムスライス残量 (クロックサイクル単位) |
| `time_slice_reload` | [15:0] | 16 | タイムスライス初期値 |
| `blocked_on` | [7:0] | 8 | ブロック要因ID (セマフォID/ミューテックスID/キューID) |
| `blocked_type` | [1:0] | 2 | ブロック種別 (00:なし, 01:セマフォ, 10:ミューテックス, 11:メッセージキュー) |
| `reg_save_addr` | [31:0] | 32 | レジスタ退避先ベースアドレス (BRAM内) |
| `csr_mstatus` | [31:0] | 32 | 退避CSR: mstatus |
| `csr_mepc` | [31:0] | 32 | 退避CSR: mepc |
| `next_task` | [7:0] | 8 | リンクリスト: 次タスクID (Ready/Waitキュー用) |
| `prev_task` | [7:0] | 8 | リンクリスト: 前タスクID (双方向リスト) |
| `join_wait_task` | [7:0] | 8 | このタスクのjoinを待っているタスクID |
| `stack_base` | [31:0] | 32 | スタック領域ベースアドレス |
| `stack_size` | [15:0] | 16 | スタックサイズ (バイト) |
| `entry_point` | [31:0] | 32 | タスクエントリポイントアドレス |
| `pmp_cfg` | [31:0] | 32 | PMP設定 (pmpcfg0相当) |
| `pmp_addr0` | [31:0] | 32 | PMPアドレス0 |
| `pmp_addr1` | [31:0] | 32 | PMPアドレス1 |
| `pmp_addr2` | [31:0] | 32 | PMPアドレス2 |
| `pmp_addr3` | [31:0] | 32 | PMPアドレス3 |
| **合計** | | **約480ビット (60バイト)** | |

### 4.2 TCBメモリレイアウト (BRAM内)

```
TCBメモリマップ (1タスクあたり64バイト = 16ワード、2^4ワード境界):

ワードオフセット  フィールド
  +0x00         task_id[7:0] | priority[3:0] | state[2:0] | blocked_type[1:0] | reserved[14:0]
  +0x04         sp[31:0]
  +0x08         pc[31:0]
  +0x0C         time_slice[15:0] | time_slice_reload[15:0]
  +0x10         blocked_on[7:0] | next_task[7:0] | prev_task[7:0] | join_wait_task[7:0]
  +0x14         reg_save_addr[31:0]
  +0x18         csr_mstatus[31:0]
  +0x1C         csr_mepc[31:0]
  +0x20         stack_base[31:0]
  +0x24         stack_size[15:0] | entry_point[15:0] (下位16ビット)
  +0x28         entry_point[31:16] | reserved[15:0]
  +0x2C         pmp_cfg[31:0]
  +0x30         pmp_addr0[31:0]
  +0x34         pmp_addr1[31:0]
  +0x38         pmp_addr2[31:0]
  +0x3C         pmp_addr3[31:0]

TCBテーブルベースアドレス: TCB_BASE (パラメータ)
タスクnのTCBアドレス: TCB_BASE + (n * 64)
最大256タスク: TCB_BASE〜TCB_BASE + 16384 (16KB)
```

### 4.3 レジスタ退避領域レイアウト

```
レジスタ退避領域 (1タスクあたり128バイト = 32ワード):

ワードオフセット  レジスタ
  +0x00         x0  (常に0、退避不要だが領域確保)
  +0x04         x1  (ra: return address)
  +0x08         x2  (sp: stack pointer) ← TCBのspフィールドと同一
  +0x0C         x3  (gp: global pointer)
  +0x10         x4  (tp: thread pointer)
  ...
  +0x78         x30
  +0x7C         x31

レジスタ退避ベースアドレス: REG_SAVE_BASE (パラメータ)
タスクnの退避領域: REG_SAVE_BASE + (n * 128)
最大256タスク: REG_SAVE_BASE〜REG_SAVE_BASE + 32768 (32KB)
```

### 4.4 最大タスク数の設計

```systemverilog
// パラメータ定義
parameter MAX_TASKS       = 256;    // 最大タスク数
parameter TASK_ID_WIDTH   = 8;      // タスクID幅 = log2(MAX_TASKS)
parameter TCB_SIZE        = 64;     // TCBサイズ (バイト)
parameter REG_SAVE_SIZE   = 128;    // レジスタ退避サイズ (バイト)
parameter PRIORITY_LEVELS = 16;     // 優先度レベル数
parameter PRIORITY_WIDTH  = 4;      // 優先度幅 = log2(PRIORITY_LEVELS)

// BRAM使用量見積もり
// TCBテーブル:      MAX_TASKS * TCB_SIZE      = 256 * 64  = 16,384 bytes (16KB)
// レジスタ退避:     MAX_TASKS * REG_SAVE_SIZE = 256 * 128 = 32,768 bytes (32KB)
// 合計BRAM使用量:   48KB (RTOS管理領域)
```

---

## 5. セマフォ/ミューテックス取得・解放FSM

### 5.1 セマフォFSM

#### セマフォ制御ブロック (SCB) 定義

| フィールド名 | ビット幅 | 説明 |
|---|---|---|
| `sem_id` | [7:0] | セマフォID |
| `count` | [15:0] | 現在のカウント値 |
| `max_count` | [15:0] | 最大カウント値 |
| `wait_queue_head` | [7:0] | 待ちキュー先頭タスクID (0xFF=空) |
| `wait_queue_tail` | [7:0] | 待ちキュー末尾タスクID |
| `valid` | [0:0] | セマフォ有効フラグ |

```
SCBメモリレイアウト (1セマフォあたり8バイト = 2ワード):
  +0x00: sem_id[7:0] | count[15:0] | valid[0:0] | reserved[6:0]
  +0x04: max_count[15:0] | wait_queue_head[7:0] | wait_queue_tail[7:0]

最大セマフォ数: 64 (パラメータ: MAX_SEMAPHORES)
SCBテーブルサイズ: 64 * 8 = 512 bytes
```

#### FSM状態定義

| 状態 | エンコード | 説明 |
|---|---|---|
| `SEM_IDLE` | 3'b000 | アイドル |
| `SEM_CHECK_COUNT` | 3'b001 | カウント値チェック |
| `SEM_ACQUIRE` | 3'b010 | セマフォ取得 (デクリメント) |
| `SEM_BLOCK_TASK` | 3'b011 | タスクをブロック状態へ |
| `SEM_RELEASE` | 3'b100 | セマフォ解放 (インクリメント) |
| `SEM_WAKE_TASK` | 3'b101 | 待ちタスクのウェイクアップ |
| `SEM_DONE` | 3'b110 | 操作完了 |

#### セマフォ取得操作 (sem_wait) FSM

```
                    sem_wait要求
                         |
                         v
                  +------------+
                  | SEM_IDLE   |
                  +------------+
                         |
                         v
                  +--------------+
                  | SEM_CHECK_   |
                  | COUNT        |
                  +--------------+
                    |           |
          count > 0 |           | count == 0
                    v           v
            +------------+  +-------------+
            | SEM_       |  | SEM_BLOCK_  |
            | ACQUIRE    |  | TASK        |
            +------------+  +-------------+
                    |           |
                    |           | タスク状態→Blocked
                    |           | 待ちキューに追加
                    v           v
                  +------------+
                  | SEM_DONE   |
                  +------------+
                         |
                    戻り値設定:
                    ACQUIRE → 0 (成功)
                    BLOCK → スケジューラ起動
```

#### セマフォ取得操作の詳細動作

```
SEM_CHECK_COUNT:
  1. SCBからcount読み出し (1サイクル: BRAM読み出し)
  2. count > 0 → SEM_ACQUIRE
  3. count == 0 → SEM_BLOCK_TASK

SEM_ACQUIRE:
  1. count <= count - 1
  2. SCBのcount更新 (1サイクル: BRAM書き込み)
  3. 戻り値 a0 <= 0 (成功)
  4. → SEM_DONE

SEM_BLOCK_TASK:
  1. 現タスクの状態をBlocked (3'b010) に変更
  2. TCB.blocked_on <= sem_id
  3. TCB.blocked_type <= 2'b01 (セマフォ)
  4. 待ちキュー末尾に現タスクを追加:
     - wait_queue_tail.next_task <= current_task_id
     - wait_queue_tail <= current_task_id
     - (空キューの場合: wait_queue_head <= current_task_id)
  5. スケジューラにスケジュール要求
  6. → SEM_DONE
```

#### セマフォ解放操作 (sem_post) FSM

```
                    sem_post要求
                         |
                         v
                  +------------+
                  | SEM_IDLE   |
                  +------------+
                         |
                         v
                  +--------------+
                  | SEM_CHECK_   |
                  | COUNT        |
                  +--------------+
                    |              |
      wait_queue    |              | wait_queue
      非空          |              | 空
                    v              v
            +-------------+  +------------+
            | SEM_WAKE_   |  | SEM_       |
            | TASK        |  | RELEASE    |
            +-------------+  +------------+
                    |              |
                    | 最高優先度    | count++
                    | タスクをReady |
                    v              v
                  +------------+
                  | SEM_DONE   |
                  +------------+
```

#### セマフォ解放操作の詳細動作

```
SEM_CHECK_COUNT (解放時):
  1. SCBからwait_queue_head読み出し
  2. wait_queue_head != 0xFF → SEM_WAKE_TASK (待ちタスクあり)
  3. wait_queue_head == 0xFF → SEM_RELEASE (待ちタスクなし)

SEM_WAKE_TASK:
  1. wait_queue_headのタスクを取得
  2. 待ちキューから除去 (wait_queue_head <= next_task)
  3. 対象タスクの状態をReady (3'b000) に変更
  4. TCB.blocked_on <= 0, TCB.blocked_type <= 2'b00
  5. Readyキューに追加
  6. (セマフォのcountは変更しない: 取得→解放が相殺)
  7. スケジューラにプリエンプションチェック要求
  8. 戻り値 a0 <= 0 (成功)
  9. → SEM_DONE

SEM_RELEASE:
  1. count < max_count チェック
  2. count <= count + 1
  3. SCBのcount更新
  4. 戻り値 a0 <= 0 (成功)
  5. (count == max_count の場合: 戻り値 a0 <= -EOVERFLOW)
  6. → SEM_DONE
```

---

### 5.2 ミューテックスFSM

#### ミューテックス制御ブロック (MCB) 定義

| フィールド名 | ビット幅 | 説明 |
|---|---|---|
| `mutex_id` | [7:0] | ミューテックスID |
| `owner` | [7:0] | 所有者タスクID (0xFF=未ロック) |
| `locked` | [0:0] | ロック状態 |
| `original_priority` | [3:0] | 所有者の元の優先度 (優先度継承用) |
| `wait_queue_head` | [7:0] | 待ちキュー先頭タスクID |
| `wait_queue_tail` | [7:0] | 待ちキュー末尾タスクID |
| `nest_count` | [3:0] | ネストカウント (再帰ロック用、将来拡張) |
| `valid` | [0:0] | ミューテックス有効フラグ |

```
MCBメモリレイアウト (1ミューテックスあたり8バイト = 2ワード):
  +0x00: mutex_id[7:0] | owner[7:0] | locked[0:0] | original_priority[3:0] | nest_count[3:0] | valid[0:0] | reserved[1:0]
  +0x04: wait_queue_head[7:0] | wait_queue_tail[7:0] | reserved[15:0]

最大ミューテックス数: 64 (パラメータ: MAX_MUTEXES)
MCBテーブルサイズ: 64 * 8 = 512 bytes
```

#### FSM状態定義

| 状態 | エンコード | 説明 |
|---|---|---|
| `MTX_IDLE` | 3'b000 | アイドル |
| `MTX_CHECK_OWNER` | 3'b001 | 所有者チェック |
| `MTX_ACQUIRE` | 3'b010 | ミューテックス取得 |
| `MTX_BLOCK_TASK` | 3'b011 | タスクをブロック状態へ |
| `MTX_RELEASE` | 3'b100 | ミューテックス解放 |
| `MTX_WAKE_TASK` | 3'b101 | 待ちタスクへのロック移譲 |
| `MTX_PRIORITY_INHERIT` | 3'b110 | 優先度継承処理 |
| `MTX_DONE` | 3'b111 | 操作完了 |

#### ミューテックス取得操作 (mutex_lock) FSM

```
                    mutex_lock要求
                         |
                         v
                  +------------+
                  | MTX_IDLE   |
                  +------------+
                         |
                         v
                  +--------------+
                  | MTX_CHECK_   |
                  | OWNER        |
                  +--------------+
                    |           |
          未ロック  |           | 他タスクがロック中
                    v           v
            +------------+  +------------------+
            | MTX_       |  | MTX_PRIORITY_    |
            | ACQUIRE    |  | INHERIT          |
            +------------+  +------------------+
                    |           |
                    |           | 優先度継承処理後
                    |           v
                    |       +-------------+
                    |       | MTX_BLOCK_  |
                    |       | TASK        |
                    |       +-------------+
                    |           |
                    v           v
                  +------------+
                  | MTX_DONE   |
                  +------------+
```

#### ミューテックス取得操作の詳細動作

```
MTX_CHECK_OWNER:
  1. MCBからowner, locked読み出し
  2. locked == 0 → MTX_ACQUIRE (未ロック)
  3. locked == 1 && owner == current_task_id → MTX_DONE (自タスク再ロック: エラー -EDEADLK)
  4. locked == 1 && owner != current_task_id → MTX_PRIORITY_INHERIT

MTX_ACQUIRE:
  1. locked <= 1
  2. owner <= current_task_id
  3. original_priority <= current_task.priority
  4. MCB更新
  5. 戻り値 a0 <= 0 (成功)
  6. → MTX_DONE

MTX_PRIORITY_INHERIT:
  条件: current_task.priority < owner.priority (現タスクが高優先度)
  動作:
    1. owner_task.priority <= current_task.priority (所有者の優先度を引き上げ)
    2. 所有者がReadyキューにいる場合、キュー位置を再配置
    3. → MTX_BLOCK_TASK

MTX_BLOCK_TASK:
  1. 現タスクの状態をBlocked (3'b010) に変更
  2. TCB.blocked_on <= mutex_id
  3. TCB.blocked_type <= 2'b10 (ミューテックス)
  4. 待ちキューに追加 (優先度順: 最高優先度が先頭)
  5. スケジューラにスケジュール要求
  6. → MTX_DONE
```

#### ミューテックス解放操作 (mutex_unlock) FSM

```
                    mutex_unlock要求
                         |
                         v
                  +------------+
                  | MTX_IDLE   |
                  +------------+
                         |
                         v
                  +--------------+
                  | MTX_CHECK_   |
                  | OWNER        |
                  +--------------+
                    |           |
          所有者    |           | 非所有者
          一致      |           | → エラー (-EPERM)
                    v           v
            +--------------+  +----------+
            | MTX_RELEASE  |  | MTX_DONE |
            +--------------+  | (error)  |
                    |         +----------+
                    v
             wait_queue確認
                    |
           +--------+--------+
           |                 |
     待ちタスクあり    待ちタスクなし
           |                 |
           v                 v
    +-------------+   +-----------+
    | MTX_WAKE_   |   | ロック    |
    | TASK        |   | 解放完了  |
    +-------------+   +-----------+
           |                 |
           v                 v
    +------------+
    | MTX_DONE   |
    +------------+
```

#### ミューテックス解放操作の詳細動作

```
MTX_CHECK_OWNER (解放時):
  1. MCBからowner読み出し
  2. owner == current_task_id → MTX_RELEASE
  3. owner != current_task_id → MTX_DONE (エラー: -EPERM)

MTX_RELEASE:
  1. 所有者の優先度を元に戻す (original_priorityが現在の優先度と異なる場合):
     current_task.priority <= original_priority
  2. wait_queue_head確認
  3. wait_queue_head != 0xFF → MTX_WAKE_TASK
  4. wait_queue_head == 0xFF → ロック解放 (locked <= 0, owner <= 0xFF)

MTX_WAKE_TASK:
  1. 待ちキュー先頭タスクを取得 (最高優先度)
  2. 待ちキューから除去
  3. ロック移譲:
     - owner <= wake_task_id
     - original_priority <= wake_task.priority
  4. 対象タスクの状態をReady (3'b000) に変更
  5. Readyキューに追加
  6. スケジューラにプリエンプションチェック要求
  7. 戻り値 a0 <= 0 (成功)
  8. → MTX_DONE
```

#### 優先度逆転防止 (優先度継承プロトコル)

```
優先度継承の動作例:

タスクA (優先度1: 高), タスクB (優先度2: 中), タスクC (優先度3: 低)

1. タスクCがミューテックスMをロック → C実行中
2. タスクAがミューテックスMをロック試行
   → Cの優先度をAの優先度(1)に引き上げ (優先度継承)
   → Aはブロック状態
3. タスクBがReady状態に → しかしCの優先度が1なのでプリエンプトされない
   (優先度逆転を防止)
4. タスクCがミューテックスMをアンロック
   → Cの優先度を元の3に戻す
   → ミューテックスをAに移譲、AをReady状態に
5. タスクAが最高優先度 → A実行
```

---

## 6. メッセージキュー送信・受信FSM

### 6.1 メッセージキュー制御ブロック (QCB) 定義

| フィールド名 | ビット幅 | 説明 |
|---|---|---|
| `queue_id` | [7:0] | キューID |
| `queue_depth` | [7:0] | キュー最大深さ (エントリ数) |
| `msg_size` | [7:0] | 1メッセージのサイズ (ワード数) |
| `count` | [7:0] | 現在のメッセージ数 |
| `head_ptr` | [7:0] | 読み出しポインタ (リングバッファ) |
| `tail_ptr` | [7:0] | 書き込みポインタ (リングバッファ) |
| `send_wait_head` | [7:0] | 送信待ちキュー先頭タスクID |
| `send_wait_tail` | [7:0] | 送信待ちキュー末尾タスクID |
| `recv_wait_head` | [7:0] | 受信待ちキュー先頭タスクID |
| `recv_wait_tail` | [7:0] | 受信待ちキュー末尾タスクID |
| `buffer_base` | [31:0] | メッセージバッファベースアドレス |
| `valid` | [0:0] | キュー有効フラグ |

```
QCBメモリレイアウト (1キューあたり16バイト = 4ワード):
  +0x00: queue_id[7:0] | queue_depth[7:0] | msg_size[7:0] | count[7:0]
  +0x04: head_ptr[7:0] | tail_ptr[7:0] | send_wait_head[7:0] | send_wait_tail[7:0]
  +0x08: recv_wait_head[7:0] | recv_wait_tail[7:0] | valid[0:0] | reserved[14:0]
  +0x0C: buffer_base[31:0]

最大キュー数: 32 (パラメータ: MAX_QUEUES)
QCBテーブルサイズ: 32 * 16 = 512 bytes
```

### 6.2 FSM状態定義

| 状態 | エンコード | 説明 |
|---|---|---|
| `MQ_IDLE` | 3'b000 | アイドル |
| `MQ_CHECK_QUEUE` | 3'b001 | キュー状態チェック |
| `MQ_ENQUEUE` | 3'b010 | メッセージエンキュー |
| `MQ_DEQUEUE` | 3'b011 | メッセージデキュー |
| `MQ_BLOCK_SENDER` | 3'b100 | 送信タスクをブロック |
| `MQ_BLOCK_RECEIVER` | 3'b101 | 受信タスクをブロック |
| `MQ_WAKE_TASK` | 3'b110 | 待ちタスクのウェイクアップ |
| `MQ_DONE` | 3'b111 | 操作完了 |

### 6.3 送信操作 (mq_send) FSM

```
                    mq_send要求
                    (queue_id, msg_ptr, msg_size)
                         |
                         v
                  +------------+
                  | MQ_IDLE    |
                  +------------+
                         |
                         v
                  +--------------+
                  | MQ_CHECK_    |
                  | QUEUE        |
                  +--------------+
                    |       |        |
          受信待ち  |  空き |        | 満杯
          タスクあり |  あり |        |
                    |       |        v
                    |       |  +---------------+
                    |       |  | MQ_BLOCK_     |
                    |       |  | SENDER        |
                    |       |  +---------------+
                    |       |        |
                    v       v        v
            +-------------+ |  +----------+
            | MQ_WAKE_    | |  | MQ_DONE  |
            | TASK        | |  | (blocked)|
            +-------------+ |  +----------+
                    |       |
                    v       v
              +------------+
              | MQ_ENQUEUE |
              +------------+
                    |
                    v
              +------------+
              | MQ_DONE    |
              +------------+
```

#### 送信操作の詳細動作

```
MQ_CHECK_QUEUE (送信時):
  1. QCBからcount, queue_depth, recv_wait_head読み出し
  2. recv_wait_head != 0xFF → 受信待ちタスクにダイレクト転送 + MQ_WAKE_TASK
  3. count < queue_depth → MQ_ENQUEUE (空きあり)
  4. count == queue_depth → MQ_BLOCK_SENDER (満杯)

MQ_ENQUEUE:
  1. メッセージデータをバッファに書き込み:
     write_addr = buffer_base + (tail_ptr * msg_size * 4)
     バッファ[write_addr] <= msg_data (msg_sizeワード分)
  2. tail_ptr <= (tail_ptr + 1) % queue_depth
  3. count <= count + 1
  4. QCB更新
  5. 戻り値 a0 <= 0 (成功)
  6. → MQ_DONE

MQ_BLOCK_SENDER:
  1. 現タスクの状態をBlocked (3'b010) に変更
  2. TCB.blocked_on <= queue_id
  3. TCB.blocked_type <= 2'b11 (メッセージキュー)
  4. 送信待ちキューに追加
  5. スケジューラにスケジュール要求
  6. → MQ_DONE

MQ_WAKE_TASK (送信時: 受信待ちタスクのウェイク):
  1. recv_wait_headのタスクを取得
  2. 受信待ちキューから除去
  3. メッセージデータをダイレクトにタスクに転送 (メモリ経由)
  4. 対象タスクの状態をReady (3'b000) に変更
  5. Readyキューに追加
  6. スケジューラにプリエンプションチェック要求
  7. → MQ_DONE
```

### 6.4 受信操作 (mq_receive) FSM

```
                    mq_receive要求
                    (queue_id, buf_ptr, buf_size)
                         |
                         v
                  +------------+
                  | MQ_IDLE    |
                  +------------+
                         |
                         v
                  +--------------+
                  | MQ_CHECK_    |
                  | QUEUE        |
                  +--------------+
                    |       |        |
          送信待ち  |  msg  |        | キュー空
          タスクあり |  あり |        |
                    |       |        v
                    |       |  +---------------+
                    |       |  | MQ_BLOCK_     |
                    |       |  | RECEIVER      |
                    |       |  +---------------+
                    |       |        |
                    v       v        v
              +------------+ |  +----------+
              | MQ_DEQUEUE | |  | MQ_DONE  |
              +------------+ |  | (blocked)|
                    |       |  +----------+
                    v       |
            +-------------+|
            | MQ_WAKE_    ||
            | TASK        ||
            +-------------+|
                    |       |
                    v       v
              +------------+
              | MQ_DONE    |
              +------------+
```

#### 受信操作の詳細動作

```
MQ_CHECK_QUEUE (受信時):
  1. QCBからcount, send_wait_head読み出し
  2. count > 0 → MQ_DEQUEUE (メッセージあり)
  3. count == 0 → MQ_BLOCK_RECEIVER (キュー空)

MQ_DEQUEUE:
  1. メッセージデータをバッファから読み出し:
     read_addr = buffer_base + (head_ptr * msg_size * 4)
     msg_data <= バッファ[read_addr] (msg_sizeワード分)
  2. head_ptr <= (head_ptr + 1) % queue_depth
  3. count <= count - 1
  4. QCB更新
  5. メッセージデータを受信タスクのバッファにコピー
  6. send_wait_head != 0xFF → MQ_WAKE_TASK (送信待ちタスクあり)
  7. 戻り値 a0 <= msg_size (受信バイト数)
  8. → MQ_DONE

MQ_BLOCK_RECEIVER:
  1. 現タスクの状態をBlocked (3'b010) に変更
  2. TCB.blocked_on <= queue_id
  3. TCB.blocked_type <= 2'b11 (メッセージキュー)
  4. 受信待ちキューに追加
  5. スケジューラにスケジュール要求
  6. → MQ_DONE

MQ_WAKE_TASK (受信時: 送信待ちタスクのウェイク):
  1. send_wait_headのタスクを取得
  2. 送信待ちキューから除去
  3. 送信待ちタスクのメッセージをキューにエンキュー
  4. 対象タスクの状態をReady (3'b000) に変更
  5. Readyキューに追加
  6. スケジューラにプリエンプションチェック要求
  7. → MQ_DONE
```

### 6.5 メッセージバッファメモリレイアウト

```
メッセージバッファ構造 (リングバッファ):

キューnのバッファ:
  base_addr = MQ_BUFFER_BASE + queue_offset[n]

  +---+---+---+---+---+---+---+---+
  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |  ← エントリインデックス
  +---+---+---+---+---+---+---+---+
        ^                   ^
        |                   |
     head_ptr            tail_ptr

  各エントリサイズ = msg_size * 4 bytes
  バッファサイズ = queue_depth * msg_size * 4 bytes

バッファ配置 (パラメータ):
  MQ_BUFFER_BASE: メッセージバッファ領域開始アドレス
  デフォルト: 各キューに256バイト割当
  最大バッファサイズ: MAX_QUEUES * 256 = 8KB
```

---

## 7. PMP設定管理

### 7.1 タスクごとのPMP設定保持

各タスクのTCBに以下のPMP関連フィールドを保持:

| フィールド | 説明 |
|---|---|
| `pmp_cfg` | pmpcfg0相当 (4エントリ分のPMP設定、各8ビット) |
| `pmp_addr0` | pmpaddr0 (保護領域0のアドレス) |
| `pmp_addr1` | pmpaddr1 (保護領域1のアドレス) |
| `pmp_addr2` | pmpaddr2 (保護領域2のアドレス) |
| `pmp_addr3` | pmpaddr3 (保護領域3のアドレス) |

#### PMPエントリ設定 (pmpcfg)

```
各PMPエントリの設定 (8ビット):
  [7]   : L (Lock) - ロックビット
  [6:5] : reserved
  [4:3] : A (Address Matching Mode)
           00: OFF (無効)
           01: TOR (Top of Range)
           10: NA4 (Naturally Aligned 4-byte)
           11: NAPOT (Naturally Aligned Power-of-Two)
  [2]   : X (Execute) - 実行許可
  [1]   : W (Write) - 書き込み許可
  [0]   : R (Read) - 読み出し許可

pmpcfg0[31:0] = {pmp3cfg[7:0], pmp2cfg[7:0], pmp1cfg[7:0], pmp0cfg[7:0]}
```

### 7.2 コンテキストスイッチ時のPMP切り替え

```
PMP切り替えシーケンス (コンテキストスイッチの一部):

退避フェーズ:
  1. 現CPUのpmpcfg0/pmpaddr0-3を読み出し
  2. 現タスクTCBのpmp_cfg/pmp_addr0-3に保存

復帰フェーズ:
  1. 次タスクTCBからpmp_cfg/pmp_addr0-3を読み出し
  2. CPUのpmpcfg0/pmpaddr0-3にロード
  3. TLBフラッシュ (PMPキャッシュがある場合)

サイクル数: 退避2サイクル + 復帰2サイクル = 計4サイクル (バースト転送時)
```

### 7.3 pmpcfg/pmpaddr CSRとの連携

```
PMPチェック回路 (CPU内、MEM段):

  メモリアクセス要求:
    access_addr[31:0]  // アクセスアドレス
    access_type[2:0]   // R/W/X

  PMPマッチング (優先度: PMP0 > PMP1 > PMP2 > PMP3):
    for (i = 0; i < 4; i++) begin
      if (pmp_match(access_addr, pmpaddr[i], pmpcfg[i].A)) begin
        if (check_permission(access_type, pmpcfg[i])) begin
          // アクセス許可
          break;
        end else begin
          // アクセス拒否 → アクセスフォルト例外
          raise_exception(access_type == X ? INST_ACCESS_FAULT :
                         access_type == R ? LOAD_ACCESS_FAULT :
                                            STORE_ACCESS_FAULT);
          break;
        end
      end
    end
    // マッチなし: M-modeではアクセス許可 (デフォルト)

RTOSとの連携:
  - タスク生成時: PMP設定を初期化 (タスクのスタック領域とコード領域を設定)
  - コンテキストスイッチ時: PMP設定を切り替え
  - タスク終了時: PMP設定をクリア
```

### 7.4 デフォルトPMP設定

```
タスク生成時のデフォルトPMP設定:

PMP0: コード領域 (R/X)
  pmpcfg: A=NAPOT, R=1, W=0, X=1
  pmpaddr: タスクのコード領域

PMP1: データ領域 (R/W)
  pmpcfg: A=NAPOT, R=1, W=1, X=0
  pmpaddr: タスクのスタック領域

PMP2: 共有領域 (R/W)
  pmpcfg: A=NAPOT, R=1, W=1, X=0
  pmpaddr: 共有データ領域 (メッセージバッファ等)

PMP3: ペリフェラル (R/W)
  pmpcfg: A=NAPOT, R=1, W=1, X=0
  pmpaddr: APBペリフェラル領域
```

---

## 付録A: RTOS BRAM使用量サマリ

| 領域 | サイズ | 説明 |
|---|---|---|
| TCBテーブル | 16 KB | 256タスク × 64バイト |
| レジスタ退避 | 32 KB | 256タスク × 128バイト |
| SCBテーブル | 512 B | 64セマフォ × 8バイト |
| MCBテーブル | 512 B | 64ミューテックス × 8バイト |
| QCBテーブル | 512 B | 32キュー × 16バイト |
| メッセージバッファ | 8 KB | 32キュー × 256バイト |
| Readyキュー管理 | 128 B | 16優先度 × 8バイト (head/tail) |
| **合計** | **約57 KB** | |

## 付録B: スケジューラ性能見積もり

| 操作 | 最悪サイクル数 | 説明 |
|---|---|---|
| 最高優先度検索 | 1 | CLZ回路 (組合せ論理) |
| 優先度比較・判定 | 2 | 比較 + 判定 |
| コンテキストスイッチ | 75 | 退避 + 復帰 (全レジスタ) |
| セマフォ取得 (非ブロック) | 4 | チェック + 取得 + 更新 |
| セマフォ取得 (ブロック) | 8 + 75 | ブロック + コンテキストスイッチ |
| ミューテックス取得 (非ブロック) | 4 | チェック + 取得 + 更新 |
| ミューテックス取得 (ブロック + 優先度継承) | 12 + 75 | 継承 + ブロック + スイッチ |
| メッセージ送信 (非ブロック) | 6 + N | チェック + エンキュー (Nワード) |
| タイマ割り込み処理 (スイッチなし) | 5 | 更新 + 比較 + ディスパッチ |
| タイマ割り込み処理 (スイッチあり) | 5 + 75 | 更新 + コンテキストスイッチ |
