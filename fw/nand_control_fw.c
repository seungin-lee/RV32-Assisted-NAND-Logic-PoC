/* Purpose: Human-readable C control firmware for the NAND PicoRV32 path.
 * Role: Firmware logic, executed from the RV32 control agent SRAM.
 * Related design docs:
 * - design_spec/nand_control_fw.md
 * - design_spec/nand_register_bank.md
 * - design_spec/nand_model_vpl.md
 * Block contract: Reads Register Bank IRQ/mailbox MMIO, dispatches host
 * commands, writes readout/VPL control registers, and clears handled W1C
 * status bits without touching Decode FSM or VPL internals.
 * File version: v0.1
 * Revision history:
 * - v0.1: Initial IRQ-driven C implementation matching the
 *   surrogate FW MMIO sequence.
 */

#include "nand_fw_defs.h"
#include "nand_mmio.h"

struct host_mailbox {
    unsigned int op;
    unsigned int cmd;
    unsigned int addr[5];
    unsigned int addr_count;
    unsigned int data_count;
    unsigned int protocol_error;
    unsigned int protocol_error_code;
};

struct target_addr {
    unsigned int column;
    unsigned int row;
    unsigned int block;
    unsigned int page;
};

static volatile unsigned int current_vpl_op;

static void clear_irq(unsigned int bits)
{
    if (bits != 0u)
        mmio_write32(REG_IRQ_STATUS, bits);
}

static void clear_op_status(unsigned int bits)
{
    if (bits != 0u)
        mmio_write32(REG_OP_STATUS_CLR, bits);
}

static struct host_mailbox read_host_mailbox(void)
{
    struct host_mailbox host;
    unsigned int meta;

    (void)mmio_read32(REG_HOST_EVENT);
    meta = mmio_read32(REG_HOST_META);

    host.op = meta & 0x0fu;
    host.addr_count = (meta >> 4) & 0x07u;
    host.protocol_error = (meta >> 7) & 0x01u;
    host.protocol_error_code = (meta >> 8) & 0x0fu;
    host.cmd = mmio_read32(REG_HOST_CMD) & 0xffu;
    host.addr[0] = mmio_read32(REG_HOST_ADDR0) & 0xffu;
    host.addr[1] = mmio_read32(REG_HOST_ADDR1) & 0xffu;
    host.addr[2] = mmio_read32(REG_HOST_ADDR2) & 0xffu;
    host.addr[3] = mmio_read32(REG_HOST_ADDR3) & 0xffu;
    host.addr[4] = mmio_read32(REG_HOST_ADDR4) & 0xffu;
    host.data_count = mmio_read32(REG_HOST_DATA_COUNT) & 0x1fffu;

    return host;
}

static struct target_addr decode_page_addr(const struct host_mailbox *host)
{
    struct target_addr target;

    target.column = host->addr[0] | (host->addr[1] << 8);
    target.row = host->addr[2] | (host->addr[3] << 8) |
                 (host->addr[4] << 16);
    target.block = target.row >> NAND_PAGE_SHIFT;
    target.page = target.row & NAND_PAGE_MASK;

    return target;
}

static struct target_addr decode_erase_addr(const struct host_mailbox *host)
{
    struct target_addr target;

    target.column = 0u;
    target.row = host->addr[0] | (host->addr[1] << 8) |
                 (host->addr[2] << 16);
    target.block = target.row >> NAND_PAGE_SHIFT;
    target.page = target.row & NAND_PAGE_MASK;

    return target;
}

static void setup_read_bias(void)
{
    mmio_write32(REG_VREAD_LEVEL, 1u);
    mmio_write32(REG_VPASS_LEVEL, 1u);
    mmio_write32(REG_BL_CTRL, 3u);
    mmio_write32(REG_WL_CTRL, 0x11u);
    mmio_write32(REG_LINE_CTRL, 0x0fu);
    mmio_write32(REG_BIAS_PROFILE, BIAS_READ);
}

static void setup_program_bias(void)
{
    mmio_write32(REG_VPGM_LEVEL, 0x10u);
    mmio_write32(REG_VPASS_LEVEL, 0x0au);
    mmio_write32(REG_BL_CTRL, 4u);
    mmio_write32(REG_WL_CTRL, 0x22u);
    mmio_write32(REG_LINE_CTRL, 0x0fu);
    mmio_write32(REG_BIAS_PROFILE, BIAS_PROGRAM);
}

static void setup_erase_bias(void)
{
    mmio_write32(REG_VERS_LEVEL, 0x14u);
    mmio_write32(REG_BL_CTRL, 0u);
    mmio_write32(REG_WL_CTRL, 0x100u);
    mmio_write32(REG_LINE_CTRL, 0x71u);
    mmio_write32(REG_BIAS_PROFILE, BIAS_ERASE);
}

static void start_vpl_op(const struct target_addr *target,
                         unsigned int opcode,
                         unsigned int options)
{
    mmio_write32(REG_BLOCK_SEL, target->block);
    mmio_write32(REG_PAGE_SEL, target->page);
    mmio_write32(REG_COL_SEL, target->column);
    mmio_write32(REG_OP_CTRL, options | opcode);
    mmio_write32(REG_OP_TRIGGER, 1u);
}

