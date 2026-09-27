"""Tests for software digital downconversion (DDC / NCO mixer)."""

from __future__ import annotations

import numpy as np
import pytest

from cryocontrol.dsp_ref.ddc import ddc

FS = 100e6  # Hz
F_LO = 10e6  # Hz
N = 4096
AMP = 0.75


def _tone(fs: float, f: float, n: int, amp: float = 1.0, phase: float = 0.0) -> np.ndarray:
    t = np.arange(n, dtype=np.float64) / fs
    return amp * np.exp(1j * (2.0 * np.pi * f * t + phase))


def test_tone_at_lo_lands_at_dc() -> None:
    """A complex tone at f_lo mixes to near-DC with amplitude preserved."""
    x = _tone(FS, F_LO, N, amp=AMP)
    y = ddc(x, fs=FS, f_lo=F_LO)
    assert y.dtype.kind == "c"
    assert np.abs(np.mean(y)) == pytest.approx(AMP, rel=1e-3)
    residual = y - np.mean(y)
    assert np.abs(np.mean(y)) > 50.0 * np.std(residual)


def test_fft_dc_bin_dominates() -> None:
    """After DDC, energy concentrates in the DC FFT bin."""
    x = _tone(FS, F_LO, N, amp=AMP)
    y = ddc(x, fs=FS, f_lo=F_LO)
    spectrum = np.abs(np.fft.fft(y))
    assert spectrum[0] == pytest.approx(np.max(spectrum), rel=1e-9)
    assert spectrum[0] > 100.0 * np.median(spectrum)


def test_phase0_rotates_baseband() -> None:
    """Nonzero phase0 rotates the recovered baseband complex phasor."""
    x = _tone(FS, F_LO, N, amp=AMP, phase=0.0)
    y0 = ddc(x, fs=FS, f_lo=F_LO, phase0=0.0)
    y1 = ddc(x, fs=FS, f_lo=F_LO, phase0=np.pi / 3)
    mean0 = np.mean(y0)
    mean1 = np.mean(y1)
    expected = mean0 * np.exp(-1j * np.pi / 3)
    np.testing.assert_allclose(mean1, expected, rtol=1e-6, atol=1e-9)


def test_real_if_input_accepted() -> None:
    """Real-valued IF samples are accepted (Q promoted to 0)."""
    t = np.arange(N, dtype=np.float64) / FS
    x_real = AMP * np.cos(2.0 * np.pi * F_LO * t)
    y = ddc(x_real, fs=FS, f_lo=F_LO)
    assert y.dtype.kind == "c"
    # Cosine = (e^{jωt} + e^{-jωt})/2 → after mix, DC component ≈ AMP/2
    assert np.abs(np.mean(y)) == pytest.approx(AMP / 2.0, rel=1e-2)
