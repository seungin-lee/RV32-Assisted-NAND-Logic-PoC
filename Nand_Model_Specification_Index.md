# Nand Model Specification Index
Version: v0.54

이 문서는 SIMPLE NAND model의 최상위 인덱스 문서이다. 상세 사양은 `design_spec/` 아래 문서로 분리되어 있으며, 이 파일은 빠르게 원하는 문서 위치를 찾기 위한 lightweight map으로 유지한다.

## 1. 문서 구조
| 알고 싶은 내용 | 참고 문서 |
| --- | --- |
| NAND model 전체 architecture, PicoRV32/surrogate FW 연계 구조 | `design_spec/Architecture.md` |
| SIMPLE NAND ONFI SDR 모델의 지원 command와 기대 동작 | `design_spec/SIMPLE_ONFI_SDR_behavior_model_reference.md` |
| Host Testbench traffic 제어 시나리오와 top E2E simulation 실행 방식 | `design_spec/host_tb_traffice_scenario.md` |
| SIMPLE NAND geometry/timing/address-cycle 공유 parameter | `nand_model/nand_parameters.vh`, `design_spec/SIMPLE_ONFI_SDR_behavior_model_reference.md`, `design_spec/host_tb_traffice_scenario.md` |
| RTL FSM coding style, Moore/Mealy/Hybrid 선택 기준 | `design_spec/FSM_RTL_Design_Guide.md` |
| 합성 가능한 ONFI Decode FSM 설계 | `design_spec/SIMPLE_ONFI_SDR_decode_fsm.md` |
| NAND Adapter contract, reusable adapter primitive policy, Host Event/Host Pin Status/Page Buffer/VPL/Read Output role adapter | `design_spec/nand_adapter_contracts.md` |
| NAND-owned CDC primitive, external event adapter, CDC 검증 목적/tool/command/flow, directed/lint/formal coverage와 한계 | `design_spec/nand_cdc_ip.md` |
| Page Buffer direct program stream, VPL direct read/write port, Read Output read port, internal count, freeze/prog_ready, overflow, current RTL scope | `design_spec/nand_page_buffer.md` |
| Read ID/Status/Page Buffer source를 host `re_n`에 맞춰 `dq_out`으로 내보내는 Read Output Datapath | `design_spec/nand_read_output_datapath.md` |
| Read/Program/Erase 시 WL/BL/bias의 cell-level 의미 | `design_spec/nand_cell_operation.md` |
| Register Bank MMIO map, offset, bitfield, host mailbox RO view, IRQ/W1C, VPL command/status/transfer-byte snapshot contract | `design_spec/nand_register_bank.md` |
| Surrogate FW와 RV32 C control FW, IRQ-driven mailbox entry flow, Register Bank mailbox/IRQ/opcode 사용 흐름 | `design_spec/nand_control_fw.md` |
| PicoRV32 vendored core 구조, native bus, RV32 control-agent 내부 bridge, MMIO memory map, IRQ/FW-ready, FW image 연결 | `design_spec/nand_picorv32.md` |
| Virtual Physical Layer(VPL), VPL Command/Response Adapter snapshot, Page Buffer direct port 기반 read/program/erase commit | `design_spec/nand_model_vpl.md` |
| RTL/TB/FW 파일 위치와 한 줄 역할 | `design_spec/File_Index.md` |
| top/block/file revision 추적 | `design_spec/Design_Revision_History.md` |

