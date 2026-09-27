"""Lorentzian resonator transmission model S21(f)."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def s21(
    f: ArrayLike,
    f0: float,
    q: float,
    coupling: float,
) -> NDArray[np.complexfloating]:
    """Complex notch-transmission Lorentzian.

    S21(f) = 1 - coupling / (1 + 2j * Q * (f - f0) / f0)

    Parameters
    ----------
    f :
        Probe frequency or frequencies in Hz.
    f0 :
        Resonance (center) frequency in Hz.
    q :
        Loaded quality factor (dimensionless, > 0).
    coupling :
        On-resonance dip depth in (0, 1]; |S21(f0)| = 1 - coupling.
    """
    f_arr = np.asarray(f, dtype=np.float64)
    return 1.0 - coupling / (1.0 + 2j * q * (f_arr - f0) / f0)


def s21_for_state(
    f: ArrayLike,
    f0: float,
    q: float,
    coupling: float,
    state: int,
    chi: float,
) -> NDArray[np.complexfloating]:
    """S21 with qubit-state-dependent resonator frequency.

    Dispersive readout model: resonance at ``f0`` for ``state=0`` and at
    ``f0 + chi`` for ``state=1``.
    """
    if state not in (0, 1):
        raise ValueError(f"state must be 0 or 1, got {state!r}")
    f_res = f0 + state * chi
    return s21(f, f0=f_res, q=q, coupling=coupling)
