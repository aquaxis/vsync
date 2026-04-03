# POSIX Syscall to Hardware Mapping Reference

## Document Information

| Item | Detail |
|------|--------|
| Document ID | POSIX-MAP-001 |
| Version | 1.0 |
| Date | 2026-02-21 |
| Project | VSync - RISC-V RV32IM with Hardware RTOS |
| Target Device | Xilinx Spartan UltraScale+ |
| Language | SystemVerilog (IEEE 1800-2017) |
| Related Modules | posix_hw_layer, hw_rtos, rv32im_core, clint, uart_apb, gpio_apb |

---

## Overview

This document specifies the complete mapping from POSIX-compatible syscall APIs to hardware operations in the VSync FPGA-based RISC-V RV32IM processor with integrated hardware RTOS. All POSIX operations are dispatched via the RISC-V ECALL instruction and executed entirely in hardware by the `posix_hw_layer` module in coordination with the `hw_rtos` engine and peripheral controllers.

The system uses a custom syscall numbering scheme (not Linux ABI) organized into categorical ranges. Syscall dispatch is synchronous from the CPU perspective: the pipeline stalls while the hardware POSIX layer processes the request, unless the operation triggers a context switch to another task.

---

## 1. Syscall Number Assignment Table

Syscall numbers are encoded as 8-bit values passed in register `a7` (x17). Numbers are organized by functional category with reserved gaps for future expansion.

### 1.1 Thread Management (0x00-0x0F)

| Syscall # | POSIX API | Arguments | Return Value | Description |
|-----------|-----------|-----------|--------------|-------------|
| 0x00 | pthread_create | a0=entry_addr, a1=stack_addr, a2=priority, a3=stack_size | a0=thread_id or -errno | Create new thread |
| 0x01 | pthread_exit | a0=exit_code | (no return) | Exit current thread |
| 0x02 | pthread_join | a0=thread_id | a0=exit_code or -errno | Wait for thread completion |
| 0x03 | pthread_detach | a0=thread_id | a0=0 or -errno | Detach thread |
| 0x04 | pthread_self | (none) | a0=current_thread_id | Get current thread ID |
| 0x05 | pthread_yield | (none) | a0=0 | Yield CPU |
| 0x06 | pthread_setschedparam | a0=thread_id, a1=priority | a0=0 or -errno | Set scheduling parameters |
| 0x07 | pthread_getschedparam | a0=thread_id | a0=priority or -errno | Get scheduling parameters |

### 1.2 Mutex Operations (0x10-0x1F)

| Syscall # | POSIX API | Arguments | Return Value | Description |
|-----------|-----------|-----------|--------------|-------------|
| 0x10 | pthread_mutex_init | a0=mutex_id_ptr, a1=attr | a0=0 or -errno | Initialize mutex |
| 0x11 | pthread_mutex_lock | a0=mutex_id | a0=0 or -errno | Lock mutex (blocking) |
| 0x12 | pthread_mutex_trylock | a0=mutex_id | a0=0 or -EBUSY | Try lock mutex (non-blocking) |
| 0x13 | pthread_mutex_unlock | a0=mutex_id | a0=0 or -errno | Unlock mutex |
| 0x14 | pthread_mutex_destroy | a0=mutex_id | a0=0 or -errno | Destroy mutex |

### 1.3 Semaphore Operations (0x20-0x2F)

| Syscall # | POSIX API | Arguments | Return Value | Description |
|-----------|-----------|-----------|--------------|-------------|
| 0x20 | sem_init | a0=sem_id_ptr, a1=initial_value, a2=max_value | a0=0 or -errno | Initialize semaphore |
| 0x21 | sem_wait | a0=sem_id | a0=0 or -errno | Wait (decrement) semaphore |
| 0x22 | sem_trywait | a0=sem_id | a0=0 or -EAGAIN | Try wait semaphore (non-blocking) |
| 0x23 | sem_timedwait | a0=sem_id, a1=timeout_ns | a0=0 or -ETIMEDOUT | Timed wait semaphore |
| 0x24 | sem_post | a0=sem_id | a0=0 or -errno | Post (increment) semaphore |
| 0x25 | sem_getvalue | a0=sem_id | a0=value or -errno | Get semaphore value |
| 0x26 | sem_destroy | a0=sem_id | a0=0 or -errno | Destroy semaphore |

### 1.4 Message Queue Operations (0x30-0x3F)

| Syscall # | POSIX API | Arguments | Return Value | Description |
|-----------|-----------|-----------|--------------|-------------|
| 0x30 | mq_open | a0=queue_depth, a1=msg_size | a0=mq_id or -errno | Create/open message queue |
| 0x31 | mq_send | a0=mq_id, a1=msg_data_addr, a2=msg_len | a0=0 or -errno | Send message |
| 0x32 | mq_receive | a0=mq_id, a1=buf_addr, a2=buf_len | a0=msg_len or -errno | Receive message |
| 0x33 | mq_close | a0=mq_id | a0=0 or -errno | Close message queue |
| 0x34 | mq_timedreceive | a0=mq_id, a1=buf_addr, a2=buf_len, a3=timeout_ns | a0=msg_len or -ETIMEDOUT | Timed receive |
| 0x35 | mq_timedsend | a0=mq_id, a1=msg_data_addr, a2=msg_len, a3=timeout_ns | a0=0 or -ETIMEDOUT | Timed send |

### 1.5 Timer/Clock Operations (0x40-0x4F)

| Syscall # | POSIX API | Arguments | Return Value | Description |
|-----------|-----------|-----------|--------------|-------------|
| 0x40 | clock_gettime | a0=clock_id | a0=time_lo, a1=time_hi | Get current time |
| 0x41 | clock_settime | a0=clock_id, a1=time_lo, a2=time_hi | a0=0 or -errno | Set time |
| 0x42 | nanosleep | a0=duration_lo, a1=duration_hi | a0=0 or -errno | Sleep for duration |
| 0x43 | timer_create | a0=clock_id, a1=callback_addr | a0=timer_id or -errno | Create timer |
| 0x44 | timer_settime | a0=timer_id, a1=interval_lo, a2=interval_hi | a0=0 or -errno | Set timer interval |
| 0x45 | timer_delete | a0=timer_id | a0=0 or -errno | Delete timer |
| 0x46 | timer_gettime | a0=timer_id | a0=remaining_lo, a1=remaining_hi | Get remaining time |

### 1.6 File I/O Operations (0x50-0x5F)

| Syscall # | POSIX API | Arguments | Return Value | Description |
|-----------|-----------|-----------|--------------|-------------|
| 0x50 | open | a0=device_type, a1=flags | a0=fd or -errno | Open file descriptor |
| 0x51 | close | a0=fd | a0=0 or -errno | Close file descriptor |
| 0x52 | read | a0=fd, a1=buf_addr, a2=count | a0=bytes_read or -errno | Read from fd |
| 0x53 | write | a0=fd, a1=buf_addr, a2=count | a0=bytes_written or -errno | Write to fd |
| 0x54 | ioctl | a0=fd, a1=request, a2=arg | a0=0 or -errno | Device control |
| 0x55 | lseek | a0=fd, a1=offset, a2=whence | a0=position or -errno | Seek (limited support) |

### 1.7 Signal Operations (0x60-0x6F)

| Syscall # | POSIX API | Arguments | Return Value | Description |
|-----------|-----------|-----------|--------------|-------------|
| 0x60 | kill | a0=thread_id, a1=signal_num | a0=0 or -errno | Send signal to thread |
| 0x61 | sigaction | a0=signal_num, a1=handler_addr | a0=0 or -errno | Register signal handler |
| 0x62 | sigprocmask | a0=how, a1=set | a0=old_set or -errno | Set signal mask |
| 0x63 | sigwait | a0=set | a0=signal_num or -errno | Wait for signal |
| 0x64 | raise | a0=signal_num | a0=0 or -errno | Raise signal in current thread |

### 1.8 System Operations (0x70-0x7F)

| Syscall # | POSIX API | Arguments | Return Value | Description |
|-----------|-----------|-----------|--------------|-------------|
| 0x70 | sysconf | a0=name | a0=value or -errno | Get system configuration |
| 0x71 | sched_get_priority_max | (none) | a0=max_priority | Get max priority value |
| 0x72 | sched_get_priority_min | (none) | a0=min_priority | Get min priority value |
| 0x73 | sbrk | a0=increment | a0=prev_brk or -errno | Adjust program break (heap) |

---

## 2. Detailed POSIX API to Hardware Operation Mapping

This section describes the precise hardware flow for every syscall, including the signals exchanged between `posix_hw_layer`, `hw_rtos`, the CPU pipeline, and peripheral controllers. Signal names correspond to the module interconnection defined in the architecture block diagram (ARCH-BD-001).

### 2.1 Thread Management

#### 2.1.1 pthread_create (0x00) -- Hardware Task Creation

```
Syscall Flow:
1. CPU executes ECALL with a7=0x00
2. posix_hw_layer receives: entry_addr(a0), stack_addr(a1), priority(a2), stack_size(a3)
3. posix_hw_layer asserts rtos_task_create=1, rtos_op_data={entry_addr, stack_addr, priority, stack_size}
4. hw_rtos allocates TCB:
   a. Scan TCB table valid bits [0:15] to find first free slot (valid==0)
   b. If no free slot found: return -ENOMEM (0xFFFFFFF4) via rtos_op_result
   c. Initialize TCB entry:
      - tcb[slot].valid     = 1
      - tcb[slot].task_id   = slot (4-bit)
      - tcb[slot].state     = TASK_READY (3'b000)
      - tcb[slot].pc        = entry_addr
      - tcb[slot].sp        = stack_addr + stack_size (top of stack, grows downward)
      - tcb[slot].priority  = priority[3:0]
      - tcb[slot].time_slice = default_time_slice
   d. Initialize register save area for the new task:
      - x0 = 0 (hardwired)
      - x2 (sp) = stack_addr + stack_size
      - x10 (a0) = 0 (thread argument, can be extended)
      - All other registers = 0
   e. Add task to the ready queue at the appropriate priority level
5. hw_rtos asserts rtos_op_done=1, rtos_op_result=task_id (success)
6. posix_hw_layer sets syscall_ret=task_id, asserts syscall_done=1
7. CPU resumes with a0=task_id (instruction after ECALL)
8. If new task priority > current task priority:
   a. hw_rtos asserts ctx_switch_req=1
   b. CPU saves current registers via save_regs[31:0][0:31] and save_pc[31:0]
   c. hw_rtos stores context into current TCB, sets current task state=TASK_READY
   d. hw_rtos loads new task context into restore_regs and restore_pc
   e. CPU acknowledges via ctx_switch_ack=1, resumes at new task's PC
```

**Hardware registers involved:**
- TCB memory: 16 entries, each containing {task_id[3:0], priority[3:0], state[2:0], pc[31:0], sp[31:0], time_slice[15:0], valid[0]}
- Register save area: 16 x 32 x 32-bit SRAM (16 tasks, 32 registers each)
- Ready queue: priority bitmap (16-bit) + per-priority FIFO pointers

**Error conditions:**
- No free TCB slot: return -ENOMEM (0xFFFFFFF4)
- Invalid priority (>15): return -EINVAL (0xFFFFFFEA)
- Invalid stack_addr (null or misaligned): return -EINVAL (0xFFFFFFEA)
- stack_size too small (<64 bytes): return -EINVAL (0xFFFFFFEA)

**Cycle count:** 10-20 cycles (TCB scan + initialization + optional context switch)

#### 2.1.2 pthread_exit (0x01) -- Hardware Task Termination

```
Syscall Flow:
1. CPU executes ECALL with a7=0x01
2. posix_hw_layer receives: exit_code(a0)
3. posix_hw_layer asserts rtos_task_exit=1, rtos_op_data=exit_code
4. hw_rtos terminates current task:
   a. Read current_task_id from scheduler
   b. Store exit_code in TCB exit_code field
   c. Set tcb[current_task_id].state = TASK_DORMANT (3'b100)
   d. Release mutex/semaphore resources owned by this task:
      - Scan mutex owner fields; for any mutex owned by this task, release it
      - Wake any task blocked waiting to join this task (see pthread_join)
   e. If any task is blocked in pthread_join on this task_id:
      - Set the joining task's state to TASK_READY
      - Set the joining task's saved a0 register to exit_code
   f. Remove task from scheduling queues
5. hw_rtos triggers mandatory context switch:
   a. Select next highest-priority TASK_READY task via priority scheduler
   b. Load new task context (restore_regs, restore_pc)
   c. Assert ctx_switch_req=1
   d. CPU acknowledges, resumes at new task's PC
6. The terminated task's syscall never returns (no syscall_done for the exiting task)
```