## 2. 구현 파일 빠른 맵
| 파일 | 역할 | 상세 문서 |
| --- | --- | --- |
| `nand_model/pin_sync_edge_detect.v` | 범용 pin synchronizer / edge detector | `SIMPLE_ONFI_SDR_decode_fsm.md`, `nand_cdc_ip.md` |
| `nand_model/nand_parameters.vh` | SIMPLE NAND geometry, SDR Mode 0 timing, host TB guard cycle, address-cycle macro의 canonical include | `SIMPLE_ONFI_SDR_behavior_model_reference.md`, `host_tb_traffice_scenario.md`, `SIMPLE_ONFI_SDR_decode_fsm.md` |
| `nand_model/onfi_sdr_decode_fsm.v` | registered-output hybrid ONFI SDR Decode FSM core. write-side command/address/data input decode와 transaction event/program stream 생성 담당 | `SIMPLE_ONFI_SDR_decode_fsm.md`, `FSM_RTL_Design_Guide.md`, `nand_adapter_contracts.md` |
| `nand_model/nand_role_adapters.v` | reusable CDC wrapper, Host Event CDC plus busy mirror, Host Pin Status `wp_n` mirror, Page Buffer control/status CDC, VPL/Read Output role adapters | `nand_adapter_contracts.md`, `Architecture.md`, `nand_cdc_ip.md` |
| `nand_model/nand_page_buffer.v` | sysclk Page Buffer storage, direct program data input, VPL direct read/write port, Read Output direct read port, internal write count/freeze/prog_ready/overflow owner | `design_spec/nand_page_buffer.md`, `Architecture.md`, `nand_adapter_contracts.md` |
| `nand_model/nand_read_output_datapath.v` | sysclk Read ID/Status/Page Buffer source mux, `re_n` fall 기반 `dq_out` drive, `re_n` rise 기반 `dq_oe` release, read pointer owner | `design_spec/nand_read_output_datapath.md`, `design_spec/nand_register_bank.md`, `Architecture.md` |
| `nand_model/onfi_sdr_decode_frontend.v` | Pin Sync + Decode FSM raw handoff frontend wrapper. RE# edge pulse는 Read Output Datapath용으로 노출 | `Architecture.md`, `SIMPLE_ONFI_SDR_decode_fsm.md`, `nand_adapter_contracts.md`, `design_spec/nand_read_output_datapath.md` |
| `nand_model/cdc_valid_ack.sv` | NAND-owned multi-bit payload valid/ack CDC primitive | `design_spec/nand_cdc_ip.md`, `nand_adapter_contracts.md` |
| `nand_model/cdc_level_sync.sv` | NAND-owned single-bit level synchronizer | `design_spec/nand_cdc_ip.md`, `nand_adapter_contracts.md` |
| `nand_model/external_event_adapter.sv` | generic event payload CDC wrapper와 optional IRQ level sync reference/helper | `design_spec/nand_cdc_ip.md`, `nand_adapter_contracts.md` |
| `nand_model/soc_regbank.sv` | NAND-owned parameterized register bank payload/IRQ/W1C core | `design_spec/nand_register_bank.md`, `design_spec/nand_picorv32.md` |
| `nand_model/picorv32.v` | vendored PicoRV32 native memory bus/IRQ core copy | `Architecture.md`, `design_spec/nand_picorv32.md` |
| `nand_model/nand_register_bank.v` | public NAND MMIO map, host mailbox, IRQ/W1C, VPL command/status/transfer-byte side effect, Read Output snapshot을 구현한 Register Bank RTL | `design_spec/nand_register_bank.md`, `design_spec/nand_control_fw.md`, `design_spec/nand_model_vpl.md`, `design_spec/nand_read_output_datapath.md` |
| `nand_model/nand_vpl_executor.v` | VPL command snapshot accept, internal array READ/PROGRAM/ERASE, latency counter, done/error response를 수행하는 sysclk clocked executor | `design_spec/nand_model_vpl.md`, `design_spec/nand_register_bank.md`, `Architecture.md` |
| `nand_model/nand_surrogate_fw_agent.v` | Register Bank `cpu_*` MMIO bus와 `irq_o`를 사용하는 simulation-only surrogate FW behavior agent | `design_spec/nand_control_fw.md`, `design_spec/nand_register_bank.md` |
| `nand_model/nand_rv32_control_agent.v` | PicoRV32 core + firmware SRAM + Register Bank MMIO bridge + IRQ/FW-ready handoff를 묶는 RV32 control-agent path | `design_spec/nand_picorv32.md`, `design_spec/nand_control_fw.md`, `design_spec/nand_register_bank.md`, `Architecture.md` |
| `nand_model/nand_logic_top.v` | ONFI host-facing pins(`dq` inout, `rb_n` 포함)와 clock/reset만 public port로 두고 Decode Frontend, role adapters, Page Buffer, VPL executor, Register Bank, control-agent 선택 구간을 instance하는 current PoC top | `Architecture.md`, `nand_adapter_contracts.md`, `design_spec/nand_control_fw.md`, `design_spec/nand_register_bank.md`, `design_spec/nand_model_vpl.md` |
| `fw/nand_startup.S` | PicoRV32 reset/IRQ veneer, stack setup, BSS clear, C entry, IRQ save/restore | `design_spec/nand_control_fw.md`, `design_spec/nand_picorv32.md` |
| `fw/picorv32_custom_ops.S` | PicoRV32 `maskirq`/`retirq` custom instruction macro include | `design_spec/nand_picorv32.md`, `design_spec/nand_control_fw.md` |
| `fw/nand_control_fw.c` | Register Bank MMIO/IRQ를 사용하는 readable RV32 C control firmware | `design_spec/nand_control_fw.md`, `design_spec/nand_register_bank.md`, `design_spec/nand_model_vpl.md` |
| `fw/nand_mmio.h`, `fw/nand_fw_defs.h`, `fw/nand_linker.ld` | RV32 FW MMIO offsets, FW constants, 32 KiB SRAM linker layout | `design_spec/nand_control_fw.md`, `design_spec/nand_register_bank.md` |
| `scripts/makehex.py` | RV32 firmware binary를 `$readmemh` hex로 변환하는 build helper | `design_spec/nand_picorv32.md` |
| `scripts/install_deps.sh` | build/simulation/formal 의존성 설치 helper. `tools/sby` submodule source에서 SymbiYosys 설치 | `design_spec/nand_cdc_ip.md`, `design_spec/nand_picorv32.md` |
| `formal/cdc_valid_ack_formal.sv`, `formal/cdc_valid_ack.sby` | `cdc_valid_ack` bounded formal harness/wrapper | `design_spec/nand_cdc_ip.md` |
| `tools/sby/` | SymbiYosys tool source submodule | `design_spec/nand_cdc_ip.md` |
| `tb/tb_picorv32_core_ez.v` | firmware-free PicoRV32 native-bus core smoke testbench | `design_spec/nand_picorv32.md` |
| `tb/tb_cdc_valid_ack.sv`, `tb/tb_external_event_adapter.sv` | CDC primitive/wrapper directed smoke testbench | `design_spec/nand_cdc_ip.md` |
| `tb/tb_pin_sync_edge_detect.v` | generic pin sync/edge detect smoke testbench | `SIMPLE_ONFI_SDR_decode_fsm.md` |
| `tb/tb_onfi_sdr_decode_fsm.v` | Decode FSM module smoke testbench | `SIMPLE_ONFI_SDR_decode_fsm.md` |
| `tb/tb_onfi_sdr_decode_frontend.v` | behavior reference/host traffic scenario 기반 Decode frontend + Host Event Adapter + Page Buffer scoreboard testbench | `Architecture.md`, `SIMPLE_ONFI_SDR_behavior_model_reference.md`, `host_tb_traffice_scenario.md`, `nand_adapter_contracts.md` |
| `tb/tb_nand_role_adapters.v` | Host Event CDC, Page Buffer control/status CDC, VPL Command/Response, Read Output Mirror adapter smoke testbench | `nand_adapter_contracts.md`, `Architecture.md` |
| `tb/tb_nand_page_buffer.v` | Page Buffer direct program stream handshake, VPL direct read/write, freeze/clear/overflow smoke testbench | `nand_adapter_contracts.md`, `Architecture.md`, `design_spec/nand_page_buffer.md` |
| `tb/tb_nand_read_output_datapath.v` | Read ID 00h/20h, Read Status, Page Buffer readout source mux smoke testbench | `design_spec/nand_read_output_datapath.md`, `design_spec/nand_page_buffer.md` |
| `tb/tb_nand_vpl_executor.v` | VPL executor command/response, READ/PROGRAM/ERASE data effect, latency, error, backpressure smoke testbench | `design_spec/nand_model_vpl.md`, `design_spec/nand_page_buffer.md` |
| `tb/tb_nand_register_bank.v` | Register Bank host mailbox, VPL command/status/transfer-byte snapshot directed smoke testbench | `design_spec/nand_register_bank.md` |
| `tb/tb_nand_surrogate_fw_agent.v` | surrogate FW agent가 host mailbox를 읽고 readout/VPL register를 설정하는지 확인하는 smoke testbench | `design_spec/nand_control_fw.md`, `design_spec/nand_register_bank.md`, `design_spec/nand_model_vpl.md` |
| `tb/tb_nand_logic_top_e2e.v` | Host traffic scenario 기반 actual `dq` inout/`rb_n` top pin을 사용하는 Decode/Register Bank/control-agent/VPL/Page Buffer/Read Output full-sim testbench. RV32 build에서는 trap/FW-ready initial gate도 확인 | `Architecture.md`, `host_tb_traffice_scenario.md`, `design_spec/nand_control_fw.md` |

