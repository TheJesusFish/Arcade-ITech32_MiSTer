`timescale 1ns/1ps
// PREPARATION ONLY. Requires the future candidate main_bus ports; there is no
// compatibility define that silently substitutes today's SFTM/TK decoder.
// Real main_bus + unchanged real blitter color latches. ROM/video targets are
// finite, owned, delayed testbench services, not vendor DDR/timing models.
module itech32_bloodstorm_bus_env #(parameter bit USE_PROGRAM_ROM = 0) (
    input logic clk, reset, timekill_mode, bloodstorm_mode,
    input logic rom_buffer_invalidate,
    input logic cpu_req, cpu_we,
    input logic [23:0] cpu_addr,
    input logic [31:0] cpu_wdata,
    input logic [3:0] cpu_be,
    output logic cpu_ack,
    output logic [31:0] cpu_rdata,
    input logic [31:0] input_p1, input_p2, input_p3, input_p4, input_dips, input_extra,
    input logic [14:0] palette_video_addr,
    output logic [23:0] palette_video_rgb,
    input logic rom_hold, rom_force_ack,
    input logic [7:0] image_id,
    input logic [31:0] program_rom_data,
    output logic rom_req,
    output logic [21:0] rom_addr,
    output logic rom_ack,
    output logic [31:0] rom_rdata,
    output logic sound_valid, watchdog, vint_ack, special_read, color0_we, color1_we,
    output logic [7:0] sound_data, color_data,
    output logic [1:0] plane_enable, grom_bank,
    output logic [15:0] color0_latch, color1_latch
);
    logic video_req, video_we, video_ack;
    logic [6:0] video_addr;
    logic [15:0] video_wdata, video_rdata;
    logic [1:0] video_be;
    integer rom_launches = 0, rom_responses = 0, rom_aborts = 0, video_launches = 0;
    integer sound_pulses = 0, watchdog_pulses = 0, vint_pulses = 0;
    integer special_pulses = 0, color0_pulses = 0, color1_pulses = 0;
    logic rom_owned = 0, rom_replied = 0, video_owned = 0;
    logic [21:0] owned_rom_addr;
    logic [31:0] owned_rom_data;
    logic [6:0] last_video_addr;
    logic [15:0] last_video_data;
    logic [1:0] last_video_be;
    logic last_video_we;
    integer rom_delay = 0, video_delay = 0;

    // Distinct full dword bytes expose lane swaps and image-epoch mistakes.
    // Callers supply the independently specified logical offset; no production
    // address decoder is reused by this function.
    function automatic logic [31:0] rom_pattern(input logic [21:0] offset,
                                               input logic [7:0] image);
        return {8'h91 ^ image ^ offset[7:0],
                8'h36 ^ image ^ offset[15:8],
                8'hc7 ^ image ^ {2'b00,offset[21:16]},
                8'h5a ^ image ^ offset[7:0] ^ offset[15:8]};
    endfunction

    itech32_main_bus bus (
        .clk(clk), .reset(reset), .timekill_mode(timekill_mode), .bloodstorm_mode(bloodstorm_mode),
        .rom_buffer_invalidate(rom_buffer_invalidate),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_be(cpu_be), .cpu_ack(cpu_ack), .cpu_rdata(cpu_rdata),
        .input_p1(input_p1), .input_p2(input_p2), .input_p3(input_p3), .input_p4(input_p4),
        .input_dips(input_dips), .input_extra(input_extra), .protection_address(15'd0),
		.nvram_host_access(1'b0),
		.nvram_host_write(1'b0), .nvram_host_addr(17'd0),
		.nvram_host_wdata(16'd0), .nvram_host_rdata(), .nvram_cpu_write(),
        .video_req(video_req), .video_we(video_we), .video_addr(video_addr),
        .video_wdata(video_wdata), .video_be(video_be), .video_ack(video_ack), .video_rdata(video_rdata),
        .rom_req(rom_req), .rom_addr(rom_addr), .rom_ack(rom_ack), .rom_rdata(rom_rdata),
        .sound_command_valid(sound_valid), .sound_command(sound_data), .watchdog_strobe(watchdog),
        .vint_ack_strobe(vint_ack), .special_read_strobe(special_read),
        .color0_strobe(color0_we), .color1_strobe(color1_we), .color_data(color_data),
        .plane_enable(plane_enable), .grom_bank(grom_bank),
        .palette_video_addr(palette_video_addr), .palette_video_rgb(palette_video_rgb)
    );
    logic unused_grom, unused_vram;
    itech32_blitter color_consumer (
        .clk(clk), .reset(reset), .timekill_mode(timekill_mode),
        .reg_req(1'b0), .reg_we(1'b0), .reg_addr(7'd0), .reg_wdata(16'd0), .reg_be(2'd0),
        .reg_ack(), .reg_rdata(), .color0_we(color0_we), .color1_we(color1_we), .color_data(color_data),
        .plane_enable(plane_enable), .grom_bank(grom_bank), .scanline_event(1'b0),
        .irq_blitter(), .irq_scanline(), .interrupt_state(), .busy(), .timing_int_scanline(),
        .timing_vtotal(), .timing_vsync(), .timing_vblank_start(), .timing_vblank_end(),
        .timing_htotal(), .timing_hsync(), .timing_hblank_start(), .timing_hblank_end(),
        .display_xorigin1(), .display_yorigin1(), .display_xorigin2(), .display_yorigin2(),
        .display_xscroll2(), .display_yscroll2(), .grom_req(unused_grom), .grom_addr(),
        .grom_ack(1'b0), .grom_rdata(64'd0), .vram_req(unused_vram), .vram_we(),
        .vram_plane(), .vram_addr(), .vram_wdata(), .vram_ack(1'b0), .vram_rdata(16'd0),
        .vram_writes_pending(1'b0)
    );
    assign color0_latch = color_consumer.color_latch[0];
    assign color1_latch = color_consumer.color_latch[1];
    assign rom_ack = rom_force_ack || (rom_owned && !rom_hold && rom_delay == 0 && rom_req);
    assign rom_rdata = rom_owned ? owned_rom_data : 32'hdeadc0de;
    assign video_ack = video_owned && video_delay == 0 && video_req;
    assign video_rdata = 16'h6000 | {9'd0,last_video_addr};

    always @(posedge clk) begin
        if (reset) begin
            if (rom_owned && !rom_replied) rom_aborts <= rom_aborts+1;
            rom_owned <= 0; rom_replied <= 0; video_owned <= 0;
        end else begin
            if (unused_grom || unused_vram) $fatal(1,"BLOOD_ENV_UNEXPECTED_COLOR_CONSUMER_WORK");
            if (!rom_owned && rom_req) begin
                rom_owned <= 1; rom_replied <= 0;
                owned_rom_addr <= rom_addr;
                // The transport returns the entire aligned 32-bit response;
                // address bits1:0 select CPU bytes later, not another dword.
                owned_rom_data <= USE_PROGRAM_ROM ? program_rom_data :
                    rom_pattern({rom_addr[21:2],2'b00},image_id);
                rom_delay <= 3; rom_launches <= rom_launches+1;
            end else if (rom_owned) begin
                if (rom_req && rom_addr !== owned_rom_addr) $fatal(1,"BLOOD_ROM_CHANGED_OWNED_ADDRESS");
                if (!rom_req) begin
                    if (!rom_replied) $fatal(1,"BLOOD_ROM_DROPPED_BEFORE_ACK");
                    rom_owned <= 0;
                end else if (rom_delay != 0) rom_delay <= rom_delay-1;
                else if (rom_ack && !rom_replied) begin rom_replied <= 1; rom_responses <= rom_responses+1; end
            end
            if (!video_owned && video_req) begin
                video_owned <= 1; video_delay <= 2; video_launches <= video_launches+1;
                last_video_addr <= video_addr; last_video_data <= video_wdata;
                last_video_be <= video_be; last_video_we <= video_we;
            end else if (video_owned) begin
                if (!video_req) video_owned <= 0;
                else begin
                    if ({video_addr,video_wdata,video_be,video_we} !== {last_video_addr,last_video_data,last_video_be,last_video_we})
                        $fatal(1,"BLOOD_VIDEO_CHANGED_OWNED_PAYLOAD");
                    if (video_delay != 0) video_delay <= video_delay-1;
                end
            end
            if (sound_valid) sound_pulses <= sound_pulses+1;
            if (watchdog) watchdog_pulses <= watchdog_pulses+1;
            if (vint_ack) vint_pulses <= vint_pulses+1;
            if (special_read) special_pulses <= special_pulses+1;
            if (color0_we) color0_pulses <= color0_pulses+1;
            if (color1_we) color1_pulses <= color1_pulses+1;
        end
    end
endmodule
