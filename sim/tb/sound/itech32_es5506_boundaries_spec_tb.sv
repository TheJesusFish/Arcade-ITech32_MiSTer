// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1fs

// Actual-engine multi-frame boundary tests, ENSONIQ OTTO Rev2.3 printed10-11,
// 19,29,41: https://gjcp.net/pdf/es5506.pdf . The explicit strict-boundary note
// on printed29 is selected over contradictory pseudocode/prose. Reverse
// transwave with START>END follows the documented direction-role swap, but its
// exact arithmetic is retained as an interpretation, not measured silicon.
// No game ROMs, internal forcing, or DUT arithmetic helpers are used.
module itech32_es5506_boundaries_spec_tb;
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
    logic audio_strobe,irq,engine_busy;
    logic [7:0] irq_vector;
    logic [6:0] current_page;
    logic [4:0] active_voices,scan_voice;
    itech32_es5506 dut(
        .clk(clk),.reset(reset),.ce_16m(ce_16m),.host_req(host_req),.host_write(host_write),
        .host_addr(host_addr),.host_wdata(host_wdata),.host_rdata(host_rdata),.host_ack(host_ack),
		.par_comparator_tripped(1'b0),.par_discharge(),
		.sample_req(sample_req),.sample_bank(sample_bank),.sample_addr(sample_addr),
        .sample_companded(sample_companded),.sample_voice(sample_voice),.sample_rdata(16'd0),.sample_ack(sample_ack),
        .audio_left(audio_left),.audio_right(audio_right),.audio_strobe(audio_strobe),
        .irq(irq),.irq_vector(irq_vector),.current_page(current_page),.active_voices(active_voices),
        .scan_voice(scan_voice),.engine_busy(engine_busy)
    );
    always @(posedge clk)begin
        sample_ack<=0;
        if(reset || !sample_req)sample_served<=0;
        else if(!sample_served || sample_signature!={sample_bank,sample_addr})begin
            sample_served<=1;sample_signature<={sample_bank,sample_addr};sample_ack<=1;
        end
    end
    string test_case="irqe-off",vector_name="";
    integer vectors=0,total_frames=0,total_crossings=0;
    integer frames=0,commits=0,crossings=0,direction_changes=0;
    integer carriers=0,input_ticks=0,frame_origin=0,frames_launched=0;
    logic check_engine=0,expected_irq=0;
    logic [15:0] expected_control=0;
    logic [31:0] expected_accum=0,expected_start=0,expected_end=0;
    logic [16:0] expected_frequency=0;

    // Integer-domain phase oracle. Values are masked to their documented
    // architectural widths, but unused register read bits get no golden value.
    function automatic longint signed unsigned32(input longint signed value);
        longint signed reduced;
        reduced=value%64'sd4294967296;
        if(reduced<0)reduced+=64'sd4294967296;
        return reduced;
    endfunction
    task automatic advance_oracle;
        longint signed position,lo,hi,delta;
        integer mode;
        logic reverse,crossed;
        reverse=expected_control[6];crossed=0;
        position=longint'({1'b0,expected_accum});
        lo=longint'({1'b0,expected_start});hi=longint'({1'b0,expected_end});
        if((expected_control&3)==0)begin
            position=unsigned32(position+(reverse ? -longint'({1'b0,expected_frequency}):longint'({1'b0,expected_frequency})));
            if(!expected_control[2])crossed=reverse ? position<lo:position>hi;
            if(crossed)begin
                crossings++;
                if(expected_control[5])begin expected_control[7]=1;expected_irq=1;end
                mode=integer'(expected_control[4:3]);
                delta=reverse ? lo-position:position-hi;
                if(mode==0)expected_control[0]=1;
                else if(mode==3)begin
                    position=reverse ? lo+delta:hi-delta;
                    expected_control[6]=!reverse;direction_changes++;
                end else begin
                    position=reverse ? hi-delta:lo+delta;
                    if(mode==2)begin expected_control[4:3]=0;expected_control[2]=1;end
                end
            end
        end
        expected_accum=32'(unsigned32(position));
        assert(dut.voice_write_data.accum==expected_accum && dut.voice_write_data.control==expected_control)
            else $fatal(1,"BOUNDARY %s commit=%0d expected ACCUM=%h CR=%h actual ACCUM=%h CR=%h crossings=%0d",
                vector_name,commits,expected_accum,expected_control,dut.voice_write_data.accum,dut.voice_write_data.control,crossings);
        assert(dut.voice_write_data.start_addr==expected_start && dut.voice_write_data.end_addr==expected_end)
            else $fatal(1,"boundary processing changed START/END");
    endtask
    always @(posedge clk)begin
        if(reset)begin
            frames=0;commits=0;carriers=0;input_ticks=0;frame_origin=0;frames_launched=0;
        end else begin
            carriers++;
            if(clock_enable && ce_16m)begin
                input_ticks++;
                if(input_ticks%512==0)begin frame_origin=carriers;frames_launched++;end
            end
            if(check_engine && dut.voice_write_en && !dut.host_write_execute_pending && dut.voice_write_addr==0)begin
                advance_oracle();commits++;
            end
            #0.001;
            if(check_engine)begin
                assert(irq==expected_irq && (irq_vector[7]==!expected_irq))
                    else $fatal(1,"boundary IRQ expectation %s expected=%0d actual=%0d vector=%h",vector_name,expected_irq,irq,irq_vector);
                if(expected_irq)assert(irq_vector[4:0]==0)else $fatal(1,"boundary IRQ assigned wrong voice");
            end
            if(check_engine && audio_strobe)begin
                assert(!dut.scan_underrun && !dut.sample_underrun)
                    else $fatal(1,"boundary cache underrun invalidates vector %s frame=%0d",vector_name,frames);
                assert(commits==frames+1 && frames_launched==frames+1 && carriers-frame_origin==28)
                    else $fatal(1,"boundary missing/duplicate actual processing or changed output cadence");
                frames++;
            end
        end
    end
    task automatic transfer(input logic wr,input logic [5:0] address,input logic [7:0] value,
        output logic [7:0] result);
        integer timeout;
        @(negedge clk);#0.002;host_req=1;host_write=wr;host_addr=address;host_wdata=value;
        timeout=0;
        do begin @(posedge clk);#0.002;timeout++;end while(!host_ack && timeout<100);
        assert(host_ack)else $fatal(1,"boundary host timeout");
        result=host_rdata;
        repeat(2)begin @(posedge clk);#0.002;assert(!host_ack)else $fatal(1,"duplicate host ACK");end
        @(negedge clk);#0.002;host_req=0;repeat(2)@(posedge clk);#0.002;
    endtask
    task automatic write_reg(input logic [3:0] slot,input logic [31:0] value);
        logic [7:0] ignored;
        for(integer b=0;b<4;b++)transfer(1,{slot,2'(b)},value[31-b*8-:8],ignored);
    endtask
    task automatic read_reg(input logic [3:0] slot,output logic [31:0] value);
        for(integer b=0;b<4;b++)transfer(0,{slot,2'(b)},0,value[31-b*8-:8]);
    endtask
    task automatic run_vector(input string name,input logic [15:0] control,input logic [16:0] frequency,
        input logic [31:0] start_raw,input logic [31:0] end_raw,input logic [31:0] accum,
        input integer frame_count,input integer minimum_crossings);
        integer timeout;
        logic [31:0] actual;
        check_engine=0;clock_enable=0;
        @(negedge clk);#0.002;reset=1;host_req=0;
        repeat(5)@(negedge clk);#0.002;reset=0;repeat(5)@(negedge clk);
        vector_name=name;crossings=0;direction_changes=0;expected_irq=0;
        expected_control=control;expected_frequency=frequency;expected_accum=accum;
        expected_start=start_raw&32'hfffff800;expected_end=end_raw&32'hffffff80;
        write_reg(4'hb,31);write_reg(4'hf,32'h20);
        write_reg(4'h1,start_raw);write_reg(4'h2,end_raw);write_reg(4'h3,accum);
        write_reg(4'hf,0);write_reg(4'h1,{15'd0,frequency});write_reg(4'h6,0);write_reg(4'h0,{16'd0,control});
        // Synthetic prefetch is prepared before measurement. Native device CE
        // then runs uninterrupted across every boundary and continuation frame.
        repeat(8000)@(negedge clk);
        check_engine=1;clock_enable=1;timeout=0;
        while(frames<frame_count && timeout<100000)begin @(negedge clk);#0.002;timeout++;end
        assert(frames==frame_count && crossings>=minimum_crossings)
            else $fatal(1,"boundary incomplete coverage %s frames=%0d crossings=%0d",name,frames,crossings);
        if(control[4:3]==3 && minimum_crossings>=2)
            assert(direction_changes>=2)else $fatal(1,"bidirectional continuation never reflected at both ends");
        clock_enable=0;check_engine=0;
        write_reg(4'hf,32'h20);
        read_reg(4'h3,actual);assert(actual==expected_accum)else $fatal(1,"final architectural ACCUM readback %s",name);
        read_reg(4'h0,actual);assert(actual[15:0]==expected_control)else $fatal(1,"final architectural CR readback %s",name);
        read_reg(4'h1,actual);assert((actual&32'hfffff800)==expected_start)else $fatal(1,"masked START readback");
        read_reg(4'h2,actual);assert((actual&32'hffffff80)==expected_end)else $fatal(1,"fractional END readback");
        $display("PASS BOUNDARY_VECTOR name=%s frames=%0d crossings=%0d DIRchanges=%0d finalACCUM=%h CR=%h",
            name,frames,crossings,direction_changes,expected_accum,expected_control);
        vectors++;total_frames+=frames;total_crossings+=crossings;
    endtask
    initial begin
        logic [31:0] start_raw,end_raw,point;
        logic [15:0] control;
        void'($value$plusargs("CASE=%s",test_case));
        if(test_case=="irqe-off")begin
            for(integer reverse=0;reverse<2;reverse++)for(integer mode=0;mode<4;mode++)begin
                control=16'h300|16'(reverse*64+mode*8);
                run_vector($sformatf("IRQEoff-dir%0d-mode%0d",reverse,mode),control,17'h81,
                    32'h000107ff,32'h000183ff,reverse!=0 ? 32'h10000:32'h18380,8,1);
            end
        end else if(test_case=="fractional")begin
            // All four fractional END bits, with discarded low7 bits set, and
            // first updated position one below/equal/one above that boundary.
            for(integer fraction=0;fraction<16;fraction++)for(integer delta=-1;delta<=1;delta++)begin
                end_raw=32'h18000+32'(fraction*128)+32'h7f;
                point=(end_raw&32'hffffff80)+32'(delta)-32'd1;
                run_vector($sformatf("ENDfraction%0d-delta%0d",fraction,delta),16'h320,17'd1,
                    32'h107ff,end_raw,point,3,1);
            end
            // START has no fraction. Every excluded bit is covered collectively
            // while reverse first-step positions straddle its integer boundary.
            for(integer pattern=0;pattern<4;pattern++)for(integer delta=-1;delta<=1;delta++)begin
                case(pattern)0:start_raw=32'h10000;1:start_raw=32'h10001;
                    2:start_raw=32'h10400;default:start_raw=32'h107ff;endcase
                point=32'h10000+32'(delta)+32'd1;
                run_vector($sformatf("STARTmask%0d-delta%0d",pattern,delta),16'h360,17'd1,
                    start_raw,32'h183ff,point,3,1);
            end
        end else if(test_case=="transwave")begin
            for(integer reverse=0;reverse<2;reverse++)for(integer enabled=0;enabled<2;enabled++)begin
                control=16'h310|16'(reverse*64+enabled*32);
                run_vector($sformatf("STARTaboveEND-dir%0d-IRQE%0d",reverse,enabled),control,17'h281,
                    32'h187ff,32'h103ff,reverse!=0 ? 32'h18000:32'h10380,10,1);
                assert(crossings==1 && expected_control[2] && expected_control[4:3]==0 && expected_control[1:0]==0)
                    else $fatal(1,"transwave did not become one-shot LEI continuation");
            end
        end else if(test_case=="continuation")begin
            for(integer reverse=0;reverse<2;reverse++)for(integer bidi=0;bidi<2;bidi++)for(integer enabled=0;enabled<2;enabled++)begin
                control=16'h308|16'(reverse*64+bidi*16+enabled*32);
                run_vector($sformatf("continue-dir%0d-bidi%0d-IRQE%0d",reverse,bidi,enabled),control,17'h601,
                    32'h107ff,32'h118ff,32'h1101b,16,2);
            end
        end else if(test_case=="equal-nonzero")begin
            // Rev2.3 gives no START==END shortcut: the same strict crossing and
            // one-transform rules remain selected. Exercise motion rather than
            // the existing FC0 smoke case, including repeated zero-width loops.
            for(integer reverse=0;reverse<2;reverse++)for(integer mode=0;mode<4;mode++)for(integer enabled=0;enabled<2;enabled++)begin
                control=16'h300|16'(reverse*64+mode*8+enabled*32);
                run_vector($sformatf("equal-dir%0d-mode%0d-IRQE%0d",reverse,mode,enabled),control,17'h81,
                    32'h10000,32'h10000,32'h10000,4,1);
            end
            // LEI suppresses the comparator even though every nonzero step is
            // outside the zero-width range. IRQE must therefore remain quiet.
            for(integer reverse=0;reverse<2;reverse++)for(integer enabled=0;enabled<2;enabled++)begin
                control=16'h304|16'(reverse*64+enabled*32);
                run_vector($sformatf("equal-LEI-dir%0d-IRQE%0d",reverse,enabled),control,17'h81,
                    32'h10000,32'h10000,32'h10000,4,0);
                assert(!expected_irq && !irq)else $fatal(1,"equal-endpoint LEI raised IRQ");
            end
        end else $fatal(1,"unknown boundary CASE=%s",test_case);
        $display("PASS ES_BOUNDARIES_SPEC CASE=%s vectors=%0d frames=%0d crossings=%0d native_carrier=%0d",
            test_case,vectors,total_frames,total_crossings,CARRIER_HZ);
        $finish;
    end
    initial begin repeat(8_000_000)@(posedge clk);$fatal(1,"boundary watchdog CASE=%s",test_case);end
endmodule
