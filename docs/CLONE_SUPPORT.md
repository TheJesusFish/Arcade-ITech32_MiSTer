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
place of Cabinet. World Class Bowling Deluxe has no clones. The tournament
editions need the M48T02 timekeeper and are not yet supported.

## Reproduction and integrity

Run `scripts/generate_alternative_mras.py` to recreate all 34 generated descriptors from
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
  Deluxe, and Shuffleshot descriptors (seven parents, eighteen alternatives)
  reproduce their pinned MD5s from merged archives. Each assembled
  stream was also compared byte-for-byte with the regions that MAME 0.288's
  `ROM_START` definitions load, at the core's DDR offsets; the BloodStorm parent
  passed the same comparison as a control. They have not yet been run on MiSTer.
- Clone testing used the normal MiSTer scaler path. It does not add a separate
  Direct Video qualification claim beyond the already qualified shared RBF.
