/**
 * @file vsync_hw.h
 * @brief VSync Hardware Register Definitions
 *
 * MMIO register address definitions for all VSync peripherals.
 * Register offsets are verified against RTL source (uart_apb.sv,
 * gpio_apb.sv, hw_rtos.sv, clint.sv, vsync_pkg.sv).
 *
 * Usage:
 *   #include "../lib/vsync_hw.h"
 *   uint32_t val = REG32(UART_BASE + UART_STATUS);
 *   REG32(GPIO_BASE + GPIO_OUT) = 0xFF;
 */

#ifndef VSYNC_HW_H
#define VSYNC_HW_H

#include <stdint.h>

/* =========================================================================
 * MMIO Access Macros
 * ========================================================================= */

/** Read/write a 32-bit memory-mapped register */
#define REG32(addr)  (*(volatile uint32_t *)(addr))

/** Read-only access (for documentation clarity) */
#define REG32_RO(addr)  (*(volatile const uint32_t *)(addr))

/* =========================================================================
 * Memory Map - Base Addresses (from vsync_pkg.sv)
 * ========================================================================= */

#define IMEM_BASE       0x00000000U  /**< Instruction memory (64 KB) */
#define IMEM_SIZE       0x00010000U
#define DMEM_BASE       0x00010000U  /**< Data memory (16 KB)        */
#define DMEM_SIZE       0x00004000U
#define CLINT_BASE      0x02000000U  /**< Core Local Interruptor     */
#define PLIC_BASE       0x0C000000U  /**< Platform-Level Int. Ctrl.  */
#define UART_BASE       0x10000000U  /**< UART peripheral            */
#define GPIO_BASE       0x10000100U  /**< GPIO peripheral            */
#define RTOS_BASE       0x11000000U  /**< Hardware RTOS subsystem    */
#define POSIX_BASE      0x12000000U  /**< POSIX syscall interface    */
#define HYPERRAM_BASE   0x20000000U  /**< HyperRAM (256 MB)          */

/* =========================================================================
 * UART Registers (uart_apb.sv)
 *   Base: 0x10000000
 *   16-byte TX/RX FIFOs, 8N1, fractional baud divider, default 115200 bps @ 25 MHz
 * ========================================================================= */

#define UART_TX_DATA    0x00U   /**< TX data register (write)        */
#define UART_RX_DATA    0x04U   /**< RX data register (read)         */
#define UART_STATUS     0x08U   /**< Status register (read)          */
#define UART_CTRL       0x0CU   /**< Control register (read/write)   */
#define UART_BAUD_DIV   0x10U   /**< Baud rate divisor (read/write)
                                  *  Value = round(CLK_FREQ / BAUD)
                                  *  [31:4]=int, [3:0]=frac (1/16ths)
                                  *  Default @25MHz/115200: 217 (0xD9) */

/** Calculate UART baud divisor for given clock and baud rate */
#define UART_BAUD_DIV_CALC(clk_hz, baud) \
    (((clk_hz) + (baud) / 2) / (baud))

/* UART Status Register Bits */
#define UART_ST_TX_FULL     (1U << 0)  /**< TX FIFO full            */
#define UART_ST_TX_EMPTY    (1U << 1)  /**< TX FIFO empty           */
#define UART_ST_RX_FULL     (1U << 2)  /**< RX FIFO full            */
#define UART_ST_RX_EMPTY    (1U << 3)  /**< RX FIFO empty           */
#define UART_ST_TX_BUSY     (1U << 4)  /**< TX shift reg busy       */

/* UART Control Register Bits */
#define UART_CTRL_TX_IE     (1U << 0)  /**< TX interrupt enable     */
#define UART_CTRL_RX_IE     (1U << 1)  /**< RX interrupt enable     */
#define UART_CTRL_TX_EN     (1U << 2)  /**< TX enable               */
#define UART_CTRL_RX_EN     (1U << 3)  /**< RX enable               */

