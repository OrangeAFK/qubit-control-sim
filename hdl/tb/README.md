# tb

Per-module and top-level chain testbenches. One per RTL module minimum.

## Phase 3 — DDC

See [`ddc/`](ddc/) for `tb_ddc.sv`, fixture export script, and run instructions
(`hdl/vivado/sim_ddc.tcl`).

## Phase 3 — FIR (+ decimation)

See [`fir/`](fir/) for `tb_fir.sv`, fixture export script, and run instructions
(`hdl/vivado/sim_fir.tcl`). TB-only until human review; `hdl/rtl/fir/fir.v` is
an empty shell.
