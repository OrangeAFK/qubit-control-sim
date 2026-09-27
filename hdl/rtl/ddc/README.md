# ddc

Digital downconversion module. Phase 3.

## Status

- **Testbench:** `hdl/tb/ddc/tb_ddc.sv` (human-reviewed).
- **RTL:** `ddc.v` — synthesizable NCO mixer (see below).

Port / Q-format contract: `docs/fixed_point_notes.md` § ddc.

## Algorithm

1. **Phase accumulator** (32-bit): load `phase0` once after `rst_n` release; on each
   accepted `in_valid` sample, mix with current phase then `phase += phase_inc`.
2. **NCO:** top-of-phase quadrant + 10-bit quarter-wave address + 8-bit linear
   interpolation into `sin_q14.vh` (Q1.14). Emits `cos(θ)`, `sin(θ)`.
3. **Mixer:** `out = (I + jQ) * (cos − j sin)` → Q2.28 products, 33-bit sum,
   round-nearest / saturate to Q1.14.

**Pipeline latency:** 1 clock after `phase0` load (first `in_valid` → `out_valid`
on the following edge). TB collects N samples from the first `out_valid`.

## Files

| File | Role |
|------|------|
| `ddc.v` | DUT |
| `sin_q14.vh` | Quarter-wave LUT init (included by `ddc.v`) |
| `gen_sin_lut.py` | Regenerates `sin_q14.vh` |
