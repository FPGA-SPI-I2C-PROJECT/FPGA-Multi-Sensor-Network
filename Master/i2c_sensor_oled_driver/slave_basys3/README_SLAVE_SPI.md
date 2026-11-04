# Slave 코드 안내: SPI + I2C

최신 사용법은 [README_NETWORK.md](../README_NETWORK.md)를 참고한다.

Slave 프로젝트는 `project/slave_spi_basys3.xpr`, 현재 합성 Top은 **`top_slave_network`**다. 파일명에 SPI가 남아 있지만 SPI/I2C를 모두 포함한다. 이전 `top_slave_spi`는 SPI 전용 참고 코드다.

- `rtl/i2c_sensor_slave.v`: 주소 0x42의 I2C 센서 응답부.
- `rtl/spi_sensor_slave.v`: SPI 센서 응답부.
- `rtl/top_slave_network.v`: 기존 센서·reg_bank·UART와 두 통신부 연결.
- `original/*.v`: 지정 브랜치의 센서·reg_bank·UART 원본 7개. Git blob 해시는 `original/SOURCE_MANIFEST.json`에 기록했다.

Slave 스위치로 모드를 맞출 필요는 없다. Master가 선택한 버스로 요청하며 두 통신부는 같은 reg_bank를 읽는다. I2C는 JB1/SDA, JB2/SCL이며 두 선에 3.3V 외부 풀업을 연결한다. 기존 GitHub `top_slave.v`는 변경하지 않았다.
