// SPDX-License-Identifier: GPL-2.0-or-later
`timescale 1ns/1ps

module itech32_clock_enables #(
	parameter integer CLK_HZ   = 100_000_000,
	// CLK_HZ is deliberately six times the measured pixel rate in hardware.
	// Keep the pixel enable integral so direct video's line length cannot wander.
	parameter integer PIXEL_DIV = 6
) (
	input  logic clk,
	input  logic reset,
	output logic ce_cpu_25m,
	output logic ce_cpu_12m,
	output logic ce_ensoniq_16m,
	output logic ce_pixel,
	output logic ce_sound_8m,
	output logic ce_sound_2m
);

	itech32_rate_enable #(.CLK_HZ(CLK_HZ), .RATE_HZ(25_000_000)) cpu_ce
		(.clk(clk), .reset(reset), .ce(ce_cpu_25m));
	itech32_rate_enable #(.CLK_HZ(CLK_HZ), .RATE_HZ(12_000_000)) cpu_12m_ce
		(.clk(clk), .reset(reset), .ce(ce_cpu_12m));
	itech32_rate_enable #(.CLK_HZ(CLK_HZ), .RATE_HZ(16_000_000)) ensoniq_ce
		(.clk(clk), .reset(reset), .ce(ce_ensoniq_16m));
	localparam integer PIXEL_COUNT_WIDTH = $clog2(PIXEL_DIV);
	logic [PIXEL_COUNT_WIDTH-1:0] pixel_count;
	always_ff @(posedge clk) begin
		if (reset) begin
			pixel_count <= '0;
			ce_pixel <= 1'b0;
		end else if (pixel_count == PIXEL_COUNT_WIDTH'(PIXEL_DIV - 1)) begin
			pixel_count <= '0;
			ce_pixel <= 1'b1;
		end else begin
			pixel_count <= pixel_count + 1'b1;
			ce_pixel <= 1'b0;
		end
	end
	// The sound board has its own 8 MHz source. It must not inherit the measured
	// video cadence merely because the earlier approximation used 8 MHz for both.
	itech32_rate_enable #(.CLK_HZ(CLK_HZ), .RATE_HZ(8_000_000)) sound_8m_ce
		(.clk(clk), .reset(reset), .ce(ce_sound_8m));
	itech32_rate_enable #(.CLK_HZ(CLK_HZ), .RATE_HZ(2_000_000)) sound_ce
		(.clk(clk), .reset(reset), .ce(ce_sound_2m));

endmodule
