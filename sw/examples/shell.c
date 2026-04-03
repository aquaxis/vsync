/**
 * @file shell.c
 * @brief VSync UART Shell / Monitor Program
 *
 * Interactive command-line shell for debugging and monitoring the VSync
 * hardware RTOS processor via UART (115200 8N1).
 *
 * Features:
 *   - Memory peek/poke (hex address read/write)
 *   - RTOS scheduler state monitoring
 *   - GPIO register inspection and control
 *   - UART status display
 *   - System information and uptime
 *
 * UART RX: Direct MMIO polling (STATUS.RX_EMPTY check -> RX_DATA read)
 * UART TX: POSIX write() via stdout fd
 *
 * Build:
 *   cd sw/tools && make shell
 */

#include "../lib/vsync_posix.h"
#include "../lib/vsync_hw.h"

/* =========================================================================
 * Configuration
 * ========================================================================= */

#define CMD_BUF_SIZE    80      /**< Maximum command line length       */
#define MAX_ARGS         4      /**< Maximum number of arguments       */
#define PEEK_MAX_WORDS  16      /**< Maximum words for peek command    */
#define PROMPT          "vsync> "

/* UART file descriptor (opened once in main) */
static int uart_fd = -1;

/* =========================================================================
 * String Utilities (no libc dependency)
 * ========================================================================= */

static int shell_strlen(const char *s)
{
    int len = 0;
    while (s[len] != '\0') len++;
    return len;
}

static int shell_strcmp(const char *a, const char *b)
{
    while (*a && *a == *b) { a++; b++; }
    return (unsigned char)*a - (unsigned char)*b;
}

static void shell_memset(void *dst, int c, int n)
{
    unsigned char *p = (unsigned char *)dst;
    for (int i = 0; i < n; i++) p[i] = (unsigned char)c;
}

/* =========================================================================
 * Number Conversion
 * ========================================================================= */

/**
 * @brief Parse hexadecimal string to uint32_t
 * @param s  Input string (with or without "0x" prefix)
 * @param out  Output value
 * @return 0 on success, -1 on parse error
 */
static int hex_to_uint32(const char *s, uint32_t *out)
{
    uint32_t val = 0;
    int digits = 0;

    /* Skip optional "0x" or "0X" prefix */
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        s += 2;
    }

    while (*s) {
        uint32_t nib;
        if (*s >= '0' && *s <= '9')      nib = (uint32_t)(*s - '0');
        else if (*s >= 'a' && *s <= 'f') nib = (uint32_t)(*s - 'a' + 10);
        else if (*s >= 'A' && *s <= 'F') nib = (uint32_t)(*s - 'A' + 10);
        else return -1;  /* invalid character */

        val = (val << 4) | nib;
        digits++;
        if (digits > 8) return -1;  /* overflow */
        s++;
    }

    if (digits == 0) return -1;
    *out = val;
    return 0;
}

/**
 * @brief Parse decimal string to uint32_t
 * @param s  Input string
 * @param out  Output value
 * @return 0 on success, -1 on parse error
 */
static int dec_to_uint32(const char *s, uint32_t *out)
{
    uint32_t val = 0;
    int digits = 0;

    while (*s) {
        if (*s < '0' || *s > '9') return -1;
        uint32_t prev = val;
        val = val * 10 + (uint32_t)(*s - '0');
        if (val < prev) return -1;  /* overflow */
        digits++;
        s++;
    }

    if (digits == 0) return -1;
    *out = val;
    return 0;
}

/* Hex output buffer (shared, 9 bytes: 8 hex digits + NUL) */
static char hex_buf[9];

/**
 * @brief Convert uint32_t to 8-digit hex string
 * @param val  Value to convert
 * @return Pointer to static hex_buf
 */
static const char *uint32_to_hex(uint32_t val)
{
    static const char hextab[] = "0123456789ABCDEF";
    for (int i = 7; i >= 0; i--) {
        hex_buf[i] = hextab[val & 0xF];
        val >>= 4;
    }
    hex_buf[8] = '\0';
    return hex_buf;
}

/* Decimal output buffer */
static char dec_buf[11];  /* max "4294967295" + NUL */

/**
 * @brief Convert uint32_t to decimal string
 * @param val  Value to convert
 * @return Pointer to static dec_buf
 */
