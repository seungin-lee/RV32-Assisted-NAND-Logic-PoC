# NAND Cell Operation Reference
Version: v0.3

본 문서는 SIMPLE NAND 모델에서 `READ`, `PROGRAM`, `ERASE`를 설명할 때 사용할 cell-level 개념 기준을 정리한다.

이 모델은 실제 floating-gate/charge-trap cell transistor를 전기적으로 풀어내지 않는다. 대신 Host/FW/VPL 문서에서 "어떤 WL/BL/전압을 의도한 것인가"를 같은 언어로 설명할 수 있도록, SLC NAND의 기본 동작을 단순화한 reference로 사용한다.

## 1. 모델링 범위
이 문서는 다음을 정의한다.
- Erased/programmed state의 논리값 의미
- Read, Program, Erase 시 선택 WL, 비선택 WL, BL, SSL/GSL, source/bulk의 의도
- SIMPLE 모델에서 이를 어떻게 functional behavior로 축약하는지

이 문서는 다음을 정의하지 않는다.
- 실제 전압값, ISPP pulse 수, verify loop, threshold voltage distribution
- disturb, retention, wear, bad block, ECC
- transistor-level string current 또는 sense amplifier analog 동작

## 2. 기본 Cell State
SLC NAND 모델에서는 한 cell이 1 bit를 저장한다고 본다.

| Cell 상태 | 논리값 | SIMPLE 모델 표현 | 의미 |
| --- | ---: | --- | --- |
| Erased | `1` | `mem bit = 1` | 전자가 제거된 상태로 간주 |
| Programmed | `0` | `mem bit = 0` | 전자가 주입된 상태로 간주 |

따라서 erased block은 byte 기준 `8'hFF`로 초기화된다. Program은 `1 -> 0`만 만들 수 있고, `0 -> 1` 복구는 erase를 통해서만 가능하다고 본다.

## 3. NAND String 관점
한 NAND string은 여러 cell이 직렬로 연결된 구조로 추상화한다.

```text
BL -- SSL -- Cell(WL63) -- ... -- Cell(WL0) -- GSL -- Source Line
```

Read/Program에서는 선택된 page가 하나의 selected WL이 된다. 같은 string의 나머지 WL은 selected cell을 제외한 path가 열리도록 pass bias를 받는 것으로 표현한다.

Erase는 page가 아니라 block 단위 동작이다. 선택 block 안의 모든 WL이 erase 대상이 된다.

## 4. Read Operation
Read는 selected page의 cell state를 BL 전류/전압 변화로 sense해서 page buffer에 적재하는 동작이다. 목적은 cell을 바꾸는 것이 아니라, selected WL에 연결된 cell이 erased인지 programmed인지 판별하는 것이다.

Selected WL에는 read 기준 전압(`VREAD`)을 건다. 이 전압은 cell state에 따라 string path가 도통되는지 달라지도록 고른 기준점이다. Unselected WL에는 `VPASS` 또는 read-pass 계열 전압을 걸어야 한다. 그래야 읽고 싶은 cell이 아닌 나머지 cell들이 pass transistor처럼 열리고, selected cell 하나의 상태가 BL sense 결과를 지배한다.

BL은 먼저 precharge된 뒤 floating/sense 상태가 된다. selected cell이 read 조건에서 도통되면 BL 전압이 source line 쪽으로 변하고, 도통되지 않으면 precharge 상태가 더 유지된다. SSL/GSL은 string과 BL/source line을 연결하기 위해 ON이 되고, source line은 GND 기준으로 둔다.

### 4.1 Line/Bias 의도
| Node/Register | 기대 설정 | 이유 |
| --- | --- | --- |
| Selected WL / `REG_VREAD_LEVEL` | `VREAD` code | selected cell의 threshold state를 판별하는 기준 전압 |
| Unselected WL / `REG_VPASS_LEVEL` | `VPASS` 또는 read-pass code | 선택되지 않은 cell을 pass path로 열기 위함 |
| `REG_BL_CTRL` | `BL_PRECHARGE_FLOAT` | BL을 precharge한 뒤 cell state에 따른 변화를 sense |
| `REG_WL_CTRL` | selected=`VREAD`, unselected=`VPASS` | selected WL만 판별 대상, 나머지 WL은 pass 역할 |
| `REG_LINE_CTRL` | `ROW_DEC_EN`, `SSL_ON`, `GSL_ON`, `SL_GND_EN` | target row/string을 선택하고 BL-source path 구성 |
| `REG_BIAS_PROFILE` | `READ_BIAS` | optional bias checker가 read 의도를 확인 |

### 4.2 기대 결과
정상 read에서는 array의 cell state가 바뀌지 않는다. 기대 결과는 selected page의 논리값이 page buffer에 반영되고, 이후 host read data cycle에서 같은 byte sequence가 출력되는 것이다.

