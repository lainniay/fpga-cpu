cd [file dirname [file normalize [info script]]]
if {![file exists ../../../func/obj/inst_ram.coe]} {
    error "Missing UART firmware: run make remote-uart-demo from the repository root first"
}

create_project -force loongson_remote ./project_remote -part xc7a200tfbg676-1

# Add local SoC sources
add_files -scan_for_includes ../rtl/soc_lite_top.v
add_files -scan_for_includes [glob -nocomplain ../rtl/BRIDGE/*.v]
add_files -scan_for_includes [glob -nocomplain ../rtl/CONFREG/*.v]
add_files -scan_for_includes [glob -nocomplain ../rtl/UART/*.v]

# Add remote platform wrapper
add_files -scan_for_includes ./remote/remote2local.v
add_files -scan_for_includes ./remote/loongson_remote_top.v

# Add myCPU
add_files -scan_for_includes [glob -nocomplain ../../../myCPU/*.v]

# Add memory IPs and the remote 50 MHz PLL
add_files -quiet ./remote/inst_ram/inst_ram.xci
add_files -quiet ../rtl/xilinx_ip/data_ram/data_ram.xci
add_files -quiet ./remote/clk_pll.xci

# Add remote constraints only
add_files -fileset constrs_1 -quiet ./remote/loongson_remote.xdc

set_property top loongson_remote_top [current_fileset]
set_property -name "top" -value "loongson_remote_top" -objects [get_filesets sim_1]
set_property -name "xsim.simulate.log_all_signals" -value "1" -objects [get_filesets sim_1]
