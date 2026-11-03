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
		assert (profile.vram_two_planes && profile.vram_512_rows &&
			profile.nvram_workram_bytes == 17'h04000 &&
			profile.palette_format == PALETTE_TIMEKILL && !profile.grom_banked)
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
		assert (profile.input_layout == INPUTS_BLOODSTORM &&
			profile.trackball == TRACKBALL_NONE && !profile.pic_result_read &&
			!profile.zero_578000)
			else $fatal(1, "SELECTOR_BLOODSTORM_INPUTS");
		// MAME init_wcbowl: bloodstm board plus trackball, PIC word at RAM
		// 0x111c, and the zero-reading 0x578000 window; v1.3J adds trackball 2.
		select(SELECT_WCBOWL);
		expect_board("WCBOWL", MAP_BLOODSTORM, 1'b1, 1'b1, 1'b0, 7'd17);
		assert (profile.input_layout == INPUTS_WCBOWL &&
			profile.trackball == TRACKBALL_ONE && profile.pic_result_read &&
			profile.protection_address == 15'h111c && profile.zero_578000 &&
			profile.nvram_workram_bytes == 17'h10000 &&
			profile.palette_format == PALETTE_BLOODSTORM &&
			profile.sample_slots == {SAMPLE_EMPTY, SAMPLE_SLOT_B, SAMPLE_EMPTY, SAMPLE_SLOT_A})
			else $fatal(1, "SELECTOR_WCBOWL_FEATURES");
		select(SELECT_WCBOWL_J);
		expect_board("WCBOWL_J", MAP_BLOODSTORM, 1'b1, 1'b1, 1'b0, 7'd17);
		assert (profile.input_layout == INPUTS_WCBOWL &&
			profile.trackball == TRACKBALL_TWO && profile.pic_result_read &&
			profile.protection_address == 15'h111c && profile.zero_578000)
			else $fatal(1, "SELECTOR_WCBOWL_J_FEATURES");
		select(SELECT_TIMEKILL);
		assert (!profile.zero_578000 && profile.trackball == TRACKBALL_NONE)
			else $fatal(1, "SELECTOR_TIMEKILL_WINDOW");
		// MAME sftm machine + init_shuffle_bowl_common: the SFTM board with two
		// trackballs, a six-bank sound ROM, samples in banks 0/1, and the
		// itech020 protection byte at 0x1116 (init_wcbowln) or 0x111a.
		select(SELECT_WCBOWL_020);
		expect_board("WCBOWL_020", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd17);
		assert (profile.input_layout == INPUTS_SHUFFLE_BOWL &&
			profile.trackball == TRACKBALL_TWO && profile.protection_address == 15'h1116 &&
			profile.sound_last_bank == 8'd5 && profile.zero_578000 &&
			!profile.pic_result_read && profile.palette_format == PALETTE_DIRECT &&
			profile.sample_slots == {SAMPLE_EMPTY, SAMPLE_EMPTY, SAMPLE_SLOT_B, SAMPLE_SLOT_A})
			else $fatal(1, "SELECTOR_WCBOWL_020_FEATURES");
		select(SELECT_WCBOWL_DX);
		expect_board("WCBOWL_DX", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd17);
		assert (profile.input_layout == INPUTS_SHUFFLE_BOWL &&
			profile.trackball == TRACKBALL_TWO && profile.protection_address == 15'h111a)
			else $fatal(1, "SELECTOR_WCBOWL_DX_FEATURES");
		select(SELECT_SHUFSHOT);
		expect_board("SHUFSHOT", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd16);
		assert (profile.input_layout == INPUTS_SHUFFLE_BOWL &&
			profile.trackball == TRACKBALL_TWO && profile.protection_address == 15'h111a &&
			profile.sound_last_bank == 8'd5 &&
			profile.trackball_port == TRACKBALL_AT_180800 &&
			profile.trackball_rate == TRACKBALL_RATE_1600 &&
			!profile.vram_two_planes && !profile.color_latch_swap && !profile.grom_banked &&
			!profile.blitter_status_live)
			else $fatal(1, "SELECTOR_SHUFSHOT_FEATURES");
		// MAME sftm machine + init_gt_common: two 1024-row planes, the base map's
		// colour latches, the protection byte at 0x112f and a 12-page GROM.
		for (int gt = 0; gt < 6; gt++) begin
			select(SELECT_GT_AAMA + 8'(gt));
			expect_board("GOLDEN_TEE", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd12);
			assert (profile.input_layout == INPUTS_GOLDEN_TEE &&
				profile.vram_two_planes && !profile.vram_512_rows &&
				profile.color_latch_swap && !profile.grom_banked &&
				profile.protection_address == 15'h112f && profile.zero_578000 &&
				profile.sound_last_bank == 8'd5 && !profile.pic_result_read &&
				profile.palette_format == PALETTE_DIRECT && profile.nvram_dedicated &&
				profile.blitter_status_live)
				else $fatal(1, "SELECTOR_GOLDEN_TEE_COMMON %0d", gt);
		end
		// init_aama: two balls at 0x180800/0x181000, samples in bank 0 only.
		select(SELECT_GT_AAMA);
		assert (profile.trackball == TRACKBALL_TWO &&
			profile.trackball_port == TRACKBALL_AT_180800 &&
			profile.trackball_rate == TRACKBALL_RATE_3600 && !profile.protection_fixed &&
			profile.sample_slots == {SAMPLE_EMPTY, SAMPLE_EMPTY, SAMPLE_EMPTY, SAMPLE_SLOT_A})
			else $fatal(1, "SELECTOR_GT_AAMA_FEATURES");
		select(SELECT_GT2K_P);
		assert (profile.trackball_port == TRACKBALL_AT_180800 && profile.protection_fixed &&
			profile.protection_fixed_data == 32'h0001_0000 &&
			profile.sample_slots == {SAMPLE_EMPTY, SAMPLE_EMPTY, SAMPLE_EMPTY, SAMPLE_SLOT_A})
			else $fatal(1, "SELECTOR_GT2K_P_FEATURES");
		select(SELECT_GTCLASSC_P);
		assert (profile.trackball_port == TRACKBALL_AT_180800 && profile.protection_fixed &&
			profile.protection_fixed_data == 32'h0000_8000)
			else $fatal(1, "SELECTOR_GTCLASSC_P_FEATURES");
		// init_s_ver: one ball at 0x200200, samples in bank 2.
		select(SELECT_GT_S);
		assert (profile.trackball == TRACKBALL_ONE &&
			profile.trackball_port == TRACKBALL_AT_200200 &&
			profile.trackball_rate == TRACKBALL_RATE_3600 && !profile.protection_fixed &&
			profile.sample_slots == {SAMPLE_EMPTY, SAMPLE_SLOT_A, SAMPLE_EMPTY, SAMPLE_EMPTY})
			else $fatal(1, "SELECTOR_GT_S_FEATURES");
		// init_gt3d / init_gt3dl: samples in banks 0, 2 and 3.
		select(SELECT_GT3D_SHORT);
		assert (profile.trackball == TRACKBALL_ONE && profile.trackball_port == TRACKBALL_WIDE &&
			profile.trackball_rate == TRACKBALL_RATE_2200 &&
			profile.sample_slots == {SAMPLE_SLOT_C, SAMPLE_SLOT_B, SAMPLE_EMPTY, SAMPLE_SLOT_A})
			else $fatal(1, "SELECTOR_GT3D_SHORT_FEATURES");
		select(SELECT_GT3D_LONG);
		assert (profile.trackball == TRACKBALL_TWO &&
			profile.trackball_port == TRACKBALL_AT_200000 &&
			profile.trackball_rate == TRACKBALL_RATE_1600 &&
			profile.sample_slots == {SAMPLE_SLOT_C, SAMPLE_SLOT_B, SAMPLE_EMPTY, SAMPLE_SLOT_A})
			else $fatal(1, "SELECTOR_GT3D_LONG_FEATURES");
		// MAME pubball: the SFTM board with two 1024-row planes, a 14 MiB
		// GROM, two trackballs at 0x180800 and samples in banks 0 and 1.
		select(SELECT_PUBBALL);
		expect_board("PUBBALL", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd28);
		assert (profile.input_layout == INPUTS_PUBBALL &&
			profile.vram_two_planes && !profile.vram_512_rows && !profile.color_latch_swap &&
			!profile.grom_banked && profile.protection_address == 15'h0000 &&
			!profile.protection_fixed && !profile.pic_result_read &&
			profile.trackball == TRACKBALL_TWO &&
			profile.trackball_port == TRACKBALL_AT_180800 &&
			profile.trackball_rate == TRACKBALL_RATE_1600 && profile.sound_last_bank == 8'd5 &&
			profile.zero_578000 && !profile.blitter_status_live &&
			profile.palette_format == PALETTE_DIRECT &&
			profile.sample_slots == {SAMPLE_EMPTY, SAMPLE_EMPTY, SAMPLE_SLOT_B, SAMPLE_SLOT_A})
			else $fatal(1, "SELECTOR_PUBBALL_FEATURES");
		// Tournament editions: init_aamat and init_wcbowlt add the M48T02
		// timekeeper to the single Golden Tee board and the Deluxe bowling row.
		select(SELECT_GT_AAMA_T);
		expect_board("GT_AAMA_T", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd12);
		assert (profile.timekeeper && profile.input_layout == INPUTS_GOLDEN_TEE &&
			profile.trackball == TRACKBALL_TWO &&
			profile.trackball_port == TRACKBALL_AT_180800 &&
			profile.trackball_rate == TRACKBALL_RATE_3600 && !profile.protection_fixed &&
			profile.protection_address == 15'h112f && profile.color_latch_swap &&
			profile.blitter_status_live &&
			profile.sample_slots == {SAMPLE_EMPTY, SAMPLE_EMPTY, SAMPLE_EMPTY, SAMPLE_SLOT_A})
			else $fatal(1, "SELECTOR_GT_AAMA_T_FEATURES");
		select(SELECT_WCBOWL_T);
		expect_board("WCBOWL_T", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd17);
		assert (profile.timekeeper && profile.input_layout == INPUTS_SHUFFLE_BOWL &&
			profile.trackball == TRACKBALL_TWO && profile.protection_address == 15'h111a &&
			profile.sound_last_bank == 8'd5 &&
			profile.sample_slots == {SAMPLE_EMPTY, SAMPLE_EMPTY, SAMPLE_SLOT_B, SAMPLE_SLOT_A})
			else $fatal(1, "SELECTOR_WCBOWL_T_FEATURES");
		// MAME shoottv: the SFTM board with two 1024-row planes, the fixed
		// security-PIC dword, a 17-page GROM, samples in bank 0, and light
		// guns whose interrupts replace VINT.
		select(SELECT_SHOOTTV);
		expect_board("SHOOTTV", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd17);
		assert (profile.input_layout == INPUTS_SHOOTTV && profile.lightgun &&
			profile.vint_disabled && profile.vram_two_planes && !profile.vram_512_rows &&
			!profile.color_latch_swap && !profile.grom_banked &&
			profile.protection_fixed && profile.protection_fixed_data == 32'h0000_2000 &&
			profile.trackball == TRACKBALL_NONE && profile.sound_last_bank == 8'd5 &&
			!profile.timekeeper && !profile.blitter_status_live &&
			profile.sample_slots == {SAMPLE_EMPTY, SAMPLE_EMPTY, SAMPLE_EMPTY, SAMPLE_SLOT_A})
			else $fatal(1, "SELECTOR_SHOOTTV_FEATURES");
		// Only the tournament selectors have the timekeeper, and only Must
		// Shoot TV the light guns.
		for (int s = 0; s < 20; s++) begin
			select(8'(s));
			assert (profile.timekeeper == (s == 8'h11 || s == 8'h12) &&
				profile.lightgun == (s == 8'h13) && profile.vint_disabled == (s == 8'h13))
				else $fatal(1, "SELECTOR_FEATURE_ONLY %0d", s);
		end
		select(8'h40);
		expect_board("SFTM_FALLBACK_40", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd65);
		select(8'h80);
		expect_board("SFTM_FALLBACK_80", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd65);
		select(8'hff);
		expect_board("FALLBACK", MAP_ITECH020, 1'b0, 1'b0, 1'b1, 7'd65);
		select(SELECT_SFTM);
		assert (profile.protection_address == 15'h7a6a &&
			profile.palette_format == PALETTE_DIRECT && profile.sound_last_bank == 8'd13 &&
			profile.zero_578000 && profile.trackball == TRACKBALL_NONE &&
			profile.grom_banked && !profile.color_latch_swap && !profile.vram_two_planes &&
			!profile.vram_512_rows && !profile.protection_fixed && !profile.blitter_status_live)
			else $fatal(1, "SELECTOR_SFTM_FEATURES");
		$display("GAME_SELECTOR_PASS profiles=20 sftm_fallbacks=3");
		$finish;
	end
endmodule
