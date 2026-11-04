# Run in Vivado Tcl console: source scripts/setup_sensor_master.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] eq ""} {
    open_project [file join $root i2c_sensor_oled_driver.xpr]
}
# Pause hierarchy analysis only while registering files. Restore it below so
# the GUI can show module instances and offer Set as Top in Hierarchy view.
set_property source_mgmt_mode None [current_project]
foreach name {spi_master_transfer i2c_sensor_read_master sensor_request_master request_button oled_sensor_display sensor_network_master} {
    set path [file join $root i2c_sensor_oled_driver.srcs sources_1 new ${name}.v]
    if {[llength [get_files -quiet $path]] == 0} {add_files -norecurse $path}
}
set xdc [file join $root i2c_sensor_oled_driver.srcs constrs_1 new sensor_network_master.xdc]
if {[llength [get_files -quiet $xdc]] == 0} {add_files -fileset constrs_1 -norecurse $xdc}
set_property top sensor_network_master [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
set tb [file join $root tests tb_sensor_network_master.sv]
foreach companion [list [file join $root slave_basys3 rtl spi_sensor_slave.v] [file join $root slave_basys3 rtl i2c_sensor_slave.v] [file join $root slave_basys3 original sensor_reg_bank.v]] {
    if {[llength [get_files -quiet $companion]] == 0} {add_files -fileset sim_1 -norecurse $companion}
}
if {[llength [get_files -quiet $tb]] == 0} {add_files -fileset sim_1 -norecurse $tb}
set error_tb [file join $root tests tb_i2c_sensor_errors.sv]
if {[llength [get_files -quiet $error_tb]] == 0} {add_files -fileset sim_1 -norecurse $error_tb}
set_property top tb_sensor_network_master [get_filesets sim_1]
set_property top_auto_set false [get_filesets sim_1]
set_property source_mgmt_mode All [current_project]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Sensor Master selected: sw[0] SPI, sw[1] I2C; use top_slave_network on Slave."
