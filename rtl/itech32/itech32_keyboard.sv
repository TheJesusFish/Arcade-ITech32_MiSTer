// SPDX-License-Identifier: GPL-3.0-or-later
// MAME's default keyboard controls as two MiSTer joystick words.
//
// Main_MiSTer maps the keyboard to a joystick only when MiSTer.ini enables
// keyboard_as_joystick, so the core decodes hps_io's ps2_key itself and the
// top level ORs these words into joysticks 0 and 1. On trackball boards the
// arrow keys then move the ball, as the d-pad does.
//
// ps2_key: [10] toggles once per key event, [9] pressed, [8] 0xE0 extended,
// [7:0] PS/2 set-2 scancode. The toggle is edge-detected; it is not a level.
// Releases made while the OSD owns the keyboard never reach the core, so
// clear drops every held key.
`timescale 1ns/1ps

module itech32_keyboard (
	input  logic        clk,
	input  logic        reset,
	input  logic        clear,
	input  logic [10:0] ps2_key,
	// CONF_STR J order: R, L, D, U, B1..B6, Start, Coin.
	output logic [11:0] joystick_0,
	output logic [11:0] joystick_1
);
	logic toggle_q = 1'b0;
	logic [11:0] keys_0_q;
	logic [11:0] keys_1_q;

	wire event_valid = ps2_key[10] != toggle_q;
	wire pressed = ps2_key[9];

	// Player 1: arrows, Left Ctrl, Left Alt, Space, Left Shift, Z, X, 1, 5.
	// Player 2: G, D, F, R, A, S, Q, W, 2, 6 (MAME has no keys for its B5/B6).
	// Right Ctrl and Right Alt are the 0xE0 forms and stay unmapped.
	always_ff @(posedge clk) begin
		toggle_q <= ps2_key[10];
		if (reset || clear) begin
			keys_0_q <= 12'd0;
			keys_1_q <= 12'd0;
		end else if (event_valid) begin
			case (ps2_key[8:0])
				9'h174: keys_0_q[0]  <= pressed; // Right arrow
				9'h16b: keys_0_q[1]  <= pressed; // Left arrow
				9'h172: keys_0_q[2]  <= pressed; // Down arrow
				9'h175: keys_0_q[3]  <= pressed; // Up arrow
				9'h014: keys_0_q[4]  <= pressed; // Left Ctrl
				9'h011: keys_0_q[5]  <= pressed; // Left Alt
				9'h029: keys_0_q[6]  <= pressed; // Space
				9'h012: keys_0_q[7]  <= pressed; // Left Shift
				9'h01a: keys_0_q[8]  <= pressed; // Z
				9'h022: keys_0_q[9]  <= pressed; // X
				9'h016: keys_0_q[10] <= pressed; // 1
				9'h02e: keys_0_q[11] <= pressed; // 5
				9'h034: keys_1_q[0]  <= pressed; // G
				9'h023: keys_1_q[1]  <= pressed; // D
				9'h02b: keys_1_q[2]  <= pressed; // F
				9'h02d: keys_1_q[3]  <= pressed; // R
				9'h01c: keys_1_q[4]  <= pressed; // A
				9'h01b: keys_1_q[5]  <= pressed; // S
				9'h015: keys_1_q[6]  <= pressed; // Q
				9'h01d: keys_1_q[7]  <= pressed; // W
				9'h01e: keys_1_q[10] <= pressed; // 2
				9'h036: keys_1_q[11] <= pressed; // 6
				default: begin end
			endcase
		end
	end

	assign joystick_0 = keys_0_q;
	assign joystick_1 = keys_1_q;
endmodule
