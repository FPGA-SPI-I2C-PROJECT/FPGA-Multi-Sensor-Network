# CS 단독 HIGH 진단

Master의 JB10(C16)에 HIGH만 출력하는 별도 진단이다. 클록·리셋·스위치·버튼·SPI FSM을 사용하지 않는다. 정상 Master·Slave RTL과 `.xpr`는 이 빌드에서 수정하지 않는다.

## 생성 파일

- RTL: `cs_pin_test.v`
- 핀 제약: `cs_pin_test.xdc`
- 빌드: `build_cs_pin_test.tcl`
- 비트스트림: 프로젝트 루트의 `.verification/cs_pin_test/cs_pin_test.bit`

Basys3의 `xc7a35tcpg236-1`용이다. 핀은 C16/JB10, I/O 표준은 LVCMOS33, 출력 구동 강도는 4mA다. 연결한 외부 회로가 없는 상태에서 약 3.3V를 기대한다. FPGA 구성 완료 후의 출력을 검사하며 전원 인가 직후 구성 이전의 핀 상태를 보장하는 테스트는 아니다.

## 측정

1. Slave로 이어지는 CS 점퍼를 분리한 상태로 둔다.
2. Vivado Hardware Manager에서 실제 Master 보드를 선택하고 `cs_pin_test.bit`로 Program Device 한다. 이 작업은 아직 자동 실행하지 않았다.
3. 프로브 그라운드는 Master GND, 팁은 Master JB10에 연결한다. 알려진 3.3V를 읽을 수 있는 DC 결합 설정을 그대로 사용한다.
4. SW15와 버튼 위치에 관계없이 JB10이 약 3.3V인지 확인한다. 이 진단에는 스위치 입력 자체가 없다.

| 측정 결과 | 해석 |
|---|---|
| 약 3.3V | 해당 출력 경로로 HIGH를 낼 수 있음. 정상 비트스트림 선택·클록·리셋·CS 제어 경로를 추가 확인 |
| 계속 0V | 측정 핀, 실제 다운로드 대상/파일, 잔여 단락이나 핀 상태를 추가 확인. 핀 손상으로 단정하지 않음 |

진단 비트스트림에는 정상 SPI·센서 수집·OLED 갱신 기능이 없다. OLED가 이전 화면을 유지해도 진단 결과가 아니다. 테스트 후에는 사용자가 선택한 정상 Master 비트스트림을 다시 다운로드해야 한다.

## 재현

별도 Vivado 배치 세션에서 다음을 실행한다.

```text
vivado -mode batch -source diagnostics/cs_pin_test/build_cs_pin_test.tcl
```

빌드는 배치·배선된 C16 출력 버퍼 입력이 VCC 상수에 연결되었는지, 출력 핀·전압 표준이 맞는지, DRC 위반이 없는지 검사한 뒤 비트스트림을 생성한다. 클록과 순차회로가 없으므로 100MHz Setup/Hold 타이밍 시험 대상은 아니다. 실제 핀 전압은 보드에서 측정해야 한다.
