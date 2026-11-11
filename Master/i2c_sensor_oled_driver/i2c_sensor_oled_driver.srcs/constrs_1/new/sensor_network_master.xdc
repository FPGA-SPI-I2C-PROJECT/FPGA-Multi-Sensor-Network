# Same JB pin positions as the inspected Slave constraints.
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33} [get_ports spi_miso]
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS33} [get_ports spi_mosi]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS33} [get_ports spi_sclk]
set_property -dict {PACKAGE_PIN C16 IOSTANDARD LVCMOS33} [get_ports spi_cs_n]
# Separate board-to-board I2C bus; matching JB1/JB2 on the Slave.
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS33} [get_ports board_sda]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports board_scl]
# Asynchronous physical inputs terminate at synchronizers.
set_false_path -from [get_ports {spi_miso board_sda board_scl btnC sw[*]}] -to [get_cells -hier -filter {ASYNC_REG == TRUE}]
