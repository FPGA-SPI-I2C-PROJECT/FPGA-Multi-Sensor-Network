# 최적화 대체 코드 검증 결과

검증일: 2026-11-05. 도구: Vivado/XSim 2020.2. 대상 FPGA: xc7a35tcpg236-1.

원본 `.v` 파일과 프로젝트 설정은 수정하지 않았다. 대체 소스는 이 폴더의 두 `.sv` 파일이다.

## 실제 확인한 결과

| 항목 | 결과 |
|---|---|
| 새 RTL 두 모듈 및 테스트벤치 HDL 구문 분석 | 통과 (`xvlog --sv`) |
| 기존 통합 TB의 32행 구성, 오류 TB 및 새 TB 정적 elaboration | 완료, 이후 XSim C 컴파일 단계에서 중단 |
| 기본 파라미터에서 Master/Slave 각각 합성 | 모두 성공, 각각 경고 0 / 오류 0 |
| 합성된 래치 | 네 비교 구성 모두 0 |
| 기능 시뮬레이션 | 미완료: 테스트벤치 본문 실행 및 PASS를 확인하지 못함 |
| 배치·배선 타이밍 / 비트스트림 생성 / 실물 통신 | 미실행 |

## 동일 조건의 모듈별 합성 자원

기본 파라미터, 모듈 단독 Top, 같은 합성 도구와 FPGA 조건에서 비교했다.

| 모듈 | 주요 상태 수 (원본 → 대체) | Slice LUT (원본 → 대체) | FF (원본 → 대체) |
|---|---:|---:|---:|
| Master | 33 → 10 | 168 → 151 | 143 → 114 |
| Slave | 12 → 8 | 131 → 95 | 84 → 75 |

Slice LUT 값은 각 utilization 보고서의 Slice LUTs 행을 사용했다. 자동 CSV의 `lut_primitives`는 LUT1~LUT6 인스턴스의 단순 합계이므로 Slice LUTs 수와 다르다. 단독 모듈 합성 결과가 전체 Top의 최종 배치·배선 자원이나 타이밍을 보장하지는 않는다.

보고서 위치:

- `.verification/optimized_i2c/original_i2c_sensor_read_master_utilization.rpt`
- `.verification/optimized_i2c/optimized_i2c_sensor_read_master_utilization.rpt`
- `.verification/optimized_i2c/original_i2c_sensor_slave_utilization.rpt`
- `.verification/optimized_i2c/optimized_i2c_sensor_slave_utilization.rpt`
- `.verification/optimized_i2c/synthesis_comparison.csv`
- `.verification/optimized_i2c/synthesis.log`

## 기능 시험이 미완료인 이유

HDL 정적 elaboration 이후 XSim이 생성한 C 파일을 컴파일하는 단계에서 다음 오류가 발생했다. 프로젝트의 기존 검증 문서에도 기록된 것과 같은 오류이며, 테스트벤치의 `$fatal`이나 DUT 기능 불일치를 관측한 결과는 아니다.

```text
ERROR: [XSIM 43-3409] Failed to compile generated C file .../xsim_1.c.
ERROR: [XSIM 43-3915] Encountered a fatal error. Cannot continue. Exiting...
```

따라서 아래 시험은 작성하고 구문을 확인했지만 동작 통과를 주장하지 않는다.

- 기존 SPI/I2C 통합 시험 및 I2C 오류 시험의 대체 소스 연결 버전.
- 100/400kHz에서 버스 이벤트로 측정하는 SCL Low/High, SDA 설정, START/STOP 및 repeated START 타이밍 검사.
- 독립적인 Slave 클록에서 정상 센서값 읽기와 데이터 클록 중간의 clock stretching.
- 별도 bit-bang Master를 통한 STOP으로 분리된 포인터 쓰기/읽기, 첫 바이트 NACK, 마지막 바이트 ACK 처리.
- 잘못된 주소·명령, 무효 포인터 읽기, Slave idle timeout, SDA 고정 시 9클록 복구와 타임아웃 후 재통신.

정상적인 XSim 실행 환경에서 `run_tests.ps1`을 실행하면 각 시험의 PASS 문구와 종료 코드를 확인한다. 원본 `.v` 또는 원본 테스트벤치를 수정할 필요는 없다.
