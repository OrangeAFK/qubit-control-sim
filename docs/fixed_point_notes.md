# Fixed-point design notes

Running ledger of numeric-format decisions. Add one entry per HDL module **before**
writing its RTL (see AGENTS.md). Format:

## <module name>
Format: Q<int_bits>.<frac_bits>, signed/unsigned
Range: <min> to <max>
Rationale: <why this width>
Verified against: <golden reference / tolerance>

---

Convention used below: **signed Qm.n** means two's-complement with **m integer bits
(including the sign bit)** and **n fractional bits**, total width `m + n`. Example:
Q1.14 is 16 bits with range approximately `[-2, 2)`.

Phase 3 readout-chain context (from checked-in Phase 2 fixtures
`python/cryocontrol/dsp_ref/fixtures/{noiseless,noisy}.npz`):

| Quantity | Observed (float golden) |
|---|---|
| IF / post-DDC \|IQ\| peak | ≤ ~1.00 (\|1⟩), ≤ ~0.32 (noisy) |
| Post-FIR \|IQ\| peak | ≤ ~1.06 (unity-DC FIR transient) |
| Integrate window | 1016 decimated samples (`start=8`, through end) |
| Integrated Re(IQ) | ~203 (\|0⟩), ~1013 (\|1⟩); threshold ~608 |
| State separation \|ΔIQ\| | ~811 |

Chain sample rate in fixtures: `fs = 100e6`, `f_lo = 10e6`, FIR 63 taps / 5 MHz
cutoff, decimation `M = 4`. Decimation is **not** a separate RTL module in Phase 3;
it is part of the FIR stage (keep-every-Mth after the LPF).

**Chain-wide HDL-vs-fixture tolerance (top-level compare):** integrated I and Q each
within absolute error **≤ 1.0** (≪ ~405 margin to threshold); state decision must
**match** the fixture bit-exact for both noiseless and noisy cases.

---

## ddc

Format: Q1.14, signed (I and Q sample ports; NCO cos/sin also Q1.14)
Range: sample I/Q ≈ [-2, 2); NCO cos/sin ≈ [-1, 1]
Rationale: Phase 2 IF amplitudes live in ~[0, 1] with FIR headroom to ~1.06, so one
integer magnitude bit (Q1.14) gives ~6e-5 LSB resolution and avoids saturating the
post-mix baseband. Complex multiply `x * exp(-jθ)` uses a 32-bit phase accumulator
(tuning word from AXI in Phase 4; for Phase 3 sim, set from fixture `f_lo`/`fs`/
`phase0`) and a LUT (or CORDIC) emitting Q1.14 cos/sin. Full product is Q2.28 before
round-to-nearest / saturate back to Q1.14 — unit-magnitude NCO preserves amplitude to
within one LSB. 16-bit ports map cleanly onto AXI-Stream and DSP48 18×25 multipliers
on the XC7Z007S.
Verified against: `dsp_ref/fixtures/noiseless.npz` + `noisy.npz` baseband magnitude
(post-DDC float \|IQ\| ≤ ~1.0); intermediate compare optional. End-to-end tolerance
owned by top-level (≤ 1.0 on integrated I/Q; decision exact).

Phase-3 sim ports (module TB / future AXI-Stream wrapper):
`clk`, `rst_n` (active-low); `in_valid`; `in_i`/`in_q` signed 16-bit Q1.14;
`phase_inc`/`phase0` unsigned 32-bit (`phase_inc = round(f_lo/fs·2³²)`,
`phase0_word = round(phase0_rad/(2π)·2³²)` from fixture); `out_valid`;
`out_i`/`out_q` signed 16-bit Q1.14. One complex sample per clock when `in_valid`.
Per-sample module-TB compare (vs quantized `dsp_ref.ddc` of fixture IF): absolute
error ≤ **4 LSB** on I and on Q after the DUT pipeline latency / first `out_valid`.

---

## fir

