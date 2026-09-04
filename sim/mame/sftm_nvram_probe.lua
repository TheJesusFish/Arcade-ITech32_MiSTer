-- Capture a deterministic reload checkpoint for an existing SFTM NVRAM file.

local frame = 0

local function frame_done()
	frame = frame + 1
	if frame == 480 then
		print("SFTM_NVRAM_PROBE: taking reload snapshot")
		manager.machine.video:snapshot()
	elseif frame == 500 then
		print("SFTM_NVRAM_PROBE: requesting clean exit")
		manager.machine:exit()
	end
end

emu.register_frame_done(frame_done, "sftm_nvram_probe")
