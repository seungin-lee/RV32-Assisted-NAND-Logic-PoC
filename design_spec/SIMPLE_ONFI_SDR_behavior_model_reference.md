# Simple NAND ONFI SDR Behavioral Model Reference
Version: v0.3

본 문서는 SIMPLE NAND 모델에서 지원하는 일부 ONFI SDR 커맨드에 대해, Host Testbench(TB)가 인가해야 하는 트랜잭션 흐름과 NAND 모델이 보여야 하는 기대 동작(Expected Behavior)을 정리한 참조 문서이다.
완전한 ONFI 규격 호환 모델을 정의하는 문서가 아니며, 지원하는 커맨드는 Chapter 2에 명시되어 있다.

## 0. 모델 제약 사항 (Limitations & Assumptions)
본 문서는 핵심 동작 검증을 위한 SIMPLE NAND 모델의 동작 기댓값을 정의한다. 따라서 아래 항목은 모델의 의도된 제약 및 가정으로 본다.
- 초기화 간소화: ONFI 스펙의 Read Parameter Page(ECh) 및 Set Features 커맨드는 모델링하지 않는다. Host는 전원 인가 직후 별도의 모드 합의 과정 없이 SDR Timing Mode 0으로 통신을 시작한다고 가정한다.
- SDR Mode 0 전용: 본 모델은 기본 SDR Timing Mode 0 기준의 동작 검증을 목표로 한다.
- EDO 타이밍 생략: 고속 모드(Mode 4, Mode 5 등) 및 EDO(Extended Data Out) 데이터 래치 사이클은 검증 범위에서 제외한다.
- 부분 커맨드 지원: 본 문서에 명시되지 않은 ONFI 커맨드의 동작은 모델 검증 범위 밖이며, 모델 구현에 따라 무시되거나 에러 처리될 수 있다.
- Geometry 고정: Read Parameter Page(ECh)를 지원하지 않으므로 Host TB는 본 문서의 SIMPLE geometry와 address layout을 사전에 알고 있다고 가정한다.

### 0.1 SIMPLE 모델 주소 가정
실제 ONFI Host는 Read Parameter Page(ECh)를 통해 page size, pages per block, block count, LUN count 등을 읽고 address cycle 수와 row address bit layout을 결정한다.

본 모델은 ECh를 의도적으로 생략하므로 아래 geometry를 고정 계약으로 둔다.

| 항목 | 값 | 주소 의미 |
| --- | ---: | --- |
| Page size | 2048 bytes | column address는 0..2047 |
| Pages per block | 64 pages | row address의 하위 6 bit가 page-in-block |
| Blocks | 32 blocks | row address의 다음 5 bit가 block |
| LUN | 1 | LUN bit는 사용하지 않고 0으로 가정 |
| Plane | 1 | plane bit는 별도 해석하지 않음 |

Read/Page Program의 address cycle은 `C1, C2, R1, R2, R3`의 5 cycle을 사용한다.

Block Erase의 address cycle은 `R1, R2, R3`의 3 cycle을 사용한다.

Column address는 little-endian byte order로 전송한다.

```text
column = C1 + (C2 << 8)
```

Row address도 little-endian byte order로 전송한다.

```text
row = R1 + (R2 << 8) + (R3 << 16)
```

본 SIMPLE geometry에서 row address의 의미는 아래와 같다.

```text
row[5:0]   = page index inside block (0..63)
row[10:6]  = block index (0..31)
row[23:11] = reserved, must be 0
```

따라서 Host TB가 block `b`, page `p`에 접근하려면 아래와 같이 row를 만든다.

```text
row = (b * 64) + p
R1  = row[7:0]
R2  = row[15:8]
R3  = row[23:16]
```

예를 들어 block 5, page 10은 `row = 5 * 64 + 10 = 330 = 0x014A`이므로 `R1=4Ah`, `R2=01h`, `R3=00h`이다.

