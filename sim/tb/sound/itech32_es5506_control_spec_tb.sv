// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1fs

// Synthetic address/envelope checks against ENSONIQ OTTO Revision2.3:
// https://gjcp.net/pdf/es5506.pdf, printed10-13,29,35-37.
// Strict >END/<START takes precedence over the conflicting endpoint pseudocode.
// Very large overshoots use one boundary transform, not an invented modulo loop.
// Reset slow-ramp sub-phase is interpreted as zero. The slow-free case separately
// checks the printed35 free-running FILTCOUNT, including ECOUNT0 and reprogramming.
module itech32_es5506_control_spec_tb;
    localparam integer CARRIER_HZ = 47_727_273;
    logic clk=0,reset=1,clock_enable=0,ce_16m=0;
    integer remainder=0;
    always #(500_000_000.0/CARRIER_HZ) clk=~clk;
    always @(negedge clk) begin
        ce_16m=0;
        if(reset || !clock_enable) remainder=0;
        else begin
            remainder+=16_000_000;
            if(remainder>=CARRIER_HZ) begin remainder-=CARRIER_HZ;ce_16m=1;end
        end
    end
    logic host_req=0,host_write=0,host_ack;
    logic [5:0] host_addr=0;
    logic [7:0] host_wdata=0,host_rdata;
    logic sample_req,sample_ack=0,sample_companded;
    logic [1:0] sample_bank;
    logic [21:0] sample_addr;
    logic [4:0] sample_voice;
    logic [23:0] sample_signature=0;
    logic sample_served=0;
    logic signed [19:0] audio_left,audio_right;
    logic audio_strobe,irq,engine_busy;
    logic [7:0] irq_vector;
    logic [6:0] current_page;
    logic [4:0] active_voices,scan_voice;
    integer vectors=0,frames=0;
    string test_case="address";
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
        if(reset) sample_served<=0;
        else if(!sample_req) sample_served<=0;
        else if(!sample_served || sample_signature!={sample_bank,sample_addr}) begin
            sample_served<=1;sample_signature<={sample_bank,sample_addr};sample_ack<=1;
        end
    end
    task automatic transfer(input logic wr,input logic [5:0] address,
        input logic [7:0] data,output logic [7:0] result);
        integer timeout;
        @(negedge clk);#0.002;
        host_req=1;host_write=wr;host_addr=address;host_wdata=data;
        timeout=0;
        do begin @(posedge clk);#0.002;timeout++;end while(!host_ack && timeout<100);
        assert(host_ack)else $fatal(1,"control-spec host timeout address=%h",address);
        result=host_rdata;
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
    task automatic expect_reg(input logic [3:0] slot,input logic [31:0] expected,
        input string label_text);
        logic [31:0] actual;
        read_reg(slot,actual);
        assert(actual==expected)else $fatal(1,"%s expected=%h actual=%h",label_text,expected,actual);
    endtask
    task automatic reset_dut;
        @(negedge clk);#0.002;reset=1;clock_enable=0;host_req=0;
        repeat(5)@(posedge clk);
        @(negedge clk);#0.002;reset=0;
        repeat(5)@(posedge clk);
        write_reg(4'hb,32'd4); // five voices is the documented minimum
    endtask
    task automatic one_frame;
        integer timeout;
        @(negedge clk);#0.002;clock_enable=1;
        timeout=0;
        do begin @(posedge clk);#0.002;timeout++;end while(!audio_strobe && timeout<5000);
        assert(audio_strobe)else $fatal(1,"control-spec frame timeout");
        assert(!dut.sample_underrun && !dut.scan_underrun)
            else $fatal(1,"control-spec unprimed sample would invalidate address checker");
        @(negedge clk);#0.002;clock_enable=0;
        frames++;
    endtask
    task automatic configure_address(input logic [15:0] control,input logic [16:0] frequency,
        input logic [31:0] start_addr,input logic [31:0] end_addr,input logic [31:0] accum);
        write_reg(4'hf,32'h20);
        write_reg(4'h1,start_addr);write_reg(4'h2,end_addr);write_reg(4'h3,accum);
        write_reg(4'hf,0);
        write_reg(4'h1,{15'd0,frequency});write_reg(4'h0,{16'd0,control});
        // ROM service runs on the carrier even while the ES scan is paused.
        // Prime exact addresses rather than discarding an architectural frame.
        repeat(1600)@(posedge clk);
    endtask
    task automatic address_vector(input logic [15:0] control,input logic [16:0] frequency,
        input logic [31:0] start_addr,input logic [31:0] end_addr,input logic [31:0] accum);
        longint signed position,delta,lo,hi;
        integer mode;
        logic [15:0] expected_control;
        logic [31:0] expected_accum;
        logic crossed;
        reset_dut();
        configure_address(control,frequency,start_addr,end_addr,accum);
        lo=longint'({1'b0,start_addr & 32'hfffff800});
        hi=longint'({1'b0,end_addr & 32'hffffff80});
        position=longint'({1'b0,accum});
        expected_control=control;crossed=0;
        if((control&3)==0)begin
            if(control[6])position-=longint'({1'b0,frequency});
            else position+=longint'({1'b0,frequency});
            // ACCUM is a32-bit architectural register, including all11 fraction bits.
            position=longint'({1'b0,32'(position)});
            if(!control[2])begin
                crossed=control[6] ? position<lo : position>hi;
                if(crossed)begin
                    if(control[5])expected_control[7]=1;
                    mode=integer'((control/8)%4);
                    delta=control[6] ? lo-position : position-hi;
                    case(mode)
                        0:expected_control[0]=1;
                        1:position=control[6] ? hi-delta : lo+delta;
                        2:begin
                            position=control[6] ? hi-delta : lo+delta;
                            expected_control[4:3]=0;expected_control[2]=1;
                        end
                        3:begin
                            position=control[6] ? lo+delta : hi-delta;
                            expected_control[6]=!control[6];
                        end
                    endcase
                end
            end
        end
        expected_accum=32'(position);
        one_frame();
        write_reg(4'hf,32'h20);
        expect_reg(4'h3,expected_accum,"address/loop ACCUM");
        expect_reg(4'h0,{16'd0,expected_control},"address/loop CR");
        assert(irq==(crossed && control[5]))else $fatal(1,"address boundary IRQ mismatch");
        vectors++;
    endtask
    function automatic integer saturated(input integer value,input integer increment);
        integer sum;
        sum=value+increment;
        if(sum<0)return 0;
        if(sum>65535)return 65535;
        return sum;
    endfunction
    task automatic envelope_vector(input integer count,input logic slow1,input logic slow2,
        input integer lv,input integer rv,input integer k1,input integer k2,
        input integer lvr,input integer rvr,input integer k1r,input integer k2r);
        integer el,er,ek1,ek2,ec,phase;
        reset_dut();
        write_reg(4'h2,32'(lv));write_reg(4'h4,32'(rv));
        write_reg(4'h3,{16'd0,8'(lvr),8'd0});write_reg(4'h5,{16'd0,8'(rvr),8'd0});
        write_reg(4'h9,32'(k1));write_reg(4'h7,32'(k2));
        write_reg(4'ha,{16'd0,8'(k1r),7'd0,slow1});
        write_reg(4'h8,{16'd0,8'(k2r),7'd0,slow2});
        write_reg(4'h6,32'(count));
        el=lv;er=rv;ek1=k1;ek2=k2;ec=count;phase=0;
        for(integer f=0;f<count+2;f++)begin
            if(ec!=0)begin
                el=saturated(el,lvr);er=saturated(er,rvr);
                if(!slow1 || phase%8==0)ek1=saturated(ek1,k1r);
                if(!slow2 || phase%8==0)ek2=saturated(ek2,k2r);
                ec--;phase++;
            end
            one_frame();
            expect_reg(4'h2,32'(el),"LVOL signed saturation");
            expect_reg(4'h4,32'(er),"RVOL signed saturation");
            expect_reg(4'h9,32'(ek1),"K1 independent ramp");
            expect_reg(4'h7,32'(ek2),"K2 independent ramp");
            expect_reg(4'h6,32'(ec),"ECOUNT sample decrement/zero gate");
        end
        vectors++;
    endtask
    task automatic safe_envelope_update;
        reset_dut();
        write_reg(4'h2,32'd1000);write_reg(4'h3,32'h00000500);write_reg(4'h6,32'd511);
        one_frame();expect_reg(4'h2,32'd1005,"initial ramp");
        // Documented programming protocol: stop ramp, wait a complete sample,
        // replace increments, restart. This does not assert pin-exact behavior
        // for an unprotected host write racing a live three-voice pipeline.
        write_reg(4'h6,0);one_frame();expect_reg(4'h2,32'd1005,"ECOUNT0 protects value");
        write_reg(4'h3,32'h0000fd00);write_reg(4'h6,32'd2);
        one_frame();expect_reg(4'h2,32'd1002,"replacement ramp first sample");
        one_frame();expect_reg(4'h2,32'd999,"replacement ramp last sample");
        one_frame();expect_reg(4'h2,32'd999,"replacement ramp stops exactly");
        vectors++;
    endtask
    task automatic slow_counter_free_running;
        integer expected,phase;
        for(integer start_phase=0;start_phase<8;start_phase++)begin
            reset_dut();
            write_reg(4'h9,32'd1000);write_reg(4'ha,32'h00000701);
            // ECOUNT0 gates the ramp but not the printed modulo-eight divider.
            // Cover every possible hidden phase before the first ECOUNT write.
            repeat(start_phase)begin
                one_frame();
                expect_reg(4'h9,32'd1000,"ECOUNT0 gated slow ramp while phase advanced");
            end
            expected=1000;phase=start_phase;
            write_reg(4'h6,32'd8);
            for(integer f=0;f<8;f++)begin
                if(phase%8==0)expected+=7;
                one_frame();
                expect_reg(4'h9,32'(expected),$sformatf("slow ramp initial ECOUNT phase=%0d",start_phase));
                expect_reg(4'h6,32'(7-f),"initial ECOUNT exact decrement");
                phase++;
            end
            // Eight active scans return FILTCOUNT to the same hidden phase.
            // A second ECOUNT write must preserve that phase rather than reset it.
            write_reg(4'h6,32'd8);
            for(integer f=0;f<8;f++)begin
                if(phase%8==0)expected+=7;
                one_frame();
                expect_reg(4'h9,32'(expected),$sformatf("slow ramp rewritten ECOUNT phase=%0d",start_phase));
                expect_reg(4'h6,32'(7-f),"rewritten ECOUNT exact decrement");
                phase++;
            end
            vectors++;
        end
    endtask

    initial begin
        logic [16:0] frequencies[0:4];
        logic [15:0] control;
        void'($value$plusargs("CASE=%s",test_case));
        frequencies[0]=0;frequencies[1]=1;frequencies[2]=17'h7ff;
        frequencies[3]=17'h800;frequencies[4]=17'h1ffff;
        if(test_case=="address")begin
            for(integer direction=0;direction<2;direction++)begin
                for(integer mode=0;mode<4;mode++)begin
                    for(integer f=0;f<5;f++)begin
                        control=16'h0020|16'(direction*64+mode*8);
                        address_vector(control,frequencies[f],32'h10000,32'h10800,
                            direction!=0 ? 32'h10000 : 32'h10800);
                    end
                end
            end
            // Equality is not crossing, in either direction.
            address_vector(16'h20,17'h800,32'h10000,32'h10800,32'h10000);
            address_vector(16'h60,17'h800,32'h10000,32'h10800,32'h10800);
            // LEI bypasses end checking even if already outside the loop.
            address_vector(16'h24,17'h1ffff,32'h10000,32'h10800,32'h10800);
            address_vector(16'h64,17'h1ffff,32'h10000,32'h10800,32'h10000);
            // STOP0 and STOP1 independently prevent ALU/control changes.
            address_vector(16'h21,17'h1ffff,32'h10000,32'h10800,32'h10800);
            address_vector(16'h62,17'h1ffff,32'h10000,32'h10800,32'h10000);
            // Accumulator wrap and fractional FC1 are retained independently
            // of the interpolator's upper-nine-bit fraction selection.
            address_vector(16'h04,17'h1,32'h0,32'hffffff80,32'hffffffff);
            address_vector(16'h44,17'h1,32'h0,32'hffffff80,32'h0);
        end else if(test_case=="envelope")begin
            envelope_vector(0,0,1,1,65534,3,65534,-2,2,-2,2);
            envelope_vector(1,1,0,1,65534,3,65534,-2,2,-2,2);
            for(integer flags=0;flags<4;flags++)
                envelope_vector(17,1'(flags),1'(flags/2),32768,32768,32768,32768,
                    -128,127,127,-128);
            envelope_vector(511,1,0,32768,32768,32768,32768,0,-1,-1,1);
            safe_envelope_update();
        end else if(test_case=="slow-free")slow_counter_free_running();
        else $fatal(1,"unknown CASE=%s",test_case);
        $display("PASS ES_CONTROL_SPEC CASE=%s vectors=%0d frames=%0d",test_case,vectors,frames);
        $finish;
    end
    initial begin repeat(5_000_000)@(posedge clk);$fatal(1,"control-spec watchdog");end
endmodule
