# Agent Guidelines
Version: v0.12
Status: active
Description: NAND model repository에서 agent가 따라야 할 문서 라우팅,
vendored IP/tool submodule 취급, revision history, coding discipline 관리 원칙을 정의한다.

## 목표

이 repository의 최종 목표는 커맨드 디코딩 HW FSM, RV32 Core 구조를 바탕으로 Nand Logic 설계를 PoC (Proof of Concept) 하는 것이다.

현재 control-agent 구현 방식은 아래와 같이 2가지로 나뉜다.
1. RV32 Core + FW 동작을 모사하는 Surrogate FW path
2. 실제 PicoRV32 Core + C FW 조합으로 동작하는 RV32 path

이 repository는 SIMPLE NAND model RTL, design specification, RV32 firmware와
surrogate/RV32 control-agent 통합 구조를 함께 관리한다.

현재 top-level 구조:

```text
Makefile
design_spec/
formal/
fw/
nand_model/
Nand_Model_Specification_Index.md
scripts/
tb/
tools/
```

PicoRV32 core와 reusable CDC/register-bank IP는 NAND repo 내부 vendored source로
관리한다. 검증 tool source는 필요 시 `tools/` 아래 submodule로 관리한다.

## Source of Truth

문서와 코드의 역할은 아래 우선순위로 해석한다.

- `AGENTS.md`: agent 작업 운영 규칙, repository 경계, vendored IP 취급 원칙.
- `Nand_Model_Specification_Index.md`: NAND 문서 라우팅과 파일 위치를 찾는 canonical index.
- `design_spec/Architecture.md`: top-level 구조, block boundary, clock/reset/CDC,
  surrogate/RV32 control-agent 선택 구조와 integration contract.
- `design_spec/nand_picorv32.md`: NAND repo 내부 PicoRV32 vendored core, native
  bus MMIO bridge, firmware image, IRQ/FW-ready integration contract.
- `design_spec/nand_cdc_ip.md`: NAND repo 내부 reusable CDC primitive와
  directed/formal verification contract.
- `design_spec/*.md`: 각 block 또는 기능의 상세 계약. 관련 RTL을 바꿀 때 가장 가까운
  상세 설계 문서를 우선 확인한다.

문서끼리 충돌하거나 RTL과 문서가 맞지 않으면 조용히 한쪽을 고르지 않는다. 충돌 위치,
선택 가능한 해석, 최소 수정 범위를 먼저 명시한다.

## Repository Routing

- 상세 NAND 설계 문서는 `design_spec/` 아래에 둔다.
- NAND RTL/source는 `nand_model/` 아래에 둔다.
- RV32 NAND firmware는 root-level `fw/` 아래에 둔다.
- reusable build helper script는 `scripts/` 아래에 둔다.
- formal harness는 `formal/` 아래에 둔다.
- testbench는 `tb/` 또는 명확한 하위 디렉터리에 둔다.
- 외부 tool source는 설계 source와 섞지 않고 `tools/` 아래 submodule로 둔다.
- 새 파일은 필요한 경우에만 만들고, 만들기 전에
  `Nand_Model_Specification_Index.md`, 관련 index 문서, 기존 디렉터리를 확인한다.
- 새 NAND 설계 문서를 추가하면 `Nand_Model_Specification_Index.md`를 함께 갱신한다.
- `Nand_Model_Specification_Index.md`를 갱신할 때는 문서 자체의 `Version`과
  `Version History`도 현재 변경 내용과 맞는지 항상 확인한다.
- RTL/TB/FW 파일이 본격적으로 늘어나면 `design_spec/File_Index.md`를 별도로 두고,
  파일 추가/이동/삭제와 같은 변경 단위에서 함께 갱신한다.
- RTL/문서 작업의 책임 경계는 별도 agent 역할 문서로 중복 관리하지 않는다.
  `Architecture.md`의 block boundary와 각 상세 설계 문서의 contract를 기준으로 판단한다.

## Vendored IP / Tool Submodule Policy

- NAND build는 이전 외부 submodule path에 의존하지 않는다.
- PicoRV32 core, `soc_regbank`, CDC primitive, firmware helper는 NAND repo 내부
  vendored source를 사용한다.
- vendored source 위치는 `nand_model/`, `fw/`, `scripts/`, `formal/`, `tb/`를 따른다.
- `tools/` 아래 submodule은 설계 source가 아니라 검증/build tool source를 고정하기
  위한 영역이다.
