// SPDX-License-Identifier: GPL-2.0-or-later
// Always-running black raster for direct-video acquisition before the board
// CRTC is programmed. Totals match SFTM's programmed 508x286 frame and use the
// same exact /6 cadence as the selected game path.
`timescale 1ns/1ps

module itech32_fallback_raster (
	input  logic        clk,
	input  logic        reset,
	output logic        ce_pixel,
	output logic        hblank,
	output logic        vblank,
	output logic        hsync,
	output logic        vsync,
	output logic [23:0] rgb
);
	logic [2:0] pixel_div;
	logic [8:0] hpos;
	logic [8:0] vpos;

	always_ff @(posedge clk) begin
		if (reset) begin
			pixel_div <= 3'd0;
			hpos <= 9'd0;
			vpos <= 9'd0;
			ce_pixel <= 1'b0;
		end else if (pixel_div == 3'd5) begin
			pixel_div <= 3'd0;
			ce_pixel <= 1'b1;
			if (hpos == 9'd507) begin
				hpos <= 9'd0;
				vpos <= (vpos == 9'd285) ? 9'd0 : vpos + 9'd1;
			end else begin
				hpos <= hpos + 9'd1;
			end
		end else begin
			pixel_div <= pixel_div + 3'd1;
			ce_pixel <= 1'b0;
		end
	end

	always_comb begin
		hblank = hpos >= 9'd384;
		vblank = vpos >= 9'd240;
		hsync = (hpos >= 9'd408) && (hpos < 9'd448);
		vsync = (vpos >= 9'd248) && (vpos < 9'd252);
		rgb = 24'd0;
	end
endmodule
