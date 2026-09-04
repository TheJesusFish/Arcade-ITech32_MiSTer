// SPDX-License-Identifier: GPL-2.0-or-later
// ITech32 source-video alignment, CRT adjustments, and MiSTer video mixer.
`timescale 1ns/1ps

module itech32_video_path (
	input  logic              clk,
	input  logic              core_ce_pixel,
	input  logic [23:0]       core_rgb,
	input  logic              core_hblank,
	input  logic              core_vblank,
	input  logic              core_hsync,
	input  logic              core_vsync,
	input  logic [2:0]        scandoubler_fx,
	input  logic              forced_scandoubler,
	input  logic signed [5:0] crt_h_offset,
	input  logic signed [5:0] crt_v_offset,
	input  logic              hscale_enable,
	input  logic signed [4:0] hscale,
	inout  wire [21:0]        gamma_bus,
	output logic              ce_pixel,
	output logic [7:0]        vga_r,
	output logic [7:0]        vga_g,
	output logic [7:0]        vga_b,
	output logic              vga_hs,
	output logic              vga_vs,
	output logic              vga_de,
	output logic [1:0]        vga_sl
);
	logic adjusted_hs;
	logic adjusted_vs;
	itech32_video_resync crt_resync (
		.clk(clk),
		.ce_pixel(core_ce_pixel),
		.hsync_in(core_hsync),
		.vsync_in(core_vsync),
		.hblank_in(core_hblank),
		.vblank_in(core_vblank),
		.h_offset(crt_h_offset),
		.v_offset(crt_v_offset),
		.hsync_out(adjusted_hs),
		.vsync_out(adjusted_vs)
	);

	logic hscale_latched;
	logic [7:0] hscale_r;
	logic [7:0] hscale_g;
	logic [7:0] hscale_b;
	logic hscale_hs;
	logic hscale_vs;
	logic hscale_hblank;
	logic hscale_vblank;
	itech32_video_hscale analog_hscale (
		.clk(clk),
		.enable(hscale_enable),
		.scale(hscale),
		.enable_latched(hscale_latched),
		.ce_pixel_in(core_ce_pixel),
		.r_in(core_rgb[23:16]),
		.g_in(core_rgb[15:8]),
		.b_in(core_rgb[7:0]),
		.hsync_in(adjusted_hs),
		.hblank_in(core_hblank),
		.vblank_in(core_vblank),
		.vsync_in(adjusted_vs),
		.r_out(hscale_r),
		.g_out(hscale_g),
		.b_out(hscale_b),
		.hsync_out(hscale_hs),
		.hblank_out(hscale_hblank),
		.vblank_out(hscale_vblank),
		.vsync_out(hscale_vs)
	);
	// The live Off request is an unconditional hardware safety guard.  The
	// scaler still enters only through its frame-latched enable, but a stale or
	// power-up-high latch can never override an explicit menu Off selection.
	// This preserves the accepted direct mixer path without adding a register
	// or moving any externally visible video cycle.
	wire hscale_selected = hscale_enable && hscale_latched;

	logic mixer_ce;
	logic [7:0] mixer_r;
	logic [7:0] mixer_g;
	logic [7:0] mixer_b;
	logic mixer_hs;
	logic mixer_vs;
	logic mixer_de;
	logic freeze_sync_unused;
	wire mixer_hq2x = !hscale_selected && scandoubler_fx == 3'd1;
	wire mixer_scandoubler = !hscale_selected &&
		(forced_scandoubler || scandoubler_fx != 3'd0);

	video_mixer #(
		.LINE_LENGTH(388),
		.HALF_DEPTH(0),
		.GAMMA(1)
	) mixer (
		.CLK_VIDEO(clk),
		.CE_PIXEL(mixer_ce),
		.ce_pix(core_ce_pixel),
		.scandoubler(mixer_scandoubler),
		.hq2x(mixer_hq2x),
		.gamma_bus(gamma_bus),
		.R(core_rgb[23:16]),
		.G(core_rgb[15:8]),
		.B(core_rgb[7:0]),
		.HSync(adjusted_hs),
		.VSync(adjusted_vs),
		.HBlank(core_hblank),
		.VBlank(core_vblank),
		.HDMI_FREEZE(1'b0),
		.freeze_sync(freeze_sync_unused),
		.VGA_R(mixer_r),
		.VGA_G(mixer_g),
		.VGA_B(mixer_b),
		.VGA_VS(mixer_vs),
		.VGA_HS(mixer_hs),
		.VGA_DE(mixer_de)
	);

	// H-scale Off is deliberately the hardware-proven direct
	// core -> resync -> framework-mixer path. Do not insert a recapture stage
	// here: it changes the external RGB/blank/sync cycle and previously produced
	// a black hardware display. The scaler owns its registered line-buffer
	// pipeline only while its frame-latched enable selects the analog branch.
	always_comb begin
		ce_pixel = hscale_selected ? 1'b1 : mixer_ce;
		vga_r = hscale_selected ? hscale_r : mixer_r;
		vga_g = hscale_selected ? hscale_g : mixer_g;
		vga_b = hscale_selected ? hscale_b : mixer_b;
		vga_hs = hscale_selected ? hscale_hs : mixer_hs;
		vga_vs = hscale_selected ? hscale_vs : mixer_vs;
		vga_de = hscale_selected ?
			!(hscale_hblank || hscale_vblank) : mixer_de;
		// Values 1..4 map to the framework's 0..3 scanline strengths. Use
		// the explicit low-width subtraction so synthesis does not create a
		// needless 3-bit result followed by an implicit truncation.
		vga_sl = scandoubler_fx == 3'd0 ? 2'd0 :
			(scandoubler_fx[1:0] - 2'd1);
	end
endmodule
