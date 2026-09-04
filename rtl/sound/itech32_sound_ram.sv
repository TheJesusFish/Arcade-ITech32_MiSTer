// SPDX-License-Identifier: GPL-3.0-or-later
//
// Rev-2 sound-board 8 KiB work RAM with one registered CPU port.

`timescale 1ns/1ps

module itech32_sound_ram (
	input  logic        clk,
	input  logic        reset,
	input  logic        request,
	input  logic        write,
	input  logic [12:0] addr,
	input  logic [7:0]  wdata,
	output logic        response_valid,
	output logic [7:0]  rdata
);

	// Keep payload and read data reset-free so Quartus can infer M10Ks. The
	// response-valid bit is the only visibility qualifier.
	(* ramstyle = "M10K, no_rw_check" *) logic [7:0] memory [0:8191];

	always_ff @(posedge clk) begin
		if (request) begin
			if (write)
				memory[addr] <= wdata;
			rdata <= memory[addr];
		end
	end

	// request is a one-cycle launch from the board bridge; the RAM data and
	// this response flag become visible together in the following cycle.
	always_ff @(posedge clk) begin
		if (reset)
			response_valid <= 1'b0;
		else
			response_valid <= request;
	end

endmodule
