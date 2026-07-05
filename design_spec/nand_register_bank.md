# NAND Register Bank
Version: v0.9
Status: active

## 1. Document Purpose

본 문서는 SIMPLE NAND model의 Register Bank/MMIO contract를 정의한다. Register
offset, bit field, access class, W1C side effect, IRQ pending/enable, Host Event
mailbox, VPL command/response, Read Output control은 이 문서를 canonical source로
한다.

상위 구조와 clock/domain 배치는 `Architecture.md`를 따른다. FW flow는
`nand_control_fw.md`, VPL operation semantics는 `nand_model_vpl.md`, Decode FSM
event handoff와 Page Buffer Adapter contract는 `nand_adapter_contracts.md`를
따른다. Reusable register-bank IP 위치와 PicoRV32 integration 경계는
`nand_picorv32.md`를 따른다.

## 2. Design Principles

- Register Bank는 coreclk/MMIO domain에 위치한다.
- FW-visible register는 32-bit word MMIO access를 기본으로 한다.
- Reserved bit는 read `0`, write ignored로 둔다.
- Hardware event/status set과 FW W1C clear가 같은 cycle에 겹치면 hardware set이
  우선한다.
- Decode FSM, Host Event Adapter, VPL은 FW-visible IRQ line을 직접 drive하지 않는다.
- Register Bank는 pending/status/enable/W1C state를 소유한다. IRQ output은
  `|(REG_IRQ_STATUS & REG_IRQ_ENABLE)` level로 만든다.
- Multi-bit host event payload는 valid/ready handoff로 atomic capture한다.
- Pending host event가 clear되기 전에는 같은 mailbox를 덮어쓰지 않는다.

## 3. Address Map

| Offset | Register | Width | Access | Reset | Description |
| ---: | --- | ---: | --- | ---: | --- |
| `0x00` | `REG_HOST_CMD` | 8 | RO | `0x00` | accepted transaction command |
| `0x04` | `REG_HOST_ADDR0` | 8 | RO | `0x00` | accepted address byte 0 |
| `0x08` | `REG_HOST_ADDR1` | 8 | RO | `0x00` | accepted address byte 1 |
| `0x0C` | `REG_HOST_ADDR2` | 8 | RO | `0x00` | accepted address byte 2 |
| `0x10` | `REG_HOST_ADDR3` | 8 | RO | `0x00` | accepted address byte 3 |
| `0x14` | `REG_HOST_ADDR4` | 8 | RO | `0x00` | accepted address byte 4 |
| `0x18` | `REG_HOST_META` | 32 | RO | `0x00000000` | decoded op, address count, protocol error |
| `0x1C` | `REG_HOST_EVENT` | 2 | RO | `0x0` | host transaction mailbox pending/error view |
| `0x20` | `REG_NAND_STATUS` | 8 | RO | `0xC0` | host-visible NAND status image |
| `0x24` | `REG_IRQ_STATUS` | 3 | RO/W1C | `0x0` | IRQ pending status |
| `0x28` | `REG_IRQ_ENABLE` | 3 | RW | `0x0` | IRQ output enable mask |
| `0x2C` | `REG_HOST_DATA_COUNT` | 13 | RO | `0x0` | accepted program data byte count |
| `0x30` | `REG_BLOCK_SEL` | 32 | RW | `0x00000000` | target block index |
| `0x34` | `REG_PAGE_SEL` | 32 | RW | `0x00000000` | target page/WL index |
| `0x38` | `REG_COL_SEL` | 32 | RW | `0x00000000` | column offset |
| `0x3C` | `REG_PAGE_BYTES` | 32 | RO | 구현값 | page byte size |
| `0x40` | `REG_OP_CTRL` | 32 | RW | `0x00000000` | VPL opcode/options |
| `0x44` | `REG_OP_TRIGGER` | 1 | WO | `0x0` | VPL start pulse |
| `0x48` | `REG_OP_STATUS` | 6 | RO | `0x00` | VPL busy/done/error/page-buffer state |
| `0x4C` | `REG_OP_STATUS_CLR` | 4 | WO | `0x0` | op/page-buffer status clear pulse |
| `0x50` | `REG_OP_ERROR` | 8 | RO | `0x00` | last VPL error code |
| `0x54` | `REG_OP_LATENCY` | 32 | RW | `0x00000000` | simulation busy delay cycle/scale |
| `0x58` | `REG_READOUT_CTRL` | 8 | RW | `0x00` | Read Output source/mode snapshot control |
| `0x5C` | Reserved | 32 | - | - | reserved |
| `0x60` | `REG_VREAD_LEVEL` | 8 | RW | `0x00` | read selected WL voltage code |
| `0x64` | `REG_VPGM_LEVEL` | 8 | RW | `0x00` | program selected WL voltage code |
| `0x68` | `REG_VPASS_LEVEL` | 8 | RW | `0x00` | unselected WL pass voltage code |
| `0x6C` | `REG_VERS_LEVEL` | 8 | RW | `0x00` | erase voltage domain code |
| `0x70` | `REG_BL_CTRL` | 3 | RW | `0x0` | bitline control mode |
| `0x74` | `REG_WL_CTRL` | 9 | RW | `0x000` | wordline bias control |
| `0x78` | `REG_LINE_CTRL` | 7 | RW | `0x00` | row/SSL/GSL/source/bulk line control |
| `0x7C` | `REG_BIAS_PROFILE` | 2 | RW | `0x0` | optional bias profile ID |

