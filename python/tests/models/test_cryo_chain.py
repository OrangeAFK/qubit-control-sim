"""Tests for parameterized cryo-chain gain/loss with toggleable faults."""

import numpy as np
import pytest

from cryocontrol.models.cryo_chain import (
    CryoChain,
    CryoStage,
    FaultConfig,
    db_to_voltage_gain,
    default_cryo_stages,
)


def test_db_to_voltage_gain() -> None:
    assert db_to_voltage_gain(0.0) == pytest.approx(1.0)
    assert db_to_voltage_gain(20.0) == pytest.approx(10.0)
    assert db_to_voltage_gain(-20.0) == pytest.approx(0.1)


def test_net_gain_is_product_of_parameterized_stages() -> None:
    stages = [
        CryoStage(
            name="a",
            temperature=300.0,
            attenuation_db=10.0,
            amp_gain_db=0.0,
            noise_temperature=0.0,
            cable_loss_db=0.0,
        ),
        CryoStage(
            name="b",
            temperature=4.0,
            attenuation_db=0.0,
            amp_gain_db=20.0,
            noise_temperature=0.0,
            cable_loss_db=0.0,
        ),
    ]
    chain = CryoChain(stages)
    # net dB = -10 + 20 = +10 → voltage × 10^(10/20)
    assert chain.net_voltage_gain_db() == pytest.approx(10.0)
    signal = np.array([1.0 + 0.0j])
    out = chain.apply(signal, bandwidth=1e6, rng=np.random.default_rng(0))
    assert out[0] == pytest.approx(db_to_voltage_gain(10.0) + 0.0j)


def test_disabled_stage_is_skipped() -> None:
    stages = [
        CryoStage(
            name="loss",
            temperature=300.0,
            attenuation_db=20.0,
            amp_gain_db=0.0,
            noise_temperature=0.0,
            cable_loss_db=0.0,
            enabled=False,
        ),
        CryoStage(
            name="amp",
            temperature=4.0,
            attenuation_db=0.0,
            amp_gain_db=6.0,
            noise_temperature=0.0,
            cable_loss_db=0.0,
        ),
    ]
    chain = CryoChain(stages)
    assert chain.net_voltage_gain_db() == pytest.approx(6.0)


def test_default_stages_match_architecture_temperatures() -> None:
    stages = default_cryo_stages()
    temps = [s.temperature for s in stages]
    assert temps[0] == pytest.approx(300.0)
    assert temps[1] == pytest.approx(4.0)
    assert temps[2] < 1.0  # sub-Kelvin
    assert 0.01 <= temps[3] <= 0.02  # ~10–20 mK device


def test_gain_drift_fault_independently_changes_output() -> None:
    stages = [
        CryoStage(
            name="amp",
            temperature=4.0,
            attenuation_db=0.0,
            amp_gain_db=20.0,
            noise_temperature=0.0,
            cable_loss_db=0.0,
        )
    ]
    signal = np.array([1.0 + 0.0j])
    baseline = CryoChain(stages).apply(signal, bandwidth=1e6, rng=np.random.default_rng(1))
    faulted = CryoChain(
        stages,
        faults=FaultConfig(gain_drift_db=-3.0, gain_drift_enabled=True),
    ).apply(signal, bandwidth=1e6, rng=np.random.default_rng(1))
    # -3 dB voltage ≈ 0.707×
    assert np.abs(faulted[0]) < np.abs(baseline[0])
    assert faulted[0] / baseline[0] == pytest.approx(db_to_voltage_gain(-3.0), rel=1e-12)


def test_noise_fault_independently_increases_variance() -> None:
    stages = [
        CryoStage(
            name="amp",
            temperature=4.0,
            attenuation_db=0.0,
            amp_gain_db=0.0,
            noise_temperature=20.0,
            cable_loss_db=0.0,
        )
    ]
    signal = np.zeros(80_000, dtype=np.complex128)
    rng = np.random.default_rng(2)
    quiet = CryoChain(stages).apply(signal, bandwidth=1e6, rng=rng)
    noisy = CryoChain(
        stages,
        faults=FaultConfig(noise_scale=4.0, noise_fault_enabled=True),
    ).apply(signal, bandwidth=1e6, rng=rng)
    # noise_temperature effective ×4 → variance ×4
    assert np.var(noisy) / np.var(quiet) == pytest.approx(4.0, rel=0.15)


def test_frequency_drift_fault_is_independent() -> None:
    stages = default_cryo_stages()
    stages[-1].frequency_drift_hz = 1e5
    chain = CryoChain(stages)
    assert chain.effective_frequency_drift_hz() == pytest.approx(1e5)

    faulted = CryoChain(
        stages,
        faults=FaultConfig(
            frequency_drift_hz=2e6,
            frequency_drift_enabled=True,
        ),
    )
    assert faulted.effective_frequency_drift_hz() == pytest.approx(1e5 + 2e6)

    # Other faults off: net gain unchanged vs baseline
    assert faulted.net_voltage_gain_db() == pytest.approx(chain.net_voltage_gain_db())


def test_iq_imbalance_and_adc_saturation_faults_toggle_independently() -> None:
    stages = [
        CryoStage(
            name="thru",
            temperature=0.015,
            attenuation_db=0.0,
            amp_gain_db=0.0,
            noise_temperature=0.0,
            cable_loss_db=0.0,
        )
    ]
    signal = np.array([1.0 + 1.0j, 3.0 + 0.0j])

    iq = CryoChain(
        stages,
        faults=FaultConfig(
            iq_gain_imbalance=0.5,
            iq_imbalance_enabled=True,
        ),
    ).apply(signal, bandwidth=1e6, rng=np.random.default_rng(0))
    assert iq[0].imag / iq[0].real == pytest.approx(0.5)

    sat = CryoChain(
        stages,
        faults=FaultConfig(
            adc_saturation_level=1.5,
            adc_saturation_enabled=True,
        ),
    ).apply(signal, bandwidth=1e6, rng=np.random.default_rng(0))
    assert sat[1].real == pytest.approx(1.5)
    assert sat[0].real == pytest.approx(1.0)