단, 우리 모델에서는 analog BL precharge/sense와 threshold 비교를 계산하지 않는다. FW가 `READ_BIAS` 의도를 남길 수는 있지만, VPL functional path는 아래처럼 array byte를 page buffer로 복사한다.

```text
page_buffer[0:PAGE_BYTES-1] <= mem[block][page][0:PAGE_BYTES-1]
```

Host 관점에서는 이후 `re_n` 토글에 따라 page buffer byte가 출력된다.

## 5. Program Operation
Program은 selected page의 erased bit 중 일부를 programmed state, 즉 논리 `0`으로 낮추는 동작이다. NAND program은 기본적으로 `1 -> 0` 방향만 가능하고, 이미 `0`인 cell을 program으로 `1`로 되돌릴 수 없다.

Selected WL에는 높은 program 전압(`VPGM`)을 인가한다. 이 전압은 selected cell에 전자 주입이 일어날 수 있는 조건을 만들기 위한 것이다. Unselected WL에는 `VPASS`를 걸어 string path를 열되, selected WL처럼 강한 program 조건이 생기지 않도록 한다.

BL은 모든 bit가 같은 전압을 받지 않는다. Page buffer bit가 `0`인 위치는 program 대상이므로 해당 BL은 low/GND 계열로 둔다. Page buffer bit가 `1`인 위치는 inhibit 대상이므로 해당 BL은 high/VDD 계열로 두어 channel boosting이 일어나고, selected WL에 `VPGM`이 있어도 cell이 program되지 않도록 막는 의미를 갖는다.

### 5.1 Line/Bias 의도
| Node/Register | 기대 설정 | 이유 |
| --- | --- | --- |
| Selected WL / `REG_VPGM_LEVEL` | `VPGM` code | selected cell에 program 조건 형성 |
| Unselected WL / `REG_VPASS_LEVEL` | `VPASS` code | string path를 열면서 unselected cell program을 피함 |
| `REG_BL_CTRL` | `BL_PB_CONTROL` | page buffer bit별로 program/inhibit BL을 결정 |
| `REG_WL_CTRL` | selected=`VPGM`, unselected=`VPASS` | selected WL만 program 대상 |
| `REG_LINE_CTRL` | `ROW_DEC_EN`, `SSL_ON`, `GSL_ON`, `SL_GND_EN` | target row/string을 선택하고 program path 구성 |
| `REG_BIAS_PROFILE` | `PROGRAM_BIAS` | optional bias checker가 program 의도를 확인 |

### 5.2 Page Buffer와 BL의 관계
Page program에서 BL 상태는 전역 1 bit 제어로 표현하기 어렵다. 각 bitline은 page buffer bit에 의해 program 또는 inhibit로 나뉜다.

| `page_buffer` bit | BL 의미 | 결과 |
| ---: | --- | --- |
| `0` | Program 대상 BL | cell이 `0`으로 내려갈 수 있음 |
| `1` | Program inhibit BL | cell 값을 유지 |

### 5.3 기대 결과
정상 program 이후 기대 결과는 page buffer에서 `0`인 bit만 target page에서 `0`으로 내려가고, page buffer에서 `1`인 bit는 기존 값을 유지하는 것이다. 따라서 old cell이 이미 `0`이면 page buffer가 `1`이어도 다시 `1`이 되지 않는다.

단, 우리 모델에서는 `VPGM` pulse, channel boosting, verify loop를 계산하지 않는다. `REG_BL_CTRL=BL_PB_CONTROL`의 의미를 page buffer mask로 축약하고, VPL은 program 결과를 bitwise AND로 모델링한다.

```text
mem[block][page] <= mem[block][page] & page_buffer
```

예:

```text
old mem     = 1111_0000
page_buffer = 1010_1010
result      = 1010_0000
```

`page_buffer`가 `1`인 bit는 inhibit 의미이므로 기존 `0`을 `1`로 되돌리지 않는다.

## 6. Erase Operation
Erase는 선택 block 전체를 erased state, 즉 논리 `1`로 되돌리는 동작이다. NAND에서 erase는 page 단위가 아니라 block 단위로 일어난다. Program과 반대로 cell에 저장된 전자를 제거하는 방향의 동작으로 단순화한다.

Erase 시에는 선택 block의 모든 WL을 0V 계열로 두고, bulk/substrate 또는 erase domain에 erase 전압(`VERS`)을 건다고 본다. 이 전압 차이가 block 안 cell들을 erased state로 이동시키는 조건이다. SSL/GSL과 BL은 read/program처럼 string current path를 적극적으로 만들 필요가 없으므로 floating 또는 high-z 의미로 둔다.

