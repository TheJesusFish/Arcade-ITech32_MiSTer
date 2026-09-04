// SPDX-License-Identifier: GPL-3.0-or-later
//
// Four-phase E/Q clock-enable generator for the ITech32 sound-board 6809.
// The physical board derives the CPU clock from an 8 MHz enable. One E pulse
// and one Q pulse are produced in each group of four accepted 8 MHz enables,
// so architectural CPU cycles advance at 2 MHz.

`timescale 1ns/1ps

module itech32_6809_phase_enable (
	input  logic       clk,
	input  logic       reset,
	input  logic       ce_8m,
	input  logic       hold,
	output logic       ce_e,
	output logic       ce_q,
	output logic       ce_cpu_2m,
	output logic [1:0] phase
);

	logic advance;

	always_comb begin
		advance   = ce_8m && !hold && !reset;
		ce_e      = advance && (phase == 2'b00);
		ce_q      = advance && (phase == 2'b10);
		ce_cpu_2m = ce_e;
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			phase <= 2'b00;
		end else if (advance) begin
			phase <= phase + 2'd1;
		end
	end

endmodule
