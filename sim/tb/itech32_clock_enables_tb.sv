`timescale 1ns/1ps

module itech32_clock_enables_tb;
	localparam integer SFTM_H_TOTAL = 508;
	localparam integer SFTM_V_TOTAL = 286;
	localparam longint FABRIC_HZ = 47_727_273;
	localparam integer PIXEL_DIV = 6;
	localparam longint SFTM_PIXEL_HZ = FABRIC_HZ / PIXEL_DIV;
	localparam longint TEST_CYCLES = 100_000;
	logic clk;
	logic reset;
	logic ce25, ce12, ce16, ce_pixel, ce_sound8, ce2;
	integer count25;
	integer count12;
	integer count16;
	integer count_pixel;
	integer count_sound8;
	integer count2;
	integer cycle;
	integer pixel_gap;
	integer pixel_gap_min;
	integer pixel_gap_max;
	integer previous_pixel_cycle;
	integer sound8_pulse_count;
	integer previous_sound_e_cycle;
	integer sound_eq_gap;
	integer sound_eq_gap_min;
	integer sound_eq_gap_max;

	always #5 clk = ~clk;

	itech32_clock_enables #(.CLK_HZ(FABRIC_HZ), .PIXEL_DIV(PIXEL_DIV)) dut (
		.clk(clk), .reset(reset),
		.ce_cpu_25m(ce25), .ce_ensoniq_16m(ce16),
		.ce_cpu_12m(ce12),
		.ce_pixel(ce_pixel), .ce_sound_8m(ce_sound8), .ce_sound_2m(ce2)
	);

	initial begin
		clk = 1'b0;
		reset = 1'b1;
		count25 = 0;
		count12 = 0;
		count16 = 0;
		count_pixel = 0;
		count_sound8 = 0;
		count2 = 0;
		pixel_gap_min = 32'h7fff_ffff;
		pixel_gap_max = 0;
		previous_pixel_cycle = -1;
		sound8_pulse_count = 0;
		previous_sound_e_cycle = -1;
		sound_eq_gap_min = 32'h7fff_ffff;
		sound_eq_gap_max = 0;
		repeat (4) @(posedge clk);
		@(negedge clk); reset = 1'b0;
		for (cycle = 0; cycle < TEST_CYCLES; cycle = cycle + 1) begin
			@(posedge clk);
			#1;
			count25 = count25 + ce25;
			count12 = count12 + ce12;
			count16 = count16 + ce16;
			count_pixel = count_pixel + ce_pixel;
			count_sound8 = count_sound8 + ce_sound8;
			count2  = count2  + ce2;
			if (ce_pixel) begin
				if (previous_pixel_cycle >= 0) begin
					pixel_gap = cycle - previous_pixel_cycle;
					if (pixel_gap < pixel_gap_min) pixel_gap_min = pixel_gap;
					if (pixel_gap > pixel_gap_max) pixel_gap_max = pixel_gap;
				end
				previous_pixel_cycle = cycle;
			end
			if (ce_sound8) begin
				if ((sound8_pulse_count & 1) == 0) begin
					if (previous_sound_e_cycle >= 0) begin
						sound_eq_gap = cycle - previous_sound_e_cycle;
						if (sound_eq_gap < sound_eq_gap_min)
							sound_eq_gap_min = sound_eq_gap;
						if (sound_eq_gap > sound_eq_gap_max)
							sound_eq_gap_max = sound_eq_gap;
					end
					previous_sound_e_cycle = cycle;
				end
				sound8_pulse_count = sound8_pulse_count + 1;
			end
		end
		if (count25 != (TEST_CYCLES * 25_000_000) / FABRIC_HZ)
			$fatal(1, "25 MHz count %0d", count25);
		if (count12 != (TEST_CYCLES * 12_000_000) / FABRIC_HZ)
			$fatal(1, "12 MHz count %0d", count12);
		if (count16 != (TEST_CYCLES * 16_000_000) / FABRIC_HZ)
			$fatal(1, "16 MHz count %0d", count16);
		if (count_pixel != TEST_CYCLES / PIXEL_DIV)
			$fatal(1, "exact /6 pixel count %0d", count_pixel);
		if (count_sound8 != (TEST_CYCLES * 8_000_000) / FABRIC_HZ)
			$fatal(1, "8 MHz sound count %0d", count_sound8);
		if (count2 != (TEST_CYCLES * 2_000_000) / FABRIC_HZ)
			$fatal(1, "2 MHz count %0d", count2);
		if (pixel_gap_min != PIXEL_DIV || pixel_gap_max != PIXEL_DIV)
			$fatal(1, "pixel CE gap min/max %0d/%0d", pixel_gap_min, pixel_gap_max);
		if (sound_eq_gap_min != 11 || sound_eq_gap_max != 12)
			$fatal(1, "6809 E-to-E/Q-to-Q gap min/max %0d/%0d",
				sound_eq_gap_min, sound_eq_gap_max);
		if ((SFTM_PIXEL_HZ * 1000 / (SFTM_H_TOTAL * SFTM_V_TOTAL)) != 54_750)
			$fatal(1, "SFTM approximately 54.75 Hz geometry drifted");
		$display("PASS 47.727273MHz clock enables: cpu25=%0d cpu12=%0d es=%0d pixel=%0d sound8=%0d sound2=%0d pixel-gap=%0d/%0d sound-EQ-gap=%0d/%0d refresh=54.751Hz totals=%0dx%0d",
			count25, count12, count16, count_pixel, count_sound8, count2,
			pixel_gap_min, pixel_gap_max, sound_eq_gap_min, sound_eq_gap_max,
			SFTM_H_TOTAL, SFTM_V_TOTAL);
		$finish;
	end
endmodule
