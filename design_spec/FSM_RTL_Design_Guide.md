# FSM RTL Design Guide
Version: v0.3
Status: active

## 1. 목적

본 문서는 합성 가능한 RTL FSM을 설계하고 코딩할 때 따를 공통 기준을 정의한다.
목표는 waveform에서 추적 가능한 state, 명확한 transition, 안정적인 output,
그리고 synthesis/simulation mismatch 위험이 낮은 RTL을 만드는 것이다.

참고 기준:

- Clifford E. Cummings, "State Machine Coding Styles for Synthesis", SNUG 1998
- Cummings/Heath, "Finite State Machine Design & Synthesis using SystemVerilog", SNUG 2019
- lowRISC Verilog Coding Style Guide
- Cummings, "FSM Designs With Synthesis-Optimized, Glitch-Free Outputs", SNUG 2000

## 2. FSM 기본 타입

FSM 타입은 설계 문서에 명시한다.

| 타입 | 정의 | 특징 |
| --- | --- | --- |
| Moore | output이 현재 state에만 의존 | output이 안정적이고 debug가 쉽다. 반응이 1 clock 늦을 수 있다. |
| Mealy | output이 현재 state와 input에 의존 | 입력에 빠르게 반응하지만 glitch/timing path 관리가 어렵다. |
| Registered-output hybrid | next decision은 input을 보지만 output은 register | 실무 RTL에서 control/data handshake에 자주 쓰는 절충안이다. |

예를 들어 `ST_IDLE`에서 `start_i`를 보고 다음 상태를 고르는 것은 Mealy 성격이다.
하지만 `valid_o`와 payload를 clock edge에서 register한 뒤 외부로 내보내면
registered-output hybrid다.

## 3. `q`와 `d`의 의미

`q`는 현재 register 값이고, `d`는 다음 clock에 register로 들어갈 값이다.

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state_q <= ST_IDLE;
    else        state_q <= state_d;
end
```

```text
state_q: 지금 cycle에서 FSM이 실제로 갖고 있는 상태
state_d: combinational logic이 계산한 다음 상태 후보
posedge clk: state_q <= state_d
```

context register도 같은 규칙을 쓴다.
예: `count_q/count_d`, `payload_q/payload_d`, `valid_q/valid_d`.

## 4. 2-process 구조

2-process FSM은 register update block과 next-value calculation block으로 나눈다.

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= ST_IDLE;
        valid_q <= 1'b0;
    end else begin
        state_q <= state_d;
        valid_q <= valid_d;
    end
end

always @* begin
    state_d = state_q;
    valid_d = valid_q;
    case (state_q)
        ST_IDLE: if (start_i) state_d = ST_BUSY;
        ST_BUSY: if (done_i) begin
            state_d = ST_IDLE;
            valid_d = 1'b1;
        end
    endcase
end
```

장점은 "현재 값"과 "다음 값"이 분리되어 state transition priority가 잘 보인다는 점이다.

## 5. 3-process 구조

3-process FSM은 아래처럼 나눈다.

```text
1. state/context register update
2. next-state calculation
3. output calculation
```

output이 현재 state만 보고 만들어지는 Moore FSM이거나, output decode가 복잡할 때
3-process가 읽기 쉽다. 단, output이 combinational이면 glitch와 timing path를
검토해야 한다.

## 6. 1-process Registered-Output Style

1-process style은 한 clocked block 안에서 state와 output을 모두 갱신한다.

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= ST_IDLE;
        valid <= 1'b0;
    end else begin
        valid <= 1'b0;
        case (state)
            ST_IDLE: if (start_i) state <= ST_BUSY;
            ST_BUSY: if (done_i) begin
                valid <= 1'b1;
                state <= ST_IDLE;
            end
        endcase
    end
