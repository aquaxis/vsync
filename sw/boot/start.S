# =============================================================================
# VSync - RISC-V RV32IM Boot Loader
#
# File: start.S
# Description: Startup code for VSync processor
#              - Stack pointer initialization
#              - BSS zero-clear
#              - .data section initialization (ROM -> RAM)
#              - main() call and exit handling
#              - Exception vector table and trap handler
# =============================================================================

    .section .text.init, "ax", @progbits
    .globl _start
    .globl _trap_handler

# =============================================================================
# Reset Vector / Entry Point
# =============================================================================
    .align 4
_start:
    # ------------------------------------------------------------------
    # 1. Disable interrupts during initialization
    # ------------------------------------------------------------------
    csrci   mstatus, 0x8           # Clear MIE bit (mstatus[3])

    # ------------------------------------------------------------------
    # 2. Initialize stack pointer (SP = DMEM end = 0x00013FFF)
    # ------------------------------------------------------------------
    lui     sp, %hi(0x00014000)
    addi    sp, sp, %lo(0x00014000)
    addi    sp, sp, -4             # sp = 0x00013FFC (word-aligned)

    # ------------------------------------------------------------------
    # 3. Initialize global pointer (if used)
    # ------------------------------------------------------------------
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    # ------------------------------------------------------------------
    # 4. Set up trap vector (mtvec = _trap_handler, Direct mode)
    # ------------------------------------------------------------------
    la      t0, _trap_handler
    csrw    mtvec, t0

    # Set up trap stack pointer in mscratch (for interrupt/exception handlers)
    la      t0, _trap_stack_top
    csrw    mscratch, t0

    # ------------------------------------------------------------------
    # 5. Clear BSS section (_bss_start to _bss_end)
    # ------------------------------------------------------------------
    la      t0, _bss_start
    la      t1, _bss_end
_bss_clear_loop:
    bge     t0, t1, _bss_clear_done
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       _bss_clear_loop
_bss_clear_done:

    # ------------------------------------------------------------------
    # 6. Initialize .data section (copy from ROM to RAM)
    #    Source: _data_load (in IMEM/ROM)
    #    Dest:   _data_start to _data_end (in DMEM/RAM)
    # ------------------------------------------------------------------
    la      t0, _data_start        # Destination (RAM)
    la      t1, _data_end          # Destination end
    la      t2, _data_load         # Source (ROM)
_data_copy_loop:
    bge     t0, t1, _data_copy_done
    lw      t3, 0(t2)
    sw      t3, 0(t0)
    addi    t0, t0, 4
    addi    t2, t2, 4
    j       _data_copy_loop
_data_copy_done:

    # ------------------------------------------------------------------
    # 7. Initialize hart ID (a0 = mhartid)
    # ------------------------------------------------------------------
    csrr    a0, mhartid

    # ------------------------------------------------------------------
    # 8. Enable interrupts
    # ------------------------------------------------------------------
    csrsi   mstatus, 0x8           # Set MIE bit (mstatus[3])

    # ------------------------------------------------------------------
    # 9. Call main()
    # ------------------------------------------------------------------
    call    main

    # ------------------------------------------------------------------
    # 10. After main() returns: pthread_exit(0) syscall
    #     syscall number: SYS_PTHREAD_EXIT = 0x01
    # ------------------------------------------------------------------
    li      a0, 0                  # Exit code = 0
    li      a7, 0x01               # SYS_PTHREAD_EXIT
    ecall

    # ------------------------------------------------------------------
    # 11. Infinite loop (should not reach here)
    # ------------------------------------------------------------------
_halt:
    wfi
    j       _halt


# =============================================================================
# Trap Handler (Exception / Interrupt)
# =============================================================================
    .align 4
