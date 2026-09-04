// SPDX-License-Identifier: GPL-3.0-or-later
//
// ROM-free check of the exact production PAR raw-pin boundary. This proves
// digital synchronization and polarity only, not a physical RC network.

`timescale 1ns/1ps
`default_nettype none

module itech32_es5506_par_pins_tb;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic discharge_active = 1'b0;
	logic [3:0] compare_pin = 4'b1100;
	logic [3:0] comparator_tripped;
	logic [3:0] res_pin;

	always #5 clk = ~clk;

	itech32_es5506_par_pins #(
		.POT_COMPARE_ACTIVE_HIGH(1'b1), .POT_RES_ACTIVE_HIGH(1'b1)
	) hh (
		.clk(clk), .reset(reset), .pot_compare_pin_i(compare_pin[0]),
		.discharge_active_i(discharge_active),
		.comparator_tripped_o(comparator_tripped[0]), .pot_res_pin_o(res_pin[0])
	);
	itech32_es5506_par_pins #(
		.POT_COMPARE_ACTIVE_HIGH(1'b1), .POT_RES_ACTIVE_HIGH(1'b0)
	) hl (
		.clk(clk), .reset(reset), .pot_compare_pin_i(compare_pin[1]),
		.discharge_active_i(discharge_active),
		.comparator_tripped_o(comparator_tripped[1]), .pot_res_pin_o(res_pin[1])
	);
	itech32_es5506_par_pins #(
		.POT_COMPARE_ACTIVE_HIGH(1'b0), .POT_RES_ACTIVE_HIGH(1'b1)
	) lh (
		.clk(clk), .reset(reset), .pot_compare_pin_i(compare_pin[2]),
		.discharge_active_i(discharge_active),
		.comparator_tripped_o(comparator_tripped[2]), .pot_res_pin_o(res_pin[2])
	);
	itech32_es5506_par_pins #(
		.POT_COMPARE_ACTIVE_HIGH(1'b0), .POT_RES_ACTIVE_HIGH(1'b0)
	) ll (
		.clk(clk), .reset(reset), .pot_compare_pin_i(compare_pin[3]),
		.discharge_active_i(discharge_active),
		.comparator_tripped_o(comparator_tripped[3]), .pot_res_pin_o(res_pin[3])
	);

	task automatic expect_outputs(
		input logic [3:0] expected_compare,
		input logic [3:0] expected_res,
		input string label_text
	);
		begin
			#1;
			assert (comparator_tripped == expected_compare &&
			        res_pin == expected_res)
				else $fatal(1, "%s compare=%b/%b res=%b/%b", label_text,
				            comparator_tripped, expected_compare, res_pin, expected_res);
		end
	endtask

	initial begin
		// Raw inactive levels are 0 for active-high comparators and 1 for
		// active-low comparators. Reset must establish semantic inactivity.
		repeat (3) @(posedge clk);
		expect_outputs(4'b0000, 4'b1010, "reset inactive");
		@(negedge clk);
		reset = 1'b0;
		repeat (2) @(posedge clk);
		expect_outputs(4'b0000, 4'b1010, "released inactive");

		// Assert all four raw comparator pins. The first destination edge may
		// update only the metastability stage; the second updates the visible
		// synchronized level. Independent polarities must agree semantically.
		@(negedge clk);
		compare_pin = 4'b0011;
		@(posedge clk);
		expect_outputs(4'b0000, 4'b1010, "first synchronizer edge");
		@(posedge clk);
		expect_outputs(4'b1111, 4'b1010, "second synchronizer edge");

		// The raw discharge output is combinational and its two polarities are
		// independent of comparator polarity.
		@(negedge clk);
		discharge_active = 1'b1;
		expect_outputs(4'b1111, 4'b0101, "discharge asserted");
		@(negedge clk);
		discharge_active = 1'b0;
		expect_outputs(4'b1111, 4'b1010, "discharge released");

		// A transition one nanosecond after an edge cannot appear until two
		// later destination captures. This is a deterministic simulation of the
		// synchronizer latency, not a metastability model.
		@(posedge clk);
		#1;
		compare_pin = 4'b1100;
		@(posedge clk);
		expect_outputs(4'b1111, 4'b1010, "post-edge first capture");
		@(posedge clk);
		expect_outputs(4'b0000, 4'b1010, "post-edge second capture");

		// A transition one nanosecond before an edge is captured by stage one at
		// that edge but is still invisible until the following destination edge.
		@(negedge clk);
		#4;
		compare_pin = 4'b0011;
		@(posedge clk);
		expect_outputs(4'b0000, 4'b1010, "pre-edge first capture");
		@(posedge clk);
		expect_outputs(4'b1111, 4'b1010, "pre-edge second capture");

		// Reset dominates an asserted raw input and returns both synchronizer
		// stages to the parameter-selected inactive level.
		@(negedge clk);
		reset = 1'b1;
		@(posedge clk);
		expect_outputs(4'b0000, 4'b1010, "reset dominance");

		$display("PASS: production ES5506 PAR pin synchronization and polarity");
		$finish;
	end
endmodule

`default_nettype wire