Host TB는 unsupported LUN/plane bit 또는 `row >= 2048`인 주소를 정상 접근으로 사용하지 않는다. 모델/checker는 이런 주소를 range violation으로 처리할 수 있다.

## 1. SDR 버스 상태 (Bus State) 정의
NAND SDR 인터페이스는 ce_n이 Low(0)로 활성화된 상태에서, cle, ale의 조합과 we_n, re_n의 토글(Toggle)에 의해 버스 상태가 결정됩니다.
- Command Cycle: `cle`=1, `ale`=0. `we_n`의 상승 에지(Rising Edge)에서 `dq[7:0]`의 명령어를 래치(Latch)합니다. 
- Address Cycle: `cle`=0, `ale`=1. `we_n`의 상승 에지에서 `dq[7:0]`의 주소를 래치합니다.
- Data Input Cycle: `cle`=0, `ale`=0. `we_n`의 상승 에지에서 호스트가 보낸 `dq[7:0]` 데이터를 래치합니다. (Host → NAND)
- Data Output Cycle: `cle`=0, `ale`=0. `re_n`이 Low로 drive 하면, NAND는 최대 `tREA`시간 이후에 `dq[7:0]`에 data를 드라이브(Drive)하며, 호스트는 데이터가 안정화된 시점인 re_n의 상승 에지에서 데이터를 래치합니다. (NAND → Host) 
본 모델에서는 고속 모드(e.g. Mode 5)나 EDO 타이밍 사이클을 고려하지 않습니다.

## 2. 주요 커맨드별 기대 동작 시퀀스 (Expected Behavior Sequences)
### 2.1 Reset (FFh)
디바이스를 기본 전원 켜짐 상태로 초기화하는 커맨드입니다.  
- Command Cycle: Host가 `dq`에 FFh를 인가하고 `we_n`을 토글합니다.
- Busy Transition (`tWB`): FFh 커맨드의 `we_n` 상승 에지 이후, NAND 모델은 최대 `tWB` 시간 이내에 `rb_n`을 Low(Busy)로 떨어뜨려야 합니다. Host TB는 이 구간에서 `rb_n`이 즉시 Low가 아닐 수 있음을 감안합니다.
- Reset Busy (`tRST`): NAND 모델은 `tRST` 시간 동안 Busy 상태를 유지한 후 `rb_n`을 High(Ready)로 복귀시킵니다.
- Expected Result: 내부 커맨드/주소/데이터 상태는 초기 상태로 복귀하며, 이후 Host는 SDR Mode 0 기준으로 새 커맨드를 인가할 수 있습니다.

### 2.2 Read ID (90h)
ONFI 시그니처나 제조사/디바이스 ID를 읽어오는 커맨드입니다.
- Command/Address Cycle: Host가 `dq`에 90h를 인가한 뒤, 00h(제조사 ID) 또는 20h(ONFI 시그니처) 주소 1 Cycle을 인가합니다.
- Ready & Wait (`tWHR`): Host TB는 주소 인가 후 최소 `tWHR` 시간이 지난 뒤 데이터 출력 요청을 시작해야 합니다.
- Data Output Cycle: Host가 `re_n`을 연속으로 토글하면, NAND 모델은 선택된 ID 영역의 바이트를 순차적으로 `dq[7:0]`에 출력합니다.
- Expected Result: 주소가 20h인 경우 ONFI 시그니처 바이트(예: 'O', 'N', 'F', 'I')가 순서대로 관측되어야 합니다. 주소가 00h인 경우 모델에 정의된 제조사/디바이스 ID가 순서대로 관측되어야 합니다.

