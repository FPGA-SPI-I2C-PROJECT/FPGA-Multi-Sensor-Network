# Standalone Vivado: vivado -mode batch -source scripts/create_slave_project.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set slave_root [file join $root slave_basys3]
set project_file [file join $slave_root project slave_spi_basys3.xpr]
if {[current_project -quiet] ne ""} {
    error "Use a separate Vivado session for the Slave project."
}
if {[file exists $project_file]} {open_project $project_file} else {
    create_project slave_spi_basys3 [file join $slave_root project] -part xc7a35tcpg236-1
}
set_property source_mgmt_mode None [current_project]
foreach path [concat [glob [file join $slave_root original *.v]] [glob [file join $slave_root rtl *.v]]] {
    if {[llength [get_files -quiet $path]] == 0} {add_files -norecurse $path}
}
set xdc [file join $slave_root constraints Basys3-Slave-SPI.xdc]
if {[llength [get_files -quiet $xdc]] == 0} {add_files -fileset constrs_1 -norecurse $xdc}
set_property top top_slave_network [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
set_property source_mgmt_mode All [current_project]
update_compile_order -fileset sources_1
puts "Created companion Slave project: $project_file (top_slave_network: SPI + I2C)"
