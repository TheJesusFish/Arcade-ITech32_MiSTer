// SPDX-License-Identifier: GPL-2.0-or-later
// Coordinates a quiesced switch between two always-running PLL clocks.
`timescale 1ns/1ps

module itech32_clock_mode_control #(
	parameter integer HOLD_CYCLES = 16,
	parameter integer SETTLE_CYCLES = 16,
	parameter integer LOCK_CYCLES = 16
) (
	input  logic ref_clk,
	input  logic pll_ready,
	input  logic transport_locked,
	input  logic memory_quiesced,
	input  logic request_mame,
	output logic select_mame,
	output logic switch_reset,
	output logic transport_reset,
	output logic preserve_memory
);
	typedef enum logic [2:0] {
		ST_WAIT_SOURCE,
		ST_START_PLL,
		ST_RUN,
		ST_QUIESCE,
		ST_HOLD,
		ST_SETTLE,
		ST_RELOCK
	} state_t;

	localparam integer HOLD_SETTLE_MAX =
		(HOLD_CYCLES > SETTLE_CYCLES) ? HOLD_CYCLES : SETTLE_CYCLES;
	localparam integer MAX_DELAY =
		(HOLD_SETTLE_MAX > LOCK_CYCLES) ? HOLD_SETTLE_MAX : LOCK_CYCLES;
	localparam integer COUNT_WIDTH = (MAX_DELAY <= 1) ? 1 : $clog2(MAX_DELAY);

	(* preserve, useioff = 0,
	   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [2:0] pll_ready_sync;
	(* preserve, useioff = 0,
	   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [2:0] transport_locked_sync;
	(* preserve, useioff = 0,
	   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [2:0] memory_quiesced_sync;
	(* preserve, useioff = 0,
	   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [2:0] request_sync;
	state_t state;
	logic switching;
	logic [COUNT_WIDTH-1:0] delay_count;

	// State zero is the power-up state on Cyclone V, so these combinational
	// outputs hold the board and transport PLL reset before the first ref edge.
	assign switch_reset = state != ST_RUN;
	assign transport_reset = state == ST_WAIT_SOURCE || state == ST_HOLD ||
		state == ST_SETTLE;
	assign preserve_memory = switching;

	always_ff @(posedge ref_clk) begin
		pll_ready_sync <= {pll_ready_sync[1:0], pll_ready};
		transport_locked_sync <= {transport_locked_sync[1:0], transport_locked};
		memory_quiesced_sync <= {memory_quiesced_sync[1:0], memory_quiesced};
		request_sync <= {request_sync[1:0], request_mame};

		if (!pll_ready_sync[2]) begin
			select_mame <= 1'b0;
			switching <= 1'b0;
			state <= ST_WAIT_SOURCE;
			delay_count <= '0;
		end else begin
			case (state)
				ST_WAIT_SOURCE: begin
					// Start the transport only after both source PLLs are stable.
					switching <= 1'b0;
					delay_count <= '0;
					state <= ST_START_PLL;
				end

				ST_START_PLL: begin
					// Startup is a cold-memory boundary. Do not release the board
					// until the transport lock has remained synchronized and high.
					if (!transport_locked_sync[2]) begin
						delay_count <= '0;
					end else if (delay_count == COUNT_WIDTH'(LOCK_CYCLES - 1)) begin
						delay_count <= '0;
						state <= ST_RUN;
					end else begin
						delay_count <= delay_count + 1'b1;
					end
				end

				ST_RUN: begin
					delay_count <= '0;
					if (!transport_locked_sync[2]) begin
						// An unrequested transport-lock loss is a true cold reset.
						switching <= 1'b0;
						state <= ST_WAIT_SOURCE;
					end else if (request_sync[2] != select_mame) begin
						// Assert the board reset while the old carrier still runs.
						// The DDR service explicitly acknowledges when every accepted
						// transaction has drained.
						switching <= 1'b1;
						state <= ST_QUIESCE;
					end
				end

				ST_QUIESCE: begin
					if (!transport_locked_sync[2]) begin
						// The clock failed before the deliberate stop, so retained
						// memory state can no longer be treated as trustworthy.
						switching <= 1'b0;
						state <= ST_WAIT_SOURCE;
					end else if (memory_quiesced_sync[2]) begin
						delay_count <= '0;
						state <= ST_HOLD;
					end
				end

				ST_HOLD: begin
					if (delay_count == COUNT_WIDTH'(HOLD_CYCLES - 1)) begin
						select_mame <= request_sync[2];
						delay_count <= '0;
						state <= ST_SETTLE;
					end else begin
						delay_count <= delay_count + 1'b1;
					end
				end

				ST_SETTLE: begin
					if (delay_count == COUNT_WIDTH'(SETTLE_CYCLES - 1)) begin
						delay_count <= '0;
						state <= ST_RELOCK;
					end else begin
						delay_count <= delay_count + 1'b1;
					end
				end

				ST_RELOCK: begin
					if (!transport_locked_sync[2]) begin
						delay_count <= '0;
					end else if (delay_count == COUNT_WIDTH'(LOCK_CYCLES - 1)) begin
						delay_count <= '0;
						if (request_sync[2] != select_mame) begin
							// The menu changed again during relock. Memory is still
							// quiesced, so repeat the protected carrier change.
							state <= ST_HOLD;
						end else begin
							switching <= 1'b0;
							state <= ST_RUN;
						end
					end else begin
						delay_count <= delay_count + 1'b1;
					end
				end

				default: begin
					select_mame <= 1'b0;
					switching <= 1'b0;
					state <= ST_WAIT_SOURCE;
					delay_count <= '0;
				end
			endcase
		end
	end
endmodule
