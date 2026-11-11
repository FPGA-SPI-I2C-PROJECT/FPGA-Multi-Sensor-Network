# Master 코드 안내

최신 SPI/I2C 구성과 조작·핀 연결·프로토콜은 [README_NETWORK.md](README_NETWORK.md)를 참고한다.

Master Top은 `sensor_network_master`, Slave Top은 `top_slave_network`다. 기존 OLED용 `i2c_write_master`는 그대로 사용하며 보드 간 I2C 읽기에는 `i2c_sensor_read_master`를 추가했다. `sw[0]`=SPI, `sw[1]`=I2C이며 둘 중 하나만 켠 후 `btnC`로 요청한다.
