// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// CPU accesses that overlap the start of an index-2 NVRAM upload.
//
// runtime_hold only stops the TG68 from starting new cycles; the bus adapter
// still presents a cycle it captured just before the upload began. The main
// bus must finish anything it already accepted using the CPU's own address,
// must not accept a new access until the transfer has released the RAM ports,
// and the host must not read before nvram_host_ready.
module itech32_nvram_upload_race_tb;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic timekill_mode = 1'b0;
	logic bloodstorm_mode = 1'b0;
	logic cpu_req = 1'b0;
	logic cpu_we = 1'b0;
	logic [23:0] cpu_addr = 24'd0;
	logic [31:0] cpu_wdata = 32'd0;
	logic [3:0] cpu_be = 4'h0;
	logic cpu_ack;
	logic [31:0] cpu_rdata;
	logic nvram_host_access = 1'b0;
	logic nvram_host_write = 1'b0;
	logic [16:0] nvram_host_addr = 17'd0;
	logic [15:0] nvram_host_wdata = 16'd0;
	logic [15:0] nvram_host_rdata;
	logic nvram_host_ready;
	logic nvram_cpu_write;
	integer ack_count = 0;
	integer ack_before;
	integer checks = 0;

	itech32_main_bus dut (
		.clk(clk), .reset(reset), .profile(itech32_profile_tb_pkg::mode_profile(timekill_mode, bloodstorm_mode)),
		.rom_buffer_invalidate(1'b0),
		.cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata), .cpu_be(cpu_be), .cpu_ack(cpu_ack),
		.cpu_rdata(cpu_rdata),
		.input_p1(32'hffff_ffff), .input_p2(32'hffff_ffff),
		.input_p3(32'hffff_ffff), .input_p4(32'hffff_ffff),
		.input_dips(32'hffff_ffff), .input_extra(32'hffff_ffff), .trackball1(8'h00), .trackball2(8'h00),
		.nvram_host_access(nvram_host_access),
		.nvram_host_write(nvram_host_write),
		.nvram_host_addr(nvram_host_addr),
		.nvram_host_wdata(nvram_host_wdata),
		.nvram_host_rdata(nvram_host_rdata),
		.nvram_host_ready(nvram_host_ready),
		.nvram_cpu_write(nvram_cpu_write),
		.video_req(), .video_we(), .video_addr(), .video_wdata(), .video_be(),
		.video_ack(1'b0), .video_rdata(16'd0),
		.rom_req(), .rom_addr(), .rom_ack(1'b0), .rom_rdata(32'd0),
		.sound_command_valid(), .sound_command(), .watchdog_strobe(),
		.vint_ack_strobe(), .special_read_strobe(), .color0_strobe(),
		.color1_strobe(), .color_data(), .plane_enable(), .grom_bank(),
		.palette_video_addr(15'd0), .palette_video_rgb()
	);

	always #5 clk = ~clk;

	always @(posedge clk) begin
		if (cpu_ack)
			ack_count <= ack_count + 1;
		assert (!(cpu_ack && nvram_host_ready))
			else $fatal(1, "NVRAM_RACE_ACK_DURING_HOST_OWNERSHIP");
	end

	task automatic do_reset;
		@(negedge clk); reset = 1'b1;
		repeat (3) @(negedge clk);
		reset = 1'b0;
		repeat (2) @(negedge clk);
	endtask

	task automatic issue_cpu(input logic [23:0] address, input logic write_cycle,
		input logic [31:0] data);
		cpu_addr = address; cpu_we = write_cycle; cpu_wdata = data;
		cpu_be = 4'hf; cpu_req = 1'b1;
	endtask

	task automatic wait_cpu_ack(output logic [31:0] result);
		integer edges;
		edges = 0;
		while (!cpu_ack) begin
			@(posedge clk); #1;
			edges++;
			if (edges > 20) $fatal(1, "NVRAM_RACE_CPU_TIMEOUT addr=%06x", cpu_addr);
		end
		result = cpu_rdata;
		@(negedge clk);
		cpu_req = 1'b0; cpu_we = 1'b0; cpu_be = 4'h0;
		repeat (2) @(negedge clk);
	endtask

	task automatic cpu_access(input logic [23:0] address, input logic write_cycle,
		input logic [31:0] data, output logic [31:0] result);
		@(negedge clk);
		issue_cpu(address, write_cycle, data);
		@(posedge clk); #1;
		wait_cpu_ack(result);
	endtask

	// One WIDE=1 host read once the transfer owns the RAM ports.
	task automatic host_expect(input logic [16:0] address, input logic [15:0] expected);
		integer edges;
		nvram_host_addr = address;
		edges = 0;
		while (!nvram_host_ready) begin
			@(posedge clk); #1;
			edges++;
			if (edges > 8) $fatal(1, "NVRAM_RACE_READY_TIMEOUT");
		end
		repeat (2) @(posedge clk);
		#1;
		assert (nvram_host_rdata === expected)
			else $fatal(1, "NVRAM_RACE_HOST_READ addr=%05x got=%04x expected=%04x",
				address, nvram_host_rdata, expected);
		checks++;
		@(negedge clk);
	endtask

	task automatic end_upload;
		nvram_host_access = 1'b0;
		nvram_host_addr = 17'd0;
		@(negedge clk);
	endtask

	task automatic check(input string what, input logic [31:0] got,
		input logic [31:0] expected);
		assert (got === expected)
			else $fatal(1, "NVRAM_RACE %s: got %08x expected %08x", what, got, expected);
		checks++;
	endtask

	logic [31:0] r;
	initial begin
		#200000;
		$fatal(1, "NVRAM_RACE_GLOBAL_TIMEOUT");
	end

	initial begin
		// ---- BloodStorm/Time Killers: the backing store is live work RAM ----
		bloodstorm_mode = 1'b1;
		do_reset();
		cpu_access(24'h001000, 1'b1, 32'h1234_5678, r);
		cpu_access(24'h001004, 1'b1, 32'h0bad_f00d, r);

		// A read presented at, or a few clocks after, the upload start must
		// wait for the transfer and then return the CPU's own word.
		for (integer lag = 0; lag <= 2; lag++) begin
			@(negedge clk);
			nvram_host_access = 1'b1;
			nvram_host_addr = 17'd0;
			repeat (lag) @(negedge clk);
			issue_cpu(24'h001000, 1'b0, 32'd0);
			ack_before = ack_count;
			host_expect(17'h01000, 16'h3412);
			host_expect(17'h01002, 16'h7856);
			assert (ack_count == ack_before)
				else $fatal(1, "NVRAM_RACE_READ_SERVED_DURING_UPLOAD lag=%0d", lag);
			end_upload();
			wait_cpu_ack(r);
			check($sformatf("BS read after upload lag=%0d", lag), r, 32'h1234_5678);
		end

		// A read accepted one clock before the upload drains with CPU data.
		@(negedge clk);
		issue_cpu(24'h001004, 1'b0, 32'd0);
		@(posedge clk); #1;
		@(negedge clk);
		nvram_host_access = 1'b1;
		wait_cpu_ack(r);
		check("BS read accepted before upload", r, 32'h0bad_f00d);
		host_expect(17'h01004, 16'had0b);
		end_upload();

		// A write accepted one clock before the upload lands before the host
		// samples it.
		@(negedge clk);
		issue_cpu(24'h001008, 1'b1, 32'hcafe_babe);
		@(posedge clk); #1;
		@(negedge clk);
		nvram_host_access = 1'b1;
		wait_cpu_ack(r);
		host_expect(17'h01008, 16'hfeca);
		host_expect(17'h0100a, 16'hbeba);
		end_upload();

		// ---- SFTM: dedicated 128 KiB NVRAM at 0x600000 ----
		bloodstorm_mode = 1'b0;
		do_reset();
		cpu_access(24'h600000, 1'b1, 32'h1111_1111, r);
		cpu_access(24'h600100, 1'b1, 32'h2222_2222, r);

		// A write accepted one clock before the upload must reach its own
		// address, not the host's (address zero).
		@(negedge clk);
		issue_cpu(24'h600100, 1'b1, 32'hdead_beef);
		@(posedge clk); #1;
		@(negedge clk);
		nvram_host_access = 1'b1;
		nvram_host_addr = 17'd0;
		wait_cpu_ack(r);
		host_expect(17'h00100, 16'hadde);
		host_expect(17'h00000, 16'h1111);
		end_upload();
		cpu_access(24'h600100, 1'b0, 32'd0, r);
		check("SFTM straddling write target", r, 32'hdead_beef);
		cpu_access(24'h600000, 1'b0, 32'd0, r);
		check("SFTM host address untouched", r, 32'h1111_1111);

		// An NVRAM read accepted one clock before the upload returns CPU data.
		@(negedge clk);
		issue_cpu(24'h600100, 1'b0, 32'd0);
		@(posedge clk); #1;
		@(negedge clk);
		nvram_host_access = 1'b1;
		wait_cpu_ack(r);
		check("SFTM read accepted before upload", r, 32'hdead_beef);
		end_upload();

		// A write presented after the upload starts waits, then completes.
		@(negedge clk);
		nvram_host_access = 1'b1;
		nvram_host_addr = 17'd0;
		@(negedge clk);
		issue_cpu(24'h600200, 1'b1, 32'h3333_4444);
		ack_before = ack_count;
		host_expect(17'h00000, 16'h1111);
		assert (ack_count == ack_before)
			else $fatal(1, "NVRAM_RACE_WRITE_SERVED_DURING_UPLOAD");
		end_upload();
		wait_cpu_ack(r);
		cpu_access(24'h600200, 1'b0, 32'd0, r);
		check("SFTM write held across upload", r, 32'h3333_4444);
		cpu_access(24'h600000, 1'b0, 32'd0, r);
		check("SFTM host address still untouched", r, 32'h1111_1111);

		$display("NVRAM_UPLOAD_RACE_PASS checks=%0d", checks);
		$finish;
	end
endmodule
