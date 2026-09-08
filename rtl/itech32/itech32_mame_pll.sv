// SPDX-License-Identifier: GPL-2.0-or-later
// Second always-locked carrier used by SFTM's optional MAME timing profile.
`timescale 1ns/10ps

module itech32_mame_pll (
	input  wire refclk,
	input  wire reset,
	output wire outclk,
	output wire locked
);
	altera_pll #(
		.fractional_vco_multiplier("false"),
		.reference_clock_frequency("50.0 MHz"),
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
