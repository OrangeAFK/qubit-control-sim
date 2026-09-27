"""Tests for simple threshold-based state discrimination."""

from __future__ import annotations

import numpy as np
import pytest

from cryocontrol.dsp_ref.threshold import discriminate


def test_discriminate_real_part_below_threshold_is_zero() -> None:
    """Re(iq) < threshold → state 0."""
    assert discriminate(0.1 + 2.0j, threshold=0.5) == 0


def test_discriminate_real_part_at_or_above_threshold_is_one() -> None:
    """Re(iq) >= threshold → state 1."""
    assert discriminate(0.5 + 0.0j, threshold=0.5) == 1
    assert discriminate(1.0 - 3.0j, threshold=0.5) == 1


def test_discriminate_vectorized() -> None:
    """Array of IQ points maps elementwise to state decisions."""
    iq = np.array([-1.0 + 0j, 0.0 + 0j, 2.0 + 1j])
    states = discriminate(iq, threshold=0.0)
    np.testing.assert_array_equal(states, np.array([0, 1, 1]))


def test_discriminate_accepts_real_scalar() -> None:
    """A real scalar is treated as I with Q=0."""
    assert discriminate(-0.2, threshold=0.0) == 0
    assert discriminate(0.2, threshold=0.0) == 1