### 2.3 Read Status (70h)
NAND의 내부 상태(Ready/Busy, Pass/Fail 등)를 읽어오는 커맨드입니다.
- Command Cycle: Host가 `dq`에 70h를 인가하고 `we_n`을 토글합니다.
- Ready & Wait (`tWHR`): Host TB는 커맨드 인가 후 최소 `tWHR` 시간이 지난 뒤 `re_n`을 토글합니다.
- Data Output Cycle: NAND 모델은 현재 내부 상태를 Status 바이트로 `dq[7:0]`에 출력합니다.
- Expected Result: bit 6은 Ready/Busy(1=Ready, 0=Busy), bit 0은 Pass/Fail(0=Pass, 1=Fail)을 나타냅니다. Program/Erase Busy 구간에서도 Read Status는 허용 커맨드로 처리되어야 합니다.
> HOST 는 70h 커맨드를 한번 인가한 후, `re_n`을 반복적으로 토글하여 상태 변화를 연속적으로 폴링할 수 있습니다.

### 2.4 Read Page (00h - 30h)
NAND 셀 어레이에서 페이지 레지스터로 데이터를 읽어온 후, 호스트로 전송하는 커맨드입니다.
- Command/Address Cycle: Host가 00h 커맨드, `C1, C2, R1, R2, R3`의 5 address cycle, 30h 커맨드를 순차적으로 인가합니다. `C1/C2`는 column little-endian이고, `R1/R2/R3`는 `0.1 SIMPLE 모델 주소 가정`의 row little-endian layout을 따른다.
- Busy Transition (`tWB`): 30h 커맨드의 마지막 `we_n` 상승 에지 이후, NAND 모델은 최대 `tWB` 시간 이내에 `rb_n`을 Low(Busy)로 떨어뜨려야 합니다. Host TB는 이 구간에서 `rb_n`이 즉시 Low가 아닐 수 있음을 감안하여 `tWB_max`까지 폴링 판정을 유예할 수 있습니다.
- Read Busy (`tR`): NAND 모델은 `tR` 시간 동안 `rb_n`=Low를 유지하며 내부 데이터를 페이지 버퍼로 로드하는 동작을 모사합니다. `tR` 경과 후 `rb_n`을 High(Ready)로 구동합니다.
- Ready & Wait (`tRR`): Host는 `rb_n`이 High가 된 것을 감지한 후, 최소 `tRR` 시간이 지난 뒤 데이터 출력을 요청할 수 있습니다.
- Data Output Cycle: Host가 `re_n`을 토글하면, NAND 모델은 `re_n` 하강 에지 감지 후 `tREA` 딜레이를 거쳐 `dq[7:0]`에 데이터를 출력합니다. Host TB는 `re_n` 상승 에지 부근 또는 데이터가 안정화된 시점에서 값을 캡처하여 기댓값과 비교합니다.

### 2.5 Page Program (80h - 10h)
호스트의 데이터를 페이지 레지스터에 적재한 뒤, NAND 셀 어레이에 기록(Program)하는 커맨드입니다.
- Command/Address Cycle: Host가 80h 커맨드와 `C1, C2, R1, R2, R3`의 5 address cycle을 순차적으로 인가합니다. 주소 byte order와 row bit layout은 `0.1 SIMPLE 모델 주소 가정`을 따른다.
- Address to Data Wait (`tADL`): Host TB는 주소 인가 후 최소 `tADL` 시간이 지난 뒤 Data Input Cycle을 시작해야 합니다.
- Data Input Cycle: Host가 기록할 데이터를 `dq[7:0]`에 인가하고 `we_n`을 반복 토글하면, NAND 모델은 데이터를 페이지 버퍼에 순차적으로 적재합니다.
- Program Confirm: Host가 10h 커맨드를 인가하여 Program 동작을 확정합니다.
- Busy Transition (`tWB`): 10h 커맨드의 `we_n` 상승 에지 이후, NAND 모델은 최대 `tWB` 시간 이내에 `rb_n`을 Low(Busy)로 떨어뜨려야 합니다.
- Program Busy (`tPROG`): NAND 모델은 `tPROG` 시간 동안 Busy를 유지하며 실제 셀 프로그래밍을 모사합니다. 완료 후 `rb_n`은 High로 복귀하고, Read Status의 Pass/Fail bit는 모델의 program 결과를 반영해야 합니다.

