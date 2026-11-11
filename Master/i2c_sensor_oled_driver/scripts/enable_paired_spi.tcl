# Run in the MASTER project only, when using top_slave_network on Slave.
set root [file normalize [file join [file dirname [info script]] ..]]
source [file join $root scripts setup_sensor_master.tcl]
set_property generic {SPI_PROTOCOL_READY=1} [get_filesets sources_1]
puts "Master SPI/I2C enabled for top_slave_network. Select one mode with sw[1:0]."