## 3. 모델 핵심 범위
- Legacy Async SDR, x8 `dq[7:0]`
- SDR Timing Mode 0 기준
- Single die, single LUN, single plane
- SLC program 특성: program은 1->0만 허용
- 지원 command: `FFh`, `90h`, `70h`, `00h-30h`, `80h-10h`, `60h-D0h`
- 비지원 command와 제한 사항은 `design_spec/SIMPLE_ONFI_SDR_behavior_model_reference.md`에 정리되어 있다.

## 4. 설계 경계
현재 문서 체계는 아래 경계를 기준으로 나뉜다.

1. Top-level architecture 및 PicoRV32/surrogate FW control-agent 선택 구조
   위치: `design_spec/Architecture.md`

2. Host-visible ONFI behavior  
   위치: `design_spec/SIMPLE_ONFI_SDR_behavior_model_reference.md`

3. Host TB가 생성해야 하는 pin-level traffic  
   위치: `design_spec/host_tb_traffice_scenario.md`

4. RTL FSM coding style과 Moore/Mealy/Hybrid 선택 기준
   위치: `design_spec/FSM_RTL_Design_Guide.md`

5. NAND model 내부 ONFI Decode FSM
   위치: `design_spec/SIMPLE_ONFI_SDR_decode_fsm.md`

