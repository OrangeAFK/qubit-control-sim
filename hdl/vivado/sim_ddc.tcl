# Non-project xsim flow for the Phase-3 DDC testbench (tb_ddc).
#
# Prerequisites
#   - Vivado settings script sourced so xvlog/xelab/xsim are on PATH
#   - Vectors present under hdl/tb/ddc/vectors/ (run export_fixtures.py if missing)
#
# From repo root (Windows example after settings64.bat)::
#
#   vivado -mode batch -source hdl/vivado/sim_ddc.tcl
#
# Or invoke the tools directly (this script does that; Vivado GUI not required)::
#
#   # after sourcing Vivado settings
#   tclsh hdl/vivado/sim_ddc.tcl
#
# Expected with real DDC RTL: ALL CASES PASSED (within DDC_TOL_LSB).

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set rtl_ddc    [file join $repo_root hdl rtl ddc ddc.v]
set tb_sv      [file join $repo_root hdl tb ddc tb_ddc.sv]
set vec_dir    [file join $repo_root hdl tb ddc vectors]
set work_dir   [file join $repo_root hdl vivado xsim_ddc]

puts "repo_root = $repo_root"
puts "vec_dir   = $vec_dir"

if {![file isfile [file join $vec_dir ddc_params.svh]]} {
  puts "ERROR: missing $vec_dir/ddc_params.svh"
  puts "Run:  python hdl/tb/ddc/export_fixtures.py"
  exit 1
}
if {![file isfile $rtl_ddc]} {
  puts "ERROR: missing DUT/shell $rtl_ddc"
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

set rtl_ddc_dir [file join $repo_root hdl rtl ddc]

puts "=== xvlog ==="
set rc [catch {
  exec xvlog -sv -i $vec_dir -i $rtl_ddc_dir $rtl_ddc $tb_sv >@stdout 2>@stderr
} err]
if {$rc != 0} {
  puts "xvlog failed: $err"
  exit 1
}

puts "=== xelab ==="
set rc [catch {
  exec xelab -debug typical tb_ddc -s tb_ddc_sim >@stdout 2>@stderr
} err]
if {$rc != 0} {
  puts "xelab failed: $err"
  exit 1
}

# Stay in work_dir (snapshot lives here). Pass absolute vector dir to TB.
puts "=== xsim ==="
# Convert to forward slashes for the plusarg (helps on Windows).
set vec_dir_fwd [string map {\\ /} $vec_dir]
set rc [catch {
  exec xsim tb_ddc_sim -runall -testplusarg VECDIR=$vec_dir_fwd >@stdout 2>@stderr
} err]

# xsim returns non-zero on $fatal; that is the expected pre-DUT outcome with the shell.
if {$rc != 0} {
  puts "xsim finished with non-zero status (expected until real DDC RTL exists)."
  puts "$err"
  exit 1
}

puts "xsim completed successfully."
exit 0
