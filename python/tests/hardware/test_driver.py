"""Tests for Phase 4 readout hardware driver (mock backend, no board)."""

from __future__ import annotations

import pytest

from cryocontrol.hardware.axi_lite_regs import (
    BASE_ADDR_TENTATIVE,
    FIXTURE_INTEGRATE_LENGTH,
    FIXTURE_INTEGRATE_START,
    FIXTURE_PHASE0,
    FIXTURE_PHASE_INC,
    FIXTURE_THRESHOLD_Q12_14,
    MAGIC_RESET,
    REG_BY_NAME,
    VERSION_RESET,
    CtrlBits,
    StatusBits,
)
from cryocontrol.hardware.driver import ReadoutConfig, ReadoutDriver
from cryocontrol.hardware.mock_backend import MockBackend
from cryocontrol.hardware.mmio_backend import ByteBufferBackend, MmioBackend
from cryocontrol.hardware.packing import (
    Q1_14_SCALE,
    float_to_q1_14,
    pack_iq_bytes,
    pack_iq_word,
    pack_iq_words,
    unpack_iq_word,
)


# ---------------------------------------------------------------------------
# Packing (ARCHITECTURE.md §3.3.1)
# ---------------------------------------------------------------------------


def test_pack_iq_word_layout_matches_architecture() -> None:
    # I in [15:0], Q in [31:16]
    i, q = 0x1234, 0x5678
    w = pack_iq_word(i, q)
    assert w == 0x5678_1234
    assert unpack_iq_word(w) == (i, q)


def test_pack_iq_word_signed_q1_14() -> None:
    i = -1  # 0xFFFF as u16
    q = -32768  # 0x8000
    w = pack_iq_word(i, q)
    assert w == 0x8000_FFFF
    assert unpack_iq_word(w) == (i, q)


def test_pack_iq_bytes_little_endian_dma_layout() -> None:
    words = pack_iq_words([1, 2], [3, 4])
    buf = pack_iq_bytes([1, 2], [3, 4])
    assert len(buf) == 8
    assert int.from_bytes(buf[0:4], "little") == words[0]
    assert int.from_bytes(buf[4:8], "little") == words[1]
    assert words[0] == pack_iq_word(1, 3)
    assert words[1] == pack_iq_word(2, 4)


def test_float_to_q1_14_round_trip_near_one() -> None:
    v = float_to_q1_14(1.0)
    assert v == Q1_14_SCALE
    assert unpack_iq_word(pack_iq_word(v, -v)) == (v, -v)


# ---------------------------------------------------------------------------
# Register offsets via driver
# ---------------------------------------------------------------------------


def test_driver_writes_config_at_frozen_offsets() -> None:
    be = MockBackend()
    drv = ReadoutDriver(be)
    cfg = ReadoutConfig(
        phase_inc=0x1111_2222,
        phase0=0x3333_4444,
        threshold=0x5555_6666,
        integrate_start=9,
        integrate_length=100,
    )
    drv.configure(cfg)

    assert be.read_u32(REG_BY_NAME["PHASE_INC"].offset) == 0x1111_2222
    assert be.read_u32(REG_BY_NAME["PHASE0"].offset) == 0x3333_4444
    assert be.read_u32(REG_BY_NAME["THRESHOLD"].offset) == 0x5555_6666
    assert be.read_u32(REG_BY_NAME["INTEGRATE_START"].offset) == 9
    assert be.read_u32(REG_BY_NAME["INTEGRATE_LENGTH"].offset) == 100

    # Offsets themselves match the frozen map constants from axi_lite_regs.
    assert REG_BY_NAME["PHASE_INC"].offset == 0x08
    assert REG_BY_NAME["PHASE0"].offset == 0x0C
    assert REG_BY_NAME["THRESHOLD"].offset == 0x10
    assert REG_BY_NAME["INTEGRATE_START"].offset == 0x14
    assert REG_BY_NAME["INTEGRATE_LENGTH"].offset == 0x18
    assert REG_BY_NAME["RESULT_I"].offset == 0x1C
    assert REG_BY_NAME["RESULT_Q"].offset == 0x20
    assert REG_BY_NAME["RESULT_META"].offset == 0x24
    assert REG_BY_NAME["IF_SAMPLE_COUNT"].offset == 0x38
    assert REG_BY_NAME["CTRL"].offset == 0x00
    assert REG_BY_NAME["STATUS"].offset == 0x04


