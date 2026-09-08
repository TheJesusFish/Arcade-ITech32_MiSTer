// SPDX-License-Identifier: GPL-2.0-or-later
// Unity-ratio transport PLL. It converts the reset-protected source selection
// back into a direct PLL output, as required by MiSTer's downstream HDMI and
// analog clock-control blocks. The 48 MHz nominal declaration also makes
// TimeQuest analyze the common domain at the faster of the two runtime rates.
`timescale 1ns/10ps

module itech32_transport_pll (
	input  wire refclk,
	input  wire reset,
	output wire outclk,
	output wire locked
);
	altera_pll #(
		.fractional_vco_multiplier("false"),
		.reference_clock_frequency("48.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(1),
		.output_clock_frequency0("48.0 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.pll_type("General"),
		.pll_subtype("General")
	) pll_i (
		.rst(reset),
		.outclk({outclk}),
		.locked(locked),
		.fboutclk(),
		.fbclk(1'b0),
		.refclk(refclk)
	);
endmodule
