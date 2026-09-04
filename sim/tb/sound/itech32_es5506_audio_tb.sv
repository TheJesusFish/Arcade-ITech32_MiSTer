// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module itech32_es5506_audio_tb;

	logic clk = 1'b0;
	logic reset = 1'b1;
	logic ce_16m = 1'b0;
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
	logic [2:0] mem_delay = 3'd0;
	logic [1:0] held_bank = 2'd0;
	logic [21:0] held_addr = 22'd0;
	logic held_companded = 1'b0;
	logic [4:0] held_voice = 5'd0;
	logic [15:0] lfsr = 16'h1ace;
	integer fetch_count = 0;
	integer stall_cycles = 0;

	always #5 clk = ~clk;

	// ce_16m is intentionally continuous in this arithmetic-focused TB.
	// A 32-clock slot leaves the fixed T0..T28 engine pipeline enough room;
	// real 16 MHz cadence is covered with SLOT_TICKS=16 by cadence_tb.
	itech32_es5506 #(
		.SLOT_TICKS (32)
	) dut (
		.clk              (clk),
		.reset            (reset),
		.ce_16m           (ce_16m),
		.host_req         (host_req),
		.host_write       (host_write),
		.host_addr        (host_addr),
		.host_wdata       (host_wdata),
		.host_rdata       (host_rdata),
		.host_ack         (host_ack),
		.par_comparator_tripped (1'b0),
		.par_discharge    (),
		.sample_req       (sample_req),
		.sample_bank      (sample_bank),
		.sample_addr      (sample_addr),
		.sample_companded (sample_companded),
		.sample_voice     (sample_voice),
		.sample_rdata     (sample_rdata),
		.sample_ack       (sample_ack),
		.audio_left       (audio_left),
		.audio_right      (audio_right),
		.audio_strobe     (audio_strobe),
		.irq              (irq),
		.irq_vector       (irq_vector),
		.current_page     (current_page),
		.active_voices    (active_voices),
		.scan_voice       (scan_voice),
		.engine_busy      (engine_busy)
	);

	function automatic [15:0] sample_word(
		input logic [1:0] bank,
		input logic [21:0] byte_address
	);
		logic [20:0] word_address;
		begin
			word_address = byte_address[21:1];
			sample_word = 16'd0;
			case (bank)
				2'd0: begin
					case (word_address)
						21'd64, 21'd65: sample_word = 16'he000;
						21'd80, 21'd81: sample_word = 16'h4000;
						21'd96: sample_word = 16'h8000;
						21'd97: sample_word = 16'h7fff;
						default: sample_word = 16'd0;
					endcase
				end
				2'd1: sample_word = 16'h2000;
				2'd2: begin
					case (word_address)
						21'd16: sample_word = 16'h1000;
						21'd17: sample_word = 16'h3000;
						default: sample_word = 16'h0800;
					endcase
				end
				2'd3: sample_word = 16'h1800;
			endcase
		end
	endfunction

	assign sample_ack = mem_pending && (mem_delay == 0);
	assign sample_rdata = sample_word(held_bank, held_addr);

	// Deterministic pseudo-random 0..7-cycle sample-ROM latency. Every stalled
	// request is checked for stable address, bank, format, and voice payload.
	always_ff @(posedge clk) begin
		if (reset) begin
			mem_pending <= 1'b0;
			mem_delay <= 3'd0;
			held_bank <= 2'd0;
			held_addr <= 22'd0;
			held_companded <= 1'b0;
			held_voice <= 5'd0;
			lfsr <= 16'h1ace;
		end else if (!mem_pending) begin
			if (sample_req) begin
				mem_pending <= 1'b1;
				mem_delay <= lfsr[2:0];
				held_bank <= sample_bank;
				held_addr <= sample_addr;
				held_companded <= sample_companded;
				held_voice <= sample_voice;
				lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
				fetch_count <= fetch_count + 1;
			end
		end else begin
			if (!sample_req)
				$fatal(1, "sample request dropped before acknowledgment");
			if (sample_bank != held_bank || sample_addr != held_addr ||
			    sample_companded != held_companded || sample_voice != held_voice)
				$fatal(1, "sample request payload changed while stalled");
			if (mem_delay != 0) begin
				mem_delay <= mem_delay - 3'd1;
				stall_cycles <= stall_cycles + 1;
			end else begin
				mem_pending <= 1'b0;
			end
		end
	end

	task automatic host_transfer(
		input  logic       write_cycle,
		input  logic [5:0] address,
		input  logic [7:0] write_data,
		output logic [7:0] read_data
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
				$fatal(1, "host transaction timed out at %02x", address);
			end
			read_data = host_rdata;
			@(negedge clk);
			host_req = 1'b0;
			host_write = 1'b0;
			@(posedge clk);
			#1;
		end
	endtask

	task automatic write_byte(input logic [5:0] address, input logic [7:0] data);
		logic [7:0] ignored;
		begin
			host_transfer(1'b1, address, data, ignored);
		end
	endtask

	task automatic read_byte(input logic [5:0] address, output logic [7:0] data);
		begin
			host_transfer(1'b0, address, 8'd0, data);
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

	task automatic read_reg(input logic [3:0] slot, output logic [31:0] data);
		logic [7:0] b0;
		logic [7:0] b1;
		logic [7:0] b2;
		logic [7:0] b3;
		begin
			read_byte({slot, 2'd0}, b0);
			read_byte({slot, 2'd1}, b1);
			read_byte({slot, 2'd2}, b2);
			read_byte({slot, 2'd3}, b3);
			data = {b0, b1, b2, b3};
		end
	endtask

	task automatic set_page(input logic [6:0] page);
		begin
			write_reg(4'hf, {25'd0, page});
		end
	endtask

	task automatic set_active(input logic [4:0] last_voice);
		begin
			set_page(7'd0);
			write_reg(4'hb, {27'd0, last_voice});
		end
	endtask

	task automatic program_voice(
		input logic [4:0] voice,
		input logic [15:0] control,
		input logic [16:0] frequency,
		input logic [31:0] start_address,
		input logic [31:0] end_address,
		input logic [31:0] accumulator,
		input logic [15:0] left_volume,
		input logic [15:0] right_volume,
		input logic [15:0] k1,
		input logic [15:0] k2,
		input logic signed [31:0] history
	);
		logic [31:0] history_reg;
		begin
			// Fixture arguments are integer samples. The Rev2.3 history map
			// stores a fractional bit below FD0, so encode signed16.1 here.
			history_reg = (history << 1) & 32'h0003ffff;
			set_page({2'b01, voice});
			write_reg(4'h1, start_address);
			write_reg(4'h2, end_address);
			write_reg(4'h3, accumulator);
			write_reg(4'h4, history_reg);
			write_reg(4'h5, history_reg);
			write_reg(4'h6, history_reg);
			write_reg(4'h7, history_reg);
			write_reg(4'h8, history_reg);
			write_reg(4'h9, history_reg);
			set_page({2'b00, voice});
			write_reg(4'h1, {15'd0, frequency});
			write_reg(4'h2, {16'd0, left_volume});
			write_reg(4'h4, {16'd0, right_volume});
			write_reg(4'h7, {16'd0, k2});
			write_reg(4'h9, {16'd0, k1});
			write_reg(4'h0, {16'd0, control});
		end
	endtask

	task automatic read_voice_low(
		input logic [4:0] voice,
		input logic [3:0] slot,
		output logic [31:0] data
	);
		begin
			set_page({2'b00, voice});
			read_reg(slot, data);
		end
	endtask

	task automatic read_voice_high(
		input logic [4:0] voice,
		input logic [3:0] slot,
		output logic [31:0] data
	);
		begin
			set_page({2'b01, voice});
			read_reg(slot, data);
		end
	endtask

	task automatic reset_dut;
		integer timeout;
		begin
			@(negedge clk);
			ce_16m = 1'b0;
			host_req = 1'b0;
			reset = 1'b1;
			repeat (4) @(posedge clk);
			@(negedge clk);
			reset = 1'b0;
			timeout = 0;
			do begin
				@(posedge clk);
				#1;
				timeout = timeout + 1;
			end while (!dut.cache_initialized && timeout < 1200);
			if (!dut.cache_initialized)
				$fatal(1, "ES5506 audio cache initialization timed out");
		end
	endtask

	task automatic wait_audio(
		input logic signed [19:0] expected_left,
		input logic signed [19:0] expected_right,
		input string description
	);
		integer timeout;
		begin : wait_loop
			for (timeout = 0; timeout < 20000; timeout = timeout + 1) begin
				@(posedge clk);
				#1;
				// Cache priming is an explicit underrun condition, not a valid
				// golden sample.  The focused cadence test separately bounds and
				// asserts steady-state underruns under long DDR stalls.
				if (audio_strobe && !dut.sample_underrun && !dut.scan_underrun) begin
					if ($signed(audio_left) !== expected_left ||
					    $signed(audio_right) !== expected_right)
						$fatal(1, "%s audio: expected L=%0d R=%0d got L=%0d R=%0d",
						       description, expected_left, expected_right,
						       $signed(audio_left), $signed(audio_right));
					disable wait_loop;
				end
			end
			$fatal(1, "timeout waiting for %s audio", description);
		end
	endtask

	task automatic stop_audio_clock;
		begin
			@(negedge clk);
			ce_16m = 1'b0;
		end
	endtask

	task automatic expect_value(
		input logic [31:0] actual,
		input logic [31:0] expected,
		input string description
	);
		begin
			if (actual !== expected)
				$fatal(1, "%s: expected %08x got %08x", description,
				       expected, actual);
		end
	endtask

	initial begin : watchdog
		repeat (500000) @(posedge clk);
		$fatal(1, "ES5506 audio regression watchdog expired");
	end

	initial begin : test
		logic [31:0] value;
		logic [31:0] irq_read;
		integer fetches_before;
		integer voice;

		// Forward PCM interpolation, nonlinear volume, one-shot stop and IRQ.
		reset_dut();
		set_active(5'd3);
		program_voice(5'd3, 16'h8320, 17'h00c00,
		              32'h00008000, 32'h00008f80, 32'h00008400,
		              16'hf000, 16'he000, 16'h1234, 16'habcd, 32'sd8192);
		ce_16m = 1'b1;
		wait_audio(20'sd65536, 20'sd32768, "forward PCM/IRQ");
		stop_audio_clock();
		if (!irq || irq_vector != 8'h03)
			$fatal(1, "voice-3 end IRQ was not latched");
		read_voice_high(5'd3, 4'h3, value);
		expect_value(value, 32'h00009000, "one-shot overshot accumulator");
		read_voice_low(5'd3, 4'h0, value);
		// Rev2.3 section 14 retains CR.IRQ until IRQV is acknowledged and
		// this voice is processed again; assigning its vector does not clear it.
		expect_value(value, 32'h000083a1, "one-shot STOP0/control state");
		read_reg(4'he, irq_read);
		expect_value(irq_read, 32'h00000003, "IRQV read latch");
		if (irq || irq_vector != 8'h80)
			$fatal(1, "IRQV lane-zero read did not acknowledge IRQ");

		// MAME forward loop formula preserves the overshoot past END.
		reset_dut();
		set_active(5'd0);
		program_voice(5'd0, 16'h4308, 17'h00800,
		              32'h00010000, 32'h00010800, 32'h00010400,
		              16'hc000, 16'hc000, 16'hffff, 16'hffff, 32'sd8192);
		ce_16m = 1'b1;
		wait_audio(20'sd8192, 20'sd8192, "unidirectional loop");
		stop_audio_clock();
		read_voice_high(5'd0, 4'h3, value);
		expect_value(value, 32'h00010400, "LPE overshoot wrap");
		read_voice_low(5'd0, 4'h0, value);
		expect_value(value, 32'h00004308, "LPE control");

		// BLE-only is ES5506 trans-wave: wrap once, then replace loop bits by LEI.
		reset_dut();
		set_active(5'd0);
		program_voice(5'd0, 16'h4310, 17'h00800,
		              32'h00010000, 32'h00010800, 32'h00010400,
		              16'hc000, 16'hc000, 16'hffff, 16'hffff, 32'sd8192);
		ce_16m = 1'b1;
		wait_audio(20'sd8192, 20'sd8192, "trans-wave loop");
		stop_audio_clock();
		read_voice_high(5'd0, 4'h3, value);
		expect_value(value, 32'h00010400, "BLE overshoot wrap");
		read_voice_low(5'd0, 4'h0, value);
		expect_value(value, 32'h00004304, "BLE to LEI transition");

		// Bidirectional looping reflects overshoot and toggles direction on each edge.
		reset_dut();
		set_active(5'd0);
		program_voice(5'd0, 16'hc318, 17'h00800,
		              32'h00018000, 32'h00018800, 32'h00018400,
		              16'hc000, 16'hc000, 16'hffff, 16'hffff, 32'sd6144);
		ce_16m = 1'b1;
		wait_audio(20'sd6144, 20'sd6144, "bidir forward edge");
		stop_audio_clock();
		read_voice_high(5'd0, 4'h3, value);
		expect_value(value, 32'h00018400, "bidir forward reflection");
		read_voice_low(5'd0, 4'h0, value);
		expect_value(value, 32'h0000c358, "bidir reverse toggle");
		ce_16m = 1'b1;
		wait_audio(20'sd6144, 20'sd6144, "bidir reverse edge");
		stop_audio_clock();
		read_voice_high(5'd0, 4'h3, value);
		expect_value(value, 32'h00018400, "bidir reverse reflection");
		read_voice_low(5'd0, 4'h0, value);
		expect_value(value, 32'h0000c318, "bidir forward toggle");

		// The full compressed bus word E000 decodes to -32768. Narrow-ROM
		// zero padding does not imply the old emulator's E080 midpoint bias.
		reset_dut();
		set_active(5'd0);
		program_voice(5'd0, 16'h2300, 17'h00000,
		              32'h00020000, 32'h00021000, 32'h00020000,
		              16'hc000, 16'h8000, 16'h4567, 16'h89ab, -32'sd32768);
		ce_16m = 1'b1;
		wait_audio(-20'sd32768, -20'sd2048, "companded e0 vector");
		stop_audio_clock();

		// Four simultaneous voices cover the printed9 filter table. The first
		// impulse values at the sixteen-bit panning input are
		// 16376,16372,16368,16368. Volume0 retains the implicit mantissa bit:
		// floor(sample*256/32)/32768 contributes3 raw twenty-bit LSBs each.
		reset_dut();
		set_active(5'd3);
		for (voice = 0; voice < 4; voice = voice + 1) begin
			program_voice(voice[4:0], {6'd0, voice[1:0], 8'd0}, 17'h00000,
			              32'h00028000, 32'h00029000, 32'h00028000,
			              16'hc000, 16'h0000, 16'hffff, 16'hffff, 32'sd0);
		end
		ce_16m = 1'b1;
		wait_audio(20'sd65484, 20'sd12, "four filter modes");
		stop_audio_clock();

		// Signed interpolation uses arithmetic shift: midpoint of -32768/+32767 is -1.
		reset_dut();
		set_active(5'd0);
		program_voice(5'd0, 16'h0300, 17'h00000,
		              32'h00030000, 32'h00031000, 32'h00030400,
		              16'hc000, 16'h0000, 16'hffff, 16'hffff, -32'sd1);
		ce_16m = 1'b1;
		wait_audio(-20'sd1, -20'sd1, "signed interpolation");
		stop_audio_clock();

		// Stopped voices still drain envelopes; ramps saturate like MAME.
		reset_dut();
		set_active(5'd0);
		set_page(7'd0);
		write_reg(4'h2, 32'h00000001);
		write_reg(4'h3, 32'h0000fe00);
		write_reg(4'h4, 32'h0000fffe);
		write_reg(4'h5, 32'h00000200);
		write_reg(4'h6, 32'h00000001);
		write_reg(4'h9, 32'h00000003);
		write_reg(4'ha, 32'h0000fe01);
		write_reg(4'h7, 32'h0000fffe);
		write_reg(4'h8, 32'h00000200);
		fetches_before = fetch_count;
		ce_16m = 1'b1;
		wait_audio(20'sd0, 20'sd0, "stopped envelope");
		stop_audio_clock();
		if (fetch_count != fetches_before)
			$fatal(1, "stopped voice unexpectedly fetched sample ROM");
		read_voice_low(5'd0, 4'h2, value);
		expect_value(value, 32'h00000000, "negative LVOL saturation");
		read_voice_low(5'd0, 4'h4, value);
		expect_value(value, 32'h0000ffff, "positive RVOL saturation");
		read_voice_low(5'd0, 4'h6, value);
		expect_value(value, 32'h00000000, "stopped ECOUNT decrement");
		read_voice_low(5'd0, 4'h9, value);
		expect_value(value, 32'h00000001, "slow negative K1 ramp");
		read_voice_low(5'd0, 4'h7, value);
		expect_value(value, 32'h0000ffff, "positive K2 saturation");

		// Two end events in one scan prove stacked per-voice IRQ semantics.
		reset_dut();
		set_active(5'd1);
		program_voice(5'd0, 16'h4320, 17'h00800,
		              32'h00010000, 32'h00010800, 32'h00010400,
		              16'hc000, 16'h0000, 16'hffff, 16'hffff, 32'sd8192);
		program_voice(5'd1, 16'h4320, 17'h00800,
		              32'h00010000, 32'h00010800, 32'h00010400,
		              16'hc000, 16'h0000, 16'hffff, 16'hffff, 32'sd8192);
		ce_16m = 1'b1;
		wait_audio(20'sd16384, 20'sd4, "stacked IRQ first scan");
		stop_audio_clock();
		if (!irq || irq_vector != 8'h00)
			$fatal(1, "first stacked IRQ vector mismatch");
		read_voice_low(5'd1, 4'h0, value);
		if ((value[15:0] & 16'h0080) == 0)
			$fatal(1, "second voice IRQ did not remain pending");
		read_reg(4'he, irq_read);
		expect_value(irq_read, 32'h00000000, "first stacked IRQ acknowledge");
		ce_16m = 1'b1;
		wait_audio(20'sd0, 20'sd0, "stacked IRQ promotion scan");
		stop_audio_clock();
		if (!irq || irq_vector != 8'h01)
			$fatal(1, "pending voice IRQ was not promoted on next scan");
		read_voice_low(5'd1, 4'h0, value);
		if ((value[15:0] & 16'h0080) == 0)
			$fatal(1, "promoted voice IRQ cleared before IRQV acknowledgment");
		read_reg(4'he, irq_read);
		expect_value(irq_read, 32'h00000001, "second stacked IRQ acknowledge");
		ce_16m = 1'b1;
		wait_audio(20'sd0, 20'sd0, "stacked IRQ retirement scan");
		stop_audio_clock();
		read_voice_low(5'd1, 4'h0, value);
		if ((value[15:0] & 16'h0080) != 0 || irq)
			$fatal(1, "acknowledged voice IRQ did not clear on next processing");

		if (fetch_count < 24 || stall_cycles < 20)
			$fatal(1, "randomized sample-memory stall coverage was too small (fetches=%0d stalls=%0d)",
			       fetch_count, stall_cycles);

		$display("PASS: ES5506 PCM/companding/filter/volume/envelope/loop/IRQ engine");
		$display("      sample fetches=%0d randomized stall cycles=%0d",
		         fetch_count, stall_cycles);
		$finish;
	end

endmodule
