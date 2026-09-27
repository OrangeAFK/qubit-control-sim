# state_discrim

Threshold/state-discrimination module (fixed threshold Phase 3, classifier-driven Phase 8).

## Status

- **Testbench:** `hdl/tb/state_discrim/tb_state_discrim.sv` (approved).
- **RTL:** `state_discrim.v` — signed Q12.14 compare `in_i >= threshold`,
  one-cycle `out_valid` pulse, 1-bit `decision`. `in_q` unused.

Port / Q-format contract: `docs/fixed_point_notes.md` § state_discrim
(Q12.14 integrated IQ + threshold → 1-bit decision; bit-exact vs fixtures).

Simulate from repo root (after `settings64.bat`):

```
vivado -mode batch -source hdl/vivado/sim_state_discrim.tcl
```
