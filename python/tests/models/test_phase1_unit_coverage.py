"""Phase 1 unit-test task coverage (PLAN.md).

Resonance dip at expected frequency; SNR scales with noise parameters;
each fault mode independently changes output in the expected direction.
"""

from __future__ import annotations

import numpy as np
import pytest

from cryocontrol.models.cryo_chain import CryoChain, CryoStage, FaultConfig
from cryocontrol.models.noise import add_amplifier_noise
from cryocontrol.models.resonator import s21, s21_for_state


F0 = 6.0e9
Q = 1.0e4
COUPLING = 0.8
CHI = 5.0e6


def test_resonance_dip_appears_at_expected_frequency() -> None:
    """|S21| minimum is at f0 for the bare resonator."""
    f = np.linspace(F0 * (1 - 5 / Q), F0 * (1 + 5 / Q), 2001)
    mag = np.abs(s21(f, f0=F0, q=Q, coupling=COUPLING))
    assert f[np.argmin(mag)] == pytest.approx(F0, abs=f[1] - f[0])


def test_two_state_dips_appear_at_expected_frequencies() -> None:
    """|0> dip at f0; |1> dip at f0 + chi."""
    f = np.linspace(F0 - 5 * F0 / Q, F0 + CHI + 5 * F0 / Q, 4001)
    mag0 = np.abs(s21_for_state(f, f0=F0, q=Q, coupling=COUPLING, state=0, chi=CHI))
    mag1 = np.abs(s21_for_state(f, f0=F0, q=Q, coupling=COUPLING, state=1, chi=CHI))
    assert f[np.argmin(mag0)] == pytest.approx(F0, abs=CHI / 200)
    assert f[np.argmin(mag1)] == pytest.approx(F0 + CHI, abs=CHI / 200)


def test_snr_scales_inversely_with_noise_temperature() -> None:
    """Higher amplifier noise temperature lowers SNR roughly as 1/T."""
    rng = np.random.default_rng(123)
    n = 150_000
    signal = np.full(n, 2.0 + 0.0j, dtype=np.complex128)
    signal_power = float(np.mean(np.abs(signal) ** 2))
    bw = 1e6

    def measured_snr(t_noise: float) -> float:
        noisy = add_amplifier_noise(
            signal, noise_temperature=t_noise, bandwidth=bw, rng=rng
        )
        noise_power = float(np.mean(np.abs(noisy - signal) ** 2))
        return signal_power / noise_power

    t_lo, t_hi = 10.0, 40.0
    snr_lo = measured_snr(t_lo)
    snr_hi = measured_snr(t_hi)
    assert snr_lo > snr_hi
    # SNR ∝ 1/T  ⇒  snr_lo/snr_hi ≈ t_hi/t_lo
    assert snr_lo / snr_hi == pytest.approx(t_hi / t_lo, rel=0.15)


def _thru_stage() -> list[CryoStage]:
    return [
        CryoStage(
            name="thru",
            temperature=0.015,
            attenuation_db=0.0,
            amp_gain_db=0.0,
            noise_temperature=0.0,
            cable_loss_db=0.0,
        )
    ]


def _amp_stage(noise_temperature: float = 0.0) -> list[CryoStage]:
    return [
        CryoStage(
            name="amp",
            temperature=4.0,
            attenuation_db=0.0,
            amp_gain_db=0.0,
            noise_temperature=noise_temperature,
            cable_loss_db=0.0,
        )
    ]


def test_gain_drift_fault_reduces_amplitude_only_when_enabled() -> None:
    signal = np.array([1.0 + 0.0j])
    baseline = CryoChain(_thru_stage()).apply(
        signal, bandwidth=1e6, rng=np.random.default_rng(0)
    )
    disabled = CryoChain(
        _thru_stage(),
        faults=FaultConfig(gain_drift_db=-6.0, gain_drift_enabled=False),
    ).apply(signal, bandwidth=1e6, rng=np.random.default_rng(0))
    enabled = CryoChain(
        _thru_stage(),
        faults=FaultConfig(gain_drift_db=-6.0, gain_drift_enabled=True),
    ).apply(signal, bandwidth=1e6, rng=np.random.default_rng(0))

    assert disabled[0] == pytest.approx(baseline[0])
    assert np.abs(enabled[0]) < np.abs(baseline[0])
    assert np.abs(enabled[0] / baseline[0]) == pytest.approx(10 ** (-6.0 / 20.0))


