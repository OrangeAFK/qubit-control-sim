"""Validate the frozen Phase 4 AXI-Lite register map (no overlaps, required regs)."""

from __future__ import annotations

from cryocontrol.hardware.axi_lite_regs import (
    BASE_ADDR_TENTATIVE,
    FIXTURE_INTEGRATE_LENGTH,
    FIXTURE_INTEGRATE_START,
    MAP_SIZE_BYTES,
    REGS,
    REG_BY_NAME,
    REG_BY_OFFSET,
    REQUIRED_REG_NAMES,
    VERSION_RESET,
    MAGIC_RESET,
    CtrlBits,
    StatusBits,
    ResultMetaBits,
)


def test_offsets_word_aligned_and_unique() -> None:
    offsets = [r.offset for r in REGS]
    assert len(offsets) == len(set(offsets))
    for off in offsets:
        assert off % 4 == 0
        assert 0 <= off < MAP_SIZE_BYTES


def test_names_unique_and_required_present() -> None:
    names = [r.name for r in REGS]
    assert len(names) == len(set(names))
    for name in REQUIRED_REG_NAMES:
        assert name in REG_BY_NAME


def test_reg_by_offset_matches_regs() -> None:
    assert set(REG_BY_OFFSET) == {r.offset for r in REGS}
    for reg in REGS:
        assert REG_BY_OFFSET[reg.offset] is reg
        assert REG_BY_NAME[reg.name] is reg


def test_access_and_reset_contract() -> None:
    assert REG_BY_NAME["STATUS"].access == "ro"
    assert REG_BY_NAME["RESULT_I"].access == "ro"
    assert REG_BY_NAME["RESULT_Q"].access == "ro"
    assert REG_BY_NAME["RESULT_META"].access == "ro"
    assert REG_BY_NAME["PHASE_INC"].access == "rw"
    assert REG_BY_NAME["THRESHOLD"].access == "rw"

    assert REG_BY_NAME["INTEGRATE_START"].reset == FIXTURE_INTEGRATE_START
    assert REG_BY_NAME["INTEGRATE_LENGTH"].reset == FIXTURE_INTEGRATE_LENGTH
    assert REG_BY_NAME["VERSION"].reset == VERSION_RESET
    assert REG_BY_NAME["MAGIC"].reset == MAGIC_RESET
    assert REG_BY_NAME["DECIM_M"].reset == 4
    assert REG_BY_NAME["NUM_TAPS"].reset == 63


def test_bit_flags_do_not_collide() -> None:
    assert CtrlBits.SOFT_RST != CtrlBits.ARM != CtrlBits.CLR_DONE
    assert StatusBits.BUSY != StatusBits.DONE != StatusBits.OVERRUN != StatusBits.ARMED
    assert int(ResultMetaBits.DECISION) == 1


def test_tentative_base_and_aperture() -> None:
    assert BASE_ADDR_TENTATIVE == 0x43C0_0000
    assert MAP_SIZE_BYTES == 0x100
    # Last defined register fits with room before reserved FIR bank at 0x100.
    assert max(r.offset for r in REGS) + 4 <= MAP_SIZE_BYTES
