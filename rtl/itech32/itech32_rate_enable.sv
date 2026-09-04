// SPDX-License-Identifier: GPL-2.0-or-later
// Fractional clock enable with exact long-term average frequency.
`timescale 1ns/1ps

module itech32_rate_enable #(
	parameter integer CLK_HZ  = 100_000_000,
	parameter integer RATE_HZ = 25_000_000
) (
	input  logic clk,
	input  logic reset,
	output logic ce
);

	localparam logic [32:0] CLK_CONST  = {1'b0, CLK_HZ[31:0]};
	localparam logic [32:0] RATE_CONST = {1'b0, RATE_HZ[31:0]};
	localparam logic [31:0] CLK_CONST_32 = CLK_HZ;
	logic [31:0] accumulator;
	logic [32:0] sum;

	always_comb begin
		sum = {1'b0, accumulator} + RATE_CONST;
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			accumulator <= '0;
			ce          <= 1'b0;
		end else if (sum >= CLK_CONST) begin
			accumulator <= sum[31:0] - CLK_CONST_32;
			ce          <= 1'b1;
		end else begin
			accumulator <= sum[31:0];
			ce          <= 1'b0;
		end
	end

endmodule
