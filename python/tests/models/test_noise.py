"""Tests for additive Gaussian + amplifier noise-temperature model."""

import numpy as np
import pytest

from cryocontrol.models.noise import (
    add_amplifier_noise,
    add_gaussian_noise,
    thermal_noise_voltage_std,
)


def test_zero_sigma_leaves_signal_unchanged() -> None:
    signal = np.array([1.0 + 2.0j, 3.0 - 1.0j])
    out = add_gaussian_noise(signal, sigma=0.0, rng=np.random.default_rng(0))
    np.testing.assert_array_equal(out, signal)


def test_additive_gaussian_has_expected_std() -> None:
    """Real/imag each have std ≈ sigma / sqrt(2) for circular complex AWGN."""
    rng = np.random.default_rng(42)
    n = 200_000
    signal = np.zeros(n, dtype=np.complex128)
    sigma = 0.5
    noisy = add_gaussian_noise(signal, sigma=sigma, rng=rng)
    noise = noisy - signal
    expected_comp_std = sigma / np.sqrt(2)
    assert np.std(noise.real) == pytest.approx(expected_comp_std, rel=0.05)
    assert np.std(noise.imag) == pytest.approx(expected_comp_std, rel=0.05)
    assert np.abs(np.mean(noise)) == pytest.approx(0.0, abs=0.01)


def test_thermal_std_scales_as_sqrt_temperature() -> None:
    bw = 1e6
    r = 50.0
    t1, t2 = 20.0, 80.0
    s1 = thermal_noise_voltage_std(t1, bandwidth=bw, resistance=r)
    s2 = thermal_noise_voltage_std(t2, bandwidth=bw, resistance=r)
    assert s2 / s1 == pytest.approx(np.sqrt(t2 / t1), rel=1e-12)
    assert s1 > 0.0


def test_amplifier_noise_variance_scales_with_temperature() -> None:
    """Noise power (variance) scales linearly with amplifier noise temperature."""
    rng = np.random.default_rng(7)
    n = 200_000
    signal = np.ones(n, dtype=np.complex128)
    bw = 1e6
    t_cold, t_hot = 10.0, 40.0
    cold = add_amplifier_noise(
        signal, noise_temperature=t_cold, bandwidth=bw, rng=rng
    )
    hot = add_amplifier_noise(
        signal, noise_temperature=t_hot, bandwidth=bw, rng=rng
    )
    var_cold = np.var(cold - signal)
    var_hot = np.var(hot - signal)
    assert var_hot / var_cold == pytest.approx(t_hot / t_cold, rel=0.1)


def test_snr_decreases_with_higher_noise_temperature() -> None:
    rng = np.random.default_rng(99)
    n = 100_000
    signal = np.full(n, 1.0 + 0.0j, dtype=np.complex128)
    signal_power = np.mean(np.abs(signal) ** 2)

    def snr(t_noise: float) -> float:
        noisy = add_amplifier_noise(
            signal, noise_temperature=t_noise, bandwidth=1e6, rng=rng
        )
        noise_power = np.mean(np.abs(noisy - signal) ** 2)
        return float(signal_power / noise_power)

    assert snr(5.0) > snr(50.0)
