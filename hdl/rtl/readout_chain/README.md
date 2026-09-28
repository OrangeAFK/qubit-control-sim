# readout_chain

Top-level Phase 3 readout DSP chain (DDC → FIR(+decim) → integration →
state discrimination).

## Status

- **Testbench:** `hdl/tb/readout_chain/tb_readout_chain.sv` — **awaiting human
  review** (this turn is TB + empty shell only).
- **RTL:** `readout_chain.v` — **empty shell** for elaborate only. Do **not**
  wire the four green modules until the TB is reviewed.

Port / Q-format contract: `docs/fixed_point_notes.md` § readout_chain
(Q1.14 IF in → Q12.14 integrated IQ + 1-bit decision; IQ abs error ≤ 1.0;
decisions bit-exact).

Simulate from repo root (after `settings64.bat`):

```
vivado -mode batch -source hdl/vivado/sim_readout_chain.tcl
```

Expected with empty shell: TIMEOUT / FAIL (no `out_valid`).
