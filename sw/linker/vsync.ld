/* =============================================================================
 * VSync - Linker Script
 *
 * File: vsync.ld
 * Description: Memory layout and section placement for VSync processor
 *
 * Address Map (per vsync_pkg.sv):
 *   IMEM:     0x0000_0000 - 0x0000_FFFF (64KB, instruction memory / ROM)
 *   DMEM:     0x0001_0000 - 0x0001_3FFF (16KB, data memory / RAM)
 *   HYPERRAM: 0x2000_0000 - 0x2FFF_FFFF (256MB, external HyperRAM)
 * ============================================================================= */

ENTRY(_start)

MEMORY
{
    IMEM     (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM     (rwx) : ORIGIN = 0x00010000, LENGTH = 16K
    HYPERRAM (rwx) : ORIGIN = 0x20000000, LENGTH = 256M
}

SECTIONS
{
    /* -----------------------------------------------------------------
     * .text section: Code (placed in IMEM)
     * .text.init comes first to ensure _start is at address 0x0
     * ----------------------------------------------------------------- */
    .text : ALIGN(4)
    {
        *(.text.init)
        *(.text .text.*)
    } > IMEM

    /* -----------------------------------------------------------------
     * .rodata section: Read-only data (placed in IMEM)
     * ----------------------------------------------------------------- */
    .rodata : ALIGN(4)
    {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > IMEM

    /* -----------------------------------------------------------------
     * .data section: Initialized data
     * Stored in IMEM (ROM), copied to DMEM (RAM) at startup
     * ----------------------------------------------------------------- */
    .data : ALIGN(4)
    {
        _data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)

        /* Global pointer anchor (for linker relaxation) */
        . = ALIGN(4);
        PROVIDE(__global_pointer$ = . + 0x800);

        . = ALIGN(4);
        _data_end = .;
    } > DMEM AT > IMEM

    /* -----------------------------------------------------------------
     * .bss section: Uninitialized data (zero-cleared at startup)
     * ----------------------------------------------------------------- */
    .bss (NOLOAD) : ALIGN(4)
    {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DMEM

    /* -----------------------------------------------------------------
     * .stack section: Stack area
     * ----------------------------------------------------------------- */
    .stack (NOLOAD) : ALIGN(16)
    {
        _stack_bottom = .;
        . += 4K;
        _stack_top = .;
    } > DMEM

    /* -----------------------------------------------------------------
     * .trap_stack section: Separate stack for trap/interrupt handlers
     * Used via mscratch register swap in _trap_handler
     * ----------------------------------------------------------------- */
    .trap_stack (NOLOAD) : ALIGN(16)
    {
        _trap_stack_bottom = .;
        . += 1K;
        _trap_stack_top = .;
    } > DMEM

    /* -----------------------------------------------------------------
     * .heap section: Heap area
     * ----------------------------------------------------------------- */
    .heap (NOLOAD) : ALIGN(4)
    {
        _heap_start = .;
        . += 4K;
        _heap_end = .;
    } > DMEM

    /* -----------------------------------------------------------------
     * Load address for .data section (used by startup code)
     * ----------------------------------------------------------------- */
    _data_load = LOADADDR(.data);

    /* -----------------------------------------------------------------
     * End of used memory marker
     * ----------------------------------------------------------------- */
    _end = .;
    PROVIDE(end = .);

    /* -----------------------------------------------------------------
     * Discard debug sections to save space
     * ----------------------------------------------------------------- */
    /DISCARD/ :
    {
        *(.comment)
        *(.note.*)
    }
}
