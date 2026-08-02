# NAND RTL/TB/FW File Index
Version: v0.34
Status: active

이 문서는 RTL/TB/FW 파일 위치와 한 줄 역할을 빠르게 찾기 위한 index다. 상세
architecture와 block contract는 `Architecture.md` 및 각 설계 문서를 따른다.

## RTL / Include Files

| File | Block | 역할 | 관련 설계 문서 |
| --- | --- | --- | --- |
| `nand_model/onfi_sdr_defs.vh` | Decode FSM / Adapter | ONFI decode opcode/error encoding 공유 include | `SIMPLE_ONFI_SDR_decode_fsm.md`, `nand_adapter_contracts.md` |
| `nand_model/nand_parameters.vh` | Shared parameter include | SIMPLE NAND geometry, SDR Mode 0 timing, host TB timing guard, address-cycle macro의 canonical include | `SIMPLE_ONFI_SDR_behavior_model_reference.md`, `host_tb_traffice_scenario.md`, `SIMPLE_ONFI_SDR_decode_fsm.md` |
| `nand_model/pin_sync_edge_detect.v` | Generic sync IP | ONFI 의미를 모르는 범용 multi-bit 2FF synchronizer와 rise/fall edge detector | `SIMPLE_ONFI_SDR_decode_fsm.md`, `nand_cdc_ip.md` |
| `nand_model/onfi_sdr_decode_fsm.v` | Decode FSM | registered-output hybrid FSM으로 synchronized write-side pin-level 입력을 내부 bus event로 classify하고 transaction event/program data stream으로 decode | `SIMPLE_ONFI_SDR_decode_fsm.md`, `FSM_RTL_Design_Guide.md` |
| `nand_model/nand_role_adapters.v` | Reusable / Role Adapters | parameterized CDC wrapper, Host Event CDC plus busy mirror, Host Pin Status `wp_n` mirror, Page Buffer control/status CDC, VPL Command/Response, Read Output Mirror source/status/ID snapshot adapter | `nand_adapter_contracts.md`, `Architecture.md` |
| `nand_model/nand_page_buffer.v` | Page Buffer | sysclk domain program data direct input, VPL direct read/write port, Read Output direct read port, storage, internal write count, freeze/prog_ready, overflow, clear handling | `nand_page_buffer.md`, `Architecture.md`, `nand_adapter_contracts.md` |
| `nand_model/nand_read_output_datapath.v` | Read Output Datapath | sysclk Read ID/Status/Page Buffer source mux, RE# fall 기반 DQ output, RE# rise 기반 DQ release, read pointer handling | `nand_read_output_datapath.md`, `nand_register_bank.md`, `Architecture.md` |
| `nand_model/onfi_sdr_decode_frontend.v` | Decode front-end wrapper | 범용 pin sync와 Decode FSM을 묶고 raw transaction/program stream handoff와 Read Output Datapath용 synchronized RE# edge pulse를 노출하는 frontend top | `Architecture.md`, `SIMPLE_ONFI_SDR_decode_fsm.md`, `nand_adapter_contracts.md`, `nand_read_output_datapath.md` |
| `nand_model/cdc_valid_ack.sv` | Reusable CDC IP | multi-bit payload valid/ack CDC primitive | `nand_cdc_ip.md`, `nand_adapter_contracts.md` |
| `nand_model/cdc_level_sync.sv` | Reusable CDC IP | single-bit level 2FF synchronizer | `nand_cdc_ip.md`, `nand_adapter_contracts.md` |
| `nand_model/external_event_adapter.sv` | Reusable CDC wrapper | external-domain event payload와 optional IRQ level을 destination domain으로 넘기는 generic wrapper | `nand_cdc_ip.md`, `nand_adapter_contracts.md` |
| `nand_model/soc_regbank.sv` | Reusable Register Bank IP | parameterized payload capture/W1C/busy-ready/IRQ register bank core | `nand_register_bank.md`, `nand_picorv32.md` |
| `nand_model/picorv32.v` | Vendored RV32 Core IP | PicoRV32 native memory bus/IRQ core copy | `Architecture.md`, `nand_picorv32.md` |
| `nand_model/nand_register_bank.v` | NAND Register Bank | PicoRV32 `soc_regbank`를 재사용해 public NAND MMIO map, host mailbox, IRQ/W1C, VPL command/status/transfer-byte snapshot side effect를 구현 | `nand_register_bank.md`, `nand_control_fw.md`, `nand_model_vpl.md` |
| `nand_model/nand_vpl_executor.v` | VPL Executor | sysclk domain command snapshot accept, range/PB pre-check, latency counter, internal array READ/PROGRAM/ERASE, done/error response를 수행 | `nand_model_vpl.md`, `nand_register_bank.md`, `Architecture.md` |
| `nand_model/nand_surrogate_fw_agent.v` | Surrogate FW agent | Register Bank `cpu_*` MMIO bus와 `irq_o`를 사용하는 simulation-only RV32 FW 대체 behavior model | `nand_control_fw.md`, `nand_register_bank.md` |
| `nand_model/nand_rv32_control_agent.v` | RV32 Control Agent | PicoRV32 core, simulation SRAM firmware image, native-bus SRAM/MMIO decode, Register Bank `cpu_*` bridge, IRQ input, FW-ready indication을 제공 | `Architecture.md`, `nand_picorv32.md`, `nand_control_fw.md`, `nand_register_bank.md` |
| `nand_model/nand_logic_top.v` | NAND Logic Top | clock/reset과 ONFI host-facing pins(`dq` inout, `rb_n` 포함)만 public port로 두고 Decode Frontend, role adapters, Page Buffer, VPL executor, Register Bank, surrogate/RV32 control-agent 선택 구간을 instance하는 current PoC top | `Architecture.md`, `nand_adapter_contracts.md`, `nand_control_fw.md`, `nand_register_bank.md`, `nand_model_vpl.md` |

