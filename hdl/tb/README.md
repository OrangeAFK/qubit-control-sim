# tb

Per-module and top-level chain testbenches. One per RTL module minimum.

## Phase 3 — DDC

See [`ddc/`](ddc/) for `tb_ddc.sv`, fixture export script, and run instructions
(`hdl/vivado/sim_ddc.tcl`).

## Phase 3 — FIR (+ decimation)

See [`fir/`](fir/) for `tb_fir.sv`, fixture export script, and run instructions
(`hdl/vivado/sim_fir.tcl`).

## Phase 3 — Integration / accumulation

See [`integration/`](integration/) for `tb_integration.sv`, fixture export
script, and run instructions (`hdl/vivado/sim_integration.tcl`).

## Phase 3 — State discrimination / threshold

See [`state_discrim/`](state_discrim/) for `tb_state_discrim.sv`, fixture export
script, and run instructions (`hdl/vivado/sim_state_discrim.tcl`).

## Phase 3 — Top-level readout chain

See [`readout_chain/`](readout_chain/) for `tb_readout_chain.sv`, fixture export
script, and run instructions (`hdl/vivado/sim_readout_chain.tcl`).

## Phase 4 — AXI-Stream IF ingress

See [`axi_interface/`](axi_interface/) for `tb_axis_if_ingress.sv` and
`hdl/vivado/sim_axis_if_ingress.tcl` (reuses `readout_chain/vectors/`).
