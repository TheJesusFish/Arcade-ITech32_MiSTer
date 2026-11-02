// SPDX-License-Identifier: GPL-3.0-or-later
// Sound-CPU program-ROM front for itech32_ddr_memory: a registered two-way,
// 512-set cache of DDR qwords with its single-outstanding request owner.
//
// Resident hits are answered here without a DDR scheduler turn. A miss is
// exposed as miss_pending; the scheduler then owns the refill and either
// writes the returned qword (refill) and completes the request (respond), or
// abandons it. Cycle schedule for a hit: synchronous tag/data read at T0,
// compare/extract at T1, registered ACK at T2, which fits before the 6809's
// next Q edge.
`timescale 1ns/1ps

module itech32_ddr_sound_cache (
	input  logic        clk,
	input  logic        reset,
	// Reload/quiesce boundary: cancel the producer and the front owner.
	input  logic        cancel,
	// ROM download boundary: forget every resident line.
	input  logic        invalidate,

	input  logic        sound_req,
	input  logic [18:0] sound_addr,
	output logic        sound_ack,
	output logic [7:0]  sound_rdata,

	// The scheduler's generic command states currently own this front's miss.
	input  logic        miss_scheduler_active,
	// Held SOUND miss ready for a scheduler grant / still owned during capture.
	output logic        miss_pending,
	output logic        miss_owned,
	output logic [18:0] front_addr,

	// A DDR read beat for the owned SOUND operation. The data and tag are
	// written even if the request was cancelled; only publication is gated.
	input  logic        refill,
	input  logic [38:0] refill_signature,
	input  logic [63:0] refill_data,
	input  logic        refill_discard,
	// The registered response stage for the owned SOUND operation.
	input  logic        respond,
	input  logic [38:0] respond_signature,
	input  logic [7:0]  respond_data
);
	typedef enum logic [2:0] {
		SF_FREE         = 3'd0,
		SF_HIT_RESPONSE = 3'd1,
		SF_MISS_WAIT    = 3'd2,
		SF_WAIT_RELEASE = 3'd3,
		SF_PROBE_RESULT = 3'd4
	} sound_front_state_t;

	sound_front_state_t front_state;
	// The 6809 alternates fixed and banked program regions whose physical lines
	// can share a low-nine-qword index. Two registered ways retain one line from
	// each region without changing the three-edge local hit contract. Each way is
	// a canonical synchronous 1W/1R M10K body; only validity resets.
	(* ramstyle = "M10K, no_rw_check" *) logic [70:0] way0 [0:511];
	(* ramstyle = "M10K, no_rw_check" *) logic [70:0] way1 [0:511];
	logic [70:0] way0_q;
	logic [70:0] way1_q;
	logic [511:0] valid_way0;
	logic [511:0] valid_way1;
	// One bit per set names the next victim only when both ways are valid. It is
	// intentionally not reset: invalid-first fill makes stale state unobservable.
	logic [511:0] victim;
	logic        publish;
	logic [18:0] front_addr_q;
	logic [7:0]  front_data_q;
	logic        front_hit_q;
	logic        front_hit_way_q;
	logic [1:0]  front_valid_q;
	logic        front_victim_q;
	logic        refill_way_q;
	logic        way0_hit;
	logic        way1_hit;
	logic [7:0]  way0_data;
	logic [7:0]  way1_data;
	logic        hit_touch;
	logic        probe_start;
	logic        request_held;

	function automatic logic [7:0] line_byte(
		input logic [63:0] line,
		input logic [2:0] index
	);
		line_byte = line[index * 8 +: 8];
	endfunction

	assign front_addr = front_addr_q;
	// Both way reads complete at T1. Extract eight bits per way before the final
	// select so the response register never sees a 64-bit way mux.
	assign way0_hit = front_valid_q[0] && way0_q[70:64] == front_addr_q[18:12];
	assign way1_hit = front_valid_q[1] && way1_q[70:64] == front_addr_q[18:12];
	assign way0_data = line_byte(way0_q[63:0], front_addr_q[2:0]);
	assign way1_data = line_byte(way1_q[63:0], front_addr_q[2:0]);
	assign request_held = sound_req && sound_addr == front_addr_q;
	assign hit_touch = !cancel && front_state == SF_HIT_RESPONSE &&
		request_held && front_hit_q;

	always_comb begin
		// A canceled accepted read may still physically complete. Its data/tag
		// can be written but the entry is not published; reload invalidation is
		// stronger still.
		publish = !cancel && !refill_discard &&
			front_state == SF_MISS_WAIT && request_held &&
			refill_signature == {20'd0, front_addr_q};
		probe_start = !cancel && sound_req && !miss_scheduler_active &&
			(front_state == SF_FREE ||
			 (front_state == SF_WAIT_RELEASE && sound_addr != front_addr_q));
		miss_owned = !cancel && front_state == SF_MISS_WAIT && request_held;
		miss_pending = miss_owned && !miss_scheduler_active;
	end

	// Canonical synchronous old-data RAM templates. The single-outstanding SOUND
	// owner prevents a probe during refill, so no same-edge RDW value is consumed
	// (asserted below). No reset or bulk clear touches either RAM body.
	always_ff @(posedge clk) begin
		if (refill && !refill_way_q)
			way0[refill_signature[11:3]] <= {refill_signature[18:12], refill_data};
		if (probe_start)
			way0_q <= way0[sound_addr[11:3]];
	end

	always_ff @(posedge clk) begin
		if (refill && refill_way_q)
			way1[refill_signature[11:3]] <= {refill_signature[18:12], refill_data};
		if (probe_start)
			way1_q <= way1[sound_addr[11:3]];
	end

	always_ff @(posedge clk) begin
		sound_ack <= 1'b0;
		if (reset) begin
			front_state <= SF_FREE;
			front_addr_q <= 19'd0;
			front_data_q <= 8'hff;
			front_hit_q <= 1'b0;
			front_hit_way_q <= 1'b0;
			front_valid_q <= 2'b00;
			front_victim_q <= 1'b0;
			refill_way_q <= 1'b0;
			valid_way0 <= '0;
			valid_way1 <= '0;
			sound_rdata <= 8'hff;
		end else begin
			if (refill) begin
				if (refill_way_q)
					valid_way1[refill_signature[11:3]] <= publish;
				else
					valid_way0[refill_signature[11:3]] <= publish;
			end
			// One metadata write point keeps the replacement decoder narrow. A
			// successful refill and a resident-hit ACK are mutually exclusive.
			if (refill && publish)
				victim[refill_signature[11:3]] <= !refill_way_q;
			else if (hit_touch)
				victim[front_addr_q[11:3]] <= !front_hit_way_q;
			if (probe_start) begin
				front_addr_q <= sound_addr;
				front_valid_q <= {valid_way1[sound_addr[11:3]],
					valid_way0[sound_addr[11:3]]};
				front_victim_q <= victim[sound_addr[11:3]];
			end
			if (cancel) begin
				if (front_state != SF_WAIT_RELEASE || !sound_req)
					front_state <= SF_FREE;
			end else begin
				case (front_state)
					SF_FREE, SF_WAIT_RELEASE: begin
						if (probe_start)
							front_state <= SF_PROBE_RESULT;
						else if (!sound_req)
							front_state <= SF_FREE;
					end
					SF_PROBE_RESULT: begin
						if (!request_held) begin
							front_state <= SF_FREE;
						end else begin
							// Way0 wins only the impossible duplicate-tag case; the
							// assertion below keeps that priority from hiding corruption.
							front_data_q <= way0_hit ? way0_data : way1_data;
							front_hit_q <= way0_hit || way1_hit;
							front_hit_way_q <= !way0_hit && way1_hit;
							if (!front_valid_q[0])
								refill_way_q <= 1'b0;
							else if (!front_valid_q[1])
								refill_way_q <= 1'b1;
							else
								refill_way_q <= front_victim_q;
							front_state <= SF_HIT_RESPONSE;
						end
					end
					SF_HIT_RESPONSE: begin
						if (!request_held) begin
							front_state <= SF_FREE;
						end else if (front_hit_q) begin
							sound_rdata <= front_data_q;
							sound_ack <= 1'b1;
							front_state <= SF_WAIT_RELEASE;
						end else begin
							front_state <= SF_MISS_WAIT;
						end
					end
					SF_MISS_WAIT: begin
						if (!request_held)
							front_state <= SF_FREE;
					end
					default: front_state <= SF_FREE;
				endcase
			end
			// The scheduler's response completes only the miss this front still
			// owns, and takes priority over the front's own transition.
			if (respond && !cancel && request_held && front_state == SF_MISS_WAIT &&
				{20'd0, front_addr_q} == respond_signature) begin
				sound_rdata <= respond_data;
				sound_ack <= 1'b1;
				front_state <= SF_WAIT_RELEASE;
			end
			// A reload boundary is stronger than a same-edge publication.
			if (invalidate) begin
				valid_way0 <= '0;
				valid_way1 <= '0;
			end
		end
	end

`ifdef VERILATOR
	logic sim_ack_q;
	logic sim_ack_authorized_q;
	logic sim_completed_valid;
	logic [18:0] sim_completed_addr;
	always_ff @(posedge clk) begin
		if (reset) begin
			sim_ack_q <= 1'b0;
			sim_ack_authorized_q <= 1'b0;
			sim_completed_valid <= 1'b0;
			sim_completed_addr <= 19'd0;
		end else begin
			sim_ack_q <= sound_ack;
			sim_ack_authorized_q <= !cancel && request_held &&
				((front_state == SF_HIT_RESPONSE && front_hit_q) ||
				 (respond && front_state == SF_MISS_WAIT &&
				  respond_signature == {20'd0, front_addr_q}));
			assert (!(sound_ack && sim_ack_q))
				else $fatal(1, "SOUND ACK lasted more than one carrier clock");
			if (!sound_req || sound_addr != sim_completed_addr)
				sim_completed_valid <= 1'b0;
			if (sound_ack) begin
				assert (sim_ack_authorized_q && front_state == SF_WAIT_RELEASE)
					else $fatal(1, "SOUND ACK lacks matching front ownership");
				if (sound_req) begin
					assert (!(sim_completed_valid && sim_completed_addr == front_addr_q))
						else $fatal(1, "SOUND request signature acknowledged twice");
					sim_completed_valid <= 1'b1;
					sim_completed_addr <= front_addr_q;
				end
			end
			assert (!(probe_start && refill))
				else $fatal(1, "SOUND synchronous cache read overlaps refill");
			assert (!(refill && hit_touch))
				else $fatal(1, "SOUND cache refill and hit touch overlap");
			if (front_state == SF_PROBE_RESULT && request_held)
				assert (!(way0_hit && way1_hit))
					else $fatal(1, "SOUND duplicate valid tag across cache ways");
			if (probe_start)
				assert (!miss_scheduler_active)
					else $fatal(1, "SOUND probe overlaps owned refill");
		end
	end
`endif

endmodule
