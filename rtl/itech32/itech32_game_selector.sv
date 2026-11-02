// SPDX-License-Identifier: GPL-3.0-or-later
// Persistent MRA board/revision selector. The selector is deliberately not
// reset by a MiSTer warm reset; every MRA load writes index 1 before its ROM.
// The decoded profile is registered so its fields reach the board as plain
// flip-flops; it settles one clock after the selector, while the loader still
// holds the board in reset.
`timescale 1ns/1ps

module itech32_game_selector
	import itech32_profile_pkg::*;
(
	input  logic           clk,
	input  logic           write,
	input  logic [7:0]     data,
	output board_profile_t profile
);
	logic [7:0] selector = SELECT_SFTM;

	always_ff @(posedge clk) begin
		if (write)
			selector <= data;
		profile <= profile_for_selector(selector);
	end
endmodule
