# Basys3 센서 네트워크: SPI / I2C 선택

Master는 선택한 센서값을 Slave에서 읽어 SSD1306 OLED에 표시한다. Slave는 기존 센서 드라이버·reg_bank·UART 원본을 그대로 사용하고, 추가한 SPI/I2C 모듈이 같은 reg_bank를 읽는다. 기존 GitHub `top_slave.v`는 변경하지 않았으며, 실제 사용할 Slave Top은 **`top_slave_network`**다.

## 프로젝트와 Top

| 보드 | 프로젝트 | 합성 Top |
|---|---|---|
| Master | `i2c_sensor_oled_driver.xpr` | `sensor_network_master` |
| Slave | `slave_basys3/project/slave_spi_basys3.xpr` | `top_slave_network` |

Slave 프로젝트 파일명은 이전 SPI 작업과의 경로 호환을 위해 유지했다. 지금은 SPI와 I2C가 모두 포함된다. 이전 `top_slave_spi`는 SPI 전용 참고 소스로 남겨 두었고, 현재 프로젝트의 Top으로 사용하지 않는다. 각 보드용 비트스트림을 따로 생성하고 해당 보드에 다운로드한다.

## Master 조작

| sw[1] | sw[0] | 선택 |
|---|---|---|
| 0 | 1 | SPI |
| 1 | 0 | I2C |
| 0 | 0 | 선택 오류 |
| 1 | 1 | 선택 오류 |

`sw[2]`=온도, `sw[3]`=습도, `sw[4]`=거리다. 하나 이상 선택하고 `btnC`를 누르면 한 번 읽는다. 버튼은 약 20ms 디바운스한다. `led[11]`이 켜진 동안 새 요청은 무시한다.

방식과 센서 마스크는 요청 시작 시 고정한다. 도중에 스위치를 바꾸어도 진행 중 요청은 유지되고, 다음 버튼 요청부터 반영된다. 선택하지 않은 통신부는 신호를 전송하지 않는다. Slave는 두 인터페이스를 대기하므로 **Slave 스위치를 따로 맞추지 않는다**. 두 Master가 동시에 Slave를 제어하는 구성은 이 프로젝트의 사용 조건에 포함하지 않는다.

`sw[15]=1`은 Master 상태·수신 레지스터·유효 비트를 지우고 진행 중 전송을 중단한다. Slave의 리셋에 연결하지 않는다. Slave 자체 `sw[15]`는 Slave만 초기화한다. OLED는 Master 리셋 해제 후 빈 값 프레임을 전송한다. 리셋을 유지하는 동안에는 OLED I2C도 정지한다.

## 연결

| 신호 | Master | Slave / 장치 |
|---|---|---|
| 보드 I2C SDA | JB1 / A14 | Slave JB1 / A14 |
| 보드 I2C SCL | JB2 / A16 | Slave JB2 / A16 |
| SPI MISO | JB7 / A15 | Slave JB7 / A15 |
| SPI MOSI | JB8 / A17 | Slave JB8 / A17 |
| SPI SCLK | JB9 / C15 | Slave JB9 / C15 |
| SPI CS, Low 활성 | JB10 / C16 | Slave JB10 / C16 |
| GND | GND | Slave GND |
| OLED SDA | JA7 / H1 | OLED SDA |
| OLED SCL | JA8 / K2 | OLED SCL |

**보드 간 SDA와 SCL에는 각각 3.3V로 연결한 외부 풀업 저항을 사용한다.** 예를 들어 짧은 배선에서 4.7kΩ으로 시작할 수 있다. 이미 연결된 풀업이 있으면 중복 연결 여부를 확인한다. OLED 버스와 보드 간 버스는 별개다. FPGA 신호는 3.3V 기준이다.

Slave 센서 배선은 원본과 같다. DHT11 데이터=JA2/L2, 초음파 Trig=JA3/J2, Echo=JA4/G2. 센서 모듈의 Echo 출력 전압에 맞는 레벨 변환을 사용한다. 센서·UART 원본의 측정 동작은 이번 통신 추가 작업에서 수정하지 않았다.

## 공통 레지스터와 응답

| 선택값 | 데이터 | 응답 16비트 |
|---|---|---|
| `0x01` | 온도 | 상위 8비트 0, 하위 8비트 온도 |
| `0x02` | 습도 | 상위 8비트 0, 하위 8비트 습도 |
| `0x03` | 거리 | 상위 7비트 0, 하위 9비트 거리 |

