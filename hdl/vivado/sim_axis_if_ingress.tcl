# Non-project xsim flow for Phase-4 axis_if_ingress (tb_axis_if_ingress).
#
# Prerequisites
#   - Vivado settings script sourced so xvlog/xelab/xsim are on PATH
#   - Vectors under hdl/tb/readout_chain/vectors/ (Phase 3 fixtures)
#
# From repo root (Windows example after settings64.bat)::
#
#   vivado -mode batch -source hdl/vivado/sim_axis_if_ingress.tcl
#
# Expected: ALL CASES PASSED (unpack bit-exact; sample_count == N; m_last on TLAST)

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set rtl_v      [file join $repo_root hdl rtl axi_interface axis_if_ingress.v]
set tb_sv      [file join $repo_root hdl tb axi_interface tb_axis_if_ingress.sv]
set vec_dir    [file join $repo_root hdl tb readout_chain vectors]
set work_dir   [file join $repo_root hdl vivado xsim_axis_if_ingress]

puts "repo_root = $repo_root"
puts "vec_dir   = $vec_dir"

if {![file isfile [file join $vec_dir readout_chain_params.svh]]} {
  puts "ERROR: missing $vec_dir/readout_chain_params.svh"
  puts "Run:  python hdl/tb/readout_chain/export_fixtures.py"
  exit 1
}
if {![file isfile $rtl_v]} {
  puts "ERROR: missing RTL $rtl_v"
  exit 1
}
if {![file isfile $tb_sv]} {
  puts "ERROR: missing testbench $tb_sv"
  exit 1
}

file mkdir $work_dir
cd $work_dir

foreach leftover {xsim.dir xvlog.pb xelab.pb xsim_*.jou xsim_*.log} {
  catch {file delete -force {*}[glob -nocomplain $leftover]}
}

puts "=== xvlog ==="
set rc [catch {
  exec xvlog -sv \
    -i $vec_dir \
    $rtl_v $tb_sv \
    >@stdout 2>@stderr
} err]
if {$rc != 0} {
  puts "xvlog failed: $err"
  exit 1
}

puts "=== xelab ==="
set rc [catch {
  exec xelab -debug typical tb_axis_if_ingress -s tb_axis_if_ingress_sim >@stdout 2>@stderr
} err]
if {$rc != 0} {
  puts "xelab failed: $err"
  exit 1
}

puts "=== xsim ==="
set vec_dir_fwd [string map {\\ /} $vec_dir]
set run_log [file join $work_dir tb_axis_if_ingress_run.log]
set rc [catch {
  exec xsim tb_axis_if_ingress_sim -runall -testplusarg VECDIR=$vec_dir_fwd > $run_log 2>@1
} err]

if {[file isfile $run_log]} {
  set fh [open $run_log r]
  set logdata [read $fh]
  close $fh
  puts -nonewline $logdata
} else {
  set logdata ""
}

set passed [expr {[string first "tb_axis_if_ingress: ALL CASES PASSED" $logdata] >= 0}]

if {$passed} {
  puts "xsim completed successfully (ALL CASES PASSED)."
  exit 0
}

puts "xsim did not report ALL CASES PASSED."
if {$rc != 0} {
  puts "$err"
}
exit 1