### 6.1 Line/Bias 의도
| Node/Register | 기대 설정 | 이유 |
| --- | --- | --- |
| Selected block WL / `REG_WL_CTRL.ALL_WL_0V` | all selected block WL = 0V | block 전체 cell을 erase 대상에 포함 |
| Bulk/Substrate / `REG_VERS_LEVEL` | `VERS` code | erase 전압 domain 활성화 |
| `REG_BL_CTRL` | `BL_HIGH_Z` | erase 중 BL은 active program/read path가 아님 |
| `REG_LINE_CTRL` | `BULK_ERASE_EN`, `SSL_FLOAT`, `GSL_FLOAT` | erase domain을 켜고 select line을 floating 의미로 둠 |
| `REG_BIAS_PROFILE` | `ERASE_BIAS` | optional bias checker가 erase 의도를 확인 |

### 6.2 기대 결과
정상 erase 이후 기대 결과는 target block의 모든 page, 모든 byte가 erased value인 `8'hFF`가 되는 것이다. `REG_PAGE_SEL`은 erase 동작의 functional target을 좁히지 않는다.

단, 우리 모델에서는 erase voltage ramp, erase verify, over-erase, disturb를 계산하지 않는다. VPL은 block 안의 모든 page byte를 `8'hFF`로 설정한다.

```text
for each page in block:
    mem[block][page][0:PAGE_BYTES-1] <= 8'hFF
```

`REG_PAGE_SEL`은 erase functional path에서 무시된다.

## 7. Optional Bias Register 의미
SIMPLE 모델은 아래 bias/control register를 operation 판정 근거로 사용하지 않는 것을 기본으로 한다. 이 register들은 FW가 물리 sequence를 의도했다는 것을 남기기 위한 교육용, 디버그용, 선택적 checker용 신호다.

`REG_VREAD_LEVEL`, `REG_VPGM_LEVEL`, `REG_VPASS_LEVEL`, `REG_VERS_LEVEL`의 `LEVEL`은 원래 실제 전압 level 또는 voltage generator/DAC code를 의미한다. 단, 우리 모델에서는 WL/BL/bulk에 걸리는 실제 전압 크기를 계산하지 않으므로, 이 값들은 "해당 bias를 걸었다"는 의도 표현에 가깝다. 필요하면 `0`이 아닌지 정도를 checker로 볼 수 있지만, 기본 functional result는 level 값이 아니라 `OP_CODE`와 page/block/page_buffer 상태로 결정된다.

| Register 계열 | 의미 |
| --- | --- |
| `REG_VREAD_LEVEL` | read selected WL voltage code |
| `REG_VPGM_LEVEL` | program selected WL voltage code |
| `REG_VPASS_LEVEL` | unselected WL pass voltage code |
| `REG_VERS_LEVEL` | erase voltage domain code |
| `REG_BL_CTRL` | BL high-z, force, precharge, page-buffer-control 의미 |
| `REG_WL_CTRL` | selected/unselected WL bias source 의미 |
| `REG_LINE_CTRL` | row decoder, SSL/GSL, source, erase domain 의미 |
| `REG_BIAS_PROFILE` | `READ_BIAS`, `PROGRAM_BIAS`, `ERASE_BIAS` template ID |

`BIAS_CHECK_EN=1`인 경우에도 VPL은 복잡한 전압 조합 전체를 해석하지 않고, `REG_BIAS_PROFILE`이 `OP_CODE`와 맞는지만 검사하는 것을 권장한다.

각 operation의 권장 profile은 아래와 같다.

| Operation | `REG_BL_CTRL` | `REG_WL_CTRL` | `REG_LINE_CTRL` 핵심 bit | `REG_BIAS_PROFILE` |
| --- | --- | --- | --- | --- |
| Read | `BL_PRECHARGE_FLOAT` | selected=`VREAD`, unselected=`VPASS` | `ROW_DEC_EN`, `SSL_ON`, `GSL_ON`, `SL_GND_EN` | `READ_BIAS` |
| Program | `BL_PB_CONTROL` | selected=`VPGM`, unselected=`VPASS` | `ROW_DEC_EN`, `SSL_ON`, `GSL_ON`, `SL_GND_EN` | `PROGRAM_BIAS` |
| Erase | `BL_HIGH_Z` | `ALL_WL_0V` | `BULK_ERASE_EN`, `SSL_FLOAT`, `GSL_FLOAT` | `ERASE_BIAS` |

## 8. 문서 간 역할
- `nand_cell_operation.md`: cell operation을 설명하는 개념 reference
- `nand_model_vpl.md`: FW가 명시한 `OP_CODE`를 받아 array/page buffer를 갱신하는 VPL 계약
- `nand_control_fw.md`: Host command를 해석하고 target/bias/opcode/trigger를 설정하는 FW 계약

---

## Version History
| Version | 변경사항 |
| --- | --- |
| v0.3 | LEVEL register가 실제 전압 code 의도이나 SIMPLE 모델에서는 bias 설정 의도 표현으로 쓰임을 추가. |
| v0.2 | Read/Program/Erase별 bias 이유, 기대 결과, 우리 모델의 축약 동작을 보강. |
| v0.1 | Read/Program/Erase의 WL/BL/bias 의미와 SIMPLE functional 축약 기준을 최초 정리. |
