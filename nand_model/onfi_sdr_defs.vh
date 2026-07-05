`ifndef ONFI_SDR_DEFS_VH
`define ONFI_SDR_DEFS_VH

// Purpose: Shared ONFI SDR decode operation and error encodings.
// Role: Synthesizable RTL include.
// Related design docs:
// - design_spec/SIMPLE_ONFI_SDR_decode_fsm.md
// - design_spec/nand_adapter_contracts.md
// Block contract: Keep decode core, adapter, and testbench encodings aligned.
// File version: v0.1
// Revision history:
// - v0.1: Initial shared constants for Decode FSM bring-up.

`define ONFI_OP_NONE         4'd0
`define ONFI_OP_RESET        4'd1
`define ONFI_OP_READ_ID      4'd2
`define ONFI_OP_READ_STATUS  4'd3
`define ONFI_OP_READ_PAGE    4'd4
`define ONFI_OP_PROGRAM      4'd5
`define ONFI_OP_ERASE        4'd6
`define ONFI_OP_UNSUPPORTED  4'd15

`define ONFI_ERR_NONE              4'd0
`define ONFI_ERR_INVALID_BUS       4'd1
`define ONFI_ERR_UNSUPPORTED_CMD   4'd2
`define ONFI_ERR_UNEXPECTED_ADDR   4'd3
`define ONFI_ERR_BAD_CONFIRM       4'd4
`define ONFI_ERR_UNEXPECTED_DATA   4'd5
`define ONFI_ERR_BUSY_ILLEGAL_CMD  4'd6
`define ONFI_ERR_PAGE_OVERFLOW     4'd7
`define ONFI_ERR_PB_NOT_READY      4'd8

`endif
