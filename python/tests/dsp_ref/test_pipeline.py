"""End-to-end tests: Phase 1 resonator → software readout pipeline."""

from __future__ import annotations

import numpy as np
import pytest

from cryocontrol.dsp_ref.pipeline import (
    PipelineConfig,
    run_readout,
    synthesize_if_tone,
)
from cryocontrol.models.resonator import s21_for_state

FS = 100e6
F_IF = 10e6
F0 = 6.0e9
Q = 1.0e4
COUPLING = 0.8
CHI = 5.0e6
N = 4096
F_PROBE = F0  # on |0> resonance: Re(S21) separates |0> vs |1>


def _if_for_state(state: int) -> np.ndarray:
    s21 = complex(
        s21_for_state(
            F_PROBE, f0=F0, q=Q, coupling=COUPLING, state=state, chi=CHI
        )
    )
    return synthesize_if_tone(s21, fs=FS, f_if=F_IF, n_samples=N)


def _default_config(threshold: float) -> PipelineConfig:
    return PipelineConfig(
        fs=FS,
        f_lo=F_IF,
        fir_num_taps=63,
        fir_cutoff=5e6,
        decim_factor=4,
        integrate_start=8,
        integrate_length=None,
        threshold=threshold,
    )


def test_noiseless_two_state_iq_separable_on_real_axis() -> None:
    """Integrated I for |0> and |1> land on opposite sides of a mid threshold."""
    cfg = _default_config(threshold=0.0)  # threshold unused for IQ compare
    iq0, _ = run_readout(_if_for_state(0), cfg)
    iq1, _ = run_readout(_if_for_state(1), cfg)
    assert np.real(iq0) < np.real(iq1)
    mid = 0.5 * (np.real(iq0) + np.real(iq1))
    assert np.real(iq0) < mid < np.real(iq1)


def test_noiseless_pipeline_recovers_both_states() -> None:
    """Noiseless Phase-1 IF streams discriminate correctly for |0> and |1>."""
    cfg0 = _default_config(threshold=0.0)
    iq0, _ = run_readout(_if_for_state(0), cfg0)
    iq1, _ = run_readout(_if_for_state(1), cfg0)
    threshold = 0.5 * (np.real(iq0) + np.real(iq1))
    cfg = _default_config(threshold=threshold)

    _, d0 = run_readout(_if_for_state(0), cfg)
    _, d1 = run_readout(_if_for_state(1), cfg)
    assert d0 == 0
    assert d1 == 1


def test_noiseless_fidelity_is_perfect() -> None:
    """Repeated noiseless shots for both states yield 100% discrimination fidelity."""
    cfg0 = _default_config(threshold=0.0)
    iq0, _ = run_readout(_if_for_state(0), cfg0)
    iq1, _ = run_readout(_if_for_state(1), cfg0)
    cfg = _default_config(threshold=0.5 * (np.real(iq0) + np.real(iq1)))

    n_shots = 50
    correct = 0
    for state in (0, 1):
        x = _if_for_state(state)
        for _ in range(n_shots):
            _, decision = run_readout(x, cfg)
            correct += int(decision == state)
    fidelity = correct / (2 * n_shots)
    assert fidelity == pytest.approx(1.0)
