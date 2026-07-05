# NAND Control FW / Surrogate FW
Version: v0.15

본 문서는 SIMPLE NAND 모델에서 control FW 또는 Verilog surrogate FW가 담당할
동작을 정의한다. FW는 Decode FSM이 만든 host transaction mailbox를 읽고, VPL이
실행할 target/opcode/bias register를 설정한다.

Register offset, bit field, access class, W1C/IRQ 정책은
`nand_register_bank.md`를 따른다. VPL operation semantics는 `nand_model_vpl.md`,
cell-level line/bias 의미는 `nand_cell_operation.md`를 기준으로 한다. PicoRV32
native bus, firmware image, IRQ/FW-ready integration은 `nand_picorv32.md`를 따른다.

## 1. 핵심 원칙

FW가 operation을 결정한다. VPL은 FW가 쓴 `REG_OP_CTRL.OP_CODE`의 snapshot을 기준으로
동작한다.

```text
Host command/address/data -> Decode FSM transaction decode
Host Event Adapter -> Register Bank atomic mailbox commit
Register Bank sets host event pending + IRQ
FW reads host transaction mailbox
FW sets target block/page/column
FW optionally sets bias/line debug registers
FW sets REG_OP_CTRL.OP_CODE
FW writes REG_OP_TRIGGER.START
Register Bank snapshots VPL command through VPL Command/Response Adapter
VPL executes operation and returns result
Register Bank updates status/IRQ
FW observes status and clears W1C bits
```

즉 VPL이 `VPGM`, `VPASS`, `BL`, `WL`, `SSL/GSL` 조합을 보고 read/program/erase를
추론하도록 만들지 않는다.

## 2. FW 책임

- Register Bank의 host transaction mailbox를 읽고 command handler를 선택한다.
- decoded transaction의 address cycle을 column, row, block, page/WL index로 변환한다.
- program data 수신 완료 여부와 page buffer ready 상태를 확인한다.
- read/program/erase에 맞는 optional bias/line register를 설정한다.
- `REG_OP_CTRL.OP_CODE`와 option bit를 설정한다.
- `REG_OP_TRIGGER.START`로 VPL operation을 요청한다.
- `REG_OP_STATUS`, `REG_OP_ERROR`, `REG_NAND_STATUS`를 확인한다.
- command 완료 후 W1C/status clear 및 다음 command 수신 가능 상태를 만든다.

FW는 ONFI pin phase를 직접 재조립하지 않는다. command/address/data phase 해석은
Decode FSM 책임이고, FW는 Register Bank에 atomic commit된 decoded transaction
snapshot을 처리한다.

## 3. Register Bank 사용 기준

FW는 32-bit word MMIO로 Register Bank에 접근한다. Register 이름, offset, bit field,
reset value, access class는 `nand_register_bank.md`를 authoritative source로 둔다.

FW flow에서 자주 쓰는 register group은 아래와 같다.

| Group | 주요 register | FW 관점 |
| --- | --- | --- |
| Host mailbox | `REG_HOST_CMD`, `REG_HOST_ADDR*`, `REG_HOST_META`, `REG_HOST_DATA_COUNT`, `REG_HOST_EVENT` | decoded host transaction과 pending/error view 확인 |
| IRQ/status | `REG_IRQ_STATUS`, `REG_IRQ_ENABLE`, `REG_NAND_STATUS` | pending 확인, interrupt mask 설정, handled pending W1C clear, host-visible status 확인 |
| VPL command | `REG_BLOCK_SEL`, `REG_PAGE_SEL`, `REG_COL_SEL`, `REG_OP_CTRL`, `REG_OP_TRIGGER` | target/opcode/options 설정 후 start |
| VPL result | `REG_OP_STATUS`, `REG_OP_ERROR`, `REG_OP_STATUS_CLR` | done/error/page-buffer 상태 확인 및 clear |
| Read output | `REG_READOUT_CTRL` | Read ID/Status/Page output source 준비 |
| Optional bias/debug | `REG_VREAD_LEVEL`, `REG_VPGM_LEVEL`, `REG_VPASS_LEVEL`, `REG_VERS_LEVEL`, `REG_BL_CTRL`, `REG_WL_CTRL`, `REG_LINE_CTRL`, `REG_BIAS_PROFILE` | VPL check/debug metadata 설정 |

FW는 reserved bit를 `0`으로 쓰는 것을 기본으로 한다. W1C field는 처리한 bit에만
`1`을 쓰고, unrelated pending bit를 실수로 clear하지 않도록 read-modify-write를
피한다.

