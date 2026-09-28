# Readout-chain testbench (Phase 3 top-level)

Stimulus and expected vectors are **derived from checked-in Phase 2 fixtures**
(`python/cryocontrol/dsp_ref/fixtures/{noiseless,noisy}.npz`) — not invented in
the TB.

## Layout

| path | role |
|------|------|
| `tb_readout_chain.sv` | Top-level chain TB (reset, 100 MHz clk, IF stimulus, IQ+decision compare) |
| `export_fixtures.py` | NPZ → Q1.14 in / Q12.14 exp IQ / 1-bit exp decision + `vectors/readout_chain_params.svh` |
| `vectors/` | Generated mem files + params (regenerate via export script) |
| `../../rtl/readout_chain/readout_chain.v` | Empty shell for elaborate only — **not** the DUT |

## Regenerate vectors

From repo root (with `cryocontrol` importable)::

```bash
python hdl/tb/readout_chain/export_fixtures.py
```

| vector | derivation |
|--------|------------|
| `*_in_{i,q}.mem` | `quantize_Q1.14(fixture input_iq_*)` |
| `*_exp_{i,q}.mem` | `quantize_Q12.14(fixture output_iq_*)` |
| `*_exp_decision.mem` | fixture `decision_*` / `decision` (0 or 1) |
| `RC_PHASE_INC` / `RC_PHASE0` | from fixture `fs`, `f_lo`, `phase0` |
| `RC_THRESHOLD_Q` | `quantize_Q12.14(fixture threshold)` |
| `RC_NUM_TAPS` / `RC_DECIM_M` / integrate window | from fixture metadata |

Tolerance (`docs/fixed_point_notes.md` § readout_chain):

- Integrated I/Q: abs error **≤ 1.0** → `RC_TOL_LSB = 16384`
- Decision: **bit-exact**

Cases: `noiseless_s0`, `noiseless_s1`, `noisy` (4096 IF samples → one IQ + decision each).

## Run simulation (xsim)

Source Vivado settings, then from repo root::

```bash
# Windows example:
#   call C:\Xilinx\2025.1\Vivado\settings64.bat
vivado -mode batch -source hdl/vivado/sim_readout_chain.tcl
```

With the empty shell: expect TIMEOUT / FAIL (no `out_valid`) — that is the
correct pre-DUT outcome. With real structural `readout_chain` RTL: expect
`=== tb_readout_chain: ALL CASES PASSED ===`.

Note: xsim 2025.1 corrupts `localparam string` arrays from
`readout_chain_params.svh`; `tb_readout_chain.sv` resolves case names via
`case_name()` instead of `RC_CASE_NAMES`.

## STOP — TB review before DUT

Do not replace `hdl/rtl/readout_chain/readout_chain.v` with structural wiring of
`ddc` / `fir` / `integration` / `state_discrim` until this testbench (reset,
clock, stimulus, compare window, fixture wiring) has been human-reviewed.
