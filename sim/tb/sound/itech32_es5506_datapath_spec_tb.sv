// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1fs

// End-to-end synthetic ES5506 checks, not calls to DUT arithmetic helpers.
// ENSONIQ OTTO Rev2.3: https://gjcp.net/pdf/es5506.pdf
// Printed p9 mode table is selected over the conflicting p34 mode2/3 diagram.
// The host exposes signed18 histories, while the compatibility datapath retains
// signed32 filter guards, truncates signed filter divisions toward zero, and
// carries the wide O4 result into panning. These internal details are supported
// by full-game differential evidence, not a measured-silicon accuracy claim.
module itech32_es5506_datapath_spec_tb;
    localparam integer CARRIER_HZ = 47_727_273;
    logic clk = 0, reset = 1, clock_enable = 0, ce_16m = 0;
    integer phase_remainder = 0;
    always #(500_000_000.0/CARRIER_HZ) clk = ~clk;
    always @(negedge clk) begin
        ce_16m = 0;
        if (reset || !clock_enable) phase_remainder = 0;
        else begin
            phase_remainder += 16_000_000;
            if (phase_remainder >= CARRIER_HZ) begin
                phase_remainder -= CARRIER_HZ;
                ce_16m = 1;
            end
        end
    end

    logic host_req = 0, host_write = 0, host_ack;
    logic [5:0] host_addr = 0;
    logic [7:0] host_wdata = 0, host_rdata;
    logic sample_req, sample_ack = 0, sample_companded;
    logic [1:0] sample_bank;
    logic [21:0] sample_addr;
    logic [4:0] sample_voice;
    logic [15:0] sample_rdata = 0;
    logic signed [19:0] audio_left,audio_right;
    logic audio_strobe,irq,engine_busy;
    logic [7:0] irq_vector;
    logic [6:0] current_page;
    logic [4:0] active_voices,scan_voice;
    integer rom_sample0 = -32768,rom_sample1 = 32767;
    logic sample_served = 0;
    logic pause_rom = 0;
    logic [23:0] sample_signature = 0;
    integer sample_fetches = 0;
    itech32_es5506 dut (
        .clk(clk),.reset(reset),.ce_16m(ce_16m),
        .host_req(host_req),.host_write(host_write),.host_addr(host_addr),
        .host_wdata(host_wdata),.host_rdata(host_rdata),.host_ack(host_ack),
		.par_comparator_tripped(1'b0),.par_discharge(),
		.sample_req(sample_req),.sample_bank(sample_bank),
        .sample_addr(sample_addr),.sample_companded(sample_companded),
        .sample_voice(sample_voice),.sample_rdata(sample_rdata),.sample_ack(sample_ack),
        .audio_left(audio_left),.audio_right(audio_right),.audio_strobe(audio_strobe),
        .irq(irq),.irq_vector(irq_vector),.current_page(current_page),
        .active_voices(active_voices),.scan_voice(scan_voice),.engine_busy(engine_busy)
    );
    always @(posedge clk) begin
        sample_ack <= 0;
        if (reset) begin sample_served <= 0; sample_fetches <= 0; end
        else if (!sample_req) sample_served <= 0;
        else if (!pause_rom && (!sample_served || sample_signature != {sample_bank,sample_addr})) begin
            sample_served <= 1;
            sample_signature <= {sample_bank,sample_addr};
            sample_rdata <= sample_addr[1] ? 16'(rom_sample1) : 16'(rom_sample0);
            sample_ack <= 1;
            sample_fetches <= sample_fetches + 1;
        end
    end

    // Independent integer-domain oracle. Interpolation and volume use floor;
    // filter divisions use language-defined truncation toward zero.
    function automatic longint signed floor_div(input longint signed n,input longint signed d);
        if (n >= 0) return n/d;
        return -((-n+d-1)/d);
    endfunction
    function automatic integer signed wrap18(input longint signed n);
        longint signed r;
        r = n % 262144;
        if (r < 0) r += 262144;
        if (r >= 131072) r -= 262144;
        return integer'(r);
    endfunction
    function automatic integer signed lp(input integer signed x,input integer signed y,input integer k);
        return integer'(longint'(y) + longint'(x-y)*k/4096);
    endfunction
    function automatic integer signed hp(input integer signed x,input integer signed previous,
        input integer signed y,input integer k);
        return integer'(longint'(x)-previous+longint'(y)*k/8192+longint'(y)/2);
    endfunction
    function automatic integer signed pan(input integer signed o4,input integer volume);
        integer signed sample_value;
        longint signed denominator;
        sample_value = integer'(floor_div(o4,2));
        denominator = 32 * (64'd1 << (15-(volume/4096)));
        return integer'(floor_div(longint'(sample_value)*(256+((volume/16)%256)),denominator));
    endfunction
    function automatic integer signed clamp20(input integer signed value);
        if (value > 524287) return 524287;
        if (value < -524288) return -524288;
        return value;
    endfunction

    // History order: O1(n-1), O2(n-1), O2(n-2), O3(n-1), O3(n-2), O4(n-1).
    integer signed history [0:5];
    integer raw_k1 = 0,raw_k2 = 0,left_volume = 16'hf000,right_volume = 16'heab0;
    logic [31:0] expected_accum = 0;
    logic [15:0] expected_control = 0;
    integer expected_interp = 0,expected_left = 0,expected_right = 0;
    integer commits = 0,frames = 0,total_vectors = 0;
    logic check_engine = 0;
    string test_case = "filters";

    task automatic advance_oracle;
        integer f,p1,p2,p3,p4,mode;
        assert (dut.voice_write_data.control == expected_control)
            else $fatal(1,"CONTROL changed unexpectedly expected=%h actual=%h CASE=%s",expected_control,dut.voice_write_data.control,test_case);
        f = integer'((expected_accum/4)%512);
        if ((expected_control & 3) != 0) expected_interp = 0;
        else expected_interp = wrap18(floor_div(longint'(rom_sample0)*(512-f)+longint'(rom_sample1)*f,256));
        p1 = lp(expected_interp,history[0],raw_k1/16);
        p2 = lp(p1,history[1],raw_k1/16);
        mode = integer'((expected_control/256)%4);
        case(mode)
            0:p3 = hp(p2,history[2],history[3],raw_k2/16);
            2:p3 = lp(p2,history[3],raw_k2/16);
            default:p3 = lp(p2,history[3],raw_k1/16);
        endcase
        if (mode < 2) p4 = hp(p3,history[4],history[5],raw_k2/16);
        else p4 = lp(p3,history[5],raw_k2/16);
        assert ($signed(dut.interpolated_sample_reg) == expected_interp)
            else $fatal(1,"INTERP expected=%0d actual=%0d accum=%h",expected_interp,$signed(dut.interpolated_sample_reg),expected_accum);
        assert ($signed(dut.voice_write_data.o1n1) == p1 &&
                $signed(dut.voice_write_data.o2n1) == p2 &&
                $signed(dut.voice_write_data.o2n2) == history[1] &&
                $signed(dut.voice_write_data.o3n1) == p3 &&
                $signed(dut.voice_write_data.o3n2) == history[3] &&
                $signed(dut.voice_write_data.o4n1) == p4)
            else $fatal(1,"FILTER mode=%0d expected=%0d/%0d/%0d/%0d actual=%0d/%0d/%0d/%0d",
                mode,p1,p2,p3,p4,$signed(dut.voice_write_data.o1n1),$signed(dut.voice_write_data.o2n1),
                $signed(dut.voice_write_data.o3n1),$signed(dut.voice_write_data.o4n1));
        assert (dut.voice_write_data.accum == expected_accum)
            else $fatal(1,"ACCUM changed with zero FC or STOP1 expected=%h actual=%h",expected_accum,dut.voice_write_data.accum);
        history[0]=p1; history[2]=history[1]; history[1]=p2;
        history[4]=history[3]; history[3]=p3; history[5]=p4;
        if ((expected_control & 3) != 0) begin expected_left=0; expected_right=0; end
        else begin expected_left=pan(p4,left_volume); expected_right=pan(p4,right_volume); end
        assert ($signed(dut.voice_mix_left_reg) == expected_left && $signed(dut.voice_mix_right_reg) == expected_right)
            else $fatal(1,"PAN expected=%0d/%0d actual=%0d/%0d O4=%0d",expected_left,expected_right,
                $signed(dut.voice_mix_left_reg),$signed(dut.voice_mix_right_reg),p4);
    endtask

    always @(posedge clk) begin
        if (reset) begin commits=0; frames=0; end
        else begin
            if (check_engine && dut.voice_write_en && !dut.host_write_execute_pending && dut.voice_write_addr == 0) begin
                advance_oracle();
                commits++;
            end
            #0.001;
            if (check_engine && audio_strobe) begin
                assert (commits != 0) else $fatal(1,"no actual voice processing before output");
                assert ($signed(audio_left)==clamp20(expected_left) &&
                        $signed(audio_right)==clamp20(expected_right))
                    else $fatal(1,"PCM expected=%0d/%0d actual=%0d/%0d",expected_left,expected_right,$signed(audio_left),$signed(audio_right));
                frames++;
            end
        end
    end

    task automatic transfer(input logic wr,input logic [5:0] address,input logic [7:0] value,
        output logic [7:0] result);
        integer timeout;
        @(negedge clk); #0.002;
        host_req=1;host_write=wr;host_addr=address;host_wdata=value;
        timeout=0;
        do begin @(posedge clk); #0.002; timeout++; end while(!host_ack && timeout<100);
        assert(host_ack) else $fatal(1,"datapath host timeout %h",address);
        result=host_rdata;
        @(negedge clk); #0.002;host_req=0;
        repeat(2)@(posedge clk);#0.002;
    endtask
    task automatic write_reg(input logic [3:0] slot,input logic [31:0] value);
        logic [7:0] ignored;
        for(integer b=0;b<4;b++)transfer(1,{slot,2'(b)},value[31-b*8 -:8],ignored);
    endtask
    task automatic read_reg(input logic [3:0] slot,output logic [31:0] value);
        for(integer b=0;b<4;b++)transfer(0,{slot,2'(b)},0,value[31-b*8 -:8]);
    endtask
    function automatic logic [3:0] history_slot(input integer i);
        case(i)0:return 9;1:return 7;2:return 8;3:return 5;4:return 6;default:return 4;endcase
    endfunction
    task automatic readback_histories;
        logic [31:0] value;
        write_reg(4'hf,32'h20);
        for(integer i=0;i<6;i++)begin
            read_reg(history_slot(i),value);
            assert(value=={14'd0,18'(history[i])})else $fatal(1,"HISTORY host readback i=%0d expected=%h actual=%h",i,18'(history[i]),value);
        end
        read_reg(4'h3,value);
        assert(value==expected_accum)else $fatal(1,"ACCUM host readback mismatch");
        read_reg(4'h0,value);
        assert(value=={16'd0,expected_control})else $fatal(1,"CONTROL host readback mismatch");
    endtask

    task automatic reset_and_program(input logic equal_endpoints,input logic [16:0] frequency);
        check_engine=0;clock_enable=0;
        @(negedge clk);#0.002;reset=1;host_req=0;
        repeat(5)@(negedge clk);#0.002;reset=0;
        repeat(4)@(negedge clk);
        write_reg(4'hb,32'd4);
        write_reg(4'hf,32'h20);
        write_reg(4'h1,32'd0);
        write_reg(4'h2,equal_endpoints ? 32'd0 : 32'h00100000);
        write_reg(4'h3,expected_accum);
        for(integer i=0;i<6;i++)write_reg(history_slot(i),{14'd0,18'(history[i])});
        write_reg(4'hf,32'd0);
        write_reg(4'h1,{15'd0,frequency});write_reg(4'h6,32'd0);
        write_reg(4'h2,32'(left_volume));write_reg(4'h4,32'(right_volume));
        write_reg(4'h9,32'(raw_k1));write_reg(4'h7,32'(raw_k2));
        write_reg(4'h0,{16'd0,expected_control});
        // Complete cache initialization/prefetch while the device clock has not
        // started. This is configuration, not an artificially slowed voice slot.
        repeat(1800)@(negedge clk);
    endtask
    task automatic execute_frames(input integer count,input logic expect_fetch);
        integer timeout,fetches_before;
        fetches_before=sample_fetches;
        check_engine=1;clock_enable=1;timeout=0;
        while(frames<count && timeout<10000)begin @(negedge clk);#0.002;timeout++;end
        assert(frames==count && commits>=count)else $fatal(1,"engine did not process requested frames");
        // Stop the clock only after the measured full-scan output. This permits
        // stable architectural host readback without altering measured execution.
        clock_enable=0;check_engine=0;
        if(expect_fetch)assert(sample_fetches>0)else $fatal(1,"running voice fetched no sample ROM");
        // A stopped programmed voice may have completed the new low-priority
        // all-bank prewarm before execution begins. Its muted engine scans must
        // not initiate any additional ROM transaction.
        else assert(sample_fetches==fetches_before && !sample_req)
            else $fatal(1,"stopped engine scan accessed sample ROM");
        readback_histories();
        total_vectors++;
    endtask

    task automatic fill_dirty(input integer which);
        case(which)
            0:begin history[0]=10001;history[1]=-8001;history[2]=701;history[3]=-30005;history[4]=60007;history[5]=-90001;end
            1:begin history[0]=131071;history[1]=-131072;history[2]=131069;history[3]=-131071;history[4]=-65537;history[5]=65535;end
            default:begin history[0]=-1;history[1]=3;history[2]=-7;history[3]=11;history[4]=-13;history[5]=17;end
        endcase
    endtask

    integer panning_value;
    task automatic restart_underrun;
        integer timeout;
        for(integer i=0;i<6;i++)history[i]=0;
        history[5]=20000;expected_control=16'h0300;expected_accum=0;
        raw_k1=0;raw_k2=0;
        reset_and_program(0,0);execute_frames(1,1);
        assert(audio_left!=0)else $fatal(1,"restart fixture never made a sounding contribution");
        write_reg(4'hf,0);expected_control=16'h0302;
        write_reg(4'h0,{16'd0,expected_control});execute_frames(2,1);
        assert(audio_left==0 && audio_right==0)else $fatal(1,"STOP1 failed to mute voice");
        // A stopped voice's last audible contribution must not be resurrected
        // by this FPGA's cache-underrun fallback when a NEW note cannot fetch.
        // This is an integration invariant, not a claimed physical-chip stall.
        pause_rom=1;expected_accum=32'h00100000;
        write_reg(4'hf,32'h20);write_reg(4'h3,expected_accum);
        write_reg(4'hf,0);write_reg(4'h0,32'h0300);
        check_engine=0;clock_enable=1;timeout=0;
        do begin @(posedge clk);#0.002;timeout++;end while(!audio_strobe && timeout<5000);
        assert(audio_strobe && dut.scan_underrun && sample_req)
            else $fatal(1,"restart fixture failed to force a held uncached request");
        assert(audio_left==0 && audio_right==0)else $fatal(1,
            "stopped note was replayed during new-note underrun L=%0d R=%0d",audio_left,audio_right);
        @(negedge clk);#0.002;clock_enable=0;
        total_vectors++;
    endtask

    task automatic stopped_history_restart(input integer polarity);
        for(integer i=0;i<6;i++)history[i]=polarity*(10001+i*6001);
        expected_control=16'h0302;expected_accum=32'h00013579;
        raw_k1=16'h4000;raw_k2=16'h6000;
        reset_and_program(0,0);
        // Two muted scans must evolve the signed histories without a ROM read.
        execute_frames(2,0);
        assert((polarity>0 && history[5]>0) || (polarity<0 && history[5]<0))
            else $fatal(1,"stopped history lost expected sign before restart polarity=%0d O4=%0d",polarity,history[5]);

        // Restart the same voice without rewriting its filter state. The
        // independent oracle carries the two stopped scans into the first
        // audible result and checks all six committed histories.
        expected_control=16'h0300;
        write_reg(4'hf,32'd0);write_reg(4'h0,{16'd0,expected_control});
        repeat(800)@(negedge clk);
        execute_frames(4,1);
    endtask
    initial begin
        if($value$plusargs("CASE=%s",test_case))begin end
        if(test_case=="histories")begin
            for(integer pattern=0;pattern<3;pattern++)begin
                fill_dirty(pattern);expected_control=16'h0302;expected_accum=32'h12345;raw_k1=0;raw_k2=0;
                reset_and_program(0,0);readback_histories();total_vectors++;
            end
        end else if(test_case=="filters")begin
            for(integer mode=0;mode<4;mode++)for(integer pattern=0;pattern<3;pattern++)begin
                fill_dirty(pattern);expected_control=16'(mode*256);expected_accum=32'h000003fd;
                raw_k1=16'ha5b7;raw_k2=16'h357f;
                reset_and_program(0,0);execute_frames(4,1);
            end
        end else if(test_case=="interpolation")begin
            for(integer f=0;f<512;f++)for(integer low=0;low<4;low++)begin
                for(integer i=0;i<6;i++)history[i]=0;
                expected_control=16'h0300;expected_accum=32'(f*4+low);raw_k1=16'hfff0;raw_k2=16'hfff0;
                reset_and_program(0,0);execute_frames(1,1);
            end
        end else if(test_case=="panning")begin
            for(integer n=0;n<8;n++)begin
                case(n)0:panning_value=1;1:panning_value=3;2:panning_value=-1;3:panning_value=-3;
                    4:panning_value=65535;5:panning_value=-65537;6:panning_value=131071;default:panning_value=-131071;endcase
                for(integer i=0;i<6;i++)history[i]=0;
                history[5]=panning_value;expected_control=16'h0300;expected_accum=0;raw_k1=0;raw_k2=0;
                reset_and_program(0,0);execute_frames(2,1);
            end
        end else if(test_case=="stopped-flush")begin
            history[0]=10001;history[1]=20003;history[2]=17005;history[3]=30007;history[4]=27009;history[5]=40011;
            expected_control=16'h0342;expected_accum=32'h00013579;raw_k1=16'hfff0;raw_k2=16'hfff0;
            reset_and_program(0,17'h1ffff);execute_frames(4,0);
            // Truncation toward zero leaves a bounded cascade residue when K
            // is one step below unity; pin the independently calculated state.
            assert(history[0]==1 && history[1]==2 && history[2]==2 &&
                   history[3]==3 && history[4]==3 && history[5]==4)
                else $fatal(1,"positive dirty history did not reach expected residual %0d/%0d/%0d/%0d/%0d/%0d",
                    history[0],history[1],history[2],history[3],history[4],history[5]);
        end else if(test_case=="stopped-restart")begin
            stopped_history_restart(1);
            stopped_history_restart(-1);
        end else if(test_case=="equal-endpoint" || test_case=="stop1-equal")begin
            for(integer i=0;i<6;i++)history[i]=0;
            expected_control=test_case=="stop1-equal" ? 16'h0302 : 16'h0300;
            expected_accum=0;raw_k1=0;raw_k2=0;
            reset_and_program(1,0);execute_frames(1,test_case=="equal-endpoint");
        end else if(test_case=="restart-underrun")restart_underrun();
        else $fatal(1,"unknown datapath CASE=%s",test_case);
        $display("PASS ES_DATAPATH_SPEC CASE=%s vectors=%0d native_carrier=%0d compatibility_filter32",test_case,total_vectors,CARRIER_HZ);
        $finish;
    end
    initial begin #500ms;$fatal(1,"datapath watchdog CASE=%s vectors=%0d",test_case,total_vectors);end
endmodule
