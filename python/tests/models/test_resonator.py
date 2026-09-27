"""Tests for the Lorentzian resonator S21(f) model."""

import numpy as np
import pytest

from cryocontrol.models.resonator import s21, s21_for_state


F0 = 6.0e9  # Hz
Q = 1.0e4
COUPLING = 0.8
CHI = 5.0e6  # Hz dispersive shift (|1> resonance = f0 + chi)


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


def _dip_frequency(state: int) -> float:
    """Frequency of |S21| minimum for the given qubit state."""
    f_lo = F0 - 5 * F0 / Q
    f_hi = F0 + CHI + 5 * F0 / Q
    f = np.linspace(f_lo, f_hi, 4001)
    mag = np.abs(
        s21_for_state(f, f0=F0, q=Q, coupling=COUPLING, state=state, chi=CHI)
    )
    return float(f[np.argmin(mag)])


def test_state0_dip_at_f0() -> None:
    """Qubit |0>: resonance dip at f0 (unshifted)."""
    assert _dip_frequency(0) == pytest.approx(F0, rel=0, abs=CHI / 200)


def test_state1_dip_at_f0_plus_chi() -> None:
    """Qubit |1>: resonance dip shifted by dispersive chi."""
    assert _dip_frequency(1) == pytest.approx(F0 + CHI, rel=0, abs=CHI / 200)


def test_two_states_have_distinguishable_dips() -> None:
    """|0> and |1> resonance minima are separated by approximately chi."""
    f_g = _dip_frequency(0)
    f_e = _dip_frequency(1)
    assert f_e - f_g == pytest.approx(CHI, rel=0, abs=CHI / 100)


def test_state_resonance_depth_matches_coupling() -> None:
    """On each state's resonance, |S21| equals 1 - coupling."""
    for state, f_res in ((0, F0), (1, F0 + CHI)):
        val = s21_for_state(
            np.array([f_res]), f0=F0, q=Q, coupling=COUPLING, state=state, chi=CHI
        )[0]
        assert np.abs(val) == pytest.approx(1.0 - COUPLING, abs=1e-12)
