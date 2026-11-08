# 🚀 FPGA Multi-Sensor Distributed Network (I2C / SPI / UART / OLED)

> **Digilent Basys 3 FPGA 보드 2대를 활용한 하드웨어 기반 센서 데이터 수집, 다중 프로토콜 인터페이스 및 SSD1306 OLED 시각화 시스템**

---

## 📌 1. 프로젝트 개요 (Overview)
본 프로젝트는 FPGA(Artix-7) 환경에서 하드웨어 언어를 사용하여 통신 프로토콜(**UART, SPI, I2C**) 드라이버를 직접 RTL 레벨로 설계·검증하고, **Master-Slave 분산 처리 시스템**을 구축한 프로젝트입니다.

Slave 보드는 온·습도 센서(DHT11) 및 초음파 거리 센서(HC-SR04)의 정밀 데이터시트 타이밍을 제어하여 데이터를 상시 갱신하고, Master 보드는 사용자 스위치/UART 명령에 따라 동적으로 통신 방식을 선택하여 센서 데이터를 획득한 뒤 SSD1306 OLED 디스플레이에 실시간으로 시각화합니다.

- **개발 환경:** Vivado ML Standard (2021.1)
- **사용 언어:** Verilog HDL
- **대상 하드웨어:**
  * **FPGA Board:** Basys 3 (Xilinx Artix-7 XC7A35T)  (Master / Slave)
  * **Display:** SSD1306 I2C OLED (128x64) 
  * **Sensors:** DHT11 (단선 양방향 온·습도 센서), HC-SR04 (초음파 거리 측정 센서)
- **개발 인원:** 2인 (고지현, 김형진)

---

## 🏛️ 2. 시스템 아키텍처 및 역할 분담 (System Architecture)

```text
[ Slave Board (Basys 3) ]                             [ Master Board (Basys 3) ]
┌────────────────────────┐                             ┌────────────────────────┐
│ • DHT11 Trigger & Read │                             │ • Protocol Mux Router  │
│ • HC-SR04 Trigger/Echo │                             │   - SPI Master Driver  │
│ • Sensor Register Bank │                             │   - I2C Master Driver  │
│ • I2C Sensor Slave     │ ─── I2C Bus (SCL, SDA) ───► │ • UART Command Control │
│ • SPI Sensor Slave     │ ─── SPI Bus (CS, SCLK, ───► │ • SSD1306 OLED Driver  │
│ • Standalone UART Mon  │              MOSI, MISO)    │   (I2C Display Engine) │
└────────────────────────┘                             └────────────────────────┘
```

### 🔹 Master 보드 (데이터 수신 & 시각화)
- **동적 라우팅 제어 (Dynamic Protocol Mux):**
  * `sw[1:0] == 2'b01`: SPI 통신 모드 활성화
  * `sw[1:0] == 2'b10`: I2C 통신 모드 활성화
  * `sw[2] == 1'b1`: 온도 데이터 요청 (UART 문자 `T` 또는 `t` 대응)
  * `sw[3] == 1'b1`: 습도 데이터 요청 (UART 문자 `H` 또는 `h` 대응)
  * `sw[4] == 1'b1`: 거리 데이터 요청 (UART 문자 `D` 또는 `d` 대응)
- **OLED 시각화 엔진:** SSD1306 그래픽 RAM 초기화 시퀀스 및 폰트 렌더링 드라이버를 직접 RTL(I2C Master)로 구현하여 실시간 측정치 텍스트 디스플레이
- **사용자 입력 제어:** 보드 푸시버튼(`btnC`) 및 UART RX 명령 기반 측정 트리거

### 🔹 Slave 보드 (데이터 수집 & 단독 검증)
- **주기적 센서 트리거링 (`sensor_trigger_generator`):**
  * DHT11: 1.5초 주기 트리거 신호 생성
  * HC-SR04: 500ms 주기 트리거 신호 생성