### 2.6 Block Erase (60h - D0h)
지정된 블록(Block)의 데이터를 모두 소거하는 커맨드입니다.
- Command/Address Cycle: Host가 60h 커맨드와 `R1, R2, R3`의 3 row address cycle을 순차적으로 인가합니다. Erase도 ONFI row address layout을 사용하므로, target block `b`는 보통 `row = b * 64`로 만들고 page-in-block bit는 0으로 둔다.
- Erase Confirm: Host가 D0h 커맨드를 인가하여 Erase 동작을 확정합니다.
- Busy Transition (`tWB`): D0h 커맨드의 `we_n` 상승 에지 이후, NAND 모델은 최대 `tWB` 시간 이내에 `rb_n`을 Low(Busy)로 떨어뜨려야 합니다.
- Erase Busy (`tBERS`): NAND 모델은 `tBERS` 시간 동안 Busy를 유지하며 블록 소거를 모사합니다. 완료 후 `rb_n`은 High로 복귀하고, Read Status의 Pass/Fail bit는 모델의 erase 결과를 반영해야 합니다.

## 3. 토글 타이밍 조건 및 검증 체크포인트
Host TB는 타겟(NAND 모델)로 명령어, 주소, 데이터를 보낼 때 아래 타이밍 제약을 지켜야 합니다. 또한 모델 또는 checker는 해당 조건 위반 시 프로토콜 위반 에러를 발생시키거나, 이후 동작을 Unpredictable 상태로 간주할 수 있습니다.
### 3.1 기본 토글 조건 (Cycle time & Pulse Width)
신호를 한 번 토글할 때 요구되는 최소 주기와 High/Low 유지 시간입니다.
- `tWC` (WE_n cycle time): `Write Enable(we_n)` 신호의 최소 1주기 시간입니다. 이 주기는 `tWP` (WE_n low pulse width)와 `tWH` (WE_n high hold time)의 합 이상이어야 합니다.
- `tRC` (RE_n cycle time): `Read Enable(re_n)` 신호의 최소 1주기 시간입니다. 이 역시 `tRP` (RE_n low pulse width)와 `tREH` (RE_n high hold time) 조건을 만족해야 합니다.
> 참고: 전원이 켜졌을 때 기본으로 진입하는 SDR Timing Mode 0에서는 tWC와 tRC의 최소값이 100ns로 매우 여유롭지만, 가장 빠른 Mode 5에서는 20ns까지 짧아집니다

### 3.2 셋업 및 홀드 타임 (Setup & Hold Time)
`we_n`의 상승 에지(Rising Edge)에서 데이터를 래치(Latch)할 때, 데이터나 제어 신호가 안정적으로 유지되어야 하는 시간입니다.
*   **`tCLS` / `tCLH` (CLE Setup / Hold time)**: CLE 핀이 미리 세팅되어야 하는 시간과 래치 후 유지되어야 하는 시간입니다.
*   **`tALS` / `tALH` (ALE Setup / Hold time)**: ALE 핀의 셋업/홀드 타임입니다.
*   **`tDS` / `tDH` (Data Setup / Hold time)**: `dq[7:0]` 핀에 실린 커맨드, 어드레스, 데이터의 셋업/홀드 타임입니다.
*   **`tCS` / `tCH` (CE_n Setup / Hold time)**: 칩 활성화 신호인 `ce_n`의 셋업/홀드 타임입니다.
*   TB 체크포인트: 위 셋업/홀드 조건이 깨진 사이클에서 래치된 커맨드/주소/데이터는 유효 입력으로 보장하지 않습니다. Checker가 있다면 해당 사이클을 timing violation으로 보고해야 합니다.

