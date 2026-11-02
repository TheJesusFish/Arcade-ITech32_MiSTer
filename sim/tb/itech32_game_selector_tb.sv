`timescale 1ns/1ps

module itech32_game_selector_tb;
	import itech32_profile_pkg::*;
	logic clk = 1'b0;
	logic write = 1'b0;
	logic [7:0] data = 8'd0;
	board_profile_t profile;

	itech32_game_selector dut (
		.clk(clk), .write(write), .data(data), .profile(profile)
	);

	always #5 clk = ~clk;

	// The registered profile follows the selector one clock later.
	task automatic select(input logic [7:0] value);
		@(negedge clk);
		data = value;
		write = 1'b1;
		@(negedge clk);
		write = 1'b0;
		@(negedge clk);
		#1;
	endtask

	task automatic expect_board(input string label, input logic [1:0] memory_map,
		input logic cpu_68000, input logic sound_rev1, input logic nvram_dedicated,
		input logic [6:0] grom_pages);
		assert (profile.memory_map == memory_map && profile.cpu_68000 == cpu_68000 &&
			profile.sound_rev1 == sound_rev1 &&
			profile.nvram_dedicated == nvram_dedicated &&
			profile.grom_pages == grom_pages)
			else $fatal(1, "SELECTOR_%s map=%0d cpu68k=%0b rev1=%0b nv=%0b pages=%0d",
				label, profile.memory_map, profile.cpu_68000, profile.sound_rev1,
				profile.nvram_dedicated, profile.grom_pages);
	endtask

	initial begin
		repeat (2) @(negedge clk);
		#1;
		expect_board("POWERUP", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd65);
		select(SELECT_TIMEKILL);
		expect_board("TIMEKILL", MAP_TIMEKILL, 1'b1, 1'b1, 1'b0, 7'd17);
		assert (profile.vram_two_planes && profile.nvram_workram_bytes == 17'h04000 &&
			profile.palette_format == PALETTE_TIMEKILL)
			else $fatal(1, "SELECTOR_TIMEKILL_FEATURES");
		select(SELECT_BLOODSTORM);
		expect_board("BLOODSTORM", MAP_BLOODSTORM, 1'b1, 1'b1, 1'b0, 7'd17);
		assert (!profile.vram_two_planes && profile.nvram_workram_bytes == 17'h10000 &&
			profile.palette_format == PALETTE_BLOODSTORM)
			else $fatal(1, "SELECTOR_BLOODSTORM_FEATURES");
		select(SELECT_HARDYARD);
		expect_board("HARDYARD", MAP_BLOODSTORM, 1'b1, 1'b1, 1'b0, 7'd17);
		assert (profile.input_layout == INPUTS_HARDYARD &&
			profile.palette_format == PALETTE_BLOODSTORM &&
			profile.nvram_workram_bytes == 17'h10000 && profile.sound_last_bank == 8'd5 &&
			profile.sample_slots == {SAMPLE_EMPTY, SAMPLE_SLOT_B, SAMPLE_EMPTY, SAMPLE_SLOT_A})
			else $fatal(1, "SELECTOR_HARDYARD_FEATURES");
		select(SELECT_PAIRS);
		expect_board("PAIRS", MAP_BLOODSTORM, 1'b1, 1'b1, 1'b0, 7'd17);
		assert (profile.input_layout == INPUTS_PAIRS &&
			profile.palette_format == PALETTE_BLOODSTORM &&
			profile.nvram_workram_bytes == 17'h10000 && profile.sound_last_bank == 8'd5 &&
			profile.sample_slots == {SAMPLE_EMPTY, SAMPLE_SLOT_B, SAMPLE_EMPTY, SAMPLE_SLOT_A})
			else $fatal(1, "SELECTOR_PAIRS_FEATURES");
		select(SELECT_BLOODSTORM);
		assert (profile.input_layout == INPUTS_BLOODSTORM)
			else $fatal(1, "SELECTOR_BLOODSTORM_INPUTS");
		select(8'h05);
		expect_board("SFTM_FALLBACK_05", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd65);
		select(8'hff);
		expect_board("FALLBACK", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd65);
		select(SELECT_SFTM);
		assert (profile.protection_address == 15'h7a6a &&
			profile.palette_format == PALETTE_DIRECT && profile.sound_last_bank == 8'd13)
			else $fatal(1, "SELECTOR_SFTM_FEATURES");
		$display("GAME_SELECTOR_PASS profiles=5 sftm_fallbacks=2");
		$finish;
	end
endmodule
