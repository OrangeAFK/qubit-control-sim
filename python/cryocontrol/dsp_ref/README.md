# dsp_ref

Golden-reference software DSP (DDC/FIR/decimate/integrate/threshold), numpy. Phase 2. HDL in hdl/rtl/ is verified against this.

- `ddc` — digital downconversion (software NCO mixer)
- `design_fir_lowpass` / `apply_fir` — windowed-sinc low-pass FIR (unity DC gain)
- `decimate` — keep-every-Mth sample (filter separately)
- `integrate` — complex sum over an accumulation window
- `discriminate` — simple Re(iq) threshold classifier (refined in Phase 8)
