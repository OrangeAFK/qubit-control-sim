# fir

FIR low-pass + decimation module. Phase 3 / Phase 4 timing closure.

## Status

- **Testbench:** `hdl/tb/fir/tb_fir.sv` (approved).
- **RTL:** `fir.v` — multi-cycle MAC FIR(+decim M), matches `dsp_ref` centered
  convolution (`mode='same'`) then keep-every-`DECIM_M`.

Port / Q-format contract: `docs/fixed_point_notes.md` § fir.
Decimation **M = 4** is part of this stage (keep every M-th filtered sample).
Coeffs: `hdl/tb/fir/vectors/fir_coeffs.mem` (Q1.14), copied into the xsim work
dir by `hdl/vivado/sim_fir.tcl`.

**MAC:** snapshot on emit; `TAPS_PER_CYCLE=2` over 32 cycles; 8 engines
(emit period M=4). Round/sat registered after final accumulate.
