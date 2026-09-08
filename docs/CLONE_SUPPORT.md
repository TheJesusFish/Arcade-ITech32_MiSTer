# Clone and revision support

The alternative MRAs in `releases/alternatives/` cover every clone of the
three supported games that uses the core's existing board mode and protection
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

The Time Killers descriptors account for both monolithic and discrete GROM
board layouts. BloodStorm revisions 2.10, 1.10, and 1.04 select the older sound
program ROM. The Japanese and Korean SFTM descriptors select their regional
main and sound program ROMs. MAME's `init_sftm110` path documents a separate
`0x7a66` protection source for SFTM v1.11 and v1.10, but that override made the
real MiSTer core hang before video. The exact same v1.10 ROM stream boots and
runs attract material with the common `0x7a6a` SFTM profile, so the release
descriptors intentionally use the hardware-qualified profile rather than that
emulator initialization assumption.

## Reproduction and integrity

Run `scripts/generate_alternative_mras.py` to recreate all 17 descriptors from
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
- Clone testing used the normal MiSTer scaler path. It does not add a separate
  Direct Video qualification claim beyond the already qualified shared RBF.