6. NAND Adapter contract, reusable adapter primitive policy, Host Event/Host Pin Status/Page Buffer/VPL/Read Output role adapter
   위치: `design_spec/nand_adapter_contracts.md`

7. NAND-owned CDC primitive와 directed/lint/formal verification flow
   위치: `design_spec/nand_cdc_ip.md`

8. Page Buffer direct program stream, VPL direct port, Read Output direct read port, 현재 RTL ownership
   위치: `design_spec/nand_page_buffer.md`

9. Cell operation에서 WL/BL/bias가 의미하는 개념 기준
   위치: `design_spec/nand_cell_operation.md`

10. Register Bank MMIO map, offset, bitfield, IRQ/W1C, mailbox/status 계약
   위치: `design_spec/nand_register_bank.md`

11. Control FW 또는 surrogate FW가 수행하는 MMIO/IRQ/opcode 처리 흐름
   위치: `design_spec/nand_control_fw.md`

12. PicoRV32 core 구조, native bus, RV32 firmware image, Register Bank MMIO bridge
   위치: `design_spec/nand_picorv32.md`

13. FW/MMIO trigger 이후 VPL Command/Response Adapter와 Page Buffer direct port를 사용해 memory/page buffer를 갱신하는 VPL
   위치: `design_spec/nand_model_vpl.md`