- **센서 레지스터 뱅크 (`sensor_reg_bank`):** 측정 완료 시 전달받은 온·습도 정수/소수부, 초음파 거리(9비트) 데이터를 래치하여 버스 슬레이브 모듈에 안정적으로 제공
- **통신 슬레이브 엔진:** Master의 요청(I2C 클럭 / SPI CS)에 따라 즉각 데이터를 직렬화하여 반환하는 `i2c_sensor_slave`, `spi_sensor_slave` 구동
- **단독 동작 검증 모니터링 (`uart_controller`, `bin2ascii`):** Master 보드가 연결되지 않은 단독 환경에서도 UART 터미널을 통해 센서 측정값을 직접 모니터링할 수 있는 독립 검증 인터페이스 탑재

---

## 📊 3. 데이터시트 기반 센서 RTL 설계 (Sensor Drivers)

```text
                            [ sensor_trigger_generator ]
                                  ├── dht_start_tick (1.5s)
                                  └── ultra_start_tick (500ms)
                                       │            │
              ┌────────────────────────┘            └────────────────────────┐
              ▼                                                              ▼
    [ dht11_sensor ]                                              [ ultrasonic_senser ]
    • Single-Bus Bidirectional IO                                 • 10us Trigger Pulse Gen
    • Pulse-Width Decoding FSM                                    • Echo High Time Counter
    • 40-bit Checksum Verification                                • Distance = tick / 58
              │ (humi, temp, done)                                           │ (distance, done)
              └────────────────────────┬─────────────────────────────────────┘
                                       ▼
                            [ sensor_reg_bank ]
                            • reg_humi[7:0], reg_humi_dec[7:0]
                            • reg_temp[7:0], reg_temp_dec[7:0]
                            • reg_dist[8:0]
                                       │
          ┌───────────────────────────┼───────────────────────────┐
          ▼                           ▼                           ▼
 [ spi_sensor_slave ]        [ i2c_sensor_slave ]        [ uart_controller ]
```

### 🌡️ 1) DHT11 온·습도 센서 드라이버 (`dht11_sensor.v`)
단선 양방향(Single-Bus Bidirectional) 규격을 구현하기 위해 $1\,\mu\text{s}$ 단위 시간 기준 틱(`us_tick`)을 생성하고 FSM을 통한 Tri-state 버퍼 제어 방식을 적용했습니다.

#### ⏱️ 데이터시트 타이밍 시퀀스 구현
1. **Host Start Signal (`S_START_LOW`):** 버스 라인을 최소 18ms(18,000µs) 동안 강제로 Low 구동하여 센서 웨이크업 유도
2. **Host Pull-up & Bus Release (`S_START_HIGH`):** 라인을 30µs 동안 High로 유지한 뒤, `io_mode <= 1'b1`로 전환하여 핀을 High-Z(입력 모드)로 전환 (외부 풀업에 의해 3.3V 유지)
3. **Sensor Response Handshake:**
   * `S_RESP_LOW`: 센서가 구동하는 약 80µs Low 구간 대기 후, 상승 에지(`dht_posedge`) 검출 시 다음 단계 전이
   * `S_RESP_HIGH`: 센서가 구동하는 약 80µs High 구간 대기 후, 하강 에지(`dht_negedge`) 검출 시 비트 수신 단계로 전이
4. **Data Bit Decoding (`S_BIT_LOW` $\rightarrow$ `S_BIT_HIGH`):**
   * 모든 데이터 비트의 시작인 50µs Low 구간 경과 확인
   * 이후 센서가 출력하는 High 펄스의 지속 시간(`high_cnt_us`)을 계측:
     * **Data '0':** High 지속 시간 26~28µs
     * **Data '1':** High 지속 시간 약 70µs
     * **판별 알고리즘:** High 폭이 40µs를 초과하는지 여부로 이진 데이터 디코딩
       ```verilog
       rx_shift <= {rx_shift[38:0], (high_cnt_us > 16'd40) ? 1'b1 : 1'b0};
       ```
5. **체크섬 검증 (`S_CHECK`):**
   * 수신 완료된 총 40비트 데이터에 대해 상위 4바이트의 합산과 최하위 체크섬 바이트 일치 여부 판별
   * 체크섬이 일치할 경우에만 `humidity`, `temperature` 레지스터를 갱신하고 `done <= 1'b1` 플래그 출력

