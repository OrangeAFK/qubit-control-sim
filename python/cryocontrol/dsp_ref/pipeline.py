"""End-to-end software readout pipeline (DDC → FIR → decimate → integrate → threshold)."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from numpy.typing import ArrayLike, NDArray

from cryocontrol.dsp_ref.ddc import ddc
from cryocontrol.dsp_ref.decimate import decimate
from cryocontrol.dsp_ref.fir import apply_fir, design_fir_lowpass
from cryocontrol.dsp_ref.integrate import integrate
from cryocontrol.dsp_ref.threshold import discriminate


@dataclass(frozen=True)
class PipelineConfig:
    """Fixed parameters for one readout-chain run."""

    fs: float
    f_lo: float
    fir_num_taps: int
    fir_cutoff: float
    decim_factor: int
    integrate_start: int
    integrate_length: int | None
    threshold: float
    phase0: float = 0.0


def synthesize_if_tone(
    amplitude: complex,
    *,
    fs: float,
    f_if: float,
    n_samples: int,
) -> NDArray[np.complexfloating]:
    """Build a constant-envelope complex IF tone scaled by ``amplitude``.

    Typical use: ``amplitude = s21_for_state(f_probe, ...)`` from Phase 1 so the
    IF stream carries the resonator response that the readout chain recovers.
    """
    n = np.arange(n_samples, dtype=np.float64)
    return np.asarray(amplitude, dtype=np.complex128) * np.exp(
        1j * 2.0 * np.pi * f_if * n / fs
    )


def run_readout(
    samples: ArrayLike,
    config: PipelineConfig,
) -> tuple[complex, int]:
    """Run the golden-reference readout chain on an IF IQ stream.

    Returns ``(integrated_iq, state_decision)``.
    """
    y = ddc(samples, fs=config.fs, f_lo=config.f_lo, phase0=config.phase0)
    h = design_fir_lowpass(
        config.fir_num_taps, cutoff=config.fir_cutoff, fs=config.fs
    )
    y = apply_fir(y, h)
    y = decimate(y, config.decim_factor)
    iq = integrate(
        y, start=config.integrate_start, length=config.integrate_length
    )
    decision = discriminate(iq, threshold=config.threshold)
    assert isinstance(decision, int)
    return iq, decision