14. RTL/TB/FW 파일 위치와 revision 추적
   위치: `design_spec/File_Index.md`, `design_spec/Design_Revision_History.md`

## 5. 변경 시 참고 순서
사양 변경 시 아래 순서로 문서를 먼저 갱신한다.

1. Top-level block boundary, clock/reset/CDC policy, RV32 FW integration contract가 바뀌면
   `Architecture.md`

2. Host-visible command 동작이 바뀌면  
   `SIMPLE_ONFI_SDR_behavior_model_reference.md`

3. SIMPLE NAND geometry, SDR timing guard, address-cycle count가 바뀌면
   `nand_model/nand_parameters.vh`, `SIMPLE_ONFI_SDR_behavior_model_reference.md`,
   `host_tb_traffice_scenario.md`

4. TB 시나리오나 checker 조건이 바뀌면
   `host_tb_traffice_scenario.md`

5. RTL FSM coding style, Moore/Mealy/Hybrid 선택 기준이 바뀌면
   `FSM_RTL_Design_Guide.md`

6. ONFI Decode FSM, host command gating, busy/backpressure 정책이 바뀌면
   `SIMPLE_ONFI_SDR_decode_fsm.md`, 필요 시 `FSM_RTL_Design_Guide.md`,
   `nand_adapter_contracts.md`

7. Adapter 공통 규칙, Decode FSM event handoff, Page Buffer Adapter, VPL Command/Response Adapter, Read Output Mirror Adapter contract가 바뀌면
   `nand_adapter_contracts.md`, 필요 시 `nand_cdc_ip.md`, `nand_register_bank.md`

8. Read/Program/Erase의 WL/BL/bias 설명 기준이 바뀌면
   `nand_cell_operation.md`

9. Register Bank MMIO map, offset, bitfield, host event mailbox, IRQ ownership, status update, W1C 정책이 바뀌면
   `nand_register_bank.md`

10. FW/MMIO 처리 flow, command handler, address conversion, surrogate/RV32 FW handoff가 바뀌면
   `nand_control_fw.md`, 필요 시 `nand_register_bank.md`

11. Page Buffer ownership, Decode-to-Page-Buffer direct data path, VPL direct port, current RTL scope가 바뀌면
   `nand_page_buffer.md`, 필요 시 `nand_adapter_contracts.md`, `nand_model_vpl.md`

12. Register Bank/Page Buffer control-status handoff, VPL Command/Response Adapter, Read Output Mirror Adapter, CDC/timing budget이 바뀌면
   `nand_adapter_contracts.md`, 필요 시 `nand_page_buffer.md`, `nand_model_vpl.md`

13. Read/Program/Erase commit, VPL/Page Buffer direct port 사용 방식, busy timing, memory update 정책이 바뀌면
   `nand_model_vpl.md`, 필요 시 `nand_page_buffer.md`

14. PicoRV32 core attach, native-bus memory map, RV32 FW image, IRQ/FW-ready contract가 바뀌면
   `nand_picorv32.md`, 필요 시 `nand_control_fw.md`, `nand_register_bank.md`

15. RTL/TB/FW/formal/script 파일이 추가, 이동, 삭제되면
   `File_Index.md`, 필요 시 `Design_Revision_History.md`

## 6. 최소 회귀 시나리오
현재 smoke test의 기준 시나리오는 아래 흐름이다. 자세한 pin timing과 pass/fail 조건은 `design_spec/host_tb_traffice_scenario.md`를 따른다.

1. Reset
2. Read ID 00h
3. Read ID 20h
4. Page Program
5. Read Status
6. Page Readback
7. Block Erase
8. Read Status
9. Post-erase Readback

Makefile은 개별 testbench alias를 제공하지 않는다. Simulation은 공통 `sim` target을
사용하며, `TB`에는 `tb/` 아래 파일의 basename, 파일명, 또는 경로를 줄 수 있다.
RV32 control-agent path는 같은 방식의 `sim-rv32` target을 사용한다.

