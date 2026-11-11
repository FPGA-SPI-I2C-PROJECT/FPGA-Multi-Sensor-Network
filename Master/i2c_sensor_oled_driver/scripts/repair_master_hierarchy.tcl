# Source this script INSIDE the already-open Master Vivado GUI.
# Repair the live project, which can otherwise overwrite external .xpr edits.
set repair_root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] ne "" && [get_property NAME [current_project]] ne "i2c_sensor_oled_driver"} {
    error "This script is for the i2c_sensor_oled_driver Master project."
}
source [file join $repair_root scripts enable_paired_spi.tcl]
puts "Hierarchy update: [get_property SOURCE_MGMT_MODE [current_project]]"
puts "Master top: [get_property TOP [get_filesets sources_1]]"
puts "Simulation top: [get_property TOP [get_filesets sim_1]]"
puts "Open Sources > Hierarchy (not Libraries) to see the module tree."