## 4. Host Event Mailbox

Register Bank는 Host Event Adapter의 `reg_event_valid/reg_event_ready` handshake가
accept된 cycle에 decoded transaction payload를 atomic하게 capture한다.

Capture된 `REG_HOST_CMD`, `REG_HOST_ADDR*`, `REG_HOST_META`,
`REG_HOST_DATA_COUNT`는 `REG_IRQ_STATUS.HOST_CMD_IRQ`가 W1C clear될 때까지
stable하게 유지한다. `HOST_EVENT_PENDING=1`인 동안 Register Bank는
`reg_event_ready=0`으로 같은 mailbox overwrite를 막는다.

### 4.1 `REG_HOST_META`

| Bit | Name | Description |
| ---: | --- | --- |
| `[3:0]` | `DECODED_OP` | Decode FSM operation encoding. `onfi_sdr_defs.vh`의 `ONFI_OP_*`를 따른다. |
| `[6:4]` | `ADDR_COUNT` | accepted transaction의 address byte 수 |
| `[7]` | `PROTOCOL_ERROR` | Decode FSM이 protocol error transaction으로 분류했으면 `1` |
| `[11:8]` | `PROTOCOL_ERROR_CODE` | `onfi_sdr_defs.vh`의 `ONFI_ERR_*` encoding |
| `[31:12]` | Reserved | read `0`, write ignored |

### 4.2 `REG_HOST_EVENT`

| Bit | Name | Description |
| ---: | --- | --- |
| `[0]` | `HOST_EVENT_PENDING` | decoded transaction mailbox valid view. `REG_IRQ_STATUS.HOST_CMD_IRQ`와 같은 host mailbox pending source를 보여준다. |
| `[1]` | `HOST_EVENT_ERROR` | `REG_HOST_META.PROTOCOL_ERROR`가 set된 transaction 수신 view. `REG_IRQ_STATUS.HOST_CMD_IRQ` W1C clear 시 함께 clear된다. |
| `[31:2]` | Reserved | read `0`, write ignored |

`REG_HOST_EVENT`는 FW debug/mailbox view이며 clear owner가 아니다. FW는 host mailbox
payload를 모두 읽은 뒤 `REG_IRQ_STATUS.HOST_CMD_IRQ`에 `1`을 써서 host event pending과
error view를 clear한다. `REG_HOST_EVENT` write는 ignored로 둔다.

`CMD_VALID`, `ADDR_VALID`, `DATA_IN_DONE` 같은 phase flag는 Register Bank contract로
노출하지 않는다. Phase 해석은 Decode FSM 내부 책임이고, FW가 보는 단위는 completed
decoded transaction이다.

### 4.3 Reusable `soc_regbank` Payload Word Packing

Reusable `soc_regbank`의 parameterized payload window를 재사용하는 경우, Host Event
Adapter event는 `nand_register_bank.v`에서 아래 8-word mailbox payload로 확장한다.
이 packing은 public NAND register map의 host mailbox register와 1:1로 대응되도록
정렬한다. Generic `soc_regbank` IP는 payload word의 의미를 모르고, public
register 이름과 bitfield 해석은 NAND Register Bank RTL이 담당한다.

