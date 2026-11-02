`timescale 1ns/1ps
// Hard Yardage and Pairs controller vectors on the bloodstm board (MAME 0.288
// itech32.cpp itech32_base_16bit, hardyard and pairs input ports). Every MiSTer
// control of every player is pressed alone; all six ports are compared with an
// explicit table written from the MAME port definitions. Players 3/4 must not
// leak into any profile that does not wire them.
module itech32_bloodstm_family_inputs_tb;
    import itech32_profile_pkg::*;
    logic clk = 0, reset = 1;
    logic [11:0] joystick_0 = 0, joystick_1 = 0, joystick_2 = 0, joystick_3 = 0;
    logic service_button = 0, vblank = 0, sound_special = 0;
    logic [7:0] dip_switches = 0;
    logic [31:0] input_p1, input_p2, input_p3, input_p4, input_dips, input_extra;
    logic [7:0] selector = SELECT_HARDYARD;
    board_profile_t profile;
    integer checks = 0;
    assign profile = profile_for_selector(selector);
    itech32_inputs dut (.*);
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
        if (checks != 216) $fatal(1, "FAMILY_INPUTS_CASE_COUNT %0d", checks);
        $display("FAMILY_INPUTS_PASS checks=%0d layouts=2", checks);
        $finish;
    end
endmodule
