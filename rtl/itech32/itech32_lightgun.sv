// SPDX-License-Identifier: GPL-3.0-or-later
// One light gun's aim point for Must Shoot TV, in visible-screen pixels.
//
// MAME's gun ports span the visible area exactly: X 0x1c-0x19b over 384
// columns and Y 0x00-0xff over 256 lines, so the board reads 0x1c + x and y.
// Relative aiming takes MiSTer mouse packets, the d-pad (constant speed) and
// the left stick (speed follows the deflection). Absolute aiming, for MiSTer
// light guns that report through the stick, maps the full stick range onto
// the screen.
`timescale 1ns/1ps

module itech32_lightgun (
	input  logic              clk,
	input  logic              reset,
	// Integration strobe, one clock wide (1600 Hz).
	input  logic              tick,
	input  logic              absolute_stick,
	input  logic              mouse_valid,
	input  logic signed [8:0] mouse_dx,   // PS/2: +X right
	input  logic signed [8:0] mouse_dy,   // PS/2: +Y up
	input  logic signed [7:0] stick_x,    // MiSTer: +X right
	input  logic signed [7:0] stick_y,    // MiSTer: +Y down
	input  logic [3:0]        dpad,       // {up, down, left, right}
	output logic [8:0]        x,          // 0..383
	output logic [7:0]        y           // 0..255
);
	// Positions carry four fraction bits. Widths are extended by
	// concatenation (Quartus 17 rejects some width casts).
	localparam logic signed [15:0] X_MAX = 16'sd6128;   // 383 * 16
	localparam logic signed [15:0] Y_MAX = 16'sd4080;   // 255 * 16
	// D-pad: 5/16 pixel per tick, 500 pixels a second at 1600 Hz.
	localparam logic signed [7:0] DPAD_STEP = 8'sd5;
	localparam logic [6:0] STICK_DEAD_ZONE = 7'd15;

	logic [12:0] x_q = 13'd3072;   // centre, 192 * 16
	logic [11:0] y_q = 12'd2048;   // centre, 128 * 16

	function automatic logic [15:0] clamp(input logic signed [15:0] value,
		input logic signed [15:0] max);
		clamp = value < 16'sd0 ? 16'd0 : (value > max ? max : value);
	endfunction

	// Stick speed: deflection / 16 sixteenths per tick, up to 7/16 pixel
	// (700 pixels a second); inside the dead zone the d-pad applies.
	function automatic logic signed [7:0] stick_step(input logic signed [7:0] value);
		logic [6:0] magnitude;
		begin
			magnitude = value[7] ? -value[6:0] : value[6:0];
			stick_step = magnitude <= STICK_DEAD_ZONE ? 8'sd0 : value >>> 4;
		end
	endfunction

	wire signed [7:0] stick_dx = stick_step(stick_x);
	wire signed [7:0] stick_dy = stick_step(stick_y);
	wire stick_centered = stick_dx == 8'sd0 && stick_dy == 8'sd0;
	wire signed [7:0] dpad_dx = dpad[0] ? DPAD_STEP : dpad[1] ? -DPAD_STEP : 8'sd0;
	wire signed [7:0] dpad_dy = dpad[2] ? DPAD_STEP : dpad[3] ? -DPAD_STEP : 8'sd0;
	wire signed [7:0] step_x = stick_centered ? dpad_dx : stick_dx;
	wire signed [7:0] step_y = stick_centered ? dpad_dy : stick_dy;

	wire signed [15:0] x_now = {3'b000, x_q};
	wire signed [15:0] y_now = {4'b0000, y_q};
	wire signed [15:0] mouse_x16 = {{3{mouse_dx[8]}}, mouse_dx, 4'b0000};
	wire signed [15:0] mouse_y16 = {{3{mouse_dy[8]}}, mouse_dy, 4'b0000};
	wire signed [15:0] step_x16 = {{8{step_x[7]}}, step_x};
	wire signed [15:0] step_y16 = {{8{step_y[7]}}, step_y};
	wire [15:0] mouse_x_next = clamp(x_now + mouse_x16, X_MAX);
	wire [15:0] mouse_y_next = clamp(y_now - mouse_y16, Y_MAX);
	wire [15:0] tick_x_next = clamp(x_now + step_x16, X_MAX);
	wire [15:0] tick_y_next = clamp(y_now + step_y16, Y_MAX);

	// Absolute: -128..127 spans the screen; 3/2 of the offset stick for X.
	wire [7:0] stick_x_offset = stick_x ^ 8'h80;
	wire [9:0] stick_abs_x3 = {2'b00, stick_x_offset} + {1'b0, stick_x_offset, 1'b0};
	wire [8:0] stick_abs_x = stick_abs_x3[9:1];
	wire [7:0] stick_abs_y = stick_y ^ 8'h80;

	always_ff @(posedge clk) begin
		if (reset) begin
			x_q <= 13'd3072;
			y_q <= 12'd2048;
		end else if (absolute_stick) begin
			x_q <= {stick_abs_x, 4'd0};
			y_q <= {stick_abs_y, 4'd0};
		end else if (mouse_valid) begin
			// One mouse count is one pixel.
			x_q <= mouse_x_next[12:0];
			y_q <= mouse_y_next[11:0];
		end else if (tick) begin
			x_q <= tick_x_next[12:0];
			y_q <= tick_y_next[11:0];
		end
	end

	assign x = x_q[12:4];
	assign y = y_q[11:4];
endmodule