def test_fixture_defaults_match_axi_lite_regs() -> None:
    cfg = ReadoutConfig()
    assert cfg.phase_inc == FIXTURE_PHASE_INC
    assert cfg.phase0 == FIXTURE_PHASE0
    assert cfg.threshold == FIXTURE_THRESHOLD_Q12_14
    assert cfg.integrate_start == FIXTURE_INTEGRATE_START
    assert cfg.integrate_length == FIXTURE_INTEGRATE_LENGTH


# ---------------------------------------------------------------------------
# Configure → push → inject → readback
# ---------------------------------------------------------------------------


def test_configure_push_inject_readback() -> None:
    be = MockBackend()
    drv = ReadoutDriver(be)

    drv.check_identity()
    assert drv.read_reg("MAGIC") == MAGIC_RESET
    assert drv.read_reg("VERSION") == VERSION_RESET

    i_s = [100, -200, 300]
    q_s = [-50, 60, -70]
    drv.run_acquisition(ReadoutConfig(), i_s, q_s)

    assert be.axis_words == pack_iq_words(i_s, q_s)
    assert drv.read_reg("IF_SAMPLE_COUNT") == 3
    status = drv.read_status()
    assert status & StatusBits.ARMED
    assert status & StatusBits.BUSY
    assert not (status & StatusBits.DONE)

    be.inject_results(0x0012_3456, -0x0000_00AB, decision=True, if_sample_count=3)

    assert drv.is_done()
    res = drv.read_results()
    assert res.result_i == 0x0012_3456
    assert res.result_q == -0x0000_00AB
    assert res.decision is True
    assert res.if_sample_count == 3
    assert res.done is True
    assert not (res.status & StatusBits.BUSY)
    assert not (res.status & StatusBits.ARMED)


def test_arm_pulses_ctrl_and_clears_done() -> None:
    be = MockBackend()
    drv = ReadoutDriver(be)
    be.inject_results(1, 2, decision=False)
    assert drv.is_done()

    drv.arm()
    assert not drv.is_done()
    assert drv.read_status() & StatusBits.ARMED
    # CTRL is W1P — readable as 0
    assert drv.read_reg("CTRL") == 0
    assert int(CtrlBits.ARM) == 1 << 1


def test_overrun_when_push_without_arm() -> None:
    be = MockBackend()
    drv = ReadoutDriver(be)
    drv.push_iq_q1_14([1], [2])
    assert drv.read_status() & StatusBits.OVERRUN


def test_soft_reset_clears_results_keeps_config() -> None:
    be = MockBackend()
    drv = ReadoutDriver(be)
    drv.configure(ReadoutConfig(phase_inc=0xDEAD_BEEF))
    be.inject_results(99, 88, decision=True)
    drv.soft_reset()
    assert drv.read_reg("PHASE_INC") == 0xDEAD_BEEF
    assert drv.read_reg("RESULT_I") == 0
    assert not drv.is_done()


def test_clear_done_only() -> None:
    be = MockBackend()
    drv = ReadoutDriver(be)
    be.inject_results(5, 6, decision=True)
    drv.clear_done()
    assert not drv.is_done()
    assert drv.read_reg("RESULT_I") == 5  # results retained


# ---------------------------------------------------------------------------
# MMIO stub
# ---------------------------------------------------------------------------


def test_mmio_backend_unmapped_raises() -> None:
    mmio = MmioBackend()
    assert mmio.base_addr == BASE_ADDR_TENTATIVE
    with pytest.raises(NotImplementedError):
        mmio.read_u32(0x34)


def test_mmio_backend_with_mapped_buffer() -> None:
    buf = bytearray(0x100)
    mmio = MmioBackend(mapped=buf)
    mmio.write_u32(REG_BY_NAME["PHASE_INC"].offset, 0xA5A5_5A5A)
    assert mmio.read_u32(0x08) == 0xA5A5_5A5A
    assert int.from_bytes(buf[0x08:0x0C], "little") == 0xA5A5_5A5A


def test_byte_buffer_backend_roundtrip() -> None:
    be = ByteBufferBackend()
    be.write_u32(0x10, 0x1122_3344)
    assert be.read_u32(0x10) == 0x1122_3344


def test_driver_rejects_write_to_ro() -> None:
    drv = ReadoutDriver(MockBackend())
    with pytest.raises(PermissionError):
        drv.write_reg("STATUS", 1)
