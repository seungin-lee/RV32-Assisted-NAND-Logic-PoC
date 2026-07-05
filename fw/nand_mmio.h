/* Purpose: MMIO register definitions for the NAND PicoRV32 control firmware.
 * Role: Firmware C header.
 * Related design docs:
 * - design_spec/nand_register_bank.md
 * Block contract: Mirrors the Register Bank public 32-bit MMIO offsets and
 * provides volatile word read/write helpers for freestanding C firmware.
 * File version: v0.2
 * Revision history:
 * - v0.2: Add REG_PAGE_BYTES and REG_OP_LATENCY offsets so the
 *   firmware header mirrors the public Register Bank map.
 * - v0.1: Initial Register Bank address map for RV32 FW.
 */

#ifndef NAND_MMIO_H
#define NAND_MMIO_H

#ifndef NAND_REG_BASE
#define NAND_REG_BASE 0x02000000u
#endif

#define REG_HOST_CMD        (NAND_REG_BASE + 0x00u)
#define REG_HOST_ADDR0      (NAND_REG_BASE + 0x04u)
#define REG_HOST_ADDR1      (NAND_REG_BASE + 0x08u)
#define REG_HOST_ADDR2      (NAND_REG_BASE + 0x0cu)
#define REG_HOST_ADDR3      (NAND_REG_BASE + 0x10u)
#define REG_HOST_ADDR4      (NAND_REG_BASE + 0x14u)
#define REG_HOST_META       (NAND_REG_BASE + 0x18u)
#define REG_HOST_EVENT      (NAND_REG_BASE + 0x1cu)
#define REG_NAND_STATUS     (NAND_REG_BASE + 0x20u)
#define REG_IRQ_STATUS      (NAND_REG_BASE + 0x24u)
#define REG_IRQ_ENABLE      (NAND_REG_BASE + 0x28u)
#define REG_HOST_DATA_COUNT (NAND_REG_BASE + 0x2cu)
#define REG_BLOCK_SEL       (NAND_REG_BASE + 0x30u)
#define REG_PAGE_SEL        (NAND_REG_BASE + 0x34u)
#define REG_COL_SEL         (NAND_REG_BASE + 0x38u)
#define REG_PAGE_BYTES      (NAND_REG_BASE + 0x3cu)
#define REG_OP_CTRL         (NAND_REG_BASE + 0x40u)
#define REG_OP_TRIGGER      (NAND_REG_BASE + 0x44u)
#define REG_OP_STATUS       (NAND_REG_BASE + 0x48u)
#define REG_OP_STATUS_CLR   (NAND_REG_BASE + 0x4cu)
#define REG_OP_ERROR        (NAND_REG_BASE + 0x50u)
#define REG_OP_LATENCY      (NAND_REG_BASE + 0x54u)
#define REG_READOUT_CTRL    (NAND_REG_BASE + 0x58u)
#define REG_VREAD_LEVEL     (NAND_REG_BASE + 0x60u)
#define REG_VPGM_LEVEL      (NAND_REG_BASE + 0x64u)
#define REG_VPASS_LEVEL     (NAND_REG_BASE + 0x68u)
#define REG_VERS_LEVEL      (NAND_REG_BASE + 0x6cu)
#define REG_BL_CTRL         (NAND_REG_BASE + 0x70u)
#define REG_WL_CTRL         (NAND_REG_BASE + 0x74u)
#define REG_LINE_CTRL       (NAND_REG_BASE + 0x78u)
#define REG_BIAS_PROFILE    (NAND_REG_BASE + 0x7cu)

static inline unsigned int mmio_read32(unsigned int addr)
{
    return *(volatile unsigned int *)addr;
}

static inline void mmio_write32(unsigned int addr, unsigned int data)
{
    *(volatile unsigned int *)addr = data;
}

#endif
