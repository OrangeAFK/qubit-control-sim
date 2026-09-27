# fir

FIR low-pass + decimation module. Phase 3.

## Status

- **Testbench:** `hdl/tb/fir/tb_fir.sv` (awaiting human review — **TB only**).
- **RTL:** `fir.v` is an **empty shell** for xsim elaborate / fail-before-DUT.
  Do **not** treat it as the FIR implementation. Replace after TB review.

Port / Q-format contract: `docs/fixed_point_notes.md` § fir.
Decimation **M = 4** is part of this stage (keep every M-th filtered sample).