static const char *uint32_to_dec(uint32_t val)
{
    int i = 10;
    dec_buf[i] = '\0';
    if (val == 0) {
        dec_buf[--i] = '0';
    } else {
        while (val > 0) {
            dec_buf[--i] = '0' + (char)(val % 10);
            val /= 10;
        }
    }
    return &dec_buf[i];
}

/* =========================================================================
 * UART I/O
 *
 * RX: Direct MMIO polling (bypass POSIX to avoid blocking)
 * TX: POSIX write() through the opened UART fd
 * ========================================================================= */

/**
 * @brief Non-blocking character read from UART RX FIFO
 * @return Character (0-255) or -1 if no data available
 */
static int shell_getchar(void)
{
    if (REG32(UART_BASE + UART_STATUS) & UART_ST_RX_EMPTY)
        return -1;
    return (int)(REG32(UART_BASE + UART_RX_DATA) & 0xFF);
}

/**
 * @brief Blocking character read from UART
 * @return Character (0-255)
 */
static int shell_getchar_blocking(void)
{
    int c;
    while ((c = shell_getchar()) < 0)
        ;  /* spin */
    return c;
}

/**
 * @brief Write a single character to UART TX
 */
static void shell_putchar(char c)
{
    /* Wait for TX FIFO not full before writing */
    while (REG32(UART_BASE + UART_STATUS) & UART_ST_TX_FULL)
        ;  /* spin until FIFO has space */
    write(uart_fd, &c, 1);
}

/**
 * @brief Write a null-terminated string to UART TX
 */
static void shell_puts(const char *s)
{
    while (*s) {
        shell_putchar(*s++);
    }
}

/**
 * @brief Print a newline (CR+LF)
 */
static void shell_newline(void)
{
    shell_puts("\r\n");
}

/**
 * @brief Print a 32-bit value in hex with "0x" prefix
 */
static void shell_put_hex(uint32_t val)
{
    shell_puts("0x");
    shell_puts(uint32_to_hex(val));
}

/**
 * @brief Print a 32-bit value in decimal
 */
static void shell_put_dec(uint32_t val)
{
    shell_puts(uint32_to_dec(val));
}

/* =========================================================================
 * Line Editor
 *   - Echo typed characters
 *   - Backspace/DEL handling
 *   - Ctrl-C cancels line
 *   - CR/LF terminates input
 * ========================================================================= */

/**
 * @brief Read a line from UART with editing support
 * @param buf  Buffer to store the line (NUL terminated)
 * @param size  Buffer size
 * @return Number of characters read, or -1 on Ctrl-C
 */
static int shell_readline(char *buf, int size)
{
    int pos = 0;
    shell_memset(buf, 0, size);

    while (1) {
        int c = shell_getchar_blocking();

        if (c == '\r' || c == '\n') {
            /* End of line */
            shell_newline();
            buf[pos] = '\0';
            return pos;
        }

        if (c == 0x03) {
            /* Ctrl-C: cancel */
            shell_puts("^C");
            shell_newline();
            buf[0] = '\0';
            return -1;
        }

        if (c == 0x08 || c == 0x7F) {
            /* Backspace or DEL */
            if (pos > 0) {
                pos--;
                buf[pos] = '\0';
                /* Erase character on terminal: BS + space + BS */
                shell_puts("\b \b");
            }
            continue;
        }

        /* Ignore non-printable characters */
        if (c < 0x20 || c > 0x7E)
            continue;

        /* Store printable character if room */
        if (pos < size - 1) {
            buf[pos++] = (char)c;
            shell_putchar((char)c);  /* echo */
        }
    }
}

/* =========================================================================
 * Command Argument Parser
 * ========================================================================= */

static int    argc;
static char  *argv[MAX_ARGS + 1];

/**
 * @brief Parse command line into argc/argv
 *
 * Tokenizes the input buffer in-place by replacing spaces with NUL.
 *
 * @param buf  Input command line (modified in-place)
 */
static void parse_args(char *buf)
{
    argc = 0;
    char *p = buf;

    while (*p && argc <= MAX_ARGS) {
        /* Skip leading spaces */
        while (*p == ' ') p++;
        if (*p == '\0') break;

        argv[argc++] = p;

        /* Find end of token */
        while (*p && *p != ' ') p++;
        if (*p) {
            *p = '\0';
            p++;
        }
    }
}

