set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root .verification optimized_i2c]
file mkdir $out
set rows {}
foreach variant {original optimized} {
    foreach top {i2c_sensor_read_master i2c_sensor_slave} {
        create_project -in_memory -part xc7a35tcpg236-1
        if {$variant eq "optimized"} {
            read_verilog -sv [file join $root optimized_i2c ${top}.sv]
        } elseif {$top eq "i2c_sensor_slave"} {
            read_verilog [file join $root slave_basys3 rtl ${top}.v]
        } else {
            read_verilog [file join $root i2c_sensor_oled_driver.srcs sources_1 new ${top}.v]
        }
        synth_design -top $top -part xc7a35tcpg236-1
        create_clock -name sys_clk -period 10 [get_ports clk]
        report_utilization -file [file join $out ${variant}_${top}_utilization.rpt]
        set ffs [llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]]
        set luts [llength [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]]
        lappend rows "$variant,$top,$luts,$ffs"
        close_project
    }
}
set fh [open [file join $out synthesis_comparison.csv] w]
puts $fh "variant,module,lut_primitives,flip_flops"
foreach row $rows { puts $fh $row }
close $fh
exit
