# MAME NVRAM oracle

These ROM-free Lua scripts reproduce the Street Fighter: The Movie v1.10
first-boot NVRAM sequence using MAME's emulated cabinet inputs. They do not use
host keyboard automation, audio capture, ROM-derived constants, or private game
data.

Run `sftm_nvram_init.lua` with MAME's `-autoboot_script` option and an isolated
`-nvram_directory`. It discovers Player 1 Start from MAME's I/O-port metadata,
pulses the emulated switch, and requests a clean exit after 1,800 frames. Run it
twice against the same isolated directory. Then run `sftm_nvram_probe.lua` once
to capture the following boot without injecting input.

MAME 0.288 and the MiSTer core show the same sequence. The first persisted SFTM
image can show the battery warning again while the raw MAME bytes at `0x54` and
`0x55` change from `ff` to `00`. In MiSTer's 32-bit word-reversed file order,
those are offsets `0x56` and `0x57`. The next boot proceeds normally. BloodStorm
creates a 64 KiB image on the first OSD-open save and reports `SYSTEM STATUS OK`
on the next MRA reload.

Generated NVRAM files and snapshots belong in an external temporary directory;
they must not be added to this repository.