| Payload word | Bit field | Description |
| ---: | --- | --- |
| `0` | `[7:0] cmd` | `REG_HOST_CMD` |
| `1` | `[7:0] addr0` | `REG_HOST_ADDR0` |
| `2` | `[7:0] addr1` | `REG_HOST_ADDR1` |
| `3` | `[7:0] addr2` | `REG_HOST_ADDR2` |
| `4` | `[7:0] addr3` | `REG_HOST_ADDR3` |
| `5` | `[7:0] addr4` | `REG_HOST_ADDR4` |
| `6` | `[3:0] decoded_op`, `[6:4] addr_count`, `[7] protocol_error`, `[11:8] protocol_error_code` | `REG_HOST_META` |
| `7` | `[12:0] prog_data_count` | `REG_HOST_DATA_COUNT` |

## 5. NAND Status

### 5.1 `REG_NAND_STATUS`

| Bit | Name | Description |
| ---: | --- | --- |
| `[0]` | `FAIL` | `1`이면 마지막 program/erase/read operation fail |
| `[5:1]` | Reserved | read `0`, write ignored |
| `[6]` | `READY` | `1=Ready`, `0=Busy`; VPL response/status 기준으로 Register Bank가 갱신 |
| `[7]` | `WP_N` | `wp_n` mirror. 가능하면 HW가 pin 상태로 overwrite |
| `[31:8]` | Reserved | read `0`, write ignored |

`REG_NAND_STATUS`는 Register Bank-owned status image다. FW와 VPL은 이 register를
직접 동시에 쓰지 않는다. VPL은 result source만 제공하고, Register Bank가 host-visible
status image를 갱신한다.

## 6. IRQ

### 6.1 `REG_IRQ_STATUS` / `REG_IRQ_ENABLE`

| Bit | Name | Set source | FW action |
| ---: | --- | --- | --- |
| `[0]` | `HOST_CMD_IRQ` | Host Event Adapter payload accept | mailbox payload 처리 후 W1C clear. `REG_HOST_EVENT` view도 함께 clear |
| `[1]` | `OP_DONE_IRQ` | VPL done response accept | status 확인 후 W1C clear |
| `[2]` | `OP_ERROR_IRQ` | VPL error response accept | fail/error 처리 후 W1C clear |
| `[31:3]` | Reserved | - | read `0`, write ignored |

`REG_IRQ_STATUS`는 W1C pending register다. `REG_IRQ_ENABLE`은 같은 bit 위치의 output
mask다. FW-visible IRQ line은 level interrupt로 시작하며 아래 식을 따른다.

```text
irq_o = |(REG_IRQ_STATUS & REG_IRQ_ENABLE)
```

Interrupt output pulse를 직접 만들지 않는다.

## 7. VPL Command Registers

### 7.1 Target Registers

| Register | Description |
| --- | --- |
| `REG_BLOCK_SEL` | target block index |
| `REG_PAGE_SEL` | target page/WL index. `ERASE_BLOCK`에서는 무시 |
| `REG_COL_SEL` | column offset |
| `REG_PAGE_BYTES` | geometry page byte size. `nand_model/nand_parameters.vh`의 `NAND_PAGE_SIZE` 기준 |

VPL command snapshot의 transfer byte count는 operation별로 다르다.

- `READ_PAGE`: `REG_PAGE_BYTES` 값, 즉 full page size를 전달한다. Page Buffer는 full-page mirror로 채워지고 `REG_COL_SEL`은 readout pointer/range 의미로 유지한다.
- `PROGRAM_PAGE`: 마지막 정상 PROGRAM host event의 accepted data byte count인 `REG_HOST_DATA_COUNT`를 전달한다. VPL은 이 byte 수만큼 Page Buffer를 읽어 target page에 program한다.
- `ERASE_BLOCK`: VPL은 page byte count를 사용하지 않고 block geometry를 기준으로 erase한다.

### 7.2 `REG_OP_CTRL`

| Bit | Name | Description |
| ---: | --- | --- |
| `[2:0]` | `OP_CODE` | `0=NONE`, `1=READ_PAGE`, `2=PROGRAM_PAGE`, `3=ERASE_BLOCK`, others reserved |
| `[7:3]` | Reserved | read `0`, write ignored |
| `[8]` | `STRICT_PROGRAM` | target page가 erased 상태가 아니면 program error |
| `[9]` | `BIAS_CHECK_EN` | `REG_BIAS_PROFILE`이 `OP_CODE`와 맞는지 검사 |
| `[10]` | `WP_CHECK_EN` | `wp_n=0`일 때 program/erase 거부 |
| `[15:11]` | Reserved | read `0`, write ignored |
| `[16]` | `IRQ_DONE_EN` | VPL done response 수신 시 `OP_DONE_IRQ` pending set |
| `[17]` | `IRQ_ERROR_EN` | VPL error response 수신 시 `OP_ERROR_IRQ` pending set |
| `[31:18]` | Reserved | read `0`, write ignored |

