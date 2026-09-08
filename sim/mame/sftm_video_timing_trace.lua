-- Log the ITech32 video timing register set without modifying MAME.
--
-- This is equivalent to enabling LOG_SCREEN in itech32_v.cpp for the timing
-- question, but it also records HSYNC/VSYNC and de-duplicates transient writes
-- into stable end-of-frame configurations. Results belong outside the source
-- tree; set ITECH32_TIMING_TRACE to choose the output path.

local machine = manager.machine
local cpu = assert(machine.devices[":maincpu"])
local program = assert(cpu.spaces["program"])
local output_path = os.getenv("ITECH32_TIMING_TRACE") or "itech32-video-timing.log"
local output = assert(io.open(output_path, "w"))

local base = 0x500000
local frame = 0
local dirty = true
local last_signature = nil

local function reg16(offset)
	-- On the 68EC020 mapping, each 16-bit IT42 register is mirrored across
	-- one complete 32-bit CPU word. The logical offsets used by itech32_v.cpp
	-- therefore appear at twice their byte value in the CPU address space.
	return program:read_u16(base + offset * 2)
end

local function capture(reason)
	local vtotal = reg16(0x32)
	local vsync = reg16(0x34)
	local vbstart = reg16(0x36)
	local vbend = reg16(0x38)
	local htotal = reg16(0x3a)
	local hsync = reg16(0x3c)
	local hbstart = reg16(0x3e)
	local hbend = reg16(0x40)
	local signature = string.format(
		"%04x/%04x/%04x/%04x/%04x/%04x/%04x/%04x",
		htotal, hsync, hbstart, hbend,
		vtotal, vsync, vbstart, vbend)

	if signature ~= last_signature then
		local visible_h
		local visible_v
		if hbstart > hbend then
			visible_h = hbstart - hbend
		else
			visible_h = htotal - hbend + hbstart
		end
		if vbstart > vbend then
			visible_v = vbstart - vbend
		else
			visible_v = vtotal - vbend + vbstart
		end

		output:write(string.format(
			"time=%.9f frame=%d reason=%s pc=%08x " ..
			"HTOTAL=%04x HSYNC=%04x HBSTART=%04x HBEND=%04x " ..
			"VTOTAL=%04x VSYNC=%04x VBSTART=%04x VBEND=%04x " ..
			"visible=%dx%d\n",
			machine.time:as_double(), frame, reason, cpu.state["PC"].value,
			htotal, hsync, hbstart, hbend,
			vtotal, vsync, vbstart, vbend,
			visible_h, visible_v))
		output:flush()
		last_signature = signature
	end
end

local timing_tap = program:install_write_tap(
	base + 0x64, base + 0x83, "itech32_video_timing_w",
	function(_address, _data, _mask)
		dirty = true
	end)

-- MAME removes taps whose handles are garbage-collected.
_G.itech32_video_timing_tap = timing_tap

emu.register_frame_done(function()
	frame = frame + 1
	if dirty or frame == 1 then
		capture("frame_done")
		dirty = false
	end
end, "itech32_video_timing_trace")
