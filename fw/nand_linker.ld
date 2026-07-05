/* Purpose: Linker script for the NAND PicoRV32 control firmware.
 * Role: Firmware build configuration.
 * Related design docs:
 * - design_spec/nand_control_fw.md
 * - design_spec/Architecture.md
 * Block contract: Places text/rodata/data/bss into the RV32 agent SRAM image
 * and defines stack/BSS symbols consumed by fw/nand_startup.S.
 * File version: v0.1
 * Revision history:
 * - v0.1: Initial 32 KiB SRAM image layout for RV32 FW.
 */

MEMORY
{
    ram (rwx) : ORIGIN = 0x00000000, LENGTH = 0x00008000
}

SECTIONS
{
    .text : {
        *(.text.start)
        *(.text*)
    } > ram

    .rodata : {
        *(.rodata*)
    } > ram

    .data : {
        *(.data*)
    } > ram

    .bss : {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } > ram

    . = ALIGN(16);
    __stack_top = ORIGIN(ram) + LENGTH(ram);
}