`STRICT_PROGRAM`, `BIAS_CHECK_EN`, `WP_CHECK_EN`은 VPL command snapshot에 실리는
option intent bit다. 현재 `nand_vpl_executor.v`는 이 bit들을 payload로 accept하지만
strict erased-page check, write-protect check, bias-profile mismatch check는 아직
enforce하지 않는다. 현재 executor가 실제로 반환하는 pre-check error는 opcode, block,
page, column, Page Buffer ready/overflow 범위다. optional checker가 추가되면 이
bit들과 아래 reserved error code 의미를 그대로 사용한다.

### 7.3 `REG_OP_TRIGGER`

| Bit | Name | Description |
| ---: | --- | --- |
| `[0]` | `START` | `1` write 시 Register Bank가 command snapshot을 만들고 VPL Command/Response Adapter로 operation 시작. HW auto-clear |
| `[31:1]` | Reserved | read `0`, write ignored |

`START` write가 accepted되면 Register Bank는 `REG_OP_CTRL`, target register,
`REG_BIAS_PROFILE`, 필요한 option/bias/debug register를 snapshot으로 묶어 VPL
Command/Response Adapter에 전달한다. Operation 진행 중 FW가 live register를 바꿔도
현재 VPL operation에는 영향을 주지 않는다.

## 8. Operation Status

### 8.1 `REG_OP_STATUS`

| Bit | Name | Description |
| ---: | --- | --- |
| `[0]` | `BUSY` | VPL operation 진행 중 |
| `[1]` | `DONE` | VPL operation 완료. `REG_OP_STATUS_CLR.DONE_CLR`로 clear |
| `[2]` | `ERROR` | VPL error 발생. `REG_OP_STATUS_CLR.ERROR_CLR`로 clear |
| `[3]` | `PB_VALID` | read 결과가 page buffer에 valid |
| `[4]` | `PB_PROG_READY` | program data가 page buffer에 준비됨 |
| `[5]` | `PB_OVERFLOW` | program data가 page buffer capacity를 초과 |
| `[31:6]` | Reserved | read `0`, write ignored |

### 8.2 `REG_OP_STATUS_CLR`

| Bit | Name | Description |
| ---: | --- | --- |
| `[0]` | `DONE_CLR` | `1` write 시 `DONE` clear |
| `[1]` | `ERROR_CLR` | `1` write 시 `ERROR` 및 `REG_OP_ERROR` clear |
| `[2]` | `PB_VALID_CLR` | `1` write 시 `PB_VALID` clear |
| `[3]` | `PB_PROG_CLEAR` | `1` write 시 Page Buffer Adapter의 program count/prog_ready/overflow clear 요청 |
| `[31:4]` | Reserved | read `0`, write ignored |

### 8.3 `REG_OP_ERROR`

| Value | Name | Meaning |
| ---: | --- | --- |
| `0x00` | `ERR_NONE` | 정상 |
| `0x01` | `ERR_INVALID_OP` | 지원하지 않는 opcode |
| `0x02` | `ERR_BUSY` | busy 중 start 재요청 |
| `0x03` | `ERR_BLOCK_RANGE` | block index 범위 초과 |
| `0x04` | `ERR_PAGE_RANGE` | page index 범위 초과 |
| `0x05` | `ERR_PB_NOT_READY` | program data가 page buffer에 준비되지 않음 |
| `0x06` | `ERR_WP_LOCKED` | write-protect 상태에서 program/erase 요청 |
| `0x07` | `ERR_PROGRAM_NOT_ERASED` | strict program에서 target page가 erased가 아님 |
| `0x08` | `ERR_BIAS_MISMATCH` | bias profile과 opcode 불일치 |
| `0x09` | `ERR_COL_RANGE` | column address가 page size 범위를 초과 |
| `0x0A` | `ERR_ROW_RANGE` | row address가 `NAND_TOTAL_PAGES` 범위를 초과 |
| `0x0B` | `ERR_ERASE_PAGE_BITS` | erase address의 page-in-block bit가 0이 아님 |
| `0x0C..0xFF` | Reserved | reserved |