**Hardware registers involved:**
- Current task TCB entry
- Mutex owner table (8 entries, scanned for cleanup)
- Join wait table (tracks which task is waiting on which task_id)
- Ready queue priority bitmap

**Error conditions:**
- This syscall cannot fail from the caller's perspective (task is always terminated)
- If no other TASK_READY exists, the idle task (task_id=0, always READY) is scheduled

**Cycle count:** 15-50 cycles (resource cleanup scan + context switch)

#### 2.1.3 pthread_join (0x02) -- Hardware Task Wait

```
Syscall Flow:
1. CPU executes ECALL with a7=0x02
2. posix_hw_layer receives: target_thread_id(a0)
3. posix_hw_layer validates target_thread_id:
   a. If target_thread_id >= MAX_TASKS(16): return -ESRCH (0xFFFFFFFD)
   b. If tcb[target_thread_id].valid == 0: return -ESRCH (0xFFFFFFFD)
   c. If target_thread_id == current_task_id: return -EINVAL (0xFFFFFFEA) (deadlock)
4. Check target task state:
   a. If tcb[target_thread_id].state == TASK_DORMANT:
      - Target already exited: return exit_code immediately
      - Set tcb[target_thread_id].valid = 0 (free the TCB)
      - syscall_ret = exit_code, syscall_done=1
   b. If target task is still active (READY/RUNNING/BLOCKED):
      - Record join: join_table[current_task_id] = target_thread_id
      - Set current task state = TASK_BLOCKED
      - Trigger context switch to next ready task
      - When target task eventually calls pthread_exit, the blocked
        joining task is woken with exit_code placed in its saved a0
```

**Hardware registers involved:**
- Join wait table: 16 entries, each mapping a blocked task_id to the target task_id it waits on
- TCB state fields for both current and target task
- Exit code storage in TCB

**Error conditions:**
- Invalid thread_id (>=16 or not valid): return -ESRCH (0xFFFFFFFD)
- Joining self: return -EINVAL (0xFFFFFFEA)
- Another task already joining the same target: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3-5 cycles (non-blocking, target already exited), 8-15 cycles + context switch (blocking)

#### 2.1.4 pthread_detach (0x03) -- Thread Detach

