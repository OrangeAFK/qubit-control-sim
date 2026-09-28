# Phase 4 on-hardware readout test (procedure + blockers)

**Status: BLOCKED — Phase 4 acceptance criteria are not met.**

This document is prep only. No Cora Z7-07S bitstream has been programmed, and no
on-hardware RESULT_* comparison has been run. Do not treat OOC synth+impl reports
under `docs/reports/phase4_readout_2026-09-27*` as board bring-up success.

## Blockers (explicit)

1. **No PS + DMA block design / programmable bitstream.** Current flow
   (`hdl/vivado/synth_cora_readout.tcl`) is **out-of-context (OOC)** PL-only
   synth+impl of `cora_readout_pl`. That produces a routed DCP and reports, not a
   `.bit` you can load onto the Cora with ARM Linux / PYNQ / bare-metal.
2. **Need a Zynq PS BD** that maps AXI-Lite to the frozen readout aperture
   (`BASE_ADDR_TENTATIVE` in `axi_lite_regs.py` / ARCHITECTURE.md §3.3.1) and an
   AXIS MM2S (or equivalent) path to feed IF samples from Phase 2/3 fixtures.
3. **Timing does not meet 100 MHz today.** After multi-cycle FIR + DDC
   pipelining, routed WNS ≈ **−5.6 ns** (was −16.9 ns), DSP48E1 **40/66
   (61%)**. Critical path is the FIR snapshot mux → DSP → accumulate under
   congestion; full serial MAC (16 engines) / shifting-snapshot variants
   over-utilized LUTs on xc7z007s. See
   `docs/reports/phase4_readout_2026-09-27_pipelined*`.
4. **`MmioBackend` / DMA push are stubs.** `ReadoutDriver` works end-to-end under
   `MockBackend` in pytest; board MMIO + DMA wiring is still future work.

## Intended procedure (once a PS+DMA bitstream exists)

Record results under `docs/reports/` (date-stamped). Do **not** mark PLAN
acceptance boxes until every step below passes on the physical board.

### 0. Prerequisites

- Bitstream with PS + AXI-Lite + AXIS DMA (or documented equivalent) wrapping
  `cora_readout_pl` (or successor top).
- Timing closed at the chosen PL clock (or an explicitly documented lower clock
  with measured latency scaled accordingly).
- Python env with `cryocontrol` installed; board-side access to mapped Lite + DMA.

### 1. Load bitstream

Program the Cora Z7-07S with the PS+PL bitstream (Vivado Hardware Manager, `fpgautil`,
or the board image’s usual path). Boot Linux/PYNQ if that is the host for the driver.
Confirm the Lite base address matches the Address Editor (update
`BASE_ADDR_TENTATIVE` / `MmioBackend` if reassigned).

### 2. Identity + configure via `ReadoutDriver`

```text
ReadoutDriver(MmioBackend(...)).check_identity()  # MAGIC / VERSION
configure(ReadoutConfig())  # fixture defaults: PHASE_INC, PHASE0, THRESHOLD, integrate window
```

Defaults must match Phase 2/3 fixture parameters (`FIXTURE_*` in `axi_lite_regs.py`).

### 3. Push Phase 2/3 fixture vectors

Load `python/cryocontrol/dsp_ref/fixtures/noiseless.npz` (and `noisy.npz`):

- Quantize IF `input_iq_*` to signed Q1.14 (`packing.float_to_q1_14`).
- Pack `{Q,I}` AXIS words (`pack_iq_words` / `pack_iq_bytes` for DMA).
- `arm()` then push samples (DMA MM2S or future `push_axis_words` on a real backend).

Run at least: noiseless `|0⟩` and `|1⟩`, plus one noisy case.

### 4. Wait for DONE; read RESULT_*

Poll `STATUS.DONE`, then read `RESULT_I`, `RESULT_Q`, `RESULT_META`,
`IF_SAMPLE_COUNT`.

### 5. Compare to Phase 3 / fixture golden (tolerance)

From `docs/fixed_point_notes.md` (chain-wide):

- Integrated I and Q: absolute error **≤ 1.0** vs fixture `output_iq_*`
  (fixture floats; convert RESULT_* Q12.14 → float with scale `2**14`).
- Decision bit in `RESULT_META`: **exact** match to fixture `decision_*`.

Also cross-check against Phase 3 HDL sim results for the same vectors if those
logs/reports are checked in for the case under test.

### 6. Record latency

Measure samples-in → decision-out (PL cycle count and/or wall time from ARM start
of push to `DONE`). Write the number into `docs/reports/` next to the bring-up
log. PLAN acceptance requires this recorded.

### 7. What “pass” means for PLAN.md

Only then check:

- On-hardware task
- Acceptance: bitstream on Cora; output within tolerance; reports checked in;
  latency recorded

Until then leave those boxes **unchecked**.

## Software dry-run (no board)

`python scripts/phase4_readout_dry_run.py` exercises configure → push → compare
against fixtures using `MockBackend` (injects quantized golden results; does **not**
run HDL or the Cora). Exit 0 means the **driver/compare path** is consistent with
fixtures — not that hardware ran.

## Related artifacts

| Artifact | Meaning |
| -------- | ------- |
| `docs/reports/phase4_readout_2026-09-27*` | Real OOC util/timing — **not** on-HW |
| `hdl/vivado/synth_cora_readout.tcl` | OOC PL synth+impl |
| `python/cryocontrol/hardware/` | Driver + mock/MMIO stub |
| `python/cryocontrol/dsp_ref/fixtures/` | Golden IF + integrated IQ + decisions |