## Firmware Files

| File | Block | 역할 | 관련 설계 문서 |
| --- | --- | --- | --- |
| `fw/nand_startup.S` | RV32 FW startup | PicoRV32 reset vector, IRQ vector, stack setup, `.bss` clear, C entry, IRQ register save/restore veneer | `nand_control_fw.md`, `nand_picorv32.md` |
| `fw/picorv32_custom_ops.S` | RV32 FW startup include | PicoRV32 `maskirq`/`retirq` custom instruction encoding macro | `nand_picorv32.md`, `nand_control_fw.md` |
| `fw/nand_control_fw.c` | RV32 Control FW | Register Bank IRQ/mailbox MMIO를 읽고 host command를 readout/VPL MMIO sequence로 dispatch하는 readable C firmware | `nand_control_fw.md`, `nand_register_bank.md`, `nand_model_vpl.md` |
| `fw/nand_mmio.h` | RV32 FW MMIO header | Register Bank public offset과 volatile word read/write helper | `nand_register_bank.md` |
| `fw/nand_fw_defs.h` | RV32 FW constants | SIMPLE geometry, ONFI decoded op, VPL op, IRQ, readout, status/clear option constant | `nand_control_fw.md`, `nand_register_bank.md` |
| `fw/nand_linker.ld` | RV32 FW linker script | RV32 agent-local 32 KiB SRAM image layout, `.text/.rodata/.data/.bss`, stack symbol definition | `nand_control_fw.md`, `Architecture.md` |

## Script / Formal Files

| File | 대상 | 역할 | 실행 |
| --- | --- | --- | --- |
| `scripts/makehex.py` | RV32 FW build | firmware binary를 RV32 local SRAM `$readmemh` word hex로 변환 | `make fw` |
| `scripts/install_deps.sh` | Developer setup | build/simulation/formal 기본 의존성(`iverilog`, `yosys`, `z3`, `sby` 등)을 apt와 `tools/sby` submodule source로 설치 | `bash scripts/install_deps.sh` |
| `formal/cdc_valid_ack_formal.sv` | `cdc_valid_ack` | one-in-flight payload, hold stability, ordering property를 확인하는 bounded formal harness | `make cdc-formal` |
| `formal/cdc_valid_ack.sby` | `cdc_valid_ack` | SymbiYosys wrapper | `make cdc-formal-sby` |
| `tools/sby/` | Formal tool submodule | SymbiYosys source를 repo-local tool dependency로 고정 | `git submodule update --init tools/sby` |

## Testbench Files