/* =========================================================================
 * Command Handlers
 * ========================================================================= */

/* Forward declarations */
static void cmd_help(void);
static void cmd_peek(void);
static void cmd_poke(void);
static void cmd_load(void);
static void cmd_go(void);
static void cmd_rtos(void);
static void cmd_gpio(void);
static void cmd_uart(void);
static void cmd_info(void);
static void cmd_uptime(void);

/* --- help ---------------------------------------------------------------- */

static void cmd_help(void)
{
    shell_puts("VSync Shell Commands:\r\n");
    shell_puts("  help                  Show this help\r\n");
    shell_puts("  peek <addr> [count]   Read memory (hex addr, max 16 words)\r\n");
    shell_puts("  poke <addr> <value>   Write memory (hex addr & value)\r\n");
    shell_puts("  load [addr]           Load hex words via UART (default: 0x0)\r\n");
    shell_puts("  go [addr]             Jump to address (default: 0x0)\r\n");
    shell_puts("  rtos                  Show RTOS scheduler state\r\n");
    shell_puts("  gpio                  Show all GPIO registers\r\n");
    shell_puts("  gpio read             Read GPIO input value\r\n");
    shell_puts("  gpio write <val>      Set GPIO output (hex)\r\n");
    shell_puts("  gpio dir <mask>       Set GPIO direction (hex, 1=out)\r\n");
    shell_puts("  uart                  Show UART status/control\r\n");
    shell_puts("  info                  System information\r\n");
    shell_puts("  uptime                Show uptime from CLINT mtime\r\n");
}

/* --- peek ---------------------------------------------------------------- */

static void cmd_peek(void)
{
    if (argc < 2) {
        shell_puts("Usage: peek <addr> [count]\r\n");
        return;
    }

    uint32_t addr;
    if (hex_to_uint32(argv[1], &addr) < 0) {
        shell_puts("Error: invalid address\r\n");
        return;
    }

    /* Word-align the address */
    addr &= ~3U;

    uint32_t count = 1;
    if (argc >= 3) {
        if (dec_to_uint32(argv[2], &count) < 0) {
            /* Try hex too */
            if (hex_to_uint32(argv[2], &count) < 0) {
                shell_puts("Error: invalid count\r\n");
                return;
            }
        }
    }
    if (count == 0) count = 1;
    if (count > PEEK_MAX_WORDS) count = PEEK_MAX_WORDS;

    for (uint32_t i = 0; i < count; i++) {
        uint32_t a = addr + (i * 4);
        uint32_t val = REG32(a);

        shell_put_hex(a);
        shell_puts(": ");
        shell_put_hex(val);
        shell_newline();
    }
}

/* --- poke ---------------------------------------------------------------- */

static void cmd_poke(void)
{
    if (argc < 3) {
        shell_puts("Usage: poke <addr> <value>\r\n");
        return;
    }

    uint32_t addr, val;
    if (hex_to_uint32(argv[1], &addr) < 0) {
        shell_puts("Error: invalid address\r\n");
        return;
    }
    if (hex_to_uint32(argv[2], &val) < 0) {
        shell_puts("Error: invalid value\r\n");
        return;
    }

    /* Word-align */
    addr &= ~3U;

    REG32(addr) = val;

    /* Readback confirmation */
    shell_put_hex(addr);
    shell_puts(" <- ");
    shell_put_hex(val);
    shell_puts(" (readback: ");
    shell_put_hex(REG32(addr));
    shell_puts(")");
    shell_newline();
}

/* --- load ---------------------------------------------------------------- */

/**
 * @brief Load hex words from UART into memory
 *
 * Usage: load [addr]
 * Default addr = 0x00000000 (IMEM_BASE)
 *
 * Each line is an 8-digit hex word (e.g., DEADBEEF).
 * Lines starting with '#' or '@' are skipped (comments/markers).
 * Empty line or '.' terminates input.
 * Address auto-increments by 4 after each word.
 */
