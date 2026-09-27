# ARCHITECTURE.md

System design reference for CryoControl. This is the technical source of truth — `PLAN.md`
sequences the work, but interface contracts and module responsibilities are defined here.
When PLAN.md and this file conflict, fix ARCHITECTURE.md first via PR, then update PLAN.md.

## 1. Objective

Emulate the control and readout stack of a superconducting quantum computer, end to end:

```
Python experiment → pulse generation → FPGA DSP/control → simulated RF/cryogenic chain
→ simulated qubit/resonator → simulated ADC → FPGA readout DSP → IQ/state discrimination
→ Python results
```

Design constraint: the simulated RF/cryogenic block must be swappable for physical
hardware later **without changing the control architecture** — i.e. the FPGA's interface
to "the outside world" must be defined the same way whether that world is a software model
feeding synthetic samples or a real ADC/DAC.

## 2. Target hardware

- **Digilent Cora Z7-07S** (Zynq-7000: ARM Cortex-A9 PS + FPGA PL)
- Development PC running Python and Vivado

No dilution refrigerator, qubit, VNA, spectrum analyzer, signal generator, or RF hardware
in the initial build. The FPGA processes **realistic synthetic ADC/sample streams** so the
digital control/readout path is genuinely implemented in hardware, not simulated in software
and merely labeled "FPGA."

## 3. Layer responsibilities and interfaces

### 3.1 Experiment/control layer (Python, PS or host)

Responsibilities: instrument/device abstraction, experiment definition, parameter sweeps,
pulse-sequence specification, FPGA configuration, acquisition, calibration, metadata/logging,
visualization. Take architectural inspiration from **QCoDeS** (Instrument/Parameter/Sweep
abstractions) rather than building a bespoke framework from scratch.

Example experiments this layer must support: resonator spectroscopy, qubit readout, Rabi
oscillation, (stretch) Ramsey.

**Interface out:** a pulse-sequence description (see 3.2) sent to the FPGA config layer, and
sweep parameters sent to the model/hardware layer being driven.
**Interface in:** IQ points / state-discrimination results + metadata, for plotting and
calibration feedback.

### 3.2 Pulse-generation/control layer

Converts a high-level experiment spec into digital control parameters: frequency, amplitude,
phase, pulse duration, envelope, sequence timing.

**Data format contract:** define a pulse-sequence schema once, used identically by the Python
side (to generate it) and the FPGA side (to consume it). Suggested starting point — a flat
list of instruction words, e.g.:

| field | width | meaning |
|---|---|---|
| opcode | 4b | SET_FREQ / SET_AMP / SET_PHASE / PLAY / WAIT / etc. |
| channel | 4b | which NCO/output channel |
| value | 24b | fixed-point parameter value |
| duration | 32b | cycles (for WAIT/PLAY) |

Treat this table as a starting proposal, not a fixed spec — finalize the actual opcode list
and widths in Phase 5 and record the final version in `docs/fixed_point_notes.md`, since it
depends on the NCO/DDS bit widths chosen there.

FPGA target: an NCO/DDS or equivalent digital waveform-generation block (Phase 5).

### 3.3 FPGA DSP/control layer (synthesizable HDL, Vivado)

**Control path:** waveform/control input → NCO/DDS → digital pulse generation.

**Readout path:** synthetic ADC IQ samples → digital downconversion (DDC) → FIR/low-pass
filter → decimation → integration/accumulation → I/Q result → state discrimination.

Requirements:
- Fixed-point arithmetic throughout; every module's Q-format, range, and precision
  rationale documented in `docs/fixed_point_notes.md` (see AGENTS.md for the required
  format).
- Meaningful AXI interfaces: AXI-Lite for PS↔PL configuration/status registers, AXI-Stream
  for sample data into/out of the DSP chain.
- Every module ships with a synthesis/resource/timing report (Vivado, non-project TCL flow)
  checked into `docs/reports/`.

### 3.4 RF/cryogenic-chain simulation (Python software model)

