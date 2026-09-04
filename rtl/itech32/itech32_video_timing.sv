// SPDX-License-Identifier: GPL-2.0-or-later
// Register-driven raster timing for the ITech32 framebuffer platform.
`timescale 1ns/1ps

module itech32_video_timing (
	input  logic        clk,
	input  logic        reset,
	input  logic        ce_pixel,
	input  logic [9:0]  htotal,
	input  logic [9:0]  hblank_start,
	input  logic [9:0]  hblank_end,
	input  logic [9:0]  hsync_start,
	input  logic [9:0]  vtotal,
	input  logic [9:0]  vblank_start,
	input  logic [9:0]  vblank_end,
	input  logic [9:0]  vsync_start,
	output logic [9:0]  hpos,
	output logic [9:0]  vpos,
	output logic        hblank,
	output logic        vblank,
	output logic        hsync,
	output logic        vsync
);
	// The IT graphics ASIC exposes sync start positions but no programmable
	// widths.  The horizontal register geometry used by SFTM is consistent with
	// a fixed 32-pixel (4 us at the native 8 MHz pixel rate) negative pulse at
	// the JAMMA edge.  Vertical sync is the fixed four-line interval already
	// used by the board programming.  MiSTer expects these internal signals
	// active-high and performs the physical analog inversion in sys_top.
	localparam logic [9:0] HSYNC_WIDTH = 10'd32;
	localparam logic [9:0] VSYNC_WIDTH = 10'd4;

	// Sync pulse endpoints are programming-time values, not raster-time math.
	// Keep this explicit local stage so the distributed register bank cannot feed
	// start+width/wrap arithmetic and both interval comparators in one cycle.
	logic [9:0] hsync_start_q, hsync_end_q;
	logic [9:0] vsync_start_q, vsync_end_q;

	function automatic logic interval_contains(
		input logic [9:0] position,
		input logic [9:0] first,
		input logic [9:0] last
	);
		if (first > last)
			interval_contains = (position >= first) || (position < last);
		else
			interval_contains = (position >= first) && (position < last);
	endfunction

	function automatic logic [9:0] sync_end_after_width(
		input logic [9:0] first,
		input logic [9:0] total,
		input logic [9:0] width
	);
		logic [10:0] endpoint;
		begin
			endpoint = {1'b0, first} + {1'b0, width};
			if (endpoint >= {1'b0, total})
				endpoint = endpoint - {1'b0, total};
			sync_end_after_width = endpoint[9:0];
		end
	endfunction

	// Capture start and its wrapped endpoint atomically.  This also runs while
	// raster reset is asserted, so stable programmed timing is already primed on
	// the first visible raster edge. A live programming change takes effect here
	// exactly one fabric clock after it reaches this module.
	always_ff @(posedge clk) begin
		hsync_start_q <= hsync_start;
		hsync_end_q   <= sync_end_after_width(hsync_start, htotal,
			HSYNC_WIDTH);
		vsync_start_q <= vsync_start;
		vsync_end_q   <= sync_end_after_width(vsync_start, vtotal,
			VSYNC_WIDTH);
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			hpos <= 10'd0;
			vpos <= 10'd0;
		end else if (ce_pixel) begin
			if (hpos == htotal - 1'd1) begin
				hpos <= 10'd0;
				if (vpos == vtotal - 1'd1)
					vpos <= 10'd0;
				else
					vpos <= vpos + 1'd1;
			end else begin
				hpos <= hpos + 1'd1;
			end
		end
	end

	always_comb begin
		hblank = interval_contains(hpos, hblank_start, hblank_end);
		vblank = interval_contains(vpos, vblank_start, vblank_end);
		hsync = interval_contains(hpos, hsync_start_q, hsync_end_q);
		vsync = interval_contains(vpos, vsync_start_q, vsync_end_q);
	end

endmodule
