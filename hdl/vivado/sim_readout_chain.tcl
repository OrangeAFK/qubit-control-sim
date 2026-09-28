# Non-project xsim flow for the Phase-3 readout_chain testbench (tb_readout_chain).
#
# Prerequisites
#   - Vivado settings script sourced so xvlog/xelab/xsim are on PATH
#   - Vectors present under hdl/tb/readout_chain/vectors/ (run export_fixtures.py)
#   - FIR coeff ROM at hdl/tb/fir/vectors/fir_coeffs.mem (staged into work dir)
#
# From repo root (Windows example after settings64.bat)::
#
#   vivado -mode batch -source hdl/vivado/sim_readout_chain.tcl
#
# Expected with empty readout_chain.v shell: xsim FAIL / TIMEOUT (no out_valid).
# Expected with real structural readout_chain RTL: ALL CASES PASSED
#   (IQ within RC_TOL_LSB; decisions bit-exact).

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set rtl_rc     [file join $repo_root hdl rtl readout_chain readout_chain.v]
set rtl_ddc    [file join $repo_root hdl rtl ddc ddc.v]
set rtl_fir    [file join $repo_root hdl rtl fir fir.v]
set rtl_int    [file join $repo_root hdl rtl integration integration.v]
set rtl_sd     [file join $repo_root hdl rtl state_discrim state_discrim.v]
set tb_sv      [file join $repo_root hdl tb readout_chain tb_readout_chain.sv]
set vec_dir    [file join $repo_root hdl tb readout_chain vectors]
set fir_vec    [file join $repo_root hdl tb fir vectors]
set work_dir   [file join $repo_root hdl vivado xsim_readout_chain]

puts "repo_root = $repo_root"
puts "vec_dir   = $vec_dir"

if {![file isfile [file join $vec_dir readout_chain_params.svh]]} {
  puts "ERROR: missing $vec_dir/readout_chain_params.svh"
  puts "Run:  python hdl/tb/readout_chain/export_fixtures.py"
  exit 1
}
foreach f [list $rtl_rc $rtl_ddc $rtl_fir $rtl_int $rtl_sd] {
  if {![file isfile $f]} {
    puts "ERROR: missing RTL $f"
    exit 1
  }
}
if {![file isfile $tb_sv]} {
  puts "ERROR: missing testbench $tb_sv"
  exit 1
}

file mkdir $work_dir
cd $work_dir

# Coeff ROM for fir $readmemh("fir_coeffs.mem") — cwd is work_dir
set coeff_src [file join $fir_vec fir_coeffs.mem]
if {![file isfile $coeff_src]} {
  puts "ERROR: missing $coeff_src"
  puts "Run:  python hdl/tb/fir/export_fixtures.py"
  exit 1
}
file copy -force $coeff_src [file join $work_dir fir_coeffs.mem]

# Fresh compile each run
foreach leftover {xsim.dir xvlog.pb xelab.pb xsim_*.jou xsim_*.log} {
  catch {file delete -force {*}[glob -nocomplain $leftover]}
}

set rtl_rc_dir  [file join $repo_root hdl rtl readout_chain]
set rtl_ddc_dir [file join $repo_root hdl rtl ddc]
set rtl_fir_dir [file join $repo_root hdl rtl fir]

puts "=== xvlog ==="
set rc [catch {
  exec xvlog -sv \
    -i $vec_dir \
    -i $rtl_rc_dir \
    -i $rtl_ddc_dir \
    -i $rtl_fir_dir \
    $rtl_ddc $rtl_fir $rtl_int $rtl_sd $rtl_rc $tb_sv \
    >@stdout 2>@stderr
} err]
if {$rc != 0} {
  puts "xvlog failed: $err"
  exit 1
}

puts "=== xelab ==="
set rc [catch {
  exec xelab -debug typical tb_readout_chain -s tb_readout_chain_sim >@stdout 2>@stderr
} err]
if {$rc != 0} {
  puts "xelab failed: $err"
  exit 1
}

# Stay in work_dir (snapshot lives here). Pass absolute vector dir to TB.
puts "=== xsim ==="
set vec_dir_fwd [string map {\\ /} $vec_dir]
set run_log [file join $work_dir tb_readout_chain_run.log]
set rc [catch {
  exec xsim tb_readout_chain_sim -runall -testplusarg VECDIR=$vec_dir_fwd > $run_log 2>@1
} err]

if {[file isfile $run_log]} {
  set fh [open $run_log r]
  set logdata [read $fh]
  close $fh
  puts -nonewline $logdata
} else {
  set logdata ""
}

set passed [expr {[string first "tb_readout_chain: ALL CASES PASSED" $logdata] >= 0}]

if {$passed} {
  puts "xsim completed successfully (ALL CASES PASSED)."
  exit 0
}

puts "xsim did not report ALL CASES PASSED."
if {$rc != 0} {
  puts "$err"
}
exit 1
