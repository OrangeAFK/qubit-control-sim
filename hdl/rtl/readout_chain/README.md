# readout_chain

Top-level Phase 3 readout DSP chain (DDC → FIR(+decim) → integration →
state discrimination).

## Status

- **Testbench:** `hdl/tb/readout_chain/tb_readout_chain.sv` — human-reviewed
  (commit `a9a4fd9`).
- **RTL:** `readout_chain.v` — structural
  `ddc → fir(+decim) → integration → state_discrim`.

Port / Q-format contract: `docs/fixed_point_notes.md` § readout_chain
(Q1.14 IF in → Q12.14 integrated IQ + 1-bit decision; IQ abs error ≤ 1.0;
decisions bit-exact).

Simulate from repo root (after `settings64.bat`):

```
vivado -mode batch -source hdl/vivado/sim_readout_chain.tcl
```

Expected with structural DUT: `tb_readout_chain: ALL CASES PASSED`.