---

### 📏 2) HC-SR04 초음파 거리 센서 드라이버 (`ultrasonic_senser.v`)
음파의 왕복 시간을 계측하여 거리를 산출하는 모듈로, 하드웨어 타이머와 에지 검출기를 결합하여 설계했습니다.

#### ⏱️ 데이터시트 타이밍 시퀀스 구현
1. **Trigger Pulse Generation (`START_SIGNAL`):**
   * `start_trig` 수신 시 `trig` 핀에 **10µs TTL High 펄스**를 정확히 출력하여 센서에 8사이클 초음파 버스트 송출 명령 전달
2. **Echo Pulse Edge Tracking (`WAIT_HIGH` $\rightarrow$ `READ_DATA`):**
   * 센서 내부 송출 후 수신 핀이 High로 상승하는 순간(`echo_posedge`)을 포착하여 $1\,\mu\text{s}$ 단위 카운터(`tick_cnt`) 계측 시작
   * 장애물에 반사되어 돌아온 파형으로 인해 Low로 복귀하는 순간(`echo_negedge`) 계측 종료
3. **하드웨어 거리 연산 메커니즘:**
   * 상온 기준 음속 기준 왕복 거리 공식:
     $$\text{Distance (cm)} = \frac{\text{Echo Pulse Width } (\mu\text{s}) \times 0.034}{2} = \frac{\text{Echo Pulse Width } (\mu\text{s})}{58.82}$$
   * FPGA 하드웨어 연산 자원을 최적화하기 위해 정수 나눗셈 연산자 적용:
     ```verilog
     distance <= tick_cnt / 58;
     ```

---

## 🔌 4. 통신 프로토콜 엔진 설계 (Communication Protocols)

### 1) SPI 통신 인터페이스 (`spi_master.v` & `spi_sensor_slave.v`)
- **프로토콜 사양:** SPI Mode 0 (CPOL = 0, CPHA = 0), `spi_clk` 상승 에지 샘플링 / 하강 에지 천이
- **24 SCLK 독자 프레임 설계:**
  * 초음파 거리 데이터(`reg_dist[8:0]`, 최대 수백 cm) 전송을 위해 표준 16비트 프레임 대신 **24-bit Custom Frame**을 독자 설계
- **동작 시퀀스:**
  1. `spi_cs`가 Low로 떨어지며 통신 프레임 개시
  2. **Phase 1 - Command 전송 및 래치 (0 ~ 7 SCLK):**
     * MOSI를 통해 8비트 커맨드 수신
     * `0x01` (`CMD_TEMP`): 온도 요청
     * `0x02` (`CMD_HUMI`): 습도 요청
     * `0x03` (`CMD_DIST`): 거리 요청
  3. **Phase 2 - Data 응답 시프트 (8 ~ 23 SCLK):**
     * `bit_count == 7` 시점에 수신된 커맨드를 즉각 디코딩하여 16비트 송신 버퍼(`reply_shift`)에 센서 레지스터 값을 사전 로드:
       * `CMD_TEMP`: `{8'b0, reg_temp[7:0]}` (예: 28℃ $\rightarrow$ `0x00001C`)
       * `CMD_HUMI`: `{8'b0, reg_humi[7:0]}` (예: 17% $\rightarrow$ `0x000011`)
       * `CMD_DIST`: `{7'b0, reg_dist[8:0]}` (예: 59cm $\rightarrow$ `0x00003B`)
     * 이후 16클럭 동안 `spi_clk` 하강 에지에 동기화하여 MISO 핀으로 MSB부터 1비트씩 직렬 송출

---

