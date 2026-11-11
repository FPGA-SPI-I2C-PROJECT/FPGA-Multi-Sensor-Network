set root [file normalize [file join [file dirname [info script]] ..]]
file mkdir [file join $root .verification]
# Non-project synthesis includes both transports, with SPI enabled.
create_project -in_memory -part xc7a35tcpg236-1
foreach name {i2c_master_write spi_master_transfer i2c_sensor_read_master sensor_request_master request_button oled_sensor_display sensor_network_master} {
    read_verilog [file join $root i2c_sensor_oled_driver.srcs sources_1 new ${name}.v]
}
read_xdc [file join $root i2c_sensor_oled_driver.srcs constrs_1 imports digilent-xdc-master Basys3-Master_orginal.xdc]
read_xdc [file join $root i2c_sensor_oled_driver.srcs constrs_1 new sensor_network_master.xdc]
synth_design -top sensor_network_master -part xc7a35tcpg236-1 -generic SPI_PROTOCOL_READY=1
report_utilization -file [file join $root .verification synthesis_utilization.rpt]
report_drc -file [file join $root .verification synthesis_drc.rpt]
write_checkpoint -force [file join $root .verification sensor_master_synth.dcp]
puts "PASS: SPI/I2C Master synthesis completed (not a physical board test)"