## 4. IRQ-driven FW Entry Flow

surrogate FW와 RV32 FW는 Decode FSM이나 Host Event Adapter의 내부 signal을 직접 보지
않는다. FW entry point는 Register Bank가 assert한 `irq_o` 또는 polling으로 관찰한
`REG_IRQ_STATUS`다. IRQ handler는 pending source를 먼저 판별한 뒤, 필요한 mailbox나
status register를 MMIO로 읽고 command handler를 호출한다.

Host command IRQ 처리 흐름:

```text
irq_o asserted
FW reads REG_IRQ_STATUS
if REG_IRQ_STATUS.HOST_CMD_IRQ:
    FW reads REG_HOST_EVENT
    FW reads REG_HOST_META
    FW reads REG_HOST_CMD
    FW reads REG_HOST_ADDR0..REG_HOST_ADDR4
    FW reads REG_HOST_DATA_COUNT
    FW dispatches command handler using REG_HOST_META.DECODED_OP
    FW writes control/readout/VPL registers as needed
    FW W1C clears REG_IRQ_STATUS.HOST_CMD_IRQ
```

VPL completion/error IRQ 처리 흐름:

```text
FW reads REG_IRQ_STATUS
if REG_IRQ_STATUS.OP_DONE_IRQ or REG_IRQ_STATUS.OP_ERROR_IRQ:
    FW reads REG_OP_STATUS
    FW reads REG_OP_ERROR
    FW reads REG_NAND_STATUS
    FW finishes the in-flight command flow
    FW W1C clears handled REG_IRQ_STATUS bits
    FW writes REG_OP_STATUS_CLR bits for handled sticky status
```

권장 순서:

- IRQ handler는 `REG_IRQ_STATUS`를 먼저 읽고 source별 handler를 호출한다.
- `HOST_CMD_IRQ` handler는 host mailbox payload를 모두 읽은 뒤 command별 flow로
  분기한다.
- Host event clear는 해당 command를 처리하는 데 필요한 snapshot을 모두 읽은 뒤
  `REG_IRQ_STATUS.HOST_CMD_IRQ` W1C로 수행한다.
- `REG_HOST_EVENT`는 RO mailbox view다. FW는 이 register에 write해서 clear하지 않는다.
- `REG_IRQ_STATUS`는 W1C register이므로 처리한 bit에만 `1`을 쓴다.
- VPL operation을 start한 command는 host mailbox를 clear하더라도 `REG_OP_STATUS.DONE`
  또는 `ERROR` sticky status가 정리되기 전까지 다음 host event가 막힐 수 있다.
- surrogate FW도 이 흐름을 그대로 따르며, 실제 RV32 core 대신 MMIO bus를 drive할 뿐
  Register Bank를 우회하지 않는다.

## 5. Address 계산

실제 ONFI Host/FW는 Read Parameter Page(`ECh`)를 통해 geometry를 읽고 address layout을
결정한다. 본 SIMPLE 모델은 `ECh`를 지원하지 않으므로 FW는 SIMPLE geometry를
compile-time contract로 알고 있다고 가정한다.

SIMPLE geometry:

| 항목 | 값 | FW 해석 |
| --- | ---: | --- |
| Page size | 2048 bytes | `col_addr` valid range: 0..2047 |
| Pages per block | 64 | row 하위 6 bit가 page-in-block |
| Blocks | 32 | row 다음 5 bit가 block |
| LUN | 1 | row 상위 reserved/LUN bit는 0이어야 함 |

Page read/program command 기준:

```text
col_addr = addr0 + (addr1 << 8)
row_addr = addr2 + (addr3 << 8) + (addr4 << 16)

if col_addr >= NAND_PAGE_SIZE:
    ERR_COL_RANGE

if row_addr >= NAND_TOTAL_PAGES:
    ERR_ROW_RANGE

block_idx = row_addr / NAND_PAGES_PER_BLOCK
page_sel  = row_addr % NAND_PAGES_PER_BLOCK
```

Block erase command 기준:

```text
row_addr = addr0 + (addr1 << 8) + (addr2 << 16)

if row_addr >= NAND_TOTAL_PAGES:
    ERR_ROW_RANGE

block_idx = row_addr / NAND_PAGES_PER_BLOCK
page_sel  = row_addr % NAND_PAGES_PER_BLOCK

if page_sel != 0:
    ERR_ERASE_PAGE_BITS 또는 warning
```

