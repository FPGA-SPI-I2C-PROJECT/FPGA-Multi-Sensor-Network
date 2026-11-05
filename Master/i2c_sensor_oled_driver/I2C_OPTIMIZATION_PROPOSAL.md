# 보드 간 I2C 코드 최적화 제안 — 아직 적용하지 않음

대상 파일:

- `i2c_sensor_oled_driver.srcs/sources_1/new/i2c_sensor_read_master.v`
- `slave_basys3/rtl/i2c_sensor_slave.v`

이 문서의 코드는 구조를 검토하기 위한 제안이다. 기존 Verilog 파일은 수정하지 않았으며, 아래 조각은 완성된 대체 모듈이 아니다. 시뮬레이션과 합성도 아직 수행하지 않았다.

## 1. NXP 규격을 인용한 이유

NXP는 Basys3 제조사가 아니다. Basys3는 Digilent의 FPGA 보드이며, NXP의 UM10204는 I2C 통신 규격 문서다. 인용 목적은 Basys3의 하드웨어 조건을 설명하려는 것이 아니라 I2C 신호의 타이밍 조건을 확인하려는 것이다.

FPGA끼리 통신해도 SDA는 일반 데이터 전송 중 SCL High 구간에 안정되어 있어야 한다. 두 보드의 시스템 클록도 서로 독립적이므로 입력 동기화는 유지한다. 다만 각 시간 구간을 모두 별도 FSM 상태로 표현할 필요는 없다.

규격: https://www.nxp.com/docs/en/user-guide/UM10204.pdf

## 2. Master: 주요 상태 33개를 10개로 통합

현재 상태 선언:

```verilog
localparam IDLE=0, BUS_FREE=1, START_HOLD=2, START_LOW=3,
    TX_SET=4, TX_RISE=5, TX_HIGH=6, TX_FALL=7,
    ACK_SET=8, ACK_RISE=9, ACK_HIGH=10, ACK_FALL=11, NEXT_TX=12,
    RESTART_LOW=13, RESTART_RISE=14, RESTART_HIGH=15,
    RX_SET=16, RX_RISE=17, RX_HIGH=18, RX_FALL=19,
    MASTER_ACK_SET=20, MASTER_ACK_RISE=21, MASTER_ACK_HIGH=22,
    MASTER_ACK_FALL=23, STOP_SET=24, STOP_RISE=25, STOP_HIGH=26,
    STOP_RELEASE=27, STOP_FREE=28, REC_LOW=29, REC_RISE=30,
    REC_HIGH=31, REC_FALL=32;
reg [5:0] state;
```

제안하는 상태 선언:

```verilog
localparam [3:0] IDLE=0, BUS_FREE=1, START=2,
    TX_BYTE=3, RX_ACK=4, RESTART=5,
    RX_BYTE=6, TX_ACK=7, STOP=8, RECOVER=9;
reg [3:0] state;
reg [2:0] phase;  // 각 동작 내부의 타이밍 단계
```

| 현재 | 변경안 |
|---|---|
| `START_HOLD`, `START_LOW` | `START` 내부에서 순서와 시간을 처리 |
| `TX_SET`, `TX_RISE`, `TX_HIGH`, `TX_FALL` | `TX_BYTE`와 비트 카운터로 처리 |
| `ACK_SET`, `ACK_RISE`, `ACK_HIGH`, `ACK_FALL`, `NEXT_TX` | `RX_ACK` 내부에서 ACK를 받고 다음 동작 결정 |
| `RESTART_LOW`, `RESTART_RISE`, `RESTART_HIGH` | `RESTART` 내부에서 처리 |
| `RX_SET`, `RX_RISE`, `RX_HIGH`, `RX_FALL` | `RX_BYTE`와 비트 카운터로 처리 |
| `MASTER_ACK_SET/RISE/HIGH/FALL` | `TX_ACK` 내부에서 첫 바이트 ACK, 마지막 바이트 NACK 처리 |
| `STOP_SET/RISE/HIGH/RELEASE/FREE` | `STOP` 내부에서 STOP 생성과 버스 해제 대기 |
| `REC_LOW`, `REC_RISE`, `REC_HIGH`, `REC_FALL` | `RECOVER`와 9클록 카운터로 처리 |

송신·수신·ACK에 반복되는 SCL 제어는 공통 타이밍 처리로 모은다. SCL Low 구간에서 SDA를 설정하고 설정 시간을 확보한 후 SCL을 해제한다. 실제 SCL High를 확인한 다음 High 유지 시간을 센다.