| File | 대상 | 역할 | 실행 |
| --- | --- | --- | --- |
| `tb/tb_picorv32_core_ez.v` | `picorv32` | firmware/toolchain 없이 vendored PicoRV32 core native memory bus를 확인하는 smoke test | `make sim TB=tb_picorv32_core_ez` |
| `tb/tb_cdc_valid_ack.sv` | `cdc_valid_ack` | async source/destination clock, backpressure, payload ordering/hold stability directed test | `make sim TB=tb_cdc_valid_ack` |
| `tb/tb_external_event_adapter.sv` | `external_event_adapter` | event payload CDC와 optional IRQ level sync directed test | `make sim TB=tb_external_event_adapter` |
| `tb/tb_pin_sync_edge_detect.v` | `pin_sync_edge_detect` | generic sync/edge pulse smoke test | `make sim TB=tb_pin_sync_edge_detect` |
| `tb/tb_onfi_sdr_decode_fsm.v` | `onfi_sdr_decode_fsm` | synchronized write-side pin-level 입력 기준 event hold, address snapshot, program stream smoke test | `make sim TB=tb_onfi_sdr_decode_fsm` |
| `tb/tb_onfi_sdr_decode_frontend.v` | `onfi_sdr_decode_frontend` + role adapters + `nand_page_buffer` | behavior reference/host traffic scenario 기반 Decode frontend + Host Event Adapter + Page Buffer scoreboard test | `make sim TB=tb_onfi_sdr_decode_frontend` |
| `tb/tb_nand_role_adapters.v` | `nand_role_adapters` | Host Event CDC/busy mirror, Host Pin Status `wp_n` mirror, Page Buffer control/status CDC, VPL Command/Response, Read Output Mirror adapter smoke test | `make sim TB=tb_nand_role_adapters` |
| `tb/tb_nand_page_buffer.v` | `nand_page_buffer` | direct program stream handshake, VPL direct read/write port, Read Output direct read port, freeze/prog_ready, clear, overflow smoke test | `make sim TB=tb_nand_page_buffer` |
| `tb/tb_nand_read_output_datapath.v` | `nand_read_output_datapath` + `nand_page_buffer` | Read ID 00h/20h, Read Status, Page Buffer readout source mux smoke test | `make sim TB=tb_nand_read_output_datapath` |
| `tb/tb_nand_vpl_executor.v` | `nand_vpl_executor` | VPL command/response, latency, READ/PROGRAM/ERASE data effect, range/PB status error, response backpressure smoke test | `make sim TB=tb_nand_vpl_executor` |
| `tb/tb_nand_register_bank.v` | `nand_register_bank` | host mailbox/IRQ/W1C, FW MMIO write/read, VPL start/result/transfer-byte snapshot, clear pulse directed smoke test | `make sim TB=tb_nand_register_bank` |
| `tb/tb_nand_surrogate_fw_agent.v` | `nand_surrogate_fw_agent` + `nand_register_bank` | IRQ-driven host mailbox dispatch, readout setup, VPL command start/result cleanup smoke test | `make sim TB=tb_nand_surrogate_fw_agent` |
| `tb/tb_nand_logic_top_e2e.v` | `nand_logic_top` | Host traffic scenario 기반 Decode/Register Bank/control-agent/VPL/Page Buffer/Read Output full-sim. top `dq` inout, actual `rb_n`, tWC/tRC/tWHR/tADL/tRR, DQ release, ID/status/readback scoreboard 확인. `NAND_CONTROL_RV32` build에서는 RV32 trap과 FW-ready 기반 initial ready gate도 관측 | `make sim` / `make sim-rv32` |

## Version History

