`timescale 1ns/1ps
// PREPARED, NOT YET RUN. This top deliberately requires the candidate's real
// bloodstorm_mode/input_extra ports. There is no mocked BloodStorm decoder.
// Literal MAME bloodstm_map/byte-lane examples are independent of DUT decoding.
module itech32_bloodstorm_main_bus_tb;
    logic clk=0, reset=1, timekill_mode=0, bloodstorm_mode=1;
    logic rom_buffer_invalidate=0, cpu_req=0, cpu_we=0;
    logic [23:0] cpu_addr=0;
    logic [31:0] cpu_wdata=0, cpu_rdata;
    logic [3:0] cpu_be=0;
    logic cpu_ack;
    logic [31:0] input_p1=32'h00f70000, input_p2=32'h00fe0000;
    logic [31:0] input_p3=0, input_p4=32'h00ff0000;
    logic [31:0] input_dips=32'h00aa0000, input_extra=32'h00de0000;
    logic [14:0] palette_video_addr=0;
    logic [23:0] palette_video_rgb;
    logic rom_hold=0, rom_force_ack=0;
    logic [7:0] image_id=0;
    logic [31:0] program_rom_data=0, rom_rdata;
    logic rom_req,rom_ack;
    logic [21:0] rom_addr;
    logic sound_valid,watchdog,vint_ack,special_read,color0_we,color1_we;
    logic [7:0] sound_data,color_data;
    logic [1:0] plane_enable,grom_bank;
    logic [15:0] color0_latch,color1_latch;
    integer transactions=0, ram_writes=0, ram_reads=0, palette_cases=0;
    integer rom_cases=0, mmio_cases=0, negative_kind=0, last_wait_edges=0;
    integer before_sound,before_watchdog,before_vint,before_special,before_c0,before_c1;
    integer rom_before, video_before;
    logic [31:0] old_image_data;
    // The real sound board consumes only valid-qualified payloads. Unqualified
    // sound_data is allowed to change when a mapped high byte is ignored.
    logic [7:0] accepted_sound_data=0;
    itech32_bloodstorm_bus_env env (.*);
    always #5 clk=~clk;
    always @(posedge clk) if(!reset && sound_valid) accepted_sound_data<=sound_data;
    initial begin #20000000; $fatal(1,"BLOOD_BUS_GLOBAL_TIMEOUT"); end

    // First eligible posedge after start_request is board acceptance E0.
    // E0 registered local-hit ACK => one observed edge; ordinary unmapped
    // E1 ACK => two. This is NOT the adapter's later first-CE schedule.
    task automatic start_request(input logic [23:0] addr, input logic wr,
                                  input logic [31:0] data, input logic [3:0] be);
        @(negedge clk); #1;
        if(cpu_req || cpu_ack || env.rom_owned) $fatal(1,"BLOOD_BUS_UNDRAINED_START");
        before_sound=env.sound_pulses;before_watchdog=env.watchdog_pulses;
        before_vint=env.vint_pulses;before_special=env.special_pulses;
        before_c0=env.color0_pulses;before_c1=env.color1_pulses;
        cpu_addr=addr;cpu_we=wr;cpu_wdata=data;cpu_be=be;cpu_req=1;
    endtask
    task automatic finish_request(input logic [31:0] expected,mask,
                                   input logic [5:0] effects,
                                   input logic check_collision=0,
                                   input logic [23:0] collision_rgb=0);
        logic [31:0] observed;
        integer waits;
        waits=0;
        // A caller may already have waited for an explicitly held ROM owner.
        // No such caller may have let its ACK escape before entering here.
        do begin
            @(posedge clk); #1; waits++;
            if(waits>128) $fatal(1,"BLOOD_BUS_ACK_TIMEOUT addr=%06x",cpu_addr);
        end while(!cpu_ack);
        observed=cpu_rdata;
        if(negative_kind==1 && !cpu_we && mask!=0) observed^=32'h00000001;
        if((observed & mask)!==(expected & mask))
            $fatal(1,"BLOOD_BUS_DATA addr=%06x got=%08x expected=%08x mask=%08x",cpu_addr,observed,expected,mask);
        if(check_collision && palette_video_rgb!==collision_rgb)
            $fatal(1,"BLOOD_PALETTE_COLLISION got=%06x expected=%06x",palette_video_rgb,collision_rgb);
        last_wait_edges=waits;
        repeat(3) begin @(posedge clk); #1; if(cpu_ack) $fatal(1,"BLOOD_BUS_DUP_ACK"); end
        @(negedge clk); #1;cpu_req=0;cpu_we=0;cpu_be=0;
        repeat(3) begin @(posedge clk); #1; if(cpu_ack) $fatal(1,"BLOOD_BUS_LATE_ACK"); end
        if(env.sound_pulses-before_sound!=int'(effects[5]) ||
           env.watchdog_pulses-before_watchdog!=int'(effects[4]) ||
           env.vint_pulses-before_vint!=int'(effects[3]) ||
           env.special_pulses-before_special!=int'(effects[2]) ||
           env.color0_pulses-before_c0!=int'(effects[1]) ||
           env.color1_pulses-before_c1!=int'(effects[0]))
            $fatal(1,"BLOOD_BUS_SIDE_EFFECT_COUNT addr=%06x effects=%02x",cpu_addr,effects);
        transactions++;
    endtask
    task automatic access(input logic [23:0] addr, input logic wr,
                          input logic [31:0] data, input logic [3:0] be,
                          input logic [31:0] expected=0,mask=0,
                          input logic [5:0] effects=0);
        start_request(addr,wr,data,be);finish_request(expected,mask,effects);
    endtask
    function automatic logic [31:0] ram_pattern(input integer word_index);
        return 32'ha5005a00 ^ (32'(word_index)*32'h01010101);
    endfunction
    task automatic read_rom(input logic [23:0] addr,input logic [21:0] offset,
                            input logic [7:0] image,input integer expected_launches,
                            input logic [3:0] be=4'hf);
        integer launches;
        launches=env.rom_launches;
        access(addr,0,0,be,env.rom_pattern(offset,image),32'hffffffff);
        if(env.rom_launches-launches!=expected_launches)
            $fatal(1,"BLOOD_ROM_LAUNCH_COUNT addr=%06x delta=%0d",addr,env.rom_launches-launches);
        if(expected_launches==0 && last_wait_edges!=1) $fatal(1,"BLOOD_ROM_LOCAL_REGISTERED_ACK");
        if(expected_launches!=0 && last_wait_edges<5) $fatal(1,"BLOOD_ROM_MISS_TOO_EARLY");
        rom_cases++;
    endtask
    task automatic invalidate_once;
        @(negedge clk);#1;rom_buffer_invalidate=1;
        @(negedge clk);#1;rom_buffer_invalidate=0;
    endtask
    task automatic reset_drained;
        @(negedge clk);#1;reset=1;
        repeat(3) @(negedge clk);
        #1;reset=0;repeat(3) @(negedge clk);
    endtask
    task automatic palette_write(input logic [23:0] addr,input logic [31:0] data,
                                  input logic [3:0] be,input logic [31:0] stored,
                                  input logic [23:0] rgb);
        start_request(addr,1,data,be);
        finish_request(0,0,0,1,rgb); // exact commit edge: normalized collision bytes
        access({addr[23:2],2'b00},0,0,4'hf,stored,32'hffffffff);
        if(palette_video_rgb!==rgb) $fatal(1,"BLOOD_PALETTE_STORED_RGB");
        palette_cases++;
    endtask
    task automatic video_access(input logic [23:0] addr,input logic wr,
                                input logic [31:0] data,input logic [3:0] be,
                                input logic [6:0] index,input logic [15:0] half,
                                input logic [1:0] half_be,input logic [31:0] returned);
        integer count_before;
        count_before=env.video_launches;
        access(addr,wr,data,be,returned,wr?32'd0:32'hffffffff);
        if(env.video_launches!=count_before+1 || env.last_video_addr!==index ||
           env.last_video_data!==half || env.last_video_be!==half_be || env.last_video_we!==wr)
            $fatal(1,"BLOOD_VIDEO_ALIAS_OR_LANES addr=%06x",addr);
        mmio_cases++;
    endtask

    initial begin
        void'($value$plusargs("NEGATIVE=%d",negative_kind));
        repeat(4) @(negedge clk);#1;reset=0;
        // Board-side exhaustive physical RAM sweep. Unlike actual TG68, this
        // reaches the 128-byte vector underlay as well as 0x0080..0xffff.
        for(integer n=0;n<16384;n++) begin
            access(24'(n*4),1,ram_pattern(n),4'hf);ram_writes++;
        end
        for(integer n=16383;n>=0;n--) begin
            access(24'(n*4),0,0,4'hf,ram_pattern(n),32'hffffffff);ram_reads++;
        end
        access(24'h000100,1,32'h11223344,4'hf);
        access(24'h008100,1,32'ha1b2c3d4,4'hf);
        access(24'h000100,0,0,4'hf,32'h11223344,32'hffffffff);
        access(24'h008100,0,0,4'hf,32'ha1b2c3d4,32'hffffffff);
        access(24'h007ffc,1,32'h12341357,4'hf);
        access(24'h00fffc,1,32'habcd2468,4'hf);
        access(24'h007fff,1,32'h0000009a,4'h1);
        access(24'h00ffff,1,32'h000000bc,4'h1);
        access(24'h007ffe,0,0,4'h3,32'h1234139a,32'hffffffff);
        access(24'h00fffe,0,0,4'h3,32'habcd24bc,32'hffffffff);
        access(24'h010000,1,32'hffffffff,4'hf);
        access(24'h010000,0,0,4'hf,32'hffffffff,32'hffffffff);
        access(24'h000000,0,0,4'hf,ram_pattern(0),32'hffffffff);
        reset_drained();
        access(24'h000100,0,0,4'hf,32'h11223344,32'hffffffff);
        access(24'h008100,0,0,4'hf,32'ha1b2c3d4,32'hffffffff);
        access(24'h00fffe,0,0,4'h3,32'habcd24bc,32'hffffffff);

        // Exact 16-bit input apertures and +2 rejection (no SFTM dword alias).
        access(24'h080000,0,0,4'hc,32'h00f70000,32'hffffffff);
        access(24'h100001,0,0,4'h4,32'h00fe0000,32'hffffffff);
        access(24'h180000,0,0,4'hc,32'h00000000,32'hffffffff);
        access(24'h200000,0,0,4'hc,32'h00ff0000,32'hffffffff);
        access(24'h280000,0,0,4'hc,32'h00aa0000,32'hffffffff,6'b000100);
        access(24'h280001,0,0,4'h4,32'h00aa0000,32'hffffffff,6'b000100);
        access(24'h780000,0,0,4'hc,32'h00de0000,32'hffffffff);
        for(integer n=0;n<7;n++) begin : input_neighbor
            case(n)
                0:access(24'h080002,0,0,4'h3,32'hffffffff,32'hffffffff);
                1:access(24'h100002,0,0,4'h3,32'hffffffff,32'hffffffff);
                2:access(24'h180002,0,0,4'h3,32'hffffffff,32'hffffffff);
                3:access(24'h200002,0,0,4'h3,32'hffffffff,32'hffffffff);
                4:access(24'h280002,0,0,4'h3,32'hffffffff,32'hffffffff);
                5:access(24'h780002,0,0,4'h3,32'hffffffff,32'hffffffff);
                6:access(24'h600000,0,0,4'hf,32'hffffffff,32'hffffffff);
            endcase
        end
        access(24'h080000,1,32'h12340000,4'hc,0,0,6'b001000);
        access(24'h080001,1,32'h00560000,4'h4,0,0,6'b001000);
        access(24'h080002,1,32'h00001234,4'h3);
        access(24'h200000,1,32'h12340000,4'hc,0,0,6'b010000);
        access(24'h200001,1,32'h00560000,4'h4,0,0,6'b010000);
        access(24'h200002,1,32'h00001234,4'h3);
        access(24'h400000,1,32'h12340000,4'hc,0,0,6'b010000);
        access(24'h400001,1,32'h00560000,4'h4,0,0,6'b010000);
        access(24'h400002,1,32'h00001234,4'h3);
        access(24'h280000,1,32'h12340000,4'hc); // read-only DIPS, not TK watchdog
        mmio_cases+=24;

        access(24'h700001,1,32'h00c40000,4'h4);
        if(plane_enable!==2'b01 || grom_bank!==0) $fatal(1,"BLOOD_PLANE_BANK_C4");
        access(24'h300001,1,32'h00a50000,4'h4,0,0,6'b000010);
        if(color0_latch!==16'h2500 || plane_enable!==2'b01 || grom_bank!==0)
            $fatal(1,"BLOOD_COLOR0_NOT_TK");
        access(24'h300000,1,32'h12da0000,4'hc,0,0,6'b000010);
        if(color0_latch!==16'h5a00 || plane_enable!==2'b01) $fatal(1,"BLOOD_COLOR0_WORD");
        access(24'h380001,1,32'h00e30000,4'h4,0,0,6'b000001);
        if(color1_latch!==16'h6300) $fatal(1,"BLOOD_COLOR1_NOT_TK");
        access(24'h380000,1,32'h127c0000,4'hc,0,0,6'b000001);
        if(color1_latch!==16'h7c00) $fatal(1,"BLOOD_COLOR1_WORD");
        // Complete odd-byte decode: adjacent even high byte cannot fire, and
        // neither +2 nor +3 may inherit the SFTM low-dword-byte alias.
        access(24'h300000,1,32'hff000000,4'h8);
        access(24'h300002,1,32'h0000ff00,4'h2);
        access(24'h300003,1,32'h000000ff,4'h1);
        access(24'h380000,1,32'hff000000,4'h8);
        access(24'h380002,1,32'h0000ff00,4'h2);
        access(24'h380003,1,32'h000000ff,4'h1);
        if(color0_latch!==16'h5a00 || color1_latch!==16'h7c00) $fatal(1,"BLOOD_COLOR_REJECT");
        access(24'h480000,1,32'h125a0000,4'hc,0,0,6'b100000);
        if(accepted_sound_data!==8'h5a) $fatal(1,"BLOOD_SOUND_WORD");
        access(24'h480001,1,32'h00c30000,4'h4,0,0,6'b100000);
        if(accepted_sound_data!==8'hc3) $fatal(1,"BLOOD_SOUND_ODD");
        access(24'h480000,1,32'hff000000,4'h8);
        access(24'h480002,1,32'h0000ff00,4'h2);
        access(24'h480003,1,32'h000000ff,4'h1);
        if(accepted_sound_data!==8'hc3) $fatal(1,"BLOOD_SOUND_REJECT");
        access(24'h700000,1,32'hff000000,4'h8);
        access(24'h700002,1,32'h0000ff00,4'h2);
        access(24'h700003,1,32'h000000ff,4'h1);
        if(plane_enable!==2'b01 || grom_bank!==0) $fatal(1,"BLOOD_PLANE_REJECT");
        access(24'h700000,1,32'h12000000,4'hc);
        if(plane_enable!==2'b11 || grom_bank!==0) $fatal(1,"BLOOD_PLANE_WORD_00");
        access(24'h700001,1,32'h00020000,4'h4);
        if(plane_enable!==2'b10 || grom_bank!==0) $fatal(1,"BLOOD_PLANE_02");
        access(24'h700001,1,32'h00c60000,4'h4);
        if(plane_enable!==0 || grom_bank!==0) $fatal(1,"BLOOD_PLANE_06");
        access(24'h700001,0,0,4'h4,32'hffffffff,32'hffffffff);
        mmio_cases+=23;

        video_access(24'h500008,1,32'h12340000,4'hc,7'd2,16'h1234,2'b11,0);
        video_access(24'h50000a,1,32'h00005678,4'h3,7'd2,16'h5678,2'b11,0);
        video_access(24'h50000c,1,32'h9a000000,4'h8,7'd3,16'h9a00,2'b10,0);
        video_access(24'h50000b,1,32'h000000bc,4'h1,7'd2,16'h00bc,2'b01,0);
        video_access(24'h5000fe,0,0,4'h3,7'd63,0,2'b11,32'h0000603f);
        video_access(24'h500008,0,0,4'hc,7'd2,0,2'b11,32'h60020000);
        video_before=env.video_launches;
        access(24'h500100,0,0,4'hc,32'hffffffff,32'hffffffff);
        if(env.video_launches!=video_before) $fatal(1,"BLOOD_VIDEO_APERTURE_END");

        // xBGR_888 little-endian MAME word assembly: CPU bytes12,34,AB,CD
        // become RGB34,12,CD. Lower-half MSB-only write folds onto byte+3.
        palette_video_addr=15'd9;
        palette_write(24'h580024,32'h1234abcd,4'hf,32'h1234abcd,24'h3412cd);
        palette_write(24'h580026,32'h00005600,4'h2,32'h1234ab56,24'h341256);
        palette_write(24'h580027,32'h00000078,4'h1,32'h1234ab78,24'h341278);
        palette_write(24'h580026,32'h00009056,4'h3,32'h12349056,24'h341256);
        palette_write(24'h580024,32'h9a000000,4'h8,32'h9a349056,24'h349a56);
        palette_write(24'h580025,32'h00bc0000,4'h4,32'h9abc9056,24'hbc9a56);
        // Nonmatching video address must not consume a CPU collision bypass.
        access(24'h580028,1,32'h2244aa66,4'hf);
        if(palette_video_rgb!==24'hbc9a56) $fatal(1,"BLOOD_PALETTE_NONMATCH_COLLISION");
        @(negedge clk);#1;palette_video_addr=15'd10;#1;
        if(palette_video_rgb!==24'hbc9a56) $fatal(1,"BLOOD_PALETTE_ASYNC_LEAK");
        @(posedge clk);#1;
        if(palette_video_rgb!==24'h442266) $fatal(1,"BLOOD_PALETTE_ONE_EDGE_LATENCY");
        @(negedge clk);#1;palette_video_addr=15'd9;
        @(posedge clk);#1;
        if(palette_video_rgb!==24'hbc9a56) $fatal(1,"BLOOD_PALETTE_BACK_EDGE_LATENCY");
        palette_video_addr=15'h7fff;
        palette_write(24'h59fffc,32'h11335577,4'hf,32'h11335577,24'h331177);
        palette_write(24'h59fffe,32'h00009900,4'h2,32'h11335599,24'h331199);
        access(24'h5a0000,1,32'hffffffff,4'hf);
        access(24'h59fffc,0,0,4'hf,32'h11335599,32'hffffffff);

        // Sixteen exact 512-KiB mirrors, not a guessed larger power-of-two ROM.
        for(integer mirror=0;mirror<16;mirror++) begin
            read_rom(24'h800340+24'(mirror*524288),22'h000340,0,1);
        end
        read_rom(24'hf80342,22'h000340,0,0);
        read_rom(24'hf80340,22'h000340,0,0);
        read_rom(24'hfffffe,22'h07fffc,0,1);
        read_rom(24'h800000,22'h000000,0,1);
        read_rom(24'h87fffe,22'h07fffc,0,1);
        // A write whose address was a resident ROM read must remain ignored;
        // neither a new downstream request nor the local-hit ACK shortcut.
        rom_before=env.rom_launches;
        access(24'h87fffc,1,32'h11112222,4'hf);
        if(env.rom_launches!=rom_before || last_wait_edges!=2) $fatal(1,"BLOOD_ROM_WRITE_ELIGIBILITY");
        read_rom(24'h87fffe,22'h07fffc,0,0);

        read_rom(24'h800340,22'h000340,0,1);
        read_rom(24'h800340,22'h000340,0,0,4'h8);
        read_rom(24'h800341,22'h000340,0,0,4'h4);
        read_rom(24'h800342,22'h000340,0,0,4'h2);
        read_rom(24'h800343,22'h000340,0,0,4'h1);
        image_id=1;invalidate_once();
        read_rom(24'h800340,22'h000340,1,1);
        read_rom(24'h800342,22'h000340,1,0);
        // Full profile key is required even when the old TK bit remains zero.
        @(negedge clk);#1;bloodstorm_mode=0;image_id=2;
        repeat(2) @(negedge clk);
        read_rom(24'h800340,22'h000340,2,1);
        @(negedge clk);#1;bloodstorm_mode=1;image_id=3;
        repeat(2) @(negedge clk);
        read_rom(24'h800340,22'h000340,3,1);
        @(negedge clk);#1;bloodstorm_mode=0;timekill_mode=1;image_id=4;
        repeat(2) @(negedge clk);
        read_rom(24'h100340,22'h000340,4,1);
        @(negedge clk);#1;timekill_mode=0;bloodstorm_mode=1;image_id=5;
        repeat(2) @(negedge clk);
        read_rom(24'h800340,22'h000340,5,1);
        // Warm reset queries the resident address FIRST, avoiding replacement
        // by an unrelated post-reset miss that could hide stale validity.
        reset_drained();image_id=6;
        read_rom(24'h800340,22'h000340,6,1);
        read_rom(24'h800342,22'h000340,6,0);

        // Delayed old-image response survives mode ABA but cannot allocate.
        // Low offset is intentionally mapping-stable for Blood<->SFTM, so
        // this does not abuse the inherited live payload mode limitation.
        invalidate_once();rom_hold=1;image_id=7;
        start_request(24'h800340,0,0,4'hf);
        wait(env.rom_owned);@(negedge clk);#1;
        old_image_data=env.rom_pattern(22'h000340,7);
        image_id=8;bloodstorm_mode=0;
        @(negedge clk);#1;bloodstorm_mode=1;
        @(negedge clk);#1;rom_hold=0;
        finish_request(old_image_data,32'hffffffff,0);
        read_rom(24'h800340,22'h000340,8,1);
        read_rom(24'h800342,22'h000340,8,0);

        // Two invalidations cannot toggle-cancel back into an eligible fill.
        invalidate_once();rom_hold=1;image_id=9;
        start_request(24'h800380,0,0,4'hf);wait(env.rom_owned);
        invalidate_once();invalidate_once();image_id=10;
        @(negedge clk);#1;rom_hold=0;
        finish_request(env.rom_pattern(22'h000380,9),32'hffffffff,0);
        read_rom(24'h800380,22'h000380,10,1);
        read_rom(24'h800382,22'h000380,10,0);
        // Invalidation coincident with an otherwise-hit acceptance must miss.
        start_request(24'h800380,0,0,4'hf);
        rom_buffer_invalidate=1;image_id=11;
        fork
            begin @(negedge clk);#1;rom_buffer_invalidate=0; end
            begin finish_request(env.rom_pattern(22'h000380,11),32'hffffffff,0); end
        join
        read_rom(24'h800380,22'h000380,11,1);

        // Explicit invalidate on the owned ACK edge cancels fill, not delivery.
        invalidate_once();rom_hold=1;image_id=12;
        start_request(24'h8003c0,0,0,4'hf);wait(env.rom_owned);
        repeat(6) @(negedge clk);
        #1;rom_buffer_invalidate=1;rom_hold=0;image_id=13;
        finish_request(env.rom_pattern(22'h0003c0,12),32'hffffffff,0);
        @(negedge clk);#1;rom_buffer_invalidate=0;
        read_rom(24'h8003c0,22'h0003c0,13,1);
        // Unowned ACK has no response/allocation owner. It must not publish.
        invalidate_once();rom_force_ack=1;
        repeat(3) begin @(posedge clk);#1;if(cpu_ack) $fatal(1,"BLOOD_ROM_ORPHAN_ACK");end
        @(negedge clk);#1;rom_force_ack=0;image_id=14;
        read_rom(24'h8003c0,22'h0003c0,14,1);

        // Reset abandons an in-flight *different* address. A later orphan ACK
        // uses poison data, then the pre-reset resident is queried FIRST.
        // This is a modeled delayed ACK, not proof of the top loader wiring.
        rom_hold=1;start_request(24'h800400,0,0,4'hf);wait(env.rom_owned);
        @(negedge clk);#1;reset=1;cpu_req=0;cpu_be=0;
        repeat(3) @(negedge clk);
        #1;reset=0;rom_force_ack=1;rom_hold=0;image_id=15;
        repeat(3) begin @(posedge clk);#1;if(cpu_ack) $fatal(1,"BLOOD_ROM_POST_RESET_ORPHAN");end
        @(negedge clk);#1;rom_force_ack=0;
        read_rom(24'h8003c0,22'h0003c0,15,1);
        read_rom(24'h8003c2,22'h0003c0,15,0);

        if(ram_writes!=16384 || ram_reads!=16384 || palette_cases!=8 || rom_cases!=44 ||
           env.rom_owned || cpu_req || env.rom_aborts!=1 || env.rom_launches!=env.rom_responses+env.rom_aborts)
            $fatal(1,"BLOOD_BUS_COVERAGE_OR_TAIL");
        $display("BLOOD_MAIN_BUS_PASS transactions=%0d physical_ram_bytes=65536 ram_writes=%0d ram_reads=%0d palette_cases=%0d rom_cases=%0d mmio_cases=%0d rom_launches=%0d rom_acks=%0d reset_aborts=%0d candidate_ports=1",
            transactions,ram_writes,ram_reads,palette_cases,rom_cases,mmio_cases,env.rom_launches,env.rom_responses,env.rom_aborts);
        $finish;
    end
endmodule
