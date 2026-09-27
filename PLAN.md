# PLAN.md

Execution plan. Work phases **in order** — each depends on the previous one's interfaces
being real and tested, not stubbed. Do not start a phase's HDL work until its Python
reference model (where one exists) passes its own tests; the software model is the golden
reference the HDL is verified against.

Each phase lists: goal, deliverables, acceptance criteria (must be objectively checkable —
"looks right" is not acceptance criteria), and suggested atomic tasks. Agents: check off
tasks as completed, and do not mark a phase done until its acceptance criteria are met and
demonstrated (test output, plot, or report checked into the repo).

---

## Phase 1 — Software-only resonator + IQ signal simulation

**Goal:** `python/cryocontrol/models/` produces physically-plausible synthetic IQ data with
no FPGA involved yet.

**Tasks**
- [X] Lorentzian resonator model: S21(f) given center frequency, Q, coupling
- [X] Two-state resonator (qubit-state-dependent frequency shift)
- [X] Noise model: additive Gaussian + configurable amplifier noise temperature
- [X] Cryo-chain gain/loss/attenuation model (§3.4/3.6 of ARCHITECTURE.md), stages
      parameterized (not hardcoded), each stage independently toggleable for fault injection
- [X] Unit tests: resonance dip appears at expected frequency; SNR scales as expected with
      noise parameters; each fault mode independently changes output in the expected direction

**Acceptance criteria**
- [X] `pytest python/tests/models/` passes
- [X] A plot of |S21(f)| for both qubit states, saved to `docs/`, shows two distinguishable
      resonance dips
- [X] Fault injection (e.g. gain drift) visibly and correctly perturbs the output in a
      before/after plot

---

## Phase 2 — Software DDC/readout pipeline (golden reference)

**Goal:** `python/cryocontrol/dsp_ref/` implements DDC → FIR → decimate → integrate →
threshold in numpy/scipy, as the reference the HDL must match bit-for-bit-equivalent
(within documented fixed-point tolerance) in Phase 3.

**Tasks**
- [X] Digital downconversion (mixing with reference NCO in software)
- [X] FIR low-pass design + implementation
- [X] Decimation
- [X] Integration/accumulation window
- [X] Threshold-based state discrimination (simple, refined in Phase 8)
- [X] Feed Phase 1 output through this pipeline end-to-end; recover state with reasonable
      fidelity on noiseless input
- [X] Export golden I/O vectors (noiseless + one noisy case) as checked-in fixture files
      under `python/cryocontrol/dsp_ref/fixtures/` (or equivalent path documented in the
      module README) for Phase 3 HDL testbenches to replay bit-exact / within tolerance

**Acceptance criteria**
- [X] `pytest python/tests/dsp_ref/` passes
- [X] Given Phase 1's noiseless two-state output, this pipeline discriminates states
      correctly close to 100% of the time
- [X] This pipeline's I/O (input IQ stream, output I/Q + decision) is documented as the
      reference the HDL testbenches will replay against
- [X] Golden fixture files are checked in and loadable by tests (not described only in prose)

---

## Phase 3 — DDC/FIR/integration in FPGA simulation (not yet on hardware)

**Goal:** `hdl/rtl/{ddc,fir,integration,state_discrim}/` implemented in synthesizable HDL,
verified in simulation against Phase 2's golden reference — no board yet.

**Tasks**
- [ ] Fix the numeric format (Q-format) for this chain; write the decision + rationale
      to `docs/fixed_point_notes.md` before writing RTL
- [ ] DDC module + testbench
- [ ] FIR module + testbench
- [ ] Integration/accumulation module + testbench
- [ ] Threshold/state-discrimination module + testbench
- [ ] Top-level readout-chain testbench: feed Phase 2's checked-in fixture vectors in
      (not a regenerated-from-description proxy), compare HDL output to golden reference
      within documented fixed-point tolerance

**Acceptance criteria**
- [ ] Every module has a passing testbench (simulator: see AGENTS.md); each TB was
      human-reviewed before its DUT was written
- [ ] Top-level chain simulation output matches the Phase 2 golden **fixture files**
      within the documented tolerance, for at least the noiseless case and one noisy case
- [ ] `docs/fixed_point_notes.md` has an entry for every module in this phase

---

## Phase 4 — Readout DSP running on the Cora Z7-07S

**Goal:** Phase 3's HDL is running on real fabric, driven by synthetic ADC streams
(injected via testbench-style stimulus over AXI-Stream, or PS-side DMA — pick one and
document it), with results read back over AXI-Lite.

**Tasks**
- [ ] AXI-Lite config/status register map (frozen here; document in ARCHITECTURE.md)
- [ ] AXI-Stream ingestion of synthetic ADC samples (from Phase 1/2's generated test vectors,
      loaded via PS)
- [ ] `python/cryocontrol/hardware/` driver: push samples, configure, read back results
- [ ] Vivado synthesis + implementation, non-project TCL flow, resource/timing report to
      `docs/reports/`
- [ ] On-hardware test: known synthetic input in → expected I/Q/decision out