| Version | Description |
| --- | --- |
| v0.34 | Page Buffer public write monitor/count port 제거에 맞춰 RTL/TB 역할 설명을 internal write count와 handshake scoreboard 기준으로 갱신. |
| v0.33 | Decode FSM/Frontend legacy `wp_n`/`re_n` core input과 `mode_*` output 제거에 맞춰 RTL/TB 역할 설명을 갱신. |
| v0.32 | Makefile alias target 제거에 맞춰 실행 명령을 `sim`, `sim-rv32`, `fw`, `cdc-formal*` 중심으로 갱신. |
| v0.31 | SymbiYosys `tools/sby` tool submodule과 `make test-cdc-formal-sby` target을 인덱싱. |
| v0.30 | 프로젝트 build/simulation/formal 의존성 설치 helper `scripts/install_deps.sh`를 인덱싱. |
| v0.29 | PicoRV32/CDC/register-bank IP를 NAND-owned vendored files로 인덱싱하고 CDC formal/core smoke/script 파일을 추가. |
| v0.28 | 구현 완료 상태에 맞춰 문서 status를 active로 갱신. |
| v0.27 | RV32 control agent, C firmware/startup/linker/header files, RV32 full-sim target과 FW-ready gate 관측을 인덱싱. |
| v0.26 | `nand_logic_top` host-facing public port cleanup, role adapter busy/WP_N mirror, full-sim actual `rb_n`/inout `dq` 관측을 인덱싱. |
| v0.25 | `make full-sim`/`make test-full-sim` target과 `tb_nand_logic_top_e2e.v`의 timing/tWB/DQ release checker 보강을 인덱싱. |
| v0.24 | `tb_nand_logic_top_e2e.v`와 `make test-top-e2e`, Read Output `dq_oe` release 동작을 인덱싱. |
| v0.23 | Read Output Datapath RTL/TB와 Page Buffer readout direct read port를 인덱싱. |
| v0.22 | Register Bank PROGRAM VPL transfer byte snapshot을 `REG_HOST_DATA_COUNT` 기준으로 갱신한 RTL/TB 역할을 인덱싱. |
| v0.21 | Page Buffer VPL direct port, VPL executor internal array READ/PROGRAM/ERASE 구현, 관련 TB coverage를 인덱싱. |
| v0.20 | `nand_vpl_executor.v`와 `tb_nand_vpl_executor.v`를 VPL clocked executor shell 및 smoke TB로 인덱싱. |
| v0.19 | `nand_logic_core.v`를 제거하고 `nand_logic_top.v` 단일 top 내부 control-agent 선택 구조를 인덱싱. |
| v0.18 | `nand_logic_core.v`/`nand_logic_top.v` 구조로 정리하고 legacy monolithic model/include 파일 삭제를 반영. |
| v0.17 | Surrogate FW agent를 `nand_model/`로 이동하고 `nand_logic_top_surrogate.v` PoC wrapper를 인덱싱. |
| v0.16 | Surrogate FW behavior agent와 smoke TB를 인덱싱. |
| v0.15 | `nand_page_buffer.v` 관련 설계 문서로 `nand_page_buffer.md`를 추가 참조. |
| v0.14 | `nand_page_buffer.v`와 `tb_nand_page_buffer.v`를 추가하고 Page Buffer bulk write ownership을 role adapter에서 Page Buffer RTL로 이동. |
| v0.13 | `onfi_sdr_decode_adapter.v`/TB 삭제와 Decode Frontend raw handoff 구조를 반영하고 Host Event/Page Buffer write adapter를 `nand_role_adapters.v`로 통합. |
| v0.12 | `nand_role_adapters.v`와 `tb_nand_role_adapters.v`를 reusable/role adapter RTL 및 smoke test로 인덱싱. |
| v0.11 | `onfi_sdr_decode_adapter.v`, Decode Frontend, adapter TB 설명을 `sys_clk`/`core_clk`와 PB direct write helper 기준으로 갱신. |
| v0.10 | Page Buffer bulk data direct path 설계 방향에 맞춰 당시 `onfi_sdr_decode_adapter.v`/TB 설명을 초기 구현으로 명확화. |
| v0.9 | `nand_adapter_contracts.md` 승격에 맞춰 RTL/TB 관련 adapter 문서 참조를 갱신. |
| v0.8 | `nand_logic_top.v`를 Decode Frontend + Register Bank 상위 integration shell로 인덱싱. |
| v0.7 | `nand_register_bank.v`와 `tb_nand_register_bank.v`를 추가하고 PicoRV32 `soc_regbank.sv` 역할을 실제 재사용 core로 갱신. |
| v0.6 | PicoRV32 `soc_regbank.sv`를 NAND Register Bank 구현 시 재사용 후보 IP로 인덱싱. |
| v0.5 | `nand_cell_parameters.vh`를 `nand_parameters.vh`로 교체하고 공유 geometry/timing/address-cycle parameter include로 인덱싱. |
| v0.4 | `tb_onfi_sdr_decode_frontend.v`를 traffic-scenario 기반 scoreboard 검증 자산으로 갱신한 내용을 반영. |
| v0.3 | Decode FSM registered-output hybrid refactor와 `FSM_RTL_Design_Guide.md` 관련 문서 참조를 반영. |
| v0.2 | 범용 pin sync IP, PicoRV32 CDC IP 참조, adapter clock-domain 분리 변경을 반영. |
| v0.1 | Decode FSM/Adapter RTL 및 TB 추가에 맞춰 RTL/TB/FW 파일 index 최초 작성. |
