// SPDX-License-Identifier: GPL-2.0-or-later
`timescale 1ns/1ps

module itech32_clock_enables_mame_tb;
	localparam integer H_TOTAL = 508;
	localparam integer V_TOTAL = 286;
	localparam longint FABRIC_HZ = 48_000_000;
	localparam integer PIXEL_DIV = 6;
	localparam longint TEST_CYCLES = 100_000;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic ce25, ce12, ce16, ce_pixel, ce_sound8, ce2;
	integer count25 = 0;
	integer count12 = 0;
	integer count16 = 0;
	integer count_pixel = 0;
	integer count_sound8 = 0;
	integer count2 = 0;
	integer cycle;
	integer previous_pixel_cycle = -1;
	integer pixel_gap_min = 32'h7fff_ffff;
	integer pixel_gap_max = 0;
	integer previous_sound_e_cycle = -1;
	integer sound_pulses = 0;
	integer sound_eq_gap_min = 32'h7fff_ffff;
	integer sound_eq_gap_max = 0;
	integer gap;

	always #5 clk = ~clk;

	itech32_clock_enables dut (
		.clk(clk), .reset(reset), .alternate_clock(1'b1),
		.ce_cpu_25m(ce25), .ce_cpu_12m(ce12),
		.ce_ensoniq_16m(ce16), .ce_pixel(ce_pixel),
		.ce_sound_8m(ce_sound8), .ce_sound_2m(ce2)
	);

	initial begin
		repeat (4) @(posedge clk);
		@(negedge clk); reset = 1'b0;
		for (cycle = 0; cycle < TEST_CYCLES; cycle = cycle + 1) begin
			@(posedge clk); #1;
			count25 += ce25;
			count12 += ce12;
			count16 += ce16;
			count_pixel += ce_pixel;
			count_sound8 += ce_sound8;
			count2 += ce2;
			if (ce_pixel) begin
				if (previous_pixel_cycle >= 0) begin
					gap = cycle - previous_pixel_cycle;
					if (gap < pixel_gap_min) pixel_gap_min = gap;
					if (gap > pixel_gap_max) pixel_gap_max = gap;
				end
				previous_pixel_cycle = cycle;
			end
			if (ce_sound8) begin
				if ((sound_pulses & 1) == 0) begin
					if (previous_sound_e_cycle >= 0) begin
						gap = cycle - previous_sound_e_cycle;
						if (gap < sound_eq_gap_min) sound_eq_gap_min = gap;
						if (gap > sound_eq_gap_max) sound_eq_gap_max = gap;
					end
					previous_sound_e_cycle = cycle;
				end
				sound_pulses += 1;
			end
		end

		assert (count25 == (TEST_CYCLES * 25_000_000) / FABRIC_HZ);
		assert (count12 == TEST_CYCLES / 4);
		assert (count16 == TEST_CYCLES / 3);
		assert (count_pixel == TEST_CYCLES / PIXEL_DIV);
		assert (count_sound8 == TEST_CYCLES / 6);
		assert (count2 == TEST_CYCLES / 24);
		assert (pixel_gap_min == 6 && pixel_gap_max == 6);
		assert (sound_eq_gap_min == 12 && sound_eq_gap_max == 12);
		assert ((64'd8_000_000 * 1_000 / (H_TOTAL * V_TOTAL)) == 55_063);

		$display("PASS 48MHz MAME timing enables: pixel-gap=%0d/%0d sound-EQ-gap=%0d/%0d refresh=55.063Hz totals=%0dx%0d",
			pixel_gap_min, pixel_gap_max, sound_eq_gap_min, sound_eq_gap_max,
			H_TOTAL, V_TOTAL);
		$finish;
	end
endmodule
