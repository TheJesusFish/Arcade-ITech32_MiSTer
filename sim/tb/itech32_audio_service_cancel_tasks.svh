// New simulation-only cancellation extension. No DUT/cache/response forcing.
task automatic audio_cancel_reissue(input logic [21:0] address);
    integer timeout;
    begin
        @(negedge clk);
        sample_bank=timekill_mode ? 2'd2 : 2'd0;
        sample_addr=address;sample_req=1;
        timeout=0;
        do begin @(posedge clk);#1;timeout++;end while(!sample_ack && timeout<512);
        assert(sample_ack && sample_rdata==sample_expected(sample_bank,sample_addr))
            else $fatal(1,"AUDIO_CANCEL_REISSUE_DATA address=%x",address);
        repeat(3)begin
            @(posedge clk);#1;
            assert(!sample_ack)else $fatal(1,"AUDIO_CANCEL_REISSUE_DUPLICATE");
        end
        @(negedge clk);sample_req=0;
        repeat(4)@(negedge clk);
    end
endtask

task automatic audio_cancel_suite;
    integer timeout,commands_before;
    begin
        cancel_test=1;
        repeat(3)@(negedge clk);
        assert(!model_active && !retained_vram_writes && !sample_req)
            else $fatal(1,"AUDIO_CANCEL_NOT_QUIET");
        // Pending-before-grant: quiesce rejects the scheduling opportunity.
        commands_before=ddr_transactions;
        quiesce=1;framework_reset=1;
        sample_bank=0;sample_addr=22'h23010;sample_req=1;
        repeat(8)begin
            @(negedge clk);
            assert(!sample_ack && ddr_transactions==commands_before)
                else $fatal(1,"AUDIO_QUIESCED_PENDING_ACK_OR_DDR");
        end
        sample_req=0;
        repeat(3)@(negedge clk);framework_reset=0;quiesce=0;
        audio_cancel_reissue(22'h23010);

        // The next cold line is physically accepted before quiesce. Hold only
        // the external model's return for eight clocks; this interval is outside
        // the512-carrier ordinary-service bound. Preserve the accepted read and
        // suppress its architectural ACK, then drain before reset release.
        @(negedge clk);hold_read_returns=1;
        sample_bank=0;sample_addr=22'h24120;sample_req=1;timeout=0;
        while(!(model_active && model_read && dut.op_client==MEM_CLIENT_SAMPLE)
              && timeout<512)begin @(negedge clk);timeout++;end
        assert(timeout<512 && !sample_ack)
            else $fatal(1,"AUDIO_CANCEL_NO_ACCEPTED_READ");
        quiesce=1;framework_reset=1;sample_req=0;
        repeat(8)begin
            @(negedge clk);
            assert(!sample_ack && model_active)
                else $fatal(1,"AUDIO_CANCEL_EARLY_ACK_OR_LOST_READ");
        end
        hold_read_returns=0;timeout=0;
        while((model_active || terminator.read_terminating ||
               terminator.write_terminating || dut.state!=MEM_ST_IDLE) && timeout<512)begin
            @(negedge clk);timeout++;
            assert(!sample_ack)else $fatal(1,"AUDIO_CANCEL_ACK_WHILE_DRAINING");
        end
        assert(timeout<512)else $fatal(1,"AUDIO_CANCEL_DRAIN_TIMEOUT");
        repeat(3)@(negedge clk);framework_reset=0;quiesce=0;
        audio_cancel_reissue(22'h24120);
        for(integer b=0;b<4096;b++)
            assert(vram_memory[b]==expected_vram[b])
                else $fatal(1,"AUDIO_CANCEL_CHANGED_VRAM address=%x",b);
        $display("AUDIO_CANCEL_RESULT cases=2 reissues=2 held_after_ack=6 externally_held_return_clocks=8 vram_bytes=4096");
        $display("PASS: audio sample pending/inflight cancellation, safe drain and reissue");
    end
endtask