현재 `nand_vpl_executor.v`가 직접 발생시키는 error code는 `ERR_INVALID_OP`,
`ERR_BLOCK_RANGE`, `ERR_PAGE_RANGE`, `ERR_PB_NOT_READY`, `ERR_COL_RANGE`다.
`ERR_BUSY`는 Register Bank가 busy 중 `START` 재요청에서 발생시킨다. 그 외 optional
checker용 code는 public contract에 예약해 두지만 현재 executor에서는 발생하지 않는다.

## 9. Read Output Control

### 9.1 `REG_READOUT_CTRL`

| Bit | Name | Description |
| ---: | --- | --- |
| `[1:0]` | `SOURCE` | `0=NONE`, `1=READ_ID`, `2=READ_STATUS`, `3=PAGE_BUFFER` |
| `[2]` | `ENABLE` | Read Output Datapath가 selected source를 host `re_n` read에 사용할 수 있음 |
| `[3]` | `PTR_RESET` | `1` write 시 Read Output Datapath pointer reset 요청. HW auto-clear |
| `[31:4]` | Reserved | read `0`, write ignored |

`REG_READOUT_CTRL`은 coreclk Register Bank에서 sysclk Read Output Datapath로 mirror되는
control snapshot이다. Read Output Datapath는 이 snapshot과 `REG_NAND_STATUS` mirror,
page buffer data를 사용한다.

Accepted `READ_ID` host event의 `REG_HOST_ADDR0` 값은 별도 FW-visible offset을 새로
만들지 않고 `readout_id_addr_o` snapshot으로 Read Output Mirror Adapter에 전달한다.
Read Output Datapath는 이 값을 사용해 `00h` 제조사/디바이스 ID table과 `20h` ONFI
signature table을 선택한다.

## 10. Optional Bias and Line Debug Registers

LEVEL register인 `REG_VREAD_LEVEL`, `REG_VPGM_LEVEL`, `REG_VPASS_LEVEL`,
`REG_VERS_LEVEL`은 원래 voltage generator/DAC code를 지정하는 의미다. SIMPLE 모델은
실제 전압 크기나 전압 간 관계를 계산하지 않으므로, 이 값들은 FW가 해당 bias를
설정했다는 의도 표현과 debug/check metadata로 사용한다.

Functional operation 판정은 `REG_OP_CTRL.OP_CODE`가 담당하고, 선택적 bias check는
`REG_BIAS_PROFILE`로 단순화한다.

### 10.1 `REG_BL_CTRL`

| Value | Name | Description |
| ---: | --- | --- |
| `0` | `BL_HIGH_Z` | BL floating/idle |
| `1` | `BL_FORCE_LOW` | 단일 cell 실험용 BL low |
| `2` | `BL_FORCE_HIGH` | 단일 cell 실험용 BL high/inhibit |
| `3` | `BL_PRECHARGE_FLOAT` | read용 BL precharge 후 sense |
| `4` | `BL_PB_CONTROL` | page buffer bit가 각 BL program/inhibit를 결정 |
| `5..7` | Reserved | reserved |

### 10.2 `REG_WL_CTRL`

| Bit | Name | Description |
| ---: | --- | --- |
| `[2:0]` | `SEL_WL_BIAS` | `0=0V/OFF`, `1=VREAD`, `2=VPGM`, `3=FLOAT`, others reserved |
| `[3]` | Reserved | read `0`, write ignored |
| `[6:4]` | `UNSEL_WL_BIAS` | `0=0V/OFF`, `1=VPASS`, `2=VREAD_PASS`, `3=FLOAT`, others reserved |
| `[7]` | Reserved | read `0`, write ignored |
| `[8]` | `ALL_WL_0V` | erase용. 선택 block의 모든 WL을 0V로 둔다는 의미 |
| `[31:9]` | Reserved | read `0`, write ignored |

### 10.3 `REG_LINE_CTRL`

| Bit | Name | Description |
| ---: | --- | --- |
| `[0]` | `ROW_DEC_EN` | target row/block 선택 의미. VPL trigger로 사용하지 않음 |
| `[1]` | `SSL_ON` | read/program에서 SSL ON 의미 |
| `[2]` | `GSL_ON` | read/program에서 GSL ON 의미 |
| `[3]` | `SL_GND_EN` | source line GND 의미 |
| `[4]` | `BULK_ERASE_EN` | erase voltage domain 활성화 의미 |
| `[5]` | `SSL_FLOAT` | erase 시 SSL floating 의미 |
| `[6]` | `GSL_FLOAT` | erase 시 GSL floating 의미 |
| `[31:7]` | Reserved | read `0`, write ignored |

