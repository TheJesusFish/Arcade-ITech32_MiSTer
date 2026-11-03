# Persistent board NVRAM

The core persists the actual RAM seen by each game rather than maintaining a
detached settings copy:

| Board profile | CPU aperture | Saved bytes | Backing store |
| --- | --- | ---: | --- |
| Street Fighter: The Movie, World Class Bowling v1.6x/Deluxe, Shuffleshot, Golden Tee, Power Up Baseball, Must Shoot TV | `0x600000-0x61ffff` | 131072 | dedicated 128 KiB NVRAM |
| BloodStorm, Hard Yardage, Pairs family, World Class Bowling v1.0-1.5 | `0x000000-0x00ffff` | 65536 | complete work RAM |
| Time Killers | `0x000000-0x003fff` | 16384 | low 16 KiB of work RAM |
| Golden Tee and World Class Bowling tournament editions | `0x600000-0x61ffff`, then `0x681000-0x6817ff` | 133120 | dedicated 128 KiB NVRAM, then the M48T02 timekeeper's 2 KiB |

The tournament boards' M48T02 maps one byte per CPU address (offset `n` at
`0x681000 + n`). Its 2 KiB follows the 128 KiB store in the saved image, in
offset order, so the file is MAME's `nvram32` and `m48t02` images
concatenated. The last eight bytes are the clock registers; as in MAME, the
saved copies are not restored into the running clock, which restarts from the
MiSTer clock at each game load (`docs/DEVELOPMENT.md`).

Each MRA declares `<nvram index="2" size="..."/>`. Main_MiSTer restores index 2
through the ordinary download interface and saves it through the upload
interface. The core marks the store dirty on a game-side write and requests one
upload on the next OSD-opening edge. This matches the established Cave and
Batsugun core convention and prevents a repeated-save loop when BloodStorm
immediately writes its battery-backed work RAM after an upload. An index-2
restore holds board reset; an upload pauses both CPUs and the sound enables
while leaving the raster alive so Direct Video does not lose sync.

## Transfer and memory contract

The top uses `hps_io` with `WIDE=1`, so the byte at the lower file address is in
`ioctl_dout[7:0]` and the next byte is in `[15:8]`. ITech32 is big-endian: native
byte `+0` occupies dword lane 3. The host adapter performs that lane conversion
at the RAM boundary and the ROM-free `nvram-memory` test covers both halves of a
dword in every board profile.

HPS transfers temporarily own each RAM's existing synchronous port. They do not
add a second writer or a third inferred port. Upload freezes both CPUs, but the
TG68 bus adapter can still present a cycle it captured just before the freeze.
The main bus therefore:

- stops accepting new CPU accesses while a transfer is active (a waiting cycle
  completes normally after the upload);
- finishes every access it accepted before the transfer, using the CPU's own
  address, and only then hands the RAM read ports to the host
  (`nvram_host_ready`);
- routes host *writes* (restore) by the write strobe alone, so a CPU write can
  never land at the host's address.

`ioctl_wait` stays asserted until `nvram_host_ready`, then for four carrier
clocks after that grant and after every address change, so `hps_io` always
samples a registered word from the requested address. Before this handshake an
access in flight at the start of an upload could read, or for SFTM write, the
host's address instead of its own.

The dirty flag survives a warm board reset. It clears when a new MRA selector is
written, a saved image is restored, or an upload begins. The production design
does not seed proprietary settings or suppress the games' battery checks. A new
installation may therefore show the battery warning while the game establishes
its bookkeeping: acknowledge it and open the OSD to create the saved image.
BloodStorm is clean on the next MRA reload. SFTM v1.10 follows the same observed
sequence as MAME 0.288: the first persisted image can warn once more while a
two-byte validity field changes, and the following reload is clean.

## Verification and follow-up

- `game-selector` checks every board profile and unsupported-selector SFTM
  fallback behavior.
- `nvram-save-request` checks one-shot OSD-edge saves and specifically rejects
  retriggering when active work RAM becomes dirty again while the OSD is open.
- `nvram-io` checks dirty transitions, download forwarding, upload ownership,
  address-change backpressure, prefetch delay, and waiting for the RAM grant.
- `nvram-upload-race` drives the real main bus with CPU reads and writes that
  overlap the start of an upload, for both work-RAM and SFTM backing stores, and
  checks both the CPU's and the host's data. It fails on the previous design.
- `nvram-memory` checks HPS-to-CPU and CPU-to-HPS round trips for SFTM,
  Time Killers, and BloodStorm, including size bounds and byte order.
- `timekeeper-bus` checks the tournament image: the timekeeper bytes at host
  offset `0x20000` in CPU byte order, restores reaching the CPU, and the
  128 KiB store kept separate.
- Production qualification confirmed that the RAMs remain inferred block RAM,
  all reported setup/hold corners pass, and save/reload works on MiSTer for
  SFTM v1.10, SFTM v1.11, BloodStorm v2.22, and Time Killers v1.32.
