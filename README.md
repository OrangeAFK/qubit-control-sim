# CryoControl

A miniature but technically authentic superconducting-qubit **control and readout stack**:
Python experiment orchestration → FPGA DSP/control (Digilent Cora Z7-07S) → simulated
RF/cryogenic/device physics → FPGA readout DSP → state discrimination → Python results.

No dilution fridge, qubit, VNA, or RF hardware required. The digital control/readout path
runs on real FPGA fabric against physically-modeled synthetic signals; the RF/cryo/device
chain is a software model designed to be swapped for real hardware later without changing
the control architecture.

## Read these in order

1. **`ARCHITECTURE.md`** — system design reference: layers, module responsibilities,
   data formats and interface contracts between them. The technical source of truth.
2. **`PLAN.md`** — phased build plan, in dependency order, with acceptance criteria per
   phase. The execution source of truth — work top to bottom, don't skip ahead.
3. **`AGENTS.md`** — conventions and workflow for AI coding agents working in this repo.

## Repo layout

```
cryocontrol/
├── ARCHITECTURE.md          # system design reference
├── PLAN.md                  # phased build plan + acceptance criteria
├── AGENTS.md                # agent conventions & workflow
├── python/
│   └── cryocontrol/
│       ├── models/          # resonator, qubit, cryo-chain, noise models (Phase 1, 4, 5)
│       ├── dsp_ref/         # golden-reference software DSP: DDC/FIR/NCO in numpy (Phase 2)
│       ├── experiment/      # QCoDeS-style orchestration, pulse sequencing (Phase 6)
│       ├── calibration/     # calibration routines (Phase 8)
│       └── hardware/        # PS↔PL driver layer talking to the Cora Z7 (Phase 4, 5)
│   └── tests/                # pytest, mirrors package structure
├── hdl/
│   ├── rtl/
│   │   ├── nco_dds/          # Phase 5
│   │   ├── ddc/              # Phase 3
│   │   ├── fir/              # Phase 3
│   │   ├── integration/      # Phase 3 (integrate/accumulate + threshold)
│   │   ├── state_discrim/    # Phase 3/8
│   │   └── axi_interface/    # AXI-Lite config regs + AXI-Stream data path
│   ├── tb/                   # per-module testbenches (Verilog/SystemVerilog)
│   ├── constraints/          # Cora Z7-07S XDC files
│   └── vivado/               # non-project-mode TCL build scripts
├── docs/
│   ├── fixed_point_notes.md  # running ledger of Q-format decisions per module
│   └── reports/              # synthesis/timing/resource reports land here
└── scripts/
    └── run_experiment.py     # CLI entry point once Phase 6 exists
```

Each subdirectory has a short `README.md` stating what belongs there and which PLAN.md
phase populates it — check that before adding files.
