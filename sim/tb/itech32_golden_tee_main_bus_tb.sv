`timescale 1ns/1ps

// ROM-free regression for the Golden Tee board profiles on the itech020 map
// (MAME 0.288 itech32.cpp init_gt_common and the board inits). Each board's
// trackball wiring: init_aama ports at 0x180800/0x181000, init_s_ver's single
// port at 0x200200, init_gt3dl's packed dword at 0x200000 and init_gt3d's
// 8-bit low word at 0x200000 (both replacing P4). The protection byte at
// 0x112f, the fixed protection dwords of init_gt2kp and init_gtclasscp, the
// base itech020_map colour latches (0x300003 -> latch 1, 0x380003 -> latch 0),
// two planes enabled at reset, and the GROM bank bits that MAME masks off for
// GROMs under 16 MiB, and the sound command: MAME's byte handler at 0x480001
// takes Golden Tee's word write at 0x480000 as well as SFTM's byte write.
// SFTM and Shuffleshot are checked at the same addresses.
// Literal addresses and values are written from MAME, not from the DUT decoder.
module itech32_golden_tee_main_bus_tb;
    import itech32_profile_pkg::*;
    /* verilator lint_off PROCASSINIT */
    logic clk = 1'b0;
    /* verilator lint_on PROCASSINIT */
    logic reset = 1'b1;
    logic [7:0] selector = SELECT_GT_AAMA;
    logic cpu_req = 1'b0;
    logic cpu_we = 1'b0;
    logic [23:0] cpu_addr = 24'd0;
    logic [31:0] cpu_wdata = 32'd0;
    logic [3:0] cpu_be = 4'd0;
    logic cpu_ack;
    logic [31:0] cpu_rdata;
    logic [15:0] trackball1 = 16'h0000;
    logic [15:0] trackball2 = 16'h0000;
    logic video_req, rom_req, sound_command_valid, watchdog_strobe;
    logic vint_ack_strobe, special_read_strobe, color0_strobe, color1_strobe;
    logic [7:0] color_data;
    logic [1:0] plane_enable, grom_bank;
    integer color0_count = 0, color1_count = 0, sound_count = 0;
    logic [7:0] sound_command, sound_last = 8'h00;
    logic [7:0] color0_last = 8'h00, color1_last = 8'h00;
    integer checks = 0;

    /* verilator lint_off PINCONNECTEMPTY */
    itech32_main_bus dut (
        .clk(clk), .reset(reset), .profile(profile_for_selector(selector)),
        .rom_buffer_invalidate(1'b0),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_be(cpu_be), .cpu_ack(cpu_ack), .cpu_rdata(cpu_rdata),
        .input_p1(32'd0), .input_p2(32'd0), .input_p3(32'd0), .input_p4(32'h00a5_0000),
        .input_dips(32'd0), .input_extra(32'd0),
        .trackball1(trackball1), .trackball2(trackball2), .lightgun1(17'd0), .lightgun2(17'd0),
        .nvram_host_access(1'b0), .nvram_host_write(1'b0), .nvram_host_addr(18'd0),
        .nvram_host_wdata(16'd0), .nvram_host_rdata(), .nvram_host_ready(),
        .nvram_cpu_write(), .timekeeper_clock(64'd0), .timekeeper_write_enable(), .timekeeper_write_data(),
        .video_req(video_req), .video_we(), .video_addr(), .video_wdata(), .video_be(),
        .video_ack(1'b0), .video_rdata(16'd0),
        .rom_req(rom_req), .rom_addr(), .rom_ack(1'b0), .rom_rdata(32'd0),
        .sound_command_valid(sound_command_valid), .sound_command(sound_command),
        .watchdog_strobe(watchdog_strobe), .vint_ack_strobe(vint_ack_strobe),
        .special_read_strobe(special_read_strobe),
        .gun_ack5(), .gun_ack6(), .color0_strobe(color0_strobe), .color1_strobe(color1_strobe), .color_data(color_data),
        .plane_enable(plane_enable), .grom_bank(grom_bank),
        .palette_video_addr(15'd0), .palette_video_rgb()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #5 clk = ~clk;

    initial begin
        #400000;
        $fatal(1, "GT_BUS_GLOBAL_TIMEOUT");
    end

    // color_data is held with the strobe; record which latch each write loads.
    always @(posedge clk) begin
        if (color0_strobe) begin color0_count <= color0_count + 1; color0_last <= color_data; end
        if (color1_strobe) begin color1_count <= color1_count + 1; color1_last <= color_data; end
        if (sound_command_valid) begin sound_count <= sound_count + 1; sound_last <= sound_command; end
    end

    task automatic expect_sound(input string label, input integer count, input logic [7:0] last);
        begin
            @(negedge clk);
            if (sound_count != count || (count != 0 && sound_last !== last))
                $fatal(1, "GT_BUS_SOUND_%s commands=%0d last=%02x expected %0d/%02x", label,
                    sound_count, sound_last, count, last);
            checks++;
        end
    endtask

    task automatic access(input string label, input logic [23:0] address,
        input logic write_cycle, input logic [31:0] write_data, input logic [3:0] byte_enable,
        input logic [31:0] expected_data, input logic [31:0] compare_mask,
        input integer expected_ack_edges);
        integer wait_edges;
        begin
            @(negedge clk); #1;
            if (cpu_req || cpu_ack) $fatal(1, "GT_BUS_UNDRAINED_START %s", label);
            cpu_addr = address; cpu_we = write_cycle; cpu_wdata = write_data;
            cpu_be = byte_enable; cpu_req = 1'b1;
            wait_edges = 0;
            do begin
                @(posedge clk); #1;
                wait_edges = wait_edges + 1;
                if (wait_edges > 16) $fatal(1, "GT_BUS_ACK_TIMEOUT %s", label);
            end while (!cpu_ack);
            if (wait_edges != expected_ack_edges)
                $fatal(1, "GT_BUS_ACK_SCHEDULE %s got=%0d expected=%0d",
                    label, wait_edges, expected_ack_edges);
            if ((cpu_rdata & compare_mask) !== (expected_data & compare_mask))
                $fatal(1, "GT_BUS_DATA %s got=%08x expected=%08x mask=%08x",
                    label, cpu_rdata, expected_data, compare_mask);
            @(posedge clk); #1;
            if (cpu_ack) $fatal(1, "GT_BUS_DUP_ACK %s", label);
            @(negedge clk); #1;
            cpu_req = 1'b0; cpu_we = 1'b0; cpu_be = 4'd0;
            repeat (2) @(posedge clk);
            checks++;
        end
    endtask

    task automatic read(input string label, input logic [23:0] address,
        input logic [31:0] expected_data, input logic [31:0] compare_mask);
        access(label, address, 1'b0, 32'd0, 4'hf, expected_data, compare_mask, 2);
    endtask

    task automatic write(input string label, input logic [23:0] address,
        input logic [31:0] data, input logic [3:0] byte_enable);
        access(label, address, 1'b1, data, byte_enable, 32'd0, 32'd0, 2);
    endtask

    // Selects a board and restarts the bus, as the core does after the MRA's
    // selector byte, so reset-time plane enables follow the profile.
    task automatic board(input logic [7:0] value);
        begin
            @(negedge clk); #1;
            selector = value; reset = 1'b1;
            repeat (2) @(negedge clk);
            #1; reset = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic expect_color(input string label, input integer count0, input logic [7:0] last0,
        input integer count1, input logic [7:0] last1);
        begin
            @(negedge clk);
            if (color0_count != count0 || color1_count != count1 ||
                (count0 != 0 && color0_last !== last0) || (count1 != 0 && color1_last !== last1))
                $fatal(1, "GT_BUS_COLOR_%s latch0=%0d/%02x latch1=%0d/%02x", label,
                    color0_count, color0_last, color1_count, color1_last);
            checks++;
        end
    endtask

    task automatic expect_planes(input string label, input logic [1:0] planes, input logic [1:0] bank);
        begin
            @(negedge clk);
            if (plane_enable !== planes || grom_bank !== bank)
                $fatal(1, "GT_BUS_PLANE_%s planes=%b bank=%0d expected %b/%0d", label,
                    plane_enable, grom_bank, planes, bank);
            checks++;
        end
    endtask

    initial begin
        board(SELECT_GT_AAMA);

        // init_gt_common: both planes enabled from reset (m_planes = 2).
        expect_planes("GT_RESET", 2'b11, 2'd0);
        // The protection byte is work RAM 0x112f (0x112c..f = 11 22 33 44),
        // presented on CPU lane +2.
        write("GT_RAM_WRITE", 24'h00112c, 32'h1122_3344, 4'hf);
        access("GT_PROTECTION", 24'h680002, 1'b0, 32'd0, 4'h2, 32'h0000_4400, 32'h0000_ff00, 3);
        // init_aama: both 4-bit ports, (Y << 4) | X in bytes 1 and 3.
        trackball1 = 16'hf3ea; trackball2 = 16'h8797;
        read("GT_TB1", 24'h180800, 32'h003a_003a, 32'hffff_ffff);
        read("GT_TB2", 24'h181000, 32'h0077_0077, 32'hffff_ffff);
        read("GT_P4", 24'h200000, 32'h00a5_0000, 32'hffff_ffff);
        read("GT_200200_UNMAPPED", 24'h200200, 32'h0000_0000, 32'hffff_ffff);
        // Without the alternate protection, 0x680000 keeps the all-ones range.
        read("GT_680000", 24'h680000, 32'hffff_ffff, 32'hffff_0000);
        // Base itech020_map: 0x300003 loads latch 1, 0x380003 latch 0.
        write("GT_COLOR_300003", 24'h300003, 32'h0000_0055, 4'h1);
        expect_color("GT_300003", 0, 8'h00, 1, 8'h55);
        write("GT_COLOR_380003", 24'h380003, 32'h0000_0066, 4'h1);
        expect_color("GT_380003", 1, 8'h66, 1, 8'h55);
        // Only byte +3 is a latch.
        write("GT_COLOR_300000", 24'h300000, 32'h7700_0000, 4'h8);
        expect_color("GT_300000", 1, 8'h66, 1, 8'h55);
        // Plane latch 0xc6: planes 1 and 2 enabled; bank bits 7:6 ignored
        // (6 MiB GROM, MAME grom_bank_mask 0).
        write("GT_PLANE", 24'h700002, 32'h0000_c600, 4'h2);
        expect_planes("GT_PLANE_C6", 2'b00, 2'd0);
        write("GT_PLANE_OFF", 24'h700002, 32'h0000_0600, 4'h2);
        expect_planes("GT_PLANE_06", 2'b00, 2'd0);
        write("GT_PLANE_ONE", 24'h700002, 32'h0000_0400, 4'h2);
        expect_planes("GT_PLANE_04", 2'b01, 2'd0);
        // Golden Tee's sound command: a word write at 0x480000 whose low byte
        // (0x480001, lane +1) is the command. A write to 0x480002/3 alone is not.
        write("GT_SOUND_WORD", 24'h480000, 32'h0042_0000, 4'hc);
        expect_sound("GT_WORD", 1, 8'h42);
        write("GT_SOUND_UPPER", 24'h480002, 32'h0000_7777, 4'h3);
        expect_sound("GT_UPPER", 1, 8'h42);
        write("GT_SOUND_EVEN", 24'h480000, 32'h9900_0000, 4'h8);
        expect_sound("GT_EVEN", 1, 8'h42);

        // init_gt2kp / init_gtclasscp: fixed dwords at 0x680000-0x680003; the
        // game tests the byte at 0x680002.
        board(SELECT_GT2K_P);
        read("GT2KP_DWORD", 24'h680000, 32'h0001_0000, 32'hffff_ffff);
        access("GT2KP_BYTE", 24'h680002, 1'b0, 32'd0, 4'h2, 32'h0000_0000, 32'h0000_ff00, 2);
        write("GT2KP_WRITE", 24'h680000, 32'hffff_ffff, 4'hf);
        read("GT2KP_AFTER_WRITE", 24'h680000, 32'h0001_0000, 32'hffff_ffff);
        read("GT2KP_TB1", 24'h180800, 32'h003a_003a, 32'hffff_ffff);
        board(SELECT_GTCLASSC_P);
        access("GTCLASSCP_BYTE", 24'h680002, 1'b0, 32'd0, 4'h2, 32'h0000_8000, 32'h0000_ff00, 2);
        read("GTCLASSCP_DWORD", 24'h680000, 32'h0000_8000, 32'hffff_ffff);

        // init_s_ver: one ball at 0x200200; 0x180800 and P4 as on SFTM.
        board(SELECT_GT_S);
        read("GTS_TB1", 24'h200200, 32'h003a_003a, 32'hffff_ffff);
        read("GTS_180800", 24'h180800, 32'h0000_0000, 32'hffff_ffff);
        read("GTS_181000", 24'h181000, 32'h0000_0000, 32'hffff_ffff);
        read("GTS_P4", 24'h200000, 32'h00a5_0000, 32'hffff_ffff);

        // init_gt3dl: player 1 in bytes +3/+1, player 2 in +2/+0 of 0x200000.
        board(SELECT_GT3D_LONG);
        read("GT3DL_TB", 24'h200000, 32'h773a_773a, 32'hffff_ffff);
        read("GT3DL_180800", 24'h180800, 32'h0000_0000, 32'hffff_ffff);
        read("GT3DL_200200", 24'h200200, 32'h0000_0000, 32'hffff_ffff);

        // init_gt3d: the 8-bit counters, (Y << 8) | X, in the low word.
        board(SELECT_GT3D_SHORT);
        read("GT3D_TB", 24'h200000, 32'h0000_f3ea, 32'hffff_ffff);
        trackball1 = 16'h7f80;
        read("GT3D_TB_LIVE", 24'h200000, 32'h0000_7f80, 32'hffff_ffff);
        read("GT3D_180800", 24'h180800, 32'h0000_0000, 32'hffff_ffff);
        expect_planes("GT3D_RESET", 2'b11, 2'd0);

        // SFTM keeps init_sftm_common's latches and its GROM bank bits, and
        // one plane at reset.
        board(SELECT_SFTM);
        expect_planes("SFTM_RESET", 2'b01, 2'd0);
        write("SFTM_COLOR_300003", 24'h300003, 32'h0000_0011, 4'h1);
        expect_color("SFTM_300003", 2, 8'h11, 1, 8'h55);
        write("SFTM_COLOR_380003", 24'h380003, 32'h0000_0022, 4'h1);
        expect_color("SFTM_380003", 2, 8'h11, 2, 8'h22);
        write("SFTM_PLANE", 24'h700002, 32'h0000_c600, 4'h2);
        expect_planes("SFTM_PLANE_C6", 2'b00, 2'd3);
        // SFTM writes the byte at 0x480001.
        write("SFTM_SOUND_BYTE", 24'h480001, 32'h0013_0000, 4'h4);
        expect_sound("SFTM_BYTE", 2, 8'h13);
        read("SFTM_200000", 24'h200000, 32'h00a5_0000, 32'hffff_ffff);
        read("SFTM_680000", 24'h680000, 32'hffff_ffff, 32'hffff_0000);
        // Shuffleshot's 8 MiB GROM has no bank bits either.
        board(SELECT_SHUFSHOT);
        write("SHUF_PLANE", 24'h700002, 32'h0000_8000, 4'h2);
        expect_planes("SHUF_PLANE_80", 2'b11, 2'd0);
        write("SHUF_COLOR_300003", 24'h300003, 32'h0000_0033, 4'h1);
        expect_color("SHUF_300003", 3, 8'h33, 2, 8'h22);

        if (video_req || rom_req || sound_command_valid || watchdog_strobe ||
            vint_ack_strobe || special_read_strobe)
            $fatal(1, "GT_BUS_UNEXPECTED_SIDE_EFFECT");
        if (checks != 59) $fatal(1, "GT_BUS_CASE_COUNT %0d", checks);
        $display("GT_BUS_PASS checks=%0d", checks);
        $finish;
    end
endmodule
