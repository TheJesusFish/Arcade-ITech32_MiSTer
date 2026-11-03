// SPDX-License-Identifier: GPL-3.0-or-later
// One trackball for the ITech32 ROM-board trackball port.
//
// Board side: two 8-bit up/down position counters. Most boards read only the
// low four bits (MAME trackball_r: (Y << 4) | X); Golden Tee 3D's short ROM
// board reads all eight. Player side: a MiSTer mouse, an analog stick or the
// d-pad stands in for the ball. Their movement collects in a saturating
// per-axis accumulator in 1/16-count units and is released as single counts,
// at most one per release strobe.
//
// The release strobe bounds the count rate like a real ball's encoder. A
// 4-bit counter aliases past 7 counts between two reads by the game, so the
// release period must keep the game's longest read gap below 8 counts (127
// for 8-bit counters). The stick and d-pad integrate on the separate, fixed
// tick, so their speed does not depend on the release rate.
//
// Orientation follows MAME's ports: X is reversed (moving right decreases
// it) and Y decreases when the ball rolls forward, away from the player.
`timescale 1ns/1ps

module itech32_trackball (
	input  logic              clk,
	input  logic              reset,
	// Low holds the counters and discards input (no trackball on this board).
	input  logic              enable,
	// Stick/d-pad integration strobe, one clock wide.
	input  logic              tick,
	// Count-release strobe, one clock wide.
	input  logic              release_tick,
	// Movement gain: 0..3 = 25%, 50%, 100%, 200% (MAME's default is 25%).
	input  logic [1:0]        speed,
	// One clock per MiSTer mouse packet. PS/2 deltas: +X right, +Y forward.
	input  logic              mouse_valid,
	input  logic signed [8:0] mouse_dx,
	input  logic signed [8:0] mouse_dy,
	// MiSTer left stick, -127..127: +X right, +Y toward the player.
	input  logic signed [7:0] stick_x,
	input  logic signed [7:0] stick_y,
	// MiSTer d-pad {up, down, left, right}, used while the stick is centered.
	input  logic [3:0]        dpad,
	output logic [7:0]        count_x,
	output logic [7:0]        count_y
);
	// Pending movement in 1/16 counts. +-1023 holds 64 counts (about 40 ms at
	// the fastest release), so a hard flick ends promptly once the ball stops.
	localparam int PENDING_W = 12;
	localparam logic signed [PENDING_W-1:0] PENDING_MAX = 12'sd1023;
	localparam logic signed [PENDING_W-1:0] PENDING_MIN = -12'sd1023;
	localparam logic signed [PENDING_W-1:0] ONE_COUNT = 12'sd16;
	// Widths are extended explicitly by concatenation (Quartus 17 rejects a
	// negated width cast). Sums need 18 bits: a 12-bit pending value plus a
	// 15-bit mouse step.
	localparam logic signed [17:0] SUM_MAX = 18'sd1023;
	localparam logic signed [17:0] SUM_MIN = -18'sd1023;
	localparam logic signed [17:0] SUM_ONE = 18'sd16;
	// Stick magnitudes inside this are treated as centered.
	localparam logic [6:0] STICK_DEAD_ZONE = 7'd15;
	// D-pad stands in for a three-quarter stick deflection.
	localparam logic signed [7:0] DPAD_RATE = 8'sd96;

	logic signed [PENDING_W-1:0] pending_x_q, pending_y_q;
	logic signed [PENDING_W-1:0] pending_x_d, pending_y_d;

	// Signed magnitude of one stick axis after the dead zone, or the d-pad.
	function automatic logic signed [7:0] axis_rate(input logic signed [7:0] stick,
		input logic positive, input logic negative);
		logic signed [7:0] negated;
		logic [6:0] magnitude;
		begin
			negated = -stick;
			magnitude = stick[7] ? negated[6:0] : stick[6:0];
			if (magnitude > STICK_DEAD_ZONE)
				axis_rate = stick;
			else if (positive && !negative)
				axis_rate = DPAD_RATE;
			else if (negative && !positive)
				axis_rate = -DPAD_RATE;
			else
				axis_rate = 8'sd0;
		end
	endfunction

	// Mouse: one mickey is 4 << speed sixteenths (25% = a quarter count).
	function automatic logic signed [17:0] mouse_step(input logic signed [8:0] delta,
		input logic [1:0] gain);
		logic signed [17:0] wide;
		begin
			wide = {{9{delta[8]}}, delta};
			mouse_step = wide <<< ({1'b0, gain} + 3'd2);
		end
	endfunction

	// Stick: (|rate| << speed) / 16 sixteenths per tick, sign restored after
	// the divide so both directions move equally; full deflection at 25%
	// gives roughly 0.44 counts per tick.
	function automatic logic signed [17:0] stick_step(input logic signed [7:0] rate,
		input logic [1:0] gain);
		logic signed [7:0] negated;
		logic [10:0] magnitude;
		logic signed [17:0] wide;
		begin
			negated = -rate;
			magnitude = {3'd0, rate[7] ? negated : rate};
			magnitude = (magnitude << gain) >> 4;
			wide = {7'd0, magnitude};
			stick_step = rate[7] ? -wide : wide;
		end
	endfunction

	function automatic logic signed [17:0] extend_pending(
		input logic signed [PENDING_W-1:0] value);
		extend_pending = {{(18 - PENDING_W){value[PENDING_W-1]}}, value};
	endfunction

	function automatic logic signed [PENDING_W-1:0] saturate(input logic signed [17:0] value);
		if (value > SUM_MAX)
			saturate = PENDING_MAX;
		else if (value < SUM_MIN)
			saturate = PENDING_MIN;
		else
			saturate = value[PENDING_W-1:0];
	endfunction

	logic signed [7:0] rate_x, rate_y;
	logic step_x_up, step_x_down, step_y_up, step_y_down;
	logic signed [17:0] sum_x, sum_y;

	always_comb begin
		rate_x = axis_rate(stick_x, dpad[0], dpad[1]);
		rate_y = axis_rate(stick_y, dpad[2], dpad[3]);

		// One count leaves per release strobe once a whole count is pending.
		step_x_up   = release_tick && pending_x_q >= ONE_COUNT;
		step_x_down = release_tick && pending_x_q <= -ONE_COUNT;
		step_y_up   = release_tick && pending_y_q >= ONE_COUNT;
		step_y_down = release_tick && pending_y_q <= -ONE_COUNT;

		sum_x = extend_pending(pending_x_q);
		sum_y = extend_pending(pending_y_q);
		if (step_x_up)   sum_x = sum_x - SUM_ONE;
		if (step_x_down) sum_x = sum_x + SUM_ONE;
		if (step_y_up)   sum_y = sum_y - SUM_ONE;
		if (step_y_down) sum_y = sum_y + SUM_ONE;
		// Port X is reversed; port Y falls as the ball rolls forward.
		if (mouse_valid) begin
			sum_x = sum_x - mouse_step(mouse_dx, speed);
			sum_y = sum_y - mouse_step(mouse_dy, speed);
		end
		if (tick) begin
			sum_x = sum_x - stick_step(rate_x, speed);
			sum_y = sum_y + stick_step(rate_y, speed);
		end

		pending_x_d = saturate(sum_x);
		pending_y_d = saturate(sum_y);
	end

	always_ff @(posedge clk) begin
		if (reset || !enable) begin
			pending_x_q <= '0;
			pending_y_q <= '0;
		end else begin
			pending_x_q <= pending_x_d;
			pending_y_q <= pending_y_d;
		end
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			count_x <= 8'd0;
			count_y <= 8'd0;
		end else if (enable) begin
			if (step_x_up)        count_x <= count_x + 8'd1;
			else if (step_x_down) count_x <= count_x - 8'd1;
			if (step_y_up)        count_y <= count_y + 8'd1;
			else if (step_y_down) count_y <= count_y - 8'd1;
		end
	end

endmodule