- `tools/sby/`는 SymbiYosys source submodule이다. Makefile과 installer는 formal
  검증 실행을 위해 참조할 수 있지만, NAND RTL/FW/TB source가 `tools/` 내부 파일을
  설계 dependency로 include/import하지 않는다.
- PicoRV32 attach 방식과 memory/MMIO/IRQ/FW-ready contract는
  `design_spec/nand_picorv32.md`를 따른다.
- CDC primitive와 formal verification contract는 `design_spec/nand_cdc_ip.md`를
  따른다.
- upstream 또는 외부 repository에서 다시 가져온 source를 갱신하면, 기존 NAND
  wrapper/contract와 달라진 점을 관련 설계문서와 revision history에 명시한다.

## File Hygiene

- 많은 파일을 top-level에 늘어놓지 않는다.
- 새 RTL/TB/FW 파일을 추가하면 파일 상단에 짧은 header comment를 둔다.
- 새 RTL/TB/FW 파일 header에는 최소한 목적, 합성/시뮬레이션 용도 구분, 관련
  설계문서, block contract, 파일 version을 적는다.
- 새 RTL/TB/FW 파일 header에는 짧은 file-level revision history를 둔다. 최소 형식은
  version 또는 revision id, 간단 설명이다. 공개 문서와 file header의 revision
  history에는 날짜 column이나 날짜 값을 넣지 않는다.
- file-level revision history가 길어지면 header에는 최신 주요 변경만 남기고,
  전체 추적은 `design_spec/Design_Revision_History.md`를 참조하게 한다.
- 기존 RTL/TB/FW 파일을 본격적으로 수정하는데 header가 없거나 위 항목이 빠져 있으면,
  같은 변경 단위에서 header를 보강한다.
- 각 파일 전체를 장황하게 설명하지 말고, 파일 역할과 block contract를 이해하는 데
  필요한 정도만 주석으로 남긴다.
- 모든 NAND 설계 문서에는 `Version`과 마지막 `Version History` 표를 둔다.

## Build and Simulation 원칙

- RTL 변경 후에는 가능한 범위에서 Makefile target으로 build/simulation을 실행한다.
- 새 simulation flow가 필요하면 Makefile에 명확한 target을 추가하고 이름을 안정적으로
  유지한다.
- Makefile target은 다른 agent가 반복 실행할 수 있도록 입력 파일과 산출물을 예측
  가능하게 둔다.
- 시뮬레이션 통과는 필요조건일 뿐이며, 합성 가능성/clock-reset/CDC/ownership 계약을
  대체하지 않는다.

## Synthesizable RTL 원칙

- Testbench, Surrogate FW, VPL 을 제외한 로직들은 합성 가능한 방식으로 Verilog/SystemVerilog로 작성한다.
- `#delay`, testbench-only task, file I/O, force/release, non-synthesizable initial
  dependency를 최종 RTL path에 넣지 않는다.
- Simulation을 쉽게 하려고 clock/reset, handshake, state ownership을 흐리지 않는다.
- VPL, surrogate FW, TB에 있는 임시 task/helper를 최종 hardware controller로
  착각하지 않는다.
- Timing delay는 RTL에서는 counter, parameter, ready/busy protocol로 표현한다.
- Multi-cycle array/page-buffer 동작은 필요하면 FSM으로 분해한다.
- 당장 smoke test가 통과하더라도 합성 불가능하거나 CDC/race 계약이 불명확하면
  완료로 보지 않는다.

## LLM Coding Discipline

이 지침은 agent가 흔히 저지르는 과잉 구현, 임의 가정, 불필요한 refactor를
줄이기 위한 행동 규칙이다. 사소한 작업에서는 판단을 사용하되, RTL/문서 계약이
걸린 작업에서는 보수적으로 적용한다.

### Think Before Coding

- 구현 전에 가정을 명시한다.
- 해석이 여러 개면 조용히 하나를 고르지 말고 선택지를 드러낸다.
- 더 단순한 접근이 있으면 말하고, 필요하면 push back한다.
- 불명확한 점이 구현 위험을 만들면 멈추고 무엇이 헷갈리는지 말한 뒤 질문한다.

### Simplicity First