Slave는 명령/읽기 주소를 처리할 때 선택한 최신 reg_bank 값을 복사해 응답한다. 두 바이트를 보내는 도중 측정값이 갱신되어도 같은 복사본을 사용한다. 여러 센서는 별도의 트랜잭션으로 읽으므로 세 값이 동일한 측정 시점이라는 뜻은 아니다. 첫 측정 전에는 reg_bank 초기값 0을 읽는다.

SPI는 Mode 0, MSB 우선, 명령 8클록 + 응답용 더미 16클록이다. 기본 SCLK는 100kHz다. Slave 구현의 지원 범위는 SCLK 1MHz 이하, CS 설정/High 유지 각각 100ns 이상이다. SPI에는 ACK/CRC가 없어 Master가 Slave 미연결과 유효한 0을 구분하지 못한다.

## I2C 프로토콜

7비트 Slave 주소는 **`0x42`**다. 선로상 주소 바이트는 쓰기 `0x84`, 읽기 `0x85`다. 기본 속도는 100kHz이고 Slave는 100MHz 클록에서 400kHz 이하로 사용한다.

1. START → 주소+W → Slave ACK.
2. 선택값 1바이트 → Slave ACK.
3. repeated START → 주소+R → Slave ACK.
4. 응답 상위 바이트 → Master ACK.
5. 응답 하위 바이트 → Master NACK → STOP.

Slave는 선택값 쓰기와 읽기 사이에 STOP이 있는 방식도 수용한다. 다른 주소와 잘못된 선택값에는 ACK하지 않는다. 이 버전은 응답을 2바이트로 고정한다. Master는 매 센서 요청마다 선택값을 다시 보낸다.

Master는 NACK/타임아웃을 검출하고, 클록 스트레칭 동안 SCL이 실제 High가 될 때까지 기다린다. Slave 자체는 클록 스트레칭을 하지 않는다. Slave는 25ms 동안 버스 에지가 없으면 SDA를 해제하고 대기 상태로 돌아간다.

Master 리셋으로 Slave가 읽기 중 SDA를 잡은 상태라면 다음 I2C 요청에서 9클록과 STOP으로 버스 복구를 시도한다. SCL 자체가 Low로 고정되거나 SDA가 계속 고정되면 타임아웃으로 종료한다. 이 복구는 단일 Master 구성용이다.

## Master 저장과 OLED

`acquisition.temperature[7:0]`, `humidity[7:0]`, `distance[8:0]`에 수신값을 저장한다. `valid_mask[2:0]`은 `{거리,습도,온도}`다. 새 요청은 이전 값과 유효 비트를 지우고, 선택한 센서를 모두 읽은 뒤 한 번에 공개한다. I2C 오류 시 일부만 성공한 값도 공개하지 않는다.

```text
Temperature:  25
Humidity:
Distance:    301
```

위 예시는 온도와 거리만 요청한 경우다. 미요청 항목은 숫자 영역 전체를 공백으로 덮어쓰며, 값 0은 유효 비트가 있을 때 `0`으로 표시한다. OLED는 프레임 경계에서 값을 복사해 화면 중간에 서로 다른 요청이 섞이지 않게 한다. 전송 중 새 값은 후속 프레임으로 반영한다. 현재 확인된 실제 패널은 128x64이므로 Top의 `OLED_HEIGHT=64`를 유지한다. 128x32 패널에서는 `OLED_HEIGHT=32`로 설정한다. 주소는 `0x3C`다.

OLED는 페이지 주소 모드(`0x20,0x02`)로 초기화한다. 각 페이지마다 `B0+page,00,10`으로 페이지와 시작 열을 지정한 뒤 제어 바이트 `0x40`과 128바이트의 픽셀을 보낸다. 128x64는 8페이지, 128x32는 4페이지를 전부 갱신한다. 기존 `i2c_write_master`는 변경하지 않았다.

센서 응답의 상위 패딩 비트가 0이 아니면 `error_code=6`, Master `LED[2]=1`로 처리하고 해당 요청의 값은 확정하지 않는다. 따라서 `16'hFFFF`가 온도 255·습도 255·거리 511로 표시되지 않는다. 정상적으로 0을 붙인 `00FF`/`01FF`는 허용한다. 이 검사는 CRC나 응답 존재 검사를 대신하지 않는다.