static void cmd_load(void)
{
    uint32_t addr = IMEM_BASE;
    static char line_buf[CMD_BUF_SIZE];

    if (argc >= 2) {
        if (hex_to_uint32(argv[1], &addr) < 0) {
            shell_puts("Error: invalid address\r\n");
            return;
        }
    }

    /* Word-align */
    addr &= ~3U;

    shell_puts("Loading to ");
    shell_put_hex(addr);
    shell_puts(" ... (empty line or '.' to end)\r\n");

    uint32_t count = 0;
    uint32_t cur_addr = addr;

    while (1) {
        int len = shell_readline(line_buf, CMD_BUF_SIZE);
        if (len < 0) {
            /* Ctrl-C: abort */
            shell_puts("Aborted.\r\n");
            return;
        }

        /* Empty line or '.' terminates */
        if (len == 0 || line_buf[0] == '.') {
            break;
        }

        /* Skip comment lines starting with '#' or '@' */
        if (line_buf[0] == '#' || line_buf[0] == '@') {
            continue;
        }

        /* Parse hex word */
        uint32_t val;
        if (hex_to_uint32(line_buf, &val) < 0) {
            shell_puts("Error: invalid hex '");
            shell_puts(line_buf);
            shell_puts("'\r\n");
            continue;
        }

        /* Write to memory */
        REG32(cur_addr) = val;
        cur_addr += 4;
        count++;
    }

    shell_puts("Loaded ");
    shell_put_dec(count);
    shell_puts(" words (");
    shell_put_dec(count * 4);
    shell_puts(" bytes) to ");
    shell_put_hex(addr);
    shell_puts(" - ");
    shell_put_hex(cur_addr - 4);
    shell_newline();
}

/* --- go ------------------------------------------------------------------ */

/**
 * @brief Jump to specified address and execute
 *
 * Usage: go [addr]
 * Default addr = 0x00000000 (IMEM_BASE)
 *
 * Drains UART TX FIFO, disables interrupts, then jumps to the target address
 * via function pointer cast.
 */
static void cmd_go(void)
{
    uint32_t addr = IMEM_BASE;

    if (argc >= 2) {
        if (hex_to_uint32(argv[1], &addr) < 0) {
            shell_puts("Error: invalid address\r\n");
            return;
        }
    }

    shell_puts("Jumping to ");
    shell_put_hex(addr);
    shell_puts(" ...\r\n");

    /* Drain UART TX FIFO - wait until all output has been transmitted */
    while (!(REG32(UART_BASE + UART_STATUS) & UART_ST_TX_EMPTY))
        ;  /* spin */

    /* Disable interrupts (clear MIE bit in mstatus) */
    __asm__ volatile("csrci mstatus, 0x8");

    /* Jump to target address via function pointer */
    ((void (*)(void))addr)();

    /* Should never reach here */
}

/* --- rtos ---------------------------------------------------------------- */

static const char *sched_fsm_name(uint32_t state)
{
    switch (state) {
    case SCHED_FSM_IDLE:    return "IDLE";
    case SCHED_FSM_SCAN:    return "SCAN";
    case SCHED_FSM_PREEMPT: return "PREEMPT";
    case SCHED_FSM_SWITCH:  return "SWITCH";
    case SCHED_FSM_DONE:    return "DONE";
    default:                return "UNKNOWN";
    }
}

static void cmd_rtos(void)
{
    shell_puts("=== RTOS Scheduler State ===\r\n");

    uint32_t en     = REG32(RTOS_BASE + RTOS_SCHED_EN);
    uint32_t policy = REG32(RTOS_BASE + RTOS_SCHED_POLICY);
    uint32_t cur    = REG32(RTOS_BASE + RTOS_CURRENT_TASK);
    uint32_t next   = REG32(RTOS_BASE + RTOS_NEXT_TASK);
    uint32_t active = REG32(RTOS_BASE + RTOS_TASK_ACTIVE);
    uint32_t count  = REG32(RTOS_BASE + RTOS_TASK_COUNT);
    uint32_t tslice = REG32(RTOS_BASE + RTOS_TIME_SLICE);
    uint32_t fsm    = REG32(RTOS_BASE + RTOS_FSM_STATE);
    uint32_t irq    = REG32(RTOS_BASE + RTOS_IRQ_STATUS);
    uint32_t trig   = REG32(RTOS_BASE + RTOS_SCHED_TRIGGER);

    shell_puts("  Scheduler Enable : ");
    shell_puts(en ? "ON" : "OFF");
    shell_newline();

    shell_puts("  Policy           : ");
    shell_put_dec(policy);
    shell_newline();

    shell_puts("  Current Task ID  : ");
    shell_put_dec(cur);
    shell_newline();

    shell_puts("  Next Task ID     : ");
    shell_put_dec(next);
    shell_newline();

    shell_puts("  Active Tasks Mask: ");
    shell_put_hex(active);
    shell_newline();

    shell_puts("  Task Count       : ");
    shell_put_dec(count);
    shell_puts(" / ");
    shell_put_dec(RTOS_MAX_TASKS);
    shell_newline();

    shell_puts("  Time Slice       : ");
    shell_put_dec(tslice);
    shell_puts(" cycles");
    shell_newline();

    shell_puts("  FSM State        : ");
    shell_puts(sched_fsm_name(fsm));
    shell_puts(" (");
    shell_put_dec(fsm);
    shell_puts(")");
    shell_newline();

    shell_puts("  IRQ Status       : ");
    shell_put_hex(irq);
    shell_newline();

    shell_puts("  Sched Trigger    : ");
    shell_put_hex(trig);
    shell_newline();
}

