-- Produce a clean Street Fighter: The Movie NVRAM image without host input.
--
-- Run this through MAME's -autoboot_script option.  It finds Player 1 Start
-- from the emulated I/O-port metadata, pulses it at several points during the
-- boot sequence, then requests a clean emulator exit so MAME flushes NVRAM.
-- No keyboard, controller, audio, video-capture, or ROM-derived data is used.

local frame = 0
local start_field = nil

for tag, port in pairs(manager.machine.ioport.ports) do
	for name, field in pairs(port.fields) do
		local lower_name = string.lower(name)
		if (field.player == 0) and string.find(lower_name, "start", 1, true) then
			start_field = field
			print(string.format("SFTM_NVRAM: using %s/%s", tag, name))
			break
		end
	end
	if start_field then
		break
	end
end

if not start_field then
	error("SFTM_NVRAM: Player 1 Start field was not found")
end

local function set_start(active)
	if active then
		start_field:set_value(1)
	else
		start_field:clear_value()
	end
end

local function frame_done()
	frame = frame + 1

	-- Repeated pulses make the harness insensitive to normal boot-time
	-- variation while still behaving exactly like a cabinet Start input.
	if (frame == 300) or (frame == 600) or (frame == 900) then
		set_start(true)
		print(string.format("SFTM_NVRAM: Start pressed at frame %d", frame))
	elseif (frame == 330) or (frame == 630) or (frame == 930) then
		set_start(false)
		print(string.format("SFTM_NVRAM: Start released at frame %d", frame))
	elseif frame == 1800 then
		set_start(false)
		print("SFTM_NVRAM: requesting clean exit")
		manager.machine:exit()
	end
end

emu.register_frame_done(frame_done, "sftm_nvram_init")
