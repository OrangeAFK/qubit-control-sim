"""Additive Gaussian noise and amplifier noise-temperature model."""

from __future__ import annotations

import numpy as np
from numpy.random import Generator
from numpy.typing import ArrayLike, NDArray

# Boltzmann constant (J/K)
K_B = 1.380649e-23


def thermal_noise_voltage_std(
    noise_temperature: float,
    bandwidth: float,
    resistance: float = 50.0,
) -> float:
    """RMS voltage std from Johnson–Nyquist noise: ``sqrt(4 k_B T B R)``.

    Parameters
    ----------
    noise_temperature :
        Amplifier (or effective) noise temperature in kelvin.
    bandwidth :
        Noise bandwidth in Hz.
    resistance :
        Reference resistance in ohms (default 50 Ω).
    """
    if noise_temperature < 0.0:
        raise ValueError("noise_temperature must be >= 0")
    if bandwidth < 0.0:
        raise ValueError("bandwidth must be >= 0")
    if resistance <= 0.0:
        raise ValueError("resistance must be > 0")
    return float(np.sqrt(4.0 * K_B * noise_temperature * bandwidth * resistance))


def add_gaussian_noise(
    signal: ArrayLike,
    sigma: float,
    rng: Generator | None = None,
) -> NDArray:
    """Add circularly-symmetric complex AWGN with total amplitude std ``sigma``.

    Real and imaginary parts each have std ``sigma / sqrt(2)``. Real-valued
    inputs receive real AWGN with std ``sigma``.
    """
    if sigma < 0.0:
        raise ValueError("sigma must be >= 0")
    arr = np.asarray(signal)
    if sigma == 0.0:
        return arr.copy()
    if rng is None:
        rng = np.random.default_rng()
    if np.iscomplexobj(arr):
        comp_std = sigma / np.sqrt(2.0)
        noise = comp_std * (
            rng.standard_normal(arr.shape) + 1j * rng.standard_normal(arr.shape)
        )
        return arr + noise.astype(arr.dtype, copy=False)
    noise = sigma * rng.standard_normal(arr.shape)
    return arr + noise.astype(arr.dtype, copy=False)


def add_amplifier_noise(
    signal: ArrayLike,
    noise_temperature: float,
    bandwidth: float,
    resistance: float = 50.0,
    rng: Generator | None = None,
) -> NDArray:
    """Add amplifier thermal noise parameterized by noise temperature.

    Noise amplitude std is ``thermal_noise_voltage_std(T, B, R)`` applied as
    complex AWGN via :func:`add_gaussian_noise`.
    """
    sigma = thermal_noise_voltage_std(
        noise_temperature, bandwidth=bandwidth, resistance=resistance
    )
    return add_gaussian_noise(signal, sigma=sigma, rng=rng)
