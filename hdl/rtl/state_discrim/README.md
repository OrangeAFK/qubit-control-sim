# state_discrim

Threshold/state-discrimination module (fixed threshold Phase 3, classifier-driven Phase 8).

## Status

- **Testbench:** `hdl/tb/state_discrim/tb_state_discrim.sv` (awaiting human review).
- **RTL:** `state_discrim.v` — **empty shell** for xsim elaborate only. Do not
  implement the compare until the TB is reviewed.

Port / Q-format contract: `docs/fixed_point_notes.md` § state_discrim
(Q12.14 integrated IQ + threshold → 1-bit decision; bit-exact vs fixtures).

Simulate from repo root (after `settings64.bat`):

```
vivado -mode batch -source hdl/vivado/sim_state_discrim.tcl
```
