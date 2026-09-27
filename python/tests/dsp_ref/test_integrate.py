"""Tests for integration / accumulation window."""

from __future__ import annotations

import numpy as np
import pytest

from cryocontrol.dsp_ref.integrate import integrate


def test_integrate_full_window_sum() -> None:
    """Default window accumulates the entire stream (complex sum)."""
    x = np.array([1.0 + 0.0j, 2.0 + 1.0j, 3.0 - 1.0j])
    result = integrate(x)
    assert result == pytest.approx(6.0 + 0.0j)


def test_integrate_partial_window() -> None:
    """start/length select a contiguous accumulation window."""
    x = np.arange(10, dtype=np.float64) + 1j * np.arange(10, dtype=np.float64)
    result = integrate(x, start=2, length=3)
    expected = np.sum(x[2:5])
    assert result == pytest.approx(expected)


def test_integrate_rejects_out_of_range_window() -> None:
    """Window must lie inside the sample array."""
    x = np.zeros(5, dtype=np.complex128)
    with pytest.raises(ValueError, match="window"):
        integrate(x, start=3, length=5)
    with pytest.raises(ValueError, match="window"):
        integrate(x, start=-1, length=2)
