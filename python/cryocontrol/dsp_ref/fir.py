"""FIR low-pass design and filtering for the software readout chain."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def design_fir_lowpass(
    num_taps: int,
    cutoff: float,
    fs: float,
    *,
    window: str = "hamming",
) -> NDArray[np.floating]:
    """Design a Type-I windowed-sinc low-pass FIR with unity DC gain.

    Parameters
    ----------
    num_taps :
        Filter length; must be odd.
    cutoff :
        Cutoff frequency in Hz (passband edge of the ideal rect response).
    fs :
        Sample rate in Hz.
    window :
        Window name: ``"hamming"`` (default) or ``"rectangular"``.
    """
    if num_taps < 3 or num_taps % 2 == 0:
        raise ValueError(f"num_taps must be an odd integer >= 3, got {num_taps}")
    if not (0.0 < cutoff < fs / 2.0):
        raise ValueError(f"cutoff must be in (0, fs/2), got {cutoff} with fs={fs}")

    m = (num_taps - 1) // 2
    n = np.arange(num_taps, dtype=np.float64) - m
    fc = cutoff / fs  # cycles per sample
    h = np.empty(num_taps, dtype=np.float64)
    zero = n == 0
    h[zero] = 2.0 * fc
    n_nz = n[~zero]
    h[~zero] = np.sin(2.0 * np.pi * fc * n_nz) / (np.pi * n_nz)

    if window == "hamming":
        w = 0.54 - 0.46 * np.cos(2.0 * np.pi * np.arange(num_taps) / (num_taps - 1))
    elif window == "rectangular":
        w = np.ones(num_taps, dtype=np.float64)
    else:
        raise ValueError(f"unsupported window {window!r}; use 'hamming' or 'rectangular'")

    h = h * w
    h = h / np.sum(h)
    return h


def apply_fir(
    samples: ArrayLike,
    coeffs: ArrayLike,
) -> NDArray:
    """Apply an FIR filter via centered convolution (``mode='same'``).

    Real coefficients are applied to real or complex sample streams. Complex
    inputs are filtered with the same real impulse response on I and Q.
    """
    x = np.asarray(samples)
    h = np.asarray(coeffs, dtype=np.float64)
    if h.ndim != 1:
        raise ValueError("coeffs must be a 1-D FIR impulse response")
    return np.convolve(x, h, mode="same")
