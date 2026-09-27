# Non-project xsim flow for the Phase-3 FIR testbench (tb_fir).
#
# Prerequisites
#   - Vivado settings script sourced so xvlog/xelab/xsim are on PATH
#   - Vectors present under hdl/tb/fir/vectors/ (run export_fixtures.py if missing)
#
# From repo root (Windows example after settings64.bat)::
#
#   vivado -mode batch -source hdl/vivado/sim_fir.tcl
#
# Expected with empty fir.v shell: xsim FAIL / TIMEOUT (no out_valid).
# Expected with real FIR RTL: ALL CASES PASSED (within FIR_TOL_LSB).

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set rtl_fir    [file join $repo_root hdl rtl fir fir.v]
set tb_sv      [file join $repo_root hdl tb fir tb_fir.sv]
set vec_dir    [file join $repo_root hdl tb fir vectors]
set work_dir   [file join $repo_root hdl vivado xsim_fir]

puts "repo_root = $repo_root"
puts "vec_dir   = $vec_dir"

if {![file isfile [file join $vec_dir fir_params.svh]]} {
  puts "ERROR: missing $vec_dir/fir_params.svh"
  puts "Run:  python hdl/tb/fir/export_fixtures.py"
  exit 1
}
if {![file isfile $rtl_fir]} {
  puts "ERROR: missing DUT/shell $rtl_fir"
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

set rtl_fir_dir [file join $repo_root hdl rtl fir]

puts "=== xvlog ==="
set rc [catch {
  exec xvlog -sv -i $vec_dir -i $rtl_fir_dir $rtl_fir $tb_sv >@stdout 2>@stderr
} err]
if {$rc != 0} {
  puts "xvlog failed: $err"
  exit 1
}

puts "=== xelab ==="
set rc [catch {
  exec xelab -debug typical tb_fir -s tb_fir_sim >@stdout 2>@stderr
} err]
if {$rc != 0} {
  puts "xelab failed: $err"
  exit 1
}

# Stay in work_dir (snapshot lives here). Pass absolute vector dir to TB.
puts "=== xsim ==="
# Convert to forward slashes for the plusarg (helps on Windows).
set vec_dir_fwd [string map {\\ /} $vec_dir]
set run_log [file join $work_dir tb_fir_run.log]
# xsim may return 0 even after $fatal; capture transcript and require PASS banner.
set rc [catch {
  exec xsim tb_fir_sim -runall -testplusarg VECDIR=$vec_dir_fwd > $run_log 2>@1
} err]

# Echo transcript to console for interactive debugging.
if {[file isfile $run_log]} {
  set fh [open $run_log r]
  set logdata [read $fh]
  close $fh
  puts -nonewline $logdata
} else {
  set logdata ""
}

set passed [expr {[string first "tb_fir: ALL CASES PASSED" $logdata] >= 0}]

if {$passed} {
  puts "xsim completed successfully (ALL CASES PASSED)."
  exit 0
}

puts "xsim did not report ALL CASES PASSED (expected until real FIR RTL exists)."
if {$rc != 0} {
  puts "$err"
}
exit 1
