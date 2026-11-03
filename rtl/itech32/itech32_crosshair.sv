// SPDX-License-Identifier: GPL-3.0-or-later
// Light-gun crosshairs drawn over the board's RGB (Must Shoot TV).
//
// The aim points are in visible-screen pixels, so the overlay counts active
// pixels from the end of horizontal blanking and active lines from the end
// of vertical blanking; it needs no knowledge of the game-programmed raster.
// The RGB path gets no register: Time Killers' palette pipeline already uses
// five of the six clocks per pixel (Arcade-ITech32.sdc). The hit test is
// registered from the raster counters one clock into each pixel and holds
// through the mixer's sample at the next CE_PIXEL; only a 2:1 select sits in
// the RGB path, and with both guns disabled it always passes rgb_in.
`timescale 1ns/1ps

module itech32_crosshair (
	input  logic        clk,
	input  logic        ce_pixel,
	input  logic        hblank,
	input  logic        vblank,
	input  logic [23:0] rgb_in,
	input  logic [1:0]  enable,      // per gun
	input  logic [8:0]  gun1_x,
	input  logic [7:0]  gun1_y,
	input  logic [8:0]  gun2_x,
	input  logic [7:0]  gun2_y,
	output logic [23:0] rgb_out
);
	localparam logic [23:0] GUN1_COLOR = 24'hff2020;
	localparam logic [23:0] GUN2_COLOR = 24'h2090ff;
	// Arms reach six pixels from the aim point, leaving it clear.
	localparam logic [8:0] ARM = 9'd6;

	logic [8:0] column_q = 9'd0;
	logic [8:0] row_q = 9'd0;
	logic line_active_q = 1'b0;

	// column_q/row_q index the pixel now presented (valid while it is active).
	always_ff @(posedge clk) begin
		if (ce_pixel) begin
			column_q <= hblank ? 9'd0 : column_q + 9'd1;
			if (vblank) begin
				row_q <= 9'd0;
				line_active_q <= 1'b0;
			end else if (!hblank) begin
				line_active_q <= 1'b1;
			end else if (line_active_q) begin
				row_q <= row_q + 9'd1;
				line_active_q <= 1'b0;
			end
		end
	end

	function automatic logic near(input logic [8:0] a, input logic [8:0] b);
		near = (a >= b ? a - b : b - a) <= ARM;
	endfunction

	function automatic logic on_cross(input logic [8:0] x, input logic [8:0] y);
		logic dx_zero, dy_zero;
		begin
			dx_zero = column_q == x;
			dy_zero = row_q == y;
			on_cross = (dy_zero && near(column_q, x) && !dx_zero) ||
				(dx_zero && near(row_q, y) && !dy_zero);
		end
	endfunction

	wire active = !hblank && !vblank;
	wire hit1 = enable[0] && active && on_cross(gun1_x, {1'b0, gun1_y});
	wire hit2 = enable[1] && active && on_cross(gun2_x, {1'b0, gun2_y});

	logic hit1_q = 1'b0;
	logic hit2_q = 1'b0;
	always_ff @(posedge clk) begin
		hit1_q <= hit1;
		hit2_q <= hit2;
	end
	assign rgb_out = hit1_q ? GUN1_COLOR : hit2_q ? GUN2_COLOR : rgb_in;
endmodule
