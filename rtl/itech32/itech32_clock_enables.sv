// SPDX-License-Identifier: GPL-2.0-or-later
`timescale 1ns/1ps

module itech32_clock_enables #(
	parameter integer CLK_HZ     = 47_727_273,
	parameter integer ALT_CLK_HZ = 48_000_000,
	// Both carriers use the same integral pixel divider. This keeps every
	// direct-video line exactly the same number of carrier clocks in either
	// mode; only the carrier period changes.
	parameter integer PIXEL_DIV = 6
) (
	input  logic clk,
	input  logic reset,
	input  logic alternate_clock,
	output logic ce_cpu_25m,
	output logic ce_cpu_12m,
	output logic ce_ensoniq_16m,
	output logic ce_pixel,
	output logic ce_sound_8m,
	output logic ce_sound_2m
);

	itech32_selectable_rate_enable #(
		.CLK_HZ(CLK_HZ), .ALT_CLK_HZ(ALT_CLK_HZ), .RATE_HZ(25_000_000)
	) cpu_ce (
		.clk(clk), .reset(reset), .alternate_clock(alternate_clock),
		.ce(ce_cpu_25m)
	);
	itech32_selectable_rate_enable #(
		.CLK_HZ(CLK_HZ), .ALT_CLK_HZ(ALT_CLK_HZ), .RATE_HZ(12_000_000)
	) cpu_12m_ce (
		.clk(clk), .reset(reset), .alternate_clock(alternate_clock),
		.ce(ce_cpu_12m)
	);
	itech32_selectable_rate_enable #(
		.CLK_HZ(CLK_HZ), .ALT_CLK_HZ(ALT_CLK_HZ), .RATE_HZ(16_000_000)
	) ensoniq_ce (
		.clk(clk), .reset(reset), .alternate_clock(alternate_clock),
		.ce(ce_ensoniq_16m)
	);
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
	itech32_selectable_rate_enable #(
		.CLK_HZ(CLK_HZ), .ALT_CLK_HZ(ALT_CLK_HZ), .RATE_HZ(8_000_000)
	) sound_8m_ce (
		.clk(clk), .reset(reset), .alternate_clock(alternate_clock),
		.ce(ce_sound_8m)
	);
	itech32_selectable_rate_enable #(
		.CLK_HZ(CLK_HZ), .ALT_CLK_HZ(ALT_CLK_HZ), .RATE_HZ(2_000_000)
	) sound_ce (
		.clk(clk), .reset(reset), .alternate_clock(alternate_clock),
		.ce(ce_sound_2m)
	);

endmodule

// The selected denominator is static while reset is released. The top-level
// clock-mode controller asserts reset before changing it, so one accumulator
// implements both exact long-term rates without duplicating the rate engines.
module itech32_selectable_rate_enable #(
	parameter integer CLK_HZ     = 47_727_273,
	parameter integer ALT_CLK_HZ = 48_000_000,
	parameter integer RATE_HZ    = 8_000_000
) (
	input  logic clk,
	input  logic reset,
	input  logic alternate_clock,
	output logic ce
);
	localparam logic [32:0] CLK_CONST = {1'b0, CLK_HZ[31:0]};
	localparam logic [32:0] ALT_CLK_CONST = {1'b0, ALT_CLK_HZ[31:0]};
	localparam logic [32:0] RATE_CONST = {1'b0, RATE_HZ[31:0]};
	logic [31:0] accumulator;
	logic [32:0] sum;
	logic [32:0] selected_clock;

	always_comb begin
		sum = {1'b0, accumulator} + RATE_CONST;
		selected_clock = alternate_clock ? ALT_CLK_CONST : CLK_CONST;
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			accumulator <= '0;
			ce <= 1'b0;
		end else if (sum >= selected_clock) begin
			accumulator <= sum[31:0] - selected_clock[31:0];
			ce <= 1'b1;
		end else begin
			accumulator <= sum[31:0];
			ce <= 1'b0;
		end
	end
endmodule
