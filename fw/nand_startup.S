/* Purpose: PicoRV32 reset/IRQ startup veneer for C NAND control firmware.
 * Role: Firmware assembly glue.
 * Related design docs:
 * - design_spec/nand_control_fw.md
 * - design_spec/nand_picorv32.md
 * Block contract: Provides reset vector, IRQ vector, BSS clear, stack setup,
 * C entry call, and register save/restore around the C IRQ handler.
 * File version: v0.2
 * Revision history:
 * - v0.2: Update PicoRV32 reference to NAND-owned integration doc.
 * - v0.1: Initial reset vector, BSS clear, C entry, and IRQ veneer.
 */

#include "picorv32_custom_ops.S"

    .option norvc
    .option norelax
    .section .text.start
    .global _start

_start:
    j reset_entry

    .org 0x10
    j irq_entry

reset_entry:
    la sp, __stack_top

    la t0, __bss_start
    la t1, __bss_end
clear_bss:
    bgeu t0, t1, clear_bss_done
    sw zero, 0(t0)
    addi t0, t0, 4
    j clear_bss

clear_bss_done:
    picorv32_maskirq_insn(zero, zero)
    call nand_fw_main

reset_halt:
    j reset_halt

irq_entry:
    addi sp, sp, -128
    sw ra,   0(sp)
    sw gp,   4(sp)
    sw tp,   8(sp)
    sw t0,  12(sp)
    sw t1,  16(sp)
    sw t2,  20(sp)
    sw s0,  24(sp)
    sw s1,  28(sp)
    sw a0,  32(sp)
    sw a1,  36(sp)
    sw a2,  40(sp)
    sw a3,  44(sp)
    sw a4,  48(sp)
    sw a5,  52(sp)
    sw a6,  56(sp)
    sw a7,  60(sp)
    sw s2,  64(sp)
    sw s3,  68(sp)
    sw s4,  72(sp)
    sw s5,  76(sp)
    sw s6,  80(sp)
    sw s7,  84(sp)
    sw s8,  88(sp)
    sw s9,  92(sp)
    sw s10, 96(sp)
    sw s11, 100(sp)
    sw t3,  104(sp)
    sw t4,  108(sp)
    sw t5,  112(sp)
    sw t6,  116(sp)

    call nand_fw_irq_handler

    lw ra,   0(sp)
    lw gp,   4(sp)
    lw tp,   8(sp)
    lw t0,  12(sp)
    lw t1,  16(sp)
    lw t2,  20(sp)
    lw s0,  24(sp)
    lw s1,  28(sp)
    lw a0,  32(sp)
    lw a1,  36(sp)
    lw a2,  40(sp)
    lw a3,  44(sp)
    lw a4,  48(sp)
    lw a5,  52(sp)
    lw a6,  56(sp)
    lw a7,  60(sp)
    lw s2,  64(sp)
    lw s3,  68(sp)
    lw s4,  72(sp)
    lw s5,  76(sp)
    lw s6,  80(sp)
    lw s7,  84(sp)
    lw s8,  88(sp)
    lw s9,  92(sp)
    lw s10, 96(sp)
    lw s11, 100(sp)
    lw t3,  104(sp)
    lw t4,  108(sp)
    lw t5,  112(sp)
    lw t6,  116(sp)
    addi sp, sp, 128

    picorv32_retirq_insn()