/* --- gpio ---------------------------------------------------------------- */

static void cmd_gpio(void)
{
    /* Sub-commands: gpio, gpio read, gpio write <val>, gpio dir <mask> */
    if (argc >= 2 && shell_strcmp(argv[1], "read") == 0) {
        /* gpio read */
        uint32_t val = REG32(GPIO_BASE + GPIO_IN);
        shell_puts("GPIO IN: ");
        shell_put_hex(val);
        shell_newline();
        return;
    }

    if (argc >= 3 && shell_strcmp(argv[1], "write") == 0) {
        /* gpio write <val> */
        uint32_t val;
        if (hex_to_uint32(argv[2], &val) < 0) {
            shell_puts("Error: invalid value\r\n");
            return;
        }
        REG32(GPIO_BASE + GPIO_OUT) = val;
        shell_puts("GPIO OUT <- ");
        shell_put_hex(val);
        shell_newline();
        return;
    }

    if (argc >= 3 && shell_strcmp(argv[1], "dir") == 0) {
        /* gpio dir <mask> */
        uint32_t val;
        if (hex_to_uint32(argv[2], &val) < 0) {
            shell_puts("Error: invalid mask\r\n");
            return;
        }
        REG32(GPIO_BASE + GPIO_DIR) = val;
        shell_puts("GPIO DIR <- ");
        shell_put_hex(val);
        shell_newline();
        return;
    }

    /* Default: show all GPIO registers */
    shell_puts("=== GPIO Registers ===\r\n");

    shell_puts("  OUT        : ");
    shell_put_hex(REG32(GPIO_BASE + GPIO_OUT));
    shell_newline();

    shell_puts("  IN         : ");
    shell_put_hex(REG32(GPIO_BASE + GPIO_IN));
    shell_newline();

    shell_puts("  DIR        : ");
    shell_put_hex(REG32(GPIO_BASE + GPIO_DIR));
    shell_newline();

    shell_puts("  INT_EN     : ");
    shell_put_hex(REG32(GPIO_BASE + GPIO_INT_EN));
    shell_newline();

    shell_puts("  INT_STATUS : ");
    shell_put_hex(REG32(GPIO_BASE + GPIO_INT_STATUS));
    shell_newline();

    shell_puts("  INT_TYPE   : ");
    shell_put_hex(REG32(GPIO_BASE + GPIO_INT_TYPE));
    shell_newline();

    shell_puts("  INT_POL    : ");
    shell_put_hex(REG32(GPIO_BASE + GPIO_INT_POL));
    shell_newline();
}

/* --- uart ---------------------------------------------------------------- */

