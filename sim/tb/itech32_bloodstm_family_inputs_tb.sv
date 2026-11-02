`timescale 1ns/1ps
// Hard Yardage, Pairs and World Class Bowling controller vectors on the
// bloodstm board (MAME 0.288 itech32.cpp itech32_base_16bit, hardyard, pairs and
// wcbowl input ports). Every MiSTer control of every player is pressed alone;
// all six ports are compared with an explicit table written from the MAME port
// definitions. Players 3/4 must not leak into any profile that does not wire
// them. The bowling trackball ports are driven end to end from mouse packets
// and sticks, including OSD ownership and boards without a trackball.
module itech32_bloodstm_family_inputs_tb;
    import itech32_profile_pkg::*;
    logic clk = 0, reset = 1;
    logic [11:0] joystick_0 = 0, joystick_1 = 0, joystick_2 = 0, joystick_3 = 0;
    logic service_button = 0, vblank = 0, sound_special = 0;
    logic [7:0] dip_switches = 0;
    logic [31:0] input_p1, input_p2, input_p3, input_p4, input_dips, input_extra;
    logic [15:0] analog_0 = 0, analog_1 = 0;
    logic [24:0] ps2_mouse = 0;
    logic mouse_ignore = 0;
    logic [1:0] trackball_speed = 2'd2;
    logic [7:0] trackball1, trackball2;
    logic [7:0] selector = SELECT_HARDYARD;
    board_profile_t profile;
    integer checks = 0;
    assign profile = profile_for_selector(selector);
    // A 16 kHz "clock" makes the trackball release tick every 10 cycles.
    itech32_inputs #(.CLK_HZ(16000)) dut (.*);
    always #5 clk = ~clk;

    function automatic logic [31:0] port(input logic [7:0] value);
        return {8'h00, value, 16'h0000};
    endfunction

    task automatic expected(input string label, input logic [7:0] p1, p2, p3, p4, extra, dips);
        if (input_p1 !== port(p1) || input_p2 !== port(p2) || input_p3 !== port(p3) ||
            input_p4 !== port(p4) || input_extra !== port(extra) || input_dips !== port(dips))
            $fatal(1, "FAMILY_INPUTS_%s p1=%08x p2=%08x p3=%08x p4=%08x extra=%08x dip=%08x",
                label, input_p1, input_p2, input_p3, input_p4, input_extra, input_dips);
        checks++;
    endtask

    // MAME player byte for one MiSTer control (0..3 R/L/D/U, 4.. B1.., 10 Start,
    // 11 Coin). Hard Yardage: B1/B2, no coin on players 3/4. Pairs: B1 only.
    function automatic logic [7:0] hardyard_byte(input integer player, input integer button);
        case (button)
            0:return 8'hef; 1:return 8'hdf; 2:return 8'hbf; 3:return 8'h7f;
            4:return 8'hfb; 5:return 8'hf7; 10:return 8'hfd;
            11:return player < 2 ? 8'hfe : 8'hff;
            default:return 8'hff;
        endcase
    endfunction
    function automatic logic [7:0] pairs_byte(input integer button);
        case (button)
            0:return 8'hef; 1:return 8'hdf; 2:return 8'hbf; 3:return 8'h7f;
            4:return 8'hfb; 10:return 8'hfd; 11:return 8'hfe;
            default:return 8'hff;
        endcase
    endfunction

    task automatic press(input integer player, input logic [11:0] value);
        case (player)
            0: joystick_0 = value; 1: joystick_1 = value;
            2: joystick_2 = value; default: joystick_3 = value;
        endcase
    endtask

    // MAME wcbowl P1/P2: Coin, Start, Hook Left (B1), Hook Right (B2).
    function automatic logic [7:0] wcbowl_byte(input integer button);
        case (button)
            4:return 8'hfb; 5:return 8'hf7; 10:return 8'hfd; 11:return 8'hfe;
            default:return 8'hff;
        endcase
    endfunction

    // One hps_io mouse packet: flags byte (bit 3 set, sign bits 4/5), X, Y.
    task automatic mouse_packet(input integer dx, input integer dy);
        @(negedge clk);
        ps2_mouse = {~ps2_mouse[24], 8'(dy), 8'(dx),
            2'b00, dy < 0, dx < 0, 1'b1, 3'b000};
    endtask

    task automatic trackball_check(input string label, input logic [7:0] tb1, input logic [7:0] tb2);
        if (trackball1 !== tb1 || trackball2 !== tb2)
            $fatal(1, "FAMILY_INPUTS_%s tb1=%02x tb2=%02x expected %02x %02x",
                label, trackball1, trackball2, tb1, tb2);
        checks++;
    endtask

    task automatic release_all();
        joystick_0 = 0; joystick_1 = 0; joystick_2 = 0; joystick_3 = 0;
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        @(posedge clk); #1;
        expected("HARDYARD_IDLE", 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'h07);
        for (integer player = 0; player < 4; player++) for (integer button = 0; button < 12; button++) begin
            @(negedge clk); #1; press(player, 12'(1 << button));
            #1; expected("HARDYARD_NO_LEAK", 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'h07);
            @(posedge clk); #1;
            expected("HARDYARD_PRESS",
                player == 0 ? hardyard_byte(0, button) : 8'hff,
                player == 1 ? hardyard_byte(1, button) : 8'hff,
                player == 2 ? hardyard_byte(2, button) : 8'hff,
                player == 3 ? hardyard_byte(3, button) : 8'hff, 8'hff, 8'h07);
            @(negedge clk); #1; release_all();
            @(posedge clk); #1;
            expected("HARDYARD_RELEASE", 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'h07);
        end
        @(negedge clk); #1;
        joystick_0 = 12'hfff; joystick_1 = 12'hfff; joystick_2 = 12'hfff; joystick_3 = 12'hfff;
        @(posedge clk); #1;
        expected("HARDYARD_ALL", 8'h00, 8'h00, 8'h01, 8'h01, 8'hff, 8'h07);
        for (integer sw = 0; sw < 16; sw++) begin
            dip_switches = 8'(sw); #1;
            expected("HARDYARD_DIP", 8'h00, 8'h00, 8'h01, 8'h01, 8'hff, {4'(sw), 4'h7});
        end
        dip_switches = 0; service_button = 1; vblank = 1; sound_special = 1; #1;
        expected("HARDYARD_SYSTEM", 8'h00, 8'h00, 8'h01, 8'h01, 8'hff, 8'h0a);
        service_button = 0; vblank = 0; sound_special = 0;

        @(negedge clk); #1; release_all(); selector = SELECT_PAIRS;
        @(posedge clk); #1;
        expected("PAIRS_IDLE", 8'hff, 8'hff, 8'h00, 8'hff, 8'hff, 8'h07);
        for (integer player = 0; player < 4; player++) for (integer button = 0; button < 12; button++) begin
            @(negedge clk); #1; press(player, 12'(1 << button));
            @(posedge clk); #1;
            expected("PAIRS_PRESS",
                player == 0 ? pairs_byte(button) : 8'hff,
                player == 1 ? pairs_byte(button) : 8'hff, 8'h00, 8'hff, 8'hff, 8'h07);
            @(negedge clk); #1; release_all();
        end
        @(negedge clk); #1;
        joystick_0 = 12'hfff; joystick_1 = 12'hfff; joystick_2 = 12'hfff; joystick_3 = 12'hfff;
        dip_switches = 8'h0a;
        @(posedge clk); #1;
        expected("PAIRS_ALL", 8'h08, 8'h08, 8'h00, 8'hff, 8'hff, 8'ha7);

        // Players 3/4 are not wired on the other boards.
        @(negedge clk); #1; release_all(); dip_switches = 0;
        joystick_2 = 12'hfff; joystick_3 = 12'hfff; selector = SELECT_BLOODSTORM;
        @(posedge clk); #1;
        expected("BLOODSTORM_P34", 8'hff, 8'hff, 8'h00, 8'hff, 8'hff, 8'h07);
        selector = SELECT_TIMEKILL; #1;
        if (input_p1 !== 32'hffff_0000 || input_p2 !== 32'hffff_0000 ||
            input_p3 !== 32'hffff_0000 || input_p4 !== 32'hffff_0000 || input_extra !== 0)
            $fatal(1, "FAMILY_INPUTS_TIMEKILL_P34 p1=%08x p2=%08x p3=%08x p4=%08x extra=%08x",
                input_p1, input_p2, input_p3, input_p4, input_extra);
        checks++;
        selector = SELECT_SFTM; #1;
        if (input_p1 !== 32'h00ff_0000 || input_p2 !== 32'h00ff_0000 ||
            input_p3 !== 32'h00ff_0000 || input_p4 !== 32'h00ff_0000 || input_extra !== 0)
            $fatal(1, "FAMILY_INPUTS_SFTM_P34 p1=%08x p2=%08x p3=%08x p4=%08x extra=%08x",
                input_p1, input_p2, input_p3, input_p4, input_extra);
        checks++;
        // World Class Bowling: Hook Left/Right on B1/B2; bits 4..7 unused (the
        // d-pad moves the trackball instead); P3 0x00, P4/EXTRA 0xff.
        @(negedge clk); #1; release_all(); selector = SELECT_WCBOWL;
        @(posedge clk); #1;
        expected("WCBOWL_IDLE", 8'hff, 8'hff, 8'h00, 8'hff, 8'hff, 8'h07);
        for (integer player = 0; player < 2; player++) for (integer button = 0; button < 12; button++) begin
            @(negedge clk); #1; press(player, 12'(1 << button));
            @(posedge clk); #1;
            expected("WCBOWL_PRESS",
                player == 0 ? wcbowl_byte(button) : 8'hff,
                player == 1 ? wcbowl_byte(button) : 8'hff, 8'h00, 8'hff, 8'hff, 8'h07);
            @(negedge clk); #1; release_all();
        end

        // Trackball ports, end to end. Restart from reset so the d-pad presses
        // above leave nothing pending.
        @(negedge clk); reset = 1; @(negedge clk); reset = 0;
        trackball_check("TB_RESET", 8'h00, 8'h00);
        // 100%: mouse right 2 and forward 1 -> X -2, Y -1, one count per tick.
        mouse_packet(2, 1);
        repeat (60) @(negedge clk);
        trackball_check("TB_MOUSE", 8'hfe, 8'h00);
        // OSD owns the mouse: the packet is dropped, not replayed later.
        mouse_ignore = 1; mouse_packet(-5, 0); repeat (60) @(negedge clk);
        mouse_ignore = 0; repeat (60) @(negedge clk);
        trackball_check("TB_IGNORED", 8'hfe, 8'h00);
        // v1.0-1.5 have one trackball: player 2's stick moves nothing.
        analog_1 = 16'h0040; repeat (60) @(negedge clk);
        trackball_check("TB2_ABSENT", 8'hfe, 8'h00);
        // v1.3J: player 2's stick right 64 is one count per tick, X falling.
        selector = SELECT_WCBOWL_J; repeat (45) @(negedge clk);
        if (trackball2[7:4] !== 4'h0 || trackball2[3:0] == 4'h0 || trackball1 !== 8'hfe)
            $fatal(1, "FAMILY_INPUTS_TB2_J tb1=%02x tb2=%02x", trackball1, trackball2);
        checks++;
        analog_1 = 0;
        // Boards without a trackball hold the counters and ignore the mouse.
        selector = SELECT_BLOODSTORM; @(negedge clk);
        mouse_packet(-3, -3); repeat (60) @(negedge clk);
        if (trackball1 !== 8'hfe) $fatal(1, "FAMILY_INPUTS_TB_DISABLED tb1=%02x", trackball1);
        checks++;

        if (checks != 247) $fatal(1, "FAMILY_INPUTS_CASE_COUNT %0d", checks);
        $display("FAMILY_INPUTS_PASS checks=%0d layouts=3", checks);
        $finish;
    end
endmodule
