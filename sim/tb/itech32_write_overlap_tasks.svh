// Simulation-only ownership tests, included inside the DDR-memory fixture.
logic [7:0] overlap_expected [0:4095];
integer overlap_acks = 0;

always @(posedge clk) begin
    if ($test$plusargs("OVERLAP_TRACE") && DDRAM_WE && !DDRAM_BUSY)
        $display("OW t=%0t addr=%x count=%0d active=%b beat=%0d data=%016x be=%02x core-index=%0d drain=%b collect=%b retry=%b quiesce=%b",
            $time,DDRAM_ADDR,DDRAM_BURSTCNT,model_active,model_burst_beat,
            DDRAM_DIN,DDRAM_BE,dut.vram_write_burst_index,dut.vram_drain_bank,
            dut.vram_collect_bank,dut.vram_write_buffer_retry,quiesce);
end

task automatic overlap_score;
    for (integer n=0; n<4096; n++)
        assert(vram_memory[n] == overlap_expected[n])
            else $fatal(1,"overlap backing byte %03x got=%02x expected=%02x",
                        n,vram_memory[n],overlap_expected[n]);
endtask

task automatic overlap_qwrite(input logic [17:0] address,
                              input logic [63:0] data,
                              input logic [7:0] mask);
    integer timeout;
    begin
        @(negedge clk);
        vram_qwrite_req=1;vram_qwrite_addr=address;
        vram_qwrite_data=data;vram_qwrite_be=mask;
        vram_qwrite_token=!vram_qwrite_token;
        timeout=0;
        do begin @(posedge clk);#1;timeout++;end
        while(!vram_qwrite_ack && timeout<2000);
        assert(vram_qwrite_ack) else $fatal(1,"overlap qwrite timeout addr=%x",address);
        overlap_acks++;
        for(integer b=0;b<8;b++)
            if(mask[b]) overlap_expected[integer'(address)*8+b]=data[b*8+:8];
        @(negedge clk);vram_qwrite_req=0;
    end
endtask

task automatic overlap_scan(input logic [19:0] address);
    integer timeout,beat;
    logic [63:0] expected_line;
    begin
        @(negedge clk);scan_addr=address;scan_req=1;timeout=0;
        do begin @(posedge clk);#1;timeout++;end
        while(!scan_accept && timeout<4000);
        assert(scan_accept) else $fatal(1,"overlap scan timeout");
        overlap_score();
        @(negedge clk);scan_req=0;beat=0;timeout=0;
        while(beat<128 && timeout<4000) begin
            @(posedge clk);#1;timeout++;
            if(scan_data_valid) begin
                for(integer b=0;b<8;b++)
                    expected_line[b*8+:8]=overlap_expected[integer'(address)*2+beat*8+b];
                assert(scan_rdata==expected_line && scan_last==(beat==127))
                    else $fatal(1,"overlap scan data mismatch beat=%0d",beat);
                beat++;
            end
        end
        assert(beat==128) else $fatal(1,"overlap scan missing return beats");
        repeat(3) @(negedge clk);
    end
endtask

task automatic overlap_fill(input logic [17:0] base,input logic [7:0] pattern);
    for(integer n=0;n<16;n++)
        overlap_qwrite(base+18'(n),{8{pattern^8'(n)}},8'hff);
endtask

task automatic overlap_reset_case(input integer stop_beat);
    integer timeout;
    logic [135:0] held_front;
    begin
        $display("overlap reset case stop=%0d t=%0t",stop_beat,$time);
        overlap_fill(18'h100,8'h80^8'(stop_beat));
        force_waitrequest=1;
        repeat(2) @(negedge clk);
        overlap_qwrite(18'h110,64'h0123456789abcdef,8'h5a);
        assert(dut.state==MEM_ST_VRAM_BURST_WRITE && dut.vram_drain_valid)
            else $fatal(1,"reset test lacks active old drain");
        repeat(2) @(negedge clk);
        if(stop_beat!=0) begin
            force_waitrequest=0;timeout=0;
            while(!(dut.vram_write_burst_accepted==5'(stop_beat) && core_DDRAM_BUSY) && timeout<1000) begin
                @(negedge clk);timeout++;
            end
            assert(timeout<1000) else $fatal(1,"cannot stop burst at beat %0d",stop_beat);
            force_waitrequest=1;repeat(2) @(negedge clk);
        end
        // Leave this accepted newer write in the front at the reset edge.
        overlap_qwrite(18'h11f,64'hfeedc0dedeadbeef,8'ha5);
        assert(dut.vram_fast_pending && dut.vram_write_buffer_valid)
            else $fatal(1,"reset test did not retain collector plus front");
        held_front={dut.vram_fast_base_q,dut.vram_fast_index_q,
                    dut.vram_fast_select_q,dut.vram_fast_data_q,dut.vram_fast_be_q};
        framework_reset=1;quiesce=1;
        repeat(3) begin
            @(negedge clk);
            assert(!vram_qwrite_ack && dut.vram_fast_pending && held_front==
                {dut.vram_fast_base_q,dut.vram_fast_index_q,dut.vram_fast_select_q,
                 dut.vram_fast_data_q,dut.vram_fast_be_q})
                else $fatal(1,"quiesce lost or re-ACKed front ownership");
        end
        force_waitrequest=0;timeout=0;
        while(!(dut.state==MEM_ST_IDLE && !model_active) && timeout<2000) begin
            @(negedge clk);timeout++;
        end
        assert(timeout<2000 && dut.vram_write_buffer_retry && dut.vram_drain_valid &&
               dut.vram_write_buffer_valid && dut.vram_fast_pending)
            else $fatal(1,"quiesced burst lost retry/collector/front");
        // Separate from the common early-release negative probe: the positive
        // ownership test holds reset until the framework has finished replacing
        // beats. Memory IDLE alone does not imply that the terminator is done.
        timeout=0;
        while(terminator.write_terminating && timeout<2000) begin
            @(negedge clk);timeout++;
        end
        assert(timeout<2000) else $fatal(1,"framework did not finish write termination");
        repeat(3) @(negedge clk);
        framework_reset=0;quiesce=0;
        if ($test$plusargs("OVERLAP_TRACE"))
            $display("OR t=%0t stop=%0d first=%0d count=%0d drain-base=%x drain-first-data=%016x",
                $time,stop_beat,dut.vram_drain_first,dut.vram_write_burst_count,
                dut.vram_drain_base,dut.vram_write_buffer_data[{dut.vram_drain_bank,dut.vram_drain_first}]);
        // A scan observes the entire row only after old retry and newer writes.
        overlap_scan(20'h400);
        assert(!retained_vram_writes) else $fatal(1,"reset retry retained an unflushed tail");
    end
endtask

task automatic write_overlap_suite;
    integer timeout;
    logic [63:0] before_reload;
    begin
        for(integer n=0;n<4096;n++) overlap_expected[n]=vram_memory[n];
        // First window is held before its first physical acceptance.
        overlap_fill(18'h080,8'h20);
        force_waitrequest=1;repeat(2) @(negedge clk);
        overlap_qwrite(18'h090,64'h0123456789abcdef,8'hff);
        overlap_qwrite(18'h09f,64'hf0e1d2c3b4a59687,8'hff);
        overlap_qwrite(18'h094,64'h1111222233334444,8'h55);
        overlap_qwrite(18'h094,64'h5555666677778888,8'haa);
        overlap_qwrite(18'h094,64'h9999999999999999,8'h01);
        overlap_qwrite(18'h095,64'hffffffffffffffff,8'h00);
        repeat(2) @(negedge clk);
        assert(dut.state==MEM_ST_VRAM_BURST_WRITE && core_DDRAM_BUSY &&
               dut.vram_drain_valid && dut.vram_write_buffer_valid &&
               dut.vram_drain_bank!=dut.vram_collect_bank && dut.vram_write_burst_accepted==0)
            else $fatal(1,"overlap did not collect independently of stalled drain");
        // A third block cannot overwrite either owner and receives no ACK.
        vram_qwrite_req=1;vram_qwrite_addr=18'h0a0;
        vram_qwrite_data=64'h76543210fedcba98;vram_qwrite_be=8'hff;
        vram_qwrite_token=!vram_qwrite_token;
        repeat(12) begin
            @(posedge clk);#1;
            assert(!vram_qwrite_ack && dut.vram_write_burst_accepted==0)
                else $fatal(1,"third window bypassed full ownership");
        end
        @(negedge clk);force_waitrequest=0;timeout=0;
        do begin @(posedge clk);#1;timeout++;end
        while(!vram_qwrite_ack && timeout<2000);
        assert(vram_qwrite_ack) else $fatal(1,"third window did not resume");
        overlap_acks++;
        for(integer b=0;b<8;b++) overlap_expected['h500+b]=vram_qwrite_data[b*8+:8];
        // A held signature must not generate another ACK while its old burst drains.
        repeat(3) begin
            @(posedge clk);#1;
            assert(!vram_qwrite_ack) else $fatal(1,"held overlap signature re-ACKed");
        end
        @(negedge clk);vram_qwrite_req=0;
        overlap_scan(20'h200);
        overlap_reset_case(0);
        overlap_reset_case(8);
        overlap_reset_case(15);

        // Reload cancels the new collector/front, not the physical old burst.
        overlap_fill(18'h180,8'hd0);
        before_reload=model_line(VRAM_BASE+28'hc80);
        force_waitrequest=1;repeat(2) @(negedge clk);
        overlap_qwrite(18'h190,64'hbad0bad0bad0bad0,8'hff);
        ioctl_download=1;
        repeat(3) @(negedge clk);
        assert(dut.state==MEM_ST_VRAM_BURST_WRITE && !dut.vram_drain_valid &&
               !dut.vram_write_buffer_valid && !dut.vram_fast_pending && !vram_qwrite_ack)
            else $fatal(1,"reload did not cancel logical old-image owners");
        for(integer b=0;b<8;b++) overlap_expected['hc80+b]=before_reload[b*8+:8];
        force_waitrequest=0;timeout=0;
        while(!(dut.state==MEM_ST_IDLE && !model_active) && timeout<2000) begin
            @(negedge clk);timeout++;
        end
        assert(timeout<2000) else $fatal(1,"reload did not safely drain offered burst");
        overlap_score();
        ioctl_download=0;timeout=0;
        do begin @(negedge clk);timeout++;end while(!rom_loaded && timeout<4000);
        assert(rom_loaded && !retained_vram_writes) else $fatal(1,"reload did not recover");
        overlap_score();
        $display("PASS: write-window overlap ownership, masks, capacity, scan, retry and reload; ACKs=%0d",overlap_acks);
    end
endtask
