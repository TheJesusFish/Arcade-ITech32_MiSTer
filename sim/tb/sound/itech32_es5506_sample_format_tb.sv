// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1fs

// Actual-engine sample-format checks, using synthetic ROM words only.
// ENSONIQ OTTO Rev2.3 section11.2 (printed30): https://gjcp.net/pdf/es5506.pdf
// Every compressed-bus bit is significant, and BOTH adjacent samples are
// decompressed before interpolation. The inverse compression endpoint, signed
// floor and compressed reconstruction are explicit interpretations. Filter
// histories retain signed32 guards and filter division truncates toward zero;
// those choices are compatibility evidence, not measured silicon behavior.
module itech32_es5506_sample_format_tb;
    localparam integer CARRIER_HZ = 47_727_273;
    logic clk=0,reset=1,clock_enable=0,ce_16m=0;
    integer phase_remainder=0;
    always #(500_000_000.0/CARRIER_HZ) clk=~clk;
    always @(negedge clk) begin
        ce_16m=0;
        if(reset || !clock_enable) phase_remainder=0;
        else begin
            phase_remainder+=16_000_000;
            if(phase_remainder>=CARRIER_HZ)begin
                phase_remainder-=CARRIER_HZ;ce_16m=1;
            end
        end
    end
    logic host_req=0,host_write=0,host_ack;
    logic [5:0] host_addr=0;
    logic [7:0] host_wdata=0,host_rdata;
    logic sample_req,sample_ack=0,sample_companded,sample_served=0;
    logic [1:0] sample_bank;
    logic [21:0] sample_addr;
    logic [4:0] sample_voice;
    logic [15:0] sample_rdata=0;
    logic [23:0] sample_signature=0;
    logic signed [19:0] audio_left,audio_right;
    logic [119:0] audio_left_channels,audio_right_channels;
    logic audio_strobe,irq,engine_busy;
    logic [7:0] irq_vector;
    logic [6:0] current_page;
    logic [4:0] active_voices,scan_voice;
    logic [15:0] raw_word [0:3][0:1];
    integer fetches=0,bank_fetches[0:3];
    itech32_es5506 dut(
        .clk(clk),.reset(reset),.ce_16m(ce_16m),
        .host_req(host_req),.host_write(host_write),.host_addr(host_addr),
        .host_wdata(host_wdata),.host_rdata(host_rdata),.host_ack(host_ack),
		.par_comparator_tripped(1'b0),.par_discharge(),
		.sample_req(sample_req),.sample_bank(sample_bank),
        .sample_addr(sample_addr),.sample_companded(sample_companded),
        .sample_voice(sample_voice),.sample_rdata(sample_rdata),.sample_ack(sample_ack),
        .audio_left(audio_left),.audio_right(audio_right),
        .audio_left_channels(audio_left_channels),.audio_right_channels(audio_right_channels),
        .audio_strobe(audio_strobe),.irq(irq),.irq_vector(irq_vector),
        .current_page(current_page),.active_voices(active_voices),
        .scan_voice(scan_voice),.engine_busy(engine_busy)
    );
    // The synthetic ROM ignores CMPD: decompression belongs inside the chip.
    // Distinct bank payloads expose missing bank bits in warm cache identity.
    always @(posedge clk)begin
        sample_ack<=0;
        if(reset)begin
            sample_served<=0;fetches<=0;
            for(integer b=0;b<4;b++)bank_fetches[b]<=0;
        end else if(!sample_req)sample_served<=0;
        else if(!sample_served || sample_signature!={sample_bank,sample_addr})begin
            sample_served<=1;sample_signature<={sample_bank,sample_addr};
            sample_rdata<=raw_word[sample_bank][sample_addr[1]];
            sample_ack<=1;fetches<=fetches+1;
            bank_fetches[sample_bank]<=bank_fetches[sample_bank]+1;
        end
    end

    function automatic longint signed floor_div(input longint signed n,input longint signed d);
        if(n>=0)return n/d;
        return -((-n+d-1)/d);
    endfunction
    function automatic integer signed wrap18(input longint signed n);
        longint signed r;
        r=n%262144;if(r<0)r+=262144;if(r>=131072)r-=262144;
        return integer'(r);
    endfunction
    function automatic integer signed signed16(input integer n);
        return n>=32768 ? n-65536 : n;
    endfunction
    // Invert the manual's leading-sign removal in integer arithmetic. For
    // exponent0 the retained13-bit mantissa includes its own sign. Otherwise
    // its top bit is the inverse of the removed sign. Keep the low bus bits;
    // do not replace them with an 8-bit code midpoint or telephony G.711 bias.
    function automatic integer signed expand(input logic [15:0] raw);
        integer e,m,n;
        e=integer'(raw)/8192;m=integer'(raw)%8192;
        if(e==0)begin
            n=m>=4096 ? m-8192 : m;
            return integer'(floor_div(n,16));
        end
        n=4*m-(m<4096 ? 32768 : 0);
        return integer'(floor_div(n,64'd1<<(7-e)));
    endfunction
    function automatic integer signed lowpass(input integer x,input integer y);
        return integer'(longint'(y)+longint'(x-y)*4095/4096);
    endfunction
    function automatic integer signed pan(input integer o4,input integer volume);
        integer s;
        s=integer'(floor_div(o4,2));
        return integer'(floor_div(longint'(s)*(256+((volume/16)%256)),
            32*(64'd1<<(15-volume/4096))));
    endfunction
    function automatic integer signed clamp20(input integer signed value);
        if(value>524287)return 524287;
        if(value< -524288)return -524288;
        return value;
    endfunction

    logic [15:0] expected_control=16'h0300;
    logic [31:0] expected_accum=0;
    integer history[0:5];
    integer expected_left=0,expected_right=0;
    integer frames=0,commits=0,total_vectors=0,total_frames=0;
    integer low_bits_observed=0,format_toggles=0,bank_changes=0;
    logic check_engine=0;
    string test_case="formats";
    task automatic check_commit;
        integer bank,first_word,f,s0,s1,accepted_s1,interp,p1,p2,p3,p4;
        logic [15:0] r0,r1;
        bank=integer'(expected_control)/16384;
        first_word=integer'((expected_accum/2048)%2);
        r0=raw_word[bank][first_word];r1=raw_word[bank][1-first_word];
        s0=expected_control[13] ? expand(r0) : signed16(integer'(r0));
        s1=expected_control[13] ? expand(r1) : signed16(integer'(r1));
        f=integer'((expected_accum/4)%512);
        interp=wrap18(floor_div(longint'(s0)*(512-f)+longint'(s1)*f,256));
        // A boundary neighbor has zero mathematical contribution when the
        // upper-nine-bit fraction is0. Either the real raw neighbor (baseline)
        // or the already validated current raw word (zero-weight fast path)
        // is legal then. No other raw replacement is accepted; non-boundary
        // and nonzero-weight cases still require the actual second word.
        assert(dut.fetched_sample0==r0 &&
            (dut.fetched_sample1==r1 ||
             (expected_accum[12:11]==2'd3 && f==0 && dut.fetched_sample1==r0)))
            else $fatal(1,"raw neighbors CASE=%s bank=%0d expected=%h/%h got=%h/%h",
                test_case,bank,r0,r1,dut.fetched_sample0,dut.fetched_sample1);
        // Decode the independently qualified accepted payload; the output
        // oracle above deliberately retains s1 from the REAL authored pair.
        accepted_s1=expected_control[13] ? expand(dut.fetched_sample1)
            : signed16(integer'(dut.fetched_sample1));
        assert($signed(dut.decoded_sample0_reg)==s0 && $signed(dut.decoded_sample1_reg)==accepted_s1)
            else $fatal(1,"both-neighbor decode ctrl=%h raw=%h/%h expected=%0d/%0d got=%0d/%0d",
                expected_control,r0,r1,s0,accepted_s1,$signed(dut.decoded_sample0_reg),$signed(dut.decoded_sample1_reg));
        assert($signed(dut.interpolated_sample_reg)==interp)
            else $fatal(1,"decode-before-interpolate expected=%0d actual=%0d f=%0d",interp,$signed(dut.interpolated_sample_reg),f);
        if(expected_control[13] && (r0[7:0]!=0 || r1[7:0]!=0))low_bits_observed++;
        p1=lowpass(interp,history[0]);p2=lowpass(p1,history[1]);
        p3=lowpass(p2,history[3]);p4=lowpass(p3,history[5]);
        assert($signed(dut.voice_write_data.o1n1)==p1 && $signed(dut.voice_write_data.o2n1)==p2 &&
               $signed(dut.voice_write_data.o2n2)==history[1] && $signed(dut.voice_write_data.o3n1)==p3 &&
               $signed(dut.voice_write_data.o3n2)==history[3] && $signed(dut.voice_write_data.o4n1)==p4)
            else $fatal(1,"sample-format filter histories failed CASE=%s vector=%0d",test_case,total_vectors);
        assert(dut.voice_write_data.accum==expected_accum && dut.voice_write_data.control==expected_control)
            else $fatal(1,"sample-format ACCUM/control changed unexpectedly");
        history[0]=p1;history[2]=history[1];history[1]=p2;
        history[4]=history[3];history[3]=p3;history[5]=p4;
        expected_left=pan(p4,16'hf000);expected_right=pan(p4,16'heab0);
        assert($signed(dut.voice_mix_left_reg)==expected_left && $signed(dut.voice_mix_right_reg)==expected_right)
            else $fatal(1,"sample-format panning failed");
        commits++;
    endtask
    always @(posedge clk)begin
        if(reset)begin frames=0;commits=0;end
        else begin
            if(check_engine && dut.voice_write_en && !dut.host_write_execute_pending && dut.voice_write_addr==0)
                check_commit();
            #0.001;
            if(check_engine)begin
                assert(!dut.sample_underrun)else $fatal(1,"sample-format test suffered real cache underrun");
                if(audio_strobe)begin
                    assert(commits==frames+1)else $fatal(1,"missing/duplicate voice0 processing");
                    assert($signed(audio_left)==clamp20(expected_left) &&
                           $signed(audio_right)==clamp20(expected_right))
                        else $fatal(1,"PCM CASE=%s expected=%0d/%0d actual=%0d/%0d",test_case,
                            expected_left,expected_right,$signed(audio_left),$signed(audio_right));
                    assert(audio_left_channels[119:20]==0 && audio_right_channels[119:20]==0)
                        else $fatal(1,"sample voice escaped channel0");
                    frames++;total_frames++;
                end
            end
        end
    end

    task automatic transfer(input logic wr,input logic[5:0]addr,input logic[7:0]data,output logic[7:0]result);
        integer timeout;
        @(negedge clk);#0.002;host_req=1;host_write=wr;host_addr=addr;host_wdata=data;
        timeout=0;
        do begin @(posedge clk);#0.002;timeout++;end while(!host_ack && timeout<100);
        assert(host_ack)else $fatal(1,"sample-format host timeout");result=host_rdata;
        @(negedge clk);#0.002;host_req=0;repeat(2)@(posedge clk);#0.002;
    endtask
    task automatic write_reg(input logic[3:0]slot,input logic[31:0]value);
        logic[7:0]ignored;
        for(integer b=0;b<4;b++)transfer(1,{slot,2'(b)},value[31-b*8 -:8],ignored);
    endtask
    task automatic read_reg(input logic[3:0]slot,output logic[31:0]value);
        for(integer b=0;b<4;b++)transfer(0,{slot,2'(b)},0,value[31-b*8 -:8]);
    endtask
    function automatic logic[3:0]history_slot(input integer i);
        case(i)0:return 9;1:return 7;2:return 8;3:return 5;4:return 6;default:return 4;endcase
    endfunction
    task automatic readback;
        logic[31:0]value;
        write_reg(15,32'h20);
        for(integer i=0;i<6;i++)begin
            read_reg(history_slot(i),value);
            assert(value=={14'd0,18'(history[i])})else $fatal(1,"sample-format host history i=%0d",i);
        end
        read_reg(3,value);assert(value==expected_accum)else $fatal(1,"host ACCUM mismatch");
        read_reg(0,value);assert(value=={16'd0,expected_control})else $fatal(1,"host CR mismatch");
    endtask
    task automatic warm_prefetch;
        repeat(1800)@(negedge clk);#0.002;
        assert(!sample_req)else $fatal(1,"prefetch did not reach a warm idle state");
    endtask
    task automatic reset_program;
        check_engine=0;clock_enable=0;
        @(negedge clk);#0.002;reset=1;host_req=0;
        repeat(5)@(negedge clk);#0.002;reset=0;
        repeat(4)@(negedge clk);
        for(integer i=0;i<6;i++)history[i]=0;
        write_reg(11,4);write_reg(15,32'h20);
        write_reg(1,0);write_reg(2,32'h01000000);write_reg(3,expected_accum);
        write_reg(15,0);write_reg(1,0);write_reg(6,0);
        write_reg(2,32'hf000);write_reg(4,32'heab0);
        write_reg(9,32'hfff0);write_reg(7,32'hfff0);
        write_reg(0,{16'd0,expected_control});warm_prefetch();
    endtask
    task automatic run_frames(input integer count);
        integer target,timeout;
        target=frames+count;timeout=0;check_engine=1;clock_enable=1;
        while(frames<target && timeout<20000)begin @(negedge clk);#0.002;timeout++;end
        assert(frames==target)else $fatal(1,"sample-format frame timeout");
        clock_enable=0;check_engine=0;
        readback();total_vectors++;
    endtask
    task automatic change_control(input logic[15:0]value);
        write_reg(15,0);write_reg(0,{16'd0,value});expected_control=value;
    endtask
    task automatic set_patterns(input integer exponent,input integer sign_bit);
        for(integer b=0;b<4;b++)begin
            // Different exponent/sign in the upper neighbor makes a decode of
            // the already interpolated raw word observably incorrect.
            raw_word[b][0]=16'(exponent*8192+sign_bit*4096+16'h135+b*16'h219);
            raw_word[b][1]=16'(((exponent+3)%8)*8192+(1-sign_bit)*4096+16'h2cb+b*16'h183);
        end
    endtask
    function automatic integer fraction(input integer i);
        case(i)0:return 0;1:return 1;2:return 255;default:return 511;endcase
    endfunction
    integer before_fetch,before_bank,bank;
    logic bank_visited[0:3];
    initial begin
        if($value$plusargs("CASE=%s",test_case))begin end
        // Independent anchors from the manual's printed31 compression ranges.
        assert(expand(16'h0000)==0 && expand(16'h0f00)==240 && expand(16'h1000)==-256 &&
               expand(16'h3000)==256 && expand(16'he000)==-32768 && expand(16'hff00)==31744 &&
               expand(16'hffff)==32764 && expand(16'he001)==-32764)
            else $fatal(1,"sample-format independent oracle anchors failed");
        if(test_case=="formats")begin
            for(integer e=0;e<8;e++)for(integer s=0;s<2;s++)begin
                set_patterns(e,s);
                for(integer b=0;b<4;b++)for(integer f=0;f<4;f++)
                for(integer crossing=0;crossing<2;crossing++)for(integer cmpd=0;cmpd<2;cmpd++)begin
                    expected_control=16'(16'h0300+b*16384+cmpd*8192);
                    expected_accum=32'((crossing ? 3 : 0)*2048+fraction(f)*4+f);
                    reset_program();run_frames(2);
                end
            end
        end else if(test_case=="warm-format")begin
            for(integer b=0;b<4;b++)begin
                set_patterns(7,0);expected_control=16'(16'h0300+b*16384);
                expected_accum=32'(3*2048+255*4+3);reset_program();run_frames(2);
                for(integer n=0;n<4;n++)begin
                    before_fetch=fetches;
                    change_control(expected_control^16'h2000);format_toggles++;
                    warm_prefetch();run_frames(2);
                    assert(fetches==before_fetch)else $fatal(1,"CMPD-only change unnecessarily refetched cached raw words");
                end
            end
        end else if(test_case=="warm-bank")begin
            for(integer cmpd=0;cmpd<2;cmpd++)begin
                set_patterns(5,1);expected_control=16'(16'h0300+cmpd*8192);
                expected_accum=32'(3*2048+511*4+1);reset_program();run_frames(2);
                for(integer b=0;b<4;b++)bank_visited[b]=0;
                bank_visited[0]=1;
                for(integer n=1;n<8;n++)begin
                    case(n)1:bank=1;2:bank=2;3:bank=3;4:bank=0;5:bank=3;6:bank=2;default:bank=1;endcase
                    before_bank=bank_fetches[bank];
                    change_control(16'(16'h0300+cmpd*8192+bank*16384));bank_changes++;
                    warm_prefetch();run_frames(2);
                    // The bank is now part of the direct-map index. The stopped
                    // programming prewarm may be interrupted by this fixture's
                    // immediate RUN write, so a bank's first visit may still
                    // fetch. Once visited, however, returning to it must use the
                    // exact resident payload without a stale-bank alias or new
                    // ROM transaction. run_frames/check_commit independently
                    // prove both raw words and the final arithmetic every time.
                    if(bank_visited[bank])
                        assert(bank_fetches[bank]==before_bank)
                            else $fatal(1,"resident bank switch unexpectedly refetched sample payload");
                    bank_visited[bank]=1;
                end
            end
        end else $fatal(1,"unknown sample-format CASE=%s",test_case);
        assert(low_bits_observed>0)else $fatal(1,"full-bus compressed stimulus was not exercised");
        $display("PASS ES_SAMPLE_FORMAT CASE=%s vectors=%0d frames=%0d compressed_full_bus_commits=%0d format_toggles=%0d bank_changes=%0d native_carrier=%0d",
            test_case,total_vectors,total_frames,low_bits_observed,format_toggles,bank_changes,CARRIER_HZ);
        $finish;
    end
    initial begin #500ms;$fatal(1,"sample-format watchdog CASE=%s vectors=%0d",test_case,total_vectors);end
endmodule
