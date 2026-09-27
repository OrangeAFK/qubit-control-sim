# Non-project xsim flow for the Phase-3 integration testbench (tb_integration).
#
# Prerequisites
#   - Vivado settings script sourced so xvlog/xelab/xsim are on PATH
#   - Vectors present under hdl/tb/integration/vectors/ (run export_fixtures.py)
#
# From repo root (Windows example after settings64.bat)::
#
#   vivado -mode batch -source hdl/vivado/sim_integration.tcl
#
# Expected with empty integration.v shell: xsim FAIL / TIMEOUT (no out_valid).
# Expected with real integration RTL: ALL CASES PASSED (within INT_TOL_LSB).

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set rtl_int    [file join $repo_root hdl rtl integration integration.v]
set tb_sv      [file join $repo_root hdl tb integration tb_integration.sv]
set vec_dir    [file join $repo_root hdl tb integration vectors]
set work_dir   [file join $repo_root hdl vivado xsim_integration]

puts "repo_root = $repo_root"
puts "vec_dir   = $vec_dir"

if {![file isfile [file join $vec_dir integration_params.svh]]} {
  puts "ERROR: missing $vec_dir/integration_params.svh"
  puts "Run:  python hdl/tb/integration/export_fixtures.py"
  exit 1
}
if {![file isfile $rtl_int]} {
  puts "ERROR: missing DUT/shell $rtl_int"
  exit 1
}
if {![file isfile $tb_sv]} {
  puts "ERROR: missing testbench $tb_sv"
  exit 1
}

file mkdir $work_dir
cd $work_dir

# Fresh compile each run
foreach leftover {xsim.dir xvlog.pb xelab.pb xsim_*.jou xsim_*.log} {
  catch {file delete -force {*}[glob -nocomplain $leftover]}
}

set rtl_int_dir [file join $repo_root hdl rtl integration]

puts "=== xvlog ==="
set rc [catch {
  exec xvlog -sv -i $vec_dir -i $rtl_int_dir $rtl_int $tb_sv >@stdout 2>@stderr
} err]
if {$rc != 0} {
  puts "xvlog failed: $err"
  exit 1
}

puts "=== xelab ==="
set rc [catch {
  exec xelab -debug typical tb_integration -s tb_integration_sim >@stdout 2>@stderr
} err]
if {$rc != 0} {
  puts "xelab failed: $err"
  exit 1
}

# Stay in work_dir (snapshot lives here). Pass absolute vector dir to TB.
puts "=== xsim ==="
set vec_dir_fwd [string map {\\ /} $vec_dir]
set run_log [file join $work_dir tb_integration_run.log]
set rc [catch {
  exec xsim tb_integration_sim -runall -testplusarg VECDIR=$vec_dir_fwd > $run_log 2>@1
} err]

if {[file isfile $run_log]} {
  set fh [open $run_log r]
  set logdata [read $fh]
  close $fh
  puts -nonewline $logdata
} else {
  set logdata ""
}

set passed [expr {[string first "tb_integration: ALL CASES PASSED" $logdata] >= 0}]

if {$passed} {
  puts "xsim completed successfully (ALL CASES PASSED)."
  exit 0
}

puts "xsim did not report ALL CASES PASSED (expected until real integration RTL exists)."
if {$rc != 0} {
  puts "$err"
}
exit 1