### 3.3 주요 상태 전환 대기 시간 (Phase Transition Timings)
연속된 커맨드 시퀀스 중 다른 페이즈(Phase)로 넘어갈 때 Host TB가 만족해야 하는 시간 간격입니다.
*   **`tADL` (Address to Data Loading time)**: 쓰기(Program) 동작 등에서 **주소(Address) 전송을 마치고 데이터(Data Input)를 보내기 전**까지 기다려야 하는 시간입니다. Host TB가 이 시간 이전에 Data Input을 시작하면 모델/checker는 protocol violation으로 처리할 수 있습니다.
*   **`tWHR` (Write to Read time)**: 커맨드, 주소 또는 데이터 입력을 마친 뒤 **데이터 출력(Read) 사이클로 넘어가기 전**에 대기해야 하는 시간입니다(Read ID, Read Status 커맨드 등에 사용됨). Host TB가 이 시간 이전에 `re_n`을 토글하면 출력 데이터는 유효하지 않은 것으로 간주합니다.
*   **`tCCS` (Change Column Setup time)**: 파이프라인에 영향을 주는 **컬럼 주소 변경(Change Read/Write Column) 커맨드 송신 후** 데이터 송수신을 시작하기 전까지 대기해야 하는 시간입니다. 해당 커맨드가 모델 범위에 포함될 경우 checker의 phase transition 조건으로 사용합니다.
*   **`tWB` (WE_n High to Busy)**: 커맨드나 데이터를 보낸 후(`we_n` High), NAND 내부 로직이 동작을 시작하며 **`rb_n` 핀을 Low(Busy)로 떨어뜨리기 전까지 걸리는 최대 시간**입니다. Host TB는 `tWB_max` 이내에 Busy 전이가 발생할 수 있음을 고려하여 Ready/Busy 판정을 수행해야 합니다.
*   **`tWW` (Write Protect transition to command)**: `wp_n` 핀의 값을 변경한 경우, 다음 커맨드를 보내기 전까지 버스가 Idle 상태로 대기해야 하는 시간입니다.
*   **`tPROG` / `tBERS` (Program/Erase Busy time)**: NAND 모델 내부 타이머로 처리되는 Busy 구간입니다. 이 시간 동안 Host가 70h(Read Status) 또는 FFh(Reset) 외의 커맨드를 인가하면 모델은 이를 무시하거나 에러 처리할 수 있습니다.

## 4. Timing Mode 및 SDR 타이밍 조건 요구치
### 4.1 Timing Mode란?
전원이 막 켜졌을 때 호스트 컨트롤러는 연결된 NAND가 얼마나 빠른 속도를 지원하는지 알 수 없습니다. 그래서 모든 디바이스가 공통으로 알아들을 수 있는 **가장 느리고 안전한 'SDR Timing Mode 0' 상태로 통신을 시작**합니다.(`VccQ`가 1.8V 또는 3.3V일 때)

속도를 올리는 과정은 다음과 같습니다.
1. **스펙 확인**: 호스트는 Mode 0 상태에서 `Read Parameter Page` 커맨드를 보내, 이 NAND가 얼마나 빠른 Mode까지 지원하는지 정보를 읽어옵니다.
2. **모드 변경 (합의)**: 더 빠른 속도를 지원한다면, 호스트는 `Set Features` 커맨드를 사용해 "지금부터 Mode 5로 통신하자"고 NAND에게 설정값을 보냅니다.
3. **고속 통신 시작**: 이 명령이 성공적으로 처리된 직후부터 양쪽은 새로 약속된 빡빡한 타이밍 조건(Mode 5)에 맞춰 통신을 시작합니다.

본 NAND MODEL의 경우 `Read Parameter Page` 및 `Set Features` 커맨드를 지원하지 않습니다. 따라서 SDR Mode 0으로만 동작합니다.

