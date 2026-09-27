# integration

Integration/accumulation module. Phase 3.

## Status

- **Testbench:** `hdl/tb/integration/tb_integration.sv` (human-reviewed).
- **RTL:** `integration.v` — accumulate window
  `[INTEGRATE_START : INTEGRATE_START+INTEGRATE_LENGTH)` of accepted
  `in_valid` samples as Q12.14; pulse `out_valid` when the window completes.

Port / Q-format contract: `docs/fixed_point_notes.md` § integration
(Q1.14 in → Q12.14 out; window `start=8`, `length=1016`).

Simulate from repo root (after `settings64.bat`):

```
vivado -mode batch -source hdl/vivado/sim_integration.tcl
```