### 10.4 `REG_BIAS_PROFILE`

| Value | Name | Description |
| ---: | --- | --- |
| `0` | `BIAS_NONE` | bias check 없음 또는 idle |
| `1` | `READ_BIAS` | `READ_PAGE` 기대 profile |
| `2` | `PROGRAM_BIAS` | `PROGRAM_PAGE` 기대 profile |
| `3` | `ERASE_BIAS` | `ERASE_BLOCK` 기대 profile |

### 10.5 Optional Bias / Line Debug Usage

| Register | Read sequence | Program sequence | Erase sequence |
| --- | --- | --- | --- |
| `REG_VREAD_LEVEL` | set | don't care | don't care |
| `REG_VPGM_LEVEL` | don't care | set | don't care |
| `REG_VPASS_LEVEL` | set | set | don't care |
| `REG_VERS_LEVEL` | don't care | don't care | set |
| `REG_BL_CTRL` | `BL_PRECHARGE_FLOAT` | `BL_PB_CONTROL` | `BL_HIGH_Z` |
| `REG_WL_CTRL` | selected=`VREAD`, unselected=`VPASS` | selected=`VPGM`, unselected=`VPASS` | `ALL_WL_0V` |
| `REG_LINE_CTRL` | row/SSL/GSL/source intent | row/SSL/GSL/source intent | bulk erase/floating intent |
| `REG_BIAS_PROFILE` | `READ_BIAS` | `PROGRAM_BIAS` | `ERASE_BIAS` |

`BIAS_CHECK_EN=0`이면 optional bias/line 값들은 VPL functional result에 영향을 주지
않는다.

## 11. RTL Implementation Notes

`nand_model/nand_register_bank.v`는 NAND repo 내부 reusable
`nand_model/soc_regbank.sv`를 instantiate한다.

구현 기준:

- `soc_regbank #(.PAYLOAD_WORDS(8), .IRQ_WIDTH(3))`를 사용한다.
- `soc_regbank`는 host event payload storage, `REG_IRQ_STATUS`,
  `REG_IRQ_ENABLE`, W1C merge rule, level `irq_o` generation을 담당한다.
- NAND Register Bank RTL은 public NAND MMIO offset remap, host mailbox unpack,
  `REG_HOST_EVENT` view, VPL command snapshot, VPL response status, Read Output
  control, Page Buffer clear/status, bias/debug register를 담당한다.
- Host Event Adapter ready는 host mailbox pending뿐 아니라 VPL command
  pending/busy와 FW가 아직 clear하지 않은 `REG_OP_STATUS.DONE/ERROR` sticky
  status가 남아 있을 때도 닫힌다.
- PicoRV32 core RTL 자체는 vendored IP로 취급하고, NAND-specific 연결은
  `nand_rv32_control_agent.v`와 Register Bank/MMIO contract에서 관리한다.

## Version History

| Version | Description |
| --- | --- |
| v0.9 | 현재 VPL executor가 enforce하는 pre-check 범위와 optional checker bit/error code의 예약 의미를 명확화하고 PicoRV32 외부 경로 표현을 vendored core 기준으로 정정. |
| v0.8 | `soc_regbank` 참조를 NAND-owned vendored IP와 `nand_picorv32.md` 기준으로 갱신. |
| v0.7 | 구현 완료 상태에 맞춰 문서 status를 active로 갱신. |
| v0.6 | Read Output Datapath의 Read ID table 선택을 위한 accepted Read ID address snapshot 출력을 명시. |
| v0.5 | VPL command snapshot transfer byte count를 READ full page, PROGRAM `REG_HOST_DATA_COUNT`, ERASE geometry 기준으로 명시. |
| v0.4 | `REG_HOST_EVENT`를 RO mailbox view로 정리하고 host event clear owner를 `REG_IRQ_STATUS.HOST_CMD_IRQ` W1C로 통일. |
| v0.3 | Adapter contract 문서 승격에 맞춰 `nand_adapter_contracts.md` 참조를 반영. |
| v0.2 | `nand_register_bank.v` 구현에 맞춰 PicoRV32 payload packing과 RTL reuse boundary를 갱신. |
| v0.1 | Register Bank canonical MMIO map, host mailbox, IRQ/W1C, VPL command/status, readout, bias/debug register contract 최초 작성. |
