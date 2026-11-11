set root [file normalize [file join [file dirname [info script]] ..]]
source [file join $root scripts create_slave_project.tcl]
set_param general.maxThreads 1
synth_design -top top_slave_network -part xc7a35tcpg236-1
report_utilization -file [file join $root .verification slave_spi_utilization.rpt]
report_drc -file [file join $root .verification slave_spi_drc.rpt]
write_checkpoint -force [file join $root .verification slave_spi_synth.dcp]
puts "PASS: companion SPI/I2C Slave synthesis completed"