OLED용 기존 `i2c_master_write.v`의 `i2c_write_master`는 **수정하지 않았다**. 이 모듈은 쓰기 전용이므로 보드 간 센서 읽기에는 새 `i2c_sensor_read_master.v`를 사용한다.

## LED

| 보드 | LED | 의미 |
|---|---|---|
| Master | 15 / 14 / 13 / 12 | OLED 준비 / 오류 / NACK / 타임아웃 |
| Master | 11 / 10 | 요청 진행 / SPI 비활성화 |
| Master | 9 / 8 / 7 / 3 | 보드 I2C NACK / 모드 오류 / 빈 요청 / 보드 I2C 타임아웃 |
| Master | 2 | 응답의 상위 패딩 비트 오류 (`FFFF` 등) |
| Master | 6 / 5 / 4 | 거리 / 습도 / 온도 유효 |
| Slave | 15 / 14 / 13 / 12 | DHT 오류 / SPI 명령 오류 / SPI 선택 중 / SPI 완료 이력 |
| Slave | 11 / 10 / 9 | I2C 명령 오류 / I2C 선택 중 / I2C 완료 이력 |
| Slave | 8..0 | 거리 레지스터 |

## 설정 및 검증

Master Tcl Console에서는 `source scripts/enable_paired_spi.tcl`을 실행한다. 현재 저장된 프로젝트에도 두 방식용 소스와 SPI 활성 generic을 등록했다. Slave 프로젝트 재생성은 별도 Vivado에서 `vivado -mode batch -source scripts/create_slave_project.tcl`이다.

`scripts/run_tests.ps1`은 실제 SPI/I2C Slave RTL을 연결한 통합 시험과 I2C 오류 시험을 실행한다. 후자는 미연결 NACK, 잘못된 선택값, 타임아웃, 일시적인 SCL Low, 응답 중 값 변경을 확인하도록 작성했다. 통합 시험은 양쪽 프로토콜의 센서 마스크, OLED 숫자 지움, 모드 고정, Master 단독 리셋과 I2C 복구를 확인한다.

합성 스크립트는 `scripts/synth_sensor_master.tcl`, `scripts/synth_slave_spi.tcl`이다. 구문 분석·합성·기능 시뮬레이션·실물 검증의 결과는 `VALIDATION_SENSOR_MASTER.md`에 구분해 기록한다.

Master OLED 픽셀 생성은 100MHz 타이밍을 만족하도록 4단계 파이프라인으로 구현했다. 기존 I2C 쓰기 코어의 샘플링 시점에 맞추기 위해 `CLK_HZ/(4*I2C_HZ)`는 5 이상이어야 한다. 기본 100kHz에서는 250이므로 충족한다. 배치·배선 및 비트스트림까지 재검증하려면 `scripts/implement_timing_fix.tcl`을 사용한다.

## OLED 분리 진단

`SPI_PROTOCOL_READY`는 센서 요청 경로만 제어한다. OLED가 전원 직후부터 깨지고 아직 요청 버튼도 누르지 않았다면, 이 설정만으로 원인이 확정되지 않는다. LED[15]는 I2C ACK를 포함한 패킷 완료 상태이며 화면 내용을 검사하는 신호가 아니다.

`OLED_SELF_TEST=1`은 SPI를 활성화한 상태에서도 OLED에 온도 25, 습도 60, 거리 123을 고정 표시한다. 진단 화면의 숫자는 실제 센서값이 아니다. 일반 사용에는 기본값 `OLED_SELF_TEST=0`을 유지한다. 진단 빌드는 PowerShell에서 `$env:OLED_SELF_TEST_BUILD='1'`을 설정한 뒤 `scripts/implement_timing_fix.tcl`을 실행한다. 일반 빌드는 이 환경 변수를 해제하고 실행한다. 출력 폴더는 각각 `.verification/oled_self_test`, `.verification/normal`이다.

고정값 화면도 깨지면 수신 센서값을 원인으로 단정할 수 없으며 실제 OLED 컨트롤러 종류·초기화·I2C 신호를 확인해야 한다. 고정값 화면은 정상이고 일반 화면만 깨지면 요청·수신·갱신 경로를 추가 조사한다. 테스트벤치는 32/64 높이와 페이지별 전송 및 `FFFF` 거부를 확인하도록 구성했다. 실제 실행 결과는 검증 문서에 기록한다.
