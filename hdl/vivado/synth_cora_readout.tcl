# Non-project Vivado synth + implementation for Phase 4 Cora readout PL wrapper.
#
# Top: cora_readout_pl (axis_if_ingress + readout_chain + axi_lite_regs stub)
# Part: xc7z007sclg400-1  (Digilent Cora Z7-07S)
#
# Scope: fabric DSP core resource/timing (out-of-context). Does NOT build a
# Zynq PS Block Design, bitstream with DMA, or program the board. Full-chip
# place fails if every Lite/AXIS bit is a package pin (125 > 100 user IOs on
# xc7z007s); OOC treats ports as virtual until BD/PS attach. See README.md.
#
# From repo root (Windows, after settings64.bat)::
#
#   call C:\Xilinx\2025.1\Vivado\settings64.bat
#   vivado -mode batch -source hdl/vivado/synth_cora_readout.tcl
#
# Reports land under hdl/vivado/out_cora_readout/ and are copied to
# docs/reports/phase4_readout_<YYYY-MM-DD>_*.rpt on success.

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set out_dir    [file join $repo_root hdl vivado out_cora_readout]
set docs_rpt   [file join $repo_root docs reports]
set xdc        [file join $script_dir constraints cora_z7_07s_readout.xdc]
set fir_mem    [file join $repo_root hdl tb fir vectors fir_coeffs.mem]

set part       xc7z007sclg400-1
set top        cora_readout_pl

# RTL sources
set rtl_ddc    [file join $repo_root hdl rtl ddc ddc.v]
set rtl_fir    [file join $repo_root hdl rtl fir fir.v]
set rtl_int    [file join $repo_root hdl rtl integration integration.v]
set rtl_sd     [file join $repo_root hdl rtl state_discrim state_discrim.v]
set rtl_rc     [file join $repo_root hdl rtl readout_chain readout_chain.v]
set rtl_axis   [file join $repo_root hdl rtl axi_interface axis_if_ingress.v]
set rtl_lite   [file join $repo_root hdl rtl axi_interface axi_lite_regs.v]
set rtl_top    [file join $repo_root hdl rtl top cora_readout_pl.v]
set ddc_inc    [file join $repo_root hdl rtl ddc]

puts "repo_root = $repo_root"
puts "part      = $part"
puts "top       = $top"
puts "out_dir   = $out_dir"

foreach f [list $rtl_ddc $rtl_fir $rtl_int $rtl_sd $rtl_rc $rtl_axis $rtl_lite $rtl_top $xdc $fir_mem] {
  if {![file isfile $f]} {
    puts "ERROR: missing $f"
    exit 1
  }
}

file mkdir $out_dir
file mkdir $docs_rpt
cd $out_dir

# FIR $readmemh("fir_coeffs.mem") resolves relative to cwd / design search path
file copy -force $fir_mem [file join $out_dir fir_coeffs.mem]
# Also stage next to fir.v for tools that search the RTL file directory
file copy -force $fir_mem [file join $repo_root hdl rtl fir fir_coeffs.mem]

# Fresh run artifacts (keep prior reports if any)
foreach leftover {*.jou *.log .Xil} {
  catch {file delete -force {*}[glob -nocomplain $leftover]}
}

puts "=== read_verilog (SystemVerilog) ==="
# Phase-3 RTL uses SV casts (e.g. ACC_W'(32767)); .v extension still needs -sv.
read_verilog -sv $rtl_ddc
read_verilog -sv $rtl_fir
read_verilog -sv $rtl_int
read_verilog -sv $rtl_sd
read_verilog -sv $rtl_rc
read_verilog -sv $rtl_axis
read_verilog -sv $rtl_lite
read_verilog -sv $rtl_top

puts "=== read_xdc ==="
read_xdc $xdc

puts "=== synth_design (out_of_context) ==="
# OOC: AXI Lite/Stream ports stay virtual — Cora Z7-07S has only ~100 user IOs;
# exposing the full Lite+AXIS bus as package pins is infeasible (Place 30-58).
# PS/DMA attach in a later BD consumes interconnect, not PL IOB pins per bit.
set synth_rc [catch {
  synth_design -top $top -part $part -mode out_of_context \
    -include_dirs [list $ddc_inc] -flatten_hierarchy rebuilt
} synth_err]
if {$synth_rc != 0} {
  puts "ERROR: synth_design failed: $synth_err"
  exit 1
}

puts "=== opt_design ==="
opt_design

puts "=== place_design ==="
place_design

puts "=== route_design ==="
route_design

# Timestamp for report names (UTC date)
set date_str [clock format [clock seconds] -format "%Y-%m-%d"]

set util_rpt   [file join $out_dir utilization.rpt]
set timing_rpt [file join $out_dir timing_summary.rpt]
set dcp        [file join $out_dir cora_readout_pl_routed.dcp]

puts "=== report_utilization ==="
report_utilization -file $util_rpt
puts "=== report_timing_summary ==="
report_timing_summary -file $timing_rpt -delay_type min_max -max_paths 10

puts "=== write_checkpoint ==="
write_checkpoint -force $dcp

# Combined human-facing report under docs/reports/
set docs_combined [file join $docs_rpt "phase4_readout_${date_str}.txt"]
set fh [open $docs_combined w]
puts $fh "Phase 4 Cora Z7-07S readout PL — Vivado non-project synth+impl"
puts $fh "Generated: [clock format [clock seconds]]"
puts $fh "Part: $part"
puts $fh "Top:  $top"
puts $fh "Flow: hdl/vivado/synth_cora_readout.tcl"
puts $fh "DCP:  $dcp"
puts $fh ""
puts $fh "========== utilization.rpt =========="
set uf [open $util_rpt r]
puts -nonewline $fh [read $uf]
close $uf
puts $fh ""
puts $fh "========== timing_summary.rpt =========="
set tf [open $timing_rpt r]
puts -nonewline $fh [read $tf]
close $tf
close $fh

# Also keep native-named copies in docs/reports
file copy -force $util_rpt   [file join $docs_rpt "phase4_readout_${date_str}_utilization.rpt"]
file copy -force $timing_rpt [file join $docs_rpt "phase4_readout_${date_str}_timing.rpt"]

puts "OK: reports written:"
puts "  $docs_combined"
puts "  [file join $docs_rpt phase4_readout_${date_str}_utilization.rpt]"
puts "  [file join $docs_rpt phase4_readout_${date_str}_timing.rpt]"
puts "  $util_rpt"
puts "  $timing_rpt"
puts "  $dcp"
exit 0
