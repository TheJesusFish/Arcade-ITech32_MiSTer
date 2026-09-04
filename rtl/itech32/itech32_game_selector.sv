// SPDX-License-Identifier: GPL-3.0-or-later
// Persistent MRA board/revision selector. The selector is deliberately not
// reset by a MiSTer warm reset; every MRA load writes index 1 before its ROM.
`timescale 1ns/1ps

module itech32_game_selector (
	input  logic       clk,
	input  logic       write,
	input  logic [7:0] data,
	output logic       timekill_mode = 1'b0,
	output logic       bloodstorm_mode = 1'b0
);
	always_ff @(posedge clk) begin
		if (write) begin
			timekill_mode <= data == 8'h01;
			bloodstorm_mode <= data == 8'h02;
		end
	end
endmodule
