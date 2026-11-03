// SPDX-License-Identifier: GPL-3.0-or-later
// MiSTer controller mapping onto the ITech32 board input ports; the wiring
// follows the board profile's input layout.
`timescale 1ns/1ps

module itech32_inputs
	import itech32_profile_pkg::*;
#(
	parameter int CLK_HZ = 47_727_273
)
(
	input  logic        clk,
	input  logic        reset,
	input  board_profile_t profile,
	input  logic [11:0] joystick_0,
	input  logic [11:0] joystick_1,
	input  logic [11:0] joystick_2,
	input  logic [11:0] joystick_3,
	// MiSTer left sticks for players 1/2: [15:8] Y, [7:0] X, signed.
	input  logic [15:0] analog_0,
	input  logic [15:0] analog_1,
	// hps_io ps2_mouse: [24] toggles per packet, PS/2 flags/X/Y bytes.
	input  logic [24:0] ps2_mouse,
	// Discard mouse packets (the OSD owns the input).
	input  logic        mouse_ignore,
	input  logic [1:0]  trackball_speed,
	input  logic        service_button,
	input  logic        vblank,
	input  logic        sound_special,
	// Direct MAME DIP values: bit 0 -> mask 0x00100000 (SW1:4),
	// through bit 3 -> mask 0x00800000 (SW1:1).
	input  logic [7:0]  dip_switches,
	output logic [31:0] input_p1,
	output logic [31:0] input_p2,
	output logic [31:0] input_p3,
	output logic [31:0] input_p4,
	output logic [31:0] input_dips,
	output logic [31:0] input_extra,
	// Trackball ports, (Y << 4) | X.
	output logic [7:0]  trackball1,
	output logic [7:0]  trackball2
);
	logic [11:0] joystick_0_q;
	logic [11:0] joystick_1_q;
	logic [11:0] joystick_2_q;
	logic [11:0] joystick_3_q;

	// hps_io and OSD ownership are clk-domain signals, but their live decode
	// previously reached the main CPU read path in one combinational cone.
	// Snapshot the complete controller payload at the board boundary. OSD-open
	// zeroes supplied by the top therefore become a stable released state on
	// the next fabric edge, while Service remains an independent menu action.
	always_ff @(posedge clk) begin
		if (reset) begin
			joystick_0_q <= 12'd0;
			joystick_1_q <= 12'd0;
			joystick_2_q <= 12'd0;
			joystick_3_q <= 12'd0;
		end else begin
			joystick_0_q <= joystick_0[11:0];
			joystick_1_q <= joystick_1[11:0];
			joystick_2_q <= joystick_2[11:0];
			joystick_3_q <= joystick_3[11:0];
		end
	end

	// Trackball count release: 1600 Hz keeps a 3.8 ms read gap (MAME's 3.5 ms
	// longest World Class Bowling gap, stretched to this core's frame rate)
	// at six counts, inside the 4-bit counters' +-7 reach.
	localparam int TICK_CYCLES = CLK_HZ / 1600;
	localparam int TICK_W = $clog2(TICK_CYCLES);
	localparam logic [31:0] TICK_LAST = TICK_CYCLES - 1;
	logic [TICK_W-1:0] tick_count_q;
	logic trackball_tick;
	logic mouse_toggle_q;
	logic mouse_valid;
	logic [3:0] tb1_x, tb1_y, tb2_x, tb2_y;

	always_ff @(posedge clk) begin
		if (reset || trackball_tick)
			tick_count_q <= '0;
		else
			tick_count_q <= tick_count_q + 1'b1;
		mouse_toggle_q <= ps2_mouse[24];
	end
	assign trackball_tick = tick_count_q == TICK_LAST[TICK_W-1:0];
	// The toggle is tracked even while ignored, so no stale packet replays.
	assign mouse_valid = (ps2_mouse[24] != mouse_toggle_q) && !mouse_ignore && !reset;

	// Player 1's ball takes the mouse, stick and d-pad; player 2's the second
	// controller's stick and d-pad. The d-pad only moves a ball on boards
	// that have one.
	itech32_trackball trackball_p1 (
		.clk(clk), .reset(reset),
		.enable(profile.trackball != TRACKBALL_NONE),
		.tick(trackball_tick), .speed(trackball_speed),
		.mouse_valid(mouse_valid),
		.mouse_dx({ps2_mouse[4], ps2_mouse[15:8]}),
		.mouse_dy({ps2_mouse[5], ps2_mouse[23:16]}),
		.stick_x(analog_0[7:0]), .stick_y(analog_0[15:8]),
		.dpad(joystick_0_q[3:0]),
		.count_x(tb1_x), .count_y(tb1_y)
	);

	itech32_trackball trackball_p2 (
		.clk(clk), .reset(reset),
		.enable(profile.trackball == TRACKBALL_TWO),
		.tick(trackball_tick), .speed(trackball_speed),
		.mouse_valid(1'b0), .mouse_dx(9'sd0), .mouse_dy(9'sd0),
		.stick_x(analog_1[7:0]), .stick_y(analog_1[15:8]),
		.dpad(joystick_1_q[3:0]),
		.count_x(tb2_x), .count_y(tb2_y)
	);

	assign trackball1 = {tb1_y, tb1_x};
	assign trackball2 = {tb2_y, tb2_x};

	// MiSTer joystick ordering follows the CONF_STR J field: directions in
	// bits 0..3, then B1..B6 in 4..9, Start 10 and Coin 11.

	// MAME itech32_base_16bit player byte, active low: Coin, Start, B1, then
	// the game's bit-3 control, Right, Left, Down, Up.
	function automatic logic [7:0] player_16bit(input logic [11:0] joystick,
		input logic bit3, input logic coin);
		player_16bit = ~{joystick[3:0], bit3, joystick[4], joystick[10], coin};
	endfunction

	always_comb begin
		input_p1 = 32'd0;
		input_p2 = 32'd0;
		input_p3 = 32'd0;
		input_extra = 32'd0;
		input_p4 = 32'd0;
		input_dips = 32'd0;

		if (profile.input_layout == INPUTS_TIMEKILL) begin
			// The 68000 reads these as 16-bit words.  Board signals occupy the
			// low byte and the unused high byte is pulled up.
			input_p1[31:16] = {
				8'hff,
				~joystick_0_q[3], ~joystick_0_q[2],
				~joystick_0_q[1], ~joystick_0_q[0],
				~joystick_0_q[7], ~joystick_0_q[6],
				~joystick_0_q[5], ~joystick_0_q[4]
			};
			input_p2[31:16] = {
				8'hff,
				~joystick_1_q[3], ~joystick_1_q[2],
				~joystick_1_q[1], ~joystick_1_q[0],
				~joystick_1_q[7], ~joystick_1_q[6],
				~joystick_1_q[5], ~joystick_1_q[4]
			};
			input_p3[31:16] = {
				8'hff,
				1'b1, ~joystick_1_q[10], ~joystick_1_q[11],
				~joystick_1_q[8], 1'b1, ~joystick_0_q[10],
				~joystick_0_q[11], ~joystick_0_q[8]
			};
			input_p4[31:16] = 16'hffff;
			input_dips[31:16] = {
				8'hff,
				dip_switches[7:4], sound_special,
				~vblank, ~service_button, ~dip_switches[0]
			};
		end else if (profile.input_layout == INPUTS_BLOODSTORM ||
			profile.input_layout == INPUTS_HARDYARD ||
			profile.input_layout == INPUTS_PAIRS ||
			profile.input_layout == INPUTS_WCBOWL) begin
			// The bloodstm board's 16-bit ports have zero upper bytes. MiSTer
			// B1..B5 are MAME BUTTON1..5; Start/Coin stay in slots 10/11.
			// Unused P3 reads 0x00, unused P4/EXTRA read 0xff.
			input_p4[23:16] = 8'hff;
			input_extra[23:16] = 8'hff;
			input_dips[23:16] = {dip_switches[3:0], sound_special,
				~vblank, 1'b1, ~service_button};
			case (profile.input_layout)
				INPUTS_HARDYARD: begin
					// Players 3/4 have no coin input; their bit 0 is unused.
					input_p1[23:16] = player_16bit(joystick_0_q, joystick_0_q[5], joystick_0_q[11]);
					input_p2[23:16] = player_16bit(joystick_1_q, joystick_1_q[5], joystick_1_q[11]);
					input_p3[23:16] = player_16bit(joystick_2_q, joystick_2_q[5], 1'b0);
					input_p4[23:16] = player_16bit(joystick_3_q, joystick_3_q[5], 1'b0);
				end
				INPUTS_PAIRS: begin
					input_p1[23:16] = player_16bit(joystick_0_q, 1'b0, joystick_0_q[11]);
					input_p2[23:16] = player_16bit(joystick_1_q, 1'b0, joystick_1_q[11]);
				end
				INPUTS_WCBOWL: begin
					// Hook Left/Right on B1/B2; bits 4..7 are unused (the
					// d-pad drives the trackball instead).
					input_p1[23:16] = player_16bit({joystick_0_q[11:4], 4'd0},
						joystick_0_q[5], joystick_0_q[11]);
					input_p2[23:16] = player_16bit({joystick_1_q[11:4], 4'd0},
						joystick_1_q[5], joystick_1_q[11]);
				end
				default: begin
					// BloodStorm: B3 on bit 3, B2/B4/B5 on the EXTRA port.
					input_p1[23:16] = player_16bit(joystick_0_q, joystick_0_q[6], joystick_0_q[11]);
					input_p2[23:16] = player_16bit(joystick_1_q, joystick_1_q[6], joystick_1_q[11]);
					input_extra[23:16] = {2'b11, ~joystick_1_q[8], ~joystick_0_q[8],
						~joystick_1_q[7], ~joystick_0_q[7], ~joystick_1_q[5], ~joystick_0_q[5]};
				end
			endcase
		end else if (profile.input_layout == INPUTS_SHUFFLE_BOWL) begin
			// 68EC020 Shuffleshot/World Class Bowling: Zoom/Wax or Hook
			// Left/Right on B1/B2, bits 4..7 unused (the d-pad drives the
			// trackball); P3 holds only an unmapped third coin. DIPS and P4
			// follow the SFTM board.
			input_p1[23:16] = player_16bit({joystick_0_q[11:4], 4'd0},
				joystick_0_q[5], joystick_0_q[11]);
			input_p2[23:16] = player_16bit({joystick_1_q[11:4], 4'd0},
				joystick_1_q[5], joystick_1_q[11]);
			input_p3[23:16] = 8'hff;
			input_p4[23:16] = 8'hff;
			input_dips[23:16] = {dip_switches[3:0], ~sound_special,
				~vblank, 1'b1, ~service_button};
		end else begin
			input_p1[16] = ~joystick_0_q[11];
			input_p1[17] = ~joystick_0_q[10];
			input_p1[18] = ~joystick_0_q[4];
			input_p1[19] = ~joystick_0_q[5];
			input_p1[20] = ~joystick_0_q[0];
			input_p1[21] = ~joystick_0_q[1];
			input_p1[22] = ~joystick_0_q[2];
			input_p1[23] = ~joystick_0_q[3];

			input_p2[16] = ~joystick_1_q[11];
			input_p2[17] = ~joystick_1_q[10];
			input_p2[18] = ~joystick_1_q[4];
			input_p2[19] = ~joystick_1_q[5];
			input_p2[20] = ~joystick_1_q[0];
			input_p2[21] = ~joystick_1_q[1];
			input_p2[22] = ~joystick_1_q[2];
			input_p2[23] = ~joystick_1_q[3];

			input_p3[16] = ~joystick_0_q[6];
			input_p3[17] = ~joystick_1_q[6];
			input_p3[18] = ~joystick_0_q[7];
			input_p3[19] = ~joystick_1_q[7];
			input_p3[20] = ~joystick_0_q[8];
			input_p3[21] = ~joystick_1_q[8];
			input_p3[22] = ~joystick_0_q[9];
			input_p3[23] = ~joystick_1_q[9];
			input_p4[23:16] = 8'hff;

			input_dips[16] = ~service_button;
			input_dips[17] = 1'b1;
			input_dips[18] = ~vblank;
			input_dips[19] = ~sound_special;
			input_dips[23:20] = dip_switches[3:0];
		end
	end

endmodule
