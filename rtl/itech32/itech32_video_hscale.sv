// SPDX-License-Identifier: GPL-3.0-or-later
// Analog horizontal scaler adapted from Arcade-IGSPGM_MiSTer video_hscale.
// Original implementation copyright (C) 2026 Martin Donlon.
// https://github.com/MiSTer-devel/Arcade-IGSPGM_MiSTer/blob/main/rtl/video_hscale.sv
// Modified for ITech32; see CREDITS.md and LICENSE for attribution and terms.
//
// The PGM implementation assumes a fixed integer number of fabric clocks per
// source pixel. ITech32 uses a fractional fabric-clock CE to reproduce the
// measured 54.75-Hz refresh, so this version measures the active interval in
// fabric clocks and maps that interval to the source pixels with a registered
// DDA. Geometry arithmetic runs serially between line boundaries: there is no
// combinational divider, wide RGB mux, or variable shift on the 100-MHz path.
`timescale 1ns/1ps

module itech32_video_hscale (
	input  logic              clk,
	input  logic              enable,
	input  logic signed [4:0] scale,
	output logic              enable_latched = 1'b0,

	input  logic              ce_pixel_in,
	input  logic [7:0]        r_in,
	input  logic [7:0]        g_in,
	input  logic [7:0]        b_in,
	input  logic              hsync_in,
	input  logic              hblank_in,
	input  logic              vblank_in,
	input  logic              vsync_in,

	output logic [7:0]        r_out = 8'd0,
	output logic [7:0]        g_out = 8'd0,
	output logic [7:0]        b_out = 8'd0,
	output logic              hsync_out = 1'b0,
	output logic              hblank_out = 1'b1,
	output logic              vblank_out = 1'b1,
	output logic              vsync_out = 1'b0
);

	localparam logic [12:0] READ_LEAD = 13'd16;

	logic hblank_d = 1'b1;
	logic vblank_d = 1'b1;
	logic hsync_d = 1'b0;
	wire line_start = hblank_in && !hblank_d;
	wire frame_blank_start = vblank_in && !vblank_d;

	logic [12:0] measure_line_clocks = 13'd0;
	logic [9:0]  measure_active_pixels = 10'd0;
	logic [12:0] measure_hsync_start = 13'd0;
	logic [12:0] measured_hblank_clocks = 13'd0;
	logic [12:0] measured_hsync_start = 13'd0;
	logic [12:0] measured_hsync_width = 13'd0;

	typedef enum logic [1:0] {
		CALC_IDLE,
		CALC_MULTIPLY,
		CALC_DIVIDE
	} calc_state_t;
	calc_state_t calc_state = CALC_IDLE;

	logic [12:0] calc_total = 13'd0;
	logic [12:0] calc_base_active = 13'd0;
	logic [9:0]  calc_active_pixels = 10'd0;
	logic [12:0] calc_hblank = 13'd0;
	logic [12:0] calc_hsync_start = 13'd0;
	logic [12:0] calc_hsync_width = 13'd0;
	logic        calc_negative = 1'b0;
	logic [4:0]  calc_remaining = 5'd0;
	logic [16:0] calc_product = 17'd0;
	logic [16:0] calc_dividend = 17'd0;
	logic [12:0] calc_quotient = 13'd0;

	logic        geometry_valid = 1'b0;
	logic [12:0] geometry_total = 13'd0;
	logic [12:0] geometry_active_length = 13'd0;
	logic [9:0]  geometry_active_pixels = 10'd0;
	logic [12:0] geometry_read_start = 13'd0;
	logic [12:0] geometry_hsync_start = 13'd0;
	logic [12:0] geometry_hsync_end = 13'd0;
	logic [12:0] geometry_blank_clock = 13'd0;
	logic geometry_overrun = 1'b0;

	logic [12:0] frame_total = 13'd0;
	logic [12:0] active_length = 13'd0;
	logic [9:0]  active_pixels = 10'd0;
	logic [12:0] read_start = 13'd0;
	logic [12:0] hsync_start = 13'd0;
	logic [12:0] hsync_end = 13'd0;
	logic [12:0] blank_clock = 13'd0;

	wire signed [5:0] scale_extended = {scale[4], scale};
	wire [5:0] absolute_scale = scale_extended[5]
		? $unsigned(-scale_extended)
		: $unsigned(scale_extended);

	// Measure source geometry and calculate the requested 1.25-percent steps.
	// Multiplication is repeated addition (at most 16 cycles); division by 80 is
	// repeated subtraction (at most about 1,100 cycles for SFTM). Both finish
	// long before the next approximately 7,000-clock line boundary.
	always_ff @(posedge clk) begin
		hblank_d <= hblank_in;
		vblank_d <= vblank_in;
		hsync_d <= hsync_in;

		if (line_start) begin
			if (calc_state != CALC_IDLE)
				geometry_overrun <= 1'b1;

			calc_total <= measure_line_clocks + 13'd1;
			calc_base_active <= measure_line_clocks + 13'd1 -
				measured_hblank_clocks;
			calc_active_pixels <= measure_active_pixels;
			calc_hblank <= measured_hblank_clocks;
			calc_hsync_start <= measured_hsync_start;
			calc_hsync_width <= measured_hsync_width;
			calc_negative <= scale[4];
			calc_remaining <= absolute_scale[4:0];
			calc_product <= 17'd0;
			calc_dividend <= 17'd0;
			calc_quotient <= 13'd0;
			calc_state <= (absolute_scale == 6'd0)
				? CALC_DIVIDE : CALC_MULTIPLY;

			measure_line_clocks <= 13'd0;
			measure_active_pixels <= 10'd0;
		end else begin
			measure_line_clocks <= measure_line_clocks + 13'd1;
			if (ce_pixel_in && !hblank_in)
				measure_active_pixels <= measure_active_pixels + 10'd1;
		end

		if (hblank_d && !hblank_in)
			measured_hblank_clocks <= measure_line_clocks;
		if (hsync_in && !hsync_d) begin
			measured_hsync_start <= measure_line_clocks;
			measure_hsync_start <= measure_line_clocks;
		end
		if (!hsync_in && hsync_d)
			measured_hsync_width <= measure_line_clocks - measure_hsync_start;

		if (!line_start) begin
			case (calc_state)
				CALC_MULTIPLY: begin
					calc_product <= calc_product + {4'd0, calc_base_active};
					calc_remaining <= calc_remaining - 5'd1;
					if (calc_remaining == 5'd1) begin
						calc_dividend <= calc_product + {4'd0, calc_base_active};
						calc_state <= CALC_DIVIDE;
					end
				end

				CALC_DIVIDE: begin
					if (calc_dividend >= 17'd80) begin
						calc_dividend <= calc_dividend - 17'd80;
						calc_quotient <= calc_quotient + 13'd1;
					end else begin
						geometry_total <= calc_total;
						geometry_active_length <= calc_negative
							? calc_base_active - calc_quotient
							: calc_base_active + calc_quotient;
						geometry_active_pixels <= calc_active_pixels;
						geometry_read_start <= calc_hblank + READ_LEAD +
							(calc_negative ? {1'b0, calc_quotient[11:0]} : 13'd0);
						geometry_hsync_start <= calc_hsync_start +
							{2'b0, calc_quotient[11:1]};
						geometry_hsync_end <= calc_hsync_start +
							{2'b0, calc_quotient[11:1]} + calc_hsync_width;
						geometry_blank_clock <= READ_LEAD +
							(calc_negative ? 13'd0 : {1'b0, calc_quotient[11:0]});
						geometry_valid <= calc_active_pixels != 10'd0 &&
							calc_total != 13'd0;
						calc_state <= CALC_IDLE;
					end
				end

				default: begin end
			endcase
		end

		// All output geometry changes at the source vblank boundary. The scaler
		// therefore never changes line width or output selection mid-frame.
		if (frame_blank_start) begin
			enable_latched <= enable && geometry_valid;
			if (geometry_valid) begin
				frame_total <= geometry_total;
				active_length <= geometry_active_length;
				active_pixels <= geometry_active_pixels;
				read_start <= geometry_read_start;
				hsync_start <= geometry_hsync_start;
				hsync_end <= geometry_hsync_end;
				blank_clock <= geometry_blank_clock;
			end
		end
	end

	(* ramstyle = "M10K, no_rw_check" *)
	logic [23:0] line_buffer [0:127];
	logic [8:0] write_index = 9'd0;
	logic [8:0] read_index = 9'd0;
	logic [23:0] read_data = 24'd0;
	wire write_enable = ce_pixel_in && !hblank_in;

	// One synchronous write plus one synchronous read is the canonical
	// Cyclone-V simple-dual-port M10K shape. Storage is intentionally reset-free.
	always_ff @(posedge clk) begin
		if (write_enable)
			line_buffer[write_index[6:0]] <= {r_in, g_in, b_in};
		read_data <= line_buffer[read_index[6:0]];
	end

	logic [12:0] line_clock = 13'd0;
	logic line_vblank = 1'b1;
	logic line_vsync = 1'b0;
	logic [12:0] active_count = 13'd0;
	logic [12:0] source_phase = 13'd0;
	logic read_active_d = 1'b0;
	logic hsync_stage1 = 1'b0;
	logic reading_current_line = 1'b0;
	logic debug_underrun = 1'b0;
	logic debug_overflow = 1'b0;
	wire read_active = active_count != 13'd0;
	wire read_load = enable_latched && !line_vblank &&
		(line_clock == read_start);
	wire [13:0] source_phase_sum = {1'b0, source_phase} +
		{4'd0, active_pixels};
	// The supported scale range keeps this sum below 8192. Retain only the
	// datapath width actually consumed by the DDA so the unused carry bit cannot
	// become warning noise or an unnecessary comparator/mux input.
	wire [12:0] source_phase_difference = source_phase_sum[12:0] -
		active_length;

	always_ff @(posedge clk) begin
		if (line_start) begin
			line_clock <= 13'd0;
			write_index <= 9'd0;
			reading_current_line <= 1'b0;
			line_vblank <= vblank_in;
			line_vsync <= vsync_in;
		end else if (frame_total != 13'd0) begin
			line_clock <= (line_clock >= frame_total - 13'd1)
				? 13'd0 : line_clock + 13'd1;
		end

		if (line_clock == blank_clock) begin
			vblank_out <= line_vblank;
			vsync_out <= line_vsync;
		end

		if (write_enable)
			write_index <= write_index + 9'd1;

		if (read_load) begin
			active_count <= active_length;
			read_index <= 9'd0;
			source_phase <= 13'd0;
			reading_current_line <= 1'b1;
		end else if (read_active) begin
			active_count <= active_count - 13'd1;
			if (source_phase_sum >= {1'b0, active_length}) begin
				source_phase <= source_phase_difference;
				read_index <= read_index + 9'd1;
			end else begin
				source_phase <= source_phase_sum[12:0];
			end
		end

		if (reading_current_line && read_active && read_index >= write_index)
			debug_underrun <= 1'b1;
		if (reading_current_line && write_index >= read_index &&
		    (write_index - read_index) >= 9'd128)
			debug_overflow <= 1'b1;

		read_active_d <= read_active;
		{r_out, g_out, b_out} <= read_data;
		hblank_out <= !read_active_d;
		// The inferred M10K read and final RGB register form a two-edge
		// address-to-output pipeline. Carry HSync through the same depth so the
		// scaled pixel bundle remains cycle-aligned at the MiSTer boundary.
		hsync_stage1 <= line_clock >= hsync_start && line_clock < hsync_end;
		hsync_out <= hsync_stage1;
	end

endmodule