Format: data path Q1.14 signed in/out; coefficients Q1.14 signed; internal MAC wider
Range: I/Q samples ≈ [-2, 2); coeffs ≈ [-0.02, 0.10] (fixture `fir_coeffs`, sum = 1)
Rationale: Same Q1.14 sample format as DDC so the chain does not requantize between
stages. Fixture FIR is unity-DC (`sum(h)=1`, `max|h|≈0.100`); Q1.14 resolves the
largest tap to ~1636 LSBs. Each tap product is Q1.14×Q1.14 → Q2.28; a 63-tap
accumulator needs ~6 extra integer bits for worst-case `sum|h|·|x|` (~1.32·|x|) —
use a signed **Q8.28** (or equivalent ≥36-bit) MAC, then round/saturate to Q1.14
output. Decimation **M = 4** (fixture `decim_factor`) is implemented at this stage
by emitting every M-th filtered sample (no format change). Coeffs are compile-time /
AXI-loadable copies of quantized `fir_coeffs` from the golden fixture.
Verified against: fixture post-FIR/decimated streams within a few LSBs; end-to-end
tolerance owned by top-level.

Phase-3 sim ports (module TB / future AXI-Stream wrapper):
`clk`, `rst_n` (active-low); `in_valid`; `in_i`/`in_q` signed 16-bit Q1.14
(post-DDC baseband at `fs`); parameters `NUM_TAPS` / `DECIM_M` (fixture 63 / 4);
`out_valid`; `out_i`/`out_q` signed 16-bit Q1.14 at `fs/M`. Coeff ROM =
quantized fixture `fir_coeffs` (Q1.14). One complex input sample per clock when
`in_valid`; DUT emits every `DECIM_M`-th filtered sample (`out_valid`).
Per-sample module-TB compare (vs quantized `decimate(apply_fir(dsp_ref.ddc(IF)))`):
absolute error ≤ **8 LSB** on I and on Q after the DUT pipeline latency / first
`out_valid`.

---

## integration

Format: input Q1.14 signed; accumulator / output **Q12.14** signed (26-bit value,
sign-extended in a 32-bit container for later AXI-Lite)
Range: input ≈ [-2, 2); output ≈ [-2048, 2048)
Rationale: Float golden integrates ~1016 Q≈1 samples → peak Re ≈ 1013, so ≥11
magnitude bits past the binary point alignment of Q1.14 are required. Q12.14
(sign + 11 magnitude integer bits + 14 fraction) covers ±2048 with ~2× headroom
above the \|1⟩ integral and matches the sample fractional grid (no rescale). Window
parameters `integrate_start` / `integrate_length` match the fixture (`start=8`,
length through end). Complex sum is two independent accumulators (I and Q).
Verified against: `output_iq_s0` / `output_iq_s1` / `output_iq` in the Phase 2
fixtures within abs error ≤ 1.0 on Re and Im.

---

## state_discrim

Format: IQ input and threshold **Q12.14** signed; decision **1-bit** unsigned
Range: threshold / Re(IQ) ≈ [-2048, 2048); decision ∈ {0, 1}
Rationale: Implements Phase 2 rule `Re(iq) >= threshold → 1 else 0` with the
threshold in the same Q12.14 format as the integrator output (fixture threshold ≈
608.083 → nearest Q12.14 code). A single signed compare needs no extra fractional
width; 1-bit state is enough until Phase 8 replaces this with a calibrated
classifier. Keeping threshold co-format with the integrator avoids a second
quantize step that could flip decisions near the boundary (fixture margin ~405).
Verified against: `decision_s0` / `decision_s1` / `decision` in the Phase 2
fixtures — must match exactly for noiseless and noisy cases.

---

## readout_chain (top-level)

Format: AXI-Stream (sim) IQ samples **Q1.14** signed I/Q → integrated IQ **Q12.14**
signed + **1-bit** decision (same as modules above)
Range: as per stage entries; fixture streams are float complex in ~[-1, 1] and must
be quantized to Q1.14 on stimulus ingress
Rationale: Documents the Phase 3 end-to-end seam against
`python/cryocontrol/dsp_ref/fixtures/`. Stimulus = fixture `input_iq_*` quantized to
Q1.14; expected = fixture `output_iq_*` / `decision_*` with the chain-wide tolerance
above. No additional arithmetic beyond stitching `ddc → fir(+decim) → integration →
state_discrim`. Phase 4 may wrap the same formats on AXI-Lite/Stream without
changing Q-formats.
Verified against: both `noiseless.npz` and `noisy.npz`; integrated I/Q abs error
≤ 1.0; decisions bit-exact.
