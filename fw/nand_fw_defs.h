/* Purpose: Shared constants for the NAND PicoRV32 control firmware.
 * Role: Firmware C header.
 * Related design docs:
 * - design_spec/nand_control_fw.md
 * - design_spec/nand_register_bank.md
 * Block contract: Keeps FW-local opcode, geometry, IRQ, readout, and VPL
 * option constants aligned with the Register Bank and control FW documents.
 * File version: v0.1
 * Revision history:
 * - v0.1: Initial opcode, IRQ, readout, and geometry constants.
 */

#ifndef NAND_FW_DEFS_H
#define NAND_FW_DEFS_H

#define NAND_PAGE_SIZE        2048u
#define NAND_PAGES_PER_BLOCK  64u
#define NAND_PAGE_SHIFT       6u
#define NAND_PAGE_MASK        0x3fu

#define ONFI_OP_NONE          0u
#define ONFI_OP_RESET         1u
#define ONFI_OP_READ_ID       2u
#define ONFI_OP_READ_STATUS   3u
#define ONFI_OP_READ_PAGE     4u
#define ONFI_OP_PROGRAM       5u
#define ONFI_OP_ERASE         6u
#define ONFI_OP_UNSUPPORTED   15u

#define VPL_OP_NONE           0u
#define VPL_OP_READ_PAGE      1u
#define VPL_OP_PROGRAM_PAGE   2u
#define VPL_OP_ERASE_BLOCK    3u

#define BIAS_NONE             0u
#define BIAS_READ             1u
#define BIAS_PROGRAM          2u
#define BIAS_ERASE            3u

#define READOUT_NONE          0u
#define READOUT_READ_ID       1u
#define READOUT_READ_STATUS   2u
#define READOUT_PAGE_BUFFER   3u
#define READOUT_ENABLE        4u

#define IRQ_HOST_CMD          0x1u
#define IRQ_OP_DONE           0x2u
#define IRQ_OP_ERROR          0x4u
#define IRQ_ALL               (IRQ_HOST_CMD | IRQ_OP_DONE | IRQ_OP_ERROR)

#define OP_STATUS_BUSY        0x01u
#define OP_STATUS_DONE        0x02u
#define OP_STATUS_ERROR       0x04u
#define OP_STATUS_PB_VALID    0x08u
#define OP_STATUS_PB_READY    0x10u
#define OP_STATUS_PB_OVERFLOW 0x20u

#define OP_CLR_DONE           0x1u
#define OP_CLR_ERROR          0x2u
#define OP_CLR_PB_VALID       0x4u
#define OP_CLR_PB_PROG        0x8u

#define OP_OPT_STRICT_PROGRAM 0x00000100u
#define OP_OPT_BIAS_CHECK_EN  0x00000200u
#define OP_OPT_WP_CHECK_EN    0x00000400u
#define OP_OPT_IRQ_DONE_EN    0x00010000u
#define OP_OPT_IRQ_ERROR_EN   0x00020000u

#endif
