// Common baseline/candidate probe: reset while the final burst beat is stalled.
// Keep the early-release failure explicit; a settled reset is a separate test.
task automatic early_write_reset_probe;
    integer timeout;
    bit mismatch;
    begin
        for(integer n=0;n<16;n++)
            vram_write(20'h400+20'(n*4),16'h4000+16'(n),2'b11);
        scan_addr=20'h400;scan_req=1;timeout=0;
        while(!(dut.state==MEM_ST_VRAM_BURST_WRITE &&
                dut.vram_write_burst_accepted==15 && core_DDRAM_BUSY) && timeout<2000) begin
            @(negedge clk);timeout++;
        end
        assert(timeout<2000) else $fatal(1,"reset probe failed to reach final-beat stall");
        force_waitrequest=1;quiesce=1;scan_req=0;
        repeat(2) @(negedge clk);
        framework_reset=1;
        repeat(3) @(negedge clk);
        force_waitrequest=0;timeout=0;
        while(!(dut.state==MEM_ST_IDLE && !model_active) && timeout<2000) begin
            @(negedge clk);timeout++;
        end
        assert(timeout<2000) else $fatal(1,"reset probe old burst did not drain");
        $display("RESET_RELEASE_CHECK settled=%0d terminating=%b write_terminating=%b counter=%0d count=%0d",
            $test$plusargs("RESET_SETTLED"),terminator.terminating,
            terminator.write_terminating,terminator.write_terminate_counter,terminator.burstcount_latch);
        if($test$plusargs("RESET_SETTLED")) begin
            timeout=0;
            while(terminator.write_terminating && timeout<2000) begin
                @(negedge clk);timeout++;
            end
            assert(timeout<2000) else $fatal(1,"terminator did not settle");
            repeat(3) @(negedge clk);
        end
        framework_reset=0;
        @(negedge clk);quiesce=0;
        timeout=0;
        while((retained_vram_writes || model_active || core_DDRAM_WE) && timeout<2000) begin
            @(negedge clk);timeout++;
        end
        assert(timeout<2000) else $fatal(1,"reset probe retry did not drain");
        mismatch=0;
        for(integer n=0;n<16;n++) begin
            if(vram_memory['h800+n*8]!=8'h40 || vram_memory['h801+n*8]!=8'(n)) begin
                $display("RESET_BYTE n=%0d got=%02x%02x expected=%04x",n,
                    vram_memory['h800+n*8],vram_memory['h801+n*8],16'h4000+16'(n));
                mismatch=1;
            end
        end
        assert(!mismatch) else $fatal(1,"EARLY_RESET_DATA_MISMATCH");
        $display("PASS: settled write-reset probe");
    end
endtask