static void handle_reset(void)
{
    current_vpl_op = ONFI_OP_RESET;
    mmio_write32(REG_READOUT_CTRL, READOUT_NONE);
    clear_op_status(OP_CLR_DONE | OP_CLR_ERROR |
                    OP_CLR_PB_VALID | OP_CLR_PB_PROG);
    clear_irq(IRQ_HOST_CMD);
}

static void handle_read_id(void)
{
    current_vpl_op = ONFI_OP_READ_ID;
    mmio_write32(REG_READOUT_CTRL, READOUT_ENABLE | READOUT_READ_ID);
    clear_irq(IRQ_HOST_CMD);
}

static void handle_read_status(void)
{
    current_vpl_op = ONFI_OP_READ_STATUS;
    mmio_write32(REG_READOUT_CTRL, READOUT_ENABLE | READOUT_READ_STATUS);
    clear_irq(IRQ_HOST_CMD);
}

static void handle_read_page(const struct host_mailbox *host)
{
    struct target_addr target = decode_page_addr(host);

    setup_read_bias();
    start_vpl_op(&target, VPL_OP_READ_PAGE,
                 OP_OPT_IRQ_DONE_EN | OP_OPT_BIAS_CHECK_EN);
    current_vpl_op = ONFI_OP_READ_PAGE;
    clear_irq(IRQ_HOST_CMD);
}

static void handle_program(const struct host_mailbox *host)
{
    unsigned int op_status = mmio_read32(REG_OP_STATUS);
    struct target_addr target = decode_page_addr(host);

    if ((op_status & OP_STATUS_PB_READY) == 0u ||
        (op_status & OP_STATUS_PB_OVERFLOW) != 0u) {
        clear_irq(IRQ_HOST_CMD);
        return;
    }

    setup_program_bias();
    start_vpl_op(&target, VPL_OP_PROGRAM_PAGE,
                 OP_OPT_IRQ_DONE_EN | OP_OPT_IRQ_ERROR_EN |
                 OP_OPT_WP_CHECK_EN | OP_OPT_BIAS_CHECK_EN |
                 OP_OPT_STRICT_PROGRAM);
    current_vpl_op = ONFI_OP_PROGRAM;
    clear_irq(IRQ_HOST_CMD);
}

static void handle_erase(const struct host_mailbox *host)
{
    struct target_addr target = decode_erase_addr(host);

    setup_erase_bias();
    start_vpl_op(&target, VPL_OP_ERASE_BLOCK,
                 OP_OPT_IRQ_DONE_EN | OP_OPT_IRQ_ERROR_EN |
                 OP_OPT_WP_CHECK_EN | OP_OPT_BIAS_CHECK_EN);
    current_vpl_op = ONFI_OP_ERASE;
    clear_irq(IRQ_HOST_CMD);
}

static void handle_host_command(void)
{
    struct host_mailbox host = read_host_mailbox();

    if (host.protocol_error != 0u) {
        clear_irq(IRQ_HOST_CMD);
        return;
    }

    switch (host.op) {
    case ONFI_OP_RESET:
        handle_reset();
        break;
    case ONFI_OP_READ_ID:
        handle_read_id();
        break;
    case ONFI_OP_READ_STATUS:
        handle_read_status();
        break;
    case ONFI_OP_READ_PAGE:
        handle_read_page(&host);
        break;
    case ONFI_OP_PROGRAM:
        handle_program(&host);
        break;
    case ONFI_OP_ERASE:
        handle_erase(&host);
        break;
    default:
        clear_irq(IRQ_HOST_CMD);
        break;
    }
}

static void handle_vpl_result(unsigned int pending)
{
    unsigned int op_status = mmio_read32(REG_OP_STATUS);
    (void)mmio_read32(REG_OP_ERROR);
    (void)mmio_read32(REG_NAND_STATUS);

    if ((op_status & OP_STATUS_DONE) != 0u &&
        (op_status & OP_STATUS_ERROR) == 0u &&
        current_vpl_op == ONFI_OP_READ_PAGE) {
        mmio_write32(REG_READOUT_CTRL, READOUT_ENABLE | READOUT_PAGE_BUFFER);
    }

    {
        unsigned int clear = 0u;

        if ((op_status & OP_STATUS_DONE) != 0u)
            clear |= OP_CLR_DONE;
        if ((op_status & OP_STATUS_ERROR) != 0u)
            clear |= OP_CLR_ERROR;
        if ((op_status & OP_STATUS_PB_VALID) != 0u)
            clear |= OP_CLR_PB_VALID;
        if ((op_status & OP_STATUS_DONE) != 0u &&
            (op_status & OP_STATUS_ERROR) == 0u &&
            current_vpl_op == ONFI_OP_PROGRAM)
            clear |= OP_CLR_PB_PROG;

        clear_op_status(clear);
    }

    clear_irq(pending & (IRQ_OP_DONE | IRQ_OP_ERROR));
    current_vpl_op = ONFI_OP_NONE;
}

void nand_fw_irq_handler(void)
{
    unsigned int pending = mmio_read32(REG_IRQ_STATUS) & IRQ_ALL;

    if ((pending & IRQ_HOST_CMD) != 0u)
        handle_host_command();

    if ((pending & (IRQ_OP_DONE | IRQ_OP_ERROR)) != 0u)
        handle_vpl_result(pending);
}

void nand_fw_main(void)
{
    current_vpl_op = ONFI_OP_NONE;
    mmio_write32(REG_IRQ_ENABLE, IRQ_ALL);

    for (;;)
        ;
}
