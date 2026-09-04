// SPDX-License-Identifier: GPL-2.0-or-later
// Decode the MiSTer OSD's unsigned choice index into a calibrated CRT shift.
`timescale 1ns/1ps

module itech32_crt_adjust_decode (
	input  logic [5:0] h_trim_code,
	input  logic [5:0] v_trim_code,
	output logic signed [5:0] h_offset,
	output logic signed [5:0] v_offset
);
	// Menu codes are ordered 0,+1..+16,-16..-1 so code zero remains the
	// persistent-settings default.  The board calibration is -16 pixels/lines;
	// the signed user trim is added around it for a physical range of -32..0.
	function automatic logic signed [5:0] decode_offset(
		input logic [5:0] trim_code
	);
		begin
			if (trim_code <= 6'd16)
				decode_offset = $signed({1'b0, trim_code[4:0]}) - 6'sd16;
			else if (trim_code < 6'd32)
				// 6'sh20 is the signed six-bit minimum (-32).  Avoid
				// unary minus on 6'sd32: that literal already encodes -32
				// and Quartus correctly reports the attempted +32 overflow.
				decode_offset = 6'sh20 +
					$signed({2'b00, trim_code[3:0]}) - 6'sd1;
			else if (trim_code == 6'd32)
				decode_offset = -6'sd17;
			else
				decode_offset = -6'sd16;
		end
	endfunction

	always_comb begin
		h_offset = decode_offset(h_trim_code);
		v_offset = decode_offset(v_trim_code);
	end
endmodule