```
Syscall Flow:
1. CPU executes ECALL with a7=0x03
2. posix_hw_layer receives: thread_id(a0)
3. Validate thread_id:
   a. If thread_id >= MAX_TASKS or tcb[thread_id].valid == 0: return -ESRCH
4. Set tcb[thread_id].detached = 1 (flag in TCB)
5. If tcb[thread_id].state == TASK_DORMANT and detached flag is set:
   a. Immediately free TCB: tcb[thread_id].valid = 0
6. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Error conditions:**
- Invalid thread_id: return -ESRCH (0xFFFFFFFD)
- Thread already detached: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3-5 cycles (non-blocking)

#### 2.1.5 pthread_self (0x04) -- Get Current Thread ID

```
Syscall Flow:
1. CPU executes ECALL with a7=0x04
2. posix_hw_layer reads current_task_id[3:0] from hw_rtos
3. posix_hw_layer sets syscall_ret = {28'b0, current_task_id}, asserts syscall_done=1
4. CPU resumes with a0=current_task_id
```

**Hardware registers involved:**
- current_task_id[3:0]: maintained by hw_rtos scheduler, always reflects the running task

**Error conditions:** None (this syscall always succeeds)

**Cycle count:** 2 cycles (register read + return)

#### 2.1.6 pthread_yield (0x05) -- Voluntary CPU Yield

```
Syscall Flow:
1. CPU executes ECALL with a7=0x05
2. posix_hw_layer asserts rtos_task_yield=1
3. hw_rtos processes yield:
   a. Move current task to the back of its priority-level ready queue
   b. Set current task state = TASK_READY
   c. Run scheduler: select next task from highest-priority non-empty ready queue
   d. If only the current task is at its priority level:
      - Reschedule the same task (no context switch needed)
      - rtos_op_result=0, rtos_op_done=1
   e. Otherwise:
      - Trigger context switch to the newly selected task
      - Save current task context, load new task context
4. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Hardware registers involved:**
- Ready queue per-priority FIFO: current task moved to tail
- TCB state field: RUNNING -> READY -> RUNNING (for new task)
- Context switch engine: save/restore register file

**Error conditions:** None (yield always succeeds, returns 0)

**Cycle count:** 5 cycles (no context switch), 15-25 cycles (with context switch)

#### 2.1.7 pthread_setschedparam (0x06) -- Set Scheduling Priority

```
Syscall Flow:
1. CPU executes ECALL with a7=0x06
2. posix_hw_layer receives: thread_id(a0), new_priority(a1)
3. Validate parameters:
   a. thread_id >= MAX_TASKS or tcb[thread_id].valid == 0: return -ESRCH
   b. new_priority > 15: return -EINVAL
4. hw_rtos updates scheduling:
   a. Remove task from its current priority queue
   b. Set tcb[thread_id].priority = new_priority[3:0]
   c. If task is in TASK_READY state, re-insert into new priority queue
   d. If task is currently RUNNING and new_priority < any READY task's priority:
      - Trigger preemption: context switch to the higher-priority ready task
5. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Error conditions:**
- Invalid thread_id: return -ESRCH (0xFFFFFFFD)
- Invalid priority (>15): return -EINVAL (0xFFFFFFEA)

**Cycle count:** 5-10 cycles (without preemption), 15-25 cycles (with preemption)

#### 2.1.8 pthread_getschedparam (0x07) -- Get Scheduling Priority

```
Syscall Flow:
1. CPU executes ECALL with a7=0x07
2. posix_hw_layer receives: thread_id(a0)
3. Validate thread_id:
   a. thread_id >= MAX_TASKS or tcb[thread_id].valid == 0: return -ESRCH
4. Read tcb[thread_id].priority
5. posix_hw_layer sets syscall_ret = {28'b0, priority[3:0]}, asserts syscall_done=1
```

**Error conditions:**
- Invalid thread_id: return -ESRCH (0xFFFFFFFD)

**Cycle count:** 3 cycles (TCB read + return)

---

### 2.2 Mutex Operations

#### 2.2.1 pthread_mutex_init (0x10) -- Hardware Mutex Initialization

```
Syscall Flow:
1. CPU executes ECALL with a7=0x10
2. posix_hw_layer receives: mutex_id_ptr(a0), attr(a1)
3. posix_hw_layer scans hw_rtos mutex table for free slot:
   a. Mutex table has 8 entries (Mutex[0-7])
   b. Find first entry where mutex[i].valid == 0
   c. If no free slot: return -ENOMEM
4. Initialize mutex entry:
   a. mutex[slot].valid   = 1
   b. mutex[slot].locked  = 0
   c. mutex[slot].owner   = 4'hF (no owner)
   d. mutex[slot].wait_list = 16'h0000 (no waiters)
   e. mutex[slot].attr    = attr[7:0] (protocol bits: normal, errorcheck, recursive)
   f. mutex[slot].lock_count = 0 (for recursive mutexes)
   g. mutex[slot].ceiling_priority = attr[11:8] (for priority ceiling protocol)
5. Write mutex_id (slot number) to memory at mutex_id_ptr via AXI4 write:
   a. posix_hw_layer initiates AXI4 write transaction: AWADDR=mutex_id_ptr, WDATA=slot
   b. Wait for BVALID/BREADY handshake
6. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Hardware registers involved:**
- Mutex table: 8 entries x {valid[0], locked[0], owner[3:0], wait_list[15:0], attr[7:0], lock_count[3:0], ceiling_priority[3:0]}
- AXI4 master interface for writing mutex_id back to user memory

**Error conditions:**
- No free mutex slot: return -ENOMEM (0xFFFFFFF4)
- Invalid mutex_id_ptr (null): return -EINVAL (0xFFFFFFEA)

**Cycle count:** 5-10 cycles (scan + init + AXI4 write)

#### 2.2.2 pthread_mutex_lock (0x11) -- Hardware Mutex Acquire with Priority Inheritance

```
Syscall Flow:
1. CPU executes ECALL with a7=0x11
2. posix_hw_layer receives: mutex_id(a0)
3. Validate mutex_id:
   a. mutex_id >= 8 or mutex[mutex_id].valid == 0: return -EINVAL
4. posix_hw_layer sends rtos_mutex_op=2'b01 (LOCK), rtos_op_data=mutex_id
5. hw_rtos checks mutex state:

   Case A - Mutex is unlocked (mutex[id].locked == 0):
   a. Set mutex[id].locked = 1
   b. Set mutex[id].owner = current_task_id
   c. Set mutex[id].lock_count = 1
   d. rtos_op_result = 0 (success)
   e. rtos_op_done = 1
   f. posix_hw_layer sets syscall_ret=0, syscall_done=1
   g. CPU resumes immediately

   Case B - Mutex is locked by another task:
   a. Add current_task_id to mutex[id].wait_list bitmap
   b. Set tcb[current_task_id].state = TASK_BLOCKED
   c. Priority Inheritance Protocol:
      - If tcb[current_task_id].priority > tcb[mutex[id].owner].priority:
        * Save original priority: tcb[owner].saved_priority = tcb[owner].priority
        * Boost owner priority: tcb[owner].priority = tcb[current_task_id].priority
        * If owner is in a ready queue, move it to the higher-priority queue
   d. Trigger context switch to next ready task
   e. When mutex is eventually unlocked, this task is woken and receives a0=0

   Case C - Mutex is locked by current task (recursive):
   a. If attr indicates RECURSIVE: increment lock_count, return 0
   b. If attr indicates ERRORCHECK: return -EBUSY
   c. If attr indicates NORMAL: deadlock (implementation: return -EBUSY)
```

**Hardware registers involved:**
- Mutex entry: locked, owner, wait_list bitmap, attr, lock_count
- TCB priority fields (for priority inheritance)
- Ready queue (for priority queue re-insertion during inheritance)

**Error conditions:**
- Invalid mutex_id: return -EINVAL (0xFFFFFFEA)
- Deadlock detection (self-lock on non-recursive): return -EBUSY (0xFFFFFFF0)

**Cycle count:** 3-5 cycles (unlocked), 10-25 cycles (blocked + context switch + priority inheritance)

#### 2.2.3 pthread_mutex_trylock (0x12) -- Non-blocking Mutex Acquire

```
Syscall Flow:
1. CPU executes ECALL with a7=0x12
2. posix_hw_layer receives: mutex_id(a0)
3. Validate mutex_id:
   a. mutex_id >= 8 or mutex[mutex_id].valid == 0: return -EINVAL
4. hw_rtos checks mutex state atomically:
   a. If mutex[id].locked == 0:
      - Set mutex[id].locked = 1, owner = current_task_id, lock_count = 1
      - Return 0 (success)
   b. If mutex[id].locked == 1 and owner == current_task_id and attr==RECURSIVE:
      - Increment lock_count
      - Return 0
   c. Otherwise:
      - Return -EBUSY (0xFFFFFFF0)
5. No blocking, no context switch. CPU resumes immediately.
```

**Error conditions:**
- Invalid mutex_id: return -EINVAL (0xFFFFFFEA)
- Mutex already locked: return -EBUSY (0xFFFFFFF0)

**Cycle count:** 3-4 cycles (always non-blocking)

#### 2.2.4 pthread_mutex_unlock (0x13) -- Hardware Mutex Release with Priority Restoration

```
Syscall Flow:
1. CPU executes ECALL with a7=0x13
2. posix_hw_layer receives: mutex_id(a0)
3. Validate:
   a. mutex_id >= 8 or mutex[mutex_id].valid == 0: return -EINVAL
   b. mutex[mutex_id].owner != current_task_id: return -EPERM (0xFFFFFFFF)
4. posix_hw_layer sends rtos_mutex_op=2'b10 (UNLOCK), rtos_op_data=mutex_id
5. hw_rtos processes unlock:
   a. If attr==RECURSIVE and lock_count > 1:
      - Decrement lock_count
      - Return 0 (mutex stays locked)
   b. Priority Restoration:
      - If tcb[current_task_id].priority != tcb[current_task_id].saved_priority:
        * Restore: tcb[current_task_id].priority = tcb[current_task_id].saved_priority
        * Move current task in ready queue if needed
   c. Check wait_list bitmap for waiters:
      - If wait_list == 0: set mutex[id].locked=0, owner=4'hF, return 0
      - If wait_list != 0:
        * Select highest-priority waiter from wait_list bitmap:
          Find bit position with highest tcb[bit].priority
        * Clear that bit from wait_list
        * Transfer mutex ownership: mutex[id].owner = waiter_task_id
        * Set tcb[waiter].state = TASK_READY
        * Set waiter's saved a0 register = 0 (successful lock return)
        * Add waiter to ready queue
   d. Check if woken task has higher priority than current task:
      - If yes: trigger preemption (context switch)
      - If no: current task continues
6. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Hardware registers involved:**
- Mutex entry: locked, owner, wait_list, lock_count
- TCB priority and saved_priority fields
- Ready queue priority bitmap and FIFOs
- Waiter selection logic: priority-based scan of wait_list bitmap

**Error conditions:**
- Invalid mutex_id: return -EINVAL (0xFFFFFFEA)
- Caller is not the owner: return -EPERM (0xFFFFFFFF)

**Cycle count:** 5-8 cycles (no waiters), 10-25 cycles (wake waiter + optional preemption)

#### 2.2.5 pthread_mutex_destroy (0x14) -- Mutex Destruction

```
Syscall Flow:
1. CPU executes ECALL with a7=0x14
2. posix_hw_layer receives: mutex_id(a0)
3. Validate:
   a. mutex_id >= 8 or mutex[mutex_id].valid == 0: return -EINVAL
   b. mutex[mutex_id].locked == 1: return -EBUSY (cannot destroy locked mutex)
   c. mutex[mutex_id].wait_list != 0: return -EBUSY (cannot destroy with waiters)
4. Set mutex[mutex_id].valid = 0 (free the slot)
5. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Error conditions:**
- Invalid mutex_id: return -EINVAL (0xFFFFFFEA)
- Mutex locked or has waiters: return -EBUSY (0xFFFFFFF0)

**Cycle count:** 3-4 cycles

---

### 2.3 Semaphore Operations

#### 2.3.1 sem_init (0x20) -- Hardware Semaphore Initialization

```
Syscall Flow:
1. CPU executes ECALL with a7=0x20
2. posix_hw_layer receives: sem_id_ptr(a0), initial_value(a1), max_value(a2)
3. Scan hw_rtos semaphore table for free slot:
   a. Semaphore table has 8 entries (Semaphore[0-7])
   b. Find first entry where sem[i].valid == 0
   c. If no free slot: return -ENOMEM
4. Validate parameters:
   a. If initial_value > max_value: return -EINVAL
   b. If max_value == 0: return -EINVAL
5. Initialize semaphore entry:
   a. sem[slot].valid     = 1
   b. sem[slot].count     = initial_value[15:0]
   c. sem[slot].max_count = max_value[15:0]
   d. sem[slot].wait_list = 16'h0000
6. Write sem_id (slot number) to memory at sem_id_ptr via AXI4 write
7. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Hardware registers involved:**
- Semaphore table: 8 entries x {valid[0], count[15:0], max_count[15:0], wait_list[15:0]}

**Error conditions:**
- No free semaphore slot: return -ENOMEM (0xFFFFFFF4)
- initial_value > max_value: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 5-10 cycles

#### 2.3.2 sem_wait (0x21) -- Hardware Semaphore Acquire (Blocking)

```
Syscall Flow:
1. CPU executes ECALL with a7=0x21
2. posix_hw_layer receives: sem_id(a0)
3. Validate: sem_id >= 8 or sem[sem_id].valid == 0: return -EINVAL
4. posix_hw_layer sends rtos_sem_op=2'b01 (WAIT), rtos_op_data=sem_id
5. hw_rtos checks semaphore count atomically:

   Case A - Count > 0 (resource available):
   a. Decrement: sem[id].count = sem[id].count - 1
   b. rtos_op_result = 0 (success)
   c. rtos_op_done = 1
   d. posix_hw_layer sets syscall_ret=0, syscall_done=1
   e. CPU resumes immediately (non-blocking path)

   Case B - Count == 0 (resource unavailable, must block):
   a. Add current_task_id to sem[id].wait_list bitmap
   b. Set tcb[current_task_id].state = TASK_BLOCKED
   c. Record blocking reason: tcb[current_task_id].block_resource = {SEM, sem_id}
   d. Trigger context switch to next ready task:
      - Save context (save_regs, save_pc)
      - Select next highest-priority READY task
      - Load new task context (restore_regs, restore_pc)
   e. When sem_post eventually increments the count, this task will be woken:
      - Set state = TASK_READY
      - Set saved a0 = 0 (successful acquisition)
      - Insert into ready queue
```

**Hardware registers involved:**
- Semaphore count register (16-bit decrement)
- Wait list bitmap (16-bit, one bit per task)
- TCB state and block_resource fields
- Context switch engine

**Error conditions:**
- Invalid sem_id: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3-4 cycles (count>0), 10-25 cycles (count==0, blocking + context switch)

#### 2.3.3 sem_trywait (0x22) -- Non-blocking Semaphore Acquire

```
Syscall Flow:
1. CPU executes ECALL with a7=0x22
2. posix_hw_layer receives: sem_id(a0)
3. Validate: sem_id >= 8 or sem[sem_id].valid == 0: return -EINVAL
4. Check semaphore count:
   a. If sem[id].count > 0: decrement count, return 0
   b. If sem[id].count == 0: return -EAGAIN (0xFFFFFFF5)
5. No blocking, no context switch.
```

**Error conditions:**
- Invalid sem_id: return -EINVAL (0xFFFFFFEA)
- Semaphore count is zero: return -EAGAIN (0xFFFFFFF5)

**Cycle count:** 3-4 cycles (always non-blocking)

#### 2.3.4 sem_timedwait (0x23) -- Timed Semaphore Acquire

```
Syscall Flow:
1. CPU executes ECALL with a7=0x23
2. posix_hw_layer receives: sem_id(a0), timeout_ns(a1)
3. Validate: sem_id >= 8 or sem[sem_id].valid == 0: return -EINVAL
4. Check semaphore count:
   a. If sem[id].count > 0: decrement count, return 0 (immediate success)
   b. If sem[id].count == 0:
      - Convert timeout_ns to timer ticks: ticks = timeout_ns / tick_period_ns
      - Read current mtime from CLINT (via direct register read, not APB)
      - Compute deadline: deadline = mtime + ticks
      - Store deadline in tcb[current_task_id].wakeup_time
      - Add current_task_id to sem[id].wait_list
      - Add current_task_id to the timer wakeup list in hw_rtos
      - Set tcb[current_task_id].state = TASK_BLOCKED
      - Trigger context switch
5. On wakeup:
   a. If woken by sem_post: return 0 (success)
   b. If woken by timer expiry: remove from sem wait_list, return -ETIMEDOUT
```

**Hardware registers involved:**
- Semaphore count and wait_list
- CLINT mtime register (read directly by hw_rtos for time reference)
- TCB wakeup_time field (64-bit)
- Timer wakeup list (sorted by deadline)

**Error conditions:**
- Invalid sem_id: return -EINVAL (0xFFFFFFEA)
- Timeout expired: return -ETIMEDOUT (0xFFFFFF92)

**Cycle count:** 3-4 cycles (immediate), 12-30 cycles (blocking with timer setup)

#### 2.3.5 sem_post (0x24) -- Hardware Semaphore Release

```
Syscall Flow:
1. CPU executes ECALL with a7=0x24
2. posix_hw_layer receives: sem_id(a0)
3. Validate: sem_id >= 8 or sem[sem_id].valid == 0: return -EINVAL
4. posix_hw_layer sends rtos_sem_op=2'b10 (POST), rtos_op_data=sem_id
5. hw_rtos processes post:

   Case A - No waiters (sem[id].wait_list == 0):
   a. If sem[id].count < sem[id].max_count:
      - Increment: sem[id].count = sem[id].count + 1
      - Return 0
   b. If sem[id].count >= sem[id].max_count:
      - Return -EINVAL (overflow)

   Case B - Waiters present (sem[id].wait_list != 0):
   a. Select highest-priority waiter from wait_list bitmap
   b. Clear waiter bit from wait_list
   c. Do NOT increment count (resource is transferred directly to waiter)
   d. Remove waiter from timer wakeup list if it had a timeout (sem_timedwait)
   e. Set tcb[waiter].state = TASK_READY
   f. Set waiter's saved a0 = 0 (successful sem_wait return)
   g. Add waiter to ready queue
   h. If waiter priority > current task priority: trigger preemption
6. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Hardware registers involved:**
- Semaphore count (16-bit increment or transfer)
- Wait list bitmap (16-bit scan for highest priority)
- TCB state fields for woken task
- Ready queue and priority bitmap

**Error conditions:**
- Invalid sem_id: return -EINVAL (0xFFFFFFEA)
- Semaphore overflow (count >= max_count with no waiters): return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3-5 cycles (no waiters), 8-20 cycles (wake waiter + optional preemption)

#### 2.3.6 sem_getvalue (0x25) -- Read Semaphore Count

```
Syscall Flow:
1. CPU executes ECALL with a7=0x25
2. posix_hw_layer receives: sem_id(a0)
3. Validate: sem_id >= 8 or sem[sem_id].valid == 0: return -EINVAL
4. Read sem[sem_id].count
5. posix_hw_layer sets syscall_ret = count, asserts syscall_done=1
```

**Error conditions:**
- Invalid sem_id: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3 cycles

#### 2.3.7 sem_destroy (0x26) -- Semaphore Destruction

```
Syscall Flow:
1. CPU executes ECALL with a7=0x26
2. posix_hw_layer receives: sem_id(a0)
3. Validate:
   a. sem_id >= 8 or sem[sem_id].valid == 0: return -EINVAL
   b. sem[sem_id].wait_list != 0: return -EBUSY (cannot destroy with waiters)
4. Set sem[sem_id].valid = 0
5. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Error conditions:**
- Invalid sem_id: return -EINVAL (0xFFFFFFEA)
- Waiters present: return -EBUSY (0xFFFFFFF0)

**Cycle count:** 3-4 cycles

---

### 2.4 Message Queue Operations

#### 2.4.1 mq_open (0x30) -- Create Message Queue

```
Syscall Flow:
1. CPU executes ECALL with a7=0x30
2. posix_hw_layer receives: queue_depth(a0), msg_size(a1)
3. Scan hw_rtos message queue table for free slot:
   a. Message queue table has 4 entries (MsgQ[0-3])
   b. Find first entry where msgq[i].valid == 0
   c. If no free slot: return -ENOMEM
4. Validate parameters:
   a. queue_depth must be 1-16 (power of 2 preferred): if 0 or >16, return -EINVAL
   b. msg_size must be 1-64 bytes: if 0 or >64, return -EINVAL
5. Initialize message queue:
   a. msgq[slot].valid      = 1
   b. msgq[slot].depth      = queue_depth
   c. msgq[slot].msg_size   = msg_size
   d. msgq[slot].count      = 0
   e. msgq[slot].head_ptr   = 0
   f. msgq[slot].tail_ptr   = 0
   g. msgq[slot].send_wait  = 16'h0000 (no senders blocked)
   h. msgq[slot].recv_wait  = 16'h0000 (no receivers blocked)
   i. Clear message buffer SRAM region for this queue
6. posix_hw_layer sets syscall_ret=slot (mq_id), asserts syscall_done=1
```

**Hardware registers involved:**
- Message queue control table: 4 entries x {valid, depth, msg_size, count, head_ptr, tail_ptr, send_wait, recv_wait}
- Message buffer SRAM: 4 queues x 16 slots x 64 bytes = 4KB dedicated SRAM

**Error conditions:**
- No free queue slot: return -ENOMEM (0xFFFFFFF4)
- Invalid depth or msg_size: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 8-15 cycles (init + SRAM clear)

#### 2.4.2 mq_send (0x31) -- Send Message (Blocking)

```
Syscall Flow:
1. CPU executes ECALL with a7=0x31
2. posix_hw_layer receives: mq_id(a0), msg_data_addr(a1), msg_len(a2)
3. Validate:
   a. mq_id >= 4 or msgq[mq_id].valid == 0: return -EINVAL
   b. msg_len > msgq[mq_id].msg_size: return -EINVAL
4. Check queue state:

   Case A - Queue not full (count < depth):
   a. Copy message from msg_data_addr to queue buffer SRAM:
      - posix_hw_layer initiates AXI4 burst read from msg_data_addr
      - Read msg_len bytes into internal buffer
      - Write bytes to msgq SRAM at tail_ptr position
   b. Store msg_len in message header (for variable-length messages)
   c. Advance tail_ptr = (tail_ptr + 1) % depth
   d. Increment count
   e. If recv_wait != 0 (receivers waiting):
      - Wake highest-priority waiting receiver
      - Transfer message directly (copy to receiver's buffer)
      - Decrement count (message was consumed immediately)
   f. Return 0

   Case B - Queue full (count == depth):
   a. Add current_task_id to msgq[mq_id].send_wait
   b. Store msg_data_addr and msg_len in TCB scratch area
   c. Set tcb[current_task_id].state = TASK_BLOCKED
   d. Trigger context switch
   e. When space becomes available, this task is woken:
      - Message is copied from scratch area to queue
      - Return 0
```

**Hardware registers involved:**
- Message queue control registers
- Message buffer SRAM (4KB)
- AXI4 master interface for reading user-space message data
- TCB scratch fields for blocked sender's message info

**Error conditions:**
- Invalid mq_id: return -EINVAL (0xFFFFFFEA)
- msg_len exceeds configured msg_size: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 10-30 cycles (non-blocking, depends on msg_len), 15-40 cycles (blocking)

#### 2.4.3 mq_receive (0x32) -- Receive Message (Blocking)

```
Syscall Flow:
1. CPU executes ECALL with a7=0x32
2. posix_hw_layer receives: mq_id(a0), buf_addr(a1), buf_len(a2)
3. Validate:
   a. mq_id >= 4 or msgq[mq_id].valid == 0: return -EINVAL
   b. buf_len < msgq[mq_id].msg_size: return -EINVAL (buffer too small)
4. Check queue state:

   Case A - Queue not empty (count > 0):
   a. Read message from queue buffer SRAM at head_ptr position
   b. Read stored msg_len from message header
   c. Copy msg_len bytes to buf_addr via AXI4 burst write:
      - posix_hw_layer initiates AXI4 write transactions
      - AWADDR=buf_addr, WDATA=message bytes, burst length=ceil(msg_len/4)
   d. Advance head_ptr = (head_ptr + 1) % depth
   e. Decrement count
   f. If send_wait != 0 (senders blocked):
      - Wake highest-priority blocked sender
      - Sender's message is copied into the now-free slot
   g. Return msg_len (actual bytes received)

   Case B - Queue empty (count == 0):
   a. Add current_task_id to msgq[mq_id].recv_wait
   b. Store buf_addr and buf_len in TCB scratch area
   c. Set tcb[current_task_id].state = TASK_BLOCKED
   d. Trigger context switch
   e. When message arrives (via mq_send), this task is woken:
      - Message is copied directly to buf_addr
      - Saved a0 = msg_len
```

**Error conditions:**
- Invalid mq_id: return -EINVAL (0xFFFFFFEA)
- Buffer too small: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 10-30 cycles (non-blocking), 15-40 cycles (blocking)

#### 2.4.4 mq_close (0x33) -- Close Message Queue

```
Syscall Flow:
1. CPU executes ECALL with a7=0x33
2. posix_hw_layer receives: mq_id(a0)
3. Validate: mq_id >= 4 or msgq[mq_id].valid == 0: return -EINVAL
4. Check: if send_wait != 0 or recv_wait != 0:
   a. Wake all blocked tasks with return value -EINVAL
   b. Clear wait lists
5. Set msgq[mq_id].valid = 0
6. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Error conditions:**
- Invalid mq_id: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 5-15 cycles (wake blocked tasks if any)

#### 2.4.5 mq_timedreceive (0x34) -- Timed Message Receive

```
Syscall Flow:
1. CPU executes ECALL with a7=0x34
2. posix_hw_layer receives: mq_id(a0), buf_addr(a1), buf_len(a2), timeout_ns(a3)
3. Validate parameters (same as mq_receive)
4. If queue not empty: same as mq_receive Case A (return immediately)
5. If queue empty:
   a. Convert timeout_ns to timer ticks
   b. Compute deadline = mtime + ticks
   c. Store deadline in tcb[current_task_id].wakeup_time
   d. Add to recv_wait list and timer wakeup list
   e. Block and context switch
6. On wakeup:
   a. If woken by mq_send: message copied, return msg_len
   b. If woken by timer: remove from recv_wait, return -ETIMEDOUT
```

**Error conditions:**
- Invalid mq_id or buf_len: return -EINVAL (0xFFFFFFEA)
- Timeout expired: return -ETIMEDOUT (0xFFFFFF92)

**Cycle count:** 10-30 cycles (immediate), 15-40 cycles (blocking with timer)

#### 2.4.6 mq_timedsend (0x35) -- Timed Message Send

```
Syscall Flow:
1. CPU executes ECALL with a7=0x35
2. posix_hw_layer receives: mq_id(a0), msg_data_addr(a1), msg_len(a2), timeout_ns(a3)
3. Validate parameters (same as mq_send)
4. If queue not full: same as mq_send Case A (return immediately)
5. If queue full:
   a. Convert timeout_ns to timer ticks
   b. Compute deadline = mtime + ticks
   c. Store deadline in tcb[current_task_id].wakeup_time
   d. Add to send_wait list and timer wakeup list
   e. Block and context switch
6. On wakeup:
   a. If woken by mq_receive (space freed): message sent, return 0
   b. If woken by timer: remove from send_wait, return -ETIMEDOUT
```

**Error conditions:**
- Invalid mq_id or msg_len: return -EINVAL (0xFFFFFFEA)
- Timeout expired: return -ETIMEDOUT (0xFFFFFF92)

**Cycle count:** 10-30 cycles (immediate), 15-40 cycles (blocking with timer)

---

### 2.5 Timer/Clock Operations

#### 2.5.1 clock_gettime (0x40) -- CLINT mtime Read

```
Syscall Flow:
1. CPU executes ECALL with a7=0x40
2. posix_hw_layer receives: clock_id(a0)
3. Validate clock_id:
   a. clock_id == 0 (CLOCK_REALTIME): read mtime
   b. clock_id == 1 (CLOCK_MONOTONIC): read mtime (same source in this system)
   c. Other values: return -EINVAL
4. posix_hw_layer reads CLINT mtime register directly:
   a. hw_rtos has a direct connection to the CLINT mtime counter (64-bit)
   b. Read mtime_r[31:0] into time_lo
   c. Read mtime_r[63:32] into time_hi
   d. Note: both halves are read atomically by hardware (no tearing)
5. posix_hw_layer sets:
   a. syscall_ret = time_lo (returned in a0)
   b. time_hi written to a1 via second return register mechanism
   c. syscall_done=1

Register Convention for 64-bit Return:
   a0 = mtime[31:0]  (low 32 bits)
   a1 = mtime[63:32] (high 32 bits)
```

**Hardware registers involved:**
- CLINT mtime_r[63:0] register at addresses ADDR_MTIME_LO (0x0200_BFF8) and ADDR_MTIME_HI (0x0200_BFFC)
- Direct wire from CLINT to hw_rtos/posix_hw_layer (not via APB, for zero-latency read)

**Error conditions:**
- Invalid clock_id: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 2-3 cycles (direct register read, fastest syscall)

#### 2.5.2 clock_settime (0x41) -- CLINT mtime Write

```
Syscall Flow:
1. CPU executes ECALL with a7=0x41
2. posix_hw_layer receives: clock_id(a0), time_lo(a1), time_hi(a2)
3. Validate clock_id (same as clock_gettime)
4. posix_hw_layer writes to CLINT mtime via APB bus:
   a. APB write to ADDR_MTIME_HI (0x0200_BFFC): set upper 32 bits first
   b. APB write to ADDR_MTIME_LO (0x0200_BFF8): set lower 32 bits
   c. Note: write order (high first) prevents spurious timer interrupts
5. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Hardware registers involved:**
- CLINT mtime_r via APB write path

**Error conditions:**
- Invalid clock_id: return -EINVAL (0xFFFFFFEA)
- CLOCK_MONOTONIC may be read-only: return -EPERM (0xFFFFFFFF)

**Cycle count:** 6-8 cycles (two APB write transactions)

#### 2.5.3 nanosleep (0x42) -- Timer-based Sleep

```
Syscall Flow:
1. CPU executes ECALL with a7=0x42
2. posix_hw_layer receives: duration_lo(a0), duration_hi(a1)
3. Compute wakeup time:
   a. Read current CLINT mtime (64-bit, direct register access)
   b. Compute: wakeup_time = mtime + {duration_hi, duration_lo}
   c. If duration is zero: return 0 immediately (no sleep)
4. Set up timed block:
   a. Store wakeup_time in tcb[current_task_id].wakeup_time
   b. Add current_task_id to hw_rtos timer wakeup list (sorted insertion)
   c. Set tcb[current_task_id].state = TASK_BLOCKED
   d. Trigger context switch to next ready task
5. hw_rtos timer tick processing (every CLINT timer_tick):
   a. Compare mtime against wakeup_time for all tasks in timer wakeup list
   b. When mtime >= wakeup_time for a task:
      - Remove task from timer wakeup list
      - Set tcb[task].state = TASK_READY
      - Set saved a0 = 0 (success)
      - Add to ready queue
      - If woken task priority > current running task priority: trigger preemption
6. Sleeping task eventually resumes with a0=0
```

**Hardware registers involved:**
- CLINT mtime_r (read for current time)
- TCB wakeup_time field (64-bit)
- Timer wakeup list: sorted list of {task_id, wakeup_time} maintained in hw_rtos
- timer_tick signal from CLINT (drives wakeup list scan each cycle)

**Error conditions:**
- Duration is zero: return 0 immediately (not an error)
- Task interrupted by signal before duration expires: return -EINTR (not implemented; reserved)

**Cycle count:** 3 cycles (zero duration), 10-20 cycles (blocking + context switch)

#### 2.5.4 timer_create (0x43) -- Create Hardware Timer

```
Syscall Flow:
1. CPU executes ECALL with a7=0x43
2. posix_hw_layer receives: clock_id(a0), callback_addr(a1)
3. Validate: clock_id must be 0 or 1, callback_addr must be non-null and aligned
4. Allocate timer resource in hw_rtos:
   a. Timer table has 8 entries
   b. Find free slot (timer[i].valid == 0)
   c. If no free slot: return -ENOMEM
5. Initialize timer entry:
   a. timer[slot].valid          = 1
   b. timer[slot].owner_task_id  = current_task_id
   c. timer[slot].callback_addr  = callback_addr
   d. timer[slot].armed          = 0 (not yet armed)
   e. timer[slot].interval       = 0
   f. timer[slot].next_expiry    = 0
6. posix_hw_layer sets syscall_ret=slot (timer_id), asserts syscall_done=1
```

**Error conditions:**
- Invalid clock_id: return -EINVAL (0xFFFFFFEA)
- No free timer slot: return -ENOMEM (0xFFFFFFF4)
- Invalid callback_addr: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 5-8 cycles

#### 2.5.5 timer_settime (0x44) -- Arm/Set Hardware Timer

```
Syscall Flow:
1. CPU executes ECALL with a7=0x44
2. posix_hw_layer receives: timer_id(a0), interval_lo(a1), interval_hi(a2)
3. Validate: timer_id >= 8 or timer[timer_id].valid == 0: return -EINVAL
4. Set timer parameters:
   a. timer[id].interval = {interval_hi, interval_lo}
   b. Read current mtime
   c. timer[id].next_expiry = mtime + interval
   d. timer[id].armed = 1
   e. Insert timer into hw_rtos timer expiry list (sorted by next_expiry)
5. If interval == 0: disarm timer (timer[id].armed = 0)
6. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1

Timer Expiry Handling (asynchronous, on CLINT timer_tick):
   When mtime >= timer[id].next_expiry:
   a. Deliver signal SIGALRM to owner task (see signal mechanism section 2.7)
   b. For periodic timer: timer[id].next_expiry += timer[id].interval
   c. For one-shot: timer[id].armed = 0
```

**Error conditions:**
- Invalid timer_id: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 5-8 cycles

#### 2.5.6 timer_delete (0x45) -- Delete Hardware Timer

```
Syscall Flow:
1. CPU executes ECALL with a7=0x45
2. posix_hw_layer receives: timer_id(a0)
3. Validate: timer_id >= 8 or timer[timer_id].valid == 0: return -EINVAL
4. Disarm and free timer:
   a. Remove from timer expiry list
   b. Set timer[id].valid = 0
5. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Error conditions:**
- Invalid timer_id: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3-5 cycles

#### 2.5.7 timer_gettime (0x46) -- Get Remaining Timer Time

```
Syscall Flow:
1. CPU executes ECALL with a7=0x46
2. posix_hw_layer receives: timer_id(a0)
3. Validate: timer_id >= 8 or timer[timer_id].valid == 0: return -EINVAL
4. If timer not armed: return {0, 0}
5. Compute remaining:
   a. Read current mtime
   b. remaining = timer[id].next_expiry - mtime
   c. If next_expiry <= mtime: remaining = 0 (already expired)
6. Return:
   a. a0 = remaining[31:0]
   b. a1 = remaining[63:32]
7. posix_hw_layer asserts syscall_done=1
```

**Error conditions:**
- Invalid timer_id: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3-4 cycles

---

### 2.6 File I/O Operations

#### 2.6.1 open (0x50) -- Open File Descriptor

```
Syscall Flow:
1. CPU executes ECALL with a7=0x50
2. posix_hw_layer receives: device_type(a0), flags(a1)
3. posix_hw_layer manages FD table (16 entries per vsync_pkg):
   a. Scan fd_table[0:15] for first entry where fd_table[i].valid == 0
   b. Skip fd 0, 1, 2 (pre-assigned stdin/stdout/stderr)
   c. If no free entry: return -EMFILE (0xFFFFFFE4, too many open files)
4. Validate device_type:
   a. FD_TYPE_UART (3'b001): UART peripheral at 0x1000_0000
   b. FD_TYPE_GPIO (3'b010): GPIO peripheral at 0x1000_0100
   c. FD_TYPE_MEM  (3'b011): HyperRAM memory-mapped file at 0x2000_0000
   d. FD_TYPE_PIPE (3'b100): inter-task pipe (backed by message queue)
   e. FD_TYPE_NONE (3'b000): /dev/null equivalent
   f. Other values: return -ENOENT (0xFFFFFFFE)
5. Validate flags:
   a. O_RDONLY (0x0000), O_WRONLY (0x0001), O_RDWR (0x0002)
   b. O_NONBLOCK (0x0800): optional non-blocking flag
6. Initialize FD entry:
   a. fd_table[slot].valid     = 1
   b. fd_table[slot].fd_type   = device_type
   c. fd_table[slot].base_addr = device base address (from address map)
   d. fd_table[slot].flags     = flags[15:0]
   e. fd_table[slot].position  = 0 (for seekable devices)
7. posix_hw_layer sets syscall_ret=slot (fd number), asserts syscall_done=1
```

**Hardware registers involved:**
- FD table: 16 entries x {valid[0], fd_type[2:0], base_addr[31:0], flags[15:0]}
  (as defined by fd_entry_t in vsync_pkg)
- Pre-assigned entries:
  - fd_table[0]: {valid=1, fd_type=FD_TYPE_UART, base_addr=0x1000_0000, flags=O_RDONLY}  (stdin)
  - fd_table[1]: {valid=1, fd_type=FD_TYPE_UART, base_addr=0x1000_0000, flags=O_WRONLY}  (stdout)
  - fd_table[2]: {valid=1, fd_type=FD_TYPE_UART, base_addr=0x1000_0000, flags=O_WRONLY}  (stderr)

**Error conditions:**
- FD table full: return -EMFILE (0xFFFFFFE4)
- Invalid device_type: return -ENOENT (0xFFFFFFFE)
- Invalid flags: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 5-8 cycles

#### 2.6.2 close (0x51) -- Close File Descriptor

```
Syscall Flow:
1. CPU executes ECALL with a7=0x51
2. posix_hw_layer receives: fd(a0)
3. Validate:
   a. fd >= MAX_FD(16): return -EBADF (0xFFFFFFF7)
   b. fd_table[fd].valid == 0: return -EBADF
   c. fd == 0, 1, or 2: return -EPERM (cannot close stdin/stdout/stderr)
4. Clear FD entry:
   a. fd_table[fd].valid = 0
   b. fd_table[fd].fd_type = FD_TYPE_NONE
5. If fd_type was FD_TYPE_PIPE: release associated message queue resource
6. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Error conditions:**
- Invalid fd: return -EBADF (0xFFFFFFF7)
- Attempt to close stdin/stdout/stderr: return -EPERM (0xFFFFFFFF)

**Cycle count:** 3-5 cycles

#### 2.6.3 read (0x52) -- Read from File Descriptor

```
Syscall Flow:
1. CPU executes ECALL with a7=0x52
2. posix_hw_layer receives: fd(a0), buf_addr(a1), count(a2)
3. Validate:
   a. fd >= MAX_FD or fd_table[fd].valid == 0: return -EBADF
   b. fd_table[fd].flags does not include read permission: return -EBADF
   c. buf_addr is null: return -EINVAL
   d. count == 0: return 0
4. Route to peripheral based on fd_table[fd].fd_type:

   FD_TYPE_UART (Serial Read):
   a. Read UART status register at REG_STATUS (base+0x08) via APB:
      - Check bit 3 (RX_EMPTY)
   b. If RX FIFO empty:
      - If O_NONBLOCK flag set: return -EAGAIN
      - Otherwise: block task until UART RX interrupt wakes it
        * Set tcb[current_task_id].state = TASK_BLOCKED
        * Register for UART RX interrupt via PLIC
        * Context switch; when UART IRQ fires, task woken
   c. Read bytes from UART RX FIFO:
      - For each byte (up to count):
        * APB read from REG_RX_DATA (base+0x04): read one byte, auto-pop FIFO
        * Write byte to buf_addr via AXI4 write: AWADDR=buf_addr+offset, WDATA=byte
        * Check RX_EMPTY after each byte; stop if FIFO becomes empty
   d. Return bytes_read (actual number of bytes transferred)

   FD_TYPE_GPIO (GPIO Input Read):
   a. APB read from REG_GPIO_IN (base+0x04): read all GPIO input pins
   b. Write 4 bytes to buf_addr via AXI4 write
   c. Return min(count, 4)

   FD_TYPE_MEM (HyperRAM Read):
   a. Compute address: hyperram_addr = base_addr + fd_table[fd].position
   b. AXI4 burst read from hyperram_addr, length=count bytes
   c. AXI4 burst write to buf_addr with read data
   d. Update fd_table[fd].position += bytes_read
   e. Return bytes_read

   FD_TYPE_NONE (/dev/null):
   a. Return 0 (EOF)

5. posix_hw_layer sets syscall_ret=bytes_read, asserts syscall_done=1
```

**Hardware registers involved:**
- FD table for device routing
- UART APB registers: REG_STATUS (0x08), REG_RX_DATA (0x04)
- GPIO APB register: REG_GPIO_IN (0x04)
- AXI4 master interface for data memory writes (buf_addr)
- AXI4 slave interface to HyperRAM controller (memory reads)

**Error conditions:**
- Invalid fd: return -EBADF (0xFFFFFFF7)
- No data available (non-blocking): return -EAGAIN (0xFFFFFFF5)

**Cycle count:** 5-10 cycles (GPIO), 10-100+ cycles (UART, depends on byte count and FIFO state), 20-200+ cycles (HyperRAM, depends on burst length and latency)

#### 2.6.4 write (0x53) -- Write to File Descriptor

```
Syscall Flow:
1. CPU executes ECALL with a7=0x53
2. posix_hw_layer receives: fd(a0), buf_addr(a1), count(a2)
3. Validate:
   a. fd >= MAX_FD or fd_table[fd].valid == 0: return -EBADF
   b. fd_table[fd].flags does not include write permission: return -EBADF
   c. buf_addr is null: return -EINVAL
   d. count == 0: return 0
4. Route to peripheral based on fd_table[fd].fd_type:

   FD_TYPE_UART (Serial Write):
   a. Read UART status register at REG_STATUS (base+0x08) via APB:
      - Check bit 0 (TX_FULL)
   b. For each byte (up to count):
      - AXI4 read from buf_addr+offset: fetch byte to send
      - If TX FIFO full:
        * If O_NONBLOCK: return bytes_written so far
        * Otherwise: block task until UART TX interrupt (TX FIFO not full)
      - APB write to REG_TX_DATA (base+0x00): push byte into TX FIFO
      - Check TX_FULL after each byte
   c. Return bytes_written

   FD_TYPE_GPIO (GPIO Output Write):
   a. AXI4 read 4 bytes from buf_addr
   b. APB write to REG_GPIO_OUT (base+0x00): set GPIO output pins
   c. Return min(count, 4)

   FD_TYPE_MEM (HyperRAM Write):
   a. Compute address: hyperram_addr = base_addr + fd_table[fd].position
   b. AXI4 burst read from buf_addr to fetch data
   c. AXI4 burst write to hyperram_addr with fetched data
   d. Update fd_table[fd].position += bytes_written
   e. Return bytes_written

   FD_TYPE_NONE (/dev/null):
   a. Return count (all bytes "written" and discarded)

5. posix_hw_layer sets syscall_ret=bytes_written, asserts syscall_done=1
```

**Hardware registers involved:**
- UART APB registers: REG_TX_DATA (0x00), REG_STATUS (0x08)
- GPIO APB register: REG_GPIO_OUT (0x00)
- AXI4 master interface for buf_addr reads and peripheral writes

**Error conditions:**
- Invalid fd: return -EBADF (0xFFFFFFF7)
- TX FIFO full (non-blocking): return -EAGAIN or partial write count

**Cycle count:** 5-10 cycles (GPIO), 10-100+ cycles (UART), 20-200+ cycles (HyperRAM)

#### 2.6.5 ioctl (0x54) -- Device Control

```
Syscall Flow:
1. CPU executes ECALL with a7=0x54
2. posix_hw_layer receives: fd(a0), request(a1), arg(a2)
3. Validate fd
4. Route based on fd_type and request:

   FD_TYPE_UART:
   a. request=0x01 (SET_BAUD): APB write to REG_BAUD_DIV (base+0x10), data=arg
   b. request=0x02 (GET_STATUS): APB read REG_STATUS (base+0x08), return in a0
   c. request=0x03 (SET_CTRL): APB write to REG_CTRL (base+0x0C), data=arg
   d. request=0x04 (GET_CTRL): APB read REG_CTRL (base+0x0C), return in a0

   FD_TYPE_GPIO:
   a. request=0x01 (SET_DIRECTION): APB write to REG_GPIO_DIR (base+0x08), data=arg
   b. request=0x02 (GET_DIRECTION): APB read REG_GPIO_DIR, return in a0
   c. request=0x03 (SET_INT_EN): APB write to REG_GPIO_INT_EN (base+0x0C), data=arg
   d. request=0x04 (SET_INT_TYPE): APB write to REG_GPIO_INT_TYPE (base+0x14), data=arg
   e. request=0x05 (SET_INT_POL): APB write to REG_GPIO_INT_POL (base+0x18), data=arg
   f. request=0x06 (CLR_INT): APB write to REG_GPIO_INT_STATUS (base+0x10), data=arg (W1C)

5. posix_hw_layer sets syscall_ret=0 (or read value), asserts syscall_done=1
```

**Error conditions:**
- Invalid fd: return -EBADF (0xFFFFFFF7)
- Unsupported request for device type: return -ENOSYS (0xFFFFFFDA)

**Cycle count:** 4-8 cycles (single APB transaction)

#### 2.6.6 lseek (0x55) -- Seek (Limited Support)

```
Syscall Flow:
1. CPU executes ECALL with a7=0x55
2. posix_hw_layer receives: fd(a0), offset(a1), whence(a2)
3. Validate:
   a. Invalid fd: return -EBADF
   b. fd_type not FD_TYPE_MEM: return -ESPIPE (unseekable device)
4. Compute new position based on whence:
   a. SEEK_SET (0): new_pos = offset
   b. SEEK_CUR (1): new_pos = fd_table[fd].position + offset
   c. SEEK_END (2): not supported on HyperRAM (no file size), return -EINVAL
5. Validate new_pos >= 0
6. fd_table[fd].position = new_pos
7. posix_hw_layer sets syscall_ret=new_pos, asserts syscall_done=1
```

**Error conditions:**
- Invalid fd: return -EBADF (0xFFFFFFF7)
- Device not seekable: return -ESPIPE (0xFFFFFFE3)
- Invalid whence: return -EINVAL (0xFFFFFFEA)
- Negative resulting position: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3-4 cycles

---

### 2.7 Signal Operations

#### 2.7.1 kill (0x60) -- Send Signal to Thread

```
Syscall Flow:
1. CPU executes ECALL with a7=0x60
2. posix_hw_layer receives: thread_id(a0), signal_num(a1)
3. Validate:
   a. thread_id >= MAX_TASKS or tcb[thread_id].valid == 0: return -ESRCH
   b. signal_num > 31 or signal_num == 0: return -EINVAL
4. Set pending signal bit in target task:
   a. tcb[thread_id].signal_pending |= (1 << signal_num)
5. If target task is TASK_BLOCKED and blocked in sigwait for this signal:
   a. Wake task: set state = TASK_READY
   b. Set saved a0 = signal_num (return value of sigwait)
   c. Clear the pending bit
6. If signal_num == SIGKILL (9):
   a. Force-terminate target task (same as pthread_exit)
   b. No handler, cannot be masked
7. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Hardware registers involved:**
- TCB signal_pending bitmap (32-bit, one bit per signal number)
- TCB signal_mask bitmap (32-bit, per-task signal blocking mask)
- Signal handler table: 32 entries x {handler_addr[31:0]} per task (stored in TCB extension)

**Error conditions:**
- Invalid thread_id: return -ESRCH (0xFFFFFFFD)
- Invalid signal_num: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3-5 cycles (set pending), 8-15 cycles (wake blocked task)

#### 2.7.2 sigaction (0x61) -- Register Signal Handler

```
Syscall Flow:
1. CPU executes ECALL with a7=0x61
2. posix_hw_layer receives: signal_num(a0), handler_addr(a1)
3. Validate:
   a. signal_num > 31 or signal_num == 0: return -EINVAL
   b. signal_num == SIGKILL(9): return -EINVAL (cannot set handler for SIGKILL)
4. Store handler in current task's signal handler table:
   a. sig_handler[current_task_id][signal_num] = handler_addr
   b. If handler_addr == 0: restore default action for this signal
   c. If handler_addr == 1: SIG_IGN (ignore signal)
5. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Hardware registers involved:**
- Signal handler table: per-task, 32 entries, stored in TCB extension SRAM

**Error conditions:**
- Invalid signal_num: return -EINVAL (0xFFFFFFEA)
- Cannot set handler for SIGKILL: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3-5 cycles

#### 2.7.3 sigprocmask (0x62) -- Set Signal Mask

```
Syscall Flow:
1. CPU executes ECALL with a7=0x62
2. posix_hw_layer receives: how(a0), set(a1)
3. Read current signal mask: old_mask = tcb[current_task_id].signal_mask
4. Update signal mask based on 'how':
   a. SIG_BLOCK (0):   new_mask = old_mask | set
   b. SIG_UNBLOCK (1): new_mask = old_mask & ~set
   c. SIG_SETMASK (2): new_mask = set
   d. Other: return -EINVAL
5. Force SIGKILL bit to 0 (cannot be masked): new_mask &= ~(1 << 9)
6. tcb[current_task_id].signal_mask = new_mask
7. posix_hw_layer sets syscall_ret=old_mask, asserts syscall_done=1
```

**Error conditions:**
- Invalid 'how' value: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3-4 cycles

#### 2.7.4 sigwait (0x63) -- Wait for Signal

```
Syscall Flow:
1. CPU executes ECALL with a7=0x63
2. posix_hw_layer receives: set(a0) -- bitmap of signals to wait for
3. Check if any signal in 'set' is already pending:
   a. pending_match = tcb[current_task_id].signal_pending & set
   b. If pending_match != 0:
      - sig = lowest set bit of pending_match (priority-encoded)
      - Clear bit: tcb[current_task_id].signal_pending &= ~(1 << sig)
      - Return sig immediately
4. If no matching signal is pending:
   a. Store wait set: tcb[current_task_id].sigwait_set = set
   b. Set tcb[current_task_id].state = TASK_BLOCKED
   c. Trigger context switch
   d. When kill() delivers a matching signal, task is woken with a0=signal_num
```

**Error conditions:**
- Empty set (set==0): return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3-5 cycles (signal already pending), 10-20 cycles (blocking)

#### 2.7.5 raise (0x64) -- Raise Signal in Current Thread

```
Syscall Flow:
1. CPU executes ECALL with a7=0x64
2. posix_hw_layer receives: signal_num(a0)
3. Equivalent to: kill(current_task_id, signal_num)
4. Set bit in own signal_pending bitmap
5. Signal delivery happens before the task resumes:
   a. Check if signal is not masked and handler is registered
   b. If handler exists: push signal frame, redirect to handler
   c. If default action is terminate: execute pthread_exit
6. posix_hw_layer sets syscall_ret=0, asserts syscall_done=1
```

**Error conditions:**
- Invalid signal_num: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 3-5 cycles (set pending + immediate delivery check)

#### 2.7.6 Signal Delivery Mechanism (Asynchronous)

```
Signal delivery occurs when a task is about to be scheduled (during context restore):

1. hw_rtos checks: tcb[task_id].signal_pending & ~tcb[task_id].signal_mask
2. If deliverable signals exist:
   a. Select highest-priority signal (SIGKILL always first)
   b. Look up handler: handler_addr = sig_handler[task_id][signal_num]
   c. If handler_addr is a valid function:
      - Save current PC and registers to signal frame on task's stack:
        * Decrement sp by frame size (132 bytes: 32 regs + PC)
        * Write saved registers to stack via AXI4 writes
      - Set task PC = handler_addr
      - Set a0 = signal_num (handler argument)
      - Set ra = sigreturn_trampoline_addr (return address)
   d. If handler_addr == SIG_IGN (1): discard signal, clear pending bit
   e. If handler_addr == SIG_DFL (0):
      - SIGKILL: terminate task (pthread_exit equivalent)
      - SIGTERM: terminate task
      - SIGUSR1/SIGUSR2/SIGALRM: ignore by default

3. sigreturn trampoline (at fixed address in IMEM):
   - Executes ECALL with a7=0x65 (internal sigreturn syscall)
   - posix_hw_layer restores original register context from signal frame
   - Task resumes at the original PC before signal delivery
```

---

### 2.8 System Operations

#### 2.8.1 sysconf (0x70) -- Get System Configuration

```
Syscall Flow:
1. CPU executes ECALL with a7=0x70
2. posix_hw_layer receives: name(a0)
3. Return configuration value based on name:
   a. _SC_NPROCESSORS_CONF (0): return 1 (single-hart system)
   b. _SC_NPROCESSORS_ONLN (1): return 1
   c. _SC_PAGE_SIZE (2): return 4096 (even without MMU, defines allocation unit)
   d. _SC_THREAD_THREADS_MAX (3): return MAX_TASKS (16)
   e. _SC_SEM_NSEMS_MAX (4): return 8
   f. _SC_SEM_VALUE_MAX (5): return 65535 (16-bit count)
   g. _SC_MQ_OPEN_MAX (6): return 4
   h. _SC_TIMER_MAX (7): return 8
   i. _SC_OPEN_MAX (8): return MAX_FD (16)
   j. _SC_CLK_TCK (9): return clock frequency / tick divisor
   k. Other: return -EINVAL
4. posix_hw_layer sets syscall_ret=value, asserts syscall_done=1
```

**Error conditions:**
- Unrecognized name: return -EINVAL (0xFFFFFFEA)

**Cycle count:** 2-3 cycles (lookup table)

#### 2.8.2 sched_get_priority_max (0x71) -- Get Maximum Priority

```
Syscall Flow:
1. CPU executes ECALL with a7=0x71
2. posix_hw_layer returns: a0 = 15 (TASK_PRIORITY_W=4, range 0-15)
3. syscall_done=1
```

**Cycle count:** 2 cycles (constant return)

#### 2.8.3 sched_get_priority_min (0x72) -- Get Minimum Priority

```
Syscall Flow:
1. CPU executes ECALL with a7=0x72
2. posix_hw_layer returns: a0 = 0
3. syscall_done=1
```

**Cycle count:** 2 cycles (constant return)

#### 2.8.4 sbrk (0x73) -- Adjust Program Break (Heap)

```
Syscall Flow:
1. CPU executes ECALL with a7=0x73
2. posix_hw_layer receives: increment(a0)
3. posix_hw_layer manages per-task heap pointer:
   a. Read current break: prev_brk = heap_brk[current_task_id]
   b. Compute new break: new_brk = prev_brk + increment
   c. Validate new_brk:
      - Must not exceed task's allocated memory region
      - Must not overlap with stack (compare with tcb[current_task_id].sp)
      - If invalid: return -ENOMEM
   d. Update: heap_brk[current_task_id] = new_brk
4. posix_hw_layer sets syscall_ret=prev_brk (old break value), asserts syscall_done=1
```

**Hardware registers involved:**
- Heap break table: 16 entries (one per task), 32-bit each
- TCB sp field (for stack collision detection)

**Error conditions:**
- Would exceed memory region: return -ENOMEM (0xFFFFFFF4)
- Would collide with stack: return -ENOMEM (0xFFFFFFF4)

**Cycle count:** 3-5 cycles

---

## 3. ECALL Instruction Syscall Dispatch Specification

### 3.1 Syscall Calling Convention (RISC-V ABI)

```
Register Usage:
  a7 (x17):     Syscall number (8-bit, values 0x00-0x7F)
  a0-a5 (x10-x15): Arguments (up to 6, left-to-right)
  a0 (x10):     Primary return value
  a1 (x11):     Secondary return value (for 64-bit returns like clock_gettime)

ECALL Instruction Encoding:
  31        20 19  15 14  12 11   7 6     0
  [000000000000][00000][ 000][00000][1110011]
  imm=0         rs1=0  f3=0  rd=0   OP_SYSTEM

Exception Cause:
  mcause = 11 (Environment call from M-mode, CAUSE_ECALL_M)
  mepc   = address of the ECALL instruction itself
```

### 3.2 ECALL Dispatch Sequence (Cycle-Accurate)

```
Cycle 0: ECALL instruction in ID stage
         - decode_stage detects OP_SYSTEM with funct3=000, instr[20]=0
         - ctrl.ecall asserted in ctrl_signals_t
         - Pipeline registers: ecall=1 propagates to EX stage

Cycle 1: ECALL reaches exception_unit (EX/MEM boundary)
         - exception_unit sees ecall=1
         - exception_taken=1, exception_cause=CAUSE_ECALL_M (11)
         - exception_pc = PC of ECALL instruction (saved to mepc via CSR unit)
         - flush_all=1 (flush IF, ID, EX stages)
         - redirect_valid=1, redirect_pc = mtvec (trap vector)

Cycle 2: Pipeline flush propagates
         - IF/ID, ID/EX, EX/MEM registers invalidated (valid=0)
         - CSR unit updates: mepc=ECALL_PC, mcause=11, mstatus.MIE=0
         - In VSync hardware RTOS mode:
           * Instead of jumping to mtvec software handler, the ECALL is
             intercepted by posix_hw_layer via direct signals:
           * ecall_req asserted to posix_hw_layer
           * syscall_num = a7 value (captured from register file x17)
           * syscall_arg0-arg5 = a0-a5 values (captured from x10-x15)

Cycle 3: posix_hw_layer begins processing
         - syscall_busy asserted (CPU pipeline stalls via hazard_unit)
         - Syscall number decoded (8-bit case statement)
         - Arguments latched into internal registers

Cycle 4-N: Hardware operation executes
         - Duration depends on syscall type:
           * Trivial (pthread_self, sched_get_priority_max): 1 cycle
           * Register read (clock_gettime): 1-2 cycles
           * Table operation (sem_trywait, mutex_trylock): 2-3 cycles
           * Complex (pthread_create): 10-20 cycles
           * Peripheral I/O (read/write): 10-200+ cycles
           * Blocking (sem_wait on count=0): triggers context switch

Cycle N+1: Operation complete
         - syscall_ret[31:0] loaded with return value
         - For dual-return syscalls (clock_gettime): a1 also set
         - syscall_done asserted for 1 cycle

Cycle N+2: CPU pipeline resumes
         - Pipeline stall released
         - a0 register in register file updated with syscall_ret
         - PC = mepc + 4 (instruction after ECALL)
         - Pipeline begins fetching from mepc+4
         - mstatus.MIE restored (interrupts re-enabled)

Cycle N+3: Normal pipeline execution continues
```

### 3.3 Blocking Syscall Handling

When a syscall results in the calling task being blocked (e.g., sem_wait on a semaphore with count=0, pthread_join on a still-active thread, or read on an empty UART FIFO without O_NONBLOCK):

```
Blocking Flow:
1. posix_hw_layer determines the operation must block
2. posix_hw_layer signals hw_rtos to block the current task:
   a. rtos_op_data encodes the blocking reason and resource ID
   b. hw_rtos sets tcb[current_task_id].state = TASK_BLOCKED
   c. hw_rtos records the blocking condition in the TCB

3. hw_rtos initiates context switch:
   a. Assert ctx_switch_req=1
   b. CPU saves register state:
      - save_regs[0:31] = {x0..x31} (32 registers x 32 bits)
      - save_pc = mepc + 4 (return point after ECALL)
   c. hw_rtos stores context into current TCB's register save area (16x32x32 SRAM)
   d. CPU asserts ctx_switch_ack=1

4. hw_rtos selects next task:
   a. Run priority scheduler on ready queue
   b. Select highest-priority TASK_READY task
   c. If no READY task: select idle task (task_id=0, WFI loop)
   d. Load new task context from register save area
   e. Output: restore_regs[0:31], restore_pc

5. CPU resumes new task:
   a. Register file loaded from restore_regs
   b. PC set to restore_pc
   c. current_task_id updated
   d. Pipeline resumes fetching

6. Later, when the resource becomes available:
   a. The event (sem_post, mutex_unlock, UART data arrival) triggers the hw_rtos
   b. hw_rtos changes blocked task state to TASK_READY
   c. hw_rtos writes the syscall return value into the task's saved a0 register
   d. Task is added to ready queue
   e. If woken task has higher priority than currently running task:
      preemption occurs (another context switch)
```

### 3.4 Non-blocking Syscall Handling

For operations that always complete immediately without blocking:

```
Non-blocking Examples:
  - pthread_self (0x04): reads current_task_id register
  - sem_trywait (0x22): checks count, returns immediately
  - clock_gettime (0x40): reads mtime register
  - sched_get_priority_max (0x71): returns constant

Non-blocking Flow:
1. posix_hw_layer receives syscall
2. Executes operation (1-5 cycles)
3. Sets syscall_ret with result
4. Asserts syscall_done
5. CPU resumes at mepc+4
6. Total latency: 4-8 cycles (pipeline flush + operation + resume)
```

### 3.5 Interaction with Interrupt System

```
ECALL and Interrupt Interaction:
1. When ECALL is being processed (syscall_busy=1):
   - External interrupts are masked (mstatus.MIE=0, set during trap entry)
   - Timer interrupts are deferred
   - No nested exceptions during syscall processing

2. After syscall completion:
   - mstatus.MIE is restored
   - Any pending interrupts are serviced on the next cycle
   - RTOS time-slice timer continues counting during syscall

3. Preemption during long syscalls:
   - For very long operations (e.g., large UART read), the posix_hw_layer
     may periodically check for pending higher-priority tasks
   - Implementation: hw_rtos timer_tick signal is monitored even during
     syscall processing; if time slice expires, operation is checkpointed
     and context switch occurs
```

---

## 4. Error Handling

### 4.1 Error Code Definitions

Errors are returned as negative values in a0 (32-bit two's complement). These codes are compatible with standard POSIX errno values.

| Error Code | Decimal | Hex (32-bit) | Name | Description |
|------------|---------|--------------|------|-------------|
| -1 | -1 | 0xFFFFFFFF | EPERM | Operation not permitted |
| -2 | -2 | 0xFFFFFFFE | ENOENT | No such entity (device/file) |
| -3 | -3 | 0xFFFFFFFD | ESRCH | No such thread/process |
| -9 | -9 | 0xFFFFFFF7 | EBADF | Bad file descriptor |
| -11 | -11 | 0xFFFFFFF5 | EAGAIN | Resource temporarily unavailable |
| -12 | -12 | 0xFFFFFFF4 | ENOMEM | Out of memory / no free resource slots |
| -16 | -16 | 0xFFFFFFF0 | EBUSY | Resource busy (mutex locked, etc.) |
| -22 | -22 | 0xFFFFFFEA | EINVAL | Invalid argument |
| -24 | -24 | 0xFFFFFFE8 | EMFILE | Too many open file descriptors |
| -29 | -29 | 0xFFFFFFE3 | ESPIPE | Illegal seek (device not seekable) |
| -35 | -35 | 0xFFFFFFDD | EDEADLK | Resource deadlock would occur |
| -38 | -38 | 0xFFFFFFDA | ENOSYS | Function not implemented |
| -110 | -110 | 0xFFFFFF92 | ETIMEDOUT | Operation timed out |

### 4.2 Invalid Syscall Number Handling

```
When syscall_num does not match any defined entry:
1. posix_hw_layer default case in syscall decoder
2. Set syscall_ret = 0xFFFFFFDA (-ENOSYS)
3. Assert syscall_done=1
4. CPU resumes with a0 = -ENOSYS
5. No side effects, no state changes
```

### 4.3 Resource Exhaustion Handling

| Resource | Limit | Error on Exhaustion | Syscalls Affected |
|----------|-------|--------------------|--------------------|
| TCB (task) slots | 16 (MAX_TASKS) | -ENOMEM | pthread_create |
| Mutex slots | 8 | -ENOMEM | pthread_mutex_init |
| Semaphore slots | 8 | -ENOMEM | sem_init |
| Message queue slots | 4 | -ENOMEM | mq_open |
| Timer slots | 8 | -ENOMEM | timer_create |
| File descriptor slots | 16 (MAX_FD) | -EMFILE | open |
| Heap memory | Per-task limit | -ENOMEM | sbrk |

### 4.4 Hardware Fault Handling

```
Bus Error during Syscall:
  If an AXI4 transaction returns SLVERR or DECERR during a syscall
  (e.g., reading from an invalid buf_addr):
  1. posix_hw_layer detects error from AXI4 BRESP or RRESP
  2. Aborts the current operation
  3. Returns -EFAULT (value -14, 0xFFFFFFF2) to indicate memory fault
  4. No partial results are committed

Timeout Protection:
  Each syscall operation has a hardware watchdog counter:
  1. Counter starts when syscall_busy is asserted
  2. If counter exceeds configurable limit (default: 65536 cycles):
     - Operation is forcibly terminated
     - Returns -ETIMEDOUT
     - Affected peripheral may need reset via ioctl
```

---

## 5. File Descriptor (FD) Table

### 5.1 FD Table Structure

The FD table is managed entirely within the `posix_hw_layer` module as a register array. It is shared across all tasks (global FD namespace, consistent with POSIX semantics).

```
Parameters:
  MAX_FD     = 16   (from vsync_pkg)
  FD_WIDTH   = 4    ($clog2(MAX_FD))

FD Table Array:
  fd_entry_t fd_table [0:MAX_FD-1];
```

### 5.2 FD Table Entry

Each entry uses the `fd_entry_t` structure defined in `vsync_pkg.sv`:

| Field | Type | Bits | Description |
|-------|------|------|-------------|
| valid | logic | [0:0] | Entry is active (1) or free (0) |
| fd_type | fd_type_t | [2:0] | Device type enum |
| base_addr | logic | [31:0] | Peripheral base address for this device |
| flags | logic | [15:0] | Open flags (read/write/nonblock) |

Extended fields (implementation-specific, not in fd_entry_t):

| Field | Bits | Description |
|-------|------|-------------|
| position | [31:0] | Current read/write position (for seekable devices) |
| device_id | [3:0] | Device instance ID (for multiple UARTs, etc.) |

### 5.3 Pre-assigned File Descriptors

```
Reset initialization (posix_hw_layer reset logic):

fd_table[0] = {valid:1, fd_type:FD_TYPE_UART, base_addr:32'h1000_0000, flags:16'h0000};
  // stdin: UART RX, O_RDONLY

fd_table[1] = {valid:1, fd_type:FD_TYPE_UART, base_addr:32'h1000_0000, flags:16'h0001};
  // stdout: UART TX, O_WRONLY

fd_table[2] = {valid:1, fd_type:FD_TYPE_UART, base_addr:32'h1000_0000, flags:16'h0001};
  // stderr: UART TX, O_WRONLY (same physical UART as stdout)
```

### 5.4 Device Type to Peripheral Mapping

| Device Type | Enum Value | Peripheral Module | Base Address | Description |
|-------------|------------|-------------------|--------------|-------------|
| FD_TYPE_NONE | 3'b000 | (none) | N/A | /dev/null equivalent; reads return 0, writes are discarded |
| FD_TYPE_UART | 3'b001 | uart_apb | 0x1000_0000 | Serial I/O via TX/RX FIFOs (16-deep) |
| FD_TYPE_GPIO | 3'b010 | gpio_apb | 0x1000_0100 | GPIO pins; read=input register, write=output register |
| FD_TYPE_MEM | 3'b011 | hyperram_ctrl | 0x2000_0000 | Memory-mapped file in external HyperRAM |
| FD_TYPE_PIPE | 3'b100 | (internal msgq) | N/A | Inter-task pipe backed by message queue |

### 5.5 Read/Write Operation Flow

```
read(fd, buf_addr, count) -- Detailed Peripheral Routing:

1. Lookup: entry = fd_table[fd]
2. Validate: entry.valid==1, flags permit read
3. Switch on entry.fd_type:

   FD_TYPE_UART:
     base = entry.base_addr (0x1000_0000)
     bytes_read = 0
     while (bytes_read < count):
       // Check RX FIFO status
       APB_READ(base + REG_STATUS)  // 0x1000_0008
       if (prdata[3] == 1):         // bit3 = RX_EMPTY
         break                      // No more data
       // Read one byte from RX FIFO
       APB_READ(base + REG_RX_DATA) // 0x1000_0004
       byte = prdata[7:0]
       // Write byte to user buffer
       AXI4_WRITE(buf_addr + bytes_read, {24'h0, byte}, strb=4'b0001)
       bytes_read++
     return bytes_read

   FD_TYPE_GPIO:
     base = entry.base_addr (0x1000_0100)
     APB_READ(base + REG_GPIO_IN)   // 0x1000_0104
     gpio_val = prdata
     AXI4_WRITE(buf_addr, gpio_val, strb=4'b1111)
     return min(count, 4)

   FD_TYPE_MEM:
     base = entry.base_addr (0x2000_0000)
     offset = fd_table[fd].position
     // AXI4 burst read from HyperRAM
     for i in 0..((count+3)/4 - 1):
       AXI4_READ(base + offset + i*4)
       AXI4_WRITE(buf_addr + i*4, rdata)
     fd_table[fd].position += count
     return count

   FD_TYPE_NONE:
     return 0  // EOF
```

```
write(fd, buf_addr, count) -- Detailed Peripheral Routing:

1. Lookup: entry = fd_table[fd]
2. Validate: entry.valid==1, flags permit write
3. Switch on entry.fd_type:

   FD_TYPE_UART:
     base = entry.base_addr (0x1000_0000)
     bytes_written = 0
     while (bytes_written < count):
       // Check TX FIFO status
       APB_READ(base + REG_STATUS)  // 0x1000_0008
       if (prdata[0] == 1):         // bit0 = TX_FULL
         if (O_NONBLOCK): break     // Return partial
         else: block until TX not full (UART interrupt driven)
       // Read byte from user buffer
       AXI4_READ(buf_addr + bytes_written)
       byte = rdata[7:0]
       // Push byte to TX FIFO
       APB_WRITE(base + REG_TX_DATA, {24'h0, byte})  // 0x1000_0000
       bytes_written++
     return bytes_written

   FD_TYPE_GPIO:
     base = entry.base_addr (0x1000_0100)
     AXI4_READ(buf_addr)
     gpio_val = rdata
     APB_WRITE(base + REG_GPIO_OUT, gpio_val)  // 0x1000_0100
     return min(count, 4)

   FD_TYPE_MEM:
     base = entry.base_addr (0x2000_0000)
     offset = fd_table[fd].position
     for i in 0..((count+3)/4 - 1):
       AXI4_READ(buf_addr + i*4)
       AXI4_WRITE(base + offset + i*4, rdata)
     fd_table[fd].position += count
     return count

   FD_TYPE_NONE:
     return count  // Discard all data
```

---

## 6. Signal Handling

### 6.1 Signal Table

| Signal Name | Number | Default Action | Maskable | Description |
|-------------|--------|---------------|----------|-------------|
| SIGHUP | 1 | Terminate | Yes | Hangup |
| SIGINT | 2 | Terminate | Yes | Interrupt (Ctrl+C equivalent via UART) |
| SIGKILL | 9 | Terminate | No | Kill (cannot be caught, blocked, or ignored) |
| SIGUSR1 | 10 | Ignore | Yes | User-defined signal 1 |
| SIGUSR2 | 12 | Ignore | Yes | User-defined signal 2 |
| SIGALRM | 14 | Ignore | Yes | Timer alarm (from timer_settime expiry) |
| SIGTERM | 15 | Terminate | Yes | Termination request |
| SIGCHLD | 17 | Ignore | Yes | Child task terminated |

### 6.2 Signal Delivery Mechanism

```
Signal Lifecycle:

1. Signal Generation (kill/raise/timer expiry):
   - tcb[target_task_id].signal_pending |= (1 << signal_num)

2. Signal Delivery Check (on every task schedule):
   - deliverable = signal_pending & ~signal_mask
   - If deliverable == 0: no signals to deliver, resume normally
   - If deliverable != 0: process signals before resuming task

3. Signal Handler Invocation:
   a. Select signal: sig = find_first_set(deliverable)
   b. Clear pending: signal_pending &= ~(1 << sig)
   c. Look up handler: handler = sig_handler[task_id][sig]

   d. If handler is a valid function address (>1):
      // Build signal frame on task's stack
      current_sp = tcb[task_id].sp
      frame_sp = current_sp - 136  // 32 regs * 4 + PC(4) = 132, aligned to 8

      // Save all 32 registers + PC to stack via AXI4 writes
      for reg in 0..31:
        AXI4_WRITE(frame_sp + reg*4, saved_regs[reg])
      AXI4_WRITE(frame_sp + 128, saved_pc)

      // Set up handler execution context
      tcb[task_id].sp = frame_sp
      tcb[task_id].pc = handler
      saved_regs[10] = sig            // a0 = signal number
      saved_regs[1]  = SIGRETURN_ADDR // ra = sigreturn trampoline

   e. If handler == SIG_IGN (1):
      - Discard signal, continue to next deliverable signal

   f. If handler == SIG_DFL (0):
      - SIGKILL/SIGTERM/SIGHUP/SIGINT: terminate task (pthread_exit flow)
      - SIGUSR1/SIGUSR2/SIGALRM/SIGCHLD: ignore

4. Signal Return (sigreturn):
   a. Handler completes, returns to sigreturn trampoline (via ra)
   b. Trampoline executes ECALL with a7=0x65 (internal SYS_SIGRETURN)
   c. posix_hw_layer restores:
      - Read 32 registers + PC from signal frame on stack via AXI4 reads
      - Restore tcb[task_id].sp = frame_sp + 136
      - Resume at original saved PC
```

### 6.3 Signal Pending and Mask Registers

```
Per-task signal state (stored in TCB extension):

signal_pending[31:0]:  Bitmap of signals pending delivery
                       Bit N = 1 means signal N is pending
                       Set by kill(), raise(), timer expiry
                       Cleared when signal is delivered or discarded

signal_mask[31:0]:     Bitmap of blocked (masked) signals
                       Bit N = 1 means signal N is blocked
                       Set/modified by sigprocmask()
                       Bit 9 (SIGKILL) is always forced to 0

sigwait_set[31:0]:     Bitmap of signals being waited on via sigwait()
                       Non-zero only when task is blocked in sigwait

sig_handler[31:0][0:31]: Array of 32 handler addresses (one per signal)
                          0 = SIG_DFL (default action)
                          1 = SIG_IGN (ignore)
                          >1 = user handler function address
```

---

## 7. Hardware Resource Summary

### 7.1 RTOS Resource Limits

| Resource | Count | Storage | Notes |
|----------|-------|---------|-------|
| Tasks (TCB) | 16 | 16 x TCB struct + 16 x 32 x 32-bit register save | MAX_TASKS parameter |
| Mutexes | 8 | 8 x mutex control struct | Priority inheritance supported |
| Semaphores | 8 | 8 x semaphore control struct | 16-bit count, 16-bit wait_list |
| Message Queues | 4 | 4 x control struct + 4KB message SRAM | Up to 16 messages x 64 bytes each |
| Timers | 8 | 8 x timer control struct | Backed by CLINT mtime |
| File Descriptors | 16 | 16 x fd_entry_t | 3 pre-assigned (stdin/stdout/stderr) |

### 7.2 Cycle Count Summary

| Operation Category | Typical Cycles | Worst Case | Notes |
|-------------------|---------------|------------|-------|
| Register read (pthread_self, sched_get_*) | 2-3 | 3 | Direct register access |
| Clock read (clock_gettime) | 2-3 | 3 | CLINT mtime direct wire |
| Table lookup (sem_trywait, mutex_trylock) | 3-5 | 5 | Single table access |
| Table modify (sem_post no waiter, mutex_unlock no waiter) | 3-5 | 8 | Update + optional scan |
| Resource create (pthread_create, sem_init) | 5-15 | 20 | Scan + init + optional AXI4 write |
| Blocking + context switch | 10-25 | 50 | Save 32 regs + scheduler + restore 32 regs |
| Peripheral I/O (single byte UART) | 8-15 | 20 | APB read/write + AXI4 transfer |
| Peripheral I/O (bulk UART/HyperRAM) | 20-200+ | 1000+ | Depends on byte count and FIFO/bus state |

### 7.3 posix_hw_layer Interface Signal Summary

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| ecall_req | 1 | CPU -> posix_hw_layer | ECALL detected |
| syscall_num | 8 | CPU -> posix_hw_layer | Syscall number from a7 |
| syscall_arg0 | 32 | CPU -> posix_hw_layer | Argument a0 |
| syscall_arg1 | 32 | CPU -> posix_hw_layer | Argument a1 |
| syscall_arg2 | 32 | CPU -> posix_hw_layer | Argument a2 |
| syscall_arg3 | 32 | CPU -> posix_hw_layer | Argument a3 (extended) |
| syscall_arg4 | 32 | CPU -> posix_hw_layer | Argument a4 (extended) |
| syscall_arg5 | 32 | CPU -> posix_hw_layer | Argument a5 (extended) |
| syscall_ret | 32 | posix_hw_layer -> CPU | Return value for a0 |
| syscall_ret1 | 32 | posix_hw_layer -> CPU | Secondary return for a1 |
| syscall_done | 1 | posix_hw_layer -> CPU | Syscall complete strobe |
| syscall_busy | 1 | posix_hw_layer -> CPU | Pipeline stall request |
| rtos_task_create | 1 | posix_hw_layer -> hw_rtos | Create task command |
| rtos_task_exit | 1 | posix_hw_layer -> hw_rtos | Exit task command |
| rtos_task_yield | 1 | posix_hw_layer -> hw_rtos | Yield task command |
| rtos_sem_op | 2 | posix_hw_layer -> hw_rtos | Semaphore operation code |
| rtos_mutex_op | 2 | posix_hw_layer -> hw_rtos | Mutex operation code |
| rtos_msgq_op | 2 | posix_hw_layer -> hw_rtos | Message queue operation code |
| rtos_op_data | 32 | posix_hw_layer -> hw_rtos | Operation parameter data |
| rtos_op_done | 1 | hw_rtos -> posix_hw_layer | Operation complete |
| rtos_op_result | 32 | hw_rtos -> posix_hw_layer | Operation result value |

---

## 8. Implementation Notes

### 8.1 Syscall Number Encoding in posix_hw_layer

The syscall decoder in `posix_hw_layer` uses the upper nibble of the syscall number for category routing and the lower nibble for operation selection within the category:

```
syscall_num[7:4] = category:
  0x0 = Thread Management
  0x1 = Mutex Operations
  0x2 = Semaphore Operations
  0x3 = Message Queue Operations
  0x4 = Timer/Clock Operations
  0x5 = File I/O Operations
  0x6 = Signal Operations
  0x7 = System Operations

syscall_num[3:0] = operation within category
```

This encoding enables efficient hardware decoding with a two-level multiplexer.

### 8.2 Relationship to vsync_pkg Syscall Numbers

The `vsync_pkg.sv` file currently defines a `syscall_num_t` enum with a different (Linux-like) numbering scheme. This document specifies the target numbering for the complete POSIX-compatible interface. The `vsync_pkg.sv` enum should be updated to match the category-based numbering defined in Section 1 before implementing the `posix_hw_layer` RTL. The existing enum serves as a placeholder from early development.

### 8.3 Memory Map Reference for Peripheral Access

Syscalls that access peripherals route through the following addresses (from `vsync_pkg.sv`):

| Peripheral | Base Address | End Address | Size | Access Path |
|------------|-------------|-------------|------|-------------|
| UART (uart_apb) | 0x1000_0000 | 0x1000_00FF | 256B | AXI4 -> APB bridge -> PSEL[0] |
| GPIO (gpio_apb) | 0x1000_0100 | 0x1000_01FF | 256B | AXI4 -> APB bridge -> PSEL[1] |
| PLIC | 0x0C00_0000 | 0x0C00_0FFF | 4KB | AXI4 -> APB bridge -> PSEL[2] |
| CLINT | 0x0200_0000 | 0x0200_FFFF | 64KB | AXI4 -> APB bridge -> PSEL[3] |
| HyperRAM | 0x2000_0000 | 0x2FFF_FFFF | 256MB | AXI4 -> hyperram_ctrl |
| hw_rtos | 0x1100_0000 | 0x1100_FFFF | 64KB | Direct signals (not AXI4 for syscall path) |
| posix_hw_layer | 0x1200_0000 | 0x1200_FFFF | 64KB | Direct signals from CPU |

Note: The `posix_hw_layer` communicates with `hw_rtos` via direct signals (rtos_task_create, rtos_sem_op, etc.) for low-latency syscall processing, not through the AXI4 bus. The AXI4 slave interfaces on hw_rtos and posix_hw_layer are available for debug/diagnostic access from software.

### 8.4 Context Switch Timing Budget

```
Context switch breakdown (worst case):
  Register save:    32 registers x 1 cycle = 32 cycles (parallel wide bus)
  PC save:          1 cycle
  TCB update:       2 cycles (state change + queue update)
  Scheduler:        3-5 cycles (priority bitmap scan + FIFO dequeue)
  TCB load:         2 cycles
  Register restore: 32 registers x 1 cycle = 32 cycles (parallel wide bus)
  PC restore:       1 cycle
  Pipeline refill:  3 cycles (IF/ID/EX pipeline refill)
  ---
  Total:            ~76 cycles worst case

Optimization: Using the dedicated wide register interface (save_regs/restore_regs
as 32x32 bit bus), save and restore can be done in fewer cycles through parallel
transfer. Target: 8-15 cycles for save, 8-15 cycles for restore, bringing total
context switch to ~30-40 cycles.
```
