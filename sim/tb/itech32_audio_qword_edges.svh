// Simulation-only extension of the frozen F4 fixture. No DUT state/data forcing.
// All limits are for the inherited deterministic DDR model, not physical DDR.
bit edge_active = 0, edge_write_pending = 0;
integer edge_cases = 0, edge_samples = 0, edge_writes = 0;
integer edge_grace_eligible = 0, edge_grace_commits = 0;
integer edge_word3 = 0, edge_exceptions = 0, edge_writer_age = 0;
integer edge_writer_max = 0, edge_quiesces = 0, edge_reloads = 0;
integer edge_held_clocks = 0, edge_retargets = 0;
logic [63:0] edge_write_hash = 64'hcbf29ce484222325;
logic [63:0] edge_sample_hash = 64'hcbf29ce484222325;

// Capture the pre-edge decision and inspect the *post-NBA* action. Looking
// only at state==IDLE before this edge cannot distinguish F4 from grace.
always @(posedge clk) begin : qword_arbitration_monitor
    bit canonical, qualified, grace, word3, had_front, old_valid;
    bit commit_front, pending_flush, pending_capture;
    integer slot, select_count;
    logic [63:0] wanted_line, front_data;
    logic [7:0] wanted_be, front_be;
    logic [38:0] served_before;
    logic [15:0] sample_data_before;
    if(!reset && ((run_enable && !cancel_test) || edge_active) && sample_ack) begin
        canonical = run_enable && !cancel_test;
        qualified = sample_req && !dut.pending_clients[MEM_CLIENT_SAMPLE] &&
            !dut.main_front_cancel && !scan_req && !dut.vram_write_buffer_retry;
        grace = qualified && dut.response_byte_index[2:1]!=2'd3;
        word3 = qualified && dut.response_byte_index[2:1]==2'd3;
        if(canonical) begin
            if(grace) grace_eligible++;
            else if(word3) word3_opportunities++;
            else ack_priority_exceptions++;
            if(scan_req) scan_on_ack++;
        end else begin
            if(grace) edge_grace_eligible++;
            else if(word3) edge_word3++;
            else edge_exceptions++;
        end
        served_before=dut.served_signature[MEM_CLIENT_SAMPLE];
        sample_data_before=sample_rdata;
        if(qualified)
            assert(dut.state==MEM_ST_IDLE && dut.served[MEM_CLIENT_SAMPLE] &&
                   served_before=={15'd0,sample_bank,sample_addr})
                else $fatal(1,"AUDIO_QWORD_HELD_SIGNATURE_NOT_PROVEN");
        had_front=dut.vram_fast_pending;
        commit_front=dut.vram_buffer_commit;
        old_valid=dut.vram_write_buffer_valid;
        pending_flush=!had_front && dut.vram_write_buffer_valid &&
            dut.vram_client_req && (!dut.vram_client_write ||
                dut.live_vram_block_addr!=dut.vram_write_buffer_base);
        pending_capture=dut.vram_fast_write;
        slot=0;select_count=0;wanted_line=0;wanted_be=0;
        front_data=dut.vram_fast_data_q;front_be=dut.vram_fast_be_q;
        if(commit_front) begin
            for(integer s=0;s<32;s++) if(dut.vram_fast_select_q[s]) begin
                slot=s;select_count++;
            end
            assert(select_count==1) else $fatal(1,"AUDIO_QWORD_FRONT_NOT_ONEHOT");
            wanted_line=dut.vram_write_buffer_data[slot];
            wanted_be=old_valid ? dut.vram_write_buffer_be[slot]|front_be : front_be;
            for(integer b=0;b<8;b++) if(front_be[b])
                wanted_line[b*8+:8]=front_data[b*8+:8];
        end
        #1;
        if(grace && enforce_grace) begin
            assert(dut.state==MEM_ST_IDLE && !core_DDRAM_RD && !core_DDRAM_WE &&
                   !vram_qwrite_ack && !vram_ack && !sample_ack)
                else $fatal(1,"AUDIO_QWORD_GRACE_POSTEDGE state=%0d WE=%b qACK=%b",
                    dut.state,core_DDRAM_WE,vram_qwrite_ack);
            assert(dut.served_signature[MEM_CLIENT_SAMPLE]==served_before &&
                   sample_rdata==sample_data_before && !dut.vram_fast_pending)
                else $fatal(1,"AUDIO_QWORD_GRACE_CHANGED_RESPONSE_OR_FRONT");
            if(had_front) assert(commit_front)
                else $fatal(1,"AUDIO_QWORD_GRACE_RETAINED_FRONT_NOT_COMMITTED");
            if(commit_front) begin
                assert(dut.vram_write_buffer_data[slot]==wanted_line &&
                       dut.vram_write_buffer_be[slot]==wanted_be)
                    else $fatal(1,"AUDIO_QWORD_GRACE_FRONT_BYTES_OR_MASK");
                if(canonical) grace_front_merges++;
            end
            if(canonical) begin grace_commits++;grace_payload_checks++;end
            else edge_grace_commits++;
        end
        if(word3) begin
            if(pending_flush)
                assert(dut.state==MEM_ST_VRAM_BURST_WRITE && core_DDRAM_WE)
                    else $fatal(1,"AUDIO_QWORD_WORD3_BLOCKED_DRAIN");
            else if(pending_capture)
                assert(vram_qwrite_ack || vram_ack)
                    else $fatal(1,"AUDIO_QWORD_WORD3_BLOCKED_CAPTURE");
            if(canonical && (commit_front || vram_qwrite_ack || vram_ack ||
                             (pending_flush && core_DDRAM_WE))) word3_work_commits++;
        end
    end
end

// Independent finite edge-work producer; ACK is consumed only at posedge.
// Task stimulus is placed on negedges, and held until this registered consumer.
always @(posedge clk) begin : edge_write_consumer
    if(edge_active && edge_write_pending) begin
        if(vram_qwrite_ack) begin
            assert(vram_qwrite_req)
                else $fatal(1,"AUDIO_QWORD_EDGE_WRITE_UNOWNED");
            for(integer b=0;b<8;b++) begin
                if(vram_qwrite_be[b]) expected_vram[integer'(vram_qwrite_addr)*8+b]=
                    vram_qwrite_data[b*8+:8];
                edge_write_hash=hash_byte(edge_write_hash,vram_qwrite_data[b*8+:8]);
            end
            edge_write_hash=hash_byte(edge_write_hash,vram_qwrite_be);
            edge_writes++;
            if(edge_writer_age>edge_writer_max) edge_writer_max=edge_writer_age;
            edge_writer_age=0;
            edge_write_pending<=0;vram_qwrite_req<=0;
        end else begin
            edge_writer_age++;
            assert(edge_writer_age<SERVICE_BOUND)
                else $fatal(1,"AUDIO_QWORD_EDGE_WRITER_DEADLINE");
        end
    end
end

task automatic audio_qword_start_write(input integer address,input integer pattern);
    begin
        @(negedge clk);
        assert(!edge_write_pending && address>=0 && address<512)
            else $fatal(1,"AUDIO_QWORD_EDGE_WRITE_OVERLAP");
        vram_qwrite_addr=18'(address);vram_qwrite_data=write_data_for(pattern);
        vram_qwrite_be=write_mask_for(pattern);vram_qwrite_token=!vram_qwrite_token;
        vram_qwrite_req=1;edge_write_pending=1;edge_writer_age=0;
    end
endtask

task automatic audio_qword_wait_write;
    integer timeout;
    begin
        timeout=0;
        while(edge_write_pending && timeout<SERVICE_BOUND)begin @(negedge clk);timeout++;end
        assert(!edge_write_pending)else $fatal(1,"AUDIO_QWORD_EDGE_WRITE_TIMEOUT");
    end
endtask

task automatic audio_qword_wait_ack;
    integer timeout;
    begin
        timeout=0;
        while(!sample_ack && timeout<SERVICE_BOUND)begin @(negedge clk);timeout++;end
        assert(sample_ack && sample_req)
            else $fatal(1,"AUDIO_QWORD_EDGE_SAMPLE_TIMEOUT");
    end
endtask

task automatic audio_qword_consume_ack;
    begin
        @(posedge clk);
        assert(sample_ack && sample_req &&
               sample_rdata==sample_expected(sample_bank,sample_addr) &&
               dut.served_signature[MEM_CLIENT_SAMPLE]=={15'd0,sample_bank,sample_addr})
            else $fatal(1,"AUDIO_QWORD_EDGE_SAMPLE_DATA_OR_SIGNATURE");
        edge_samples++;
        edge_sample_hash=hash_byte(hash_byte(edge_sample_hash,sample_rdata[15:8]),
                                  sample_rdata[7:0]);
    end
endtask

task automatic audio_qword_wait_quiet;
    integer timeout;
    begin
        timeout=0;
        while((model_active || terminator.read_terminating || terminator.write_terminating ||
               dut.state!=MEM_ST_IDLE) && timeout<SERVICE_BOUND) begin
            @(negedge clk);timeout++;
            assert(!sample_ack)else $fatal(1,"AUDIO_QWORD_CANCEL_NEW_ACK");
        end
        assert(timeout<SERVICE_BOUND)else $fatal(1,"AUDIO_QWORD_CANCEL_DRAIN_TIMEOUT");
    end
endtask

task automatic audio_qword_finish_reload;
    integer timeout;
    begin
        repeat(3)begin @(negedge clk);assert(!sample_ack)
            else $fatal(1,"AUDIO_QWORD_RELOAD_OLD_ACK");end
        ioctl_download=0;timeout=0;
        while(!rom_loaded && timeout<2000) begin
            @(negedge clk);timeout++;
            assert(!sample_ack)else $fatal(1,"AUDIO_QWORD_RELOAD_STALE_ACK");
        end
        assert(rom_loaded)else $fatal(1,"AUDIO_QWORD_RELOAD_TIMEOUT");
        // VRAM_CLEAR_LINES=8: independently expected raw ff00 clear byte order.
        for(integer b=0;b<64;b++)expected_vram[b]=b[0] ? 8'hff : 8'h00;
        repeat(4)@(negedge clk);
        edge_reloads++;
    end
endtask

task automatic audio_qword_edge_suite;
    integer timeout, before_reads;
    logic [21:0] first_address;
    begin
        edge_active=1;cancel_test=1;
        for(integer c=0;c<8;c++)begin
            first_address=22'h50000+22'(c*256);
            // Six cases deliberately retain a full window and then present a
            // cross-block write during SAMPLE service. Reload cases begin with
            // no retained write: image replacement must not be confused with a
            // promise to preserve old-image buffered VRAM contents.
            if(c<6)begin
                for(integer w=0;w<16;w++)begin
                    audio_qword_start_write(w,c*32+w);audio_qword_wait_write();
                end
                repeat(3)@(negedge clk);
                assert(dut.vram_write_buffer_valid && !model_active)
                    else $fatal(1,"AUDIO_QWORD_EDGE_SEED_NOT_RETAINED");
            end
            @(negedge clk);sample_bank=0;sample_addr=first_address;sample_req=1;
            timeout=0;
            while(!(dut.state==MEM_ST_CAPTURE && dut.op_client==MEM_CLIENT_SAMPLE) &&
                  timeout<SERVICE_BOUND)begin @(negedge clk);timeout++;end
            assert(timeout<SERVICE_BOUND)else $fatal(1,"AUDIO_QWORD_EDGE_NO_FIRST_GRANT");
            if(c<6)audio_qword_start_write(16,c*32+16);
            audio_qword_wait_ack();
            if(c==4)begin quiesce=1;framework_reset=1;edge_quiesces++;end
            if(c==6)ioctl_download=1;
            audio_qword_consume_ack();
            case(c)
                0:begin
                    // No next word: grace must end after one clock despite req
                    // staying high on the already completed signature.
                    repeat(8)begin @(negedge clk);assert(!sample_ack)
                        else $fatal(1,"AUDIO_QWORD_HELD_DUPLICATE");edge_held_clocks++;end
                    sample_req=0;
                end
                1:sample_req<=0;
                2:begin sample_bank<=3;sample_addr<=first_address+22'd6;edge_retargets++;end
                3:begin sample_addr<=first_address+22'd1;edge_retargets++;end
                4,6:sample_req<=0;
                5,7:sample_addr<=first_address+22'd2;
                default:$fatal(1,"AUDIO_QWORD_BAD_EDGE_CASE");
            endcase
            if(c==2 || c==3)begin
                @(negedge clk);audio_qword_wait_ack();audio_qword_consume_ack();
                if(c==2)sample_req<=0;
                else begin
                    sample_addr<=first_address+22'd6;edge_retargets++;
                    @(negedge clk);audio_qword_wait_ack();audio_qword_consume_ack();sample_req<=0;
                end
            end
            if(c==4)begin
                repeat(8)begin @(negedge clk);assert(!sample_ack && !vram_qwrite_ack)
                    else $fatal(1,"AUDIO_QWORD_QUIESCED_NEW_ACK");end
                audio_qword_wait_quiet();repeat(3)@(negedge clk);
                framework_reset=0;quiesce=0;
            end
            if(c==5 || c==7)begin
                timeout=0;
                do begin @(negedge clk);timeout++;end
                while(!(dut.state==MEM_ST_CAPTURE && dut.op_client==MEM_CLIENT_SAMPLE) &&
                      timeout<SERVICE_BOUND);
                assert(timeout<SERVICE_BOUND && !sample_ack)
                    else $fatal(1,"AUDIO_QWORD_NO_FOLLOWING_GRANT");
                sample_req=0;
                if(c==5)begin
                    quiesce=1;framework_reset=1;edge_quiesces++;
                    repeat(8)begin @(negedge clk);assert(!sample_ack)
                        else $fatal(1,"AUDIO_QWORD_GRANTED_CANCEL_ACK");end
                    audio_qword_wait_quiet();repeat(3)@(negedge clk);
                    framework_reset=0;quiesce=0;
                end else ioctl_download=1;
            end
            if(c==6 || c==7)audio_qword_finish_reload();
            if(c==5 || c==6 || c==7)begin
                before_reads=sample_ddr_reads;
                @(negedge clk);sample_req=1;
                audio_qword_wait_ack();audio_qword_consume_ack();sample_req<=0;
                @(negedge clk);
                if(c>=6)assert(sample_ddr_reads==before_reads+1)
                    else $fatal(1,"AUDIO_QWORD_RELOAD_CACHE_NOT_INVALIDATED");
            end
            @(negedge clk);sample_req=0;
            audio_qword_wait_write();
            repeat(4)@(negedge clk);
            flush_and_score();
            edge_cases++;
        end
        assert(edge_cases==8 && edge_writes==102 && edge_samples==14 &&
               edge_held_clocks==8 && edge_retargets==3 && edge_quiesces==2 &&
               edge_reloads==2 && edge_word3==2 && edge_exceptions==2 &&
               edge_grace_eligible==10 && edge_writer_max<SERVICE_BOUND)
            else $fatal(1,"AUDIO_QWORD_EDGE_COVERAGE cases=%0d writes=%0d samples=%0d grace=%0d word3=%0d exceptions=%0d",
                edge_cases,edge_writes,edge_samples,edge_grace_eligible,edge_word3,edge_exceptions);
        if(enforce_grace)assert(edge_grace_commits==10)
            else $fatal(1,"AUDIO_QWORD_EDGE_NO_TEN_GRACES");
        $display("AUDIO_QWORD_EDGE_RESULT cases=%0d writes=%0d samples=%0d held_clocks=%0d retargets=%0d quiesces=%0d reloads=%0d grace_eligible=%0d grace_commits=%0d word3=%0d exceptions=%0d writer_max=%0d write_hash=%016x sample_hash=%016x final_hash=%016x final_bytes=4096",
            edge_cases,edge_writes,edge_samples,edge_held_clocks,edge_retargets,
            edge_quiesces,edge_reloads,edge_grace_eligible,edge_grace_commits,
            edge_word3,edge_exceptions,edge_writer_max,edge_write_hash,edge_sample_hash,final_hash);
        edge_active=0;
    end
endtask