### 4.2 주요 타이밍 조건 요구치 (SDR 기준)
SDR 인터페이스에는 **Mode 0 부터 Mode 5 까지** 총 6단계의 타이밍 모드가 있습니다. 전원 인가 시의 기본 모드인 **Mode 0**과 가장 빠른 **Mode 5**를 비교해 보면 스펙의 차이를 명확히 알 수 있습니다.

*   **`tWC` (WE_n cycle time - 쓰기 주기)**: 한 번의 쓰기 펄스에 필요한 전체 시간
    *   Mode 0: 최소 **100ns**
    *   Mode 5: 최소 **20ns**
*   **`tRC` (RE_n cycle time - 읽기 주기)**: 한 번의 읽기 펄스에 필요한 전체 시간
    *   Mode 0: 최소 **100ns**
    *   Mode 5: 최소 **20ns** (EDO 출력 지원 시)
*   **`tADL` (Address to Data Loading - 상태 전환 대기)**: 주소 전송 후 데이터 전송 전 대기 시간
    *   모든 모드 공통: 최소 **400ns**
*   **`tWHR` (Write to Read time - 상태 전환 대기)**: 커맨드 전송 후 데이터 읽기로 전환 전 대기 시간
    *   Mode 0: 최소 **120ns**
    *   Mode 5: 최소 **80ns**
*   **`tWB` (WE_n High to Busy)**: 커맨드 전송 후 NAND가 Busy(`rb_n`=0) 상태로 진입하기 전까지 걸리는 **최대 시간**. Host TB는 이 시간 안에 Busy 전이가 발생할 수 있음을 감안해야 함
    *   Mode 0: 최대 **200ns**
    *   Mode 5: 최대 **100ns**


## 5. Host Testbench(TB) 구현 및 모델 상태 확인(Checking) 시 참고 사항
- Host TB는 ONFI 디바이스에 접근할 때 `we_n` 및 `re_n` 신호를 SDR Mode 0 타이밍 조건에 맞게 생성해야 합니다.
- 본 모델은 Busy 구간 (`rb_n`=0) 에서의 `CE_n` Dont'care(High 전환)을 지원하지 않는다.
- 모든 커맨드 실행 후 Busy 구간(`rb_n` == 0)에서는 70h Read Status 또는 FFh Reset 등 극히 일부 커맨드만 허용됩니다. 그 외 커맨드는 모델 구현 정책에 따라 무시하거나 protocol violation으로 보고합니다.
- Data output cycle로 전환 시, Host TB는 마지막 `we_n`상승 에지 이후 시작되는 `tWHR` 대기구간 내에 `dq[7:0]` 구동을 끊고 (High-Z) 입력모드로 전환해야 버스 충돌을 방지할 수 있습니다.
- Data Input 시에는 Host TB가 `dq[7:0]`을 구동하고, NAND 모델은 `we_n` 상승 에지에서 데이터를 래치해야 합니다. 이때 `cle`=0, `ale`=0 상태가 유지되어야 합니다.
- 모델/checker는 커맨드 시퀀스, 주소 사이클 수, Busy/Ready 전이, 데이터 출력 순서, Pass/Fail status bit를 주요 비교 항목으로 삼습니다.
- 현재 모델은 SDR Mode 0만 고려합니다. RTL/TB의 공유 geometry와 timing guard 값은 `nand_model/nand_parameters.vh`를 기준으로 하며, 이후 Mode 확장 시에도 Host TB와 checker가 동일한 타이밍 테이블을 참조하도록 유지합니다.

---

## Version History
| Version | 변경사항 |
| --- | --- |
| v0.3 | 공유 파라미터 헤더 `nand_model/nand_parameters.vh`가 geometry/timing guard 기준임을 명시. |
| v0.2 | Read Parameter Page 생략에 따른 SIMPLE 고정 geometry와 column/row address byte layout을 명시. |
| v0.1 | SIMPLE NAND ONFI SDR 지원 command의 host-visible expected behavior와 timing checkpoint를 최초 정리. |
