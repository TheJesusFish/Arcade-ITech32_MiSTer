// SPDX-License-Identifier: GPL-3.0-or-later
//
// ROM-free integration check for the ES5506 PAR host path. Expected PAR phase
// lengths are counted only from externally supplied ce_16m events. No internal
// converter, host-pipeline, or engine state is inspected.

`timescale 1ns/1ps
`default_nettype none

module itech32_es5506_par_tb;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic ce_16m = 1'b0;

	logic       host_req_dut = 1'b0;
	logic       host_write_dut = 1'b0;
	logic [5:0] host_addr_dut = 6'd0;
	logic [7:0] host_wdata_dut = 8'd0;
	logic [7:0] host_rdata_dut;
	logic       host_ack_dut;

	logic       host_req_ref = 1'b0;
	logic       host_write_ref = 1'b0;
	logic [5:0] host_addr_ref = 6'd0;
	logic [7:0] host_wdata_ref = 8'd0;
	logic [7:0] host_rdata_ref;
	logic       host_ack_ref;

	logic comparator_tripped = 1'b0;
	logic par_discharge_dut;
	logic par_discharge_ref;

	logic sample_req_dut;
	logic [1:0] sample_bank_dut;
	logic [21:0] sample_addr_dut;
	logic sample_companded_dut;
	logic [4:0] sample_voice_dut;
	logic sample_req_ref;
	logic [1:0] sample_bank_ref;
	logic [21:0] sample_addr_ref;
	logic sample_companded_ref;
	logic [4:0] sample_voice_ref;

	logic signed [19:0] audio_left_dut;
	logic signed [19:0] audio_right_dut;
	logic [119:0] audio_left_channels_dut;
	logic [119:0] audio_right_channels_dut;
	logic audio_strobe_dut;
	logic irq_dut;
	logic [7:0] irq_vector_dut;
	logic [6:0] current_page_dut;
	logic [4:0] active_voices_dut;
	logic [4:0] scan_voice_dut;
	logic engine_busy_dut;

	logic signed [19:0] audio_left_ref;
	logic signed [19:0] audio_right_ref;
	logic [119:0] audio_left_channels_ref;
	logic [119:0] audio_right_channels_ref;
	logic audio_strobe_ref;
	logic irq_ref;
	logic [7:0] irq_vector_ref;
	logic [6:0] current_page_ref;
	logic [4:0] active_voices_ref;
	logic [4:0] scan_voice_ref;
	logic engine_busy_ref;

	logic checks_enabled = 1'b0;
	integer dut_ack_count = 0;
	integer ref_ack_count = 0;
	logic [6:0] pages [0:5];
	integer page_index;

	always #5 clk = ~clk;

	// A permanently acknowledged zero-filled synthetic sample source keeps both
	// real engines deterministic. Reset voice state is stopped, so the source is
	// not expected to be requested by this test.
	itech32_es5506 dut (
		.clk(clk), .reset(reset), .ce_16m(ce_16m),
		.host_req(host_req_dut), .host_write(host_write_dut),
		.host_addr(host_addr_dut), .host_wdata(host_wdata_dut),
		.host_rdata(host_rdata_dut), .host_ack(host_ack_dut),
		.par_comparator_tripped(comparator_tripped),
		.par_discharge(par_discharge_dut),
		.sample_req(sample_req_dut), .sample_bank(sample_bank_dut),
		.sample_addr(sample_addr_dut),
		.sample_companded(sample_companded_dut),
		.sample_voice(sample_voice_dut), .sample_rdata(16'd0),
		.sample_ack(sample_req_dut), .audio_left(audio_left_dut),
		.audio_right(audio_right_dut),
		.audio_left_channels(audio_left_channels_dut),
		.audio_right_channels(audio_right_channels_dut),
		.audio_strobe(audio_strobe_dut), .irq(irq_dut),
		.irq_vector(irq_vector_dut), .current_page(current_page_dut),
		.active_voices(active_voices_dut), .scan_voice(scan_voice_dut),
		.engine_busy(engine_busy_dut)
	);

	// The control instance receives the same host timing, CE stream, sample data,
	// and comparator level. When DUT reads PAR slot13, REF reads slot12 instead;
	// both accesses use the same real byte-zero host pipeline but only DUT starts
	// a conversion. Host read data and PAR discharge are therefore the only
	// intentionally different public observations.
	itech32_es5506 ref_dut (
		.clk(clk), .reset(reset), .ce_16m(ce_16m),
		.host_req(host_req_ref), .host_write(host_write_ref),
		.host_addr(host_addr_ref), .host_wdata(host_wdata_ref),
		.host_rdata(host_rdata_ref), .host_ack(host_ack_ref),
		.par_comparator_tripped(comparator_tripped),
		.par_discharge(par_discharge_ref),
		.sample_req(sample_req_ref), .sample_bank(sample_bank_ref),
		.sample_addr(sample_addr_ref),
		.sample_companded(sample_companded_ref),
		.sample_voice(sample_voice_ref), .sample_rdata(16'd0),
		.sample_ack(sample_req_ref), .audio_left(audio_left_ref),
		.audio_right(audio_right_ref),
		.audio_left_channels(audio_left_channels_ref),
		.audio_right_channels(audio_right_channels_ref),
		.audio_strobe(audio_strobe_ref), .irq(irq_ref),
		.irq_vector(irq_vector_ref), .current_page(current_page_ref),
		.active_voices(active_voices_ref), .scan_voice(scan_voice_ref),
		.engine_busy(engine_busy_ref)
	);

	// A conversion is allowed to change only DUT's PAR read data and discharge
	// output. Cycle-exact equality of all other public engine observations proves
	// the integrated converter does not steal or move audio work.
	always @(posedge clk) begin
		#2;
		if (host_ack_dut)
			dut_ack_count = dut_ack_count + 1;
		if (host_ack_ref)
			ref_ack_count = ref_ack_count + 1;

		if (checks_enabled) begin
			assert (host_ack_dut === host_ack_ref)
				else $fatal(1, "PAR changed host acknowledgement timing");
			assert (sample_req_dut === sample_req_ref &&
			        sample_bank_dut === sample_bank_ref &&
			        sample_addr_dut === sample_addr_ref &&
			        sample_companded_dut === sample_companded_ref &&
			        sample_voice_dut === sample_voice_ref)
				else $fatal(1, "PAR changed sample-ROM transaction timing");
			assert (audio_left_dut === audio_left_ref &&
			        audio_right_dut === audio_right_ref &&
			        audio_left_channels_dut === audio_left_channels_ref &&
			        audio_right_channels_dut === audio_right_channels_ref &&
			        audio_strobe_dut === audio_strobe_ref)
				else $fatal(1, "PAR changed PCM data or audio-strobe timing");
			assert (irq_dut === irq_ref && irq_vector_dut === irq_vector_ref)
				else $fatal(1, "PAR changed IRQ state");
			assert (current_page_dut === current_page_ref &&
			        active_voices_dut === active_voices_ref &&
			        scan_voice_dut === scan_voice_ref &&
			        engine_busy_dut === engine_busy_ref)
				else $fatal(1, "PAR changed page/active/scan/engine state");
			assert (!par_discharge_ref)
				else $fatal(1, "control access unexpectedly started PAR");
		end
	end

	// Leave at least the real engine's T0..T28 fabric-clock budget between CE
	// events. This is still much faster than a wall-clock 16 MHz simulation while
	// preserving the production ES deadline contract.
	task automatic pulse_ce(input integer event_count);
		integer event_index;
		begin
			for (event_index = 0; event_index < event_count;
			     event_index = event_index + 1) begin
				@(negedge clk);
				ce_16m = 1'b1;
				@(posedge clk);
				#2;
				@(negedge clk);
				ce_16m = 1'b0;
				repeat (32) @(posedge clk);
			end
		end
	endtask

	task automatic pair_access(
		input  logic [5:0] dut_address,
		input  logic [5:0] ref_address,
		input  logic       write_cycle,
		input  logic [7:0] write_data,
		input  integer     held_edges,
		output logic [7:0] dut_read_data
	);
		integer timeout;
		integer held_index;
		begin
			assert (held_edges >= 1) else $fatal(1, "invalid held edge count");
			@(negedge clk);
			host_req_dut = 1'b1;
			host_req_ref = 1'b1;
			host_write_dut = write_cycle;
			host_write_ref = write_cycle;
			host_addr_dut = dut_address;
			host_addr_ref = ref_address;
			host_wdata_dut = write_data;
			host_wdata_ref = write_data;
			begin : wait_for_pair_ack
				for (timeout = 0; timeout < 200; timeout = timeout + 1) begin
					@(posedge clk);
					#3;
					if (host_ack_dut && host_ack_ref)
						disable wait_for_pair_ack;
				end
				$fatal(1, "paired host transaction timed out dut=%02h ref=%02h",
				       dut_address, ref_address);
			end
			dut_read_data = host_rdata_dut;
			for (held_index = 1; held_index < held_edges;
			     held_index = held_index + 1) begin
				@(posedge clk);
				#3;
				assert (!host_ack_dut && !host_ack_ref)
					else $fatal(1, "held host request acknowledged twice");
			end
			@(negedge clk);
			host_req_dut = 1'b0;
			host_req_ref = 1'b0;
			host_write_dut = 1'b0;
			host_write_ref = 1'b0;
			repeat (3) begin
				@(posedge clk);
				#3;
				assert (!host_ack_dut && !host_ack_ref)
					else $fatal(1, "host acknowledgement after request release");
			end
		end
	endtask

	task automatic pair_write_byte(
		input logic [5:0] address,
		input logic [7:0] data
	);
		logic [7:0] ignored;
		begin
			pair_access(address, address, 1'b1, data, 1, ignored);
		end
	endtask

	task automatic pair_write_reg(
		input logic [3:0] slot,
		input logic [31:0] data
	);
		begin
			pair_write_byte({slot, 2'd0}, data[31:24]);
			pair_write_byte({slot, 2'd1}, data[23:16]);
			pair_write_byte({slot, 2'd2}, data[15:8]);
			pair_write_byte({slot, 2'd3}, data[7:0]);
		end
	endtask

	task automatic set_page(input logic [6:0] page_value);
		begin
			pair_write_reg(4'hf, {25'd0, page_value});
			assert (current_page_dut == page_value &&
			        current_page_ref == page_value)
				else $fatal(1, "PAGE write failed expected=%0d dut=%0d ref=%0d",
				            page_value, current_page_dut, current_page_ref);
		end
	endtask

	// Slot12 is a control read with the same byte-zero host timing as common
	// slot13. It is intentionally substituted only in REF so its converter stays
	// idle while all non-PAR effects remain cycle-comparable.
	task automatic start_par_snapshot(output logic [7:0] byte0);
		begin
			pair_access(6'h34, 6'h30, 1'b0, 8'd0, 1, byte0);
			assert (par_discharge_dut)
				else $fatal(1, "PAR byte-zero read did not start discharge");
		end
	endtask

	task automatic read_retained_snapshot(
		input  logic [7:0] byte0,
		output logic [31:0] snapshot
	);
		logic [7:0] byte1;
		logic [7:0] byte2;
		logic [7:0] byte3;
		begin
			pair_access(6'h35, 6'h31, 1'b0, 8'd0, 1, byte1);
			pair_access(6'h36, 6'h32, 1'b0, 8'd0, 1, byte2);
			pair_access(6'h37, 6'h33, 1'b0, 8'd0, 1, byte3);
			snapshot = {byte0, byte1, byte2, byte3};
		end
	endtask

	task automatic snapshot_par(output logic [31:0] snapshot);
		logic [7:0] byte0;
		begin
			start_par_snapshot(byte0);
			read_retained_snapshot(byte0, snapshot);
		end
	endtask

	task automatic enter_measurement;
		begin
			assert (par_discharge_dut)
				else $fatal(1, "discharge inactive before CE count");
			pulse_ce(4095);
			assert (par_discharge_dut)
				else $fatal(1, "PAR discharge shorter than 4096 CE events");
			pulse_ce(1);
			assert (!par_discharge_dut)
				else $fatal(1, "PAR discharge longer than 4096 CE events");
		end
	endtask

	task automatic finish_at_count_without_read(input integer expected_count);
		begin
			assert (expected_count >= 0 && expected_count <= 1023)
				else $fatal(1, "invalid PAR expected count");
			comparator_tripped = 1'b0;
			enter_measurement();
			if (expected_count != 0)
				pulse_ce(expected_count * 4);
			comparator_tripped = 1'b1;
			pulse_ce(3);
			assert (!par_discharge_dut)
				else $fatal(1, "PAR measurement unexpectedly restarted");
			pulse_ce(1);
			comparator_tripped = 1'b0;
		end
	endtask

	task automatic finish_at_zero_without_read;
		begin
			comparator_tripped = 1'b0;
			enter_measurement();
			comparator_tripped = 1'b1;
			pulse_ce(4);
			comparator_tripped = 1'b0;
			assert (!par_discharge_dut)
				else $fatal(1, "zero-count completion restarted discharge");
		end
	endtask

	initial begin : watchdog
		repeat (12000000) @(posedge clk);
		$fatal(1, "ES5506 PAR integration watchdog expired");
	end

	initial begin : test
		logic [31:0] snapshot;
		logic [7:0] retained_byte0;
		logic [7:0] ignored;
		integer expected_prior;
		integer ack_before;
		integer timeout;

		pages[0] = 7'd0;
		pages[1] = 7'd31;
		pages[2] = 7'd32;
		pages[3] = 7'd63;
		pages[4] = 7'd64;
		pages[5] = 7'd127;

		repeat (4) @(posedge clk);
		@(negedge clk);
		reset = 1'b0;
		// Allow the local reset release and synthetic cache initialization to
		// settle before comparing every public engine observation.
		repeat (300) @(posedge clk);
		#3;
		checks_enabled = 1'b1;
		assert (current_page_dut == 0 && active_voices_dut == 5'h1f &&
		        irq_vector_dut == 8'h80 && !par_discharge_dut)
			else $fatal(1, "bad ES5506/PAR reset state");

		// Reset prior is the chosen deterministic maximum; Rev. 2.3 specifies
		// the post-read maximum but not the RESB value. The real lane-zero pipeline captures
		// that pre-edge value and starts discharge.
		snapshot_par(snapshot);
		assert (snapshot == 32'h000003ff)
			else $fatal(1, "PAR reset prior expected 000003ff got=%08h", snapshot);

		// A nontrivial threshold verifies one comparison per four CE events.
		finish_at_count_without_read(10'h2a5);

		// Byte zero exposes the completed 2a5 and restarts. Change the live result
		// to zero
		// before lanes1..3; those lanes must remain from the earlier snapshot.
		start_par_snapshot(retained_byte0);
		finish_at_zero_without_read();
		read_retained_snapshot(retained_byte0, snapshot);
		assert (snapshot == 32'h000002a5)
			else $fatal(1, "PAR retained lanes changed with live result: %08h",
			            snapshot);

		// PAR is common slot13 on all documented page cohorts. Chain each public
		// result into the next page so every page proves both visibility and start.
		expected_prior = 0;
		for (page_index = 0; page_index < 6; page_index = page_index + 1) begin
			set_page(pages[page_index]);
			snapshot_par(snapshot);
			assert (snapshot == {22'd0, expected_prior[9:0]})
				else $fatal(1, "PAR page=%0d expected=%03h got=%08h",
				            pages[page_index], expected_prior[9:0], snapshot);
			finish_at_count_without_read(page_index + 1);
			expected_prior = page_index + 1;
		end

		// Lanes1..3 and a byte-zero write are not conversion starts.
		pair_access(6'h35, 6'h35, 1'b0, 8'd0, 1, ignored);
		pair_access(6'h36, 6'h36, 1'b0, 8'd0, 1, ignored);
		pair_access(6'h37, 6'h37, 1'b0, 8'd0, 1, ignored);
		pair_access(6'h34, 6'h34, 1'b1, 8'h5a, 1, ignored);
		assert (!par_discharge_dut)
			else $fatal(1, "non-PAR lane/write started conversion");
		pulse_ce(12);
		assert (!par_discharge_dut)
			else $fatal(1, "deferred non-PAR conversion start");

		// Hold an accepted byte-zero request through a complete conversion. One
		// acknowledgement and one discharge prove the real host one-shot.
		ack_before = dut_ack_count;
		comparator_tripped = 1'b1;
		@(negedge clk);
		host_req_dut = 1'b1;
		host_req_ref = 1'b1;
		host_addr_dut = 6'h34;
		host_addr_ref = 6'h30;
		host_write_dut = 1'b0;
		host_write_ref = 1'b0;
		begin : wait_held_ack
			for (timeout = 0; timeout < 200; timeout = timeout + 1) begin
				@(posedge clk);
				#3;
				if (host_ack_dut && host_ack_ref)
					disable wait_held_ack;
			end
			$fatal(1, "held PAR request was not acknowledged");
		end
		assert (par_discharge_dut)
			else $fatal(1, "held PAR request did not start conversion");
		pulse_ce(4096);
		assert (!par_discharge_dut)
			else $fatal(1, "held PAR request restarted during discharge");
		pulse_ce(4);
		pulse_ce(12);
		assert (!par_discharge_dut && dut_ack_count == (ack_before + 1) &&
		        ref_ack_count == dut_ack_count)
			else $fatal(1, "held PAR request duplicated start/ack");
		@(negedge clk);
		host_req_dut = 1'b0;
		host_req_ref = 1'b0;
		comparator_tripped = 1'b0;
		repeat (3) @(posedge clk);

		// Prepare divider phase3, then make the qualifying CE event coincide with
		// the real byte-zero execute edge. Restart must win over completion.
		snapshot_par(snapshot);
		assert (snapshot == 32'h00000000)
			else $fatal(1, "completion-coincident setup prior");
		comparator_tripped = 1'b0;
		enter_measurement();
		comparator_tripped = 1'b1;
		pulse_ce(3);
		@(negedge clk);
		host_req_dut = 1'b1;
		host_req_ref = 1'b1;
		host_addr_dut = 6'h34;
		host_addr_ref = 6'h30;
		host_write_dut = 1'b0;
		host_write_ref = 1'b0;
		// Input capture, then idle reservation. The following edge is the real
		// host_access_pending execute edge which also receives qualifying CE.
		repeat (2) @(posedge clk);
		@(negedge clk);
		ce_16m = 1'b1;
		@(posedge clk);
		#3;
		assert (par_discharge_dut)
			else $fatal(1, "completion won over coincident PAR restart");
		@(negedge clk);
		ce_16m = 1'b0;
		begin : wait_coincident_ack
			for (timeout = 0; timeout < 200; timeout = timeout + 1) begin
				@(posedge clk);
				#3;
				if (host_ack_dut && host_ack_ref)
					disable wait_coincident_ack;
			end
			$fatal(1, "completion-coincident read was not acknowledged");
		end
		retained_byte0 = host_rdata_dut;
		@(negedge clk);
		host_req_dut = 1'b0;
		host_req_ref = 1'b0;
		comparator_tripped = 1'b0;
		repeat (32) @(posedge clk);
		read_retained_snapshot(retained_byte0, snapshot);
		assert (snapshot == 32'h000003ff && par_discharge_dut)
			else $fatal(1, "completion-coincident snapshot/restart mismatch %08h",
			            snapshot);
		finish_at_zero_without_read();

		assert (dut_ack_count == ref_ack_count)
			else $fatal(1, "paired host acknowledgement totals diverged");
		$display("PASS: real ES5506 PAR host integration, timing, pages, and isolation");
		$finish;
	end
endmodule

`default_nettype wire
