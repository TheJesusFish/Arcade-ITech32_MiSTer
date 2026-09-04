// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module itech32_es5506_cadence_tb;

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
	logic audio_strobe;
	logic irq;
	logic [7:0] irq_vector;
	logic [6:0] current_page;
	logic [4:0] active_voices;
	logic [4:0] scan_voice;
	logic engine_busy;
	logic mem_pending = 1'b0;
	logic [9:0] mem_delay = 10'd0;
	logic [1:0] held_bank = 2'd0;
	logic [21:0] held_addr = 22'd0;
	logic held_companded = 1'b0;
	logic [4:0] held_voice = 5'd0;
	integer ce_phase = 0;
	integer cycle_count = 0;
	integer fetch_count = 0;
	integer strobe_count = 0;
	integer last_strobe_cycle = 0;
	integer phase_strobe_count = 0;
	integer expected_strobe_gap = 100;
	logic cadence_check_enable = 1'b0;
	logic cadence_phase_reset = 1'b0;
	integer underruns_at_start = 0;
	logic host_traffic_done = 1'b0;
	logic transitions_done = 1'b0;
	logic forced_miss_done = 1'b0;
	integer forced_miss_strobe = 0;
	integer forced_miss_underruns = 0;
	integer max_consecutive_underruns = 0;
	integer consecutive_underruns = 0;
	logic engine_fill_collision_arm = 1'b0;
	logic engine_fill_collision_injected = 1'b0;
	logic engine_fill_collision_masked = 1'b0;
	logic engine_fill_collision_missed = 1'b0;
	logic engine_fill_collision_recovered = 1'b0;
	logic prefetch_fill_collision_masked = 1'b0;
	logic prefetch_fill_collision_retried = 1'b0;
	logic directed_collision_window = 1'b0;
	logic directed_collision_clean = 1'b0;
	integer directed_collision_underruns = 0;
	logic directed_engine_fill_wait;
	logic [1:0] loop_window_kind = 2'd0;
	integer lpe_underruns = 0;
	integer lpe_consecutive_underruns = 0;
	integer lpe_max_consecutive_underruns = 0;
	integer ble_underruns = 0;
	integer ble_consecutive_underruns = 0;
	integer ble_max_consecutive_underruns = 0;
	integer lpe_wraps = 0;
	integer ble_wraps = 0;
	logic [24:0] host_phase_seen = 25'd0;
	integer lane0_read_count = 0;
	integer lane3_write_count = 0;
	integer zero_fallback_checks = 0;
	logic [24:0] urgent_selected_expected = 25'd0;
	logic [2:0] urgent_previous_prefetch_state = 3'd0;
	integer urgent_gather_checks = 0;
	integer urgent_select_checks = 0;
	integer urgent_target_checks = 0;

	always #5 clk = ~clk;

	itech32_es5506 dut (
		.clk(clk), .reset(reset), .ce_16m(ce_16m),
		.host_req(host_req), .host_write(host_write), .host_addr(host_addr),
		.host_wdata(host_wdata), .host_rdata(host_rdata), .host_ack(host_ack),
		.par_comparator_tripped(1'b0), .par_discharge(),
		.sample_req(sample_req), .sample_bank(sample_bank),
		.sample_addr(sample_addr), .sample_companded(sample_companded),
		.sample_voice(sample_voice), .sample_rdata(sample_rdata),
		.sample_ack(sample_ack), .audio_left(audio_left),
		.audio_right(audio_right), .audio_strobe(audio_strobe), .irq(irq),
		.irq_vector(irq_vector), .current_page(current_page),
		.active_voices(active_voices), .scan_voice(scan_voice),
		.engine_busy(engine_busy)
	);

	// PREFETCH_URGENT_GATHER/SELECT are enum values 5/6. The M10K prefetch port
	// presents the urgent row to GATHER; prove its registered descriptor and the
	// following target fields remain aligned.
	always @(negedge clk) begin
		if (reset || dut.local_reset) begin
			urgent_selected_expected = 25'd0;
			urgent_previous_prefetch_state = 3'd0;
			urgent_gather_checks = 0;
			urgent_select_checks = 0;
			urgent_target_checks = 0;
		end else begin
			if (dut.prefetch_state == 3'd5) begin
				if (dut.voice_prefetch_read_addr !== dut.prefetch_row_voice_q)
					$fatal(1, "urgent M10K row selector/voice mismatch");
				urgent_selected_expected = {
					dut.voice_prefetch_data.accum[31:13],
					((dut.voice_prefetch_data.control & 16'h0003) != 0),
					(dut.voice_prefetch_data.accum[12:11] == 2'd3) &&
						(dut.voice_prefetch_data.accum[10:2] != 9'd0),
					dut.voice_prefetch_data.control[15:14],
					(dut.prefetch_row_voice_q <= dut.active_voices_reg) &&
						(((dut.voice_prefetch_data.control & 16'h0003) == 0) ||
						 (dut.prefetch_row_program_q &&
						  ((dut.voice_prefetch_data.control & 16'h0003) != 0))),
					dut.voice_prefetch_data.control[13]
				};
				urgent_gather_checks = urgent_gather_checks + 1;
			end

			if (dut.prefetch_state == 3'd6) begin
				if (dut.prefetch_urgent_descriptor !== urgent_selected_expected)
					$fatal(1, "urgent registered M10K descriptor mismatch");
				urgent_select_checks = urgent_select_checks + 1;
			end

			if ((urgent_previous_prefetch_state == 3'd6) &&
			    (dut.prefetch_state == 3'd2)) begin
				if ((dut.prefetch_base_line_q !== urgent_selected_expected[24:6]) ||
				    (dut.prefetch_bank_q !== urgent_selected_expected[3:2]) ||
				    (dut.prefetch_running_q !== urgent_selected_expected[1]) ||
				    (dut.prefetch_companded_q !== urgent_selected_expected[0]) ||
				    (dut.prefetch_urgent_need_upper_q !==
				     urgent_selected_expected[4]))
					$fatal(1, "urgent selected descriptor changed at target stage");
				urgent_target_checks = urgent_target_checks + 1;
			end
			urgent_previous_prefetch_state = dut.prefetch_state;
		end
	end

	// Exact 16 MHz enable on a 100 MHz fabric clock: four enables per 25
	// clocks, so one ACTV=0 scan is exactly 16*25/4 = 100 fabric clocks.
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

	// The forced far landing reuses direct-map entry zero with a different tag.
	// Hold its final returned word until the engine's registered port reads that
	// same entry. This creates the Cyclone-V undefined cross-port RDW case on a
	// real fill edge, without forcing any DUT state. The collision mask must turn
	// the potentially mixed old/new tag+data result into an underrun, after which
	// the ordinary urgent retry must recover.
	assign directed_engine_fill_wait = engine_fill_collision_arm &&
		!engine_fill_collision_injected && mem_pending && (mem_delay == 0) &&
		(held_addr[21:3] == 19'h00300) && (held_addr[2:1] == 2'd3);
	assign sample_ack = mem_pending && (mem_delay == 0) &&
		(!directed_engine_fill_wait ||
		 ((dut.engine_state == 6'd2) &&
		  (dut.engine_cache_read_addr == dut.prefetch_entry_q)));
	assign sample_rdata = held_addr[17:2] ^ 16'h5a5a;

	// Occasional 665-cycle qword misses amid 96-cycle normal misses, followed
	// by three one-cycle hits.  At one word/output, average qword service must
	// remain below the 400-clock consumption interval; the eight-line window
	// absorbs the measured tail but cannot make permanent overload sustainable.
	// Every stalled cycle asserts held request stability.
	always_ff @(posedge clk) begin
		if (reset) begin
			mem_pending <= 1'b0;
			mem_delay <= 10'd0;
		end else if (!mem_pending) begin
			if (sample_req) begin
				mem_pending <= 1'b1;
				if (sample_addr[2:1] != 0)
					mem_delay <= 10'd1;
				else if (sample_addr[5:3] == 3'b111)
					mem_delay <= 10'd665;
				else
					mem_delay <= 10'd96;
				held_bank <= sample_bank;
				held_addr <= sample_addr;
				held_companded <= sample_companded;
				held_voice <= sample_voice;
				fetch_count <= fetch_count + 1;
			end
		end else begin
			if (!sample_req)
				$fatal(1, "sample request dropped before acknowledgment");
			if ({sample_bank, sample_addr, sample_companded, sample_voice} !==
			    {held_bank, held_addr, held_companded, held_voice})
				$fatal(1, "sample request payload changed while stalled");
			if (mem_delay != 0)
				mem_delay <= mem_delay - 10'd1;
			else
				mem_pending <= 1'b0;
		end
	end

	always_ff @(posedge clk) begin
		cycle_count <= cycle_count + 1;
		if (sample_ack && directed_engine_fill_wait) begin
			if (!dut.cache_fill_we ||
			    (dut.cache_write_addr != dut.engine_cache_read_addr) ||
			    (dut.cache_write_addr != dut.prefetch_target_entry))
				$fatal(1, "directed cache fill did not collide with both lookup addresses");
			engine_fill_collision_injected <= 1'b1;
		end
		if (engine_fill_collision_injected && !engine_fill_collision_masked &&
		    dut.engine_cache_collision_q)
			engine_fill_collision_masked <= 1'b1;
		if (engine_fill_collision_injected && !prefetch_fill_collision_masked &&
		    dut.prefetch_cache_collision_q) begin
			if (dut.prefetch_target_hit)
				$fatal(1, "prefetch consumed a same-entry fill collision as a hit");
			prefetch_fill_collision_masked <= 1'b1;
		end
		if (engine_fill_collision_masked && !engine_fill_collision_missed) begin
			if ((dut.engine_state == 6'd28) && (dut.work_voice == 0))
				$fatal(1, "engine committed a mixed tag/data result after fill collision");
			if (dut.sample_underrun) begin
				if (dut.debug_voice0_accum != 32'h00601c00)
					$fatal(1, "collision miss advanced voice accumulator");
				engine_fill_collision_missed <= 1'b1;
			end
		end
		if (engine_fill_collision_missed && !engine_fill_collision_recovered &&
		    (dut.engine_state == 6'd28) && (dut.work_voice == 0))
			engine_fill_collision_recovered <= 1'b1;
		// PREFETCH_LOOKUP is enum value 3. A later registered lookup of the
		// collided current line must see the completed tag cleanly; this proves
		// the collision pulse was a miss, not a permanently poisoned entry.
		if (prefetch_fill_collision_masked && !prefetch_fill_collision_retried &&
		    (dut.prefetch_state == 3'd3) &&
		    (dut.prefetch_line_q == 19'h00300) && dut.prefetch_target_hit)
			prefetch_fill_collision_retried <= 1'b1;
		if (cadence_phase_reset) begin
			phase_strobe_count <= 0;
			last_strobe_cycle <= 0;
		end
		if (audio_enable && audio_strobe) begin
			if (cadence_check_enable) begin
				if ((phase_strobe_count != 0) &&
				    ((cycle_count - last_strobe_cycle) != expected_strobe_gap))
					$fatal(1, "audio cadence changed: gap=%0d expected=%0d ACTV=%0d",
					       cycle_count - last_strobe_cycle,
					       expected_strobe_gap, active_voices);
				last_strobe_cycle <= cycle_count;
				phase_strobe_count <= phase_strobe_count + 1;
			end
			if (dut.sample_underrun || dut.scan_underrun) begin
				// This fixture runs ACTV=0, so a missing voice contributes the
				// complete output. A cache miss must freeze its state and emit zero;
				// replaying an older sample/register result is never acceptable.
				if (($signed(audio_left) !== 20'sd0) ||
				    ($signed(audio_right) !== 20'sd0))
					$fatal(1, "cache miss replayed stale contribution L=%0d R=%0d",
					       $signed(audio_left), $signed(audio_right));
				zero_fallback_checks <= zero_fallback_checks + 1;
				if (directed_collision_window) begin
					directed_collision_underruns <=
						directed_collision_underruns + 1;
				end else if (!forced_miss_done && (forced_miss_strobe != 0)) begin
					forced_miss_underruns <= forced_miss_underruns + 1;
					consecutive_underruns <= consecutive_underruns + 1;
					if ((consecutive_underruns + 1) > max_consecutive_underruns)
						max_consecutive_underruns <= consecutive_underruns + 1;
				end else if (loop_window_kind == 2'd1) begin
					lpe_underruns <= lpe_underruns + 1;
					lpe_consecutive_underruns <=
						lpe_consecutive_underruns + 1;
					if ((lpe_consecutive_underruns + 1) >
					    lpe_max_consecutive_underruns)
						lpe_max_consecutive_underruns <=
							lpe_consecutive_underruns + 1;
				end else if (loop_window_kind == 2'd2) begin
					ble_underruns <= ble_underruns + 1;
					ble_consecutive_underruns <=
						ble_consecutive_underruns + 1;
					if ((ble_consecutive_underruns + 1) >
					    ble_max_consecutive_underruns)
						ble_max_consecutive_underruns <=
							ble_consecutive_underruns + 1;
				end else begin
					$fatal(1, "unexpected cache underrun at strobe %0d", strobe_count);
				end
			end else begin
				consecutive_underruns <= 0;
				lpe_consecutive_underruns <= 0;
				ble_consecutive_underruns <= 0;
				if ((forced_miss_strobe != 0) &&
				    (strobe_count >= (forced_miss_strobe + 12)))
					forced_miss_done <= 1'b1;
				if (directed_collision_window && engine_fill_collision_recovered)
					directed_collision_clean <= 1'b1;
			end
			strobe_count <= strobe_count + 1;
		end
		// ENGINE_COMMIT is enum value 28.  Qualifying the registered crossing
		// with the commit state prevents zero-fallback underruns from being counted as
		// additional wraps while the prior boundary flag is still held.
		if ((dut.engine_state == 6'd28) && dut.step_forward_crossed_reg) begin
			if (loop_window_kind == 2'd1)
				lpe_wraps <= lpe_wraps + 1;
			else if (loop_window_kind == 2'd2)
				ble_wraps <= ble_wraps + 1;
		end
	end

	task automatic host_transfer(
		input logic write_cycle,
		input logic [5:0] address,
		input logic [7:0] write_data
	);
		integer timeout;
		begin
			@(negedge clk);
			host_req = 1'b1;
			host_write = write_cycle;
			host_addr = address;
			host_wdata = write_data;
			begin : wait_ack
				for (timeout = 0; timeout < 200; timeout = timeout + 1) begin
					@(posedge clk);
					#1;
					if (host_ack)
						disable wait_ack;
				end
				$fatal(1, "host transaction timeout at %02x", address);
			end
			@(negedge clk);
			host_req = 1'b0;
			host_write = 1'b0;
			@(posedge clk);
		end
	endtask

	task automatic read_byte_traffic(input logic [5:0] address);
		integer timeout;
		begin
			@(negedge clk);
			host_req = 1'b1;
			host_write = 1'b0;
			host_addr = address;
			begin : wait_ack
				for (timeout = 0; timeout < 200; timeout = timeout + 1) begin
					@(posedge clk);
					if (host_ack)
						disable wait_ack;
				end
				$fatal(1, "traffic read timeout at %02x", address);
			end
			@(negedge clk);
			host_req = 1'b0;
		end
	endtask

	task automatic write_byte_traffic(
		input logic [5:0] address,
		input logic [7:0] data
	);
		integer timeout;
		begin
			@(negedge clk);
			host_req = 1'b1;
			host_write = 1'b1;
			host_addr = address;
			host_wdata = data;
			begin : wait_ack
				for (timeout = 0; timeout < 200; timeout = timeout + 1) begin
					@(posedge clk);
					if (host_ack)
						disable wait_ack;
				end
				$fatal(1, "traffic write timeout at %02x", address);
			end
			@(negedge clk);
			host_req = 1'b0;
			host_write = 1'b0;
		end
	endtask

	task automatic write_reg(input logic [3:0] slot, input logic [31:0] data);
		begin
			host_transfer(1'b1, {slot, 2'd0}, data[31:24]);
			host_transfer(1'b1, {slot, 2'd1}, data[23:16]);
			host_transfer(1'b1, {slot, 2'd2}, data[15:8]);
			host_transfer(1'b1, {slot, 2'd3}, data[7:0]);
		end
	endtask

	task automatic set_page(input logic [6:0] page);
		begin
			write_reg(4'hf, {25'd0, page});
		end
	endtask

	task automatic set_active_cadence_phase(
		input logic [4:0] voice_count,
		input integer gap_clocks
	);
		begin
			// ACTV architecturally restarts the scan counter, so exclude only
			// that explicit reconfiguration boundary.  Every subsequent gap is
			// checked against 100*(ACTV+1) fabric clocks.
			@(negedge clk);
			cadence_check_enable = 1'b0;
			set_page(7'd0);
			write_reg(4'hb, {27'd0, voice_count});
			wait (active_voices == voice_count);
			@(negedge clk);
			cadence_phase_reset = 1'b1;
			@(negedge clk);
			cadence_phase_reset = 1'b0;
			expected_strobe_gap = gap_clocks;
			cadence_check_enable = 1'b1;
		end
	endtask

	initial begin : watchdog
		repeat (800000) @(posedge clk);
		$fatal(1, "cadence regression watchdog expired");
	end

	// Valid asynchronous byte-lane reads exercise every host reservation and
	// response stage without mutating voice state.  Their pseudo-random spacing
	// deliberately crosses both busy and idle engine phases.
	initial begin : host_traffic
		integer phase_index;
		wait (audio_enable);
		for (phase_index = 0; phase_index < 25; phase_index = phase_index + 1) begin
			while (ce_phase != phase_index) @(negedge clk);
			host_phase_seen[phase_index] = 1'b1;
			read_byte_traffic({4'hd, 2'd0});
			lane0_read_count = lane0_read_count + 1;
			repeat (11) @(posedge clk);
			while (ce_phase != phase_index) @(negedge clk);
			// Slot 0xd is PAR/read-only, so this lane-3 completed write
			// exercises write_execute_pending without mutating voice state.
			write_byte_traffic({4'hd, 2'd3}, 8'h00);
			lane3_write_count = lane3_write_count + 1;
		end
		host_traffic_done = 1'b1;
	end

	// Toggle the architectural STOP bits without pausing ce_16m.  The stopped
	// terminal path must be phase-identical to a cache-hit running path.
	initial begin : terminal_transitions
		wait (audio_enable && (strobe_count >= 48));
		set_page(7'd0);
		write_reg(4'h0, 32'h00000301);
		wait (strobe_count >= 56);
		set_page(7'd0);
		write_reg(4'h0, 32'h00000300);
		wait (strobe_count >= 72);
		transitions_done = 1'b1;
	end

	// A far accumulator write forces an exact urgent landing outside the
	// eight-qword window while ce_16m remains live. At ACTV0, one or more zero
	// fallback frames are permissible under a 665-cycle tail, but cadence must
	// not move and the urgent refill must recover in a bounded number of scans.
	initial begin : forced_far_landing
		wait (audio_enable && (strobe_count >= 96));
		forced_miss_strobe = strobe_count;
		set_page(7'h20);
		write_reg(4'h3, 32'h00601c00);
	end

	// A transaction reserved below the last slot tick must clear all host
	// pipeline stages before the due enable; otherwise it would steal the
	// launch edge and stretch audio despite the independent counter.
	always_ff @(posedge clk) begin
		if (audio_enable && ce_16m && (dut.slot_count == 4'hf) &&
		    (dut.host_access_pending || dut.host_write_execute_pending ||
		     dut.host_read_select_pending || dut.host_read_response_pending))
			$fatal(1, "host pipeline overlapped a due voice-launch enable");
	end

	initial begin : test
		integer timeout;
		integer wrap_strobe;
		integer actv_index;
		reset = 1'b1;
		repeat (4) @(posedge clk);
		@(negedge clk);
		reset = 1'b0;

		set_page(7'd0);
		write_reg(4'hb, 32'd0);
		set_page(7'h20);
		write_reg(4'h1, 32'h00200000);
		write_reg(4'h2, 32'h7fffff80);
		write_reg(4'h3, 32'h00200000);
		set_page(7'd0);
		write_reg(4'h1, 32'h00000800);
		write_reg(4'h2, 32'h0000c000);
		write_reg(4'h4, 32'h0000c000);
		write_reg(4'h7, 32'h0000ffff);
		write_reg(4'h9, 32'h0000ffff);
		write_reg(4'h0, 32'h00000300);

		// Prime all eight qwords under the maximum measured miss latency.
		begin : wait_prime
			for (timeout = 0; timeout < 20000; timeout = timeout + 1) begin
				@(posedge clk);
				if ((fetch_count >= 32) && !sample_req && !mem_pending)
					disable wait_prime;
			end
			$fatal(1, "sample prefetch did not prime");
		end
		repeat (100) @(posedge clk);
		underruns_at_start = dut.sample_underrun_count;
		@(negedge clk);
		expected_strobe_gap = 100;
		cadence_check_enable = 1'b1;
		audio_enable = 1'b1;

		begin : wait_strobes
			for (timeout = 0; timeout < 40000; timeout = timeout + 1) begin
				@(posedge clk);
				if ((strobe_count >= 256) && host_traffic_done && transitions_done &&
				    forced_miss_done)
					disable wait_strobes;
			end
			$fatal(1, "timeout waiting for cadence coverage");
		end
		if (&host_phase_seen !== 1'b1 || lane0_read_count != 25 ||
		    lane3_write_count != 25)
			$fatal(1, "host phase/operation coverage incomplete");
		if (forced_miss_underruns == 0 || max_consecutive_underruns > 8)
			$fatal(1, "urgent far-landing recovery invalid (underruns=%0d max_run=%0d)",
			       forced_miss_underruns, max_consecutive_underruns);
		if (zero_fallback_checks == 0)
			$fatal(1, "zero-on-miss fallback was not exercised");
		if ((urgent_gather_checks == 0) ||
		    (urgent_gather_checks < urgent_select_checks) ||
		    (urgent_select_checks < urgent_target_checks) ||
		    ((urgent_gather_checks - urgent_select_checks) > 1) ||
		    ((urgent_select_checks - urgent_target_checks) > 1))
			$fatal(1, "urgent pipeline coverage invalid: gather=%0d select=%0d target=%0d",
			       urgent_gather_checks, urgent_select_checks, urgent_target_checks);
		$display("PASS: ES5506 ACTV=0 cadence under 665-cycle qword misses");
		$display("      strobes=%0d exact gap=100 clocks fetches=%0d underruns=%0d zero_checks=%0d urgent_checks=%0d",
		         strobe_count, fetch_count, dut.sample_underrun_count,
		         zero_fallback_checks, urgent_target_checks);

		// Exercise an actual corrected landing, not just a host accumulator
		// jump.  START and END are 16 qwords apart, so their direct-map index
		// aliases while their tags differ.  Two wraps prove that the exact
		// committed START+overshoot hint recovers repeatedly without endpoint
		// prefetch thrashing.
		loop_window_kind = 2'd1;
		set_page(7'd0);
		write_reg(4'h0, 32'h00000301);
		write_reg(4'h1, 32'h00000800);
		set_page(7'h20);
		write_reg(4'h1, 32'h00200000);
		write_reg(4'h2, 32'h00220000);
		write_reg(4'h3, 32'h00220000);
		set_page(7'd0);
		write_reg(4'h0, 32'h00000308);
		begin : wait_lpe_wraps
			for (timeout = 0; timeout < 30000; timeout = timeout + 1) begin
				@(posedge clk);
				if (lpe_wraps >= 2)
					disable wait_lpe_wraps;
			end
			$fatal(1, "long LPE loop did not wrap twice");
		end
		wrap_strobe = strobe_count;
		wait ((strobe_count >= (wrap_strobe + 12)) &&
		      (lpe_consecutive_underruns == 0));
		if ((dut.debug_voice0_accum < 32'h00200000) ||
		    (dut.debug_voice0_accum > 32'h00220000))
			$fatal(1, "LPE corrected accumulator escaped programmed loop");
		// The synchronous voice-row M10K adds one scanner edge to a corrected
		// landing; the prior eight-frame bound therefore becomes nine.
		if ((lpe_underruns == 0) || (lpe_max_consecutive_underruns > 9))
			$fatal(1, "far LPE recovery invalid (underruns=%0d max_run=%0d)",
			       lpe_underruns, lpe_max_consecutive_underruns);

		// BLE wraps once, then MAME/ES5506 semantics replace BLE with LEI.
		// Its START landing is likewise more than eight qwords from END.
		set_page(7'd0);
		write_reg(4'h0, 32'h00000301);
		loop_window_kind = 2'd2;
		set_page(7'h20);
		write_reg(4'h1, 32'h00400000);
		write_reg(4'h2, 32'h00420000);
		write_reg(4'h3, 32'h00420000);
		set_page(7'd0);
		write_reg(4'h0, 32'h00000310);
		begin : wait_ble_wrap
			for (timeout = 0; timeout < 10000; timeout = timeout + 1) begin
				@(posedge clk);
				if (ble_wraps >= 1)
					disable wait_ble_wrap;
			end
			$fatal(1, "far BLE landing did not execute");
		end
		if ((dut.debug_voice0_control & 16'h001c) != 16'h0004)
			$fatal(1, "BLE did not transition atomically to LEI: control=%04x",
			       dut.debug_voice0_control);
		wrap_strobe = strobe_count;
		wait ((strobe_count >= (wrap_strobe + 12)) &&
		      (ble_consecutive_underruns == 0));
		if ((ble_underruns == 0) || (ble_max_consecutive_underruns > 9))
			$fatal(1, "far BLE recovery invalid (underruns=%0d max_run=%0d)",
			       ble_underruns, ble_max_consecutive_underruns);

		// Return voice zero to a long non-looping region and let urgent refill
		// settle before sweeping ACTV.  Voices 1..31 remain stopped, so these
		// phases cover mixed running/stopped terminal paths at scale.
		set_page(7'd0);
		write_reg(4'h0, 32'h00000301);
		set_page(7'h20);
		write_reg(4'h1, 32'h00300000);
		write_reg(4'h2, 32'h00380000);
		write_reg(4'h3, 32'h00300000);
		set_page(7'd0);
		write_reg(4'h0, 32'h00000300);
		wrap_strobe = strobe_count;
		wait ((strobe_count >= (wrap_strobe + 12)) &&
		      (ble_consecutive_underruns == 0));
		loop_window_kind = 2'd0;

		// Sweep the complete architectural ACTV range. Four intervals apiece
		// cover voice-zero running followed by 0..31 padded stopped terminals.
		for (actv_index = 0; actv_index < 32; actv_index = actv_index + 1) begin
			set_active_cadence_phase(actv_index[4:0],
			                         100 * (actv_index + 1));
			wait (phase_strobe_count >= 5);
		end

		// Isolate the forced RDW collision after the golden loop/ACTV phases so
		// the intentionally delayed fill cannot shift their deterministic DDR
		// service phase. Return to ACTV0, then revisit the earlier far landing;
		// intervening regions have replaced its direct-map entry and force a fill.
		set_active_cadence_phase(5'd0, 100);
		wait (phase_strobe_count >= 5);
		directed_collision_window = 1'b1;
		engine_fill_collision_arm = 1'b1;
		set_page(7'h20);
		write_reg(4'h3, 32'h00601c00);
		begin : wait_directed_collision
			for (timeout = 0; timeout < 20000; timeout = timeout + 1) begin
				@(posedge clk);
				if (engine_fill_collision_recovered &&
				    prefetch_fill_collision_retried && directed_collision_clean)
					disable wait_directed_collision;
			end
			$fatal(1, "directed cache collision recovery timeout");
		end
		if (!engine_fill_collision_injected || !engine_fill_collision_masked ||
		    !engine_fill_collision_missed || !engine_fill_collision_recovered ||
		    !prefetch_fill_collision_masked || !prefetch_fill_collision_retried ||
		    !directed_collision_clean || (directed_collision_underruns == 0))
			$fatal(1, "directed cache collision coverage incomplete: inject=%0b engine_mask=%0b miss=%0b recover=%0b prefetch_mask=%0b retry=%0b",
			       engine_fill_collision_injected, engine_fill_collision_masked,
			       engine_fill_collision_missed, engine_fill_collision_recovered,
			       prefetch_fill_collision_masked, prefetch_fill_collision_retried);

		if (dut.sample_underrun_count !=
		    (underruns_at_start + forced_miss_underruns +
		     lpe_underruns + ble_underruns + directed_collision_underruns))
			$fatal(1, "unexpected underrun accounting: base=%0d forced=%0d LPE=%0d BLE=%0d total=%0d",
		       underruns_at_start, forced_miss_underruns, lpe_underruns,
		       ble_underruns, dut.sample_underrun_count);
		$display("PASS: far LPE/BLE landing and complete ACTV=0..31 exact cadence");
		$display("      LPE wraps=%0d underruns=%0d max_run=%0d; BLE wraps=%0d underruns=%0d max_run=%0d",
		         lpe_wraps, lpe_underruns, lpe_max_consecutive_underruns,
		         ble_wraps, ble_underruns, ble_max_consecutive_underruns);
		$finish;
	end

endmodule
