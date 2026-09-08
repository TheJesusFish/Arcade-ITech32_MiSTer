# MAME reference probes

## SFTM video timing

Run `sftm_video_timing_trace.lua` through MAME's `-autoboot_script` option to
record the stable IT42 timing tuple written by the game. The probe watches the
68EC020 video-register aperture, includes HSYNC and VSYNC in addition to the six
values printed by MAME's `LOG_SCREEN`, and de-duplicates initialization writes
at frame boundaries. Set `ITECH32_TIMING_TRACE` to an output path outside the
repository. A long `-bench` run can cover complete attract loops without host
input or real-time throttling.

This establishes software-programmed counts and whether they change at runtime;
it does not measure the physical PCB pixel clock. Generated logs must not be
added to this repository.

## NVRAM oracle

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
