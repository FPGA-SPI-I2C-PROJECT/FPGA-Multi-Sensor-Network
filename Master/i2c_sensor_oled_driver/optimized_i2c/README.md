# I2C 최적화 대체 코드

원본 `.v` 파일과 Vivado 프로젝트 설정을 유지한 채 작성한 별도 대체 소스다.

| 파일 | 내용 |
|---|---|
| `i2c_sensor_read_master.sv` | 주요 상태 10개, 공통 SCL 타이밍 처리, 2바이트 읽기 Master |
| `i2c_sensor_slave.sv` | 주요 상태 8개, Slave ACK 통합, Master ACK 단계 통합 |
| `tb_optimized_i2c.sv` | 100/400kHz 타이밍, 독립 클록, 오류·복구 및 Slave 별도 시험 |
| `run_tests.ps1` | 기존 통합/오류 시험의 복사본과 새 테스트벤치를 실행 |
| `compare_synthesis.tcl` | 원본과 대체 모듈을 각각 Basys3 FPGA용으로 합성해 자원 비교 |

## 적용 방법

모듈 이름, 파라미터 이름 및 포트는 기존 모듈과 같다. 향후 적용할 때는 기존 두 `.v` 모듈을 빌드 대상에서 제외하고 이 폴더의 두 `.sv` 파일을 대신 사용한다. 동일한 이름의 원본·대체 모듈을 동시에 컴파일하지 않는다. 현재 프로젝트의 소스 등록과 비트스트림은 변경하지 않았다.

RTL은 SystemVerilog 소스로 제공한다. 대부분 기존 Verilog 문법을 유지하되 `.sv`로 구분하여 원본 `.v` 파일을 보존했다.

## 구현 내용

Master는 `IDLE, BUS_FREE, START, TX_BYTE, RX_ACK, RESTART, RX_BYTE, TX_ACK, STOP, RECOVER` 상태를 사용한다. `phase`는 각 동작의 세부 순서를 나타내며, 데이터·ACK·복구 클록은 하나의 SCL 제어 블록을 공유한다.

Slave는 `IDLE, RX_ADDRESS, RX_REGISTER, SLAVE_ACK, TX, MASTER_ACK, WAIT_STOP, IGNORE` 상태를 사용한다. ACK 뒤 목적지는 `after_ack`에 저장하고, 기존 `ack_phase`를 Master ACK 처리에도 재사용한다.

주소 0x42, 명령 01/02/03, MSB 우선 16비트 응답, 읽기 시작 시 데이터 스냅샷, repeated START 및 STOP으로 분리된 읽기를 유지한다. 입력 동기화, 오픈드레인 출력, NACK/타임아웃 및 9클록 복구도 유지한다.

Master는 CLK_HZ/I2C_HZ로 계산한 반주기와 Standard/Fast-mode 최소 시간을 비교해 SCL Low/High 시간을 정한다. SCL High 타이머는 동기화된 실제 SCL High 확인 뒤 시작한다. START 유지, repeated START 설정, STOP 설정, 버스 해제 시간도 별도로 계산한다. 그러므로 실제 전송 속도는 I2C_HZ보다 조금 느릴 수 있다. 지원 범위는 I2C_HZ 1~400000, CLK_HZ/I2C_HZ 20 이상이며 양의 타임아웃을 사용한다. 실물 배선의 상승·하강 시간은 별도 확인해야 한다.

카운터 폭은 필요한 최대값으로 계산하고 Slave idle_count는 포화시켜 오버플로를 방지한다. 기본 Master 타이머는 최대 500클록을 표현하는 9비트이며 watchdog은 25비트다. Slave idle_count는 기본 22비트다. 주요 상태 수 감소만으로 전체 회로가 작아진다고 판단하지 않고 실제 합성 자원을 비교한다.

## 검증 실행

프로젝트 루트의 PowerShell에서 실행한다.

```powershell
.\optimized_i2c\run_tests.ps1
.\optimized_i2c\run_tests.ps1 -Synthesize
```

합성 비교만 실행할 경우:

```powershell
vivado.bat -mode batch -source optimized_i2c/compare_synthesis.tcl
```

기존 테스트벤치의 `state == 6` 조건은 `.verification/optimized_i2c/`에 생성하는 복사본에서 `state == instance.TX`로 바꾼다. 원본 테스트벤치는 수정하지 않는다. 시험 로그와 합성 비교 보고서도 `.verification/optimized_i2c/`에 생성한다.

현재 검증 결과와 제한은 `VALIDATION.md`를 참고한다.
