"""Tests for integer-factor decimation (downsample after anti-alias FIR)."""

from __future__ import annotations

import numpy as np
import pytest

from cryocontrol.dsp_ref.decimate import decimate


def test_decimate_keeps_every_mth_sample() -> None:
    """Decimation by M retains samples at indices 0, M, 2M, ..."""
    x = np.arange(20, dtype=np.float64)
    y = decimate(x, factor=4)
    np.testing.assert_array_equal(y, np.array([0.0, 4.0, 8.0, 12.0, 16.0]))


def test_decimate_output_length() -> None:
    """Output length is ceil(N / factor)."""
    x = np.zeros(10, dtype=np.complex128)
    assert decimate(x, factor=3).size == 4
    assert decimate(x, factor=1).size == 10
    assert decimate(x, factor=10).size == 1


def test_decimate_preserves_complex_dtype() -> None:
    """Complex streams stay complex; values match the strided input."""
    x = (np.arange(8) + 1j * np.arange(8, 0, -1)).astype(np.complex128)
    y = decimate(x, factor=2)
    np.testing.assert_array_equal(y, x[::2])
    assert y.dtype.kind == "c"


def test_decimate_rejects_nonpositive_factor() -> None:
    """factor must be an integer >= 1."""
    x = np.arange(4, dtype=np.float64)
    with pytest.raises(ValueError, match="factor"):
        decimate(x, factor=0)
    with pytest.raises(ValueError, match="factor"):
        decimate(x, factor=-2)
