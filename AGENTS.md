# AGENTS.md

Instructions for AI coding agents working in this repo. Read `ARCHITECTURE.md` and
`PLAN.md` first — this file is workflow/convention, not technical spec.

Defaults below are reasonable starting points, not fixed requirements — adjust anything
in this file that doesn't fit how you're actually working, then keep it updated so it
stays true.

## Source of truth

- `ARCHITECTURE.md` — interfaces, data formats, module responsibilities. If your
  implementation needs to deviate from it, update the doc in the same PR, don't let
  code and doc drift.
- `PLAN.md` — what to build next, in order, with acceptance criteria. Don't start a
  phase whose dependencies (earlier phases) aren't done and passing their own
  acceptance criteria.

## Workflow (default — adjust if working differently)

- One feature branch per PLAN.md phase (or per major task within a phase, if the phase
  is large). Don't mix phases in one branch.
- Agent opens a PR per branch; human reviews and merges. This includes PRs that only
  change `ARCHITECTURE.md` or `PLAN.md`.
- Don't mark a PLAN.md checkbox done in the same commit that implements it — do it in
  the PR that merges after acceptance criteria are demonstrated (test output, plot, or
  report present in the repo).

## Test-driven development (required)

For every atomic task in PLAN.md:
1. Write the test first (pytest for Python, a testbench for HDL).
2. Confirm it fails for the right reason.
3. Implement until it passes.
4. Don't move to the next task until the current one's test passes.

This applies to HDL exactly like Python — a module without a passing testbench is not
done, regardless of whether it synthesizes.

## Python conventions

- Package: `python/cryocontrol/`, tests: `python/tests/`, mirroring package structure
  (`python/tests/models/test_resonator.py` for `python/cryocontrol/models/resonator.py`).
- Type hints on public functions.
- `pytest` for all tests; a test file per module minimum.
- No direct hardware register access outside `python/cryocontrol/hardware/` — Phase 6+
  experiment code goes through the Instrument/Parameter abstraction (ARCHITECTURE.md §3.1).

## HDL conventions

- Verilog or SystemVerilog, one module per file, filename matches module name.
- Testbenches in `hdl/tb/`, one per RTL module minimum, plus top-level chain testbenches
  where PLAN.md calls for them (e.g. Phase 3's end-to-end readout-chain testbench).
- Default simulator: whatever ships with your Vivado install (xsim), run via the
  non-project TCL flow in `hdl/vivado/`. If you're set up with a different
  simulator/flow (e.g. Icarus + cocotb), that's fine — just record the choice here and
  keep it consistent across the project; don't mix simulator flows between modules.
- Fixed-point format for every module: documented in `docs/fixed_point_notes.md` **before**
  writing the RTL, not reverse-engineered afterward. Entry format:

  ```
  ## <module name>
  Format: Q<int_bits>.<frac_bits>, signed/unsigned
  Range: <min> to <max>
  Rationale: <why this width — precision needed vs. resource cost>
  Verified against: <golden reference / tolerance>
  ```

- Every module that gets synthesized (Phase 4 onward) gets a resource + timing report
  saved to `docs/reports/<module_or_phase>_<date>.txt` (or Vivado's native report
  format) — generate via TCL in non-project batch mode, not by hand from the GUI, so
  it's reproducible.

## Hardware-in-the-loop checkpoints

Some PLAN.md acceptance criteria require the physical Cora Z7-07S (Phases 4, 5, 7, 9)
or a Vivado license/install (any synthesis step). If your environment doesn't have
these:
- Implement and verify everything possible in simulation first (this is most of the
  work in Phases 3, 5's core logic, and all of Phases 1, 2, 6, 8's software).
- Flag the specific on-hardware step as blocked and stop at that checkpoint rather than
  marking the phase's acceptance criteria met without it — "simulation passes" is not
  the same as "runs on hardware" per PLAN.md's own criteria, and the project's whole
  point is the hardware step being real.

## Spec changes

If implementation reveals that ARCHITECTURE.md's proposed data formats (pulse-sequence
schema, AXI register map, fixed-point widths) need to change: propose the change via PR
to ARCHITECTURE.md, get it merged, then implement against the merged version. Don't let
implementation silently diverge from the documented interface.
