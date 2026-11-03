`timescale 1ns/1ps
// Must Shoot TV's itech020 additions (MAME shoottv_map): gun registers at the
// first dword of each 2 KiB step from 0x190000 (X low byte, X bit 8, Y, zero;
// gun 2 at +0x2000; X = 0x1c + the aim column), interrupt clears on reads of
// 0x183000 (level 6) and 0x183800-0x188003 (level 5), the fixed security-PIC
// dword at 0x680000, and SFTM's colour-latch order. Literal values follow
// MAME. SFTM keeps these windows unmapped (zero, no strobes).
module itech32_shoottv_bus_tb;
	import itech32_profile_pkg::*;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic [7:0] selector = SELECT_SHOOTTV;
	logic cpu_req = 1'b0, cpu_we = 1'b0;
	logic [23:0] cpu_addr = '0;
	logic [31:0] cpu_wdata = '0;
	logic [3:0] cpu_be = '0;
	logic cpu_ack;
	logic [31:0] cpu_rdata;
	logic [16:0] lightgun1 = {8'd77, 9'd0};
	logic [16:0] lightgun2 = {8'd200, 9'd383};
	logic gun_ack5, gun_ack6, color0_strobe, color1_strobe;
	logic [7:0] color_data;
	integer ack5_count = 0, ack6_count = 0, color0_count = 0, color1_count = 0;
	integer checks = 0;

	/* verilator lint_off PINCONNECTEMPTY */
	itech32_main_bus dut (
		.clk(clk), .reset(reset), .profile(profile_for_selector(selector)),
		.rom_buffer_invalidate(1'b0),
		.cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
		.cpu_be(cpu_be), .cpu_ack(cpu_ack), .cpu_rdata(cpu_rdata),
		.input_p1(32'd0), .input_p2(32'd0), .input_p3(32'd0), .input_p4(32'hffff_ffff),
		.input_dips(32'd0), .input_extra(32'd0),
		.trackball1(16'h0000), .trackball2(16'h0000),
		.lightgun1(lightgun1), .lightgun2(lightgun2),
		.nvram_host_access(1'b0), .nvram_host_write(1'b0), .nvram_host_addr(18'd0),
		.nvram_host_wdata(16'd0), .nvram_host_rdata(), .nvram_host_ready(),
		.nvram_cpu_write(),
		.timekeeper_clock(64'd0), .timekeeper_write_enable(), .timekeeper_write_data(),
		.video_req(), .video_we(), .video_addr(), .video_wdata(), .video_be(),
		.video_ack(1'b0), .video_rdata(16'd0),
		.rom_req(), .rom_addr(), .rom_ack(1'b0), .rom_rdata(32'd0),
		.sound_command_valid(), .sound_command(), .watchdog_strobe(),
		.vint_ack_strobe(), .special_read_strobe(),
		.gun_ack5(gun_ack5), .gun_ack6(gun_ack6),
		.color0_strobe(color0_strobe), .color1_strobe(color1_strobe),
		.color_data(color_data), .plane_enable(), .grom_bank(),
		.palette_video_addr(15'd0), .palette_video_rgb()
	);
	/* verilator lint_on PINCONNECTEMPTY */

	always #5 clk = ~clk;

	always @(posedge clk) begin
		if (gun_ack5) ack5_count <= ack5_count + 1;
		if (gun_ack6) ack6_count <= ack6_count + 1;
		if (color0_strobe) color0_count <= color0_count + 1;
		if (color1_strobe) color1_count <= color1_count + 1;
	end

	initial begin
		#1000000;
		$fatal(1, "SHOOTTV_BUS_GLOBAL_TIMEOUT");
	end

	task automatic access(input string label, input logic [23:0] address,
		input logic write_cycle, input logic [31:0] data, input logic [3:0] be,
		input logic [31:0] expected);
		integer edges;
		begin
			@(negedge clk);
			cpu_addr = address; cpu_we = write_cycle; cpu_wdata = data;
			cpu_be = be; cpu_req = 1'b1;
			edges = 0;
			do begin
				@(posedge clk); #1;
				edges++;
				if (edges > 12) $fatal(1, "SHOOTTV_BUS_TIMEOUT %s", label);
			end while (!cpu_ack);
			if (!write_cycle && cpu_rdata !== expected)
				$fatal(1, "SHOOTTV_BUS_%s addr=%06x got=%08x expected=%08x",
					label, address, cpu_rdata, expected);
			@(negedge clk);
			cpu_req = 1'b0; cpu_we = 1'b0; cpu_be = 4'd0;
			repeat (2) @(negedge clk);
			checks++;
		end
	endtask

	task automatic read(input string label, input logic [23:0] address,
		input logic [31:0] expected);
		access(label, address, 1'b0, 32'd0, 4'hf, expected);
	endtask

	task automatic expect_counts(input string label, input integer a5, input integer a6);
		@(negedge clk);
		if (ack5_count != a5 || ack6_count != a6)
			$fatal(1, "SHOOTTV_BUS_ACKS_%s ack5=%0d ack6=%0d expected %0d %0d",
				label, ack5_count, ack6_count, a5, a6);
		checks++;
	endtask

	initial begin
		repeat (3) @(negedge clk);
		reset = 1'b0;
		// Gun 1 at column 0, line 77: X = 0x1c. Gun 2 at column 383, line 200:
		// X = 0x19b.
		read("GUN1_X", 24'h190000, 32'h001c_0000);
		read("GUN1_XHI", 24'h190800, 32'h0000_0000);
		read("GUN1_Y", 24'h191000, 32'h004d_0000);
		read("GUN1_ZERO", 24'h191800, 32'h0000_0000);
		read("GUN2_X", 24'h192000, 32'h009b_0000);
		read("GUN2_XHI", 24'h192800, 32'h0001_0000);
		read("GUN2_Y", 24'h193000, 32'h00c8_0000);
		read("GUN2_ZERO", 24'h193800, 32'h0000_0000);
		// Only the first dword of each step is a register.
		read("GUN_GAP", 24'h190004, 32'h0000_0000);
		lightgun1 = {8'd255, 9'd300};
		read("GUN1_X_MOVED", 24'h190000, 32'h0048_0000);   // 0x1c + 300 = 0x148
		read("GUN1_XHI_MOVED", 24'h190800, 32'h0001_0000);
		read("GUN1_Y_MOVED", 24'h191000, 32'h00ff_0000);
		expect_counts("NONE", 0, 0);
		// Interrupt clears.
		read("ACK6", 24'h183000, 32'h0000_0000);
		expect_counts("ACK6", 0, 1);
		read("ACK5_LOW", 24'h183800, 32'h0000_0000);
		read("ACK5_MID", 24'h185000, 32'h0000_0000);
		read("ACK5_HIGH", 24'h188000, 32'h0000_0000);
		expect_counts("ACK5", 3, 1);
		// Writes and the gap below 0x183800 do nothing.
		access("ACK_WRITE", 24'h183000, 1'b1, 32'd0, 4'hf, 32'd0);
		read("ACK_GAP", 24'h183400, 32'h0000_0000);
		expect_counts("NO_EXTRA", 3, 1);
		// P4 reads the inputs' all-ones value; the fixed PIC dword.
		read("P4", 24'h200000, 32'hffff_ffff);
		read("PIC", 24'h680000, 32'h0000_2000);
		// SFTM order: 0x300003 loads latch 0, 0x380003 latch 1.
		access("COLOR0", 24'h300000, 1'b1, 32'h0000_0011, 4'b0001, 32'd0);
		access("COLOR1", 24'h380000, 1'b1, 32'h0000_0022, 4'b0001, 32'd0);
		@(negedge clk);
		if (color0_count != 1 || color1_count != 1) $fatal(1, "SHOOTTV_BUS_COLOR");
		checks++;

		// SFTM: the windows stay unmapped.
		selector = SELECT_SFTM;
		read("SFTM_GUN", 24'h190000, 32'h0000_0000);
		read("SFTM_ACK", 24'h183000, 32'h0000_0000);
		expect_counts("SFTM", 3, 1);

		if (checks != 30) $fatal(1, "SHOOTTV_BUS_CASE_COUNT %0d", checks);
		$display("SHOOTTV_BUS_PASS checks=%0d", checks);
		$finish;
	end
endmodule
