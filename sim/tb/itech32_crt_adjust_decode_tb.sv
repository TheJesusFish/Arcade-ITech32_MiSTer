`timescale 1ns/1ps

module itech32_crt_adjust_decode_tb;
	logic [5:0] h_trim_code;
	logic [5:0] v_trim_code;
	logic signed [5:0] h_offset;
	logic signed [5:0] v_offset;

	itech32_crt_adjust_decode dut (
		.h_trim_code(h_trim_code), .v_trim_code(v_trim_code),
		.h_offset(h_offset), .v_offset(v_offset)
	);

	function automatic integer expected_offset(input integer code);
		if (code <= 16)
			expected_offset = code - 16;
		else if (code <= 32)
			expected_offset = code - 49;
		else
			expected_offset = -16;
	endfunction

	initial begin
		for (integer h = 0; h < 64; h = h + 1) begin
			for (integer v = 0; v < 64; v = v + 1) begin
				logic signed [5:0] expected_h;
				logic signed [5:0] expected_v;
				h_trim_code = 6'(h);
				v_trim_code = 6'(v);
				expected_h = 6'(expected_offset(h));
				expected_v = 6'(expected_offset(v));
				#1;
				if (h_offset != expected_h)
					$fatal(1, "H code %0d decoded to %0d, expected %0d",
						h, $signed(h_offset), expected_offset(h));
				if (v_offset != expected_v)
					$fatal(1, "V code %0d decoded to %0d, expected %0d",
						v, $signed(v_offset), expected_offset(v));
			end
		end

		$display("PASS CRT adjustment: default -16, trim +/-16, invalid fallback");
		$finish;
	end
endmodule