- 요청받지 않은 기능을 추가하지 않는다.
- 한 번만 쓰는 코드에 추상화를 만들지 않는다.
- 요구되지 않은 flexibility/configurability를 넣지 않는다.
- 실제로 불가능한 상황을 위한 error handling을 과하게 만들지 않는다.
- 작성한 코드가 같은 목적을 훨씬 짧고 명확하게 달성할 수 있으면 단순화한다.

### Surgical Changes

- 요청과 직접 관련된 파일과 줄만 수정한다.
- 주변 코드, comment, formatting을 임의로 개선하지 않는다.
- 기존 style을 따른다.
- 관련 없는 dead code를 발견하면 언급만 하고 삭제하지 않는다.
- 자신의 변경으로 생긴 unused import, variable, function은 정리한다.
- 모든 변경 라인은 사용자 요청과 직접 연결되어야 한다.

### Goal-Driven Execution

- 작업을 검증 가능한 성공 기준으로 바꾼다.
- 버그 수정은 가능하면 재현 check를 먼저 정의하고, 수정 후 같은 check로 검증한다.
- 다단계 작업은 간단한 plan과 각 step의 verification을 둔다.
- "동작하게 만들기"처럼 약한 기준에 머무르지 않고, 어떤 command/test/review로
  완료를 확인할지 정한다.

## Design Revision History 원칙

- RTL 작업이 본격화되면 `design_spec/Design_Revision_History.md`를 별도로 둔다.
- 해당 문서는 상세 설계 설명이 아니라 revision 추적용으로만 사용한다.
- design revision은 top-level 변경만 기록하는 문서가 아니다. top revision은 전체
  통합 기준을 요약하고, 각 block/file revision은 별도 항목으로 추적한다.
- 각 design revision에는 전체 top revision, 적용 범위, 영향을 받은 block, 주요 수정
  파일을 기록한다.
- 각 주요 수정 파일 항목에는 파일 경로, block 이름, Verilog/SystemVerilog 파일
  version, 관련 설계문서와 그 version, 변경 요약, 수행한 build/simulation/check를
  함께 적는다.
- 한 번의 변경이 여러 block에 걸치면 top revision 아래에 file/block별 row를 나누어
  어떤 파일이 어떤 계약을 바꿨는지 추적 가능하게 한다.
- 파일 header의 file-level revision history와 `Design_Revision_History.md`의 해당
  파일 version은 서로 충돌하지 않아야 한다.
- 세부 architecture 설명은 `design_spec/Architecture.md`와 각 설계문서에 둔다.
- `Design_Revision_History.md`를 새로 만들면 `Nand_Model_Specification_Index.md`에
  인덱싱한다.

## Version History

| Version | Description |
| --- | --- |
| v0.12 | Revision history와 file header history에서 날짜 column/value를 쓰지 않는 정책을 추가. |
| v0.11 | SymbiYosys를 `tools/sby` tool submodule로 관리하는 정책과 `tools/` routing을 추가. |
| v0.10 | PicoRV32/CDC/register-bank IP를 NAND repo 내부 vendored source로 관리하도록 정책과 formal/scripts/tb routing을 반영. |
| v0.9 | RV32 FW 구현 완료 상태에 맞춰 surrogate/RV32 control-agent 선택 구조와 `fw/` routing 표현을 현재형으로 정리하고 문서 status를 active로 갱신. |
| v0.8 | Design Revision History를 top-only가 아닌 block/file별 revision 추적으로 정의하고 RTL/TB/FW header 필수 항목을 보강. |
| v0.7 | Agent_Roles.md 삭제에 맞춰 별도 agent 역할 문서 대신 Architecture와 상세 설계 contract를 기준으로 책임 경계를 판단하도록 정리. |
| v0.6 | Specification index 갱신 시 index 문서 자체의 Version/Version History 확인 규칙 추가. |
| v0.5 | Authoritative source 우선순위를 추가하고 중복된 작업/디렉터리/submodule 규칙을 라우팅 중심으로 정리. |
| v0.4 | PicoRV32 submodule copy policy, 파일 구성, Makefile simulation, file index 지침 추가. |
| v0.3 | 합성 가능한 RTL 최종 목표와 LLM coding discipline 지침 추가. |
| v0.2 | Agent 역할 문서 참조 규칙과 Design Revision History 운영 지침 추가. |
| v0.1 | NAND repository 작업 지침과 PicoRV32 submodule 취급 원칙 추가. |
