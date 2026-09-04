// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// ROM-free arithmetic checks, independently derived from ENSONIQ OTTO
// Specification Rev.2.3, printed pp30-31 (compressed format) and p36 (panning):
// https://gjcp.net/pdf/es5506.pdf
//
// This suite calls DUT helpers only for ACTUAL values. Its reference uses
// integer range reconstruction and mathematical floor division, not the DUT's
// bit rearrangement/product slicing. No manufacturer scan or ROM data is used.
//
// Scope: combinational arithmetic, not host/voice pipeline integration. The
// decode endpoint and discarded-bit rounding are explicit interpretations of
// the specified full16-bit bus format. Volume tests exercise both the
// documented signed16 range and wider filter guard values. Interpolation keeps
// the selected upper-nine-fraction-bit interpretation. Filter checks use
// signed32 internal histories and the established compatibility arithmetic:
// signed division truncates toward zero, and the high-pass K/8192 and history/2
// terms truncate independently. The host register view remains signed18. These
// details are compatibility evidence, not a measured-silicon accuracy claim.
//
// CASE=all (default), volume, decode, interpolation, or filter.
// Run with assertions enabled. Helper tests do not prove pipeline wiring of
// ACCUM[10:2], filter mode bits, or the wide O4 panning handoff; integration
// tests own those checks.
module itech32_es5506_arithmetic_spec_tb;
    logic clk = 0, reset = 1;
    logic [7:0] host_rdata, irq_vector;
    logic host_ack, sample_req, sample_companded, audio_strobe, irq, engine_busy;
    logic [1:0] sample_bank;
    logic [21:0] sample_addr;
    logic [4:0] sample_voice, active_voices, scan_voice;
    logic [6:0] current_page;
    logic signed [19:0] audio_left, audio_right;
    integer checks = 0, failures = 0;
    string test_case = "all";
    always #5 clk = ~clk;

    itech32_es5506 dut (
        .clk(clk), .reset(reset), .ce_16m(1'b0),
        .host_req(1'b0), .host_write(1'b0), .host_addr(6'd0),
        .host_wdata(8'd0), .host_rdata(host_rdata), .host_ack(host_ack),
		.par_comparator_tripped(1'b0), .par_discharge(),
		.sample_req(sample_req), .sample_bank(sample_bank),
        .sample_addr(sample_addr), .sample_companded(sample_companded),
        .sample_voice(sample_voice), .sample_rdata(16'd0), .sample_ack(1'b0),
        .audio_left(audio_left), .audio_right(audio_right),
        .audio_strobe(audio_strobe), .irq(irq), .irq_vector(irq_vector),
        .current_page(current_page), .active_voices(active_voices),
        .scan_voice(scan_voice), .engine_busy(engine_busy)
    );

    // Mathematical floor, including negative numbers. This deliberately uses
    // division/remainder in SIMULATION ONLY, not synthesizable datapath RTL.
    function automatic longint signed floor_div(
        input longint signed numerator, input longint signed denominator);
        longint signed quotient;
        begin
            quotient = numerator / denominator;
            if (numerator < 0 && numerator % denominator != 0) quotient--;
            return quotient;
        end
    endfunction

    function automatic integer ref_volume(input integer sample,
        input logic [15:0] volume);
        longint signed product, divisor;
        integer exponent, mantissa;
        begin
            exponent = int'(volume[15:12]);
            mantissa = 256 + int'(volume[11:4]);
            product = longint'(sample) * longint'(mantissa);
            divisor = 64'sd1 << (20 - exponent);
            return int'(floor_div(product, divisor));
        end
    endfunction

    // Inverse of the specified leading-sign-bit compander: reconstruct the
    // signed range from exponent/mantissa, then scale. Full bus precision is
    // retained. Narrow-format unused bits are supplied as zero by the test,
    // never replaced by an invented half-bin value.
    function automatic integer ref_decode(input logic [15:0] word_value);
        integer exponent, mantissa, restored;
        begin
            exponent = int'(word_value[15:13]);
            mantissa = int'(word_value[12:0]);
            if (exponent == 0) begin
                restored = (mantissa >= 4096) ? mantissa - 8192 : mantissa;
                return int'(floor_div(longint'(restored), 64'sd16));
            end
            restored = (mantissa < 4096) ? mantissa - 8192 : mantissa;
            if (exponent <= 5)
                return int'(floor_div(longint'(restored), 64'sd1 << (5-exponent)));
            return restored * (1 << (exponent-5));
        end
    endfunction

    function automatic integer ref_interpolation(input integer first_sample,
        input integer second_sample, input integer fraction);
        longint signed numerator;
        begin
            // Preserve one half-LSB in the result; constant input x returns2x.
            numerator = longint'(first_sample) * (64'sd512-longint'(fraction))
                      + longint'(second_sample) * longint'(fraction);
            return int'(floor_div(numerator,64'sd256));
        end
    endfunction

    function automatic integer ref_lowpass(input integer sample,
        input integer history, input integer cutoff);
        longint signed delta_product;
        begin
            delta_product = (longint'(sample)-longint'(history)) * longint'(cutoff);
            return int'(longint'(history) + delta_product / 64'sd4096);
        end
    endfunction

    function automatic integer ref_highpass(input integer sample,
        input integer previous, input integer history, input integer cutoff);
        longint signed coefficient_product;
        begin
            coefficient_product = longint'(history) * longint'(cutoff);
            return int'(longint'(sample)-longint'(previous)
                + coefficient_product / 64'sd8192 + longint'(history) / 64'sd2);
        end
    endfunction

    task automatic expect_value(input integer actual, input integer expected,
        input string label_text);
        checks++;
        if (actual != expected) begin
            failures++;
            if (failures <= 16)
                $display("ARITH_SPEC mismatch %s expected=%0d actual=%0d",
                    label_text, expected, actual);
        end
    endtask

    task automatic check_volume(input logic signed [15:0] sample,
        input logic [15:0] volume);
        logic [8:0] actual_mantissa;
        logic signed [41:0] actual_product;
        logic signed [31:0] actual_result;
        integer expected;
        begin
            actual_mantissa = dut.volume_mantissa(volume);
            expect_value(int'(actual_mantissa), 256 + int'(volume[11:4]),
                $sformatf("mantissa volume=%h", volume));
            actual_product = dut.volume_multiply(32'(sample),actual_mantissa);
            actual_result = dut.volume_finish(actual_product, volume[15:12]);
            expected = ref_volume(int'(sample), volume);
            expect_value(int'(actual_result), expected,
                $sformatf("volume sample=%0d volume=%h", sample, volume));
        end
    endtask

    task automatic volume_suite;
        integer samples [0:13];
        logic [15:0] volume;
        begin
            samples = '{-32768,-32767,-16385,-1025,-33,-1,0,1,31,1023,16383,16384,32766,32767};
            // Human-readable anchors catch a bad reference scale as well as a
            // DUT regression. Positive anchors do not depend on signed-floor
            // interpretation; they distinguish premature coefficient shifts.
            expect_value(ref_volume(32767,16'h0ff0),15,"reference low volume anchor");
            expect_value(ref_volume(32767,16'h1ff0),31,"reference next exponent anchor");
            expect_value(ref_volume(32767,16'hfff0),523248,"reference full volume anchor");
            expect_value(ref_volume(-32768,16'hfff0),-523264,"reference negative rail anchor");
            for (integer e=0; e<16; e++) begin
                for (integer m=0; m<256; m++) begin
                    for (integer s=0; s<14; s++) begin
                        volume = {4'(e),8'(m),4'h0};
                        check_volume(16'(samples[s]),volume);
                        // Low4 bits are ramp fraction, not pan mantissa.
                        check_volume(16'(samples[s]),volume | 16'h000f);
                    end
                end
            end
        end
    endtask

    task automatic decode_suite;
        logic [15:0] word_value;
        integer actual, expected;
        begin
            // Endpoint anchors from the table's ranges. Zero low data bits
            // select the lower encoded endpoint under this interpretation.
            expect_value(ref_decode(16'h0000),0,"decode reference zero");
            expect_value(ref_decode(16'h0f00),240,"decode reference positive exponent0");
            expect_value(ref_decode(16'h1000),-256,"decode reference negative exponent0");
            expect_value(ref_decode(16'h1f00),-16,"decode reference negative nearzero");
            expect_value(ref_decode(16'h2000),-512,"decode reference exponent1");
            expect_value(ref_decode(16'hdf00),15872,"decode reference exponent6");
            expect_value(ref_decode(16'he000),-32768,"decode reference negative rail");
            expect_value(ref_decode(16'hff00),31744,"decode reference high exponent7");
            expect_value(ref_decode(16'hffff),32764,"decode reference full mantissa precision");
            // Exhausts all256 zero-low-byte codes, every12-bit compressed
            // word, every exponent, sign transition, and meaningful low bits.
            for (integer w=0; w<65536; w++) begin
                word_value = 16'(w);
                actual = int'($signed(dut.decode_ulaw(word_value)));
                expected = ref_decode(word_value);
                expect_value(actual,expected,$sformatf("decode word=%h",word_value));
            end
        end
    endtask

    task automatic check_interpolation(input logic signed [15:0] first_sample,
        input logic signed [15:0] second_sample, input integer fraction);
        logic [9:0] first_weight, second_weight;
        logic signed [26:0] first_product, second_product;
        logic signed [17:0] actual;
        begin
            first_weight = 10'(512-fraction);
            second_weight = 10'(fraction);
            first_product = dut.interpolation_multiply(first_sample,first_weight);
            second_product = dut.interpolation_multiply(second_sample,second_weight);
            expect_value(int'(first_product), int'(first_sample)*(512-fraction),
                "interpolation first signed product");
            expect_value(int'(second_product), int'(second_sample)*fraction,
                "interpolation second signed product");
            actual = dut.interpolation_finish(first_product,second_product);
            expect_value(int'(actual),ref_interpolation(int'(first_sample),
                int'(second_sample),fraction),$sformatf("interpolation s0=%0d s1=%0d f=%0d",
                first_sample,second_sample,fraction));
        end
    endtask

    task automatic interpolation_suite;
        integer samples [0:11];
        begin
            samples = '{-32768,-32767,-16385,-3,-1,0,1,3,16383,16384,32766,32767};
            expect_value(ref_interpolation(0,1,256),1,"reference positive half-LSB");
            expect_value(ref_interpolation(-1,0,256),-1,"reference negative half-LSB");
            expect_value(ref_interpolation(-32768,32767,1),-65281,"reference extreme step");
            expect_value(ref_interpolation(32767,32767,511),65534,"reference constant scale");
            for (integer a=0; a<12; a++)
                for (integer b=0; b<12; b++)
                    for (integer f=0; f<512; f++)
                        check_interpolation(16'(samples[a]),16'(samples[b]),f);
        end
    endtask

    task automatic check_lowpass(input logic signed [31:0] sample,
        input logic signed [31:0] history, input logic [11:0] cutoff);
        logic signed [31:0] operand;
        logic signed [28:0] product_high;
        logic [27:0] product_low;
        logic signed [47:0] product;
        logic signed [31:0] actual;
        longint signed expected_product;
        begin
            operand = sample - history;
            product_high = dut.filter_multiply_high(operand[31:16],cutoff);
            product_low = dut.filter_multiply_low(operand[15:0],cutoff);
            product = longint'(product_high) * 64'sd65536 + longint'(product_low);
            expected_product = (longint'(sample)-longint'(history))*longint'(cutoff);
            expect_value(int'(product),int'(expected_product),"lowpass signed product");
            actual = dut.lowpass_finish(product,history);
            expect_value(int'(actual),ref_lowpass(int'(sample),int'(history),int'(cutoff)),
                $sformatf("lowpass x=%0d h=%0d k=%0d",sample,history,cutoff));
        end
    endtask

    task automatic check_highpass(input logic signed [31:0] sample,
        input logic signed [31:0] previous, input logic signed [31:0] history,
        input logic [11:0] cutoff);
        logic signed [28:0] product_high;
        logic [27:0] product_low;
        logic signed [47:0] product;
        logic signed [31:0] actual;
        longint signed expected_product;
        begin
            product_high = dut.filter_multiply_high(history[31:16],cutoff);
            product_low = dut.filter_multiply_low(history[15:0],cutoff);
            product = longint'(product_high) * 64'sd65536 + longint'(product_low);
            expected_product = longint'(history)*longint'(cutoff);
            expect_value(int'(product),int'(expected_product),"highpass signed product");
            actual = dut.highpass_finish(product,sample,history,previous);
            expect_value(int'(actual),ref_highpass(int'(sample),int'(previous),
                int'(history),int'(cutoff)),
                $sformatf("highpass x=%0d previous=%0d h=%0d k=%0d",
                    sample,previous,history,cutoff));
        end
    endtask

    task automatic filter_suite;
        integer states [0:12];
        integer coefficients [0:5];
        logic [31:0] random_state;
        logic signed [31:0] sample,previous,history;
        logic [11:0] cutoff;
        begin
            states = '{-200000,-131072,-65536,-32769,-3,-1,0,1,3,32767,65535,131071,200000};
            coefficients = '{0,1,127,2048,4094,4095};
            expect_value(ref_lowpass(200000,0,4095),199951,
                "reference retains guard value beyond signed18");
            expect_value(ref_lowpass(0,1,1),1,"reference negative trunczero");
            expect_value(ref_lowpass(0,-1,1),-1,"reference positive fraction");
            expect_value(ref_highpass(0,0,3,2048),1,
                "reference separate positive HP truncation");
            expect_value(ref_highpass(0,0,-3,2048),-1,
                "reference separate negative HP truncation");
            expect_value(ref_highpass(131071,-131072,131071,4095),393197,
                "reference HP retains guard value");
            for (integer k=0; k<6; k++) begin
                for (integer x=0; x<13; x++) begin
                    for (integer h=0; h<13; h++) begin
                        check_lowpass(32'(states[x]),32'(states[h]),12'(coefficients[k]));
                        for (integer p=0; p<13; p++)
                            check_highpass(32'(states[x]),32'(states[p]),32'(states[h]),
                                12'(coefficients[k]));
                    end
                end
            end
            // Every coefficient, including discarded-bit boundaries, with
            // deliberately odd positive and negative histories.
            for (integer k=0; k<4096; k++) begin
                check_lowpass(-32'sd32769,32'sd65535,12'(k));
                check_lowpass(32'sd32767,-32'sd65535,12'(k));
                check_highpass(32'sd32767,-32'sd32769,32'sd65535,12'(k));
                check_highpass(-32'sd32769,32'sd32767,-32'sd65535,12'(k));
            end
            // Reproducible authored stimulus, not simulator-global RNG state.
            random_state = 32'h52ca_a46d;
            for (integer n=0; n<4096; n++) begin
                random_state = {random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                sample = random_state[17:0];
                random_state = {random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                previous = random_state[17:0];
                random_state = {random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                history = random_state[17:0];
                random_state = {random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                cutoff = random_state[11:0];
                check_lowpass(sample,history,cutoff);
                check_highpass(sample,previous,history,cutoff);
            end
        end
    endtask

    initial begin
        void'($value$plusargs("CASE=%s",test_case));
        repeat (3) @(negedge clk);
        reset = 0;
        if (test_case == "all" || test_case == "volume") volume_suite();
        if (test_case == "all" || test_case == "decode") decode_suite();
        if (test_case == "all" || test_case == "interpolation") interpolation_suite();
        if (test_case == "all" || test_case == "filter") filter_suite();
        if (checks == 0) $fatal(1,"Unknown arithmetic CASE=%s",test_case);
        if (failures != 0)
            $fatal(1,"ARITH_SPEC FAIL case=%s checks=%0d failures=%0d",test_case,checks,failures);
        $display("ARITH_SPEC PASS case=%s checks=%0d (documented volume order; compatibility filter; interpreted decode/interpolation)",
            test_case,checks);
        $finish;
    end
endmodule
