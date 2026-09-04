`timescale 1ns/1ps
// Candidate-only source-native input vectors (MAME itech32.cpp:1149..1254).
// Intentionally requires bloodstorm_mode/input_extra; not run on a pretend
// SFTM/TK substitute. Registered controller timing is tested independently of
// immediate DIP/service/vblank/custom inputs. No HPS/MRA/device is simulated.
module itech32_bloodstorm_inputs_tb;
    logic clk = 0, reset = 1, timekill_mode = 0, bloodstorm_mode = 1;
    logic [11:0] joystick_0 = 0, joystick_1 = 0;
    logic service_button = 0, vblank = 0, sound_special = 0;
    logic [7:0] dip_switches = 0;
    logic [31:0] input_p1, input_p2, input_p3, input_p4, input_dips, input_extra;
    integer checks = 0;
    integer negative_kind = 0;
    itech32_inputs dut (.*);
    always #5 clk = ~clk;

    task automatic expected(input logic [7:0] p1, p2, extra, dips);
        logic [31:0] observed_extra;
        observed_extra = input_extra;
        // A purposeful checker mutation, not a bypass of the DUT assertion.
        if (negative_kind == 1) observed_extra = observed_extra ^ 32'h00010000;
        if (input_p1 !== {8'h00,p1,16'h0000} || input_p2 !== {8'h00,p2,16'h0000} ||
            input_p3 !== 32'h00000000 || input_p4 !== 32'h00ff0000 ||
            observed_extra !== {8'h00,extra,16'h0000} || input_dips !== {8'h00,dips,16'h0000})
            $fatal(1,"BLOOD_INPUTS_VALUE p1=%08x p2=%08x p3=%08x p4=%08x extra=%08x dip=%08x",
                input_p1,input_p2,input_p3,input_p4,observed_extra,input_dips);
        checks++;
    endtask
    // Explicit table from board controls, not production bit assignments.
    function automatic logic [7:0] single_p(input integer button);
        case (button)
            0:return 8'hef; 1:return 8'hdf; 2:return 8'hbf; 3:return 8'h7f;
            4:return 8'hfb; 6:return 8'hf7; 10:return 8'hfd; 11:return 8'hfe;
            default:return 8'hff; // B2/B4/B5 live in EXTRA; unused B6 nowhere.
        endcase
    endfunction
    function automatic logic [7:0] single_extra(input integer player, button);
        if (player == 0) case (button)
            5:return 8'hfe; 7:return 8'hfb; 8:return 8'hef; default:return 8'hff;
        endcase
        else case (button)
            5:return 8'hfd; 7:return 8'hf7; 8:return 8'hdf; default:return 8'hff;
        endcase
    endfunction
    initial begin
        void'($value$plusargs("NEGATIVE=%d",negative_kind));
        repeat (3) @(negedge clk);
        reset = 0;
        @(posedge clk); #1; expected(8'hff,8'hff,8'hff,8'h07);
        for (integer player=0; player<2; player++) for (integer button=0; button<12; button++) begin
            @(negedge clk); #1;
            if (player==0) joystick_0 = 12'(1<<button); else joystick_1 = 12'(1<<button);
            #1; expected(8'hff,8'hff,8'hff,8'h07); // no combinational controller leak
            @(posedge clk); #1;
            expected(player==0?single_p(button):8'hff, player==1?single_p(button):8'hff,
                     single_extra(player,button),8'h07);
            @(negedge clk); #1; joystick_0=0;joystick_1=0;
            @(posedge clk); #1; expected(8'hff,8'hff,8'hff,8'h07);
        end
        @(negedge clk); #1; joystick_0=12'hfff;joystick_1=12'hfff;
        @(posedge clk); #1; expected(8'h00,8'h00,8'hc0,8'h07);
        // OSD supplies zero at this interface. Every control, including Start
        // and Coin, must release at the existing single clock boundary.
        @(negedge clk); #1; joystick_0=0;joystick_1=0;
        #1; expected(8'h00,8'h00,8'hc0,8'h07);
        @(posedge clk); #1; expected(8'hff,8'hff,8'hff,8'h07);
        for (integer sw=0; sw<16; sw++) begin
            @(negedge clk); #1; dip_switches=8'(sw); #1;
            expected(8'hff,8'hff,8'hff,{4'(sw),4'h7});
        end
        dip_switches=0;service_button=1;#1;expected(8'hff,8'hff,8'hff,8'h06);
        service_button=0;vblank=1;#1;expected(8'hff,8'hff,8'hff,8'h03);
        vblank=0;sound_special=1;#1;expected(8'hff,8'hff,8'hff,8'h0f);
        service_button=1;vblank=1;dip_switches=8'h0a;#1;expected(8'hff,8'hff,8'hff,8'haa);
        // High upload bits do not become a second copy of TK's SW1 convention.
        dip_switches=8'hfa;#1;expected(8'hff,8'hff,8'hff,8'haa);
        @(negedge clk);reset=1;joystick_0=12'hfff;joystick_1=12'hfff;
        @(posedge clk);#1;expected(8'hff,8'hff,8'hff,8'haa);
        if(checks!=98) $fatal(1,"BLOOD_INPUTS_CASE_COUNT %0d",checks);
        $display("BLOOD_INPUTS_PASS checks=%0d candidate_ports=1",checks);
        $finish;
    end
endmodule
