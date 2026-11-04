# Rebuild from the current RTL without disturbing the open GUI's run database.
set root [file normalize [file join [file dirname [info script]] ..]]
set build_variant normal
set top_generics {SPI_PROTOCOL_READY=1}
if {[info exists ::env(OLED_SELF_TEST_BUILD)] && $::env(OLED_SELF_TEST_BUILD) eq "1"} {
    set build_variant oled_self_test
    lappend top_generics OLED_SELF_TEST=1
}
set timing_build [file join $root .verification $build_variant]
file mkdir $timing_build
set_param general.maxThreads 2
create_project -in_memory -part xc7a35tcpg236-1
foreach name {i2c_master_write spi_master_transfer i2c_sensor_read_master sensor_request_master request_button oled_sensor_display sensor_network_master} {
    read_verilog [file join $root i2c_sensor_oled_driver.srcs sources_1 new ${name}.v]
}
read_xdc [file join $root i2c_sensor_oled_driver.srcs constrs_1 imports digilent-xdc-master Basys3-Master_orginal.xdc]
read_xdc [file join $root i2c_sensor_oled_driver.srcs constrs_1 new sensor_network_master.xdc]
synth_design -top sensor_network_master -part xc7a35tcpg236-1 -generic $top_generics
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -delay_type min_max -max_paths 10 -warn_on_violation -file [file join $timing_build timing_summary_routed.rpt]
report_drc -file [file join $timing_build drc_routed.rpt]
report_utilization -file [file join $timing_build utilization_routed.rpt]
write_checkpoint -force [file join $timing_build sensor_network_master_routed.dcp]
set setup_slack [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold_slack [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "ROUTED_TIMING: setup_slack=$setup_slack ns, hold_slack=$hold_slack ns"
if {$setup_slack < 0 || $hold_slack < 0} {error "Routed setup/hold timing still fails"}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]] != 0} {error "Routed DRC has errors"}
write_bitstream -force [file join $timing_build sensor_network_master.bit]
puts "PASS: $build_variant 100 MHz routed setup/hold; bitstream generated"
