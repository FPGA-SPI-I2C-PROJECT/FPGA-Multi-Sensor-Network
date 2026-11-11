# 검증 결과

## 최신 상태: SPI 활성화 후 OLED 깨짐 분리 진단

사용자 확인: 128x64 패널이며 요청 버튼을 누르기 전부터 글자가 깨지고, Master LED[15]=1/LED[14]=0이다. 당시 현재 `impl_1` 리포트는 WNS +2.397ns, Hold +0.122ns로 타이밍을 통과했다. 이 정보만으로 SPI 활성화 파라미터 자체를 물리 원인으로 확정하지 않았다. LED[15]는 패킷 완료와 ACK 상태를 뜻하며, 화면의 문자 내용을 검사하지 않는다.

OLED 전송을 페이지 주소 모드로 보완했다. `0x20,0x02`로 설정하고, 매 페이지마다 `B0+page,00,10`으로 주소를 명시한 뒤 128바이트를 전송한다. 64픽셀 높이는 8페이지를 지운다. 4단계 픽셀 파이프라인과 기존 I2C 쓰기 드라이버 원본은 유지했다.

Master 수신부에는 상위 패딩 비트 검사를 추가했다. `FFFF`처럼 정상 프레임으로 만들 수 없는 응답은 오류 6 및 LED[2]로 표시하고 유효값으로 공개하지 않는다. 0 패딩된 유효 최댓값 `00FF`/`01FF`는 허용한다.

`OLED_SELF_TEST=1`은 센서값 대신 온도 25, 습도 60, 거리 123을 고정 표시하는 진단 설정이다. SPI 활성 상태와 실제 센서 표시 상태를 구분하기 위해 두 비트스트림을 만들었다.

| 구성 | 설정 및 결과 |
|---|---|
| 일반용 `.verification/normal/sensor_network_master.bit` | SPI=1, OLED_HEIGHT=64, OLED_SELF_TEST=0. 합성·배치·배선·타이밍·DRC 통과, 비트스트림 생성 성공 |
| 진단용 `.verification/oled_self_test/sensor_network_master.bit` | SPI=1, OLED_HEIGHT=64, OLED_SELF_TEST=1. 합성·배치·배선·타이밍·DRC 통과, 비트스트림 생성 성공 |
| 테스트벤치 | 32/64 높이, 페이지 주소/128바이트 전송, 유효 최댓값 허용과 FFFF 거절을 확인하도록 확장. 구문 분석과 32 높이 HDL 정적 elaboration 완료 |
| 기능 시뮬레이션 | XSim 생성 C 파일 컴파일 오류 `XSIM 43-3409`로 미완료 |
| 실제 OLED 출력 | 미확인. 진단용 고정 화면이 실제 패널에서 정상인지 확인 필요 |

이 변경으로 화면 깨짐의 물리적 원인이 확정되었다거나 실제 출력까지 검증되었다고 주장하지 않는다. 고정값 화면 결과를 통해 센서 응답값과 표시·초기화·배선 문제를 추가로 구분해야 한다.

## 최신 상태: Master 배치·배선 타이밍 위반 수정

사용자가 생성한 `impl_1/sensor_network_master_timing_summary_routed.rpt`에서 Setup WNS -0.768ns, TNS -4.560ns, 실패 endpoint 7개를 확인했다. 모든 실패 경로는 `display/oled_bus/byte_index_reg`에서 `display/oled_bus/shift_reg`로 향했다. 인덱스 감산·문자 위치 계산·ASCII 생성·글꼴 선택이 한 경로로 연결되어 논리 단계가 13~14개였다.

`oled_sensor_display.v`에서 픽셀 생성을 4단계 레지스터 파이프라인으로 분리했다. 100MHz 클록과 I2C 속도, 핀 제약은 유지했으며 위반 경로에 false path/multicycle 예외를 추가하지 않았다. 기존 `i2c_master_write.v` 내용도 유지했다.

| 항목 | 수정 전 impl_1 | 수정 후 배치·배선 |
|---|---|---|
| Setup WNS | -0.768ns | +2.103ns |
| Setup TNS | -4.560ns | 0.000ns |
| Setup 실패 endpoint | 7 | 0 |
| Hold WHS | +0.108ns | +0.122ns |
| Hold THS | 0.000ns | 0.000ns |
| Hold 실패 endpoint | 0 | 0 |

수정 후 `scripts/implement_timing_fix.tcl`로 현재 RTL을 합성·최적화·배치·물리 최적화·배선했다. 타이밍 통과와 DRC 확인 후 `write_bitstream`도 성공했다. 보고서와 검증된 Master 비트스트림은 `.verification/timing_fix/`에 있다. 열린 GUI의 기존 `impl_1` 결과를 덮어쓰지는 않았으므로, GUI에서 최신 결과를 표시하려면 합성부터 재실행해야 한다.

