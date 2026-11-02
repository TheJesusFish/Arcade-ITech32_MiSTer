// SPDX-License-Identifier: GPL-3.0-or-later
//
// ITech32 board-level route from OTTO's signed 20-bit pair to MiSTer's
// signed 16-bit pair. MAME documents a stereo swap and applies gain 1.6 in
// its floating-point mixer. Applying that gain unconditionally before MiSTer's
// fixed 16-bit boundary clips valid ES5506 output, so the default (1x)
// preserves the complete signed 20-bit range. The MiSTer volume control can
// only attenuate, so an optional 2x/4x gain is applied here, at full 20-bit
// precision, saturating at the 16-bit limits.

`timescale 1ns/1ps

module itech32_sound_output (
	input  logic signed [19:0] es_left,
	input  logic signed [19:0] es_right,
	input  logic               es_strobe,
	// 0 = 1x (exact full-range map), 1 = 2x, 2 or 3 = 4x.
	input  logic [1:0]         gain,
	output logic signed [15:0] audio_left,
	output logic signed [15:0] audio_right,
	output logic               audio_strobe
);

	function automatic signed [15:0] route_normalize(
		input logic signed [19:0] sample,
		input logic [1:0]         gain_select
	);
		logic [19:0] magnitude;
		logic [19:0] scaled;
		begin
			// Dividing the magnitude by 16 before restoring the sign maps the
			// complete signed 20-bit range exactly into signed 16 bits. It also
			// gives deterministic truncation toward zero instead of the negative
			// one-LSB bias of a signed arithmetic right shift. Gain divides by
			// 8 or 4 instead and saturates.
			magnitude = sample[19] ? ((~sample) + 20'd1) : sample;
			case (gain_select)
				2'd0:    scaled = magnitude >> 4;
				2'd1:    scaled = magnitude >> 3;
				default: scaled = magnitude >> 2;
			endcase
			// 16'sh8000 is the signed 16-bit minimum (-32768).
			if (sample[19])
				route_normalize = (scaled >= 20'h08000) ? 16'sh8000 :
					-$signed(scaled[15:0]);
			else
				route_normalize = (scaled >= 20'h08000) ? 16'sd32767 :
					$signed(scaled[15:0]);
		end
	endfunction

	always_comb begin
		audio_left = route_normalize(es_right, gain);
		audio_right = route_normalize(es_left, gain);
		audio_strobe = es_strobe;
	end

endmodule