Models the physical chain: DAC → IQ/RF generation → attenuation → superconducting device →
amplification → downconversion → ADC. Model *effects*, not electromagnetics:

- gain/loss, attenuation
- amplifier noise (noise figure / noise temperature)
- bandwidth/filtering, frequency response
- I/Q imbalance
- ADC quantization
- frequency drift
- measurement noise

**Interface contract:** this model's output is a time-domain IQ sample stream in the same
format the FPGA readout chain (3.3) expects as input — same sample rate, same fixed-point
width/scaling. This is the seam where real hardware will eventually replace software: don't
let any other layer depend on this model being software.

### 3.5 Superconducting-device model (Python)

One qubit, one readout resonator:
- resonator response S21(f) — a complex Lorentzian is sufficient, not a full QED/Maxwell sim
- qubit-state-dependent resonator frequency
- microwave drive/readout
- relaxation/dephasing/noise as appropriate

Purpose: produce physically meaningful signals for 3.4, not to be a physics research tool.
Keep the model tractable and well-tested; correctness of the *control/readout electronics*
is the point of this project, not fidelity of the qubit model.

### 3.6 Cryogenic environment model (Python)

Abstract engineering model, not a thermodynamic simulation. Stages: 300 K → 4 K → sub-Kelvin
→ ~10-20 mK device. Each stage carries: temperature, attenuation, amplifier noise
temperature, cable loss, contribution to device frequency drift/noise.

Must support **controlled fault injection**: amplifier gain drift, increased noise,
qubit/resonator frequency drift, I/Q imbalance, ADC saturation — each toggleable
independently, for the Phase 9 fault-injection/recalibration demo.

### 3.7 Calibration (Python, drives FPGA + models)

Progression, simple → sophisticated:
1. resonator-frequency identification
2. amplitude/frequency calibration
3. IQ offset correction
4. IQ gain/phase imbalance correction
5. readout calibration using simulated |0> and |1> distributions
6. state-discrimination threshold/classifier

Report readout fidelity and classification error as first-class output metrics, not
debug prints — the fault-injection demo (Phase 9) depends on these being comparable
before/after recalibration.

### 3.8 Closed-loop experiment demos

**Demo A (Rabi):** Python Rabi experiment → pulse parameters → FPGA waveform generation →
simulated qubit response → simulated ADC → FPGA DDC/filter/integration → IQ points → state
discrimination → Python plots Rabi oscillations.

**Demo B (fault + recovery):** inject a hardware/environment fault (amplifier gain drift or
resonator-frequency drift) → show readout degradation → run automated recalibration →
demonstrate recovery, with fidelity/error numbers before and after.

## 4. Success criterion

Credible to a quantum-hardware/FPGA engineer as a miniature but technically authentic
control-and-readout stack — not merely a Python quantum simulator, and not an isolated FPGA
DSP exercise disconnected from device physics. The test question:

> Can we take a high-level superconducting-qubit experiment, generate the corresponding
> digital control/readout signals, process them through real FPGA hardware, simulate the
> cryogenic/RF/device physics realistically enough to produce meaningful measurement data,
> and recover the qubit state/experiment result automatically?

## 5. Deliverables checklist

- [ ] Clean GitHub repository
- [ ] System architecture diagram (this doc's §3 as a figure — see `docs/`)
- [ ] Python simulation/model (3.4, 3.5, 3.6)
- [ ] Synthesizable FPGA HDL (3.3)
- [ ] HDL testbenches + automated verification
- [ ] Vivado project/build scripts (non-project TCL flow)
- [ ] Fixed-point design documentation
- [ ] Cora Z7 hardware demo (bitstream running on real board)
- [ ] Experiment/control API (3.1)
- [ ] Calibration routines (3.7)
- [ ] Plots: resonator spectroscopy, readout, Rabi
- [ ] Resource utilization + timing reports
- [ ] Latency/throughput measurements
- [ ] Fault-injection demonstration (3.8 Demo B)
- [ ] Concise technical report: design decisions + limitations
- [ ] Short demo video of the complete pipeline