### 2) I2C 통신 인터페이스 (`i2c_master.v` & `i2c_sensor_slave.v`)
- **주소 지정:** 7-bit Slave Address = `7'h21` (R/W 포함 시 `Write: 0x42`, `Read: 0x43`)
- **19-상태 정밀 FSM 엔진:**
  * `IDLE` $\rightarrow$ `START_HOLD` $\rightarrow$ `START_LOW` $\rightarrow$ `BIT_SET` $\rightarrow$ `BIT_RISE` $\rightarrow$ `BIT_HIGH` $\rightarrow$ `BIT_FALL` $\rightarrow$ `ACK_SET` $\rightarrow$ `ACK_RISE` $\rightarrow$ `ACK_HIGH` $\rightarrow$ `ACK_FALL` $\rightarrow$ `STOP_SET` $\rightarrow$ `STOP_FREE` 등으로 세분화하여 신호 셋업/홀드 마진 확보
  * SCL이 High인 상태에서 SDA 하강 검출(Start) 및 상승 검출(Stop) 처리
  * 슬레이브 주소 매칭 시 9번째 클럭에서 SDA를 Low로 구동하는 ACK 반환
  * 양방향 Open-Drain 특성을 위해 `1'b1` 출력 시 High-Z(`1'bz`) 전환 처리

---

### 3) UART Controller & Standalone Monitor (`Uart_controller.v`, `bin2ascii.v`)
- **기능:** Master 제어 명령 입력 및 Slave 단독 센서 검증을 위한 디버깅 인터페이스
- **16x Oversampling 수신부 (`uart_rx.v`):**
  * 100MHz 시스템 클럭 기준 분주비 DIV = 651을 적용하여 $9600\,\text{bps} \times 16$ 오버샘플링 클럭 생성
  * Start Bit 감지 후 8번째 틱(비트 중앙)에서 안정성을 재확인하고, 이후 16틱 주기로 데이터 비트의 정중앙에서 샘플링하여 비트 에러 원천 차단
- **데이터 변환 송출:**
  * 8비트/9비트 이진수 센서 데이터를 실시간으로 3자리 10진수 ASCII 문자열로 디코딩 (`bin2ascii.v`)
  * `uart_tx.v`를 통해 PC 시리얼 터미널로 센서 상태 로그를 주기적으로 자동 전송

---

## 🧪 5. 시뮬레이션 및 하드웨어 실측 검증 (Verification)

| 검증 항목 | 검증 방식 | 주요 검증 결과 |
| :--- | :--- | :--- |
| **DHT11 Testbench (`tb_dht11_sensor.v`)** | 가상 센서 응답 모델 인가 (H: 68%, T: 25℃) | 40µs 펄스폭 판별 및 40비트 체크섬 통과 후 레지스터 정상 래치 확인 |
| **HC-SR04 Testbench (`tb_ultrasonic_sensor.v`)** | 15cm, 50cm, 100cm 대응 Echo High 시간 주입 | 정수 나눗셈(`tick/58`) 연산 결과 거리 오차 0cm 일치 확인 |
| **UART Controller (`tb_uart_controller.v`)** | 센서 레지스터 갱신에 따른 ASCII 변환 및 TX 시퀀스 | 16x 오버샘플링 기반 텍스트 직렬 전송 타이밍 무결성 검증 |
| **SPI Slave Response (`tb_top_slave.v`)** | Master SPI 클럭 인가에 따른 24-clock MISO 프레임 응답 | 커맨드 수신(`0x01`~`0x03`) 및 16비트 센서 데이터 지연 없는 출력 확인 |
| **I2C Signal Probing** | Oscilloscope & Logic Analyzer 실측 | 외부 1kΩ 풀업 적용 후 400kHz 대역 신호 무결성 및 주소 매칭 확인 |

---

## 📁 6. 프로젝트 디렉토리 구조 (Repository Structure)