/* =========================================================================
 * GPIO Registers (gpio_apb.sv)
 *   Base: 0x10000100
 *   32-bit wide, per-pin direction and interrupt control
 * ========================================================================= */

#define GPIO_OUT        0x00U   /**< Output data register            */
#define GPIO_IN         0x04U   /**< Input data register (read-only) */
#define GPIO_DIR        0x08U   /**< Direction (0=in, 1=out)         */
#define GPIO_INT_EN     0x0CU   /**< Interrupt enable per pin        */
#define GPIO_INT_STATUS 0x10U   /**< Interrupt status (W1C)          */
#define GPIO_INT_TYPE   0x14U   /**< Int type (0=level, 1=edge)      */
#define GPIO_INT_POL    0x18U   /**< Int polarity (0=low/fall, 1=hi) */

/* =========================================================================
 * RTOS Scheduler Registers (hw_rtos.sv)
 *   Base: 0x11000000
 *   AXI4-Lite slave, 32-bit aligned
 * ========================================================================= */

#define RTOS_SCHED_EN       0x00U   /**< Scheduler enable (R/W)      */
#define RTOS_SCHED_POLICY   0x04U   /**< Scheduling policy (R/W)     */
#define RTOS_CURRENT_TASK   0x08U   /**< Current task ID (R)         */
#define RTOS_NEXT_TASK      0x0CU   /**< Next scheduled task (R)     */
#define RTOS_TASK_ACTIVE    0x10U   /**< Task active bitmask (R)     */
#define RTOS_TASK_COUNT     0x14U   /**< Number of active tasks (R)  */
#define RTOS_TIME_SLICE     0x18U   /**< Time slice config (R/W)     */
#define RTOS_FSM_STATE      0x1CU   /**< Scheduler FSM state (R)     */
#define RTOS_IRQ_STATUS     0x20U   /**< IRQ/pending status (R)      */
#define RTOS_SCHED_TRIGGER  0x24U   /**< Scheduler trigger (R/W)     */

/* RTOS Task States (vsync_pkg.sv task_state_t) */
#define TASK_STATE_READY      0U
#define TASK_STATE_RUNNING    1U
#define TASK_STATE_BLOCKED    2U
#define TASK_STATE_SUSPENDED  3U
#define TASK_STATE_DORMANT    4U

/* RTOS Scheduler FSM States (task_scheduler.sv) */
#define SCHED_FSM_IDLE      0U
#define SCHED_FSM_SCAN      1U
#define SCHED_FSM_PREEMPT   2U
#define SCHED_FSM_SWITCH    3U
#define SCHED_FSM_DONE      4U

/* RTOS Parameters */
#define RTOS_MAX_TASKS      16U
#define RTOS_DEFAULT_TSLICE 1000U   /**< Default time slice (cycles) */

/* =========================================================================
 * CLINT Registers (clint.sv)
 *   Base: 0x02000000
 *   RISC-V standard Core Local Interruptor
 * ========================================================================= */

#define CLINT_MSIP          0x0000U  /**< Machine software int pending */
#define CLINT_MTIMECMP_LO   0x4000U  /**< Timer compare low 32 bits   */
#define CLINT_MTIMECMP_HI   0x4004U  /**< Timer compare high 32 bits  */
#define CLINT_MTIME_LO      0xBFF8U  /**< Timer counter low 32 bits   */
#define CLINT_MTIME_HI      0xBFFCU  /**< Timer counter high 32 bits  */

/* Clock frequency (for uptime calculation) */
#define SYS_CLK_HZ         25000000U   /**< 25 MHz system clock       */

/* =========================================================================
 * PLIC Registers (placeholder)
 *   Base: 0x0C000000
 * ========================================================================= */

#define PLIC_PRIORITY_BASE  0x0000U
#define PLIC_PENDING_BASE   0x1000U
#define PLIC_ENABLE_BASE    0x2000U
#define PLIC_THRESHOLD      0x200000U
#define PLIC_CLAIM          0x200004U

#endif /* VSYNC_HW_H */
