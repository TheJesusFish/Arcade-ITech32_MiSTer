`timescale 1ns/1ps
// Hard Yardage, Pairs and World Class Bowling controller vectors on the
// bloodstm board (MAME 0.288 itech32.cpp itech32_base_16bit, hardyard, pairs and
// wcbowl input ports). Every MiSTer control of every player is pressed alone;
// all six ports are compared with an explicit table written from the MAME port
// definitions. Players 3/4 must not leak into any profile that does not wire
// them. The bowling trackball ports are driven end to end from mouse packets
// and sticks, including OSD ownership and boards without a trackball. Golden
// Tee adds volume buttons and per-board count release rates; Power Up
// Baseball three more bases buttons per player.
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
    logic [15:0] trackball1, trackball2, tb2_before;
    logic lightgun_absolute = 1'b0;
    logic [16:0] lightgun1, lightgun2;
    logic lightgun2_active;
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

    // Counters are {Y, X}, eight bits each.
    task automatic trackball_check(input string label, input logic [15:0] tb1, input logic [15:0] tb2);
        if (trackball1 !== tb1 || trackball2 !== tb2)
            $fatal(1, "FAMILY_INPUTS_%s tb1=%04x tb2=%04x expected %04x %04x",
                label, trackball1, trackball2, tb1, tb2);
        checks++;
    endtask

    // Golden Tee P3: Volume Up/Down on player 1's B3/B4 (MAME gt3d P3 bits 0/1).
    function automatic logic [7:0] golden_tee_p3(input integer player, input integer button);
        if (player == 0 && button == 6) return 8'hfe;
        if (player == 0 && button == 7) return 8'hfd;
        return 8'hff;
    endfunction

    // Power Up Baseball P3 (MAME pubball): Third Base, Home and Power Up
    // (B3..B5) of players 1/2 interleaved in bits 0..5, active low; bits 6/7
    // are unused and read low.
    function automatic logic [7:0] pubball_p3(input integer player, input integer button);
        if (button >= 6 && button <= 8) return 8'h3f & ~8'(1 << ((button - 6) * 2 + player));
        return 8'h3f;
    endfunction

    // Must Shoot TV (MAME shoottv): P1/P2 Coin and Start, P3 the triggers.
    function automatic logic [7:0] shoottv_player(input integer button);
        case (button)
            10: return 8'hfd; 11: return 8'hfe;
            default: return 8'hff;
        endcase
    endfunction
    function automatic logic [7:0] shoottv_p3(input integer player, input integer button);
        return button == 4 ? (player == 0 ? 8'hfe : 8'hfd) : 8'hff;
    endfunction

    // Clocks between two successive count releases of a saturated mouse move.
    task automatic release_period(input string label, input logic [7:0] sel, input integer period);
        integer first, second, cycle;
        logic [7:0] last;
        @(negedge clk); selector = sel; reset = 1; @(negedge clk); reset = 0;
        mouse_packet(-100, 0);
        last = trackball1[7:0]; first = -1; second = -1; cycle = 0;
        while (second < 0 && cycle < 200) begin
            @(negedge clk); cycle++;
            if (trackball1[7:0] != last) begin
                last = trackball1[7:0];
                if (first < 0) first = cycle; else second = cycle;
            end
        end
        if (first < 0 || second - first != period)
            $fatal(1, "FAMILY_INPUTS_RATE_%s period=%0d expected %0d", label, second - first, period);
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
        trackball_check("TB_RESET", 16'h0000, 16'h0000);
        // 100%: mouse right 2 and forward 1 -> X -2, Y -1, one count per tick.
        mouse_packet(2, 1);
        repeat (60) @(negedge clk);
        trackball_check("TB_MOUSE", 16'hfffe, 16'h0000);
        // OSD owns the mouse: the packet is dropped, not replayed later.
        mouse_ignore = 1; mouse_packet(-5, 0); repeat (60) @(negedge clk);
        mouse_ignore = 0; repeat (60) @(negedge clk);
        trackball_check("TB_IGNORED", 16'hfffe, 16'h0000);
        // v1.0-1.5 have one trackball: player 2's stick moves nothing.
        analog_1 = 16'h0040; repeat (60) @(negedge clk);
        trackball_check("TB2_ABSENT", 16'hfffe, 16'h0000);
        // v1.3J: player 2's stick right 64 is one count per tick, X falling.
        selector = SELECT_WCBOWL_J; repeat (45) @(negedge clk);
        if (trackball2[15:8] !== 8'h00 || trackball2[7:0] == 8'h00 || trackball1 !== 16'hfffe)
            $fatal(1, "FAMILY_INPUTS_TB2_J tb1=%04x tb2=%04x", trackball1, trackball2);
        checks++;
        analog_1 = 0;
        // Boards without a trackball hold the counters and ignore the mouse.
        selector = SELECT_BLOODSTORM; @(negedge clk);
        mouse_packet(-3, -3); repeat (60) @(negedge clk);
        if (trackball1 !== 16'hfffe) $fatal(1, "FAMILY_INPUTS_TB_DISABLED tb1=%04x", trackball1);
        checks++;

        // 68EC020 Shuffleshot/World Class Bowling (MAME shufshot/wcbowln ports):
        // 32-bit ports with the byte in bits 23:16; B1/B2 only; P3 holds an
        // unmapped coin (0xff); DIPS in SFTM form (special active low).
        @(negedge clk); #1; release_all(); selector = SELECT_SHUFSHOT;
        @(posedge clk); #1;
        expected("SHUFFLE_IDLE", 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'h0f);
        for (integer player = 0; player < 2; player++) for (integer button = 0; button < 12; button++) begin
            @(negedge clk); #1; press(player, 12'(1 << button));
            @(posedge clk); #1;
            expected("SHUFFLE_PRESS",
                player == 0 ? wcbowl_byte(button) : 8'hff,
                player == 1 ? wcbowl_byte(button) : 8'hff, 8'hff, 8'hff, 8'h00, 8'h0f);
            @(negedge clk); #1; release_all();
        end
        @(posedge clk); #1;
        dip_switches = 8'h05; sound_special = 1; vblank = 1; #1;
        expected("SHUFFLE_SYSTEM", 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'h53);
        dip_switches = 0; sound_special = 0; vblank = 0;
        // Both trackballs are live: player 2's stick toward the player moves
        // only the second ball's Y (counters held their value while disabled).
        tb2_before = trackball2;
        analog_1 = 16'h4000; repeat (45) @(negedge clk);
        if (trackball2[7:0] !== tb2_before[7:0] || trackball2[15:8] == tb2_before[15:8])
            $fatal(1, "FAMILY_INPUTS_SHUFFLE_TB2 tb2=%04x before=%04x", trackball2, tb2_before);
        checks++;
        analog_1 = 0;

        // Golden Tee (MAME gt3d ports): Shuffleshot's layout plus Volume
        // Up/Down on P3 bits 0/1 from player 1's B3/B4.
        @(negedge clk); #1; release_all(); selector = SELECT_GT_AAMA;
        @(posedge clk); #1;
        expected("GT_IDLE", 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'h0f);
        for (integer player = 0; player < 2; player++) for (integer button = 0; button < 12; button++) begin
            @(negedge clk); #1; press(player, 12'(1 << button));
            @(posedge clk); #1;
            expected("GT_PRESS",
                player == 0 ? wcbowl_byte(button) : 8'hff,
                player == 1 ? wcbowl_byte(button) : 8'hff,
                golden_tee_p3(player, button), 8'hff, 8'h00, 8'h0f);
            @(negedge clk); #1; release_all();
        end
        @(posedge clk); #1;
        dip_switches = 8'h0a; sound_special = 1; vblank = 1; #1;
        expected("GT_SYSTEM", 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'ha3);
        dip_switches = 0; sound_special = 0; vblank = 0;

        // Power Up Baseball (MAME pubball): First/Second Base on B1/B2, the
        // other bases and Power Up on P3, joystick bits unused.
        @(negedge clk); #1; release_all(); selector = SELECT_PUBBALL;
        @(posedge clk); #1;
        expected("PUBBALL_IDLE", 8'hff, 8'hff, 8'h3f, 8'hff, 8'h00, 8'h0f);
        for (integer player = 0; player < 2; player++) for (integer button = 0; button < 12; button++) begin
            @(negedge clk); #1; press(player, 12'(1 << button));
            @(posedge clk); #1;
            expected("PUBBALL_PRESS",
                player == 0 ? wcbowl_byte(button) : 8'hff,
                player == 1 ? wcbowl_byte(button) : 8'hff,
                pubball_p3(player, button), 8'hff, 8'h00, 8'h0f);
            @(negedge clk); #1; release_all();
        end

        // Count release periods (CLK_HZ 16000: 1600 Hz = 10 clocks, 3600 Hz
        // = 4, 2200 Hz = 7). Bowling and Shuffleshot keep the stick tick's rate.
        // Must Shoot TV: 16-bit-style bytes in bits 23:16, P4 all ones,
        // SW1:2 unused (reads 0); the mouse's left button is P1's trigger.
        @(negedge clk); #1; release_all(); selector = SELECT_SHOOTTV;
        @(posedge clk); #1;
        if (input_p4 !== 32'hffff_ffff) $fatal(1, "FAMILY_INPUTS_SHOOTTV_P4 %08x", input_p4);
        checks++;
        for (integer player = 0; player < 2; player++) for (integer button = 0; button < 12; button++) begin
            @(negedge clk); #1; press(player, 12'(1 << button));
            @(posedge clk); #1;
            if (input_p1 !== port(player == 0 ? shoottv_player(button) : 8'hff) ||
                input_p2 !== port(player == 1 ? shoottv_player(button) : 8'hff) ||
                input_p3 !== port(shoottv_p3(player, button)) || input_extra !== 32'd0)
                $fatal(1, "FAMILY_INPUTS_SHOOTTV_PRESS p%0d b%0d p1=%08x p2=%08x p3=%08x",
                    player, button, input_p1, input_p2, input_p3);
            checks++;
            @(negedge clk); #1; release_all();
        end
        dip_switches = 8'h0f; sound_special = 1; vblank = 1; #1;
        if (input_dips !== port(8'hbb)) $fatal(1, "FAMILY_INPUTS_SHOOTTV_DIPS %08x", input_dips);
        checks++;
        dip_switches = 0; sound_special = 0; vblank = 0;
        // Mouse: left button fires P1, motion moves gun 1 (one pixel per count).
        // Reset first: the one-clock d-pad presses above may have nudged it.
        @(negedge clk); reset = 1; @(negedge clk); reset = 0;
        @(negedge clk);
        ps2_mouse = {~ps2_mouse[24], 8'd0, 8'd10, 8'b0000_1001};
        repeat (2) @(posedge clk); #1;
        if (input_p3[23:16] !== 8'hfe || lightgun1 !== {8'd128, 9'd202})
            $fatal(1, "FAMILY_INPUTS_SHOOTTV_MOUSE p3=%08x gun1=%05x", input_p3, lightgun1);
        checks++;
        mouse_ignore = 1; repeat (2) @(posedge clk); #1;
        if (input_p3[23:16] !== 8'hff) $fatal(1, "FAMILY_INPUTS_SHOOTTV_MOUSE_OSD %08x", input_p3);
        checks++;
        mouse_ignore = 0;
        // Player 2's gun moves from its d-pad and marks itself active.
        if (lightgun2_active) $fatal(1, "FAMILY_INPUTS_SHOOTTV_P2_IDLE_ACTIVE");
        joystick_1 = 12'h001; repeat (200) @(negedge clk);
        if (lightgun2[8:0] <= 9'd192 || !lightgun2_active)
            $fatal(1, "FAMILY_INPUTS_SHOOTTV_P2 gun2=%05x active=%0b", lightgun2, lightgun2_active);
        checks++;
        release_all();
        // Off light-gun boards the guns stay centred.
        selector = SELECT_SFTM; repeat (3) @(negedge clk);
        if (lightgun1 !== {8'd128, 9'd192} || lightgun2_active)
            $fatal(1, "FAMILY_INPUTS_GUN_DISABLED %05x", lightgun1);
        checks++;

        release_period("SHUFSHOT", SELECT_SHUFSHOT, 10);
        release_period("PUBBALL", SELECT_PUBBALL, 10);
        release_period("GT_AAMA", SELECT_GT_AAMA, 4);
        release_period("GT_S", SELECT_GT_S, 4);
        release_period("GT3D_LONG", SELECT_GT3D_LONG, 10);
        release_period("GT3D_SHORT", SELECT_GT3D_SHORT, 7);
        // The saturated move (63 counts) shows in the full 8-bit X counter.
        repeat (500) @(negedge clk);
        trackball_check("GT3D_8BIT", 16'h003f, 16'h0000);
        // The S board and GT 3D's short board have one trackball; the long
        // board has two.
        selector = SELECT_GT_S; @(negedge clk); reset = 1; @(negedge clk); reset = 0;
        analog_1 = 16'h0040; repeat (60) @(negedge clk);
        trackball_check("GT_S_ONE_BALL", 16'h0000, 16'h0000);
        selector = SELECT_GT3D_LONG; repeat (60) @(negedge clk);
        if (trackball2[15:8] !== 8'h00 || trackball2[7:0] == 8'h00)
            $fatal(1, "FAMILY_INPUTS_GT3D_LONG_TB2 tb2=%04x", trackball2);
        checks++;
        analog_1 = 0;

        if (checks != 364) $fatal(1, "FAMILY_INPUTS_CASE_COUNT %0d", checks);
        $display("FAMILY_INPUTS_PASS checks=%0d layouts=5", checks);
        $finish;
    end
endmodule