FW는 범위 초과 주소를 modulo로 접지 않는 것을 기본 정책으로 한다. modulo wrap은
잘못된 LUN/reserved bit나 block range 오류를 숨기기 때문이다.

정상 Host TB traffic은 erase address를 `row = block_idx * NAND_PAGES_PER_BLOCK`로
만들어 page-in-block bit를 0으로 보내야 한다. FW는 erase에서 `page_sel`을 target
page로 사용하지 않고 `block_idx`만 VPL의 `REG_BLOCK_SEL`로 전달한다.

## 6. Command별 FW Flow

### 6.1 `FFh` Reset

1. Register Bank의 host event IRQ pending bit를 `REG_IRQ_STATUS.HOST_CMD_IRQ` W1C로 clear한다.
2. VPL이 busy이면 reset 정책에 따라 operation을 abort하거나 완료 대기한다.
3. `REG_OP_STATUS_CLR`로 done/error/page-buffer status를 정리한다.
4. `REG_READOUT_CTRL.SOURCE=NONE`으로 host read output source를 idle로 둔다.
5. Register Bank가 `REG_NAND_STATUS`를 ready/pass 상태로 반영할 수 있게 한다.

Reset은 array erase를 의미하지 않는다. FW는 Decode FSM 내부 state를 직접 수정하지
않으며, 별도 reset/control signal이 정의된 경우에만 host-facing decode state reset을
요청한다.

### 6.2 `90h` Read ID

1. address cycle을 확인한다. Accepted Read ID address는 Register Bank가 Read Output
   Datapath용 snapshot으로 mirror한다.
2. `REG_READOUT_CTRL`로 Read ID output path를 준비한다.
3. VPL operation은 trigger하지 않는다.
4. `REG_NAND_STATUS`는 ready/pass로 유지된다.
5. 처리한 `HOST_CMD_IRQ` pending bit를 `REG_IRQ_STATUS` W1C로 clear한다.

### 6.3 `70h` Read Status

1. Register Bank가 관리하는 `REG_NAND_STATUS` image를 유지한다.
2. VPL busy 중이면 ready bit는 `0`, 완료 후 `1`이어야 한다.
3. `REG_READOUT_CTRL`로 status output path를 준비한다.
4. 별도 VPL operation은 trigger하지 않는다.
5. 처리한 `HOST_CMD_IRQ` pending bit를 `REG_IRQ_STATUS` W1C로 clear한다.

### 6.4 `00h` / `30h` Read Page

Setup/confirm이 모두 수신된 뒤:

1. column/row address를 block/page/column으로 변환한다.
2. `REG_BLOCK_SEL`, `REG_PAGE_SEL`, `REG_COL_SEL`을 설정한다.
3. optional bias register를 read profile로 설정한다.
4. `REG_OP_CTRL.OP_CODE = READ_PAGE`를 쓴다.
5. `IRQ_DONE_EN`을 set하고, bias profile 의도를 남기고 싶으면 `BIAS_CHECK_EN`을
   함께 set한다. 현재 `nand_vpl_executor.v`는 bias option bit를 snapshot으로
   받지만 mismatch check는 enforce하지 않는다.
6. `REG_OP_TRIGGER.START = 1`을 쓴다.
7. `REG_OP_STATUS.DONE` 또는 op done IRQ를 기다린다.
8. error가 없으면 `REG_READOUT_CTRL`로 page buffer output path를 host read data path에 연결한다.
9. 처리한 host event와 op done/error pending은 `REG_IRQ_STATUS` W1C로 clear하고, 필요한 op/page-buffer status는 `REG_OP_STATUS_CLR`로 정리한다.

VPL 결과는 `page_buffer <= mem[block][page]`이다.

### 6.5 `80h` / `10h` Page Program

Setup/data/confirm이 모두 수신된 뒤:

1. column/row address를 block/page/column으로 변환한다.
2. host data payload가 page buffer에 들어갔고 `PB_PROG_READY=1`인지 확인한다.
3. `REG_BLOCK_SEL`, `REG_PAGE_SEL`, `REG_COL_SEL`을 설정한다.
4. optional bias register를 program profile로 설정한다.
5. `REG_OP_CTRL.OP_CODE = PROGRAM_PAGE`를 쓴다. Register Bank는 START snapshot에서
   마지막 정상 PROGRAM host event의 `REG_HOST_DATA_COUNT`를 PROGRAM transfer byte
   count로 VPL에 전달한다.
