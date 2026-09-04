// SPDX-License-Identifier: GPL-3.0-or-later
// Frame-latched CRT sync repositioner derived from JTFRAME jtframe_resync.
// Original author: Jose Tejada Gomez (Jotego), 2019.
// https://github.com/jotego/jtcores/blob/master/modules/jtframe/hdl/video/jtframe_resync.v
// Modified for ITech32; see CREDITS.md and LICENSE for attribution and terms.
`timescale 1ns/1ps

module itech32_video_resync (
	input  logic              clk,
	input  logic              ce_pixel,
	input  logic              hsync_in,
	input  logic              vsync_in,
	input  logic              hblank_in,
	input  logic              vblank_in,
	input  logic signed [5:0] h_offset,
	input  logic signed [5:0] v_offset,
	output logic              hsync_out,
	output logic              vsync_out
);
	localparam integer COUNT_WIDTH = 10;

	logic hblank_d = 1'b1;
	logic vblank_d = 1'b1;
	logic hsync_d = 1'b0;
	logic vsync_d = 1'b0;

	wire active_line_start = hblank_d && !hblank_in;
	wire active_frame_start = vblank_d && !vblank_in;
	wire active_frame_end = !vblank_d && vblank_in;
	wire hsync_rise = hsync_in && !hsync_d;
	wire hsync_fall = !hsync_in && hsync_d;
	wire vsync_rise = vsync_in && !vsync_d;
	wire vsync_fall = !vsync_in && vsync_d;

	logic [COUNT_WIDTH-1:0] h_count = '0;
	logic [COUNT_WIDTH-1:0] v_count = '0;
	logic [COUNT_WIDTH-1:0] h_total = '0;
	logic [COUNT_WIDTH-1:0] v_total = '0;
	logic line_seen = 1'b0;
	logic frame_seen = 1'b0;
	logic totals_valid = 1'b0;

	logic [COUNT_WIDTH-1:0] measured_hsync_pos = '0;
	logic [COUNT_WIDTH-1:0] measured_hsync_width = '0;
	logic [COUNT_WIDTH-1:0] measured_vsync_hpos = '0;
	logic [COUNT_WIDTH-1:0] measured_vsync_vpos = '0;
	logic [COUNT_WIDTH-1:0] measured_vsync_width = '0;
	// (a) Retain the image height from VBlank entry until the next frame latch.
	// Zero means that no complete active interval has been observed yet.
	logic [COUNT_WIDTH-1:0] measured_active_height = '0;
	logic hsync_valid = 1'b0;
	logic vsync_valid = 1'b0;

	function automatic logic [COUNT_WIDTH-1:0] wrap_offset(
		input logic [COUNT_WIDTH-1:0] position,
		input logic signed [5:0] offset,
		input logic [COUNT_WIDTH-1:0] total
	);
		logic signed [COUNT_WIDTH+1:0] adjusted;
		logic signed [COUNT_WIDTH+1:0] signed_total;
		logic signed [COUNT_WIDTH+1:0] wrapped;
		begin
			adjusted = $signed({2'b00, position}) +
				$signed({{(COUNT_WIDTH-4){offset[5]}}, offset});
			signed_total = $signed({2'b00, total});
			if (adjusted < 0)
				wrapped = adjusted + signed_total;
			else if (adjusted >= signed_total)
				wrapped = adjusted - signed_total;
			else
				wrapped = adjusted;
			wrap_offset = wrapped[COUNT_WIDTH-1:0];
		end
	endfunction

	function automatic logic [COUNT_WIDTH-1:0] bounded_vsync_position(
		input logic [COUNT_WIDTH-1:0] position,
		input logic signed [5:0] offset,
		input logic [COUNT_WIDTH-1:0] active_height,
		input logic [COUNT_WIDTH-1:0] total,
		input logic [COUNT_WIDTH-1:0] pulse_width
	);
		logic signed [COUNT_WIDTH+1:0] adjusted;
		logic [COUNT_WIDTH-1:0] last_start;
		begin
			adjusted = $signed({2'b00, position}) +
				$signed({{(COUNT_WIDTH-4){offset[5]}}, offset});
			last_start = '0;
			bounded_vsync_position = position;
			if (total > pulse_width && pulse_width != 10'd0) begin
				last_start = total - pulse_width;
				if (active_height != 10'd0 && active_height <= last_start) begin
					if (adjusted < $signed({2'b00, active_height}))
						bounded_vsync_position = active_height;
					else if (adjusted > $signed({2'b00, last_start}))
						bounded_vsync_position = last_start;
					else
						bounded_vsync_position = adjusted[COUNT_WIDTH-1:0];
				end
			end
		end
	endfunction

	function automatic logic [COUNT_WIDTH-1:0] preceding_position(
		input logic [COUNT_WIDTH-1:0] position,
		input logic [COUNT_WIDTH-1:0] total
	);
		begin
			preceding_position = position == '0 ? total - 10'd1
				: position - 10'd1;
		end
	endfunction

	logic signed [5:0] h_offset_latched = 6'sd0;
	logic signed [5:0] v_offset_latched = 6'sd0;
	logic [COUNT_WIDTH-1:0] hsync_trip = '0;
	logic [COUNT_WIDTH-1:0] vsync_htrip = '0;
	logic [COUNT_WIDTH-1:0] vsync_vtrip = '0;
	logic geometry_valid = 1'b0;

	logic hsync_generated = 1'b0;
	logic vsync_generated = 1'b0;
	logic [COUNT_WIDTH-1:0] hsync_hold = '0;
	logic [COUNT_WIDTH-1:0] vsync_hold = '0;

	// Zero is a literal combinational bypass, preserving the accepted video
	// boundary exactly. Nonzero controls select the learned, frame-latched
	// generator; the mux is one bit wide and remains outside the RGB path.
	always_comb begin
		hsync_out = (!geometry_valid || h_offset_latched == 6'sd0)
			? hsync_in : hsync_generated;
		vsync_out = (!geometry_valid ||
			(h_offset_latched == 6'sd0 && v_offset_latched == 6'sd0))
			? vsync_in : vsync_generated;
	end

	// The v_count origin is the active-frame edge, not native raster row zero.
	// At VBlank entry it counts exactly the original visible rows. Keep this
	// measurement separate from the pixel/sync generators: no image latency.
	always_ff @(posedge clk) begin
		if (ce_pixel && active_frame_end)
			measured_active_height <= frame_seen ? v_count : 10'd0;
	end

	// All measurement and output state advances on the source pixel enable.
	// Position arithmetic is captured once per frame; the per-pixel path is
	// limited to counters, equality compares, and small hold counters.
	always_ff @(posedge clk) begin
		if (ce_pixel) begin
			hblank_d <= hblank_in;
			vblank_d <= vblank_in;
			hsync_d <= hsync_in;
			vsync_d <= vsync_in;

			if (active_line_start) begin
				if (line_seen)
					h_total <= h_count + 10'd1;
				h_count <= '0;
				line_seen <= 1'b1;
			end else begin
				h_count <= h_count + 10'd1;
			end

			if (active_frame_start) begin
				if (frame_seen) begin
					v_total <= v_count;
					totals_valid <= line_seen && h_total != 10'd0 &&
						v_count != 10'd0;
				end
				v_count <= '0;
				frame_seen <= 1'b1;

				h_offset_latched <= h_offset;
				v_offset_latched <= v_offset;
				if (totals_valid && hsync_valid && vsync_valid) begin
					// Edge detection observes the source transition on one CE and
					// the registered generator changes after its compare CE. Move
					// the trip one position earlier so the requested signed offset
					// is exact rather than offset+1.
					hsync_trip <= preceding_position(
						wrap_offset(measured_hsync_pos, h_offset, h_total),
						h_total);
					vsync_htrip <= preceding_position(
						wrap_offset(measured_vsync_hpos, h_offset, h_total),
						h_total);
					// A VS edge inside the picture puts its last rows at the top
					// of a VS-framed sink. Saturate only vertical positioning so
					// the complete pulse fits between the last and first DE rows.
					// Apply the same bounded offset while the period settles;
					// switching via native phase adds an avoidable short frame.
					vsync_vtrip <= bounded_vsync_position(
						measured_vsync_vpos, v_offset, measured_active_height,
						v_total, measured_vsync_width);
					geometry_valid <= 1'b1;
				end
			end else if (active_line_start) begin
				v_count <= v_count + 10'd1;
			end

			if (hsync_rise)
				measured_hsync_pos <= h_count;
			if (hsync_fall) begin
				measured_hsync_width <= h_count - measured_hsync_pos;
				hsync_valid <= 1'b1;
			end
			if (vsync_rise) begin
				measured_vsync_hpos <= h_count;
				measured_vsync_vpos <= v_count;
			end
			if (vsync_fall) begin
				measured_vsync_width <= v_count - measured_vsync_vpos;
				vsync_valid <= 1'b1;
			end

			if (h_count == hsync_trip && measured_hsync_width != 10'd0) begin
				hsync_generated <= 1'b1;
				hsync_hold <= measured_hsync_width - 10'd1;
			end else if (hsync_hold != 10'd0) begin
				hsync_hold <= hsync_hold - 10'd1;
			end else begin
				hsync_generated <= 1'b0;
			end

			if (h_count == vsync_htrip) begin
				if (v_count == vsync_vtrip &&
				    measured_vsync_width != 10'd0) begin
					vsync_generated <= 1'b1;
					vsync_hold <= measured_vsync_width - 10'd1;
				end else if (vsync_hold != 10'd0) begin
					vsync_hold <= vsync_hold - 10'd1;
				end else begin
					vsync_generated <= 1'b0;
				end
			end
		end
	end
endmodule
