"""Tests for the Lorentzian resonator S21(f) model."""

import numpy as np
import pytest

from cryocontrol.models.resonator import s21


F0 = 6.0e9  # Hz
Q = 1.0e4
COUPLING = 0.8


def test_dip_minimum_at_f0() -> None:
    """|S21| reaches its minimum at the resonator center frequency."""
    f = np.linspace(F0 * (1 - 5 / Q), F0 * (1 + 5 / Q), 2001)
    mag = np.abs(s21(f, f0=F0, q=Q, coupling=COUPLING))
    assert f[np.argmin(mag)] == pytest.approx(F0, rel=0, abs=f[1] - f[0])


def test_on_resonance_depth() -> None:
    """On resonance, |S21(f0)| equals 1 - coupling."""
    val = s21(np.array([F0]), f0=F0, q=Q, coupling=COUPLING)[0]
    assert np.abs(val) == pytest.approx(1.0 - COUPLING, abs=1e-12)


def test_far_off_resonance_unity() -> None:
    """Far from resonance, |S21| approaches 1."""
    delta = 100 * F0 / Q
    f = np.array([F0 - delta, F0 + delta])
    mag = np.abs(s21(f, f0=F0, q=Q, coupling=COUPLING))
    np.testing.assert_allclose(mag, 1.0, atol=1e-2)


def test_imag_sign_flips_across_resonance() -> None:
    """Imaginary part of S21 changes sign across resonance (Lorentzian antisymmetry)."""
    delta = F0 / Q
    s_below = s21(np.array([F0 - delta]), f0=F0, q=Q, coupling=COUPLING)[0]
    s_above = s21(np.array([F0 + delta]), f0=F0, q=Q, coupling=COUPLING)[0]
    assert np.iscomplexobj(s_below)
    assert np.sign(s_below.imag) == -np.sign(s_above.imag)
    assert s_below.imag != 0.0
