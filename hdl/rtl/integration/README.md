# integration

Integration/accumulation module. Phase 3.

## Status

- **Testbench:** `hdl/tb/integration/tb_integration.sv` (**awaiting human review**).
- **RTL:** `integration.v` — **empty shell** for xsim elaborate only. Do not
  implement real accumulation until the TB is reviewed.

Port / Q-format contract: `docs/fixed_point_notes.md` § integration
(Q1.14 in → Q12.14 out; window `start=8`, `length=1016`).
