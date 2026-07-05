# Simple NAND model demo Makefile

BUILD_DIR := build/nand
VVP       := vvp
IVERILOG  := iverilog
YOSYS     := yosys
YOSYS_SMTBMC ?= yosys-smtbmc
SMTBMC_SOLVER ?= z3
SBY ?= python3 tools/sby/sbysrc/sby.py
RISCV_TOOLCHAIN_PREFIX ?= /tools/riscv/bin/riscv64-unknown-elf-

IVERILOG_FLAGS := -g2005-sv -I nand_model
RV32_CFLAGS := -nostdlib -ffreestanding -fno-builtin -fno-pic \
	-msmall-data-limit=0 -mabi=ilp32 -march=rv32i -Os -Wall
RV32_LDFLAGS := -Wl,-T,fw/nand_linker.ld -Wl,--no-relax \
	-Wl,--no-warn-rwx-segments \
	-Wl,-Map=$(BUILD_DIR)/nand_control_fw.map

NAND_RTL := $(sort $(wildcard nand_model/*.v nand_model/*.sv))
NAND_INCLUDES := nand_model/nand_parameters.vh nand_model/onfi_sdr_defs.vh
NAND_CDC_RTL := nand_model/cdc_level_sync.sv nand_model/cdc_valid_ack.sv
NAND_CDC_TOP := nand_model/external_event_adapter.sv

# Generic TB selection. Examples:
#   make sim TB=tb_nand_page_buffer
#   make sim TB=tb/tb_pin_sync_edge_detect.v
#   make sim-rv32 TB=tb_nand_logic_top_e2e
TB ?= tb_nand_logic_top_e2e
TB_TOP := $(basename $(notdir $(TB)))

.DEFAULT_GOAL := sim

.PHONY: sim sim-rv32 fw top top-rv32 cdc-lint cdc-formal cdc-formal-sby clean

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/nand_control_fw.elf: fw/nand_startup.S fw/nand_control_fw.c fw/nand_mmio.h fw/nand_fw_defs.h fw/nand_linker.ld fw/picorv32_custom_ops.S | $(BUILD_DIR)
	$(RISCV_TOOLCHAIN_PREFIX)gcc $(RV32_CFLAGS) -I fw $(RV32_LDFLAGS) -o $@ fw/nand_startup.S fw/nand_control_fw.c

$(BUILD_DIR)/nand_control_fw.bin: $(BUILD_DIR)/nand_control_fw.elf
	$(RISCV_TOOLCHAIN_PREFIX)objcopy -O binary $< $@

$(BUILD_DIR)/nand_control_fw.hex: $(BUILD_DIR)/nand_control_fw.bin
	python3 scripts/makehex.py $< 8192 > $@

fw: $(BUILD_DIR)/nand_control_fw.hex

$(BUILD_DIR)/%.vvp: tb/%.v $(NAND_RTL) $(NAND_INCLUDES) Makefile | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -s $* -o $@ $< $(NAND_RTL)

$(BUILD_DIR)/%.vvp: tb/%.sv $(NAND_RTL) $(NAND_INCLUDES) Makefile | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -s $* -o $@ $< $(NAND_RTL)

$(BUILD_DIR)/%_rv32.vvp: tb/%.v $(NAND_RTL) $(NAND_INCLUDES) $(BUILD_DIR)/nand_control_fw.hex Makefile | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -DNAND_CONTROL_RV32 -s $* -o $@ $< $(NAND_RTL)

$(BUILD_DIR)/%_rv32.vvp: tb/%.sv $(NAND_RTL) $(NAND_INCLUDES) $(BUILD_DIR)/nand_control_fw.hex Makefile | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -DNAND_CONTROL_RV32 -s $* -o $@ $< $(NAND_RTL)

sim: $(BUILD_DIR)/$(TB_TOP).vvp
	$(VVP) $<

sim-rv32: $(BUILD_DIR)/$(TB_TOP)_rv32.vvp
	$(VVP) $<

top: $(NAND_RTL) $(NAND_INCLUDES) Makefile | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -s nand_logic_top -o $(BUILD_DIR)/nand_logic_top_check.vvp $(NAND_RTL)

top-rv32: $(NAND_RTL) $(NAND_INCLUDES) $(BUILD_DIR)/nand_control_fw.hex Makefile | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -DNAND_CONTROL_RV32 -s nand_logic_top -o $(BUILD_DIR)/nand_logic_top_rv32_check.vvp $(NAND_RTL)

cdc-lint: $(NAND_CDC_RTL) $(NAND_CDC_TOP) | $(BUILD_DIR)
	$(YOSYS) -p "read_verilog -sv $(NAND_CDC_RTL) $(NAND_CDC_TOP); hierarchy -top external_event_adapter; proc; check"

$(BUILD_DIR)/cdc_valid_ack_formal.smt2: formal/cdc_valid_ack_formal.sv nand_model/cdc_valid_ack.sv | $(BUILD_DIR)
	$(YOSYS) -p "read_verilog -formal -sv formal/cdc_valid_ack_formal.sv nand_model/cdc_valid_ack.sv; prep -top cdc_valid_ack_formal; write_smt2 -wires $@"

cdc-formal: $(BUILD_DIR)/cdc_valid_ack_formal.smt2
	PATH=$(HOME)/.local/bin:$$PATH $(YOSYS_SMTBMC) -s $(SMTBMC_SOLVER) -t 32 $<

cdc-formal-sby: formal/cdc_valid_ack.sby formal/cdc_valid_ack_formal.sv nand_model/cdc_valid_ack.sv | $(BUILD_DIR)
	@if [ ! -f tools/sby/sbysrc/sby.py ]; then \
		echo "ERROR: tools/sby SymbiYosys submodule is not initialized."; \
		echo "Run: git submodule update --init tools/sby"; \
		echo "Then retry, or run: bash scripts/install_deps.sh"; \
		exit 1; \
	fi
	PATH=$(HOME)/.local/bin:$$PATH $(SBY) -f -d $(BUILD_DIR)/sby_cdc_valid_ack formal/cdc_valid_ack.sby

clean:
	rm -rf build simv *.vcd
