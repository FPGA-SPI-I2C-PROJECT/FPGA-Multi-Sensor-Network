set root [file normalize [file join [file dirname [info script]] ..]]
source [file join $root scripts setup_sensor_master.tcl]
puts "PROJECT_SYNTH_FILES: [get_files -compile_order sources -used_in synthesis]"
synth_design -top sensor_network_master -part xc7a35tcpg236-1
report_drc -file [file join $root .verification production_drc.rpt]
report_utilization -file [file join $root .verification production_utilization.rpt]
close_project
# Check the SPI/I2C netlist using the current pin constraints.
open_checkpoint [file join $root .verification sensor_master_synth.dcp]
read_xdc [file join $root i2c_sensor_oled_driver.srcs constrs_1 new sensor_network_master.xdc]
report_drc -file [file join $root .verification synthesis_drc.rpt]
puts "PASS: configured project synthesis and SPI/I2C constraint verification"
