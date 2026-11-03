# Clone and revision support

The alternative MRAs in `releases/alternatives/<_Game>/` cover every clone of
the supported games that uses the core's existing board mode and protection
behavior. The inventory was reviewed against the current
[MAME ITech32 driver](https://github.com/mamedev/mame/blob/master/src/mame/itech/itech32.cpp),
while ROM names and CRCs are pinned to
[MAME 0.288](https://github.com/mamedev/mame/blob/mame0288/src/mame/itech/itech32.cpp)
to match the release descriptors.

## Included alternatives

| Family | MAME sets | Core mode | Status |
| --- | --- | --- | --- |
| Time Killers | `timekill132i`, `timekill131`, `timekill121`, `timekill121a`, `timekill120`, `timekill100` | `01` | Supported |
| BloodStorm | `bloodstm221`, `bloodstm220`, `bloodstm216`, `bloodstm210`, `bloodstm110`, `bloodstm104` | `02` | Supported by the same board and initialization path as `bloodstm` |
| Street Fighter: The Movie | `sftmj114`, `sftmj112`, `sftmk112`, `sftm111`, `sftm110` | `00` | Supported through the common SFTM board profile and `0x7a6a` protection address |
| Hard Yardage | `hardyard11`, `hardyard10` | `03` | Same board as `hardyard`; not yet hardware-tested |
| Pairs | `pairsa` | `04` | Same board as `pairs`; not yet hardware-tested |
| Hot Memory | `hotmemry11` | `04` | Same board as `hotmemry`; not yet hardware-tested |
| World Class Bowling | `wcbowl165`, `wcbowl161`, `wcbowl16` | `07` | Same 68EC020 board as `wcbowl` (v1.66); not yet hardware-tested |
| World Class Bowling | `wcbowl15`, `wcbowl14`, `wcbowl13`, `wcbowl12`, `wcbowl11`, `wcbowl10` | `05` | 68000 board (MAME `bloodstm` machine); not yet hardware-tested |
| World Class Bowling | `wcbowl13j` | `06` | 68000 board with the second trackball port; not yet hardware-tested |
| Shuffleshot | `shufshot139`, `shufshot138`, `shufshot137`, `shufshot135` | `09` | Same board as `shufshot`; not yet hardware-tested |
| Golden Tee 3D Golf | `gt3dl192`, `gt3dl191`, `gt3dl19` | `0f` | Three-tier long ROM board (MAME `init_gt3dl`); not yet hardware-tested |
| Golden Tee 3D Golf | `gt3ds192`, `gt3dv18`, `gt3dv17`, `gt3dv16`, `gt3dv15`, `gt3dv14` | `0e` | Three-tier short ROM board, one 8-bit trackball (MAME `init_gt3d`); not yet hardware-tested |
| Golden Tee '97 | `gt97v122`, `gt97v121`, `gt97v120` | `0a` | Same single board as `gt97`; not yet hardware-tested |
| Golden Tee '98 | `gt98v100`, `gt98c100` | `0a` | Same single board as `gt98`; not yet hardware-tested |
| Golden Tee 2K | `gt2kp100` | `0b` | Single board with MAME's alternate protection result; not yet hardware-tested |
| Golden Tee Classic | `gtclasscp` | `0c` | Single board with MAME's alternate protection result; not yet hardware-tested |
| Golden Tee '97, '98, '99, 2K, Classic | `gt97s121`, `gt98s100`, `gt99s100`, `gt2ks100`, `gtclasscs` | `0d` | One-trackball "S" board (MAME `init_s_ver`); not yet hardware-tested |
| Golden Tee 3D Golf, '97, '98, '99, 2K Tournament | `gt3dt231`, `gt3dt230`, `gt3dt211`, `gt97t243`, `gt97t240`, `gt98t303`, `gt98t302`, `gtdiamond`, `gt99t400`, `gtroyal`, `gt2kt500`, `gtsupreme` | `11` | Single board plus the M48T02 timekeeper (MAME `init_aamat`); `gt97t243` hardware-tested |
| World Class Bowling Tournament | `wcbowl140`, `wcbowl130` | `12` | Deluxe board plus the M48T02 timekeeper (MAME `init_wcbowlt`); `wcbowl140` hardware-tested |

The Time Killers descriptors account for both monolithic and discrete GROM
board layouts. BloodStorm revisions 2.10, 1.10, and 1.04 select the older sound
program ROM. The Japanese and Korean SFTM descriptors select their regional
main and sound program ROMs. MAME's `init_sftm110` path documents a separate
`0x7a66` protection source for SFTM v1.11 and v1.10, but that override made the
real MiSTer core hang before video. The exact same v1.10 ROM stream boots and
runs attract material with the common `0x7a6a` SFTM profile, so the release
descriptors intentionally use the hardware-qualified profile rather than that
emulator initialization assumption.

Hard Yardage v1.00 selects its older sound program ROM. Hot Memory v1.1 has
half-size program EPROMs; MAME fills the unused half of its program region with
`0xff`, and the descriptor does the same. MAME makes Hot Memory a clone of
Pairs, so its descriptors search `pairs.zip` after their own archive. Pairs
Redemption has no clones. World Class Bowling v1.1 and v1.0 select the older
sound program and 2M sample ROM; v1.3J selects its own board profile (`06`) for
the second trackball port and its Controls switch. MAME's parent `wcbowl`
(v1.66) is the release descriptor; the 68000 v1.5 descriptor in
`_World Class Bowling` is hand-written and serves as the template for the other
68000 versions. World Class Bowling v1.61 and v1.6 select older sound programs
and the original sample ROMs (a half-size `srom3`). Shuffleshot v1.37 and v1.35
select the earlier GROM3 set. The earlier 68EC020 revisions (bowling v1.65-1.6,
Shuffleshot v1.38-1.37) carry MAME's Flip Screen and Freeze Screen switches in
place of Cabinet. World Class Bowling Deluxe, Power Up Baseball and Must Shoot
TV have no clones. The World Class Bowling tournament editions use the Deluxe board's
protection address, GROM data and samples; their descriptors are built from the
Deluxe release with the tournament programs, MAME's file names for the shared
GROMs, and (v1.30) the earlier Flip/Freeze switches.

The Golden Tee descriptors, releases included, are generated from one table
emitted from MAME 0.288's ROM listing; the generator checks that the six
release files still match it. Each set takes MAME's input-port group for its
switches, so the DIP lists differ between versions as they do in MAME (for
example, GT '97 v1.30 is the first with a Cabinet switch). The three-tier
Golden Tee 3D boards fill three ES5506 sample banks; the third uses slot C,
the last 4 MiB of the GROM window, which Golden Tee's 6 MiB GROM leaves free.
The tournament editions are the single board with MAME's M48T02 timekeeper
(`init_aamat`) and 4 MiB programs. GT 3D v2.11 packs its 6 MiB GROM as one
4 MiB and one 2 MiB group; GT Diamond and GT Supreme carry their own third
GROM group. Tournament descriptors save 133120 bytes of NVRAM: the 128 KiB
store, then the timekeeper's 2 KiB (`docs/NVRAM.md`).

## Reproduction and integrity

Run `scripts/generate_alternative_mras.py` to recreate all 69 generated descriptors from
the reviewed parent MRAs. Every index-0 ROM stream is exactly `0x2e00000` bytes
and carries a pinned MD5. `scripts/verify_mra_roms.py` independently reproduces
Main_MiSTer's checksum order, including merged archives, offsets, lengths,
repeats, and pre-interleave source-byte hashing:

```sh
python scripts/verify_mra_roms.py --rom-dir <mame-zip-directory> <one-or-more-mra-files>
```

The verifier reads ROM archives but never writes or extracts them. No ROM data,
ROM-derived fixture, checksum result, or capture is stored in this repository.

## Validation boundary

- MAME 0.288 accepted every parent and clone archive used by these descriptors.
- All 17 final ROM-stream MD5 values were reproduced from the merged archives.
- On MiSTer USB-1, all six Time Killers alternatives loaded under their own set
  identity and reached executing reset or attract material. All three supported
  regional SFTM alternatives reached the expected battery-backup warning under
  their own identity.
- SFTM v1.11 and v1.10 reached coherent attract gameplay on MiSTer with selector
  `00`; both also completed the expected battery initialization sequence and
  subsequently reloaded without the warning. The rejected selector-`03`
  experiment remained black even with a MAME-created NVRAM image.
- BloodStorm v2.22 reached coherent gameplay, saved its 64 KiB image, and
  reported `SYSTEM STATUS OK` after reload on the final production RBF. The six
  BloodStorm alternatives remain source/checksum-qualified; they were not each
  replayed through a full gameplay and NVRAM test on that exact RBF.
- The Hard Yardage, Pairs-family, World Class Bowling, World Class Bowling
  Deluxe, Shuffleshot, Golden Tee, Power Up Baseball, and Must Shoot TV
  descriptors (fifteen parents, fifty-three alternatives) reproduce their
  pinned MD5s from merged
  archives. Each assembled stream was also compared byte-for-byte with the
  regions that MAME 0.288's `ROM_START` definitions load, at the core's DDR
  offsets; the BloodStorm parent passed the same comparison as a control.
  Apart from the Golden Tee, Power Up Baseball, tournament, and Must Shoot TV
  runs recorded in `docs/STATUS.md`, they have not yet been run on MiSTer.
- Clone testing used the normal MiSTer scaler path. It does not add a separate
  Direct Video qualification claim beyond the already qualified shared RBF.
