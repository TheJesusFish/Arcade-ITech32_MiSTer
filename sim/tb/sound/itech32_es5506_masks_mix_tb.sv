// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1fs

// ENSONIQ OTTO Rev2.3 https://gjcp.net/pdf/es5506.pdf, printed6,8,14,18-20,36-37.
// ROM-free host field masks and same-CA mixing through the actual voice engine.
// Reserved read bits are observed but not assigned manufacturer-defined values.
// Mixing vectors stay inside the signed23-bit guard range; no undocumented
// guard-overflow rule is invented. The optional CA diagnostic observes the
// scalar channel0 alias and contrasts hypothetical board mixing policies; the
// independent channels_spec test checks all six canonical stereo buses.
module itech32_es5506_masks_mix_tb;
    localparam integer CARRIER_HZ = 47_727_273;
    logic clk=0,reset=1,clock_enable=0,ce_16m=0;
    integer remainder=0;
    always #(500_000_000.0/CARRIER_HZ) clk=~clk;
    always @(negedge clk) begin
        ce_16m=0;
        if(reset || !clock_enable) remainder=0;
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
        .audio_left(audio_left),.audio_right(audio_right),.audio_strobe(audio_strobe),
        .irq(irq),.irq_vector(irq_vector),.current_page(current_page),
        .active_voices(active_voices),.scan_voice(scan_voice),.engine_busy(engine_busy)
    );
    always @(posedge clk) begin
        sample_ack<=0;
        if(reset || !sample_req)sample_served<=0;
        else if(!sample_served || sample_signature!={sample_bank,sample_addr})begin
            sample_served<=1;sample_signature<={sample_bank,sample_addr};sample_ack<=1;
        end
    end

    string test_case="masks";
    integer vectors=0,mask_checks=0,reserved_nonzero_reads=0;
    integer expected_voices=5,frames=0,frame_writes=0;
    integer carriers=0,input_ticks=0,frame_origin=0,frames_launched=0,output_lag=-1;
    integer expected_left=0,expected_right=0,observed_left=0,observed_right=0;
    logic check_scan=0,check_pcm=1,check_running_envelope=0;
    logic [31:0] written_voices=0;
    integer env_history[0:5];
    integer env_lvol,env_rvol,env_k1,env_k2,env_count;

    function automatic longint signed floor_div(input longint signed n,input longint signed d);
        if(n>=0)return n/d;
        return -((-n+d-1)/d);
    endfunction
    function automatic integer pan(input integer signed value,input integer volume);
        longint signed denominator;
        denominator=32*(64'd1<<(15-volume/4096));
        return integer'(floor_div(longint'(value)*(256+(volume/16)%256),denominator));
    endfunction
    function automatic integer rail20(input longint signed n);
        if(n>524287)return 524287;
        if(n< -524288)return -524288;
        return integer'(n);
    endfunction
    function automatic integer bounded_ramp(input integer value,input integer increment);
        if(value+increment<0)return 0;
        if(value+increment>65535)return 65535;
        return value+increment;
    endfunction
    function automatic integer lowpass(input integer x,input integer old_y,input integer k);
        // Filter division follows the compatibility model's truncation to zero.
        return old_y+integer'(longint'(x-old_y)*k/4096);
    endfunction
    task automatic advance_running_envelope;
        integer p1,p2,p3,p4;
        // Chosen sample ordering: oldK drives this filter evaluation, while
        // updated volume drives this sample's pan. This is an implementation
        // phase interpretation, not a pin-exact manufacturer collision claim.
        p1=lowpass(0,env_history[0],env_k1/16);
        p2=lowpass(p1,env_history[1],env_k1/16);
        p3=lowpass(p2,env_history[3],env_k1/16);
        p4=lowpass(p3,env_history[5],env_k2/16);
        if(env_count!=0)begin
            env_count--;
            env_lvol=bounded_ramp(env_lvol,127);
            env_rvol=bounded_ramp(env_rvol,-128);
            env_k1=bounded_ramp(env_k1,64);
            env_k2=bounded_ramp(env_k2,127);
        end
        assert($signed(dut.voice_write_data.o1n1)==p1 &&
            $signed(dut.voice_write_data.o2n1)==p2 &&
            $signed(dut.voice_write_data.o2n2)==env_history[1] &&
            $signed(dut.voice_write_data.o3n1)==p3 &&
            $signed(dut.voice_write_data.o3n2)==env_history[3] &&
            $signed(dut.voice_write_data.o4n1)==p4)
            else $fatal(1,"running envelope filter used wrong coefficient phase");
        assert(dut.voice_write_data.lvol==env_lvol && dut.voice_write_data.rvol==env_rvol &&
            dut.voice_write_data.k1==env_k1 && dut.voice_write_data.k2==env_k2 && dut.voice_write_data.ecount==env_count)
            else $fatal(1,"running envelope row commit mismatch");
        assert(dut.voice_write_data.accum==0 && dut.voice_write_data.control==16'h0300)
            else $fatal(1,"running envelope contaminated FC0 address/control");
        env_history[0]=p1;env_history[2]=env_history[1];env_history[1]=p2;
        env_history[4]=env_history[3];env_history[3]=p3;env_history[5]=p4;
        expected_left=pan(integer'(floor_div(p4,2)),env_lvol);
        expected_right=pan(integer'(floor_div(p4,2)),env_rvol);
    endtask

    // Read-only observation counts actual architectural voice commits. The
    // output check is external PCM; cadence is independently derived from CE.
    always @(posedge clk) begin
        if(reset)begin
            frames=0;frame_writes=0;written_voices=0;carriers=0;input_ticks=0;
            frame_origin=0;frames_launched=0;output_lag=-1;
        end else begin
            carriers++;
            if(check_scan && dut.voice_write_en && !dut.host_write_execute_pending)begin
                assert(dut.voice_write_addr<expected_voices)
                    else $fatal(1,"commit outside ACTV voice=%0d N=%0d",dut.voice_write_addr,expected_voices);
                assert(!written_voices[dut.voice_write_addr])
                    else $fatal(1,"duplicate voice contribution %0d",dut.voice_write_addr);
                written_voices[dut.voice_write_addr]=1;
                frame_writes++;
                if(check_running_envelope && dut.voice_write_addr==0)advance_running_envelope();
            end
            if(clock_enable && ce_16m)begin
                input_ticks++;
                if(input_ticks%(16*expected_voices)==0)begin frame_origin=carriers;frames_launched++;end
            end
            #0.001;
            if(check_scan && audio_strobe)begin
                assert(!dut.scan_underrun)else $fatal(1,"mix setup did not prime actual running voices");
                assert(frame_writes==expected_voices)
                    else $fatal(1,"missing voice contribution expected=%0d actual=%0d",expected_voices,frame_writes);
                assert(frames_launched==frames+1 && frame_origin!=0)
                    else $fatal(1,"missing/duplicate complete-scan output");
                if(output_lag<0)output_lag=carriers-frame_origin;
                else assert(carriers-frame_origin==output_lag)
                    else $fatal(1,"complete-scan output phase moved");
                if(check_pcm)assert($signed(audio_left)==expected_left && $signed(audio_right)==expected_right)
                    else $fatal(1,"MIX N=%0d expected=%0d/%0d actual=%0d/%0d frame=%0d",expected_voices,
                        expected_left,expected_right,$signed(audio_left),$signed(audio_right),frames);
                observed_left=$signed(audio_left);observed_right=$signed(audio_right);
                frames++;frame_writes=0;written_voices=0;
            end
        end
    end

    task automatic transfer(input logic wr,input logic [5:0] address,
        input logic [7:0] value,output logic [7:0] result);
        integer timeout;
        @(negedge clk);#0.002;host_req=1;host_write=wr;host_addr=address;host_wdata=value;
        timeout=0;
        do begin @(posedge clk);#0.002;timeout++;end while(!host_ack && timeout<100);
        assert(host_ack)else $fatal(1,"mask/mix host timeout %h",address);
        result=host_rdata;
        repeat(2)begin @(posedge clk);#0.002;assert(!host_ack)else $fatal(1,"duplicate held host ACK");end
        @(negedge clk);#0.002;host_req=0;
        repeat(2)@(posedge clk);#0.002;
    endtask
    task automatic write_reg(input logic [3:0] slot,input logic [31:0] value);
        logic [7:0] ignored;
        for(integer b=0;b<4;b++)transfer(1,{slot,2'(b)},value[31-b*8 -:8],ignored);
    endtask
    task automatic read_reg(input logic [3:0] slot,output logic [31:0] value);
        for(integer b=0;b<4;b++)transfer(0,{slot,2'(b)},0,value[31-b*8 -:8]);
    endtask
    task automatic reset_dut(input integer actv);
        check_scan=0;clock_enable=0;check_pcm=1;check_running_envelope=0;
        @(negedge clk);#0.002;reset=1;host_req=0;
        repeat(5)@(negedge clk);#0.002;reset=0;
        repeat(5)@(negedge clk);
        expected_voices=actv+1;
        write_reg(4'hb,32'(actv));
    endtask
    function automatic logic [31:0] field_mask(input logic high_page,input integer slot);
        if(high_page)begin
            case(slot)
                0:return 32'h0000ffff;
                1:return 32'hfffff800;
                2:return 32'hffffff80;
                3:return 32'hffffffff;
                default:return 32'h0003ffff;
            endcase
        end else begin
            case(slot)
                1:return 32'h0001ffff;
                3,5:return 32'h0000ff00;
                6:return 32'h000001ff;
                8,10:return 32'h0000ff01;
                default:return 32'h0000ffff;
            endcase
        end
    endfunction
    function automatic integer selected_voice(input integer i);
        case(i)0:return 0;1:return 15;2:return 16;default:return 31;endcase
    endfunction
    task automatic expect_mask(input logic [3:0] slot,input logic [31:0] mask,
        input logic [31:0] expected);
        logic [31:0] actual;
        read_reg(slot,actual);
        assert((actual&mask)==(expected&mask))
            else $fatal(1,"HOST FIELD page=%h slot=%h mask=%h expected=%h actual=%h",current_page,slot,mask,expected,actual);
        // X-marked map fields are intentionally not assigned golden read values.
        if((actual&~mask)!=0)reserved_nonzero_reads++;
        mask_checks++;
    endtask
    task automatic masks_case;
        logic [31:0] mask,value,par_discard;
        logic [31:0] shadow[0:3][0:1][0:10];
        reset_dut(4);
        // Walk all32 write bits, including excluded bits, through each voice
        // field. This checks retention/alias behavior without defining X reads.
        for(integer page=0;page<2;page++)begin
            write_reg(4'hf,32'(page*32));
            for(integer slot=0;slot<(page==0 ? 11:10);slot++)begin
                mask=field_mask(1'(page),slot);
                for(integer b=0;b<32;b++)begin
                    value=32'd1<<b;
                    write_reg(4'(slot),value);expect_mask(4'(slot),mask,value);
                end
                write_reg(4'(slot),32'hffffffff);expect_mask(4'(slot),mask,32'hffffffff);
            end
        end
        // Program four separated voices, then verify only after all are written
        // so truncating PAGE voice selection cannot accidentally pass locally.
        for(integer i=0;i<4;i++)for(integer page=0;page<2;page++)begin
            write_reg(4'hf,32'(selected_voice(i)+32*page));
            for(integer slot=0;slot<(page==0 ? 11:10);slot++)begin
                value=32'ha56f39c7^(32'(i)*32'h1834e927)^(32'(slot)*32'h4a17b369)^(32'(page)*32'h691bf403);
                shadow[i][page][slot]=value;
                if(slot==0)shadow[i][1-page][0]=value; // CR aliases low/high page
                write_reg(4'(slot),value);
            end
        end
        for(integer i=0;i<4;i++)for(integer page=0;page<2;page++)begin
            write_reg(4'hf,32'(selected_voice(i)+32*page));
            for(integer slot=0;slot<(page==0 ? 11:10);slot++)
                expect_mask(4'(slot),field_mask(1'(page),slot),shadow[i][page][slot]);
        end
        // Common fields are shared among their documented page class, not
        // voice-local. Invalid ACTV values are mask-only with CE disabled.
        for(integer b=0;b<32;b++)begin
            value=32'd1<<b;
            write_reg(4'hf,0);write_reg(4'hb,value);write_reg(4'hc,value);
            write_reg(4'hf,31);expect_mask(4'hb,32'h1f,value);expect_mask(4'hc,32'h1f,value);
            write_reg(4'hf,32);write_reg(4'ha,value);write_reg(4'hb,value);write_reg(4'hc,value);
            write_reg(4'hf,63);expect_mask(4'ha,32'h7f,value);expect_mask(4'hb,32'h7f,value);expect_mask(4'hc,32'h7f,value);
            // All seven defined PAGE bits retain. Values outside 00..40 are
            // storage checks only, not claims about undocumented page aliases.
            write_reg(4'hf,value);expect_mask(4'hf,32'h7f,value);
        end
        // PAR is a read-only converter result shared by every page class.  Its
        // RESB value is not specified, so discard one read: that documented
        // operation selects 3ff before beginning the next conversion.  With CE
        // stopped and the comparator inactive, the following page reads must
        // retain that saturated result.  Dedicated PAR benches cover timing.
        write_reg(4'hf,32'd0);read_reg(4'hd,par_discard);
        for(integer p=0;p<3;p++)begin
            write_reg(4'hf,32'(p*32));expect_mask(4'hd,32'h3ff,32'h3ff);
        end
        vectors++;
    endtask

    task automatic program_voice(input integer v,input logic running,
        input integer signed sample_value,input integer lvol,input integer rvol,input integer ca);
        write_reg(4'hf,32'(v+32));
        write_reg(4'h1,0);write_reg(4'h2,32'h00100000);write_reg(4'h3,0);
        for(integer slot=4;slot<=9;slot++)write_reg(4'(slot),slot==4 ? 32'(sample_value*2):0);
        write_reg(4'hf,32'(v));
        write_reg(4'h1,0);write_reg(4'h6,0);write_reg(4'h7,0);write_reg(4'h9,0);
        write_reg(4'h2,32'(lvol));write_reg(4'h4,32'(rvol));
        write_reg(4'h0,32'h300|32'(ca*1024)|(running ? 32'd0:32'd3));
    endtask
    task automatic run_scans(input integer count);
        integer timeout;
        // Populate synthetic caches before native measurement. No scan is
        // discarded as warmup; every actual output and every voice is checked.
        repeat(8000)@(negedge clk);
        check_scan=1;clock_enable=1;timeout=0;
        while(frames<count && timeout<50000)begin @(negedge clk);#0.002;timeout++;end
        assert(frames==count)else $fatal(1,"mix full-scan timeout");
        clock_enable=0;check_scan=0;
    endtask
    task automatic mix_vector(input integer actv,input integer pattern);
        integer value,lv,rv;
        logic running;
        longint signed sum_l,sum_r;
        reset_dut(actv);sum_l=0;sum_r=0;
        for(integer v=0;v<=actv;v++)begin
            lv=16'hf000;rv=16'heab0;running=1;
            case(pattern)
                0:begin value=0;running=0;end
                1:begin value=123;running=(v==0);end
                2:value=(v+1)*17-93;
                3:begin value=v%2==0 ? 8192:-8192;if(v==actv && actv%2==0)value=0;end
                4:value=8192;
                default:value=-8192;
            endcase
            program_voice(v,running,value,lv,rv,0);
            if(running)begin sum_l+=pan(value,lv);sum_r+=pan(value,rv);end
        end
        assert(sum_l>=-4194304 && sum_l<=4194303 && sum_r>=-4194304 && sum_r<=4194303)
            else $fatal(1,"test accidentally depends on undocumented23-bit accumulator overflow");
        expected_left=rail20(sum_l);expected_right=rail20(sum_r);
        run_scans(3);
        $display("PASS SAME_CA_MIX ACTV=%0d pattern=%0d sum=%0d/%0d PCM=%0d/%0d frames=%0d lag=%0d",
            actv,pattern,sum_l,sum_r,observed_left,observed_right,frames,output_lag);
        vectors++;
    endtask
    task automatic ca_diagnostic;
        integer all_left,split_left;
        // CA0 positive pair clips separately on the documented chip, while
        // CA1 negative voice can cancel it only at a later board mixing stage.
        // An equal-weight post-rail sum is illustrative, NOT asserted wiring.
        for(integer split=0;split<2;split++)begin
            reset_dut(4);
            for(integer v=0;v<5;v++)
                program_voice(v,v<3,v==2 ? -32768:32767,16'hfff0,16'hfff0,(split!=0 && v==2) ? 1:0);
            check_pcm=0;run_scans(3);
            if(split==0)all_left=observed_left;else split_left=observed_left;
        end
        $display("DIAG SCALAR_CA0 sameCA_PCM=%0d splitCA_PCM=%0d hypothetical_wide_fold=%0d hypothetical_post_channel_rail_sum=%0d",
            all_left,split_left,rail20(2*pan(32767,16'hfff0)+pan(-32768,16'hfff0)),
            rail20(2*pan(32767,16'hfff0))+rail20(pan(-32768,16'hfff0)));
        for(integer ca=0;ca<6;ca++)begin
            reset_dut(4);
            for(integer v=0;v<5;v++)program_voice(v,v==0,1234,16'hf000,16'heab0,ca);
            check_pcm=0;run_scans(2);
            $display("DIAG SCALAR_CA0 CA=%0d observed=%0d/%0d",ca,observed_left,observed_right);
        end
        vectors++;
    endtask
    task automatic running_envelope_case;
        logic [3:0] slot;
        reset_dut(4);
        for(integer v=0;v<5;v++)program_voice(v,v==0,0,16'h9ff0,16'ha010,0);
        env_history[0]=20001;env_history[1]=10003;env_history[2]=8005;
        env_history[3]=7007;env_history[4]=6009;env_history[5]=30011;
        env_lvol=16'h9ff0;env_rvol=16'ha010;env_k1=16'h8000;env_k2=16'h4000;env_count=5;
        write_reg(4'hf,32'h20);
        for(integer i=0;i<6;i++)begin
            case(i)0:slot=9;1:slot=7;2:slot=8;3:slot=5;4:slot=6;default:slot=4;endcase
            write_reg(slot,32'(env_history[i]));
        end
        write_reg(4'hf,0);
        write_reg(4'h9,32'(env_k1));write_reg(4'h7,32'(env_k2));
        write_reg(4'h3,32'h00007f00);write_reg(4'h5,32'h00008000);
        write_reg(4'ha,32'h00004000);write_reg(4'h8,32'h00007f00);write_reg(4'h6,32'(env_count));
        check_running_envelope=1;run_scans(7);check_running_envelope=0;
        // Architectural observation after continuous measured execution.
        expect_mask(4'h2,32'hffff,32'(env_lvol));expect_mask(4'h4,32'hffff,32'(env_rvol));
        expect_mask(4'h9,32'hffff,32'(env_k1));expect_mask(4'h7,32'hffff,32'(env_k2));
        expect_mask(4'h6,32'h1ff,32'd0);
        write_reg(4'hf,32'h20);
        for(integer i=0;i<6;i++)begin
            case(i)0:slot=9;1:slot=7;2:slot=8;3:slot=5;4:slot=6;default:slot=4;endcase
            expect_mask(slot,32'h3ffff,32'(env_history[i]));
        end
        $display("PASS RUNNING_ENVELOPE_ORDER frames=%0d LVOL=%0d RVOL=%0d K1=%0d K2=%0d phase_policy=INTERPRETED_OLD_K_NEW_VOLUME",
            frames,env_lvol,env_rvol,env_k1,env_k2);
        vectors++;
    endtask
    initial begin
        integer actv;
        void'($value$plusargs("CASE=%s",test_case));
        if(test_case=="masks")masks_case();
        else if(test_case=="mix")begin
            for(integer a=0;a<5;a++)begin
                case(a)0:actv=4;1:actv=7;2:actv=15;3:actv=23;default:actv=31;endcase
                for(integer pattern=0;pattern<6;pattern++)mix_vector(actv,pattern);
            end
        end else if(test_case=="ca-diagnostic")ca_diagnostic();
        else if(test_case=="running-envelope")running_envelope_case();
        else $fatal(1,"unknown masks/mix CASE=%s",test_case);
        $display("PASS ES_MASKS_MIX CASE=%s vectors=%0d mask_checks=%0d reserved_nonzero_reads=%0d native_carrier=%0d",
            test_case,vectors,mask_checks,reserved_nonzero_reads,CARRIER_HZ);
        $finish;
    end
    initial begin repeat(5_000_000)@(posedge clk);$fatal(1,"masks/mix watchdog CASE=%s",test_case);end
endmodule
