// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Exhaustive check of the selected board-to-MiSTer conversion, not a claim
// that its MAME-derived stereo swap is an analogue PCB measurement.
module itech32_sound_output_tb;
    logic signed [19:0] es_left = 0, es_right = 0;
    logic es_strobe = 0;
    logic [1:0] gain = 0;
    logic signed [15:0] audio_left, audio_right;
    logic audio_strobe;
    integer checks = 0;
    itech32_sound_output dut (.*);

    function automatic integer reference_scale(input integer value,
        input integer gain_select);
        // Integer division truncates toward zero, independent of the RTL's
        // magnitude-first shift implementation and its intermediate widths.
        // 1x maps the full 20-bit range exactly; 2x/4x saturate at 16 bits.
        integer divisor;
        integer scaled;
        divisor = (gain_select == 0) ? 16 : (gain_select == 1) ? 8 : 4;
        scaled = value / divisor;
        if (scaled > 32767) return 32767;
        if (scaled < -32768) return -32768;
        return scaled;
    endfunction

    initial begin
        for (integer gain_select = 0; gain_select <= 3; gain_select++) begin
            gain = 2'(gain_select);
            for (integer value = -524288; value <= 524287; value++) begin
                es_left = 20'(value);
                es_right = 20'(-value-1);
                es_strobe = value[0];
                #1;
                assert ($signed(audio_left) == reference_scale(-value-1, gain_select) &&
                        $signed(audio_right) == reference_scale(value, gain_select))
                    else $fatal(1,"board conversion mismatch gain=%0d input=%0d L=%0d R=%0d",
                        gain_select,value,$signed(audio_left),$signed(audio_right));
                assert (audio_strobe == es_strobe) else $fatal(1,"strobe changed");
                checks++;
            end
        end
        es_strobe = 0;
        repeat (16) begin
            #10;
            assert (audio_left == -16'sd32768 && audio_right == 16'sd32767 && !audio_strobe)
                else $fatal(1,"held output changed without new input");
        end
        $display("PASS SOUND_OUTPUT signed20 inputs=%0d gains=1x/2x/4x independent stereo/headroom/saturation/strobe checks",checks);
        $finish;
    end
endmodule