```text
make sim
make sim TB=tb_nand_page_buffer
make sim TB=tb/tb_pin_sync_edge_detect.v
make sim TB=tb_nand_logic_top_e2e
make sim-rv32 TB=tb_nand_logic_top_e2e
```

`make sim`의 기본 `TB`는 `tb_nand_logic_top_e2e`이며, `host_tb_traffice_scenario.md`의
Reset, Read ID 00h/20h, Program, Status, Read Page, Erase, Post-erase Read Page를
`nand_logic_top` instance 하나에서 재현한다. RV32 C firmware image와 RV32 top
elaboration은 아래 target으로 확인한다.

```text
make fw
make top
make top-rv32
```

NAND-owned CDC IP simulation/formal 회귀는 아래 target을 따른다. CDC directed
simulation도 별도 alias 없이 공통 `sim` target을 사용한다.

```text
make sim TB=tb_cdc_valid_ack
make sim TB=tb_external_event_adapter
make cdc-lint
make cdc-formal
make cdc-formal-sby
```

## 7. 문서 상태
- 이 파일은 상세 사양서가 아니라 인덱스 문서이다.
- 상세 내용은 `design_spec/` 문서를 authoritative source로 본다.
- `nand_cell_operation.md`, `nand_page_buffer.md`, `nand_register_bank.md`, `nand_control_fw.md`, `nand_adapter_contracts.md`,
  `nand_cdc_ip.md`, `nand_picorv32.md`, `nand_model_vpl.md`는 현재 RTL/FW 구현
  contract를 설명한다. 관련 RTL/FW contract가 바뀌면 같은 변경 단위에서 함께 갱신한다.

---