end
```

작은 FSM에는 가능하지만, 큰 FSM에서는 여러 조건이 같은 register를 덮어쓰기 쉽다.
복잡한 command decoder, multi-field payload, error priority가 있으면 2-process를
기본으로 한다.

## 7. Naming Rule

- 현재 state register는 `state_q`, 다음 state는 `state_d`를 사용한다.
- context register도 `*_q`, `*_d` 쌍을 사용한다.
- 1-cycle pulse는 `_pulse` 또는 `_event`를 붙인다.
- valid/ready accept 조건은 `foo_accept = foo_valid && foo_ready`로 둔다.
- 외부 output port가 register이면 internal `foo_q`를 `assign foo_o = foo_q;`로 연결할 수 있다.

## 8. Sequential Block Rule

Sequential block은 reset과 `*_q <= *_d` 업데이트 중심으로 유지한다.
큰 transition decision은 combinational next block으로 뺀다.

금지:

- 한 register를 여러 독립 branch에서 반복 assignment해 priority가 숨는 구조
- clocked block 내부의 긴 절차형 command parser
- task/function이 state/output register를 직접 갱신하는 숨은 side effect
- simulation 편의를 위한 `#delay`, force/release, file I/O

## 9. Combinational Block Rule

Combinational block은 맨 앞에서 모든 `*_d`에 default 값을 넣는다.
기본값은 보통 hold다.

```verilog
state_d = state_q;
valid_d = valid_q;
payload_d = payload_q;
```

그 다음 state별 case에서 변경점만 override한다.
모든 branch는 값을 fully-defined하게 만든다.
invalid condition은 `X` drive가 아니라 assertion, error flag, error event로 표현한다.

## 10. Mealy 사용 제한

Mealy decision은 input event를 보고 next state나 next registered output을 고를 때만
사용한다. 외부 output을 input combinational path로 바로 내보내지 않는다.

허용:

- `start_i`를 보고 `state_d = ST_BUSY` 선택
- `cmd_i`를 보고 다음 payload register 값 선택
- `ready_i`를 보고 valid hold 여부 결정

주의:

- asynchronous 또는 CDC-adjacent input이 output으로 바로 이어지면 안 된다.
- `valid_o = state_q == ST_IDLE && start_i` 같은 output은 glitch/timing 검토가 필요하다.
- CDC source payload는 ready/ack 전까지 stable해야 한다.

## 11. State Encoding

Binary localparam encoding은 state 이름을 작은 binary 숫자로 매핑하는 방식이다.

```verilog
localparam [1:0] ST_IDLE = 2'd0;
localparam [1:0] ST_BUSY = 2'd1;
localparam [1:0] ST_DONE = 2'd2;
```

state 수가 적고 timing이 여유 있으면 binary encoding을 기본으로 한다.

One-hot encoding은 state마다 bit 하나를 쓰는 방식이다.

```verilog
localparam [2:0] ST_IDLE = 3'b001;
localparam [2:0] ST_BUSY = 3'b010;
localparam [2:0] ST_DONE = 3'b100;
```

One-hot은 state decode가 단순해 FPGA에서 빠를 수 있다.
대신 flip-flop을 더 많이 쓰고 invalid state가 많아진다.
state 수가 많거나 timing 이점이 명확할 때만 문서화하고 사용한다.

## 12. Error, Recovery, Handshake

protocol error는 silent drop하지 않는다.
error event를 만들거나 sticky status로 남기는 정책을 설계 문서에 적는다.
recover state가 필요하면 실제 RTL에도 `ST_ERROR`를 구현한다.
문서에만 있는 state를 남기지 않는다.

`valid && ready`를 accept로 정의한다.
valid가 올라간 뒤 ready가 0이면 payload는 hold한다.
accepted event 이후 새 event를 받을 수 있는 조건을 state diagram이나 표에 적는다.

## 13. Review Checklist

- Moore/Mealy/Hybrid 타입, state diagram, RTL state 이름이 일치하는가?
- `q/d` 또는 명확한 1-process registered-output 구조가 보이는가?
- sequential block에 큰 decision tree가 숨어 있지 않은가?
- output valid/payload가 ready 전까지 stable한가?
- error priority가 명시되어 있고 테스트로 확인되는가?
- 문서에만 있고 RTL에는 없는 state가 없는가?
- CDC payload가 single-bit sync 없이 multi-bit로 crossing하지 않는가?

## Version History

| Version | Description |
| --- | --- |
| v0.3 | 구현 완료 상태에 맞춰 문서 status를 active로 갱신. |
| v0.2 | 범용 FSM 가이드로 재정리하고 q/d, 1/2/3-process, Mealy 제한, binary/one-hot encoding 예시를 보강. |
| v0.1 | FSM 분류, coding structure, registered-output hybrid 기본 원칙 최초 정리. |
