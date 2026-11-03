`timescale 1ns/1ps
// The tournament boards' M48T02 on the itech020 bus (MAME install_timekeeper:
// an 8-bit device on every byte lane at 0x681000-0x6817ff, so CPU address
// 0x681000 + n is chip offset n). Battery RAM through every byte lane, the
// clock bytes at 0x7f8-0x7ff from the timekeeper block (loaded from the MiSTer
// RTC, written by the CPU, ticking), dirty pulses, and the saved image: the
// 2 KiB follows the 128 KiB NVRAM at host offset 0x20000 in CPU byte order.
// The non-tournament Golden Tee board keeps the window unmapped (reads zero).
module itech32_timekeeper_bus_tb;
	import itech32_profile_pkg::*;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic [7:0] selector = SELECT_GT_AAMA_T;
	logic cpu_req = 1'b0;
	logic cpu_we = 1'b0;
	logic [23:0] cpu_addr = 24'd0;
	logic [31:0] cpu_wdata = 32'd0;
	logic [3:0] cpu_be = 4'd0;
	logic cpu_ack;
	logic [31:0] cpu_rdata;
	logic nvram_host_write = 1'b0;
	logic nvram_host_access = 1'b0;
	logic [17:0] nvram_host_addr = 18'd0;
	logic [15:0] nvram_host_wdata = 16'd0;
	logic [15:0] nvram_host_rdata;
	logic nvram_cpu_write;
	logic new_game = 1'b0;
	logic [64:0] rtc = '0;
	logic [63:0] timekeeper_clock;
	logic [7:0] timekeeper_write_enable;
	logic [63:0] timekeeper_write_data;
	integer checks = 0;

	/* verilator lint_off PINCONNECTEMPTY */
	itech32_main_bus dut (
		.clk(clk), .reset(reset), .profile(profile_for_selector(selector)),
		.rom_buffer_invalidate(1'b0),
		.cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata), .cpu_be(cpu_be), .cpu_ack(cpu_ack),
		.cpu_rdata(cpu_rdata), .input_p1(32'd0), .input_p2(32'd0),
		.input_p3(32'd0), .input_p4(32'd0), .input_dips(32'd0),
		.input_extra(32'd0), .trackball1(16'h0000), .trackball2(16'h0000), .lightgun1(17'd0), .lightgun2(17'd0),
		.nvram_host_access(nvram_host_access),
		.nvram_host_write(nvram_host_write), .nvram_host_addr(nvram_host_addr),
		.nvram_host_wdata(nvram_host_wdata), .nvram_host_rdata(nvram_host_rdata),
		.nvram_host_ready(), .nvram_cpu_write(nvram_cpu_write),
		.timekeeper_clock(timekeeper_clock),
		.timekeeper_write_enable(timekeeper_write_enable),
		.timekeeper_write_data(timekeeper_write_data),
		.video_req(), .video_we(), .video_addr(), .video_wdata(), .video_be(),
		.video_ack(1'b0), .video_rdata(16'd0),
		.rom_req(), .rom_addr(), .rom_ack(1'b0), .rom_rdata(32'd0),
		.sound_command_valid(), .sound_command(), .watchdog_strobe(),
		.vint_ack_strobe(), .special_read_strobe(),
		.gun_ack5(), .gun_ack6(), .color0_strobe(), .color1_strobe(), .color_data(), .plane_enable(),
		.grom_bank(), .palette_video_addr(15'd0), .palette_video_rgb()
	);
	/* verilator lint_on PINCONNECTEMPTY */

	// One thousand clocks per second.
	itech32_timekeeper #(.CLK_HZ(1000)) timekeeper (
		.clk(clk), .reset(1'b0), .new_game(new_game), .rtc(rtc),
		.write_enable(timekeeper_write_enable), .write_data(timekeeper_write_data),
		.read_data(timekeeper_clock)
	);

	always #5 clk = ~clk;

	initial begin
		#2000000;
		$fatal(1, "TIMEKEEPER_BUS_GLOBAL_TIMEOUT");
	end

	task automatic cpu_access(input string label, input logic [23:0] address,
		input logic write_cycle, input logic [31:0] data, input logic [3:0] be,
		input logic [31:0] expected, input logic [31:0] mask, input logic expect_dirty);
		integer edges;
		logic saw_dirty;
		begin
			@(negedge clk);
			cpu_addr = address; cpu_we = write_cycle; cpu_wdata = data;
			cpu_be = be; cpu_req = 1'b1;
			edges = 0;
			saw_dirty = 1'b0;
			do begin
				@(posedge clk); #1;
				edges++;
				saw_dirty |= nvram_cpu_write;
				if (edges > 12) $fatal(1, "TIMEKEEPER_BUS_TIMEOUT %s", label);
			end while (!cpu_ack);
			if (!write_cycle && (cpu_rdata & mask) !== (expected & mask))
				$fatal(1, "TIMEKEEPER_BUS_%s got=%08x expected=%08x mask=%08x",
					label, cpu_rdata, expected, mask);
			if (write_cycle && saw_dirty !== expect_dirty)
				$fatal(1, "TIMEKEEPER_BUS_DIRTY_%s saw=%0b", label, saw_dirty);
			@(negedge clk);
			cpu_req = 1'b0; cpu_we = 1'b0; cpu_be = 4'd0;
			repeat (2) @(negedge clk);
			checks++;
		end
	endtask

	task automatic cpu_write(input string label, input logic [23:0] address,
		input logic [31:0] data, input logic [3:0] be);
		cpu_access(label, address, 1'b1, data, be, 32'd0, 32'd0, 1'b1);
	endtask

	task automatic cpu_read(input string label, input logic [23:0] address,
		input logic [31:0] expected, input logic [31:0] mask);
		cpu_access(label, address, 1'b0, 32'd0, 4'hf, expected, mask, 1'b0);
	endtask

	task automatic host_write(input logic [17:0] address, input logic [15:0] data);
		@(negedge clk);
		nvram_host_access = 1'b1; nvram_host_addr = address;
		nvram_host_wdata = data; nvram_host_write = 1'b1;
		@(negedge clk);
		nvram_host_write = 1'b0; nvram_host_access = 1'b0;
	endtask

	task automatic host_expect(input string label, input logic [17:0] address,
		input logic [15:0] expected);
		@(negedge clk);
		nvram_host_access = 1'b1; nvram_host_addr = address;
		repeat (2) @(posedge clk);
		#1;
		if (nvram_host_rdata !== expected)
			$fatal(1, "TIMEKEEPER_HOST_%s addr=%05x got=%04x expected=%04x",
				label, address, nvram_host_rdata, expected);
		@(negedge clk);
		nvram_host_access = 1'b0;
		checks++;
	endtask

	initial begin
		// Tuesday 3 November 2026, 12:34:56 (MiSTer RTC: BCD, weekday 0-6).
		rtc = {1'b1, 8'h40, 8'd2, 8'h26, 8'h11, 8'h03, 8'h12, 8'h34, 8'h56};
		repeat (3) @(negedge clk);
		reset = 1'b0;
		@(negedge clk); new_game = 1'b1; @(negedge clk); new_game = 1'b0;

		// Battery RAM through every byte lane; offset n is CPU address 0x681000+n.
		cpu_write("RAM_DWORD", 24'h681000, 32'h1122_3344, 4'hf);
		cpu_read("RAM_DWORD", 24'h681000, 32'h1122_3344, 32'hffff_ffff);
		cpu_write("RAM_BYTE1", 24'h681005, 32'h00ab_0000, 4'b0100);
		cpu_write("RAM_BYTE3", 24'h681007, 32'h0000_00cd, 4'b0001);
		cpu_read("RAM_BYTES", 24'h681004, 32'h00ab_00cd, 32'h00ff_00ff);
		cpu_write("RAM_TOP", 24'h6817f4, 32'h5566_7788, 4'hf);
		cpu_read("RAM_TOP", 24'h6817f4, 32'h5566_7788, 32'hffff_ffff);

		// Clock bytes: control, seconds, minutes, hours | day, date, month, year.
		cpu_read("CLOCK_LOW", 24'h6817f8, 32'h0056_3412, 32'hffff_ffff);
		cpu_read("CLOCK_HIGH", 24'h6817fc, 32'h0303_1126, 32'hffff_ffff);
		// The game sets the time: W, then hours 09 and minutes 00 as bytes.
		cpu_write("CLOCK_W", 24'h6817f8, 32'h8000_0000, 4'b1000);
		cpu_write("CLOCK_HOURS", 24'h6817fb, 32'h0000_0009, 4'b0001);
		cpu_write("CLOCK_MINUTES", 24'h6817fa, 32'h0000_0000, 4'b0010);
		cpu_read("CLOCK_HELD", 24'h6817f8, 32'h8056_0009, 32'hffff_ffff);
		cpu_write("CLOCK_RUN", 24'h6817f8, 32'h0000_0000, 4'b1000);
		// Through the next one-second strobe.
		@(posedge clk iff timekeeper.second);
		repeat (2) @(negedge clk);
		cpu_read("CLOCK_TICKED", 24'h6817f8, 32'h0057_0009, 32'hffff_ffff);
		// A dword write over the high clock bytes reaches all four.
		cpu_write("CLOCK_W2", 24'h6817f8, 32'h8000_0000, 4'b1000);
		cpu_write("CLOCK_DATE", 24'h6817fc, 32'h0415_0727, 4'hf);
		cpu_write("CLOCK_RUN2", 24'h6817f8, 32'h0000_0000, 4'b1000);
		cpu_read("CLOCK_DATE", 24'h6817fc, 32'h0415_0727, 32'hffff_ffff);

		// The saved image: 128 KiB NVRAM, then the timekeeper in CPU byte order.
		host_expect("IMAGE_0", 18'h20000, 16'h2211);
		host_expect("IMAGE_2", 18'h20002, 16'h4433);
		host_expect("IMAGE_TOP", 18'h207f6, 16'h8877);
		host_write(18'h20010, 16'hbeef);
		host_write(18'h20012, 16'h0102);
		cpu_read("IMAGE_RESTORED", 24'h681010, 32'hefbe_0201, 32'hffff_ffff);
		// The NVRAM below 0x20000 is separate.
		host_write(18'h00010, 16'hcafe);
		cpu_read("NVRAM_SEPARATE", 24'h600010, 32'hfeca_0000, 32'hffff_0000);
		cpu_read("TIMEKEEPER_UNTOUCHED", 24'h681010, 32'hefbe_0201, 32'hffff_ffff);

		// The non-tournament board leaves the window unmapped: zero reads, no
		// RAM write, no dirty pulse.
		selector = SELECT_GT_AAMA;
		cpu_access("PLAIN_WRITE", 24'h681000, 1'b1, 32'hdead_beef, 4'hf, 32'd0, 32'd0, 1'b0);
		cpu_read("PLAIN_READ", 24'h681000, 32'h0000_0000, 32'hffff_ffff);
		cpu_read("PLAIN_CLOCK", 24'h6817f8, 32'h0000_0000, 32'hffff_ffff);
		selector = SELECT_GT_AAMA_T;
		cpu_read("RAM_KEPT", 24'h681000, 32'h1122_3344, 32'hffff_ffff);

		if (checks != 29) $fatal(1, "TIMEKEEPER_BUS_CASE_COUNT %0d", checks);
		$display("TIMEKEEPER_BUS_PASS checks=%0d", checks);
		$finish;
	end
endmodule