**Acceptance criteria**
- [ ] Bitstream builds and runs on physical Cora Z7-07S
- [ ] On-hardware output matches Phase 3 simulation output within documented tolerance
- [ ] Resource utilization + timing report checked into `docs/reports/`
- [ ] Latency (samples in → decision out) measured and recorded

---

## Phase 5 — FPGA waveform generation (NCO/DDS)

**Goal:** `hdl/rtl/nco_dds/` generates control waveforms on-chip from parameters written
over AXI-Lite.

**Tasks**
- [ ] NCO/DDS core (phase accumulator + lookup table or CORDIC) + testbench
- [ ] Envelope shaping (at least a simple windowed pulse)
- [ ] Pulse-sequence instruction format finalized (§3.2 of ARCHITECTURE.md) and documented
- [ ] Sequencer: consumes instruction stream, drives NCO/DDS + timing
- [ ] On-hardware test: generate a known waveform, capture it (loop back into the readout
      chain from Phase 4), verify frequency/amplitude/phase match commanded values

**Acceptance criteria**
- [ ] Generated waveform verified on hardware (loopback through Phase 4's chain, or captured
      and checked in software) matches commanded frequency/amplitude/phase within tolerance
- [ ] `docs/fixed_point_notes.md` updated for this module

---

## Phase 6 — Python experiment orchestration

**Goal:** `python/cryocontrol/experiment/` provides QCoDeS-style instrument/parameter/sweep
abstractions over the Phase 4+5 hardware driver.

**Tasks**
- [ ] Instrument abstraction wrapping the hardware driver from Phase 4
- [ ] Parameter sweep support
- [ ] Pulse-sequence builder → instruction stream (using Phase 5's finalized format)
- [ ] Metadata/logging (what ran, when, with what parameters)
- [ ] Basic visualization (plot IQ points, plot swept results)
- [ ] Implement resonator-spectroscopy experiment end-to-end using this layer

**Acceptance criteria**
- [ ] A resonator-spectroscopy sweep run through this API, on real hardware, produces a
      plot showing the resonance dip
- [ ] Experiment code contains no direct register pokes — everything goes through the
      Instrument/Parameter abstraction

---

## Phase 7 — Superconducting-qubit / Rabi model integrated end-to-end

**Goal:** Demo A from ARCHITECTURE.md §3.8 — full closed loop, Rabi oscillation.

**Tasks**
- [ ] Extend Phase 1's model with qubit drive response (Rabi oscillation vs. drive
      amplitude/duration)
- [ ] Rabi experiment implemented via Phase 6's orchestration layer
- [ ] Full pipeline run: Python → FPGA control → simulated qubit → simulated ADC → FPGA
      readout → Python plot

**Acceptance criteria**
- [ ] End-to-end run on real hardware produces a Rabi oscillation plot with the expected
      sinusoidal population-vs-drive-amplitude shape

---

## Phase 8 — Calibration

**Goal:** `python/cryocontrol/calibration/` automates the calibration progression in
ARCHITECTURE.md §3.7, replacing Phase 2/3's simple fixed threshold.

**Tasks**
- [ ] Resonator-frequency identification routine
- [ ] Amplitude/frequency calibration
- [ ] IQ offset correction
- [ ] IQ gain/phase imbalance correction
- [ ] Readout calibration from simulated |0>/|1> distributions
- [ ] State-discrimination classifier (replacing fixed threshold)
- [ ] Fidelity + classification-error reporting as structured output (not prints)

**Acceptance criteria**
- [ ] Running calibration end-to-end on a freshly-randomized (uncalibrated) model state
      converges to a documented fidelity threshold (pick and record a target, e.g. >95%
      simulated readout fidelity)
- [ ] Fidelity/error numbers are logged and plottable across calibration runs

---

## Phase 9 — Fault injection + recalibration (Demo B)

**Goal:** ARCHITECTURE.md §3.8 Demo B — inject a fault, show degradation, recalibrate,
show recovery.

**Tasks**
- [ ] Wire Phase 1/6's fault-injection hooks (amplifier gain drift, resonator-frequency
      drift, at minimum) into a runnable experiment
- [ ] Script: baseline fidelity → inject fault → measure degraded fidelity → run Phase 8
      calibration → measure recovered fidelity
- [ ] Plot/report showing all three fidelity numbers

**Acceptance criteria**
- [ ] Fault visibly degrades measured fidelity
- [ ] Recalibration measurably recovers fidelity, with before/degraded/after numbers in
      one report

---

## Phase 10 — End-to-end demonstration + benchmark + writeup

**Goal:** package the project as a credible portfolio artifact.

**Tasks**
- [ ] Architecture diagram (render ARCHITECTURE.md §3 as a figure)
- [ ] Latency/throughput measurements compiled into one summary table
- [ ] Technical report: design decisions, fixed-point tradeoffs, what was cut/deferred,
      known limitations, what "hardware-in-the-loop ready" means for this specific design
- [ ] Short demo video: Rabi run (Phase 7) + fault/recovery run (Phase 9)
- [ ] Repo cleanup pass: README accurate, all reports present in `docs/reports/`

**Acceptance criteria**
- [ ] Everything in ARCHITECTURE.md §5's deliverables checklist is checked off
- [ ] A reader with no prior context can go from README.md to a working understanding of
      the system and its limitations without reading source code