6. `IRQ_DONE_EN`, `IRQ_ERROR_EN`을 set한다. `WP_CHECK_EN`, `STRICT_PROGRAM`,
   `BIAS_CHECK_EN`은 command snapshot에 의도 bit로 남길 수 있지만, 현재
   `nand_vpl_executor.v`는 write-protect, strict erased-page, bias mismatch check를
   enforce하지 않는다.
7. `REG_OP_TRIGGER.START = 1`을 쓴다.
8. `REG_OP_STATUS.DONE` 또는 op done/error IRQ를 기다린다.
9. `REG_OP_ERROR`와 `REG_NAND_STATUS[0]`를 확인한다.
10. program source page buffer를 다시 받을 수 있게 `REG_OP_STATUS_CLR.PB_PROG_CLEAR`를 쓴다.
11. 처리한 host event와 op done/error pending은 `REG_IRQ_STATUS` W1C로 clear하고, 필요한 op/page-buffer status는 `REG_OP_STATUS_CLR`로 정리한다.

VPL 결과는 `mem[block][page] <= mem[block][page] & page_buffer`이다.

### 6.6 `60h` / `D0h` Block Erase

Setup/confirm이 모두 수신된 뒤:

1. row address를 block index로 변환한다.
2. `REG_BLOCK_SEL`을 설정한다.
3. optional bias register를 erase profile로 설정한다.
4. `REG_OP_CTRL.OP_CODE = ERASE_BLOCK`를 쓴다.
5. `IRQ_DONE_EN`, `IRQ_ERROR_EN`을 set한다. `WP_CHECK_EN`, `BIAS_CHECK_EN`은
   command snapshot에 의도 bit로 남길 수 있지만, 현재 `nand_vpl_executor.v`는
   write-protect와 bias mismatch check를 enforce하지 않는다.
6. `REG_OP_TRIGGER.START = 1`을 쓴다.
7. `REG_OP_STATUS.DONE` 또는 op done/error IRQ를 기다린다.
8. `REG_OP_ERROR`와 `REG_NAND_STATUS[0]`를 확인한다.
9. 처리한 host event와 op done/error pending은 `REG_IRQ_STATUS` W1C로 clear하고, 필요한 op status는 `REG_OP_STATUS_CLR`로 정리한다.

VPL 결과는 selected block 전체가 `8'hFF`가 되는 것이다.

## 7. IRQ 정책

합성 Decode FSM과 FW 분리를 고려하면, command/address/data/confirm이 모인
transaction-complete 시점에 FW IRQ를 1회 발생시키는 계약이 가장 단순하다.

권장 IRQ event source:

| IRQ | Source | FW 동작 |
| --- | --- | --- |
| `HOST_CMD_IRQ` | Register Bank가 Host Event Adapter payload를 accept | mailbox payload를 읽고 command handler 진입 |
| `OP_DONE_IRQ` | Register Bank가 VPL done response를 accept | status 확인 후 host ready |
| `OP_ERROR_IRQ` | Register Bank가 VPL error response를 accept | fail status 반영 |

Decode FSM과 VPL은 FW-visible IRQ line을 직접 drive하지 않는다. 이들은 Register Bank가
pending bit로 latch할 event/result source를 제공한다. IRQ pending, enable, W1C,
output level 정책은 `nand_register_bank.md`를 따른다.

## 8. FW와 VPL 경계

FW가 결정하는 것:

- decoded host transaction에 대해 어떤 command handler를 실행할 것인가
- target block/page/column
- read/program/erase 중 무엇을 실행할지
- optional bias register에 어떤 의도를 남길지
- strict program, wp check, bias check 사용 여부

Register Bank가 관리하는 것:

- decoded event mailbox payload와 `REG_IRQ_STATUS.HOST_CMD_IRQ` W1C clear
- IRQ pending/enable과 FW-visible interrupt output
- `REG_NAND_STATUS`, `REG_OP_STATUS`, `REG_OP_ERROR`의 FW-visible image
- VPL command snapshot과 VPL response capture

VPL이 결정하는 것:

- 현재 RTL에서 opcode/range/Page Buffer ready/overflow pre-check 결과
- memory/page buffer 갱신
- busy/done/error/status result

FW가 set하는 `STRICT_PROGRAM`, `WP_CHECK_EN`, `BIAS_CHECK_EN`은 현재 Register
Bank/VPL snapshot contract에 포함된 option intent bit다. 현재 executor는 이 bit들을
accept하지만 strict program, write-protect, bias mismatch check는 수행하지 않는다.
해당 check가 추가되더라도 FW flow와 Register Bank bitfield는 유지한다. 이 경계를
유지하면 FW는 NAND cell operation을 제어하는 모양을 갖고, VPL은 간결한 virtual NAND
executor로 남는다.