기존 I2C 코어는 `NEXT_BYTE`에서 인덱스를 갱신하고 한 quarter-period 뒤 `LOAD_BYTE`에서 데이터를 샘플링한다. 4클록 파이프라인이 이 시점 전에 안정되려면 quarter-period가 최소 5클록이어야 한다. 기본값은 250클록이고 가속 테스트 설정은 12클록이다. 지원 범위를 벗어난 시뮬레이션 설정에는 오류를 내도록 검사도 추가했다.

RTL과 테스트벤치 구문 분석 및 HDL 정적 elaboration은 완료했지만, 기능 시뮬레이션은 기존 XSim 생성 C 파일 컴파일 오류로 여전히 미완료다. 배치·배선 타이밍 통과는 실물 통신·화면 출력 기능 시험을 대신하지 않는다. FPGA 프로그래밍은 수행하지 않았다.

## 최신 상태: Slave I2C 및 Master SPI/I2C 선택 추가

후속 구현에서 `i2c_sensor_slave`, `i2c_sensor_read_master`, `top_slave_network`를 추가했다. Slave 프로젝트 Top은 이제 `top_slave_network`다. Master는 `sw[1:0]=01`이면 SPI, `10`이면 I2C를 요청 시작 시 고정해 사용한다. 두 버스가 동일한 원본 reg_bank를 읽으며 OLED용 기존 I2C 쓰기 드라이버는 변경하지 않았다.

| 확인 항목 | 결과 |
|---|---|
| Master SPI/I2C 구성 합성 | 성공 |
| Slave `top_slave_network` 합성 | 성공 |
| 각 구성 합성 후 DRC | 각각 위반 0 |
| 두 방식 통합 TB, I2C 오류 TB | `xvlog` 구문 분석 성공 |
| 통합 TB HDL 정적 elaboration | 완료 |
| 기능 시뮬레이션 | 생성 C 파일 컴파일 단계 `XSIM 43-3409` 오류로 미완료 |
| 비트스트림 생성·실물 송수신 | 미실행 |

통합 시험은 두 방식의 센서 마스크 전체 조합, 거리 9비트 유지, OLED 잔상 제거, 스위치 변경 중 모드 고정, Master 리셋 후 I2C 버스 복구를 검증하도록 확장했다. 별도 I2C 오류 시험은 주소 NACK, 잘못된 선택값 NACK, 타임아웃 후 핀 해제, 일시적 SCL Low, 두 바이트 응답의 스냅샷 보존을 확인하도록 작성했다. **시험 코드를 작성·구문 분석한 사실을 기능 동작 통과로 해석하지 않는다.**

Slave 원본 센서·UART의 parameter 선언 경고와 이 실행 환경의 초기 Top 분석/Tcl store 경고는 로그에 남아 있다. 원본을 수정해 경고를 제거하지 않았으며 합성 후 DRC에서 설계 위반은 없었다. 최신 사용법은 `README_NETWORK.md`에 있다. 아래 내용은 이전 단계의 검증 이력이다.

## 최신 상태: Slave SPI 추가

2026-11-04 후속 작업에서 `slave_basys3/rtl/spi_sensor_slave.v`와 `top_slave_spi.v`, Slave 전용 Vivado 프로젝트를 추가했다. 원본 센서·reg_bank·UART 소스 7개는 Git blob SHA-1까지 대조해 지정 커밋과 바이트 단위로 일치함을 확인했다. 해시 기록은 `slave_basys3/original/SOURCE_MANIFEST.json`에 있다.

| 추가 확인 항목 | 결과 |
|---|---|
| Slave 전체 Top 합성 (`top_slave_spi`) | 성공, 406 LUT / 363 레지스터, 래치 0 |
| Slave 합성 후 DRC | 위반 0 |
| Master 프로젝트 연동 설정 | `SPI_PROTOCOL_READY=1` generic 저장 |
| 실제 새 SPI Slave + 원본 reg_bank를 연결한 통합 TB | `xvlog` 구문 분석 및 HDL 정적 elaboration 완료 |
| 통합 TB 기능 실행 | XSim 생성 C 컴파일 단계 `XSIM 43-3409` 오류로 미완료 |
| 실물 보드 다운로드 및 SPI 송수신 | 미실행 |
| 보드 간 I2C | 미구현. 기존 미지원 처리를 유지 |

Slave 합성 로그에는 원본 UART의 parameter 선언 관련 경고 10개와 프로젝트 초기 Top 분석 및 로컬 Tcl store 환경 경고가 있다. 이를 없애기 위해 원본 UART를 수정하지 않았다. 합성 오류는 없고 합성 후 DRC 위반은 0이다. 기능 시뮬레이션 또는 실물 검증을 통과했다는 의미는 아니다.

