# =============================================================================
# VSync Software Build System
#
# File: Makefile
# Description: Build rules for VSync RISC-V RV32IM applications
#
# Usage:
#   make all          - Build all example applications
#   make clean        - Remove all build artifacts
#   make hello_uart   - Build hello_uart example
#   make gpio_blink   - Build gpio_blink example
#   make multitask    - Build multitask example
#   make shell        - Build UART shell/monitor
# =============================================================================

# ---------------------------------------------------------------------------
# Toolchain Configuration
# ---------------------------------------------------------------------------
PREFIX   = riscv32-unknown-elf-
CC       = $(PREFIX)gcc
AS       = $(PREFIX)gcc
LD       = $(PREFIX)gcc
OBJCOPY  = $(PREFIX)objcopy
OBJDUMP  = $(PREFIX)objdump
SIZE     = $(PREFIX)size

# ---------------------------------------------------------------------------
# Build Flags
# ---------------------------------------------------------------------------
CFLAGS   = -march=rv32im -mabi=ilp32 -Os -Wall -Wextra -nostdlib \
           -ffreestanding -fno-builtin -ffunction-sections -fdata-sections
ASFLAGS  = -march=rv32im -mabi=ilp32 -nostdlib
LDFLAGS  = -T ../linker/vsync.ld -nostartfiles -Wl,--gc-sections \
           -march=rv32im -mabi=ilp32

# ---------------------------------------------------------------------------
# Source Directories
# ---------------------------------------------------------------------------
BOOT_DIR     = ../boot
LIB_DIR      = ../lib
EXAMPLES_DIR = ../examples
LINKER_DIR   = ../linker

# ---------------------------------------------------------------------------
# Common Source Files
# ---------------------------------------------------------------------------
BOOT_SRC  = $(BOOT_DIR)/start.S
LIB_SRC   = $(LIB_DIR)/vsync_posix.c
LIB_HDR   = $(LIB_DIR)/vsync_posix.h $(LIB_DIR)/vsync_hw.h
LDSCRIPT  = $(LINKER_DIR)/vsync.ld

# ---------------------------------------------------------------------------
# Example Applications
# ---------------------------------------------------------------------------
EXAMPLES = hello_uart gpio_blink multitask shell

# ---------------------------------------------------------------------------
# Build Output Directory
# ---------------------------------------------------------------------------
BUILD_DIR = build

# ---------------------------------------------------------------------------
# Default Target
# ---------------------------------------------------------------------------
.PHONY: all clean $(EXAMPLES)

all: $(BUILD_DIR) $(foreach ex,$(EXAMPLES),$(BUILD_DIR)/$(ex).elf $(BUILD_DIR)/$(ex).hex $(BUILD_DIR)/$(ex).bin)
	@echo "=== Build complete ==="
	@for ex in $(EXAMPLES); do \
		$(SIZE) $(BUILD_DIR)/$$ex.elf; \
	done

# ---------------------------------------------------------------------------
# Create build directory
# ---------------------------------------------------------------------------
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# ---------------------------------------------------------------------------
# Pattern Rules
# ---------------------------------------------------------------------------

# Compile example application -> ELF
$(BUILD_DIR)/%.elf: $(EXAMPLES_DIR)/%.c $(BOOT_SRC) $(LIB_SRC) $(LIB_HDR) $(LDSCRIPT) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(BOOT_SRC) $(LIB_SRC) $<
	@echo "Built: $@"

# ELF -> Verilog HEX (for $readmemh)
$(BUILD_DIR)/%.hex: $(BUILD_DIR)/%.elf
	#$(OBJCOPY) -O verilog $< $@
	$(OBJDUMP) -s -S $< > $(basename $@).dump
	$(OBJCOPY) -O binary --only-section=.data* $< $(basename $@)_d.bin
	$(OBJCOPY) -O binary --only-section=.text* --only-section=.rodata* $< $(basename $@)_i.bin
	hexdump -v -e '1/4 "%08x" "\n"' $(basename $@)_i.bin > $(basename $@)_i.hex
	hexdump -v -e '1/4 "%08x" "\n"' $(basename $@)_d.bin > $(basename $@)_d.hex
	@echo "Generated: $@"

# ELF -> Binary
$(BUILD_DIR)/%.bin: $(BUILD_DIR)/%.elf
	$(OBJCOPY) -O binary $< $@
	@echo "Generated: $@"

# ---------------------------------------------------------------------------
# Individual Example Targets
# ---------------------------------------------------------------------------
$(foreach ex,$(EXAMPLES),$(eval $(ex): $(BUILD_DIR)/$(ex).elf $(BUILD_DIR)/$(ex).hex $(BUILD_DIR)/$(ex).bin))

# ---------------------------------------------------------------------------
# Disassembly (for debugging)
# ---------------------------------------------------------------------------
$(BUILD_DIR)/%.dump: $(BUILD_DIR)/%.elf
	$(OBJDUMP) -d -S $< > $@
	@echo "Disassembly: $@"

dump: $(foreach ex,$(EXAMPLES),$(BUILD_DIR)/$(ex).dump)

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR)
	@echo "=== Clean complete ==="

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
.PHONY: help
help:
	@echo "VSync Software Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build all examples (default)"
	@echo "  clean        - Remove build artifacts"
	@echo "  hello_uart   - Build hello_uart example"
	@echo "  gpio_blink   - Build gpio_blink example"
	@echo "  multitask    - Build multitask example"
	@echo "  shell        - Build UART shell/monitor"
	@echo "  dump         - Generate disassembly for all examples"
	@echo "  help         - Show this help message"
