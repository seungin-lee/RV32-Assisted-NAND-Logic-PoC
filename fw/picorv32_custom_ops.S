/*
 * Purpose: PicoRV32 custom IRQ instruction macros used by NAND RV32 startup.
 * Role: Firmware assembly include.
 * Related design docs:
 * - design_spec/nand_picorv32.md
 * - design_spec/nand_control_fw.md
 * Block contract: Provides maskirq/retirq encoding macros expected by
 * fw/nand_startup.S.
 * File version: v0.1
 * Revision history:
 * - v0.1: Import PicoRV32 custom op macros into NAND repository.
 */

// Minimal PicoRV32 custom IRQ instruction macros.

#define regnum_zero 0

#define r_type_insn(_f7, _rs2, _rs1, _f3, _rd, _opc) \
.word (((_f7) << 25) | ((_rs2) << 20) | ((_rs1) << 15) | ((_f3) << 12) | ((_rd) << 7) | ((_opc) << 0))

#define picorv32_retirq_insn() \
r_type_insn(0b0000010, 0, 0, 0b000, 0, 0b0001011)

#define picorv32_maskirq_insn(_rd, _rs) \
r_type_insn(0b0000011, 0, regnum_ ## _rs, 0b110, regnum_ ## _rd, 0b0001011)