## Version History
| Version | 변경사항 |
| --- | --- |
| v0.54 | Page Buffer public write monitor/count port 제거에 맞춰 quick map과 TB 설명을 internal count/handshake scoreboard 기준으로 갱신. |
| v0.53 | Decode FSM core의 write-side decode ownership과 Decode Frontend의 RE# edge export 역할을 current RTL contract 기준으로 quick map에 반영. |
| v0.52 | Makefile alias target 제거에 맞춰 host traffic/PicoRV32/CDC current 실행 안내와 TB 로그 문구를 새 target surface로 정리. |
| v0.51 | Makefile alias target 제거에 맞춰 현재 실행 명령을 `sim`, `sim-rv32`, `fw`, `top`, `top-rv32`, `cdc-*` 중심으로 갱신. |
| v0.50 | Makefile의 공통 `make sim TB=...` / `make sim-rv32 TB=...` testbench 실행 방식을 최소 회귀 설명에 추가. |
| v0.49 | SymbiYosys `tools/sby` tool submodule과 `make test-cdc-formal-sby` wrapper flow를 quick map/회귀 target에 추가. |
| v0.48 | build/simulation/formal 의존성 설치 helper `scripts/install_deps.sh`를 quick map에 추가. |
| v0.47 | `nand_picorv32.md` v0.2의 PicoRV32 core 구조, native bus, RV32 control-agent 내부 bridge, memory map, IRQ/FW-ready 상세화를 인덱싱. |
| v0.46 | `nand_cdc_ip.md` v0.2의 CDC 검증 목적, tool/command/flow, directed/lint/formal coverage, 산출물/PASS 로그/한계 상세화를 인덱싱. |
| v0.45 | PicoRV32/CDC IP를 NAND repo 내부 vendored source로 전환하고 `nand_picorv32.md`, `nand_cdc_ip.md`, CDC formal/core smoke target 라우팅을 추가. |
| v0.44 | 구현 완료 상태에 맞춰 주요 current contract 문서 status를 active로 정리한 변경을 반영. |
| v0.43 | current routing/회귀 설명에서 초기 전환 표현을 제거하고 현재 구현된 RV32/surrogate control-agent 선택 구조와 문서 갱신 기준으로 정리. |
| v0.42 | 삭제된 `page_buffer_cdc_timing_design_note.md`를 current 문서 구조/설계 경계/문서 상태 라우팅에서 제거하고, Page Buffer/CDC 관련 라우팅을 `nand_page_buffer.md`와 `nand_adapter_contracts.md` 중심으로 유지. |
| v0.41 | RV32 control agent, readable C firmware/startup/linker/header files, `build-nand-rv32-fw`, `full-sim-rv32`, FW-ready host-ready gate를 인덱싱. |
| v0.40 | Pre-RV32 integration audit에서 확인한 `REG_HOST_EVENT` RO/write-ignored RTL 정렬과 VPL READY/RB_N, Read Output `dq` inout 문서 표현 정리를 반영. |
| v0.39 | `nand_logic_top` host-facing public port cleanup, role adapter busy/WP_N mirror, full-sim actual `rb_n`/inout `dq` 관측 기준을 quick map에 반영. |
| v0.38 | `make full-sim`/`make test-full-sim`을 host traffic scenario canonical top simulation target으로 반영하고 full-sim checker 범위를 갱신. |
| v0.37 | `tb_nand_logic_top_e2e.v`, `make test-top-e2e`, Read Output `dq_oe` release 동작을 quick map과 회귀 설명에 반영. |
| v0.36 | Read Output Datapath 설계문서/RTL/TB, Page Buffer readout direct port, `make test-read-output`를 인덱싱. |
| v0.35 | PROGRAM VPL transfer byte count를 `REG_HOST_DATA_COUNT`로 snapshot하는 Register Bank RTL/TB/document 변경을 반영. |
| v0.34 | Page Buffer VPL direct port와 VPL executor internal array READ/PROGRAM/ERASE 구현 및 TB coverage를 quick map에 반영. |
| v0.33 | `nand_page_buffer.md`와 `nand_model_vpl.md`의 VPL/Page Buffer sysclk-local direct port contract 보강을 인덱싱. |
| v0.32 | `nand_vpl_executor.v`, `tb_nand_vpl_executor.v`, `make test-vpl-executor`를 추가하고 top 기본 VPL executor 연결을 반영. |
| v0.31 | `nand_logic_core.v`를 제거하고 `nand_logic_top.v` 단일 top 내부 control-agent 선택 구조와 `NAND_CONTROL_RV32` switch를 반영. |
| v0.30 | `Architecture.md` v0.16의 current PoC top/core ownership을 반영하고, `nand_logic_core.v`/`nand_logic_top.v` 구조, legacy monolithic model/include 파일 삭제, `make check-nand-logic-core` 추가를 반영. |
| v0.29 | Surrogate FW agent를 `nand_model/`로 이동하고 `nand_logic_top_surrogate.v`, `make check-nand-logic-top-surrogate`를 추가. |
| v0.28 | `nand_surrogate_fw_agent.v`, `tb_nand_surrogate_fw_agent.v`, `make test-surrogate-fw`를 추가. |
| v0.27 | `REG_HOST_EVENT`를 RO mailbox view로 두고 host event clear를 `REG_IRQ_STATUS.HOST_CMD_IRQ` W1C로 통일한 문서 변경 반영. |
| v0.26 | `nand_control_fw.md` v0.8의 IRQ-driven FW entry flow 보강을 반영. |
| v0.25 | `nand_page_buffer.md`를 Page Buffer RTL ownership/current scope 문서로 추가하고 관련 라우팅을 갱신. |
| v0.24 | `nand_page_buffer.v`, `tb_nand_page_buffer.v`, `make test-page-buffer`를 추가하고 Page Buffer bulk write ownership을 role adapter에서 Page Buffer RTL로 이동. |
| v0.23 | `onfi_sdr_decode_adapter.v`/TB 삭제, Decode Frontend raw handoff 구조, Host Event/Page Buffer write adapter의 `nand_role_adapters.v` 통합을 quick map에 반영. |
| v0.22 | `nand_role_adapters.v`, `tb_nand_role_adapters.v`, `make test-role-adapters`를 quick map과 최소 회귀 설명에 추가. |
| v0.21 | `host_clk`/`pb_clk` 제거와 `sys_clk`/`core_clk` RTL interface 정리에 맞춰 adapter/frontend/TB quick map을 갱신. |
| v0.20 | 당시 `onfi_sdr_decode_adapter.v`/TB는 PB stream handoff 초기 구현이며 D0.12 설계 방향에서는 PB bulk data를 direct path로 분리한다는 quick map 설명을 추가. |
| v0.19 | Decode FSM/Page Buffer program data stream을 sysclk direct path로 두고 Page Buffer Adapter를 Register Bank/Page Buffer control-status handoff로 한정한 문서 변경을 반영. |
| v0.18 | Architecture top-level block diagram을 role adapter/handoff boundary 기준으로 정렬하고 `nand_adapter_contracts.md`의 adapter 구조 설명을 한국어 중심으로 정리한 변경을 반영. |
| v0.17 | 기존 Host Event/Data Adapter 문서를 `nand_adapter_contracts.md`로 승격한 라우팅을 반영하고 Host Event/Page Buffer/VPL/Read Output adapter contract를 단일 canonical adapter 문서로 인덱싱. |
| v0.16 | `nand_logic_top.v`와 `make check-nand-logic-top` syntax/elaboration target을 quick map과 최소 회귀 설명에 추가. |
| v0.15 | `nand_register_bank.v`와 `tb_nand_register_bank.v`를 quick map과 최소 회귀 target에 추가. |
| v0.14 | `nand_register_bank.md`를 Register Bank MMIO map/bitfield/IRQ/W1C canonical 문서로 추가하고 관련 문서 라우팅을 갱신. |
| v0.13 | `nand_control_fw.md`의 Register Bank mailbox/IRQ/W1C contract와 `nand_model_vpl.md`의 VPL Command/Response Adapter snapshot/result ownership 정리를 반영. |
| v0.12 | `nand_cell_parameters.vh`를 `nand_parameters.vh`로 교체하고 geometry/timing/address-cycle 공유 parameter 라우팅을 반영. |
| v0.11 | `tb_onfi_sdr_decode_frontend.v`를 behavior reference/host traffic scenario 기반 scoreboard 검증 자산으로 갱신한 내용을 반영. |
| v0.10 | `FSM_RTL_Design_Guide.md`를 인덱싱하고 Decode FSM registered-output hybrid refactor 관련 문서 경로를 반영. |
| v0.9 | 범용 pin_sync_edge_detect, PicoRV32 CDC IP source 참조, adapter clock-domain 분리 변경을 구현 파일 quick map에 반영. |
| v0.8 | Decode FSM/Adapter RTL 및 TB 추가에 맞춰 File_Index.md, Design_Revision_History.md, 구현 파일 quick map을 인덱싱. |
| v0.7 | `SIMPLE_ONFI_SDR_decode_fsm.md`의 상세 설계 변경을 반영해 index 설명과 변경 참고 순서를 갱신. |
| v0.6 | `nand_adapter_contracts.md`를 Decode FSM handoff와 Adapter canonical contract로 인덱싱하고 `page_buffer_cdc_timing_design_note.md`를 참고 노트로 격하. |
| v0.5 | `design_spec/Agent_Roles.md` 삭제를 반영하고 책임 경계는 `Architecture.md`와 각 상세 설계 문서의 contract를 따르도록 정리. |
| v0.4 | `page_buffer_cdc_timing_design_note.md`를 인덱싱하고 Architecture v0.4의 Register Bank IRQ ownership, FSM/Adapter busy/backpressure, Page Buffer handoff 기준을 변경 참고 순서에 반영. |
| v0.3 | agent 역할 기반 작업 문서 위치를 추가. |
| v0.2 | 디렉토리 구조 변경을 반영하고 `Architecture.md` 및 PicoRV32 submodule 참조를 인덱싱. |
| v0.1 | 상세 사양 문서 위치를 안내하는 lightweight index 구조를 최초 정리. |
