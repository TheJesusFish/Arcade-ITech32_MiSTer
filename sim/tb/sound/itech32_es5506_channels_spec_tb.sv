// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1fs

// Canonical six-stereo-channel tests against ENSONIQ OTTO Rev2.3 printed14-15,
// 20,36-37: https://gjcp.net/pdf/es5506.pdf . No second compatibility mixer.
// Ordinary voice-only references stay within the signed23-bit range. Explicit
// PAGE40 boundary vectors exercise the selected two's-complement wrap at that
// storage width before documented20-bit clipping. Wrap is an interpretation of
// an unspecified overflow case, not a claim of measured silicon behavior.
// All channel outputs share one complete-scan strobe; legacy stereo ports must
// alias channel0. PAGE40 testing avoids undefined freeze/clear collisions.
module itech32_es5506_channels_spec_tb;
    localparam integer CARRIER_HZ=47_727_273;
    logic clk=0,reset=1,clock_enable=0,ce_16m=0;
    integer remainder=0;
    always #(500_000_000.0/CARRIER_HZ)clk=~clk;
    always @(negedge clk)begin
        ce_16m=0;
        if(reset || !clock_enable)remainder=0;
        else begin
            remainder+=16_000_000;
            if(remainder>=CARRIER_HZ)begin remainder-=CARRIER_HZ;ce_16m=1;end
        end
    end
    logic host_req=0,host_write=0,host_ack;
    logic [5:0] host_addr=0;
    logic [7:0] host_wdata=0,host_rdata;
    logic sample_req,sample_ack=0,sample_companded,sample_served=0;
    logic [1:0] sample_bank;
    logic [21:0] sample_addr;
    logic [4:0] sample_voice;
    logic [23:0] sample_signature=0;
    logic signed [19:0] audio_left,audio_right;
    logic [119:0] audio_left_channels,audio_right_channels;
    logic audio_strobe,irq,engine_busy;
    logic [7:0] irq_vector;
    logic [6:0] current_page;
    logic [4:0] active_voices,scan_voice;
    itech32_es5506 dut(
        .clk(clk),.reset(reset),.ce_16m(ce_16m),
        .host_req(host_req),.host_write(host_write),.host_addr(host_addr),
        .host_wdata(host_wdata),.host_rdata(host_rdata),.host_ack(host_ack),
		.par_comparator_tripped(1'b0),.par_discharge(),
		.sample_req(sample_req),.sample_bank(sample_bank),
        .sample_addr(sample_addr),.sample_companded(sample_companded),
        .sample_voice(sample_voice),.sample_rdata(16'd0),.sample_ack(sample_ack),
        .audio_left(audio_left),.audio_right(audio_right),
        .audio_left_channels(audio_left_channels),.audio_right_channels(audio_right_channels),
        .audio_strobe(audio_strobe),.irq(irq),.irq_vector(irq_vector),
        .current_page(current_page),.active_voices(active_voices),.scan_voice(scan_voice),.engine_busy(engine_busy)
    );
    always @(posedge clk)begin
        sample_ack<=0;
        if(reset || !sample_req)sample_served<=0;
        else if(!sample_served || sample_signature!={sample_bank,sample_addr})begin
            sample_served<=1;sample_signature<={sample_bank,sample_addr};sample_ack<=1;
        end
    end
    string test_case="channels";
    integer expected_voices=5,vectors=0,frames=0,frame_writes=0;
    integer carriers=0,input_ticks=0,frame_origin=0,frames_launched=0;
    integer expected_left[0:5],expected_right[0:5];
    longint signed sums_left[0:5],sums_right[0:5];
    logic check_scan=0;
    logic [31:0] written_voices=0;
    logic [119:0] previous_left=0,previous_right=0;
    event voice_store_event;
    logic [4:0] voice_store_addr;

    function automatic longint signed floor_div(input longint signed n,input longint signed d);
        if(n>=0)return n/d;
        return -((-n+d-1)/d);
    endfunction
    function automatic integer pan(input integer signed sample_value,input integer volume);
        return integer'(floor_div(longint'(sample_value)*(256+(volume/16)%256),
            32*(64'd1<<(15-volume/4096))));
    endfunction
    function automatic integer rail20(input longint signed value);
        if(value>524287)return 524287;
        if(value< -524288)return -524288;
        return integer'(value);
    endfunction
    function automatic integer signed23(input logic [31:0] raw);
        integer value;
        value=integer'(raw&32'h7fffff);
        if(value>=4194304)value-=8388608;
        return value;
    endfunction
    function automatic longint signed selected_wrap23(input longint signed value);
        longint signed wrapped;
        // Independent integer reference for the explicitly selected signed23
        // modulo-store policy. The manufacturer text specifies the width, but
        // not overflow behavior beyond its three guard bits.
        wrapped=value;
        while(wrapped>4194303)wrapped-=8388608;
        while(wrapped< -4194304)wrapped+=8388608;
        return wrapped;
    endfunction
    task automatic zero_expectations;
        for(integer ca=0;ca<6;ca++)begin
            expected_left[ca]=0;expected_right[ca]=0;sums_left[ca]=0;sums_right[ca]=0;
        end
    endtask
    task automatic finish_sums;
        for(integer ca=0;ca<6;ca++)begin
            // General voice-mix vectors intentionally remain in range. The
            // dedicated PAGE40 cases below own wrap-boundary coverage.
            assert(sums_left[ca]>=-4194304 && sums_left[ca]<=4194303 &&
                sums_right[ca]>=-4194304 && sums_right[ca]<=4194303)
                else $fatal(1,"test exceeds documented23-bit guard range CA=%0d",ca);
            expected_left[ca]=rail20(sums_left[ca]);expected_right[ca]=rail20(sums_right[ca]);
        end
    endtask

    always @(posedge clk)begin
        if(reset)begin
            carriers=0;input_ticks=0;frames=0;frame_writes=0;written_voices=0;
            frame_origin=0;frames_launched=0;previous_left=0;previous_right=0;
        end else begin
            carriers++;
            if(check_scan && dut.voice_write_en && !dut.host_write_execute_pending)begin
                assert(dut.voice_write_addr<expected_voices && !written_voices[dut.voice_write_addr])
                    else $fatal(1,"channel scan duplicate/out-of-range voice=%0d",dut.voice_write_addr);
                written_voices[dut.voice_write_addr]=1;frame_writes++;
            end
            if(clock_enable && ce_16m)begin
                input_ticks++;
                if(input_ticks%(16*expected_voices)==0)begin frame_origin=carriers;frames_launched++;end
            end
            #0.001;
            assert(audio_left==$signed(audio_left_channels[19:0]) &&
                audio_right==$signed(audio_right_channels[19:0]))
                else $fatal(1,"legacy outputs are not exact canonical channel0 aliases");
            if(check_scan && audio_strobe)begin
                assert(!dut.scan_underrun)else $fatal(1,"unprimed cache invalidates channel test");
                assert(frame_writes==expected_voices && frames_launched==frames+1 && frame_origin!=0)
                    else $fatal(1,"missing voice/full-scan output");
                // T28 is the established FPGA transport contract, not an
                // assertion about original silicon pin propagation delay.
                assert(carriers-frame_origin==28)else $fatal(1,"channel output changed terminal phase %0d",carriers-frame_origin);
                for(integer ca=0;ca<6;ca++)
                    assert($signed(audio_left_channels[ca*20+:20])==expected_left[ca] &&
                        $signed(audio_right_channels[ca*20+:20])==expected_right[ca])
                        else $fatal(1,"CHANNEL CA=%0d expected=%0d/%0d actual=%0d/%0d N=%0d frame=%0d CASE=%s",
                            ca,expected_left[ca],expected_right[ca],$signed(audio_left_channels[ca*20+:20]),
                            $signed(audio_right_channels[ca*20+:20]),expected_voices,frames,test_case);
                frames++;frame_writes=0;written_voices=0;
            end else if(check_scan)begin
                assert(audio_left_channels==previous_left && audio_right_channels==previous_right)
                    else $fatal(1,"partial/intermediate channel output outside full-scan strobe");
            end
            previous_left=audio_left_channels;previous_right=audio_right_channels;
        end
    end

    // Publish a post-NBA observation point for the canonical23-bit store. This
    // checks actual sequential accumulation order without calling DUT helpers.
    always @(posedge clk)begin
        if(!reset && check_scan && dut.voice_write_en && !dut.host_write_execute_pending)begin
            voice_store_addr<=dut.voice_write_addr;
            #0.001;
            ->voice_store_event;
        end
    end

    task automatic transfer(input logic wr,input logic [5:0] address,input logic [7:0] value,
        output logic [7:0] result);
        integer timeout;
        @(negedge clk);#0.002;host_req=1;host_write=wr;host_addr=address;host_wdata=value;
        timeout=0;
        do begin @(posedge clk);#0.002;timeout++;end while(!host_ack && timeout<100);
        assert(host_ack)else $fatal(1,"channel host timeout %h",address);
        result=host_rdata;
        repeat(2)begin @(posedge clk);#0.002;assert(!host_ack)else $fatal(1,"held request duplicateACK");end
        @(negedge clk);#0.002;host_req=0;
        repeat(2)@(posedge clk);#0.002;
    endtask
    task automatic write_reg(input logic [3:0] slot,input logic [31:0] value);
        logic [7:0] ignored;
        for(integer b=0;b<4;b++)transfer(1,{slot,2'(b)},value[31-b*8-:8],ignored);
    endtask
    task automatic reset_dut(input integer actv);
        check_scan=0;clock_enable=0;
        @(negedge clk);#0.002;reset=1;host_req=0;
        repeat(5)@(negedge clk);#0.002;reset=0;
        repeat(5)@(negedge clk);
        expected_voices=actv+1;zero_expectations();write_reg(4'hb,32'(actv));
    endtask
    task automatic program_voice(input integer v,input logic running,input integer signed sample_value,
        input integer lvol,input integer rvol,input integer ca);
        write_reg(4'hf,32'(v+32));write_reg(4'h1,0);write_reg(4'h2,32'h00100000);write_reg(4'h3,0);
        for(integer slot=4;slot<=9;slot++)write_reg(4'(slot),slot==4 ? 32'(sample_value*2):0);
        write_reg(4'hf,32'(v));write_reg(4'h1,0);write_reg(4'h6,0);write_reg(4'h7,0);write_reg(4'h9,0);
        write_reg(4'h2,32'(lvol));write_reg(4'h4,32'(rvol));
        write_reg(4'h0,32'h300|32'(ca*1024)|(running ? 32'd0:32'd3));
        if(running && ca<6)begin sums_left[ca]+=pan(sample_value,lvol);sums_right[ca]+=pan(sample_value,rvol);end
    endtask
    task automatic start_scans;
        repeat(8000)@(negedge clk);
        finish_sums();check_scan=1;clock_enable=1;
    endtask
    task automatic await_frames(input integer count);
        integer timeout;
        timeout=0;
        while(frames<count && timeout<50000)begin @(negedge clk);#0.002;timeout++;end
        assert(frames==count)else $fatal(1,"channel full-scan timeout");
    endtask
    task automatic stop_scans;
        clock_enable=0;check_scan=0;vectors++;
    endtask
    task automatic expect_channel_store(input integer voice,input integer ca,
        input longint signed expected,input string label_text);
        integer stores;
        stores=0;
        do begin
            @voice_store_event;
            stores++;
            assert(stores<=expected_voices)
                else $fatal(1,"missed accumulator checkpoint voice=%0d CA=%0d CASE=%s",
                    voice,ca,label_text);
        end while(voice_store_addr!=5'(voice));
        assert(longint'($signed(dut.channel_mix_left[ca]))==expected)
            else $fatal(1,"signed23 store mismatch voice=%0d CA=%0d expected=%0d actual=%0d CASE=%s",
                voice,ca,expected,$signed(dut.channel_mix_left[ca]),label_text);
    endtask
    task automatic solo_vector(input integer ca,input integer index);
        reset_dut(4);
        for(integer v=0;v<5;v++)program_voice(v,v==index,1234+37*ca,16'hf000,16'heab0,ca);
        start_scans();await_frames(3);stop_scans();
    endtask
    task automatic mixed_vector(input integer actv,input integer pattern);
        integer ca,value,lv,rv;
        reset_dut(actv);
        for(integer v=0;v<=actv;v++)begin
            ca=v%6;lv=16'hf000;rv=16'heab0;
            case(pattern)
                0:value=(v*97)%2001-1000;
                1:begin ca=(v/2)%6;value=v%2==0 ? 8192:-8192;end
                2:begin value=10000;lv=16'hfff0;rv=16'hfff0;end
                3:begin value=-10000;lv=16'hfff0;rv=16'hfff0;end
                default:begin
                    lv=16'hfff0;rv=16'hfff0;
                    case(v)
                        0,1:begin ca=0;value=32767;end
                        2:begin ca=0;value=-32768;end
                        3,4:begin ca=1;value=-32768;end
                        5:begin ca=2;value=32767;end
                        6:begin ca=3;value=1;end
                        7:begin ca=4;value=-1;end
                        default:begin ca=5;value=(v%2==0) ? 17:-17;end
                    endcase
                end
            endcase
            program_voice(v,1,value,lv,rv,ca);
        end
        start_scans();await_frames(3);stop_scans();
    endtask
    task automatic page40_case(input logic add_running_voice);
        logic [31:0] left_raw,right_raw;
        for(integer ca=0;ca<6;ca++)begin
            reset_dut(31); // stopped reset voices still consume all32 slots
            if(add_running_voice)program_voice(31,1,1234,16'hf000,16'heab0,ca);
            start_scans();
            // Natural clear occurs before voice0. Write afterward, far from
            // final-voice output, using normal held public host transactions.
            while(!written_voices[0])begin @(negedge clk);#0.002;end
            case(ca)
                0:begin left_raw=32'h00000001;right_raw=32'hffffffff;end
                1:begin left_raw=32'h0007ffff;right_raw=32'hfff80000;end
                2:begin left_raw=32'h003fffff;right_raw=32'hffc00000;end
                3:begin left_raw=32'h00080000;right_raw=32'hfff7ffff;end
                4:begin left_raw=32'h5a000123;right_raw=32'ha5ffedcb;end
                default:begin left_raw=32'h00000000;right_raw=32'hff812345;end
            endcase
            if(add_running_voice)begin
                left_raw=32'(520000+ca*173);right_raw=32'(-520000+ca*237);
            end
            write_reg(4'hf,32'h40);write_reg(4'(2*ca),left_raw);write_reg(4'(2*ca+1),right_raw);
            assert(frames==0)else $fatal(1,"page40 host writes missed first frame");
            expected_left[ca]=rail20(signed23(left_raw)+(add_running_voice ? pan(1234,16'hf000):0));
            expected_right[ca]=rail20(signed23(right_raw)+(add_running_voice ? pan(1234,16'heab0):0));
            await_frames(1);
            // PAGE40 is write-only. No register readback is assigned a golden
            // value. Next scan naturally clears accumulators under the chosen
            // preserved clear-beforevoice0 policy, with no invented TEST freeze.
            zero_expectations();
            if(add_running_voice)begin expected_left[ca]=pan(1234,16'hf000);expected_right[ca]=pan(1234,16'heab0);end
            await_frames(2);stop_scans();
        end
    endtask
    task automatic accumulator_wrap_boundaries;
        integer pair,ca_positive,ca_negative;
        longint signed positive_sum,negative_sum;
        assert(pan(4096,0)==1 && pan(-4096,0)==-1)
            else $fatal(1,"boundary stimulus no longer produces exact +/-1 contributions");
        for(pair=0;pair<3;pair++)begin
            ca_positive=pair*2;ca_negative=ca_positive+1;
            reset_dut(31);
            program_voice(30,1,4096,0,0,ca_positive);
            program_voice(31,1,-4096,0,0,ca_negative);
            // Select PAGE40 before the scan, then seed after voice0's natural
            // clear. The late voices leave ample distance from the host writes.
            write_reg(4'hf,32'h40);start_scans();
            while(!written_voices[0])begin @(negedge clk);#0.002;end
            write_reg(4'(2*ca_positive),32'h003fffff);
            write_reg(4'(2*ca_negative),32'h00400000);
            positive_sum=selected_wrap23(4194303+sums_left[ca_positive]);
            negative_sum=selected_wrap23(-4194304+sums_left[ca_negative]);
            assert(positive_sum==-4194304 && negative_sum==4194303)
                else $fatal(1,"signed23 boundary reference failed");
            expected_left[ca_positive]=rail20(positive_sum);
            expected_left[ca_negative]=rail20(negative_sum);
            expect_channel_store(30,ca_positive,positive_sum,"+max+1 wraps to min");
            expect_channel_store(31,ca_negative,negative_sum,"-min-1 wraps to max");
            await_frames(1);stop_scans();
        end
    endtask
    task automatic accumulator_cancellation_order;
        integer pair,ca_a,ca_b,seed_a,seed_b,first_a,first_b,second_a,second_b;
        longint signed after_first_a,after_first_b,final_a,final_b;
        for(pair=0;pair<3;pair++)begin
            ca_a=pair*2;ca_b=ca_a+1;
            case(pair)
                0:begin
                    // Same +max seed and final sum, but only CA0 crosses the
                    // signed23 boundary before its cancelling contribution.
                    seed_a=4194303;first_a=1;second_a=-1;
                    seed_b=4194303;first_b=-1;second_b=1;
                end
                1:begin
                    // Mirror the order-sensitive comparison at the low bound.
                    seed_a=-4194304;first_a=-1;second_a=1;
                    seed_b=-4194304;first_b=1;second_b=-1;
                end
                default:begin
                    // Exercise the crossing/cancellation sequence on the two
                    // remaining canonical channel stores as well.
                    seed_a=4194303;first_a=1;second_a=-1;
                    seed_b=-4194304;first_b=-1;second_b=1;
                end
            endcase
            reset_dut(31);
            program_voice(28,1,first_a*4096,0,0,ca_a);
            program_voice(29,1,first_b*4096,0,0,ca_b);
            program_voice(30,1,second_a*4096,0,0,ca_a);
            program_voice(31,1,second_b*4096,0,0,ca_b);
            write_reg(4'hf,32'h40);start_scans();
            while(!written_voices[0])begin @(negedge clk);#0.002;end
            write_reg(4'(2*ca_a),32'(seed_a));
            write_reg(4'(2*ca_b),32'(seed_b));
            after_first_a=selected_wrap23(longint'(seed_a)+longint'(first_a));
            after_first_b=selected_wrap23(longint'(seed_b)+longint'(first_b));
            final_a=selected_wrap23(longint'(seed_a)+longint'(first_a)+longint'(second_a));
            final_b=selected_wrap23(longint'(seed_b)+longint'(first_b)+longint'(second_b));
            expected_left[ca_a]=rail20(final_a);expected_left[ca_b]=rail20(final_b);
            expect_channel_store(28,ca_a,after_first_a,"cancellation order A first");
            expect_channel_store(29,ca_b,after_first_b,"cancellation order B first");
            expect_channel_store(30,ca_a,final_a,"cancellation order A final");
            expect_channel_store(31,ca_b,final_b,"cancellation order B final");
            await_frames(1);stop_scans();
        end
    endtask
    initial begin
        integer actv;
        void'($value$plusargs("CASE=%s",test_case));
        if(test_case=="channels")begin
            for(integer ca=0;ca<6;ca++)begin solo_vector(ca,0);solo_vector(ca,4);end
            for(integer a=0;a<5;a++)begin
                case(a)0:actv=4;1:actv=7;2:actv=15;3:actv=23;default:actv=31;endcase
                for(integer pattern=0;pattern<5;pattern++)mixed_vector(actv,pattern);
            end
        end else if(test_case=="page40")page40_case(0);
        else if(test_case=="page40-add")begin
            page40_case(1);
            accumulator_wrap_boundaries();
            accumulator_cancellation_order();
        end
        else if(test_case=="undefined-ca")begin
            // CA6/7 are manufacturer-undefined. Silence is an explicitly chosen
            // deterministic integration policy, not a documented silicon fact.
            solo_vector(6,0);solo_vector(7,4);
        end else $fatal(1,"unknown channel CASE=%s",test_case);
        $display("PASS ES_CHANNEL_SPEC CASE=%s vectors=%0d canonical_channels=6 alias=channel0 native_carrier=%0d",
            test_case,vectors,CARRIER_HZ);
        $finish;
    end
    initial begin repeat(5_000_000)@(posedge clk);$fatal(1,"channel watchdog CASE=%s",test_case);end
endmodule