static void cmd_uart(void)
{
    shell_puts("=== UART Registers ===\r\n");

    uint32_t status = REG32(UART_BASE + UART_STATUS);
    uint32_t ctrl   = REG32(UART_BASE + UART_CTRL);
    uint32_t baud   = REG32(UART_BASE + UART_BAUD_DIV);

    shell_puts("  STATUS   : ");
    shell_put_hex(status);
    shell_newline();

    shell_puts("    TX Full  : ");
    shell_puts((status & UART_ST_TX_FULL)  ? "Yes" : "No");
    shell_newline();

    shell_puts("    TX Empty : ");
    shell_puts((status & UART_ST_TX_EMPTY) ? "Yes" : "No");
    shell_newline();

    shell_puts("    RX Full  : ");
    shell_puts((status & UART_ST_RX_FULL)  ? "Yes" : "No");
    shell_newline();

    shell_puts("    RX Empty : ");
    shell_puts((status & UART_ST_RX_EMPTY) ? "Yes" : "No");
    shell_newline();

    shell_puts("    TX Busy  : ");
    shell_puts((status & UART_ST_TX_BUSY)  ? "Yes" : "No");
    shell_newline();

    shell_puts("  CTRL     : ");
    shell_put_hex(ctrl);
    shell_newline();

    shell_puts("    TX IE    : ");
    shell_puts((ctrl & UART_CTRL_TX_IE) ? "On" : "Off");
    shell_newline();

    shell_puts("    RX IE    : ");
    shell_puts((ctrl & UART_CTRL_RX_IE) ? "On" : "Off");
    shell_newline();

    shell_puts("    TX En    : ");
    shell_puts((ctrl & UART_CTRL_TX_EN) ? "On" : "Off");
    shell_newline();

    shell_puts("    RX En    : ");
    shell_puts((ctrl & UART_CTRL_RX_EN) ? "On" : "Off");
    shell_newline();

    shell_puts("  BAUD_DIV : ");
    shell_put_dec(baud);
    shell_puts(" (int=");
    shell_put_dec(baud >> 4);
    shell_puts(" frac=");
    shell_put_dec(baud & 0xF);
    shell_puts("/16)");
    shell_newline();
}

/* --- info ---------------------------------------------------------------- */

static void cmd_info(void)
{
    shell_puts("=== VSync System Information ===\r\n");
    shell_puts("  Architecture : RV32IM\r\n");
    shell_puts("  Clock        : 25 MHz\r\n");
    shell_puts("  RTOS         : Hardware Task Scheduler\r\n");
    shell_newline();
    shell_puts("  Memory Map:\r\n");
    shell_puts("    IMEM       : 0x00000000 - 0x0000FFFF (64 KB)\r\n");
    shell_puts("    DMEM       : 0x00010000 - 0x00013FFF (16 KB)\r\n");
    shell_puts("    CLINT      : 0x02000000 - 0x0200FFFF\r\n");
    shell_puts("    PLIC       : 0x0C000000 - 0x0C000FFF\r\n");
    shell_puts("    UART       : 0x10000000 - 0x100000FF\r\n");
    shell_puts("    GPIO       : 0x10000100 - 0x100001FF\r\n");
    shell_puts("    RTOS       : 0x11000000 - 0x1100FFFF\r\n");
    shell_puts("    POSIX      : 0x12000000 - 0x1200FFFF\r\n");
    shell_puts("    HyperRAM   : 0x20000000 - 0x2FFFFFFF (256 MB)\r\n");
}

/* --- uptime -------------------------------------------------------------- */

/**
 * @brief Divide 64-bit value (hi:lo) by 32-bit divisor using only 32-bit ops
 *
 * Uses bit-by-bit long division to avoid linking libgcc (__udivdi3).
 * Returns quotient low 32 bits (sufficient for ~136 years at 100 MHz).
 */
static uint32_t div64by32(uint32_t hi, uint32_t lo, uint32_t divisor,
                          uint32_t *remainder)
{
    uint32_t rem = 0;
    uint32_t q_hi = 0;
    uint32_t q_lo = 0;
    int i;

    /* Process high word (bit 31 down to bit 0) */
    for (i = 31; i >= 0; i--) {
        rem = (rem << 1) | ((hi >> i) & 1U);
        if (rem >= divisor) {
            rem -= divisor;
            q_hi |= (1U << i);
        }
    }

    /* Process low word (bit 31 down to bit 0) */
    for (i = 31; i >= 0; i--) {
        rem = (rem << 1) | ((lo >> i) & 1U);
        if (rem >= divisor) {
            rem -= divisor;
            q_lo |= (1U << i);
        }
    }

    if (remainder) *remainder = rem;
    /* q_hi would be needed for results > 2^32, but for practical uptimes q_lo suffices */
    (void)q_hi;
    return q_lo;
}

