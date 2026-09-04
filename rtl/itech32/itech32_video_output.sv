// SPDX-License-Identifier: GPL-2.0-or-later
// CE-gated MiSTer video boundary for the ITech32 core.
`timescale 1ns/1ps

module itech32_video_output (
	input  logic        clk,
	input  logic        reset,
	input  logic        ce_pixel,
	input  logic [23:0] rgb_in,
	input  logic        pixel_valid_in,
	input  logic        hblank_in,
	input  logic        vblank_in,
	input  logic        hsync_in,
	input  logic        vsync_in,
	output logic [7:0]  vga_r = 8'd0,
	output logic [7:0]  vga_g = 8'd0,
	output logic [7:0]  vga_b = 8'd0,
	output logic        vga_de = 1'b0,
	output logic        vga_hs = 1'b0,
	output logic        vga_vs = 1'b0,
	output logic        vga_hblank = 1'b1,
	output logic        vga_vblank = 1'b1
);
	logic hblank_q = 1'b1;
	logic vblank_q = 1'b1;
	logic hsync_q = 1'b0;
	logic vsync_q = 1'b0;
	logic pixel_valid_q = 1'b0;
	logic [23:0] rgb_q = 24'd0;

	// Raster and palette state change only on CE_PIXEL (the synchronous palette
	// read settles on the intervening fabric clocks). Capture the complete source
	// bundle before the CE-gated MiSTer boundary. This keeps deep validity and
	// blanking comparators out of all 24 color-bit D paths without introducing a
	// pixel of relative skew between RGB, DE, and sync.
	always_ff @(posedge clk) begin
		if (reset) begin
			hblank_q <= 1'b1;
			vblank_q <= 1'b1;
			hsync_q <= 1'b0;
			vsync_q <= 1'b0;
			pixel_valid_q <= 1'b0;
			rgb_q <= 24'd0;
		end else begin
			hblank_q <= hblank_in;
			vblank_q <= vblank_in;
			hsync_q <= hsync_in;
			vsync_q <= vsync_in;
			pixel_valid_q <= pixel_valid_in;
			rgb_q <= rgb_in;
		end
	end

	// MiSTer samples all video-boundary signals on CE_PIXEL. Keep RGB, blanking,
	// and sync in one stage so none can change between valid pixel strobes.
	always_ff @(posedge clk) begin
		if (ce_pixel) begin
			if (reset) begin
				vga_r  <= 8'd0;
				vga_g  <= 8'd0;
				vga_b  <= 8'd0;
				vga_de <= 1'b0;
				vga_hs <= 1'b0;
				vga_vs <= 1'b0;
				vga_hblank <= 1'b1;
				vga_vblank <= 1'b1;
			end else begin
				vga_r  <= pixel_valid_q ? rgb_q[23:16] : 8'd0;
				vga_g  <= pixel_valid_q ? rgb_q[15:8] : 8'd0;
				vga_b  <= pixel_valid_q ? rgb_q[7:0] : 8'd0;
				vga_de <= ~(hblank_q || vblank_q);
				vga_hs <= hsync_q;
				vga_vs <= vsync_q;
				vga_hblank <= hblank_q;
				vga_vblank <= vblank_q;
			end
		end
	end

endmodule