이제 SPI용 Slave RTL이 있으므로 아래의 “지정 Slave 통신부 미구현” 기록은 **기존 GitHub Top을 그대로 사용하던 최초 작업**에 대한 설명이다. 현재 사용하는 별도 Top은 `top_slave_spi`이며 기존 Top과 별도로 합성한다.

## 최초 Master 구현 때의 기록

검증일: 2026-11-04. 도구: 이 PC에 설치된 Vivado / XSim 2020.2.

| 확인 항목 | 결과 | 범위 |
|---|---|---|
| 지정된 Slave 브랜치 소스 확인 | 완료 | 커밋 `c4b9f75cd554f1cce983fad7fb0fa659678d326f`; SPI 내부 로직 및 Top 연결 미구현, 보드 간 I2C Slave 없음 |
| 기존 I2C 드라이버 원본 보존 | 통과 | 작업 전후 SHA-256 동일 |
| 새 RTL·SystemVerilog 테스트벤치 구문 분석 | 통과 | `xvlog --sv` |
| 제안 SPI 활성 구성 합성 | 통과 | `SPI_PROTOCOL_READY=1`, xc7a35tcpg236-1, 511 LUT / 365 레지스터, 래치 0 |
| 제안 SPI 활성 구성 합성 후 DRC | 통과 | 스위치 제약 수정 후 위반 0 |
| 실제 `.xpr` 기본 구성 합성 | 통과 | `SPI_PROTOCOL_READY=0`; 프로젝트에 소스·XDC·Top 등록 |
| 기본 구성 합성 후 DRC | 통과 | 위반 0 |
| 기능 시뮬레이션 | 미완료 | 아래 도구 실행 오류로 테스트벤치 본문 실행/통과를 확인하지 못함 |
| 배치·배선 후 타이밍 / 비트스트림 | 미실행 | 합성 및 합성 후 DRC까지 확인 |
| 두 보드 실물 통신 / OLED 실물 출력 | 미실행 | 실물 연결 시험 없음. 현재 Slave의 통신부 미구현으로 연동 불가 |

## 기능 시뮬레이션 제한

기본 실행은 `xvlog` 구문 분석과 HDL 정적 elaboration을 마친 후 XSim이 생성한 C 파일을 컴파일하는 단계에서 실패했다.

```text
ERROR: [XSIM 43-3409] Failed to compile generated C file .../xsim_1.c.
ERROR: [XSIM 43-3915] Encountered a fatal error. Cannot continue.
```

Vivado 내장 MinGW GCC를 직접 실행해도 Windows의 DLL 재배치 오류가 발생했다. 설치된 다른 C 컴파일러로 생성 코드를 빌드하는 대체 경로도 확인했으나 시뮬레이션 엔진 시작 시 `Simtcl 6-50`, 종료 코드 `-1073741819`로 실패했다. 도구 설치나 시스템 설정을 변경하지 않았다. 대체 빌드 실행 파일은 제거했다.

따라서 테스트벤치를 작성하고 구문을 확인한 사실과 기능 시험을 통과한 사실을 구분한다. 센서별 값 수신, 화면 잔상 제거, 리셋 등의 **동작 검증 완료를 주장하지 않는다**. 정상적인 XSim 실행 환경에서 `scripts/run_tests.ps1`을 실행하면 성공 로그가 없거나 `Fatal:`이 있으면 실패로 종료한다.

## 합성 및 프로젝트 설정

처음 작성한 XDC의 반복문이 Vivado 2020.2 XDC에서 지원되지 않아 스위치별 명시적 핀 제약으로 수정했다. 수정 후 기본 프로젝트 합성과 SPI 활성 합성 결과에 대해 각각 DRC 위반 0을 확인했다.

프로젝트의 자동 hierarchy 분석이 이 실행 환경에서 새 Top을 인식하지 못해 `SourceMgmtMode=None`의 수동 컴파일 순서를 사용하도록 저장했다. 이후 프로젝트의 합성 파일 목록에 새 RTL이 포함된 상태에서 `synth_design` 성공을 확인했다. 로그에는 초기 프로젝트 읽기 때 발생한 Top 자동 분석 경고와 로컬 Tcl store 접근 경고가 남아 있다. 이것을 기능 검증 통과로 해석하지 않는다.

기존 드라이버: `i2c_sensor_oled_driver.srcs/sources_1/new/i2c_master_write.v`.

```text
SHA256 E956CDA60F3690CF9BB6E72699951B4BDCD98D08B0F35402202D07457CCDFB3A
```

상세 실행 로그와 합성 보고서는 재생성 가능한 중간 결과로 `.verification/`에 있다. 재현용 기본 명령은 `README_SENSOR_MASTER.md`에 기재했다.
