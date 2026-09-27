"""Generate checked-in Phase 2 golden fixture ``.npz`` files.

Run from repo root::

    python -m cryocontrol.dsp_ref.fixtures.generate
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from cryocontrol.dsp_ref.fir import design_fir_lowpass
from cryocontrol.dsp_ref.fixtures import FIXTURES_DIR
from cryocontrol.dsp_ref.pipeline import (
    PipelineConfig,
    run_readout,
    synthesize_if_tone,
)
from cryocontrol.models.noise import add_gaussian_noise
from cryocontrol.models.resonator import s21_for_state

# Shared synthesis / pipeline parameters (also stored inside each fixture).
FS = 100e6
F_IF = 10e6
F0 = 6.0e9
Q = 1.0e4
COUPLING = 0.8
CHI = 5.0e6
F_PROBE = F0
N_SAMPLES = 4096
FIR_NUM_TAPS = 63
FIR_CUTOFF = 5e6
DECIM = 4
INTEGRATE_START = 8
NOISE_SIGMA = 0.05
NOISE_SEED = 42
NOISY_TRUE_STATE = 0


def _if_for_state(state: int) -> np.ndarray:
    s21 = complex(
        s21_for_state(
            F_PROBE, f0=F0, q=Q, coupling=COUPLING, state=state, chi=CHI
        )
    )
    return synthesize_if_tone(s21, fs=FS, f_if=F_IF, n_samples=N_SAMPLES)


def _shared_arrays(threshold: float, fir_coeffs: np.ndarray) -> dict:
    return {
        "fs": FS,
        "f_lo": F_IF,
        "phase0": 0.0,
        "fir_num_taps": FIR_NUM_TAPS,
        "fir_cutoff": FIR_CUTOFF,
        "fir_coeffs": fir_coeffs,
        "decim_factor": DECIM,
        "integrate_start": INTEGRATE_START,
        "integrate_length": np.int64(-1),
        "threshold": threshold,
        "f_probe": F_PROBE,
        "f0": F0,
        "q": Q,
        "coupling": COUPLING,
        "chi": CHI,
        "n_samples": N_SAMPLES,
    }


def generate(out_dir: Path | None = None) -> tuple[Path, Path]:
    """Write ``noiseless.npz`` and ``noisy.npz``; return their paths."""
    out = Path(out_dir) if out_dir is not None else FIXTURES_DIR
    out.mkdir(parents=True, exist_ok=True)

    fir_coeffs = design_fir_lowpass(FIR_NUM_TAPS, cutoff=FIR_CUTOFF, fs=FS)

    # Calibrate threshold from noiseless IQ means (midpoint on I).
    probe_cfg = PipelineConfig(
        fs=FS,
        f_lo=F_IF,
        fir_num_taps=FIR_NUM_TAPS,
        fir_cutoff=FIR_CUTOFF,
        decim_factor=DECIM,
        integrate_start=INTEGRATE_START,
        integrate_length=None,
        threshold=0.0,
    )
    iq0, _ = run_readout(_if_for_state(0), probe_cfg)
    iq1, _ = run_readout(_if_for_state(1), probe_cfg)
    threshold = 0.5 * (np.real(iq0) + np.real(iq1))

    cfg = PipelineConfig(
        fs=FS,
        f_lo=F_IF,
        fir_num_taps=FIR_NUM_TAPS,
        fir_cutoff=FIR_CUTOFF,
        decim_factor=DECIM,
        integrate_start=INTEGRATE_START,
        integrate_length=None,
        threshold=threshold,
    )

    shared = _shared_arrays(threshold, fir_coeffs)

    in0 = _if_for_state(0)
    in1 = _if_for_state(1)
    out0, d0 = run_readout(in0, cfg)
    out1, d1 = run_readout(in1, cfg)
    assert d0 == 0 and d1 == 1

    noiseless_path = out / "noiseless.npz"
    np.savez(
        noiseless_path,
        input_iq_s0=in0,
        input_iq_s1=in1,
        output_iq_s0=np.asarray(out0, dtype=np.complex128),
        output_iq_s1=np.asarray(out1, dtype=np.complex128),
        decision_s0=np.int64(d0),
        decision_s1=np.int64(d1),
        **shared,
    )

    clean = _if_for_state(NOISY_TRUE_STATE)
    noisy_in = add_gaussian_noise(
        clean, sigma=NOISE_SIGMA, rng=np.random.default_rng(NOISE_SEED)
    )
    noisy_out, noisy_decision = run_readout(noisy_in, cfg)

    noisy_path = out / "noisy.npz"
    np.savez(
        noisy_path,
        input_iq=noisy_in,
        output_iq=np.asarray(noisy_out, dtype=np.complex128),
        decision=np.int64(noisy_decision),
        true_state=np.int64(NOISY_TRUE_STATE),
        noise_sigma=NOISE_SIGMA,
        **shared,
    )
    return noiseless_path, noisy_path


def main() -> None:
    noiseless, noisy = generate()
    print(f"Wrote {noiseless}")
    print(f"Wrote {noisy}")


if __name__ == "__main__":
    main()