## 9. RV32 C FW 구현 메모

현재 RV32 path는 readable C firmware와 얇은 assembly startup veneer로 나눈다.

- C control logic은 `fw/nand_control_fw.c`에 둔다.
- Reset/IRQ vector, stack setup, `.bss` clear, IRQ register save/restore는
  `fw/nand_startup.S`가 담당한다.
- Linker script는 `fw/nand_linker.ld`를 사용한다. 현재 PoC는 RV32 agent-local
  32 KiB SRAM image에 `.text`, `.rodata`, `.data`, `.bss`를 배치하고 stack은 SRAM
  상단에서 아래로 자라게 둔다.
- Heap과 dynamic allocation은 사용하지 않는다. FW는 freestanding C로 작성하고
  MMIO helper, static/global state, stack-local variable만 사용한다.
- `nand_fw_main()`은 초기화 중 `REG_IRQ_ENABLE`을 설정한다. RV32 top path는 이
  write가 Register Bank에 accept된 뒤에만 host-facing ready gate를 연다.
- 이후 main loop는 idle 상태로 머물고, `nand_fw_irq_handler()`가
  `REG_IRQ_STATUS`를 읽어 host event와 VPL result를 처리한다.

## 10. Surrogate FW 구현 메모

Verilog surrogate FW agent는 RV32 path와 같은 Register Bank MMIO/IRQ contract를
사용하는 simulation control agent다. 구현은 아래 helper 경계를 따른다.

- `fw_read_host_mailbox()`
- `fw_decode_addr_to_target()`
- `fw_setup_read_bias()`
- `fw_setup_program_bias()`
- `fw_setup_erase_bias()`
- `fw_start_vpl_op(op_code, options)`
- `fw_wait_op_done_or_error()`
- `fw_finish_w1c_and_next_ready()`

RV32 C FW도 같은 기능 경계를 C helper 함수로 유지한다. 두 control agent는 같은
mailbox, IRQ/W1C, VPL command/result contract를 공유한다.

## Version History

| Version | Description |
| --- | --- |
| v0.15 | 현재 VPL executor가 enforce하지 않는 strict/wp/bias check를 option intent bit로 정리하고 FW/VPL pre-check 책임 표현을 RTL scope와 맞춤. |
| v0.14 | RV32 attach 세부 계약을 `nand_picorv32.md`로 라우팅. |
| v0.13 | legacy 전환 설명 섹션을 제거하고 Surrogate/RV32 FW를 현재 구현된 동일 MMIO contract의 두 control-agent path로 정리. |
| v0.12 | RV32 C FW/source layout, startup/linker/stack/BSS/no-heap 기준, FW-ready gate 초기화 흐름을 추가. |
| v0.11 | Read ID flow에서 accepted address snapshot이 Read Output Datapath table 선택에 사용됨을 명시. |
| v0.10 | PROGRAM flow에서 Register Bank가 `REG_HOST_DATA_COUNT`를 VPL transfer byte count로 snapshot한다는 점을 명시. |
| v0.9 | `REG_HOST_EVENT`는 RO view로 두고 host event clear는 `REG_IRQ_STATUS.HOST_CMD_IRQ` W1C로만 수행하도록 정리. |
| v0.8 | IRQ 수신 후 `REG_IRQ_STATUS`와 Host mailbox/VPL status를 읽는 FW entry flow를 명시. |
| v0.7 | 상세 MMIO map/bitfield를 `nand_register_bank.md`로 이동하고 FW flow 중심 문서로 정리. |
| v0.6 | Register Bank-owned host event mailbox, IRQ/W1C, NAND status, VPL command/response handoff, Read Output control contract 기준으로 정리. |
| v0.5 | 공유 파라미터 헤더 `nand_model/nand_parameters.vh` 기준으로 geometry macro 이름을 갱신. |
| v0.4 | Read Parameter Page 생략에 따른 SIMPLE 고정 geometry와 range-check 기반 address 변환 정책을 추가. |
| v0.3 | LEVEL register가 실제 전압/DAC code 의도이지만 SIMPLE 모델에서는 bias 의도/debug metadata로 쓰임을 명시. |
| v0.2 | MMIO 접근을 위한 offset, width, access, reset, bit field, reserved 정의를 register map에 추가. |
| v0.1 | FW가 Host command를 opcode/target/bias setup으로 변환하는 책임과 flow를 최초 정리. |
