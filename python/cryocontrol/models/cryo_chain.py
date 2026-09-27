"""Parameterized cryogenic RF chain: gain/loss stages + toggleable faults."""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from numpy.random import Generator
from numpy.typing import ArrayLike, NDArray

from cryocontrol.models.noise import add_amplifier_noise


def db_to_voltage_gain(gain_db: float) -> float:
    """Convert power gain in dB to a linear voltage scale factor."""
    return float(10.0 ** (gain_db / 20.0))


@dataclass
class CryoStage:
    """One temperature stage in the cryogenic / RF chain.

    All fields are parameters (not globals). Set ``enabled=False`` to remove
    the stage from the cascade (fault-injection / bypass).
    """

    name: str
    temperature: float  # K
    attenuation_db: float
    amp_gain_db: float
    noise_temperature: float  # K (0 = noiseless)
    cable_loss_db: float
    frequency_drift_hz: float = 0.0
    enabled: bool = True

    def voltage_gain_db(self) -> float:
        return self.amp_gain_db - self.attenuation_db - self.cable_loss_db


@dataclass
class FaultConfig:
    """Independently toggleable fault-injection hooks (ARCHITECTURE.md §3.6)."""

    gain_drift_db: float = 0.0
    gain_drift_enabled: bool = False

    noise_scale: float = 1.0
    noise_fault_enabled: bool = False

    frequency_drift_hz: float = 0.0
    frequency_drift_enabled: bool = False

    iq_gain_imbalance: float = 1.0  # multiplies Q relative to I
    iq_phase_imbalance_rad: float = 0.0
    iq_imbalance_enabled: bool = False

    adc_saturation_level: float = 1.0
    adc_saturation_enabled: bool = False


def default_cryo_stages() -> list[CryoStage]:
    """Default 300 K → 4 K → sub-K → ~15 mK device cascade (ARCHITECTURE §3.6)."""
    return [
        CryoStage(
            name="300K",
            temperature=300.0,
            attenuation_db=20.0,
            amp_gain_db=0.0,
            noise_temperature=0.0,
            cable_loss_db=1.0,
        ),
        CryoStage(
            name="4K",
            temperature=4.0,
            attenuation_db=10.0,
            amp_gain_db=40.0,
            noise_temperature=4.0,
            cable_loss_db=0.5,
        ),
        CryoStage(
            name="sub_K",
            temperature=0.1,
            attenuation_db=10.0,
            amp_gain_db=0.0,
            noise_temperature=0.0,
            cable_loss_db=0.5,
        ),
        CryoStage(
            name="device",
            temperature=0.015,
            attenuation_db=0.0,
            amp_gain_db=0.0,
            noise_temperature=0.0,
            cable_loss_db=0.0,
            frequency_drift_hz=0.0,
        ),
    ]


@dataclass
class CryoChain:
    """Cascade of parameterized cryo stages with optional fault injection."""

    stages: list[CryoStage]
    faults: FaultConfig = field(default_factory=FaultConfig)

    def enabled_stages(self) -> list[CryoStage]:
        return [s for s in self.stages if s.enabled]

    def net_voltage_gain_db(self) -> float:
        total = sum(s.voltage_gain_db() for s in self.enabled_stages())
        if self.faults.gain_drift_enabled:
            total += self.faults.gain_drift_db
        return float(total)

    def effective_frequency_drift_hz(self) -> float:
        total = sum(s.frequency_drift_hz for s in self.enabled_stages())
        if self.faults.frequency_drift_enabled:
            total += self.faults.frequency_drift_hz
        return float(total)

    def apply(
        self,
        signal: ArrayLike,
        bandwidth: float,
        resistance: float = 50.0,
        rng: Generator | None = None,
    ) -> NDArray:
        """Apply stage gain/loss (+ optional noise) and enabled fault effects."""
        if rng is None:
            rng = np.random.default_rng()
        out = np.asarray(signal, dtype=np.complex128).copy()

        noise_scale = (
            self.faults.noise_scale if self.faults.noise_fault_enabled else 1.0
        )

        for stage in self.enabled_stages():
            out = out * db_to_voltage_gain(stage.voltage_gain_db())
            t_noise = stage.noise_temperature * noise_scale
            if t_noise > 0.0:
                out = add_amplifier_noise(
                    out,
                    noise_temperature=t_noise,
                    bandwidth=bandwidth,
                    resistance=resistance,
                    rng=rng,
                )

        if self.faults.gain_drift_enabled:
            out = out * db_to_voltage_gain(self.faults.gain_drift_db)

        if self.faults.iq_imbalance_enabled:
            out = self._apply_iq_imbalance(out)

        if self.faults.adc_saturation_enabled:
            level = self.faults.adc_saturation_level
            out = np.clip(out.real, -level, level) + 1j * np.clip(
                out.imag, -level, level
            )

        return out

    def _apply_iq_imbalance(self, signal: NDArray) -> NDArray:
        amp = self.faults.iq_gain_imbalance
        phase = self.faults.iq_phase_imbalance_rad
        i = signal.real
        q = signal.imag * amp
        # rotate Q relative to I by phase imbalance
        q_rot = q * np.cos(phase) + i * np.sin(phase)
        return i + 1j * q_rot