`state`를 `phase`로 옮기는 것만으로 저장 비트가 줄어들지는 않는다. 위 선언의 `state + phase`는 7비트로, 기존 `state` 6비트보다 크다. 목적은 중복 제어를 정리하는 것이며, 실제 자원 감소 여부는 합성으로 확인한다.

## 3. Slave: 주요 상태 12개를 8개로 통합

현재 상태 선언:

```verilog
localparam IDLE=0, RX_ADDRESS=1, RX_REGISTER=2, ACK_WRITE=3,
    ACK_REGISTER=4, ACK_READ=5, TX=6, TX_RELEASE=7,
    MASTER_ACK=8, MASTER_ACK_FALL=9, WAIT_STOP=10, IGNORE=11;
reg [3:0] state;
```

제안하는 상태 선언:

```verilog
localparam [2:0] IDLE=0, RX_ADDRESS=1, RX_REGISTER=2,
    SLAVE_ACK=3, TX=4, MASTER_ACK=5, WAIT_STOP=6, IGNORE=7;
reg [2:0] state;
reg [2:0] after_ack;  // Slave ACK 후 이동할 상태
// 기존 ack_phase는 유지하고 MASTER_ACK에서도 재사용
```

| 현재 | 변경안 |
|---|---|
| `ACK_WRITE` | `SLAVE_ACK`, `after_ack = RX_REGISTER` |
| `ACK_REGISTER` | `SLAVE_ACK`, `after_ack = WAIT_STOP` |
| `ACK_READ` | `SLAVE_ACK`, `after_ack = TX` |
| `TX_RELEASE`, `MASTER_ACK`, `MASTER_ACK_FALL` | `MASTER_ACK` 내부 단계로 통합 |

통합한 `MASTER_ACK`의 단계는 다음과 같다.

1. 8번째 데이터 비트 이후 SCL 하강 에지에서 SDA 해제.
2. 9번째 SCL 상승 에지에서 Master ACK/NACK 저장.
3. 9번째 SCL 하강 에지에서 다음 바이트 전송 또는 대기 상태로 이동.

Slave는 현재도 SCL 에지 기반으로 동작한다. ACK 상태 세 개는 이미 같은 case 본문을 공유하므로, 통합은 주로 가독성 개선이다. `after_ack` 등이 추가되므로 상태 개수 감소가 곧 FF 감소를 의미하지 않는다.

## 4. 카운터 폭 조정

필요한 카운터 폭을 파라미터에서 계산한다. `$clog2` 결과가 0일 때도 최소 1비트를 보장한다.

```verilog
// Master에서 기존 reg [31:0] divider, watchdog; 대체 제안
localparam integer DIV_W = (Q > 1) ? $clog2(Q) : 1;
localparam integer WD_W = (LIMIT > 1) ? $clog2(LIMIT) : 1;
reg [DIV_W-1:0] divider;
reg [WD_W-1:0] watchdog;

// Slave에서 기존 reg [31:0] idle_count; 대체 제안
localparam integer IDLE_W = (LIMIT > 1) ? $clog2(LIMIT) : 1;
reg [IDLE_W-1:0] idle_count;
```

위 두 조각은 서로 다른 모듈에 들어간다. Slave 카운터는 LIMIT-1에서 포화시키거나 타임아웃 처리와 함께 초기화해 축소 후 오버플로를 방지한다. 파라미터는 양의 유효 범위를 전제로 검사한다.

기본 파라미터에서 Master divider는 8비트, watchdog은 25비트, Slave idle_count는 22비트다. 타이밍 카운터 설계가 바뀌면 해당 카운터의 최대값을 기준으로 폭을 다시 계산한다.

## 5. 타이밍과 기존 기능

현재 기본 100kHz 설정의 Q는 2.5us다. START 발생 후 START_HOLD에서 한 Q 뒤 SCL을 Low로 내리므로, 코드상 START 유지 시간은 약 2.5us다. I2C Standard-mode의 최소 START 유지 시간 4us를 만족하도록 이 계산도 보완한다. SCL Low/High, repeated START, STOP, 버스 해제 시간은 각각 필요한 시간을 보장한다.

주소 0x42, 명령 01/02/03, 16비트 응답과 응답 스냅샷, ACK/NACK, 오픈드레인 출력, 입력 동기화, 타임아웃, SCL High 확인, 9클록 버스 복구는 유지한다.

적용 후 기존 통합·오류 시뮬레이션과 타이밍 검사를 수행하고 합성 자원을 비교한다. 테스트벤치 두 곳의 `slave.state == 6` / `slave_i2c.state == 6` 조건은 새 상태에 맞추거나 숫자 의존을 제거해야 한다.
