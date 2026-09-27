# Non-project xsim flow for the Phase-3 state_discrim testbench (tb_state_discrim).
#
# Prerequisites
#   - Vivado settings script sourced so xvlog/xelab/xsim are on PATH
#   - Vectors present under hdl/tb/state_discrim/vectors/ (run export_fixtures.py)
#
# From repo root (Windows example after settings64.bat)::
#
#   vivado -mode batch -source hdl/vivado/sim_state_discrim.tcl
#
# Expected with empty state_discrim.v shell: xsim FAIL / TIMEOUT (no out_valid).
# Expected with real state_discrim RTL: ALL CASES PASSED (bit-exact decisions).

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set rtl_sd     [file join $repo_root hdl rtl state_discrim state_discrim.v]
set tb_sv      [file join $repo_root hdl tb state_discrim tb_state_discrim.sv]
set vec_dir    [file join $repo_root hdl tb state_discrim vectors]
set work_dir   [file join $repo_root hdl vivado xsim_state_discrim]

puts "repo_root = $repo_root"
puts "vec_dir   = $vec_dir"

if {![file isfile [file join $vec_dir state_discrim_params.svh]]} {
  puts "ERROR: missing $vec_dir/state_discrim_params.svh"
  puts "Run:  python hdl/tb/state_discrim/export_fixtures.py"
  exit 1
}
if {![file isfile $rtl_sd]} {
  puts "ERROR: missing DUT/shell $rtl_sd"
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

set rtl_sd_dir [file join $repo_root hdl rtl state_discrim]

puts "=== xvlog ==="
set rc [catch {
  exec xvlog -sv -i $vec_dir -i $rtl_sd_dir $rtl_sd $tb_sv >@stdout 2>@stderr
} err]
if {$rc != 0} {
  puts "xvlog failed: $err"
  exit 1
}

puts "=== xelab ==="
set rc [catch {
  exec xelab -debug typical tb_state_discrim -s tb_state_discrim_sim >@stdout 2>@stderr
} err]
if {$rc != 0} {
  puts "xelab failed: $err"
  exit 1
}

# Stay in work_dir (snapshot lives here). Pass absolute vector dir to TB.
puts "=== xsim ==="
set vec_dir_fwd [string map {\\ /} $vec_dir]
set run_log [file join $work_dir tb_state_discrim_run.log]
set rc [catch {
  exec xsim tb_state_discrim_sim -runall -testplusarg VECDIR=$vec_dir_fwd > $run_log 2>@1
} err]

if {[file isfile $run_log]} {
  set fh [open $run_log r]
  set logdata [read $fh]
  close $fh
  puts -nonewline $logdata
} else {
  set logdata ""
}

set passed [expr {[string first "tb_state_discrim: ALL CASES PASSED" $logdata] >= 0}]

if {$passed} {
  puts "xsim completed successfully (ALL CASES PASSED)."
  exit 0
}

puts "xsim did not report ALL CASES PASSED (expected until real state_discrim RTL exists)."
if {$rc != 0} {
  puts "$err"
}
exit 1
