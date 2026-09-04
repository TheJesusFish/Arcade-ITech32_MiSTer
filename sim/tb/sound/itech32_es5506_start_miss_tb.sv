// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

// ROM-free integration checks for the FPGA cache-miss policy at STOP-to-RUN.
// These are invariants of this implementation, not claims about pin-exact OTTO
// host timing: host acknowledgement cannot depend on external ROM service,
// global sample cadence continues, and only the missing voice is zero/frozen.
module itech32_es5506_start_miss_tb;

	localparam logic [5:0] ENGINE_IDLE = 6'd0;
	localparam logic [5:0] ENGINE_COMMIT = 6'd28;
	localparam logic [5:0] ENGINE_UNDERRUN = 6'd31;
	localparam logic [2:0] PREFETCH_INIT = 3'd0;
	localparam logic [2:0] PREFETCH_SCAN = 3'd1;
	localparam integer ACK_BOUND = 32;
`ifdef TEST_PROGRAM_PREWARM
	localparam bit PROGRAM_PREWARM_ENABLED = 1'b1;
`else
	localparam bit PROGRAM_PREWARM_ENABLED = 1'b0;
`endif
	typedef logic [346:0] voice_row_bits_t;

	logic clk = 1'b0;
	logic reset = 1'b1;
	logic ce_16m = 1'b0;
	logic audio_enable = 1'b0;
	logic host_req = 1'b0;
	logic host_write = 1'b0;
	logic [5:0] host_addr = 6'd0;
	logic [7:0] host_wdata = 8'd0;
	logic [7:0] host_rdata;
	logic host_ack;
	logic sample_req;
	logic [1:0] sample_bank;
	logic [21:0] sample_addr;
	logic sample_companded;
	logic [4:0] sample_voice;
	logic [15:0] sample_rdata;
	logic sample_ack;
	logic signed [19:0] audio_left;
	logic signed [19:0] audio_right;
	logic [119:0] audio_left_channels;
	logic [119:0] audio_right_channels;
	logic audio_strobe;
	logic irq;
	logic [7:0] irq_vector;
	logic [6:0] current_page;
	logic [4:0] active_voices;
	logic [4:0] scan_voice;
	logic engine_busy;

	integer ce_phase = 0;
	integer carrier_cycle = 0;
	integer accepted_words = 0;
	integer request_starts = 0;
	integer cadence_strobes = 0;
	integer cadence_last_cycle = 0;
	integer cadence_expected_gap = 100;
	integer miss_count = 0;
	logic cadence_check = 1'b0;
	logic cadence_reset = 1'b0;
	logic freeze_check = 1'b0;
	logic freeze_reset = 1'b0;
	logic forbid_miss = 1'b0;
	logic upper_only_miss_seen = 1'b0;
	logic bank_miss_seen = 1'b0;
	logic urgent_collision_seen = 1'b0;
	logic older_urgent_dispatch_seen = 1'b0;
	logic word3_zero_check = 1'b0;
	logic word3_zero_descriptor_seen = 1'b0;
	logic [18:0] word3_zero_line = 19'd0;
	logic prewarm_priority_check = 1'b0;
	logic prewarm_priority_urgent_seen = 1'b0;
	logic prewarm_priority_violation = 1'b0;
	voice_row_bits_t frozen_engine_row;
	voice_row_bits_t frozen_prefetch_row;

	logic mem_pending = 1'b0;
	logic [1:0] held_bank = 2'd0;
	logic [21:0] held_addr = 22'd0;
	logic held_companded = 1'b0;
	logic [4:0] held_voice = 5'd0;
	logic hold_all = 1'b0;
	logic hold_key_enable = 1'b0;
	logic [1:0] hold_key_bank = 2'd0;
	logic [18:0] hold_key_line = 19'd0;
	logic [4:0] hold_key_voice = 5'd0;
	logic held_is_blocked;

	logic tracking_reset = 1'b0;
	logic tracking_enable = 1'b0;
	logic [4:0] tracking_voice = 5'd0;
	logic [1:0] tracking_bank = 2'd0;
	logic [18:0] tracking_line_a = 19'd0;
	logic [18:0] tracking_line_b = 19'd0;
	logic tracking_line_b_enable = 1'b0;
	logic [3:0] tracking_words_a = 4'd0;
	logic [3:0] tracking_words_b = 4'd0;
	integer tracking_accepts = 0;

	string test_case = "lower";

	always #5 clk = ~clk;

	itech32_es5506 #(
		.ENABLE_PROGRAM_PREWARM (PROGRAM_PREWARM_ENABLED)
	) dut (
		.clk                 (clk),
		.reset               (reset),
		.ce_16m              (ce_16m),
		.host_req            (host_req),
		.host_write          (host_write),
		.host_addr           (host_addr),
		.host_wdata          (host_wdata),
		.host_rdata          (host_rdata),
		.host_ack            (host_ack),
		.par_comparator_tripped (1'b0),
		.par_discharge       (),
		.sample_req          (sample_req),
		.sample_bank         (sample_bank),
		.sample_addr         (sample_addr),
		.sample_companded    (sample_companded),
		.sample_voice        (sample_voice),
		.sample_rdata        (sample_rdata),
		.sample_ack          (sample_ack),
		.audio_left          (audio_left),
		.audio_right         (audio_right),
		.audio_left_channels (audio_left_channels),
		.audio_right_channels(audio_right_channels),
		.audio_strobe        (audio_strobe),
		.irq                 (irq),
		.irq_vector          (irq_vector),
		.current_page        (current_page),
		.active_voices       (active_voices),
		.scan_voice          (scan_voice),
		.engine_busy         (engine_busy)
	);

	function automatic logic [15:0] authored_word(
		input logic [1:0] bank,
		input logic [21:0] address,
		input logic [4:0] voice,
		input logic companded
	);
		logic [15:0] identity;
		begin
			identity = {bank, voice, address[8:0]};
			authored_word = 16'h3400 ^ identity ^ {15'd0, companded};
		end
	endfunction

	function automatic voice_row_bits_t engine_row(input integer voice);
		engine_row = dut.voice_state_engine_mem[voice];
	endfunction

	function automatic voice_row_bits_t prefetch_row(input integer voice);
		prefetch_row = dut.voice_state_prefetch_mem[voice];
	endfunction

	function automatic logic cache_line_valid(
		input logic [4:0] voice,
		input logic [1:0] bank,
		input logic [18:0] line
	);
		logic [18:0] tag;
		begin
			tag = dut.sample_cache_tag_mem[{voice, bank, line[2:0]}];
			cache_line_valid = tag[18] && (tag[17:16] == bank) &&
			                   (tag[15:0] == line[18:3]);
		end
	endfunction

	function automatic logic signed [19:0] clamp_mix20(
		input logic signed [31:0] value
	);
		begin
			if (value > 32'sd524287)
				clamp_mix20 = 20'sh7ffff;
			else if (value < -32'sd524288)
				clamp_mix20 = 20'sh80000;
			else
				clamp_mix20 = value[19:0];
		end
	endfunction

	assign held_is_blocked = hold_all ||
		(hold_key_enable && (held_bank == hold_key_bank) &&
		 (held_addr[21:3] == hold_key_line) &&
		 (held_voice == hold_key_voice));
	assign sample_ack = mem_pending && !held_is_blocked;
	assign sample_rdata = authored_word(
		held_bank, held_addr, held_voice, held_companded);

	// Exact 16 MHz enable on the 100 MHz test carrier. ACTV=0 therefore emits
	// one complete scan every 100 carrier clocks, independent of ROM latency.
	always_ff @(negedge clk) begin
		if (reset || !audio_enable) begin
			ce_phase <= 0;
			ce_16m <= 1'b0;
		end else begin
			ce_16m <= (ce_phase == 0) || (ce_phase == 6) ||
			          (ce_phase == 12) || (ce_phase == 18);
			ce_phase <= (ce_phase == 24) ? 0 : ce_phase + 1;
		end
	end

	always @(negedge clk) begin
		if (!reset && !dut.local_reset && dut.prefetch_urgent_dispatch &&
		    (dut.prefetch_urgent_scan_voice == 5'd2))
			older_urgent_dispatch_seen = 1'b1;
	end

	// A word-3 sample with zero interpolation weight needs only its current
	// qword. Background lookahead remains independent and may later request the
	// next line, so qualify this assertion to the START-triggered urgent refill.
	always @(negedge clk) begin
		if (word3_zero_check && !reset && !dut.local_reset &&
		    dut.prefetch_urgent_mode_q && (dut.prefetch_voice_q == 5'd0)) begin
			word3_zero_descriptor_seen = 1'b1;
			assert (!dut.prefetch_urgent_need_upper_q &&
			        !dut.prefetch_urgent_upper_q)
				else $fatal(1, "zero-weight word3 requested an urgent upper qword");
			if (sample_req)
				assert (sample_addr[21:3] != (word3_zero_line + 19'd1))
					else $fatal(1, "zero-weight word3 emitted an urgent upper request");
		end
	end

	// A pending urgent voice and a newly arriving hint may meet on the exact
	// scan edge that would otherwise dispatch the older voice.  The new hint
	// must neither clear the older bit nor let that edge launch background
	// work.  This is sampled at negedge (all inputs to the next sequential edge
	// are stable) and checked just after that edge.
	always @(negedge clk) begin : urgent_collision_oracle
		logic [31:0] pending_before;
		logic [31:0] set_before;
		logic [4:0] scan_before;
		if (!reset && !dut.local_reset &&
		    (dut.prefetch_state == PREFETCH_SCAN) &&
		    dut.prefetch_urgent_pending[dut.prefetch_urgent_scan_voice] &&
		    (|dut.prefetch_urgent_set_mask)) begin
			pending_before = dut.prefetch_urgent_pending;
			set_before = dut.prefetch_urgent_set_mask;
			scan_before = dut.prefetch_urgent_scan_voice;
			@(posedge clk);
			#0.002;
			assert ((dut.prefetch_urgent_pending & pending_before) == pending_before)
				else $fatal(1, "older urgent bit was lost on same-edge hint old=%08x new=%08x",
				            pending_before, dut.prefetch_urgent_pending);
			assert ((dut.prefetch_urgent_pending & set_before) == set_before)
				else $fatal(1, "new urgent bit was lost on same-edge hint set=%08x new=%08x",
				            set_before, dut.prefetch_urgent_pending);
			assert (dut.prefetch_state == PREFETCH_SCAN)
				else $fatal(1, "same-edge urgent hint launched non-urgent/background work voice=%0d state=%0d",
				            scan_before, dut.prefetch_state);
			urgent_collision_seen = 1'b1;
		end
	end

	// One registered transaction at a time. The environment never changes any
	// request field while the DUT is waiting, including across host contention.
	always_ff @(posedge clk) begin
		if (reset) begin
			mem_pending <= 1'b0;
			held_bank <= 2'd0;
			held_addr <= 22'd0;
			held_companded <= 1'b0;
			held_voice <= 5'd0;
			accepted_words <= 0;
			request_starts <= 0;
		end else begin
			if (mem_pending) begin
				assert (sample_req)
					else $fatal(1, "sample request dropped before ACK CASE=%s", test_case);
				assert ({sample_bank, sample_addr, sample_companded, sample_voice} ===
				        {held_bank, held_addr, held_companded, held_voice})
					else $fatal(1, "sample payload changed while held CASE=%s", test_case);
				if (sample_ack) begin
					mem_pending <= 1'b0;
					accepted_words <= accepted_words + 1;
				end
			end else if (sample_req) begin
				mem_pending <= 1'b1;
				held_bank <= sample_bank;
				held_addr <= sample_addr;
				held_companded <= sample_companded;
				held_voice <= sample_voice;
				request_starts <= request_starts + 1;
			end
		end
	end

	// A background all-bank prewarm is deliberately atomic for only one
	// current/upper pair. Once that pair returns to SCAN, any live urgent hint
	// must launch before the program cursor advances to another bank.
	always @(negedge clk) begin
		if (reset || dut.local_reset) begin
			prewarm_priority_urgent_seen = 1'b0;
			prewarm_priority_violation = 1'b0;
		end else if (prewarm_priority_check && sample_req && !mem_pending) begin
			if ((sample_voice == 5'd1) && (sample_bank == 2'd3))
				prewarm_priority_urgent_seen = 1'b1;
			else if (!prewarm_priority_urgent_seen &&
			         (sample_voice == 5'd0) && (sample_bank != 2'd0))
				prewarm_priority_violation = 1'b1;
		end
	end

	// Track only architecturally requested target qwords; background lookahead
	// traffic is allowed and is deliberately not mistaken for required work.
	always_ff @(posedge clk) begin
		if (reset || tracking_reset) begin
			tracking_words_a <= 4'd0;
			tracking_words_b <= 4'd0;
			tracking_accepts <= 0;
		end else if (sample_ack && tracking_enable &&
		             (held_voice == tracking_voice) &&
		             (held_bank == tracking_bank)) begin
			if (held_addr[21:3] == tracking_line_a) begin
				tracking_words_a[held_addr[2:1]] <= 1'b1;
				tracking_accepts <= tracking_accepts + 1;
			end else if (tracking_line_b_enable &&
		             (held_addr[21:3] == tracking_line_b)) begin
				tracking_words_b[held_addr[2:1]] <= 1'b1;
				tracking_accepts <= tracking_accepts + 1;
			end
		end
	end

	// The freeze oracle is a stability invariant, not a second ES5506 model.
	// It compares every bit in both physical voice-row replicas after each miss.
	always @(negedge clk) begin
		if (reset || dut.local_reset) begin
			miss_count = 0;
			upper_only_miss_seen = 1'b0;
			bank_miss_seen = 1'b0;
		end else begin
			if (freeze_reset) begin
				miss_count = 0;
				upper_only_miss_seen = 1'b0;
				bank_miss_seen = 1'b0;
			end
			if (freeze_check && dut.engine_sample_miss &&
			    dut.engine_cache_first_hit_q)
				upper_only_miss_seen = 1'b1;
			if (freeze_check && dut.engine_sample_miss &&
			    !dut.engine_cache_first_hit_q)
				bank_miss_seen = 1'b1;
			if (dut.sample_underrun) begin
				if (forbid_miss)
					$fatal(1, "cache-hit START took miss fallback");
				if (freeze_check) begin
					miss_count = miss_count + 1;
					assert (engine_row(0) === frozen_engine_row)
						else $fatal(1, "engine voice row advanced on miss CASE=%s", test_case);
					assert (prefetch_row(0) === frozen_prefetch_row)
						else $fatal(1, "prefetch voice row advanced on miss CASE=%s", test_case);
					assert (engine_row(0) === prefetch_row(0))
						else $fatal(1, "voice RAM replicas diverged on miss CASE=%s", test_case);
					assert ((audio_left == 0) && (audio_right == 0) &&
					        (audio_left_channels == 0) && (audio_right_channels == 0))
						else $fatal(1, "cache miss contributed nonzero audio CASE=%s L=%0d R=%0d",
						            test_case, $signed(audio_left), $signed(audio_right));
				end
			end
		end
	end

	always_ff @(posedge clk) begin
		carrier_cycle <= carrier_cycle + 1;
		if (reset || cadence_reset) begin
			cadence_strobes <= 0;
			cadence_last_cycle <= 0;
		end else if (cadence_check && audio_strobe) begin
			if ((cadence_strobes != 0) &&
			    ((carrier_cycle - cadence_last_cycle) != cadence_expected_gap))
				$fatal(1, "global cadence changed CASE=%s gap=%0d expected=%0d",
				       test_case, carrier_cycle - cadence_last_cycle,
				       cadence_expected_gap);
			cadence_last_cycle <= carrier_cycle;
			cadence_strobes <= cadence_strobes + 1;
		end
	end

	task automatic host_transfer(
		input logic write_cycle,
		input logic [5:0] address,
		input logic [7:0] write_data,
		output logic [7:0] read_data,
		output integer latency,
		output integer accepted_at_ack
	);
		integer timeout;
		begin
			@(negedge clk);
			host_req = 1'b1;
			host_write = write_cycle;
			host_addr = address;
			host_wdata = write_data;
			latency = 0;
			accepted_at_ack = -1;
			begin : wait_ack
				for (timeout = 0; timeout < 400; timeout = timeout + 1) begin
					@(posedge clk);
					#0.002;
					latency = latency + 1;
					if (host_ack) begin
						read_data = host_rdata;
						accepted_at_ack = accepted_words;
						disable wait_ack;
					end
				end
				$fatal(1, "host timeout CASE=%s addr=%02x", test_case, address);
			end
			repeat (2) begin
				@(posedge clk);
				#0.002;
				assert (!host_ack)
					else $fatal(1, "duplicate host ACK CASE=%s addr=%02x", test_case, address);
			end
			@(negedge clk);
			host_req = 1'b0;
			host_write = 1'b0;
			repeat (2) @(posedge clk);
			#0.002;
		end
	endtask

	task automatic prewarm_case;
		localparam logic [18:0] LINE = 19'h001b8;
		localparam logic [18:0] UPPER = LINE + 19'd1;
		localparam logic [31:0] ACCUM = {LINE, 2'd3, 9'h155, 2'b00};
		localparam logic [16:0] FREQ = 17'h00400;
		integer bank;
		integer latency;
		begin
			assert (PROGRAM_PREWARM_ENABLED)
				else $fatal(1, "prewarm case compiled with prevention disabled");
			reset_dut();
			set_active(5'd0);
			configure_stopped_voice(0, ACCUM, FREQ);
			wait_prefetch_quiet();
			for (bank = 0; bank < 4; bank = bank + 1) begin
				assert (cache_line_valid(0, bank[1:0], LINE))
					else $fatal(1, "prewarm missed current line bank=%0d", bank);
				assert (cache_line_valid(0, bank[1:0], UPPER))
					else $fatal(1, "prewarm missed upper line bank=%0d", bank);
			end
			assert ((request_starts == 32) && (accepted_words == 32))
				else $fatal(1, "prewarm traffic changed requests=%0d accepted=%0d",
				            request_starts, accepted_words);

			clear_tracking(0, 2, LINE, 1'b1, UPPER);
			hold_all = 1'b1;
			start_control(0, 16'h8000, latency);
			forbid_miss = 1'b1;
			arm_cadence(100);
			wait_voice0_commit(
				ACCUM + {15'd0, FREQ}, 1'b1,
				authored_word(2, {UPPER, 3'd0}, 0, 0),
				1'b1, authored_word(2, {LINE, 2'd3, 1'b0}, 0, 0));
			forbid_miss = 1'b0;
			assert ((dut.sample_underrun_count == 0) &&
			        (tracking_accepts == 0))
				else $fatal(1, "prewarmed bank2 RUN used miss/fetch miss=%0d accepts=%0d",
				            dut.sample_underrun_count, tracking_accepts);
			hold_all = 1'b0;
			$display("PASS ES_BANK_PREWARM ACK=%0d requests=%0d accepted=%0d",
			         latency, request_starts, accepted_words);
		end
	endtask

	task automatic prewarm_priority_case;
		localparam logic [18:0] PROGRAM_LINE = 19'h001c0;
		localparam logic [18:0] URGENT_LINE = 19'h001d0;
		localparam logic [31:0] PROGRAM_ACCUM =
			{PROGRAM_LINE, 2'd3, 9'h101, 2'b00};
		localparam logic [31:0] URGENT_ACCUM =
			{URGENT_LINE, 2'd3, 9'h081, 2'b00};
		integer latency;
		integer timeout;
		begin
			assert (PROGRAM_PREWARM_ENABLED)
				else $fatal(1, "priority case compiled with prevention disabled");
			reset_dut();
			set_active(5'd1);
			hold_line(0, 0, PROGRAM_LINE);
			configure_stopped_voice(0, PROGRAM_ACCUM, 17'h00400);
			wait_held_request(0, 0, PROGRAM_LINE);
			assert (dut.prefetch_program_mode_q)
				else $fatal(1, "held owner was not a program-prewarm pair");

			// Queue and start a different voice while bank0 of the background
			// owner is held. The held request may not be preempted, but after its
			// current/upper pair completes voice1 must beat voice0 bank1.
			configure_stopped_voice(1, URGENT_ACCUM, 17'h00400);
			start_control(1, 16'hc000, latency);
			assert (dut.prefetch_urgent_pending[1])
				else $fatal(1, "urgent voice was not queued behind held prewarm");
			prewarm_priority_urgent_seen = 1'b0;
			prewarm_priority_violation = 1'b0;
			prewarm_priority_check = 1'b1;
			hold_key_enable = 1'b0;
			begin : wait_urgent
				for (timeout = 0; timeout < 4000; timeout = timeout + 1) begin
					@(negedge clk);
					if (prewarm_priority_urgent_seen)
						disable wait_urgent;
				end
				$fatal(1, "urgent request did not dispatch after held prewarm pair");
			end
			assert (!prewarm_priority_violation)
				else $fatal(1, "background prewarm advanced banks before urgent dispatch");
			assert (dut.prefetch_program_pending[0])
				else $fatal(1, "program owner completed all banks before urgent dispatch");
			prewarm_priority_check = 1'b0;
			wait_cache_line(1, 3, URGENT_LINE);
			wait_prefetch_quiet();
			$display("PASS ES_BANK_PREWARM_PRIORITY ACK=%0d requests=%0d accepted=%0d",
			         latency, request_starts, accepted_words);
		end
	endtask

	// Drive an architectural final byte from one exact, repeatable native
	// adapter phase. Comparing transactions launched through this helper is
	// meaningful because engine state, ES slot, fractional CE phase, and host
	// pipeline eligibility are all equal at the request edge.
	task automatic host_transfer_aligned(
		input logic [5:0] address,
		input logic [7:0] write_data,
		input logic [3:0] desired_slot,
		input integer desired_ce_phase,
		output integer latency,
		output integer accepted_at_ack
	);
		integer timeout;
		begin
			begin : wait_phase
				for (timeout = 0; timeout < 40000; timeout = timeout + 1) begin
					@(negedge clk);
					#0.002;
					if ((dut.engine_state == ENGINE_IDLE) &&
					    (dut.slot_count == desired_slot) &&
					    (ce_phase == desired_ce_phase) && !ce_16m &&
					    !dut.host_pipeline_busy && !dut.host_seen &&
					    !dut.host_req_q && !host_req) begin
						host_req = 1'b1;
						host_write = 1'b1;
						host_addr = address;
						host_wdata = write_data;
						disable wait_phase;
					end
				end
				$fatal(1, "eligible aligned host phase did not recur slot=%0d ce_phase=%0d",
				       desired_slot, desired_ce_phase);
			end
			latency = 0;
			accepted_at_ack = -1;
			begin : wait_ack
				for (timeout = 0; timeout < 100; timeout = timeout + 1) begin
					@(posedge clk);
					#0.002;
					latency = latency + 1;
					if (host_ack) begin
						accepted_at_ack = accepted_words;
						disable wait_ack;
					end
				end
				$fatal(1, "aligned host transfer timed out");
			end
			repeat (2) begin
				@(posedge clk);
				#0.002;
				assert (!host_ack)
					else $fatal(1, "duplicate aligned host ACK");
			end
			@(negedge clk);
			host_req = 1'b0;
			host_write = 1'b0;
			repeat (2) @(posedge clk);
			#0.002;
		end
	endtask

	task automatic write_byte(input logic [5:0] address, input logic [7:0] data);
		logic [7:0] ignored;
		integer latency;
		integer accepted_at_ack;
		begin
			host_transfer(1'b1, address, data, ignored, latency, accepted_at_ack);
		end
	endtask

	task automatic write_reg(input logic [3:0] slot, input logic [31:0] data);
		begin
			write_byte({slot, 2'd0}, data[31:24]);
			write_byte({slot, 2'd1}, data[23:16]);
			write_byte({slot, 2'd2}, data[15:8]);
			write_byte({slot, 2'd3}, data[7:0]);
		end
	endtask

	task automatic set_page(input logic [6:0] page);
		begin
			write_reg(4'hf, {25'd0, page});
			assert (current_page == page)
				else $fatal(1, "PAGE write failed expected=%02x actual=%02x", page, current_page);
		end
	endtask

	task automatic wait_control(input integer voice, input logic [15:0] expected);
		integer timeout;
		begin : wait_loop
			for (timeout = 0; timeout < 100; timeout = timeout + 1) begin
				@(negedge clk);
				if (dut.voice_state_valid[voice] &&
				    (dut.voice_state_engine_mem[voice].control == expected))
					disable wait_loop;
			end
			$fatal(1, "CONTROL did not commit voice=%0d expected=%04x", voice, expected);
		end
	endtask

	task automatic write_control(
		input integer voice,
		input logic [15:0] control,
		output integer final_latency,
		output integer accepted_at_ack
	);
		logic [7:0] ignored;
		integer ignored_latency;
		integer ignored_accepted;
		begin
			set_page(voice[6:0]);
			write_byte(6'h00, 8'd0);
			write_byte(6'h01, 8'd0);
			write_byte(6'h02, control[15:8]);
			host_transfer(1'b1, 6'h03, control[7:0], ignored,
			              final_latency, accepted_at_ack);
			wait_control(voice, control);
		end
	endtask

	task automatic start_control(
		input integer voice,
		input logic [15:0] control,
		output integer latency
	);
		integer accepted_before;
		integer accepted_at_ack;
		begin
			accepted_before = accepted_words;
			write_control(voice, control, latency, accepted_at_ack);
			assert (latency <= ACK_BOUND)
				else $fatal(1, "START ACK exceeded fixed bound CASE=%s latency=%0d",
				            test_case, latency);
			assert (accepted_at_ack == accepted_before)
				else $fatal(1, "START ACK depended on a sample return CASE=%s before=%0d at_ack=%0d",
				            test_case, accepted_before, accepted_at_ack);
		end
	endtask

	task automatic reset_dut;
		integer timeout;
		begin
			audio_enable = 1'b0;
			cadence_check = 1'b0;
			freeze_check = 1'b0;
			forbid_miss = 1'b0;
			hold_all = 1'b0;
			hold_key_enable = 1'b0;
			tracking_enable = 1'b0;
			host_req = 1'b0;
			host_write = 1'b0;
			@(negedge clk);
			reset = 1'b1;
			repeat (6) @(posedge clk);
			@(negedge clk);
			reset = 1'b0;
			begin : wait_release
				for (timeout = 0; timeout < 20; timeout = timeout + 1) begin
					@(negedge clk);
					if (!dut.local_reset)
						disable wait_release;
				end
				$fatal(1, "local reset did not release");
			end
			begin : wait_init
				for (timeout = 0; timeout < 1200; timeout = timeout + 1) begin
					@(negedge clk);
					if (dut.cache_initialized)
						disable wait_init;
				end
				$fatal(1, "sample cache initialization timed out");
			end
		end
	endtask

	task automatic set_active(input logic [4:0] last_voice);
		begin
			set_page(7'd0);
			write_reg(4'hb, {27'd0, last_voice});
			assert (active_voices == last_voice)
				else $fatal(1, "ACTV write failed");
		end
	endtask

	task automatic configure_stopped_voice(
		input integer voice,
		input logic [31:0] accumulator,
		input logic [16:0] frequency
	);
		integer ignored_latency;
		integer ignored_accepted;
		begin
			set_page(7'h20 + voice[6:0]);
			write_reg(4'h1, 32'd0);
			write_reg(4'h2, 32'h7fffff80);
			write_reg(4'h3, accumulator);
			set_page(voice[6:0]);
			write_reg(4'h1, {15'd0, frequency});
			write_reg(4'h2, 32'h0000f000);
			write_reg(4'h4, 32'h0000e000);
			write_reg(4'h6, 32'd7);
			write_reg(4'h7, 32'h0000ffff);
			write_reg(4'h9, 32'h0000ffff);
			write_control(voice, 16'h0003, ignored_latency, ignored_accepted);
		end
	endtask

	task automatic clear_tracking(
		input logic [4:0] voice,
		input logic [1:0] bank,
		input logic [18:0] line_a,
		input logic line_b_enable,
		input logic [18:0] line_b
	);
		begin
			tracking_enable = 1'b0;
			@(negedge clk);
			tracking_reset = 1'b1;
			@(posedge clk);
			#0.002;
			@(negedge clk);
			tracking_reset = 1'b0;
			tracking_voice = voice;
			tracking_bank = bank;
			tracking_line_a = line_a;
			tracking_line_b_enable = line_b_enable;
			tracking_line_b = line_b;
			tracking_enable = 1'b1;
		end
	endtask

	task automatic hold_line(
		input logic [4:0] voice,
		input logic [1:0] bank,
		input logic [18:0] line
	);
		begin
			hold_all = 1'b0;
			hold_key_voice = voice;
			hold_key_bank = bank;
			hold_key_line = line;
			hold_key_enable = 1'b1;
		end
	endtask

	task automatic wait_held_request(
		input logic [4:0] voice,
		input logic [1:0] bank,
		input logic [18:0] line
	);
		integer timeout;
		begin : wait_loop
			for (timeout = 0; timeout < 4000; timeout = timeout + 1) begin
				@(negedge clk);
				if (mem_pending && (held_voice == voice) &&
				    (held_bank == bank) && (held_addr[21:3] == line))
					disable wait_loop;
			end
			$fatal(1, "target sample request not observed CASE=%s voice=%0d bank=%0d line=%05x",
			       test_case, voice, bank, line);
		end
	endtask

	task automatic wait_cache_line(
		input logic [4:0] voice,
		input logic [1:0] bank,
		input logic [18:0] line
	);
		integer timeout;
		begin : wait_loop
			for (timeout = 0; timeout < 4000; timeout = timeout + 1) begin
				@(negedge clk);
				if (cache_line_valid(voice, bank, line))
					disable wait_loop;
			end
			$fatal(1, "cache line did not become resident CASE=%s voice=%0d bank=%0d line=%05x",
			       test_case, voice, bank, line);
		end
	endtask

	task automatic wait_prefetch_quiet;
		integer timeout;
		begin : wait_loop
			for (timeout = 0; timeout < 4000; timeout = timeout + 1) begin
				@(negedge clk);
				if (!sample_req && !mem_pending &&
				    (dut.prefetch_urgent_pending == 0) &&
				    (dut.prefetch_program_pending == 0) &&
				    (dut.prefetch_state == PREFETCH_SCAN))
					disable wait_loop;
			end
			$fatal(1, "prefetch did not become quiet CASE=%s", test_case);
		end
	endtask

	task automatic arm_freeze;
		begin
			frozen_engine_row = engine_row(0);
			frozen_prefetch_row = prefetch_row(0);
			assert (frozen_engine_row === frozen_prefetch_row)
				else $fatal(1, "voice RAM replicas differed before miss CASE=%s", test_case);
			@(negedge clk);
			freeze_reset = 1'b1;
			@(negedge clk);
			freeze_reset = 1'b0;
			freeze_check = 1'b1;
		end
	endtask

	task automatic arm_cadence(input integer gap);
		begin
			cadence_check = 1'b0;
			@(negedge clk);
			cadence_reset = 1'b1;
			@(posedge clk);
			#0.002;
			@(negedge clk);
			cadence_reset = 1'b0;
			cadence_expected_gap = gap;
			cadence_check = 1'b1;
			audio_enable = 1'b1;
		end
	endtask

	task automatic wait_misses(input integer required);
		integer timeout;
		begin : wait_loop
			for (timeout = 0; timeout < 20000; timeout = timeout + 1) begin
				@(negedge clk);
				if (miss_count >= required)
					disable wait_loop;
			end
			$fatal(1, "miss fallback coverage timed out CASE=%s got=%0d need=%0d",
			       test_case, miss_count, required);
		end
	endtask

	task automatic wait_voice0_commit(
		input logic [31:0] expected_accumulator,
		input logic check_upper,
		input logic [15:0] expected_upper_word,
		input logic check_first,
		input logic [15:0] expected_first_word
	);
		integer timeout;
		begin : wait_loop
			for (timeout = 0; timeout < 20000; timeout = timeout + 1) begin
				@(negedge clk);
				if ((dut.engine_state == ENGINE_COMMIT) && (dut.work_voice == 0)) begin
					if (check_upper)
						assert (dut.fetched_sample1 == expected_upper_word)
							else $fatal(1, "upper-qword sample mismatch expected=%04x actual=%04x",
							            expected_upper_word, dut.fetched_sample1);
					if (check_first)
						assert (dut.fetched_sample0 == expected_first_word)
							else $fatal(1, "first sample mismatch expected=%04x actual=%04x",
							            expected_first_word, dut.fetched_sample0);
					freeze_check = 1'b0;
					@(posedge clk);
					#0.002;
					assert (dut.debug_voice0_accum == expected_accumulator)
						else $fatal(1, "voice did not resume with exactly one step expected=%08x actual=%08x",
						            expected_accumulator, dut.debug_voice0_accum);
					disable wait_loop;
				end
			end
			$fatal(1, "voice0 did not commit after refill CASE=%s", test_case);
		end
	endtask

	task automatic lower_case;
		localparam logic [18:0] LINE = 19'h00120;
		localparam logic [31:0] ACCUM = {LINE, 13'd0};
		localparam logic [16:0] FREQ = 17'h00800;
		integer latency;
		begin
			reset_dut();
			set_active(5'd0);
			configure_stopped_voice(0, ACCUM, FREQ);
			clear_tracking(0, 0, LINE, 1'b0, 19'd0);
			hold_line(0, 0, LINE);
			start_control(0, 16'h0000, latency);
			arm_freeze();
			arm_cadence(100);
			wait_held_request(0, 0, LINE);
			wait_misses(3);
			assert (tracking_words_a == 4'd0)
				else $fatal(1, "held lower qword accepted early");
			hold_key_enable = 1'b0;
			wait_cache_line(0, 0, LINE);
			wait_voice0_commit(ACCUM + {15'd0, FREQ}, 1'b0, 16'd0,
			                   1'b1, authored_word(0, {LINE, 3'd0}, 0, 0));
			assert (tracking_words_a == 4'hf)
				else $fatal(1, "lower qword did not fetch all four words mask=%x",
				            tracking_words_a);
			assert (cadence_strobes >= 3)
				else $fatal(1, "lower miss did not cover repeated global outputs");
			$display("PASS ES_START_MISS lower ACK=%0d misses=%0d strobes=%0d",
			         latency, miss_count, cadence_strobes);
		end
	endtask

	task automatic upper_case;
		localparam logic [18:0] LINE = 19'h00130;
		localparam logic [18:0] UPPER = LINE + 19'd1;
		localparam logic [31:0] ACCUM = {LINE, 2'd3, 9'h055, 2'b00};
		localparam logic [16:0] FREQ = 17'h00400;
		integer latency;
		begin
			reset_dut();
			set_active(5'd0);
			configure_stopped_voice(0, ACCUM, FREQ);
			clear_tracking(0, 0, LINE, 1'b1, UPPER);
			hold_line(0, 0, UPPER);
			start_control(0, 16'h0000, latency);
			wait_cache_line(0, 0, LINE);
			wait_held_request(0, 0, UPPER);
			assert (tracking_words_a == 4'hf)
				else $fatal(1, "word3 lower qword incomplete mask=%x", tracking_words_a);
			arm_freeze();
			arm_cadence(100);
			wait_misses(3);
			assert (upper_only_miss_seen)
				else $fatal(1, "word3 test never missed solely on upper qword");
			assert (tracking_words_b == 4'd0)
				else $fatal(1, "held upper qword accepted early");
			hold_key_enable = 1'b0;
			wait_cache_line(0, 0, UPPER);
			wait_voice0_commit(ACCUM + {15'd0, FREQ}, 1'b1,
			                   authored_word(0, {UPPER, 3'd0}, 0, 0),
			                   1'b0, 16'd0);
			assert (tracking_words_b == 4'hf)
				else $fatal(1, "upper qword did not fetch all four words mask=%x",
				            tracking_words_b);
			$display("PASS ES_START_MISS upper ACK=%0d misses=%0d strobes=%0d",
			         latency, miss_count, cadence_strobes);
		end
	endtask

	task automatic word3_zero_case;
		localparam logic [18:0] LINE = 19'h00138;
		localparam logic [18:0] UPPER = LINE + 19'd1;
		localparam logic [31:0] ACCUM = {LINE, 2'd3, 9'd0, 2'b00};
		localparam logic [16:0] FREQ = 17'h00400;
		logic [15:0] word3_sample;
		integer latency;
		begin
			reset_dut();
			word3_zero_check = 1'b0;
			word3_zero_descriptor_seen = 1'b0;
			word3_zero_line = LINE;
			set_active(5'd0);
			configure_stopped_voice(0, ACCUM, FREQ);
			clear_tracking(0, 0, LINE, 1'b1, UPPER);
			hold_line(0, 0, LINE);
			word3_zero_check = 1'b1;
			start_control(0, 16'h0000, latency);
			arm_freeze();
			arm_cadence(100);
			wait_held_request(0, 0, LINE);
			wait_misses(2);
			assert (tracking_words_a == 4'd0)
				else $fatal(1, "held word3-zero qword accepted early");
			hold_key_enable = 1'b0;
			wait_cache_line(0, 0, LINE);
			word3_sample = authored_word(0, {LINE, 2'd3, 1'b0}, 0, 0);
			wait_voice0_commit(ACCUM + {15'd0, FREQ}, 1'b1,
			                   word3_sample, 1'b1, word3_sample);
			word3_zero_check = 1'b0;
			assert (word3_zero_descriptor_seen)
				else $fatal(1, "word3-zero test never observed its urgent descriptor");
			assert (tracking_words_a == 4'hf)
				else $fatal(1, "word3-zero current qword did not fill mask=%x",
				            tracking_words_a);
			$display("PASS ES_START_MISS word3-zero ACK=%0d misses=%0d upper_background_mask=%x",
			         latency, miss_count, tracking_words_b);
		end
	endtask

	task automatic ack_phase_case;
		localparam logic [18:0] LINE = 19'h00140;
		localparam logic [31:0] ACCUM = {LINE, 13'd0};
		logic [3:0] match_slot;
		integer match_ce_phase;
		integer ordinary_latency;
		integer start_latency;
		integer ordinary_accepts;
		integer start_accepts;
		integer accepts_before_start;
		begin
			reset_dut();
			set_active(5'd0);
			configure_stopped_voice(0, ACCUM, 17'h00800);
			wait_prefetch_quiet();
			assert (!cache_line_valid(0, 0, LINE))
				else $fatal(1, "ACK-phase fixture was not cold");

			// Ordinary STOP-to-STOP CONTROL final byte.
			set_page(7'd0);
			write_byte(6'h00, 8'd0);
			write_byte(6'h01, 8'd0);
			write_byte(6'h02, 8'd0);
			audio_enable = 1'b1;
			// Do not capture the one-off reset-to-first-launch interval: its
			// early idle phases legitimately never recur once the periodic voice
			// engine is running. Enter steady-state before choosing the signature.
			begin : wait_steady_strobe
				integer timeout;
				for (timeout = 0; timeout < 20000; timeout = timeout + 1) begin
					@(negedge clk);
					if (audio_strobe)
						disable wait_steady_strobe;
				end
				$fatal(1, "stopped-voice cadence did not reach steady state");
			end
			// Capture a phase the running adapter actually presents, then use
			// that exact full signature for both measured transfers. Guessing a
			// slot/CE pairing would make a timeout a fixture error, not evidence.
			begin : capture_eligible_phase
				integer timeout;
				for (timeout = 0; timeout < 40000; timeout = timeout + 1) begin
					@(negedge clk);
					#0.002;
					if ((dut.engine_state == ENGINE_IDLE) &&
					    (dut.slot_count < 4'd14) && !ce_16m &&
					    !dut.host_pipeline_busy && !dut.host_seen &&
					    !dut.host_req_q && !host_req) begin
						match_slot = dut.slot_count;
						match_ce_phase = ce_phase;
						disable capture_eligible_phase;
					end
				end
				$fatal(1, "no eligible host phase available for matched comparison");
			end
			host_transfer_aligned(6'h03, 8'h03, match_slot,
			                      match_ce_phase, ordinary_latency,
			                      ordinary_accepts);
			wait_prefetch_quiet();

			// Cold STOP-to-RUN final byte from the identical eligible phase.
			set_page(7'd0);
			write_byte(6'h00, 8'd0);
			write_byte(6'h01, 8'd0);
			write_byte(6'h02, 8'd0);
			hold_line(0, 0, LINE);
			accepts_before_start = accepted_words;
			host_transfer_aligned(6'h03, 8'h00, match_slot,
			                      match_ce_phase, start_latency,
			                      start_accepts);
			assert (ordinary_latency == start_latency)
				else $fatal(1, "matched-phase START ACK differs ordinary=%0d start=%0d",
				            ordinary_latency, start_latency);
			assert (start_accepts == accepts_before_start)
				else $fatal(1, "cold START ACK waited for external ROM before=%0d at_ack=%0d",
				            accepts_before_start, start_accepts);
			wait_control(0, 16'h0000);
			wait_held_request(0, 0, LINE);
			hold_key_enable = 1'b0;
			audio_enable = 1'b0;
			$display("PASS ES_START_MISS ack-phase ordinary=%0d cold-start=%0d slot=%0d ce_phase=%0d",
			         ordinary_latency, start_latency, match_slot, match_ce_phase);
		end
	endtask

	task automatic mixed_hit_miss_case;
		localparam logic [18:0] HIT_LINE = 19'h00158;
		localparam logic [18:0] MISS_LINE = 19'h00168;
		localparam logic [31:0] HIT_ACCUM = {HIT_LINE, 13'd0};
		localparam logic [31:0] MISS_ACCUM = {MISS_LINE, 13'd0};
		voice_row_bits_t frozen_missing_engine;
		voice_row_bits_t frozen_missing_prefetch;
		logic signed [31:0] hit_left;
		logic signed [31:0] hit_right;
		logic hit_seen;
		logic miss_seen;
		logic nonzero_seen;
		integer latency;
		integer accepted_at_ack;
		integer frames;
		integer timeout;
		begin
			reset_dut();
			set_active(5'd1);
			configure_stopped_voice(0, HIT_ACCUM, 17'd0);
			configure_stopped_voice(1, MISS_ACCUM, 17'd0);
			wait_prefetch_quiet();

			// Prime only voice0 while device time is stopped. Its first real
			// two-voice scan is therefore a cache hit with no prior DSP history.
			start_control(0, 16'h0300, latency);
			wait_cache_line(0, 0, HIT_LINE);
			assert (!cache_line_valid(1, 0, MISS_LINE))
				else $fatal(1, "missing-voice fixture was accidentally resident");

			hold_line(1, 0, MISS_LINE);
			write_control(1, 16'h0000, latency, accepted_at_ack);
			assert (latency <= ACK_BOUND)
				else $fatal(1, "mixed missing-voice START ACK exceeded bound latency=%0d",
				            latency);
			wait_held_request(1, 0, MISS_LINE);
			frozen_missing_engine = engine_row(1);
			frozen_missing_prefetch = prefetch_row(1);
			assert (frozen_missing_engine === frozen_missing_prefetch)
				else $fatal(1, "missing voice replicas differed before mixed scan");

			hit_seen = 1'b0;
			miss_seen = 1'b0;
			nonzero_seen = 1'b0;
			frames = 0;
			arm_cadence(200);
			begin : observe_mixed_frames
				for (timeout = 0; timeout < 80000; timeout = timeout + 1) begin
					@(negedge clk);
					if ((dut.engine_state == ENGINE_COMMIT) &&
					    (dut.work_voice == 0)) begin
						hit_left = $signed(dut.voice_mix_left_reg);
						hit_right = $signed(dut.voice_mix_right_reg);
						hit_seen = 1'b1;
					end
					if (dut.sample_underrun && (dut.work_voice == 0))
						$fatal(1, "resident voice0 took miss fallback in mixed scan");
					if (dut.sample_underrun && (dut.work_voice == 1)) begin
						miss_seen = 1'b1;
						assert ((engine_row(1) === frozen_missing_engine) &&
						        (prefetch_row(1) === frozen_missing_prefetch) &&
						        (engine_row(1) === prefetch_row(1)))
							else $fatal(1, "missing voice row advanced in mixed scan");
					end
					if (audio_strobe) begin
						assert (hit_seen && miss_seen)
							else $fatal(1, "mixed frame lacked one hit and one miss hit=%0d miss=%0d",
							            hit_seen, miss_seen);
						assert (($signed(audio_left) == clamp_mix20(hit_left)) &&
						        ($signed(audio_right) == clamp_mix20(hit_right)))
							else $fatal(1, "missing voice polluted hit sum expected=%0d/%0d actual=%0d/%0d",
							            $signed(clamp_mix20(hit_left)),
							            $signed(clamp_mix20(hit_right)),
							            $signed(audio_left), $signed(audio_right));
						assert ((audio_left_channels[119:20] == 0) &&
						        (audio_right_channels[119:20] == 0))
							else $fatal(1, "mixed hit/miss escaped canonical channel0");
						if ((audio_left != 0) || (audio_right != 0))
							nonzero_seen = 1'b1;
						frames = frames + 1;
						hit_seen = 1'b0;
						miss_seen = 1'b0;
						if (frames == 3)
							disable observe_mixed_frames;
					end
				end
				$fatal(1, "mixed hit/miss frames timed out got=%0d", frames);
			end
			@(posedge clk);
			#0.002;
			assert (nonzero_seen)
				else $fatal(1, "resident voice contribution was trivially zero");
			assert (cadence_strobes >= 3)
				else $fatal(1, "mixed hit/miss cadence did not cover three frames");
			hold_key_enable = 1'b0;
			$display("PASS ES_START_MISS mixed-hit-miss frames=%0d misses=%0d strobes=%0d",
			         frames, dut.sample_underrun_count, cadence_strobes);
		end
	endtask

	task automatic new_bank_case;
		localparam logic [18:0] LINE = 19'h00148;
		localparam logic [31:0] ACCUM = {LINE, 13'd0};
		localparam logic [16:0] FREQ = 17'h00800;
		integer latency;
		integer ignored_latency;
		integer ignored_accepted;
		begin
			reset_dut();
			set_active(5'd0);
			configure_stopped_voice(0, ACCUM, FREQ);
			start_control(0, 16'h0000, latency);
			wait_cache_line(0, 0, LINE);
			write_control(0, 16'h0003, ignored_latency, ignored_accepted);
			wait_prefetch_quiet();
			assert (cache_line_valid(0, 0, LINE))
				else $fatal(1, "bank0 priming line was lost");
			assert (!cache_line_valid(0, 2, LINE))
				else $fatal(1, "bank2 unexpectedly resident before START");
			clear_tracking(0, 2, LINE, 1'b0, 19'd0);
			hold_line(0, 2, LINE);
			start_control(0, 16'h8000, latency);
			wait_held_request(0, 2, LINE);
			arm_freeze();
			arm_cadence(100);
			wait_misses(3);
			assert (bank_miss_seen)
				else $fatal(1, "new-bank START reused the stale bank0 tag");
			hold_key_enable = 1'b0;
			wait_cache_line(0, 2, LINE);
			wait_voice0_commit(ACCUM + {15'd0, FREQ}, 1'b0, 16'd0,
			                   1'b1, authored_word(2, {LINE, 3'd0}, 0, 0));
			assert (tracking_words_a == 4'hf)
				else $fatal(1, "new bank did not fetch a complete qword mask=%x",
				            tracking_words_a);
			$display("PASS ES_START_MISS new-bank ACK=%0d misses=%0d strobes=%0d",
			         latency, miss_count, cadence_strobes);
		end
	endtask

	task automatic contention_case;
		localparam logic [18:0] OWNER_LINE = 19'h00160;
		localparam logic [18:0] TARGET_LINE = 19'h00170;
		localparam logic [31:0] OWNER_ACCUM = {OWNER_LINE, 13'd0};
		localparam logic [31:0] TARGET_ACCUM = {TARGET_LINE, 13'd0};
		integer latency;
		integer accepted_at_ack;
		logic [7:0] ignored;
		logic [1:0] signature_bank;
		logic [21:0] signature_addr;
		logic signature_companded;
		logic [4:0] signature_voice;
		begin
			reset_dut();
			urgent_collision_seen = 1'b0;
			older_urgent_dispatch_seen = 1'b0;
			set_active(5'd2);
			configure_stopped_voice(0, TARGET_ACCUM, 17'h00800);
			configure_stopped_voice(1, OWNER_ACCUM, 17'h00800);
			configure_stopped_voice(2, 32'h00200000, 17'h00800);
			begin : drain_setup_hints
				integer timeout;
				for (timeout = 0; timeout < 4000; timeout = timeout + 1) begin
					@(negedge clk);
					if ((dut.prefetch_urgent_pending == 0) &&
					    (dut.prefetch_program_pending == 0) &&
					    !sample_req && !mem_pending &&
					    (dut.prefetch_state == PREFETCH_SCAN))
						disable drain_setup_hints;
				end
				$fatal(1, "setup urgent hints did not drain before contention");
			end

			// Voice 1 owns the external sample transaction. Voice 2 is then
			// queued behind it by a real same-value CONTROL write; because it
			// remains stopped, this creates an older urgent descriptor without
			// introducing a second sample request.
			hold_line(1, 0, OWNER_LINE);
			start_control(1, 16'h0400, latency);
			wait_held_request(1, 0, OWNER_LINE);
			signature_bank = held_bank;
			signature_addr = held_addr;
			signature_companded = held_companded;
			signature_voice = held_voice;
			write_control(2, 16'h0003, latency, accepted_at_ack);
			assert (dut.prefetch_urgent_pending[2])
				else $fatal(1, "older voice A was not queued behind held owner");

			// Prepare voice B's START register without committing its low byte.
			// The final byte is issued below so its execute edge can be aligned
			// exactly with A's first eligible dispatch edge.
			set_page(7'd0);
			write_byte(6'h00, 8'd0);
			write_byte(6'h01, 8'd0);
			write_byte(6'h02, 8'd0);
			clear_tracking(0, 0, TARGET_LINE, 1'b0, 19'd0);

			// Re-keying the hold acknowledges owner word0 immediately. With the
			// registered one-at-a-time ROM model, four carrier edges put word2
			// into flight. A three-cycle host ACK plus one execute edge then
			// places B's hint precisely on the first SCAN edge for pending A.
			hold_line(0, 0, TARGET_LINE);
			repeat (4) @(posedge clk);
			host_transfer(1'b1, 6'h03, 8'h00, ignored,
			              latency, accepted_at_ack);
			assert (latency <= ACK_BOUND)
				else $fatal(1, "contended START ACK exceeded fixed bound latency=%0d",
				            latency);
			assert (tracking_words_a == 4'd0)
				else $fatal(1, "START ACK depended on target voice sample service");
			wait_control(0, 16'h0000);
			wait_held_request(0, 0, TARGET_LINE);
			assert (mem_pending &&
			        ({held_bank, held_addr, held_companded, held_voice} ===
			         {2'd0, {TARGET_LINE, 3'd0}, 1'b0, 5'd0}))
				else $fatal(1, "first owner did not drain before queued START request");
			assert ({signature_bank, signature_addr, signature_companded,
			         signature_voice} === {2'd0, {OWNER_LINE, 3'd0}, 1'b0, 5'd1})
				else $fatal(1, "held first-arrival request signature changed");
			// B's pending bit is allowed to be clear here: reaching its held
			// request proves that it was cleared by an actual urgent dispatch.
			// The exact collision oracle above checked that it was present on the
			// same edge as A before that dispatch occurred.
			assert (dut.prefetch_urgent_pending[2])
				else $fatal(1, "older A hint was cleared by same-edge B hint");
			assert (tracking_words_a == 4'd0)
				else $fatal(1, "target request was acknowledged before its hold");
			assert (urgent_collision_seen)
				else $fatal(1, "contention case missed pending-A/new-B urgent collision");
			hold_key_enable = 1'b0;
			wait_cache_line(0, 0, TARGET_LINE);
			assert (tracking_words_a == 4'hf)
				else $fatal(1, "queued START request did not drain completely mask=%x",
				            tracking_words_a);
			begin : wait_older_dispatch
				integer timeout;
				for (timeout = 0; timeout < 4000; timeout = timeout + 1) begin
					@(negedge clk);
					if (older_urgent_dispatch_seen)
						disable wait_older_dispatch;
				end
				$fatal(1, "older A hint was preserved but never dispatched");
			end
			$display("PASS ES_START_MISS contention ACK=%0d requests=%0d accepted=%0d",
			         latency, request_starts, accepted_words);
		end
	endtask

	task automatic hit_case;
		localparam logic [18:0] LINE = 19'h00188;
		localparam logic [31:0] ACCUM = {LINE, 13'd0};
		localparam logic [16:0] FREQ = 17'h00800;
		integer latency;
		integer ignored_latency;
		integer ignored_accepted;
		begin
			reset_dut();
			set_active(5'd0);
			configure_stopped_voice(0, ACCUM, FREQ);
			start_control(0, 16'h0000, latency);
			wait_cache_line(0, 0, LINE);
			write_control(0, 16'h0003, ignored_latency, ignored_accepted);
			wait_prefetch_quiet();
			assert (cache_line_valid(0, 0, LINE))
				else $fatal(1, "cache-hit fixture lost current line");
			clear_tracking(0, 0, LINE, 1'b0, 19'd0);
			hold_all = 1'b1;
			start_control(0, 16'h0000, latency);
			forbid_miss = 1'b1;
			arm_cadence(100);
			wait_voice0_commit(ACCUM + {15'd0, FREQ}, 1'b0, 16'd0,
			                   1'b1, authored_word(0, {LINE, 3'd0}, 0, 0));
			forbid_miss = 1'b0;
			assert (tracking_accepts == 0)
				else $fatal(1, "cache-hit START depended on a new target fetch");
			assert (dut.sample_underrun_count == 0)
				else $fatal(1, "cache-hit START incremented underrun counter");
			hold_all = 1'b0;
			$display("PASS ES_START_MISS hit ACK=%0d strobes=%0d",
			         latency, cadence_strobes);
		end
	endtask

	task automatic reset_case;
		localparam logic [18:0] LINE = 19'h001a0;
		localparam logic [31:0] ACCUM = {LINE, 13'd0};
		integer latency;
		integer timeout;
		begin
			reset_dut();
			set_active(5'd0);
			configure_stopped_voice(0, ACCUM, 17'h00800);
			clear_tracking(0, 0, LINE, 1'b0, 19'd0);
			hold_line(0, 0, LINE);
			start_control(0, 16'h0000, latency);
			arm_freeze();
			arm_cadence(100);
			wait_held_request(0, 0, LINE);
			wait_misses(1);
			cadence_check = 1'b0;
			audio_enable = 1'b0;
			freeze_check = 1'b0;
			@(negedge clk);
			reset = 1'b1;
			host_req = 1'b0;
			repeat (3) @(posedge clk);
			#0.002;
			assert (dut.local_reset && !sample_req && !host_ack)
				else $fatal(1, "reset did not cancel outstanding interfaces");
			assert ((dut.engine_state == ENGINE_IDLE) &&
			        (dut.prefetch_state == PREFETCH_INIT) &&
			        !dut.cache_initialized && (dut.voice_state_valid == 0) &&
			        (dut.prefetch_urgent_pending == 0) &&
			        (dut.prefetch_program_pending == 0) &&
			        (dut.sample_underrun_count == 0))
				else $fatal(1, "reset left START-miss state live");
			assert ((current_page == 0) && (active_voices == 5'h1f))
				else $fatal(1, "reset architectural defaults changed");

			@(negedge clk);
			reset = 1'b0;
			hold_key_enable = 1'b0;
			begin : wait_release
				for (timeout = 0; timeout < 20; timeout = timeout + 1) begin
					@(negedge clk);
					if (!dut.local_reset)
						disable wait_release;
				end
				$fatal(1, "local reset did not release after outstanding miss");
			end
			repeat (4) begin
				@(posedge clk);
				#0.002;
				assert (!host_ack)
					else $fatal(1, "ghost host ACK after reset");
			end
			set_page(7'h12);
			assert (current_page == 7'h12)
				else $fatal(1, "host path failed after reset");
			$display("PASS ES_START_MISS reset ACK=%0d misses_before_reset=%0d",
			         latency, miss_count);
		end
	endtask

	initial begin : watchdog
		repeat (400000) @(posedge clk);
		$fatal(1, "ES START-miss watchdog CASE=%s", test_case);
	end

	initial begin : test
		void'($value$plusargs("CASE=%s", test_case));
		case (test_case)
			"lower": lower_case();
			"upper": upper_case();
			"word3-zero": word3_zero_case();
			"ack-phase": ack_phase_case();
			"mixed-hit-miss": mixed_hit_miss_case();
			"new-bank": new_bank_case();
			"contention": contention_case();
			"hit": hit_case();
			"reset": reset_case();
			"prewarm": prewarm_case();
			"prewarm-priority": prewarm_priority_case();
			default: $fatal(1, "unknown START-miss CASE=%s", test_case);
		endcase
		$finish;
	end

endmodule
