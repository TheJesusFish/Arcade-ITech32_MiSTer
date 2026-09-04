// SPDX-License-Identifier: GPL-3.0-or-later
//
// Raw board boundary for the ES5506 PAR comparator and discharge request.
// This module normalizes digital polarity only; it does not model the external
// resistor/capacitor network, comparator threshold, or PCB connectivity.

`timescale 1ns/1ps

module itech32_es5506_par_pins #(
	parameter bit POT_COMPARE_ACTIVE_HIGH = 1'b1,
	parameter bit POT_RES_ACTIVE_HIGH     = 1'b1
) (
	input  logic clk,
	input  logic reset,
	input  logic pot_compare_pin_i,
	input  logic discharge_active_i,
	output logic comparator_tripped_o,
	output logic pot_res_pin_o
);
	localparam logic POT_COMPARE_INACTIVE_LEVEL =
		POT_COMPARE_ACTIVE_HIGH ? 1'b0 : 1'b1;

	// The first stage has no functional fanout other than the second stage.
	// Keep both stages in fabric and recognizable by Quartus metastability
	// analysis; physical promotion still requires final pin/SDC/MTBF review.
	(* async_reg = "true", preserve, useioff = 0,
	   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic pot_compare_meta_q;
	(* async_reg = "true", preserve, useioff = 0,
	   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic pot_compare_sync_q;

	always_ff @(posedge clk) begin
		if (reset) begin
			pot_compare_meta_q <= POT_COMPARE_INACTIVE_LEVEL;
			pot_compare_sync_q <= POT_COMPARE_INACTIVE_LEVEL;
		end else begin
			pot_compare_meta_q <= pot_compare_pin_i;
			pot_compare_sync_q <= pot_compare_meta_q;
		end
	end

	assign comparator_tripped_o = POT_COMPARE_ACTIVE_HIGH ?
		pot_compare_sync_q : ~pot_compare_sync_q;
	assign pot_res_pin_o = POT_RES_ACTIVE_HIGH ?
		discharge_active_i : ~discharge_active_i;
endmodule
