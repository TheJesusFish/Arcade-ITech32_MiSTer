`timescale 1ns/1ps

module itech32_nvram_memory_tb;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic timekill_mode = 1'b0;
	logic bloodstorm_mode = 1'b0;
	logic cpu_req = 1'b0;
	logic cpu_we = 1'b0;
	logic [23:0] cpu_addr = 24'd0;
	logic [31:0] cpu_wdata = 32'd0;
	logic [3:0] cpu_be = 4'd0;
	logic cpu_ack;
	logic [31:0] cpu_rdata;
	logic nvram_host_write = 1'b0;
	logic nvram_host_access = 1'b0;
	logic [16:0] nvram_host_addr = 17'd0;
	logic [15:0] nvram_host_wdata = 16'd0;
	logic [15:0] nvram_host_rdata;
	logic nvram_cpu_write;

	/* verilator lint_off PINCONNECTEMPTY */
	itech32_main_bus dut (
		.clk(clk), .reset(reset), .timekill_mode(timekill_mode),
		.bloodstorm_mode(bloodstorm_mode), .rom_buffer_invalidate(1'b0),
		.cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata), .cpu_be(cpu_be), .cpu_ack(cpu_ack),
		.cpu_rdata(cpu_rdata), .input_p1(32'd0), .input_p2(32'd0),
		.input_p3(32'd0), .input_p4(32'd0), .input_dips(32'd0),
		.input_extra(32'd0), .protection_address(15'h7a6a),
		.nvram_host_access(nvram_host_access),
		.nvram_host_write(nvram_host_write), .nvram_host_addr(nvram_host_addr),
		.nvram_host_wdata(nvram_host_wdata), .nvram_host_rdata(nvram_host_rdata),
		.nvram_cpu_write(nvram_cpu_write), .video_req(), .video_we(),
		.video_addr(), .video_wdata(), .video_be(), .video_ack(1'b0),
		.video_rdata(16'd0), .rom_req(), .rom_addr(), .rom_ack(1'b0),
		.rom_rdata(32'd0), .sound_command_valid(), .sound_command(),
		.watchdog_strobe(), .vint_ack_strobe(), .special_read_strobe(),
		.color0_strobe(), .color1_strobe(), .color_data(), .plane_enable(),
		.grom_bank(), .palette_video_addr(15'd0), .palette_video_rgb()
	);
	/* verilator lint_on PINCONNECTEMPTY */

	always #5 clk = ~clk;

	task automatic pulse_reset;
		@(negedge clk); reset = 1'b1;
		repeat (2) @(negedge clk);
		reset = 1'b0;
		repeat (2) @(negedge clk);
	endtask

	task automatic host_write(input logic [16:0] address,
		input logic [15:0] data);
		@(negedge clk);
		nvram_host_access = 1'b1;
		nvram_host_addr = address;
		nvram_host_wdata = data;
		nvram_host_write = 1'b1;
		@(negedge clk);
		nvram_host_write = 1'b0;
		nvram_host_access = 1'b0;
	endtask

	task automatic host_expect(input logic [16:0] address,
		input logic [15:0] expected);
		@(negedge clk);
		nvram_host_access = 1'b1;
		nvram_host_addr = address;
		repeat (2) @(posedge clk);
		#1;
		assert (nvram_host_rdata === expected) else
			$fatal(1, "NVRAM_HOST_READ addr=%05x got=%04x expected=%04x",
				address, nvram_host_rdata, expected);
		@(negedge clk);
		nvram_host_access = 1'b0;
	endtask

	task automatic cpu_access(input logic [23:0] address,
		input logic write_cycle, input logic [31:0] data,
		input logic [31:0] expected);
		integer edges;
		logic saw_nvram_write;
		begin
			@(negedge clk);
			cpu_addr = address;
			cpu_we = write_cycle;
			cpu_wdata = data;
			cpu_be = 4'hf;
			cpu_req = 1'b1;
			edges = 0;
			saw_nvram_write = 1'b0;
			do begin
				@(posedge clk); #1;
				edges = edges + 1;
				saw_nvram_write |= nvram_cpu_write;
				if (edges > 12) $fatal(1, "NVRAM_CPU_TIMEOUT addr=%06x", address);
			end while (!cpu_ack);
			if (!write_cycle)
				assert (cpu_rdata === expected) else
					$fatal(1, "NVRAM_CPU_READ addr=%06x got=%08x expected=%08x",
						address, cpu_rdata, expected);
			else
				assert (saw_nvram_write) else $fatal(1, "NVRAM_CPU_DIRTY_PULSE");
			@(negedge clk);
			cpu_req = 1'b0;
			cpu_we = 1'b0;
			cpu_be = 4'd0;
			repeat (2) @(negedge clk);
		end
	endtask

	task automatic test_profile(input logic tk, input logic blood,
		input logic [23:0] cpu_base);
		begin
			timekill_mode = tk;
			bloodstorm_mode = blood;
			pulse_reset();
			host_write(17'h00000, 16'h2211);
			host_write(17'h00002, 16'h4433);
			cpu_access(cpu_base, 1'b0, 32'd0, 32'h1122_3344);
			cpu_access(cpu_base + 24'd4, 1'b1, 32'ha1b2_c3d4, 32'd0);
			host_expect(17'h00004, 16'hb2a1);
			host_expect(17'h00006, 16'hd4c3);
		end
	endtask

	initial begin
		#200000;
		$fatal(1, "NVRAM_MEMORY_GLOBAL_TIMEOUT");
	end

	initial begin
		test_profile(1'b0, 1'b0, 24'h600000);
		test_profile(1'b1, 1'b0, 24'h000000);
		test_profile(1'b0, 1'b1, 24'h000000);

		// Time Killers' backing store stops at 16 KiB even though BloodStorm
		// shares the same physical 64 KiB work-RAM implementation.
		timekill_mode = 1'b1;
		bloodstorm_mode = 1'b0;
		nvram_host_addr = 17'h04000;
		nvram_host_access = 1'b1;
		repeat (2) @(posedge clk);
		#1;
		assert (nvram_host_rdata == 16'd0) else $fatal(1, "NVRAM_TIMEKILL_BOUND");

		$display("NVRAM_MEMORY_PASS profiles=3 byte_order=big_endian bounds=ok");
		$finish;
	end
endmodule
