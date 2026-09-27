# dsp_ref

Golden-reference software DSP (DDC/FIR/decimate/integrate/threshold), numpy. Phase 2.
HDL in `hdl/rtl/` is verified against this.

## Pipeline stages

- `ddc` — digital downconversion (software NCO mixer)
- `design_fir_lowpass` / `apply_fir` — windowed-sinc low-pass FIR (unity DC gain)
- `decimate` — keep-every-Mth sample (filter separately)
- `integrate` — complex sum over an accumulation window
- `discriminate` — simple Re(iq) threshold classifier (refined in Phase 8)
- `run_readout` / `synthesize_if_tone` — end-to-end chain + Phase-1 IF synthesis

## Golden I/O (HDL reference)

Checked-in vectors under [`fixtures/`](fixtures/):

| file | contents |
|------|----------|
| `fixtures/noiseless.npz` | IF IQ for \|0⟩ and \|1⟩ + integrated IQ + decisions |
| `fixtures/noisy.npz` | one AWGN IF stream + integrated IQ + decision |

Contract (keys, dtypes, regenerate command): see `fixtures/__init__.py` docstring.
Load with `cryocontrol.dsp_ref.fixtures.load_fixture`. Phase 3 testbenches replay
these files — do not substitute prose descriptions of expected behavior.