def test_noise_fault_increases_variance_only_when_enabled() -> None:
    signal = np.zeros(60_000, dtype=np.complex128)
    stages = _amp_stage(noise_temperature=25.0)
    quiet = CryoChain(stages).apply(signal, bandwidth=1e6, rng=np.random.default_rng(1))
    disabled = CryoChain(
        stages,
        faults=FaultConfig(noise_scale=9.0, noise_fault_enabled=False),
    ).apply(signal, bandwidth=1e6, rng=np.random.default_rng(1))
    enabled = CryoChain(
        stages,
        faults=FaultConfig(noise_scale=9.0, noise_fault_enabled=True),
    ).apply(signal, bandwidth=1e6, rng=np.random.default_rng(1))

    assert np.var(disabled) / np.var(quiet) == pytest.approx(1.0, rel=0.2)
    assert np.var(enabled) / np.var(quiet) == pytest.approx(9.0, rel=0.2)


def test_frequency_drift_fault_increases_drift_only_when_enabled() -> None:
    stages = _thru_stage()
    stages[0].frequency_drift_hz = 1e5
    baseline = CryoChain(stages).effective_frequency_drift_hz()
    disabled = CryoChain(
        stages,
        faults=FaultConfig(frequency_drift_hz=3e6, frequency_drift_enabled=False),
    ).effective_frequency_drift_hz()
    enabled = CryoChain(
        stages,
        faults=FaultConfig(frequency_drift_hz=3e6, frequency_drift_enabled=True),
    ).effective_frequency_drift_hz()

    assert disabled == pytest.approx(baseline)
    assert enabled == pytest.approx(baseline + 3e6)


def test_iq_imbalance_fault_scales_q_only_when_enabled() -> None:
    signal = np.array([2.0 + 2.0j])
    baseline = CryoChain(_thru_stage()).apply(
        signal, bandwidth=1e6, rng=np.random.default_rng(0)
    )
    disabled = CryoChain(
        _thru_stage(),
        faults=FaultConfig(iq_gain_imbalance=0.25, iq_imbalance_enabled=False),
    ).apply(signal, bandwidth=1e6, rng=np.random.default_rng(0))
    enabled = CryoChain(
        _thru_stage(),
        faults=FaultConfig(iq_gain_imbalance=0.25, iq_imbalance_enabled=True),
    ).apply(signal, bandwidth=1e6, rng=np.random.default_rng(0))

    assert disabled[0] == pytest.approx(baseline[0])
    assert enabled[0].real == pytest.approx(baseline[0].real)
    assert enabled[0].imag == pytest.approx(0.25 * baseline[0].imag)


def test_adc_saturation_fault_clips_only_when_enabled() -> None:
    signal = np.array([2.0 + 0.5j])
    baseline = CryoChain(_thru_stage()).apply(
        signal, bandwidth=1e6, rng=np.random.default_rng(0)
    )
    disabled = CryoChain(
        _thru_stage(),
        faults=FaultConfig(adc_saturation_level=1.0, adc_saturation_enabled=False),
    ).apply(signal, bandwidth=1e6, rng=np.random.default_rng(0))
    enabled = CryoChain(
        _thru_stage(),
        faults=FaultConfig(adc_saturation_level=1.0, adc_saturation_enabled=True),
    ).apply(signal, bandwidth=1e6, rng=np.random.default_rng(0))

    assert disabled[0] == pytest.approx(baseline[0])
    assert enabled[0].real == pytest.approx(1.0)
    assert enabled[0].imag == pytest.approx(0.5)
