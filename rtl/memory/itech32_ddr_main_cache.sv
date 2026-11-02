// SPDX-License-Identifier: GPL-3.0-or-later
// Main-CPU program-ROM front for itech32_ddr_memory: thirty-two direct-mapped
// 128-byte read-ahead lines with their single-outstanding request owner.
//
// The 68020 fetches instruction words from framework DDR. These lines turn
// sequential fetches and short branch loops into synchronous embedded-memory
// hits while keeping the complete 4 MiB ROM in DDR. Tags stay in flops; only the
// reset-free 32 Kibit data body is forced into M10K, following Intel's
// registered-read template. Hits never enter the shared scheduler; only a
// miss is exposed (miss_pending). The scheduler then owns the 16-beat line
// refill: launch invalidates the set, each beat writes one qword, and a
// completed non-discarded burst publishes the tag and re-probes the request.
`timescale 1ns/1ps

module itech32_ddr_main_cache #(
	parameter integer SET_BITS = 5,
	parameter integer TAG_BITS = 22 - 7 - SET_BITS
) (
	input  logic                clk,
	input  logic                reset,
	// Reload/quiesce/loader boundary: cancel the producer and the front owner.
	input  logic                cancel,
	// ROM download boundaries and loader writes: forget every resident line.
	input  logic                invalidate_all,

	input  logic                main_req,
	input  logic [21:0]         main_addr,
	output logic                main_ack,
	output logic [31:0]         main_rdata,

	// The scheduler's burst states currently own a line refill.
	input  logic                miss_scheduler_active,
	output logic                miss_pending,
	// The front still holds its miss (without the cancel term).
	output logic                miss_held,
	output logic [21:0]         front_addr,

	input  logic                refill_launch,
	input  logic [SET_BITS-1:0] refill_set,
	input  logic [3:0]          refill_beat,
	input  logic                refill_write,
	input  logic [63:0]         refill_data,
	input  logic                refill_publish,
	input  logic [TAG_BITS-1:0] refill_tag
);
	localparam integer SETS = 1 << SET_BITS;

	typedef enum logic [2:0] {
		MF_FREE            = 3'd0,
		MF_PROBE           = 3'd1,
		MF_HIT_RESPONSE    = 3'd2,
		MF_MISS_WAIT       = 3'd3,
		MF_REFILL_PROBE    = 3'd4,
		MF_REFILL_RESPONSE = 3'd5,
		MF_WAIT_RELEASE    = 3'd6
	} main_front_state_t;

	main_front_state_t front_state;
	(* ramstyle = "M10K, no_rw_check" *) logic [63:0] read_ahead [0:SETS*16-1];
	logic [63:0] read_ahead_q;
	logic [SETS-1:0] read_ahead_valid;
	logic [TAG_BITS-1:0] read_ahead_tag [0:SETS-1];
	logic [21:0] front_addr_q;
	logic        front_hit_q;
	logic [2:0]  front_byte_q;
	logic        front_collision_q;
	logic        probe_start;
	logic        probe_enable;
	logic [21:0] probe_addr;
	logic        probe_same_set;
	logic        probe_same_word;
	logic        refill_same_set;
	logic        request_held;
	logic        line_resident;
	integer      tag_index;

	function automatic logic [7:0] line_byte(
		input logic [63:0] line,
		input logic [2:0] index
	);
		line_byte = line[index * 8 +: 8];
	endfunction

	function automatic logic [31:0] line_dword_be(
		input logic [63:0] line,
		input logic [2:0] index
	);
		logic [2:0] base;
		begin
			base = {index[2], 2'b00};
			line_dword_be = {
				line_byte(line, base),
				line_byte(line, base + 3'd1),
				line_byte(line, base + 3'd2),
				line_byte(line, base + 3'd3)
			};
		end
	endfunction

	always_comb begin
		front_addr = front_addr_q;
		request_held = main_req && main_addr == front_addr_q;
		miss_held = front_state == MF_MISS_WAIT && request_held;
		miss_pending = miss_held && !cancel && !miss_scheduler_active;
		refill_same_set = miss_scheduler_active &&
			refill_set == front_addr_q[11:7];
		// main_addr is already registered by main_bus. Launch the synchronous
		// read at acceptance, while capturing the identical request signature.
		// Refill probes still use the held address after complete publication.
		probe_start = main_req && !miss_scheduler_active &&
			((front_state == MF_FREE) ||
			 (front_state == MF_WAIT_RELEASE && main_addr != front_addr_q));
		probe_enable = !cancel && (probe_start ||
			((front_state == MF_PROBE || front_state == MF_REFILL_PROBE) &&
			 request_held));
		probe_addr = probe_start ? main_addr : front_addr_q;
		probe_same_set = miss_scheduler_active && refill_set == probe_addr[11:7];
		probe_same_word = refill_write &&
			{refill_set, refill_beat} == probe_addr[11:3];
		// A probe hit is answered only if the line is still resident and no
		// refill of the same set is in flight.
		line_resident = front_hit_q && read_ahead_valid[front_addr_q[11:7]] &&
			read_ahead_tag[front_addr_q[11:7]] == front_addr_q[21:12] &&
			!front_collision_q && !refill_same_set;
	end

	always_ff @(posedge clk) begin
		main_ack <= 1'b0;
		if (reset) begin
			front_state <= MF_FREE;
			main_rdata <= 32'hffff_ffff;
			front_addr_q <= 22'd0;
			front_hit_q <= 1'b0;
			front_byte_q <= 3'd0;
			front_collision_q <= 1'b0;
			read_ahead_valid <= '0;
			for (tag_index = 0; tag_index < SETS; tag_index = tag_index + 1)
				read_ahead_tag[tag_index] <= '0;
		end else begin
			// The RAM read remains in this same clocked process as the refill
			// write so Quartus can retain the canonical 1W/1R M10K.
			if (probe_enable) begin
				read_ahead_q <= read_ahead[probe_addr[11:3]];
`ifdef VERILATOR
				// Undefined same-word data must never escape the ownership checks.
				if (probe_same_word)
					read_ahead_q <= 64'hc011_1de5_bad0_cace;
