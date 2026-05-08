# SPDX-FileCopyrightText: © 2026 Jack Thoene
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


@cocotb.test()
async def test_reset_and_vga_runs(dut):
    """Reset the design, then confirm hsync and vsync both toggle."""
    dut._log.info("Start")

    # 25.175 MHz pixel clock => ~39.72 ns; round to 40 ns for sim.
    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # uio is fully unused; oe must be all-input.
    await ClockCycles(dut.clk, 1)
    assert dut.uio_oe.value == 0, f"uio_oe should be 0, got {int(dut.uio_oe.value):#04x}"
    assert dut.uio_out.value == 0, f"uio_out should be 0, got {int(dut.uio_out.value):#04x}"

    # Watch one full frame (~420k pixel-clocks for 800x525 timing).
    # Verify hsync (uo_out[7]) and vsync (uo_out[3]) both transition.
    hsync_seen_low  = False
    hsync_seen_high = False
    vsync_seen_low  = False
    vsync_seen_high = False

    for _ in range(420_000):
        await RisingEdge(dut.clk)
        h = (int(dut.uo_out.value) >> 7) & 1
        v = (int(dut.uo_out.value) >> 3) & 1
        hsync_seen_low  |= (h == 0)
        hsync_seen_high |= (h == 1)
        vsync_seen_low  |= (v == 0)
        vsync_seen_high |= (v == 1)
        if hsync_seen_low and hsync_seen_high and vsync_seen_low and vsync_seen_high:
            break

    assert hsync_seen_low and hsync_seen_high, "hsync did not toggle within one frame"
    assert vsync_seen_low and vsync_seen_high, "vsync did not toggle within one frame"
    dut._log.info("hsync and vsync both toggle — VGA timing alive")