_trap_handler:
    # ------------------------------------------------------------------
    # Save context: all caller-saved registers + ra
    # Using mscratch as temporary storage for sp
    # ------------------------------------------------------------------
    csrrw   sp, mscratch, sp       # Swap sp with mscratch (save user sp)

    # Allocate stack frame (32 registers * 4 bytes = 128 bytes + CSRs)
    addi    sp, sp, -144

    # Save general-purpose registers
    sw      ra,   0(sp)
    sw      t0,   4(sp)
    sw      t1,   8(sp)
    sw      t2,  12(sp)
    sw      a0,  16(sp)
    sw      a1,  20(sp)
    sw      a2,  24(sp)
    sw      a3,  28(sp)
    sw      a4,  32(sp)
    sw      a5,  36(sp)
    sw      a6,  40(sp)
    sw      a7,  44(sp)
    sw      t3,  48(sp)
    sw      t4,  52(sp)
    sw      t5,  56(sp)
    sw      t6,  60(sp)
    sw      s0,  64(sp)
    sw      s1,  68(sp)
    sw      s2,  72(sp)
    sw      s3,  76(sp)
    sw      s4,  80(sp)
    sw      s5,  84(sp)
    sw      s6,  88(sp)
    sw      s7,  92(sp)
    sw      s8,  96(sp)
    sw      s9, 100(sp)
    sw      s10,104(sp)
    sw      s11,108(sp)

    # Save CSRs
    csrr    t0, mepc
    sw      t0, 112(sp)
    csrr    t0, mcause
    sw      t0, 116(sp)
    csrr    t0, mtval
    sw      t0, 120(sp)
    csrr    t0, mstatus
    sw      t0, 124(sp)

    # Save original sp (from mscratch)
    csrr    t0, mscratch
    sw      t0, 128(sp)

    # Save gp
    sw      gp, 132(sp)

    # ------------------------------------------------------------------
    # Determine cause: interrupt or exception
    # ------------------------------------------------------------------
    csrr    t0, mcause
    bltz    t0, _handle_interrupt  # mcause[31] = 1 => interrupt

    # ------------------------------------------------------------------
    # Exception handler
    # ------------------------------------------------------------------
_handle_exception:
    # Check if ECALL (cause = 11)
    li      t1, 11
    beq     t0, t1, _handle_ecall

    # Other exceptions: skip faulting instruction (mepc += 4)
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    j       _trap_restore

_handle_ecall:
    # ECALL: Hardware RTOS handles via POSIX bridge
    # Advance PC past ecall instruction
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    j       _trap_restore

    # ------------------------------------------------------------------
    # Interrupt handler
    # ------------------------------------------------------------------
_handle_interrupt:
    # Mask off MSB to get interrupt cause number
    andi    t0, t0, 0x7FF

    # Machine software interrupt (cause = 3)
    li      t1, 3
    beq     t0, t1, _handle_sw_int

    # Machine timer interrupt (cause = 7)
    li      t1, 7
    beq     t0, t1, _handle_timer_int

    # Machine external interrupt (cause = 11)
    li      t1, 11
    beq     t0, t1, _handle_ext_int

    # Unknown interrupt: just return
    j       _trap_restore

_handle_sw_int:
    # Software interrupt handler (placeholder)
    j       _trap_restore

_handle_timer_int:
    # Timer interrupt handler (placeholder)
    j       _trap_restore

_handle_ext_int:
    # External interrupt handler (placeholder)
    j       _trap_restore

    # ------------------------------------------------------------------
    # Restore context and return from trap
    # ------------------------------------------------------------------
_trap_restore:
    # Restore CSRs
    lw      t0, 124(sp)
    csrw    mstatus, t0
    lw      t0, 112(sp)
    csrw    mepc, t0

    # Restore gp
    lw      gp, 132(sp)

    # Restore general-purpose registers
    lw      ra,   0(sp)
    lw      t0,   4(sp)
    lw      t1,   8(sp)
    lw      t2,  12(sp)
    lw      a0,  16(sp)
    lw      a1,  20(sp)
    lw      a2,  24(sp)
    lw      a3,  28(sp)
    lw      a4,  32(sp)
    lw      a5,  36(sp)
    lw      a6,  40(sp)
    lw      a7,  44(sp)
    lw      t3,  48(sp)
    lw      t4,  52(sp)
    lw      t5,  56(sp)
    lw      t6,  60(sp)
    lw      s0,  64(sp)
    lw      s1,  68(sp)
    lw      s2,  72(sp)
    lw      s3,  76(sp)
    lw      s4,  80(sp)
    lw      s5,  84(sp)
    lw      s6,  88(sp)
    lw      s7,  92(sp)
    lw      s8,  96(sp)
    lw      s9, 100(sp)
    lw      s10,104(sp)
    lw      s11,108(sp)

    # Restore original sp
    lw      sp, 128(sp)

    # Return from machine-mode trap
    mret


# =============================================================================
# Weak symbol for global pointer (may be defined by linker)
# =============================================================================
    .weak   __global_pointer$
