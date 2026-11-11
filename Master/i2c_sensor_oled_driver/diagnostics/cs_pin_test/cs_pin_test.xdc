# Basys3 xc7a35tcpg236-1: JB10 = FPGA package pin C16.
set_property -dict {PACKAGE_PIN C16 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW} [get_ports spi_cs_n]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