```text
FPGA-Multi-Sensor-Network
├── .gitignore
├── README.md
├── Master/                                       # Master 보드 프로젝트 (데이터 수신 및 OLED 시각화)
│   ├── README.md
│   └── master_top_basys3/
│       ├── master_top_basys3.xpr                 # Vivado 프로젝트 파일
│       └── master_top_basys3.srcs/
│           ├── constrs_1/imports/digilent-xdc-master/
│           │   └── Basys3-Master_original.xdc    # Master 핀 제약 파일 (Clock, Switch, Button, OLED, I2C/SPI Pin)
│           ├── sim_1/new/                        # Master 시뮬레이션 테스트벤치
│           │   ├── tb_master_top.v               # Master 전체 통합 테스트벤치
│           │   ├── tb_spi_master.v               # SPI Master 통신 검증용 TB
│           │   └── tb_oled_controller.v          # SSD1306 초기화 및 I2C 통신 검증용 TB
│           └── sources_1/new/                    # Master RTL 소스 코드
│               ├── top_master.v                  # Master 최상위 통합 모듈 (Dynamic Router & FSM)
│               ├── master_controller.v           # 버튼/스위치 및 UART 커맨드 해석기
│               ├── spi_master.v                  # 24-Clock SPI Master 통신 엔진
│               ├── i2c_master.v                  # 19-State I2C Master 통신 엔진
│               ├── ssd1306_controller.v          # SSD1306 OLED 디스플레이 드라이버 (초기화 및 텍스트 렌더링)
│               ├── oled_font_rom.v               # OLED 문자 표기를 위한 ASCII 폰트 ROM
│               ├── uart_rx.v                     # 16x Oversampling UART 수신 모듈 (커맨드 입력용)
│               └── uart_tx.v                     # 디버그용 UART 송신 모듈
└── Slave/                                        # Slave 보드 프로젝트 (센서 수집 및 버스 응답)
    ├── README.md
    └── slave_spi_basys3/
        ├── slave_spi_basys3.xpr                  # Vivado 프로젝트 파일
        └── slave_spi_basys3.srcs/
            ├── constrs_1/imports/digilent-xdc-master/
            │   └── Basys3-Master_orginal.xdc     # Slave 핀 제약 파일 (Clock, DHT11, 초음파, I2C/SPI Pin)
            ├── sim_1/new/                        # Slave 시뮬레이션 테스트벤치
            │   ├── tb_top_slave.v                # Slave 전체 통합 테스트벤치
            │   ├── tb_dht11_sensor.v             # DHT11 가상 센서 에뮬레이션 TB
            │   ├── tb_ultrasonic_sensor.v        # HC-SR04 가상 에코 생성 TB
            │   └── tb_uart_controller.v          # 단독 UART 모니터링 검증용 TB
            └── sources_1/new/                    # Slave RTL 소스 코드
                ├── top_slave.v                   # Slave 최상위 통합 모듈
                ├── senser_trig_generator.v       # 센서별 주기 트리거 발생기 (DHT 1.5s / 초음파 500ms)
                ├── dht11_sensor.v                # DHT11 1-Wire FSM 및 40-bit 체크섬 디코더
                ├── ultrasonic_senser.v           # HC-SR04 10us 트리거 생성 및 에코 폭 연산기
                ├── sensor_reg_bank.v             # 센서 측정값 동기화 레지스터 뱅크
                ├── spi_sensor_slave.v            # 24-Clock Custom SPI Slave 엔진
                ├── i2c_sensor_slave.v            # 7-bit Slave Address 매칭 및 I2C Slave 엔진
                ├── Uart_controller.v             # Slave 단독 디버깅용 UART 컨트롤러
                ├── bin2ascii.v                   # 8/9비트 이진수를 3자리 10진수 ASCII로 변환
                ├── uart_rx.v                     # 단독 제어용 UART 수신 모듈
                └── uart_tx.v                     # 단독 모니터링용 UART 송신 모듈
```

---

## 💡 8. 구현 후기 및 회고 (Conclusion & Reflection)

- **고지현:**  
  "UART, I2C, SPI 등 대표적인 시리얼 통신 프로토콜을 RTL 레벨에서 직접 설계하고 검증하면서, 각 프로토콜이 요구하는 셋업/홀드 마진과 상태 머신 핸드셰이크의 동작 원리를 뼈저리게 체감하고 깊이 이해할 수 있었습니다."
- **김형진:**  
  "단순히 디지털 로직의 문법적 무결성에 그치지 않고, 외부 풀업 저항과 선로 기생 커패시턴스로 인한 RC 시정수 등 아날로그 하드웨어 특성이 전체 통신에 미치는 영향을 오실로스코프로 실측하고 해결하면서 임베디드 하드웨어 디버깅 역량을 크게 기를 수 있었습니다."
