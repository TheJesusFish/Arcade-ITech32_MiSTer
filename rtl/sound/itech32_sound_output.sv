// SPDX-License-Identifier: GPL-3.0-or-later
//
// ITech32 board-level route from OTTO's signed 20-bit pair to MiSTer's
// signed 16-bit pair. MAME documents a stereo swap and applies gain 1.6 in
// its floating-point mixer. Applying that gain before MiSTer's fixed 16-bit
// boundary clips valid ES5506 output, so this boundary preserves the complete
// signed 20-bit range and leaves downstream/user gain to the MiSTer mixer.

`timescale 1ns/1ps

module itech32_sound_output (
	input  logic signed [19:0] es_left,
	input  logic signed [19:0] es_right,
	input  logic               es_strobe,
	output logic signed [15:0] audio_left,
	output logic signed [15:0] audio_right,
	output logic               audio_strobe
);

	function automatic signed [15:0] route_normalize(
		input logic signed [19:0] sample
	);
		logic [19:0] magnitude;
		logic [15:0] normalized;
		begin
			// Dividing the magnitude by 16 before restoring the sign maps the
			// complete signed 20-bit range exactly into signed 16 bits. It also
			// gives deterministic truncation toward zero instead of the negative
			// one-LSB bias of a signed arithmetic right shift.
			magnitude = sample[19] ? ((~sample) + 20'd1) : sample;
			normalized = magnitude[19:4];
			if (sample[19])
				route_normalize = -$signed(normalized);
			else
				route_normalize = $signed(normalized);
		end
	endfunction

	always_comb begin
		audio_left = route_normalize(es_right);
		audio_right = route_normalize(es_left);
		audio_strobe = es_strobe;
	end

endmodule