`endif
				front_hit_q <= read_ahead_valid[probe_addr[11:7]] &&
					read_ahead_tag[probe_addr[11:7]] == probe_addr[21:12] &&
					!probe_same_set;
				front_byte_q <= {probe_addr[2], 2'b00};
				front_collision_q <= probe_same_set;
			end
			if (cancel) begin
				// Preserve an already-completed signature across a non-reset
				// boundary. Otherwise a still-held request could be accepted twice
				// after the boundary clears.
				if (front_state == MF_WAIT_RELEASE) begin
					if (!main_req)
						front_state <= MF_FREE;
				end else begin
					front_state <= MF_FREE;
				end
			end else begin
				case (front_state)
					MF_FREE: begin
						// An accepted burst from a canceled request must drain before
						// the single-outstanding port can capture another signature.
						if (probe_start) begin
							front_addr_q <= main_addr;
							front_state <= MF_HIT_RESPONSE;
						end
					end

					MF_PROBE, MF_REFILL_PROBE: begin
						if (!request_held) begin
							front_state <= MF_FREE;
						end else begin
							front_state <= front_state == MF_PROBE
								? MF_HIT_RESPONSE : MF_REFILL_RESPONSE;
						end
					end

					MF_HIT_RESPONSE, MF_REFILL_RESPONSE: begin
						if (!request_held) begin
							front_state <= MF_FREE;
						end else if (line_resident) begin
							main_rdata <= line_dword_be(read_ahead_q, front_byte_q);
							main_ack <= 1'b1;
							front_state <= MF_WAIT_RELEASE;
						end else begin
							// Invalidate before any refill word can be published. A
							// failed publication/probe is never acknowledged; retry
							// through the miss scheduler using the same signature.
							read_ahead_valid[front_addr_q[11:7]] <= 1'b0;
							front_state <= MF_MISS_WAIT;
						end
					end

					MF_MISS_WAIT: begin
						// The scheduler owns refill launch/completion. A producer
						// cancellation suppresses its response; an accepted DDR
						// burst still drains before MF_FREE can accept another.
						if (!request_held)
							front_state <= MF_FREE;
					end

					MF_WAIT_RELEASE: begin
						if (!main_req) begin
							front_state <= MF_FREE;
						end else if (probe_start) begin
							// The main bus normally supplies a one-cycle low gap, but
							// the memory interface also supports changed held-high traffic.
							front_addr_q <= main_addr;
							front_state <= MF_HIT_RESPONSE;
						end
					end

					default: front_state <= MF_FREE;
				endcase
			end

			// The selector granted this front's miss: invalidate its set.
			if (refill_launch)
				read_ahead_valid[front_addr_q[11:7]] <= 1'b0;
			if (refill_write)
				read_ahead[{refill_set, refill_beat}] <= refill_data;
			if (refill_publish) begin
				read_ahead_tag[refill_set] <= refill_tag;
				read_ahead_valid[refill_set] <= 1'b1;
				if (miss_held)
					front_state <= MF_REFILL_PROBE;
			end
			// Reload boundaries and loader writes are stronger than any
			// completion from the old image.
			if (invalidate_all)
				read_ahead_valid <= '0;
		end
	end

`ifdef VERILATOR
	logic                sim_ack_q;
	logic                sim_ack_authorized_q;
	logic                sim_completed_valid;
	logic [21:0]         sim_completed_addr;
	logic                sim_refill_response_q;
	logic                sim_refill_discard_q;
	logic [SET_BITS-1:0] sim_refill_set_q;
	always_ff @(posedge clk) begin
		if (reset) begin
			sim_ack_q <= 1'b0;
			sim_ack_authorized_q <= 1'b0;
			sim_completed_valid <= 1'b0;
			sim_completed_addr <= 22'd0;
			sim_refill_response_q <= 1'b0;
			sim_refill_discard_q <= 1'b0;
			sim_refill_set_q <= '0;
		end else begin
			assert (!(main_ack && sim_ack_q))
				else $fatal(1, "main-ROM ACK lasted more than one carrier clock");
			sim_ack_q <= main_ack;
			sim_ack_authorized_q <= !cancel && request_held &&
				(front_state == MF_HIT_RESPONSE ||
				 front_state == MF_REFILL_RESPONSE) && line_resident;

			if (!main_req) begin
				sim_completed_valid <= 1'b0;
			end else if (sim_completed_valid && main_addr != sim_completed_addr) begin
				sim_completed_valid <= 1'b0;
			end
			if (main_ack) begin
				assert (sim_ack_authorized_q && front_state == MF_WAIT_RELEASE &&
					line_resident)
					else $fatal(1, "main-ROM ACK lacks matching front-end ownership");
				if (main_req) begin
					assert (!(sim_completed_valid && sim_completed_addr == front_addr_q))
						else $fatal(1, "main-ROM request signature acknowledged twice");
					sim_completed_valid <= 1'b1;
					sim_completed_addr <= front_addr_q;
				end else begin
					// Some unit-test producers release at the half-cycle after
					// sampling ACK. The generation edge was authorized above, but
					// no held signature remains to suppress.
					sim_completed_valid <= 1'b0;
				end
			end

			if (!cancel && (front_state == MF_PROBE ||
				front_state == MF_HIT_RESPONSE ||
				front_state == MF_MISS_WAIT ||
				front_state == MF_REFILL_PROBE ||
				front_state == MF_REFILL_RESPONSE) && main_req) begin
				assert (main_addr == front_addr_q)
					else $fatal(1, "main-ROM request changed before its ACK/cancel boundary");
			end
			assert (!(refill_write &&
				(front_state == MF_PROBE || front_state == MF_REFILL_PROBE)))
				else $fatal(1, "legal main-ROM probe overlapped its refill write");
			if (front_state == MF_REFILL_RESPONSE && request_held && !front_collision_q) begin
				assert (front_hit_q && read_ahead_valid[front_addr_q[11:7]] &&
					read_ahead_tag[front_addr_q[11:7]] == front_addr_q[21:12])
					else $fatal(1, "published main-ROM refill did not re-probe as a hit");
			end

			if (sim_refill_response_q)
				assert (front_state == MF_REFILL_PROBE)
					else $fatal(1, "published live refill did not enter REFILL_PROBE");
			if (sim_refill_discard_q)
				assert (!read_ahead_valid[sim_refill_set_q])
					else $fatal(1, "discarded main-ROM refill published a valid line");
			sim_refill_response_q <= refill_publish && miss_held;
			sim_refill_discard_q <= refill_write && refill_beat == 4'd15 &&
				!refill_publish;
			if (refill_write && refill_beat == 4'd15)
				sim_refill_set_q <= refill_set;
		end
	end
`endif

endmodule