static void cmd_uptime(void)
{
    /* Read 64-bit mtime (re-read if high word changed during read) */
    uint32_t hi1, lo, hi2;
    do {
        hi1 = REG32(CLINT_BASE + CLINT_MTIME_HI);
        lo  = REG32(CLINT_BASE + CLINT_MTIME_LO);
        hi2 = REG32(CLINT_BASE + CLINT_MTIME_HI);
    } while (hi1 != hi2);

    /*
     * Convert ticks to seconds using 32-bit-only division.
     * mtime increments at SYS_CLK_HZ (25 MHz).
     * seconds = ticks / 25_000_000
     */
    uint32_t rem_ticks;
    uint32_t total_sec = div64by32(hi1, lo, SYS_CLK_HZ, &rem_ticks);

    uint32_t days  = total_sec / 86400U;
    uint32_t drem  = total_sec % 86400U;
    uint32_t hours = drem / 3600U;
    drem %= 3600U;
    uint32_t mins  = drem / 60U;
    uint32_t secs  = drem % 60U;

    shell_puts("Uptime: ");

    if (days > 0) {
        shell_put_dec(days);
        shell_puts("d ");
    }

    /* Print HH:MM:SS with leading zeros */
    if (hours < 10) shell_putchar('0');
    shell_puts(uint32_to_dec(hours));
    shell_putchar(':');
    if (mins < 10) shell_putchar('0');
    shell_puts(uint32_to_dec(mins));
    shell_putchar(':');
    if (secs < 10) shell_putchar('0');
    shell_puts(uint32_to_dec(secs));
    shell_newline();

    shell_puts("Ticks : ");
    shell_put_hex(hi1);
    shell_putchar('_');
    shell_put_hex(lo);
    shell_newline();
}

/* =========================================================================
 * Command Table
 * ========================================================================= */

typedef void (*cmd_handler_t)(void);

typedef struct {
    const char    *name;
    cmd_handler_t  handler;
    const char    *help;
} cmd_entry_t;

static const cmd_entry_t cmd_table[] = {
    { "help",   cmd_help,   "Show command help"           },
    { "peek",   cmd_peek,   "Read memory words"           },
    { "poke",   cmd_poke,   "Write memory word"           },
    { "load",   cmd_load,   "Load hex words via UART"     },
    { "go",     cmd_go,     "Jump to address and execute" },
    { "rtos",   cmd_rtos,   "Show RTOS scheduler state"   },
    { "gpio",   cmd_gpio,   "GPIO register control"       },
    { "uart",   cmd_uart,   "Show UART status"            },
    { "info",   cmd_info,   "System information"          },
    { "uptime", cmd_uptime, "Show system uptime"          },
};

#define CMD_COUNT  (int)(sizeof(cmd_table) / sizeof(cmd_table[0]))

/* =========================================================================
 * Command Dispatcher
 * ========================================================================= */

static void dispatch_command(char *line)
{
    parse_args(line);

    if (argc == 0) return;  /* empty line */

    for (int i = 0; i < CMD_COUNT; i++) {
        if (shell_strcmp(argv[0], cmd_table[i].name) == 0) {
            cmd_table[i].handler();
            return;
        }
    }

    shell_puts("Unknown command: ");
    shell_puts(argv[0]);
    shell_puts("\r\nType 'help' for command list.\r\n");
}

/* =========================================================================
 * Main Entry Point
 * ========================================================================= */

int main(void)
{
    static char cmd_buf[CMD_BUF_SIZE];

    /* Open UART device for TX output */
    uart_fd = open(FD_TYPE_UART, 0);
    if (uart_fd < 0) {
        return -1;
    }

    /* Banner */
    shell_puts("\r\n");
    shell_puts("========================================\r\n");
    shell_puts("  VSync Monitor Shell v1.0\r\n");
    shell_puts("  RISC-V RV32IM Hardware RTOS Processor\r\n");
    shell_puts("  UART: 115200 8N1\r\n");
    shell_puts("========================================\r\n");
    shell_puts("Type 'help' for command list.\r\n");
    shell_newline();

    /* Main command loop */
    while (1) {
        shell_puts(PROMPT);

        int len = shell_readline(cmd_buf, CMD_BUF_SIZE);
        if (len < 0) {
            /* Ctrl-C: just re-prompt */
            continue;
        }
        if (len == 0) {
            /* Empty line: re-prompt */
            continue;
        }

        dispatch_command(cmd_buf);
    }

    /* Never reached */
    close(uart_fd);
    return 0;
}
