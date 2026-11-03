// SPDX-License-Identifier: GPL-3.0-or-later
// Graphics-ROM front for itech32_ddr_memory: one 128-byte read-ahead line in
// an M10K with its single-outstanding request owner.
//
// The blitter consumes long, sequential raw/RLE byte streams. A single 64-bit
// beat made every eighth byte contend with scanout and audio for a complete
// random DDR transaction, so the scheduler fills this line with a 16-beat
// burst. The 32 MiB graphics ROM remains in framework DDR; only the blitter's
// immediate sequential working set occupies embedded memory.
//
// Resident hit schedule: capture at T0, synchronous RAM/tag probe at T1, local
// ACK/data during T1..T2, completion at T2. Only a miss waits for the shared
// scheduler. A refill never overlaps a legal probe of this single line; the
// first re-probe is after its final write.
`timescale 1ns/1ps

module itech32_ddr_grom_cache (
	input  logic        clk,
	input  logic        reset,
	// Reload/quiesce boundary: cancel the producer and the front owner.
	input  logic        cancel,
	// ROM download boundary: forget the resident line.
	input  logic        invalidate,
	// Blitter source bytes wrap modulo this many 512 KiB pages (16..127, or
	// 4..127 for profiles whose addresses stay below 16 MiB).
	input  logic [6:0]  grom_pages,

	input  logic        grom_req,
	input  logic [25:0] grom_addr,
	output logic        grom_ack,
	// The client addresses bytes but receives the containing aligned qword.
	output logic [63:0] grom_rdata,

	// The scheduler's burst states currently own the line refill.
	input  logic        miss_scheduler_active,
	output logic        miss_pending,
	// Mapped source address of the owned request; the refill line base/tag.
	output logic [25:0] front_effective_addr,

	// Burst refill: the launch invalidates the line, each beat writes one
	// qword, and a completed non-discarded burst publishes the new tag.
	input  logic        refill_launch,
	input  logic        refill_write,
	input  logic [3:0]  refill_beat,
	input  logic [63:0] refill_data,
	input  logic        refill_publish,
	input  logic [18:0] refill_tag
);
	typedef enum logic [2:0] {
		GF_FREE         = 3'd0,
		GF_PROBE        = 3'd1,
		GF_RESPONSE     = 3'd2,
		GF_MISS_WAIT    = 3'd3,
		GF_WAIT_RELEASE = 3'd4
	} grom_front_state_t;

	grom_front_state_t front_state;
	(* ramstyle = "M10K, no_rw_check" *) logic [63:0] read_ahead [0:15];
	logic [63:0] read_ahead_q;
	logic        read_ahead_valid;
	logic [18:0] read_ahead_tag;
	logic [25:0] front_addr_q;
	logic [25:0] front_effective_q;
	logic        front_hit_q;
	logic [25:0] effective_addr;
	logic        request_held;

	// MAME wraps every blitter source byte by the actual GROM region size
	// (8.5 MiB = 17 pages for Time Killers/BloodStorm, 0x2080000 = 65 pages for
	// SFTM). Reduce only the 7-bit page, leaving the 19 byte-offset wires
	// untouched. A 7-bit page is below 8 x pages for pages >= 16, so three
	// narrow conditional subtracts (4N, 2N, N) are an exact modulo without a
	// divider or a new pipeline stage. GROMs under 16 MiB have no bank bits
	// (MAME's grom_bank_mask; profile grom_banked), so their addresses keep
	// the page below 32 and the same chain is exact down to 4 pages (Golden
	// Tee's 12).
	function automatic logic [25:0] grom_wrap(input logic [25:0] address,
		input logic [6:0] pages);
		logic [8:0] page;
		logic [8:0] n1;
		begin
			page = {2'b00, address[25:19]};
			n1 = {2'b00, pages};
			if (page >= {n1[6:0], 2'b00}) page = page - {n1[6:0], 2'b00};
			if (page >= {n1[7:0], 1'b0}) page = page - {n1[7:0], 1'b0};
			if (page >= n1) page = page - n1;
			grom_wrap = {page[6:0], address[18:0]};
		end
	endfunction

	always_comb begin
		effective_addr = grom_wrap(grom_addr, grom_pages);
		request_held = grom_req && grom_addr == front_addr_q;
		miss_pending = front_state == GF_MISS_WAIT && request_held && !cancel &&
			!miss_scheduler_active;
		// GROM exposes the synchronous RAM output after its registered probe,
		// with no extra ACK register. Keep the cancel tree off this response.
		grom_ack = front_state == GF_RESPONSE && front_hit_q;
		grom_rdata = read_ahead_q;
		front_effective_addr = front_effective_q;
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			front_state <= GF_FREE;
			front_addr_q <= 26'd0;
			front_effective_q <= 26'd0;
			front_hit_q <= 1'b0;
			read_ahead_q <= 64'd0;
			read_ahead_valid <= 1'b0;
			read_ahead_tag <= 19'd0;
		end else begin
			if (cancel) begin
				if (front_state == GF_WAIT_RELEASE) begin
					if (!grom_req) front_state <= GF_FREE;
				end else begin
					front_state <= GF_FREE;
				end
			end else begin
				case (front_state)
					GF_FREE: begin
						if (grom_req && !miss_scheduler_active) begin
							front_addr_q <= grom_addr;
							front_effective_q <= effective_addr;
							front_state <= GF_PROBE;
						end
					end
					GF_PROBE: begin
						if (!request_held) begin
							front_state <= GF_FREE;
						end else begin
							read_ahead_q <= read_ahead[front_effective_q[6:3]];
							front_hit_q <= read_ahead_valid &&
								read_ahead_tag == front_effective_q[25:7] &&
								!miss_scheduler_active;
							front_state <= GF_RESPONSE;
						end
					end
					GF_RESPONSE: begin
						if (front_hit_q) begin
							front_state <= GF_WAIT_RELEASE;
						end else if (!request_held) begin
							front_state <= GF_FREE;
						end else begin
							front_state <= GF_MISS_WAIT;
						end
					end
					GF_MISS_WAIT: begin
						if (!request_held)
							front_state <= GF_FREE;
					end
					GF_WAIT_RELEASE: begin
						if (!grom_req) begin
							front_state <= GF_FREE;
						end else if (grom_addr != front_addr_q) begin
							front_addr_q <= grom_addr;
							front_effective_q <= effective_addr;
							front_state <= GF_PROBE;
						end
					end
					default: front_state <= GF_FREE;
				endcase
			end

			if (refill_launch)
				read_ahead_valid <= 1'b0;
			if (refill_write)
				read_ahead[refill_beat] <= refill_data;
			if (refill_publish) begin
				read_ahead_tag <= refill_tag;
				read_ahead_valid <= 1'b1;
				// Re-probe the still-held request that caused this refill.
				if (front_state == GF_MISS_WAIT && request_held && !cancel)
					front_state <= GF_PROBE;
			end
			// A reload boundary is stronger than any completion from the old image.
			if (invalidate)
				read_ahead_valid <= 1'b0;
		end
	end

`ifdef VERILATOR
	logic sim_ack_q;
	logic sim_completed_valid;
	logic [25:0] sim_completed_addr;
	always_ff @(posedge clk) begin
		if (reset) begin
			sim_ack_q <= 1'b0;
			sim_completed_valid <= 1'b0;
			sim_completed_addr <= 26'd0;
		end else begin
			assert (!(grom_ack && sim_ack_q))
				else $fatal(1, "GROM ACK lasted more than one carrier clock");
			sim_ack_q <= grom_ack;
			if (!grom_req || grom_addr != sim_completed_addr)
				sim_completed_valid <= 1'b0;
			if (grom_ack && !cancel) begin
				assert (read_ahead_valid && !miss_scheduler_active &&
					read_ahead_tag == front_effective_q[25:7])
					else $fatal(1, "GROM ACK lacks complete matching cache line");
				if (grom_req) begin
					assert (!(sim_completed_valid && sim_completed_addr == front_addr_q))
						else $fatal(1, "GROM request signature acknowledged twice");
					sim_completed_valid <= 1'b1;
					sim_completed_addr <= front_addr_q;
				end
			end
			if (!cancel && front_state == GF_PROBE)
				assert (!miss_scheduler_active)
					else $fatal(1, "GROM probe overlaps single-line refill");
		end
	end
`endif

endmodule
