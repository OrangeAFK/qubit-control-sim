"""Tests for FIR low-pass design and application."""

from __future__ import annotations

import numpy as np
import pytest

from cryocontrol.dsp_ref.fir import apply_fir, design_fir_lowpass

FS = 100e6  # Hz
CUTOFF = 5e6  # Hz
NUM_TAPS = 63
N = 4096


def _tone(fs: float, f: float, n: int, amp: float = 1.0) -> np.ndarray:
    t = np.arange(n, dtype=np.float64) / fs
    return amp * np.exp(1j * 2.0 * np.pi * f * t)


def test_design_unity_dc_gain() -> None:
    """Low-pass coefficients are normalized to unity DC gain."""
    h = design_fir_lowpass(NUM_TAPS, cutoff=CUTOFF, fs=FS)
    assert h.ndim == 1
    assert h.size == NUM_TAPS
    assert h.dtype.kind == "f"
    assert np.sum(h) == pytest.approx(1.0, abs=1e-12)


def test_design_rejects_even_taps() -> None:
    """Even tap counts are rejected (Type-I linear-phase requires odd length)."""
    with pytest.raises(ValueError, match="odd"):
        design_fir_lowpass(64, cutoff=CUTOFF, fs=FS)


def test_low_frequency_tone_passes() -> None:
    """A tone well below cutoff retains nearly full amplitude after filtering."""
    h = design_fir_lowpass(NUM_TAPS, cutoff=CUTOFF, fs=FS)
    x = _tone(FS, f=0.5e6, n=N, amp=1.0)
    y = apply_fir(x, h)
    # Ignore filter transient at the edges
    mid = slice(NUM_TAPS, N - NUM_TAPS)
    assert np.mean(np.abs(y[mid])) == pytest.approx(1.0, rel=0.05)


def test_high_frequency_tone_attenuated() -> None:
    """A tone well above cutoff is strongly attenuated."""
    h = design_fir_lowpass(NUM_TAPS, cutoff=CUTOFF, fs=FS)
    x = _tone(FS, f=25e6, n=N, amp=1.0)
    y = apply_fir(x, h)
    mid = slice(NUM_TAPS, N - NUM_TAPS)
    assert np.mean(np.abs(y[mid])) < 0.05


def test_apply_fir_accepts_real_and_complex() -> None:
    """Real and complex inputs are filtered; output length matches input."""
    h = design_fir_lowpass(NUM_TAPS, cutoff=CUTOFF, fs=FS)
    x_real = np.ones(N, dtype=np.float64)
    y_real = apply_fir(x_real, h)
    assert y_real.shape == x_real.shape
    assert np.mean(y_real[NUM_TAPS:-NUM_TAPS]) == pytest.approx(1.0, abs=1e-6)

    x_c = np.ones(N, dtype=np.complex128) * (0.5 + 0.25j)
    y_c = apply_fir(x_c, h)
    assert y_c.dtype.kind == "c"
    assert y_c.shape == x_c.shape
    mid = y_c[NUM_TAPS:-NUM_TAPS]
    assert np.mean(mid) == pytest.approx(0.5 + 0.25j, abs=1e-6)
