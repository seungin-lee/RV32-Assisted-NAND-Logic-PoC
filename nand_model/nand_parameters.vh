`ifndef NAND_PARAMETERS_VH
`define NAND_PARAMETERS_VH

// -----------------------------------------------------------------------------
// NAND Model Parameters
// -----------------------------------------------------------------------------
// Purpose: Central parameter include for SIMPLE NAND model geometry, timing, and
// reusable host-testbench timing guards.
// Role: RTL/TB shared Verilog include.
// Related design docs:
// - design_spec/SIMPLE_ONFI_SDR_behavior_model_reference.md
// - design_spec/host_tb_traffice_scenario.md
// - design_spec/nand_cell_operation.md
// File version: v0.1
// Revision history:
// - v0.1: Renamed from nand_cell_parameters.vh and expanded into
//   a model-wide parameter header for geometry and SDR Mode 0 timing.

// Reference simulation clock used by current SIMPLE model and host TB flows.
`define NAND_SYS_CLK_PERIOD_NS 10

// Geometry: SLC, single-die, single-LUN, single-plane.
`define NAND_PAGE_SIZE        2048
`define NAND_PAGES_PER_BLOCK  64
`define NAND_NUM_BLOCKS       32
`define NAND_TOTAL_PAGES      (`NAND_PAGES_PER_BLOCK * `NAND_NUM_BLOCKS)

// Address-cycle contract for supported SIMPLE ONFI commands.
`define NAND_READ_ID_ADDR_CYCLES 1
`define NAND_PAGE_ADDR_CYCLES  5
`define NAND_ERASE_ADDR_CYCLES 3

// SDR Timing Mode 0 host-interface limits used by TB/checker guards.
`define NAND_T_WC_NS   100
`define NAND_T_RC_NS   100
`define NAND_T_WHR_NS  120
`define NAND_T_ADL_NS  400
`define NAND_T_RR_NS   20
`define NAND_T_WB_NS   200

// Approximate operation timings for behavioral simulation.
`define NAND_T_RST_NS  5000
`define NAND_T_R_NS    25000
`define NAND_T_PROG_NS 200000
`define NAND_T_BERS_NS 1000000

`define NAND_NS_TO_CYCLES(ns) (((ns) + `NAND_SYS_CLK_PERIOD_NS - 1) / `NAND_SYS_CLK_PERIOD_NS)

`define NAND_T_WC_CYCLES   `NAND_NS_TO_CYCLES(`NAND_T_WC_NS)
`define NAND_T_RC_CYCLES   `NAND_NS_TO_CYCLES(`NAND_T_RC_NS)
`define NAND_T_WHR_CYCLES  `NAND_NS_TO_CYCLES(`NAND_T_WHR_NS)
`define NAND_T_ADL_CYCLES  `NAND_NS_TO_CYCLES(`NAND_T_ADL_NS)
`define NAND_T_RR_CYCLES   `NAND_NS_TO_CYCLES(`NAND_T_RR_NS)
`define NAND_T_WB_CYCLES   `NAND_NS_TO_CYCLES(`NAND_T_WB_NS)
`define NAND_T_RST_CYCLES  `NAND_NS_TO_CYCLES(`NAND_T_RST_NS)
`define NAND_T_R_CYCLES    `NAND_NS_TO_CYCLES(`NAND_T_R_NS)
`define NAND_T_PROG_CYCLES `NAND_NS_TO_CYCLES(`NAND_T_PROG_NS)
`define NAND_T_BERS_CYCLES `NAND_NS_TO_CYCLES(`NAND_T_BERS_NS)

// Backward-compatible aliases for older SIMPLE behavioral files/docs.
`define SIMPLE_PAGE_SIZE        `NAND_PAGE_SIZE
`define SIMPLE_PAGES_PER_BLOCK  `NAND_PAGES_PER_BLOCK
`define SIMPLE_NUM_BLOCKS       `NAND_NUM_BLOCKS
`define SIMPLE_TOTAL_PAGES      `NAND_TOTAL_PAGES
`define T_RST_NS                `NAND_T_RST_NS
`define T_R_NS                  `NAND_T_R_NS
`define T_PROG_NS               `NAND_T_PROG_NS
`define T_BERS_NS               `NAND_T_BERS_NS
`define T_WHR_NS                `NAND_T_WHR_NS

`endif
