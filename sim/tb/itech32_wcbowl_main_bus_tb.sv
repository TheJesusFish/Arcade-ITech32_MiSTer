`timescale 1ns/1ps

// ROM-free regression for the trackball boards' bus additions. 68000 World
// Class Bowling on the bloodstm map (MAME 0.288 init_wcbowl/init_wcbowlj):
// trackball ports at 0x680000 (and 0x680040 on v1.3J), the security PIC result
// word at 0x680080 (the work-RAM word at 0x111c), and the zero-reading 0x578000
// window. 68EC020 Shuffleshot/World Class Bowling on the itech020 map (MAME
// init_shuffle_bowl_common): trackball ports at 0x180800/0x181000 returning the
// byte in both halves, and the itech020 protection byte at 0x1116 or 0x111a.
// Literal addresses and values are written from MAME, not from the DUT
// decoder. BloodStorm and SFTM keep their responses at the same addresses.
module itech32_wcbowl_main_bus_tb;
    import itech32_profile_pkg::*;
    /* verilator lint_off PROCASSINIT */
    logic clk = 1'b0;
    /* verilator lint_on PROCASSINIT */
    logic reset = 1'b1;
    logic [7:0] selector = SELECT_WCBOWL;
    logic cpu_req = 1'b0;
    logic cpu_we = 1'b0;
    logic [23:0] cpu_addr = 24'd0;
    logic [31:0] cpu_wdata = 32'd0;
    logic [3:0] cpu_be = 4'd0;
    logic cpu_ack;
    logic [31:0] cpu_rdata;
    logic [7:0] trackball1 = 8'h00;
    logic [7:0] trackball2 = 8'h00;
    logic video_req, rom_req, sound_command_valid, watchdog_strobe;
    logic vint_ack_strobe, special_read_strobe, color0_strobe, color1_strobe;
    integer checks = 0;

    /* verilator lint_off PINCONNECTEMPTY */
    itech32_main_bus dut (
        .clk(clk), .reset(reset), .profile(profile_for_selector(selector)),
        .rom_buffer_invalidate(1'b0),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_be(cpu_be), .cpu_ack(cpu_ack), .cpu_rdata(cpu_rdata),
        .input_p1(32'd0), .input_p2(32'd0), .input_p3(32'd0), .input_p4(32'd0),
        .input_dips(32'd0), .input_extra(32'd0),
        .trackball1(trackball1), .trackball2(trackball2),
        .nvram_host_access(1'b0), .nvram_host_write(1'b0), .nvram_host_addr(17'd0),
        .nvram_host_wdata(16'd0), .nvram_host_rdata(), .nvram_host_ready(),
        .nvram_cpu_write(),
        .video_req(video_req), .video_we(), .video_addr(), .video_wdata(), .video_be(),
        .video_ack(1'b0), .video_rdata(16'd0),
        .rom_req(rom_req), .rom_addr(), .rom_ack(1'b0), .rom_rdata(32'd0),
        .sound_command_valid(sound_command_valid), .sound_command(),
        .watchdog_strobe(watchdog_strobe), .vint_ack_strobe(vint_ack_strobe),
        .special_read_strobe(special_read_strobe),
        .color0_strobe(color0_strobe), .color1_strobe(color1_strobe), .color_data(),
        .plane_enable(), .grom_bank(),
        .palette_video_addr(15'd0), .palette_video_rgb()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #5 clk = ~clk;

    initial begin
        #400000;
        $fatal(1, "WCBOWL_BUS_GLOBAL_TIMEOUT");
    end

    // expected_ack_edges: registered ports answer on the second edge, work-RAM
    // backed reads (the PIC result) on the third, like the itech020 protection.
    task automatic access(input string label, input logic [23:0] address,
        input logic write_cycle, input logic [31:0] write_data, input logic [3:0] byte_enable,
        input logic [31:0] expected_data, input logic [31:0] compare_mask,
        input integer expected_ack_edges);
        integer wait_edges;
        begin
            @(negedge clk); #1;
            if (cpu_req || cpu_ack) $fatal(1, "WCBOWL_BUS_UNDRAINED_START %s", label);
            cpu_addr = address; cpu_we = write_cycle; cpu_wdata = write_data;
            cpu_be = byte_enable; cpu_req = 1'b1;
            wait_edges = 0;
            do begin
                @(posedge clk); #1;
                wait_edges = wait_edges + 1;
                if (wait_edges > 16) $fatal(1, "WCBOWL_BUS_ACK_TIMEOUT %s", label);
            end while (!cpu_ack);
            if (wait_edges != expected_ack_edges)
                $fatal(1, "WCBOWL_BUS_ACK_SCHEDULE %s got=%0d expected=%0d",
                    label, wait_edges, expected_ack_edges);
            if ((cpu_rdata & compare_mask) !== (expected_data & compare_mask))
                $fatal(1, "WCBOWL_BUS_DATA %s got=%08x expected=%08x mask=%08x",
                    label, cpu_rdata, expected_data, compare_mask);
            @(posedge clk); #1;
            if (cpu_ack) $fatal(1, "WCBOWL_BUS_DUP_ACK %s", label);
            @(negedge clk); #1;
            cpu_req = 1'b0; cpu_we = 1'b0; cpu_be = 4'd0;
            repeat (2) @(posedge clk);
            checks++;
        end
    endtask

    task automatic select(input logic [7:0] value);
        begin
            @(negedge clk); #1;
            selector = value;
            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        #1;
        reset = 1'b0;
        repeat (2) @(negedge clk);

        // Work RAM 0x111c..0x111f = BE EF 12 34; the PIC result is the 68000
        // word at 0x111c, on either half of the 32-bit response.
        access("RAM_WRITE", 24'h00111c, 1'b1, 32'hbeef_1234, 4'hf, 32'd0, 32'd0, 2);
        access("PIC_WORD", 24'h680080, 1'b0, 32'd0, 4'hc, 32'hbeef_beef, 32'hffff_ffff, 3);
        access("PIC_LOW_BYTE", 24'h680081, 1'b0, 32'd0, 4'h4, 32'h00ef_0000, 32'h00ff_0000, 3);
        // MAME nop_writes the port: a write changes nothing.
        access("PIC_WRITE", 24'h680080, 1'b1, 32'h5555_5555, 4'hc, 32'd0, 32'd0, 2);
        access("PIC_AFTER_WRITE", 24'h680080, 1'b0, 32'd0, 4'hc, 32'hbeef_0000, 32'hffff_0000, 3);
        access("RAM_UNCHANGED", 24'h00111c, 1'b0, 32'd0, 4'hf, 32'hbeef_1234, 32'hffff_ffff, 2);

        // Trackball 1: (Y << 4) | X in the low byte of the 16-bit port.
        trackball1 = 8'h3a;
        access("TB1_WORD", 24'h680000, 1'b0, 32'd0, 4'hc, 32'h003a_0000, 32'hffff_0000, 2);
        access("TB1_BYTE", 24'h680001, 1'b0, 32'd0, 4'h4, 32'h003a_0000, 32'h00ff_0000, 2);
        trackball1 = 8'hc5;
        access("TB1_LIVE", 24'h680000, 1'b0, 32'd0, 4'hc, 32'h00c5_0000, 32'hffff_0000, 2);
        // v1.0-1.5 install no second trackball: 0x680040 stays open bus.
        trackball2 = 8'h77;
        access("TB2_ABSENT", 24'h680040, 1'b0, 32'd0, 4'hc, 32'hffff_0000, 32'hffff_0000, 2);
        access("ZERO_578000", 24'h578000, 1'b0, 32'd0, 4'hc, 32'h0000_0000, 32'hffff_0000, 2);
        access("ZERO_57FFFE", 24'h57fffe, 1'b0, 32'd0, 4'h3, 32'h0000_0000, 32'h0000_ffff, 2);

        // v1.3J reads the second trackball at 0x680040.
        select(SELECT_WCBOWL_J);
        access("J_TB1", 24'h680000, 1'b0, 32'd0, 4'hc, 32'h00c5_0000, 32'hffff_0000, 2);
        access("J_TB2", 24'h680040, 1'b0, 32'd0, 4'hc, 32'h0077_0000, 32'hffff_0000, 2);
        access("J_PIC", 24'h680080, 1'b0, 32'd0, 4'hc, 32'hbeef_0000, 32'hffff_0000, 3);

        // BloodStorm (and the boards sharing its row) keep the open bus.
        select(SELECT_BLOODSTORM);
        access("BS_TB1", 24'h680000, 1'b0, 32'd0, 4'hc, 32'hffff_0000, 32'hffff_0000, 2);
        access("BS_TB2", 24'h680040, 1'b0, 32'd0, 4'hc, 32'hffff_0000, 32'hffff_0000, 2);
        access("BS_PIC", 24'h680080, 1'b0, 32'd0, 4'hc, 32'hffff_0000, 32'hffff_0000, 2);
        access("BS_578000", 24'h578000, 1'b0, 32'd0, 4'hc, 32'hffff_0000, 32'hffff_0000, 2);

        // 68EC020 bowling: protection byte 0x1116 (bytes 0x1114..7 = 11 22 33 44)
        // on CPU lane +2, trackballs in both halves of their 32-bit ports.
        select(SELECT_WCBOWL_020);
        access("020_RAM_WRITE", 24'h001114, 1'b1, 32'h1122_3344, 4'hf, 32'd0, 32'd0, 2);
        access("020_PROTECTION", 24'h680002, 1'b0, 32'd0, 4'h2, 32'h0000_3300, 32'h0000_ff00, 3);
        trackball1 = 8'h5a; trackball2 = 8'h77;
        access("020_TB1", 24'h180800, 1'b0, 32'd0, 4'hf, 32'h005a_005a, 32'hffff_ffff, 2);
        access("020_TB1_HIGH", 24'h180802, 1'b0, 32'd0, 4'h3, 32'h005a_005a, 32'h0000_ffff, 2);
        access("020_TB2", 24'h181000, 1'b0, 32'd0, 4'hf, 32'h0077_0077, 32'hffff_ffff, 2);
        access("020_ZERO_578000", 24'h578000, 1'b0, 32'd0, 4'hf, 32'h0000_0000, 32'hffff_ffff, 2);
        // Shuffleshot and Deluxe read the protection byte at 0x111a.
        select(SELECT_SHUFSHOT);
        access("SHUF_RAM_WRITE", 24'h001118, 1'b1, 32'haabb_ccdd, 4'hf, 32'd0, 32'd0, 2);
        access("SHUF_PROTECTION", 24'h680002, 1'b0, 32'd0, 4'h2, 32'h0000_cc00, 32'h0000_ff00, 3);
        access("SHUF_TB2", 24'h181000, 1'b0, 32'd0, 4'hf, 32'h0077_0077, 32'hffff_ffff, 2);
        // SFTM has no trackball: the same address keeps its zero unmapped read.
        select(SELECT_SFTM);
        access("SFTM_TB1", 24'h180800, 1'b0, 32'd0, 4'hf, 32'h0000_0000, 32'hffff_ffff, 2);

        if (video_req || rom_req || sound_command_valid || watchdog_strobe ||
            vint_ack_strobe || special_read_strobe || color0_strobe || color1_strobe)
            $fatal(1, "WCBOWL_BUS_UNEXPECTED_SIDE_EFFECT");
        if (checks != 29) $fatal(1, "WCBOWL_BUS_CASE_COUNT %0d", checks);
        $display("WCBOWL_BUS_PASS checks=%0d", checks);
        $finish;
    end
endmodule
