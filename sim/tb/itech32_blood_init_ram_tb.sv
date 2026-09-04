`timescale 1ns/1ps
// Actual main_bus / synchronous work RAM. No hierarchical memory writes or
// testbench-driven functional state. The parent comparison explicitly compiles
// with --x-initial 0; lower-zero results are RTL-model evidence, not FPGA init.
module itech32_blood_init_ram_tb;
    logic clk=0, reset=1, timekill_mode=0, bloodstorm_mode=1;
    logic rom_buffer_invalidate=0, cpu_req=0, cpu_we=0;
    logic [23:0] cpu_addr=0;
    logic [31:0] cpu_wdata=0, cpu_rdata;
    logic [3:0] cpu_be=0;
    logic cpu_ack;
    logic [31:0] input_p1=0,input_p2=0,input_p3=0,input_p4=0,input_dips=0,input_extra=0;
    logic [14:0] palette_video_addr=0;
    logic [23:0] palette_video_rgb;
    logic rom_hold=0,rom_force_ack=0;
    logic [7:0] image_id=0;
    logic [31:0] program_rom_data=0,rom_rdata;
    logic rom_req,rom_ack;
    logic [21:0] rom_addr;
    logic sound_valid,watchdog,vint_ack,special_read,color0_we,color1_we;
    logic [7:0] sound_data,color_data;
    logic [1:0] plane_enable,grom_bank;
    logic [15:0] color0_latch,color1_latch;
    itech32_bloodstorm_bus_env env(.*);
    always #5 clk=~clk;

    logic [31:0] expected_ram[0:16383];
    integer transactions=0,initial_words=0,lower_zero_bytes=0,upper_ff_bytes=0;
    integer upper_zero_bytes=0,dword_writes=0,byte_writes=0,pre_reset_words=0;
    integer post_reset_words=0,warm_resets=0,ack_count=0,latency_checks=0;
    integer held_ack_checks=0,reset_suppressed_edges=0;
    bit baseline_zero;
    string phase_name;

    function automatic logic [31:0] full_pattern(input integer word_index);
        return 32'h915ac736 ^ (32'(word_index)*32'h05030107);
    endfunction
    function automatic logic [7:0] byte_pattern(input integer byte_address);
        return 8'(8'hb3 ^ byte_address ^ (byte_address>>7) ^ (byte_address>>13));
    endfunction

    task automatic request(input bit write_cycle,input logic[23:0] address,
                           input logic[31:0] data,input logic[3:0] lanes,
                           input logic[31:0] expected);
        integer waits;
        @(negedge clk); #1;
        if(cpu_req || cpu_ack || env.rom_owned) $fatal(1,"BLOOD_INIT_NOT_DRAINED");
        cpu_req=1;cpu_we=write_cycle;cpu_addr=address;cpu_wdata=data;cpu_be=lanes;
        waits=0;
        do begin
            @(posedge clk);#1;waits++;
            if(waits>8) $fatal(1,"BLOOD_INIT_ACK_TIMEOUT phase=%s addr=%h",phase_name,address);
        end while(!cpu_ack);
        ack_count++;
        // Acceptance E0, response E1: preserve the actual registered RAM path.
        if(waits!=2) $fatal(1,"BLOOD_INIT_RAM_LATENCY phase=%s addr=%h got=%0d",phase_name,address,waits);
        latency_checks++;
        if(!write_cycle && cpu_rdata!==expected) begin
            if(phase_name=="initial" && address>=24'h008000 && !baseline_zero)
                $fatal(1,"BLOOD_INIT_INITIAL_FF addr=%06h actual=%08h expected=ffffffff",address,cpu_rdata);
            $fatal(1,"BLOOD_INIT_DATA phase=%s addr=%h actual=%h expected=%h",phase_name,address,cpu_rdata,expected);
        end
        // Leave the exact request asserted after ACK: no repeated ACK/write.
        repeat(2) begin
            @(posedge clk);#1;
            if(cpu_ack) $fatal(1,"BLOOD_INIT_DUPLICATE_ACK");
            held_ack_checks++;
        end
        @(negedge clk);#1;cpu_req=0;cpu_we=0;cpu_be=0;
        @(posedge clk);#1;
        if(cpu_ack) $fatal(1,"BLOOD_INIT_LATE_ACK");
        transactions++;
    endtask

    task automatic reset_bus;
        @(negedge clk);#1;reset=1;
        repeat(3) begin @(posedge clk);#1;if(cpu_ack) $fatal(1,"BLOOD_INIT_RESET_ACK"); end
        @(negedge clk);#1;reset=0;
        repeat(2) @(negedge clk);
    endtask

    initial begin
        integer i,w,b,lane,byte_address;
        logic [31:0] data;
        baseline_zero=$test$plusargs("BASELINE_ZERO");
        phase_name="cold_reset";
        reset_bus();
        phase_name="initial";
        for(i=0;i<16384;i++) begin
            expected_ram[i]=(i>=8192 && !baseline_zero)?32'hffffffff:32'h00000000;
            request(0,24'(i*4),0,4'hf,expected_ram[i]);
            initial_words++;
            if(i<8192) lower_zero_bytes+=4;
            else if(baseline_zero) upper_zero_bytes+=4;
            else upper_ff_bytes+=4;
        end

        phase_name="dword_write";
        for(i=0;i<16384;i++) begin
            // Odd affine multiplier traverses all14-bit physical word addresses.
            w=(i*4051+123)&16383;
            data=full_pattern(w);
            request(1,24'(w*4),data,4'hf,0);
            expected_ram[w]=data;dword_writes++;
        end
        phase_name="byte_write";
        for(i=0;i<16384;i++) begin
            w=(i*7919+8191)&16383;
            for(b=0;b<4;b++) begin
                // Address offsets are big-endian: byte+0 is BE3, byte+3 BE0.
                lane=(b+i)&3;byte_address=w*4+(3-lane);
                data={4{byte_pattern(byte_address)}};
                request(1,24'(byte_address),data,4'(1<<lane),0);
                expected_ram[w][lane*8+:8]=byte_pattern(byte_address);
                byte_writes++;
            end
        end
        phase_name="pre_reset_read";
        for(i=0;i<16384;i++) begin
            request(0,24'(i*4),0,4'hf,expected_ram[i]);pre_reset_words++;
        end

        // A real main_bus reset must not replay configuration-time contents.
        // Also hold a canary write while reset is high; reset must suppress it.
        phase_name="warm_reset";
        @(negedge clk);#1;reset=1;cpu_req=1;cpu_we=1;cpu_addr=24'h008000;
        cpu_be=4'hf;cpu_wdata=32'hdeadbeef;
        repeat(4) begin
            @(posedge clk);#1;
            if(cpu_ack) $fatal(1,"BLOOD_INIT_RESET_WRITE_ACK");
            reset_suppressed_edges++;
        end
        @(negedge clk);#1;cpu_req=0;cpu_we=0;cpu_be=0;
        @(negedge clk);#1;reset=0;warm_resets++;
        repeat(2) @(negedge clk);
        phase_name="post_reset_read";
        for(i=0;i<16384;i++) begin
            request(0,24'(i*4),0,4'hf,expected_ram[i]);post_reset_words++;
        end

        if(env.rom_launches!=0 || env.rom_responses!=0 || env.rom_aborts!=0 || env.video_launches!=0 ||
           env.sound_pulses!=0 || env.watchdog_pulses!=0 || env.vint_pulses!=0 ||
           env.special_pulses!=0 || env.color0_pulses!=0 || env.color1_pulses!=0)
            $fatal(1,"BLOOD_INIT_RAM_SIDE_EFFECT");
        if(initial_words!=16384 || lower_zero_bytes!=32768 ||
           (baseline_zero ? upper_zero_bytes!=32768 : upper_ff_bytes!=32768) ||
           dword_writes!=16384 || byte_writes!=65536 || pre_reset_words!=16384 ||
           post_reset_words!=16384 || warm_resets!=1 || transactions!=131072 ||
           ack_count!=transactions || latency_checks!=transactions || held_ack_checks!=2*transactions ||
           reset_suppressed_edges!=4)
            $fatal(1,"BLOOD_INIT_COVERAGE");
        $display("BLOOD_INIT_RAM_RESULT {\"baseline_zero\":%0d,\"initial_words\":%0d,\"lower_zero_bytes\":%0d,\"upper_ff_bytes\":%0d,\"upper_zero_bytes\":%0d,\"dword_writes\":%0d,\"byte_writes\":%0d,\"pre_reset_words\":%0d,\"post_reset_words\":%0d,\"warm_resets\":%0d,\"transactions\":%0d,\"ack_count\":%0d,\"latency_checks\":%0d,\"held_ack_checks\":%0d,\"reset_suppressed_edges\":%0d,\"downstream_transactions\":0}",
                 baseline_zero,initial_words,lower_zero_bytes,upper_ff_bytes,upper_zero_bytes,
                 dword_writes,byte_writes,pre_reset_words,post_reset_words,warm_resets,
                 transactions,ack_count,latency_checks,held_ack_checks,reset_suppressed_edges);
        $display("BLOOD_INIT_RAM_PASS actual_main_bus=1 baseline_zero=%0d",baseline_zero);
        $finish;
    end
    initial begin #20000000;$fatal(1,"BLOOD_INIT_GLOBAL_TIMEOUT");end
endmodule
