#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate supported ITech32 clone MRAs from the reviewed parent descriptors.

ROM names, CRCs, set names, and titles are pinned to MAME 0.288's
src/mame/itech/itech32.cpp.  The script never opens or writes ROM archives.
"""

from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
RELEASES = ROOT / "releases"
OUTPUT = RELEASES / "alternatives"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {text.count(old)}")
    return text.replace(old, new, 1)


def write_alternative(group: str, filename: str, text: str) -> Path:
    # Main_MiSTer lists each game's alternatives from an _<Game> folder.
    path = OUTPUT / f"_{group}" / filename
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    return path


def replace_regex_once(text: str, pattern: str, replacement: str, label: str) -> str:
    result, count = re.subn(pattern, replacement, text, count=1, flags=re.DOTALL)
    if count != 1:
        raise RuntimeError(f"{label}: expected one regular-expression anchor, found {count}")
    return result


TIMEKILL_PROGRAM = (
    '            <part name="tk00_v1.32_u54.u54" crc="68c74b81" map="01"/>\n'
    '            <part name="tk01_v1.32_u53.u53" crc="2158d8ef" map="10"/>'
)
TIMEKILL_SOUND = (
    '        <part name="tk_snd_v_4.1_u17.u17" crc="c699af7b" offset="0x18000" length="0x08000"/>\n'
    '        <part name="tk_snd_v_4.1_u17.u17" crc="c699af7b" offset="0x00000" length="0x18000"/>'
)

TIMEKILL_DISCRETE_GROM = """        <!-- 0x0500000: alternate P/N 1049 Rev 1 discrete GROM packing. -->
        <interleave output="32">
            <part name="timekill_grom00.grom00" crc="980aab02" map="0001"/>
            <part name="timekill_grom05.grom05" crc="0b28ae65" map="0010"/>
            <part name="timekill_grom10.grom10" crc="6092c59e" map="0100"/>
            <part name="timekill_grom15.grom15" crc="b08497c1" map="1000"/>
        </interleave>
        <interleave output="32">
            <part name="timekill_grom01.grom01" crc="c37d9486" map="0001"/>
            <part name="timekill_grom06.grom06" crc="f698fc14" map="0010"/>
            <part name="timekill_grom11.grom11" crc="69735cd0" map="0100"/>
            <part name="timekill_grom16.grom16" crc="1fe7cd97" map="1000"/>
        </interleave>
        <interleave output="32">
            <part name="timekill_grom02.grom02" crc="a7b9240c" map="0001"/>
            <part name="timekill_grom07.grom07" crc="fb9c04d2" map="0010"/>
            <part name="timekill_grom12.grom12" crc="383adf84" map="0100"/>
            <part name="timekill_grom17.grom17" crc="77dcbf80" map="1000"/>
        </interleave>
        <interleave output="32">
            <part name="timekill_grom03.grom03" crc="7a464aa0" map="0001"/>
            <part name="timekill_grom08.grom08" crc="7d6f7ba9" map="0010"/>
            <part name="timekill_grom13.grom13" crc="ecde039d" map="0100"/>
            <part name="timekill_grom18.grom18" crc="05cb6d82" map="1000"/>
        </interleave>
        <interleave output="32">
            <part name="timekill_grom04.grom04" crc="b030c3d9" map="0001"/>
            <part name="timekill_grom09.grom09" crc="e98492a4" map="0010"/>
            <part name="timekill_grom14.grom14" crc="6088fa64" map="0100"/>
            <part name="timekill_grom19.grom19" crc="95be2318" map="1000"/>
        </interleave>
        <part repeat="0x1880000">00</part>"""

TIMEKILL_SPECS = (
    ("timekill132i", "Time Killers (v1.32I)",
     ("tk00_v1.32i_u54.u54", "6cef5e8c", "tk01_v1.32i_u53.u53", "3360f6a3"),
     ("tk_snd_v_4.1_u17.u17", "c699af7b"), False),
    ("timekill131", "Time Killers (v1.31)",
     ("tk00_v1.31_u54.u54", "e09ae32b", "tk01_v1.31_u53.u53", "c29137ec"),
     ("timekillsnd_u17.u17", "ab1684c3"), False),
    ("timekill121", "Time Killers (v1.21)",
     ("tk00_v1.21_u54.u54", "4938a940", "tk01_v1.21_u53.u53", "0bb75c40"),
     ("timekillsnd_u17.u17", "ab1684c3"), False),
    ("timekill121a", "Time Killers (v1.21, alternate ROM board)",
     ("tk00_v1.21_u54.u54", "4938a940", "tk01_v1.21_u53.u53", "0bb75c40"),
     ("timekillsnd_u17.u17", "ab1684c3"), True),
    ("timekill120", "Time Killers (v1.20, alternate ROM board)",
     ("tk00_v1.2_u54.u54", "df1ce59d", "tk01_v1.2_u53.u53", "d42b9849"),
     ("timekillsnd_u17.u17", "ab1684c3"), False),
    ("timekill100", "Time Killers (v1.00)",
     ("tk00.bim_u54.u54", "2b379f30", "tk01.bim_u53.u53", "e43e029c"),
     ("timekillsnd_u17.u17", "ab1684c3"), True),
)

TIMEKILL_MD5 = {
    "timekill132i": "a4df6d99d2a5fc76bd6792367681f60a",
    "timekill131": "780d01689a2a0aeb5f7326adc1fbda25",
    "timekill121": "5219df8d59be3de79f5498c022790348",
    "timekill121a": "5d77dfdd39983d47a678974e856f856a",
    "timekill120": "e0c3919f03b91952d27974593c311573",
    "timekill100": "0d0aa74c0df536db4954c128cf9c4a28",
}


def generate_timekill() -> list[Path]:
    template = (RELEASES / "Time Killers (v1.32).mra").read_text(encoding="utf-8")
    written = []
    for setname, title, program, sound, discrete_grom in TIMEKILL_SPECS:
        text = replace_once(template, "<name>Time Killers (v1.32)</name>",
                            f"<name>{title}</name>", setname)
        text = replace_once(text, "<setname>timekill</setname>",
                            f"<setname>{setname}</setname>", setname)
        text = replace_once(
            text,
            '<rom index="0" zip="timekill.zip" md5="bae098be834a3c77631e204b332a9fda" address="0x30000000">',
            f'<rom index="0" zip="{setname}.zip|timekill.zip" md5="{TIMEKILL_MD5[setname]}" address="0x30000000">',
            setname,
        )
        p0, c0, p1, c1 = program
        program_text = (
            f'            <part name="{p0}" crc="{c0}" map="01"/>\n'
            f'            <part name="{p1}" crc="{c1}" map="10"/>'
        )
        text = replace_once(text, TIMEKILL_PROGRAM, program_text, setname)
        sound_name, sound_crc = sound
        sound_text = (
            f'        <part name="{sound_name}" crc="{sound_crc}" offset="0x18000" length="0x08000"/>\n'
            f'        <part name="{sound_name}" crc="{sound_crc}" offset="0x00000" length="0x18000"/>'
        )
        text = replace_once(text, TIMEKILL_SOUND, sound_text, setname)
        if discrete_grom:
            text = replace_regex_once(
                text,
                r"        <!-- 0x0500000: eight-megabyte GROM0 plus 512 KiB small tail\. -->.*?"
                r"        <part repeat=\"0x1880000\">00</part>",
                TIMEKILL_DISCRETE_GROM,
                setname,
            )
        written.append(write_alternative("Time Killers", f"{title}.mra", text))
    return written


BLOOD_PROGRAM = (
    '            <part name="bld00_v2.22_u83.u83" crc="95f36db6" map="01" />\n'
    '            <part name="bld01_v2.22_u88.u88" crc="fcc04b93" map="10" />'
)
BLOOD_SOUND = (
    '        <part name="bldsnd_v2.01_u17.u17" crc="5aa452ee" offset="0x18000" length="0x8000" />\n'
    '        <part name="bldsnd_v2.01_u17.u17" crc="5aa452ee" offset="0x0" length="0x18000" />'
)

BLOOD_SPECS = (
    ("bloodstm221", "BloodStorm (v2.21)",
     ("bld00_v2.21_u83.u83", "01907aec", "bld01_v2.21_u88.u88", "eeae123e"), False),
    ("bloodstm220", "BloodStorm (v2.20)",
     ("bld00_v2.2_u83.u83", "904e9208", "bld01_v2.2_u88.u88", "78336a7b"), False),
    ("bloodstm216", "BloodStorm (v2.16)",
     ("bld00_v2.1_u83.u83", "9b078fd9", "bld01_v2.1_u88.u88", "50b83434"), False),
    ("bloodstm210", "BloodStorm (v2.10)",
     ("bld00_v2.1_u83.u83", "71215c8e", "bld01_v2.1_u88.u88", "da403da6"), True),
    ("bloodstm110", "BloodStorm (v1.10)",
     ("bld00_v1.1_u83.u83", "4fff8f9b", "bld01_v1.1_u88.u88", "59ce23ea"), True),
    ("bloodstm104", "BloodStorm (v1.04)",
     ("bld00_v1.0_u83.u83", "a0982119", "bld01_v1.0_u88.u88", "65800339"), True),
)

BLOOD_MD5 = {
    "bloodstm221": "f5af97d53637c6bdaa0903f974964cf6",
    "bloodstm220": "23f35d81349cee0cde194a6e05508614",
    "bloodstm216": "459c5f367975fb1fc4be2e9bb69feb3c",
    "bloodstm210": "663fc89a8b4a72fb6cc2ef903a58252c",
    "bloodstm110": "cac88bc0b8feb82686660dc4147f2261",
    "bloodstm104": "c223a6a2e8c5cb398efe5c5b9162326b",
}


def generate_bloodstorm() -> list[Path]:
    template = (RELEASES / "BloodStorm (v2.22).mra").read_text(encoding="utf-8")
    written = []
    for setname, title, program, old_sound in BLOOD_SPECS:
        text = replace_once(template, "<name>BloodStorm (v2.22)</name>",
                            f"<name>{title}</name>", setname)
        text = replace_once(text, "<setname>bloodstm</setname>",
                            f"<setname>{setname}</setname>", setname)
        text = replace_once(
            text,
            '<rom index="0" zip="bloodstm.zip" address="0x30000000" md5="c53148fcff478374936ea6b61823c8b1">',
            f'<rom index="0" zip="{setname}.zip|bloodstm.zip" address="0x30000000" md5="{BLOOD_MD5[setname]}">',
            setname,
        )
        p0, c0, p1, c1 = program
        program_text = (
            f'            <part name="{p0}" crc="{c0}" map="01" />\n'
            f'            <part name="{p1}" crc="{c1}" map="10" />'
        )
        text = replace_once(text, BLOOD_PROGRAM, program_text, setname)
        if old_sound:
            sound_text = (
                '        <part name="bldsnd_v1.0_u17.u17" crc="dddeedbb" offset="0x18000" length="0x8000" />\n'
                '        <part name="bldsnd_v1.0_u17.u17" crc="dddeedbb" offset="0x0" length="0x18000" />'
            )
            text = replace_once(text, BLOOD_SOUND, sound_text, setname)
        written.append(write_alternative("BloodStorm", f"{title}.mra", text))
    return written


SFTM_PROGRAM = (
    '            <part name="sfm_prom0_v1.12.prom0" crc="9d09355c" map="0001"/>\n'
    '            <part name="sfm_prom1_v1.12.prom1" crc="a58ac6a9" map="0010"/>\n'
    '            <part name="sfm_prom2_v1.12.prom2" crc="2f21a4f6" map="0100"/>\n'
    '            <part name="sfm_prom3_v1.12.prom3" crc="d26648d9" map="1000"/>'
)
SFTM_SOUND = (
    '        <part name="sfm_snd_v1.u23" crc="10d85366" offset="0x38000" length="0x08000"/>\n'
    '        <part name="sfm_snd_v1.u23" crc="10d85366" offset="0x00000" length="0x38000"/>'
)

SFTM_SPECS = (
    ("sftmj114", "Street Fighter: The Movie (v1.14N, Japan)", "Japan",
     (("sfmn_prom0_v1.14.prom0", "2a0c0bb7"), ("sfmn_prom1_v1.14.prom1", "088aa12c"),
      ("sfmn_prom2_v1.14.prom2", "7120836e"), ("sfmn_prom3_v1.14.prom3", "84eb200d")),
     "00", True),
    ("sftmj112", "Street Fighter: The Movie (v1.12N, Japan)", "Japan",
     (("sfmn_prom0_v1.12.prom0", "640a04a8"), ("sfmn_prom1_v1.12.prom1", "2a27b690"),
      ("sfmn_prom2_v1.12.prom2", "cec1dd7b"), ("sfmn_prom3_v1.12.prom3", "48fa60f4")),
     "00", True),
    ("sftmk112", "Street Fighter: The Movie (v1.12K, Korea)", "Korea",
     (("sfmk_prom0_v1.12.prom0", "1864ca77"), ("sfmk_prom1_v1.12.prom1", "a93c52aa"),
      ("sfmk_prom2_v1.12.prom2", "8ddf8a7d"), ("sfmk_prom3_v1.12.prom3", "9a83e6fe")),
     "00", True),
    ("sftm111", "Street Fighter: The Movie (v1.11)", "World",
     (("sfm_prom0_v1.11.prom0", "28187ddc"), ("sfm_prom1_v1.11.prom1", "ec2ce6fa"),
      ("sfm_prom2_v1.11.prom2", "be20510e"), ("sfm_prom3_v1.11.prom3", "eead342f")),
     "00", False),
    ("sftm110", "Street Fighter: The Movie (v1.10)", "World",
     (("sfm_prom0_v1.1.prom0", "00c0c63c"), ("sfm_prom1_v1.1.prom1", "d4d2a67e"),
      ("sfm_prom2_v1.1.prom2", "d7b36c92"), ("sfm_prom3_v1.1.prom3", "be3efdbd")),
     "00", False),
)

SFTM_MD5 = {
    "sftmj114": "a7b6e68a1e0fb2e873ec823f46abf4a9",
    "sftmj112": "e13c76cebf091f9e00ca4735c7b3d2dd",
    "sftmk112": "061d91cf6daafaace453e3079aade004",
    "sftm111": "a1738ecbb9f450c183f2a9a3673e9723",
    "sftm110": "e2d6f7b97a015806d50d25434675ce90",
}


def generate_sftm() -> list[Path]:
    template = (RELEASES / "Street Fighter - The Movie (v1.12).mra").read_text(encoding="utf-8")
    written = []
    for setname, title, region, program, selector, alternate_sound in SFTM_SPECS:
        text = replace_once(template, "<name>Street Fighter: The Movie (v1.12)</name>",
                            f"<name>{title}</name>", setname)
        text = replace_once(text, "<setname>sftm</setname>",
                            f"<setname>{setname}</setname>", setname)
        text = replace_once(text, "<region>World</region>",
                            f"<region>{region}</region>", setname)
        text = replace_once(
            text,
            '<rom index="0" zip="sftm.zip" md5="1c66d4ec9a0eaf2a6ce5c2607e354eaa" address="0x30000000">',
            f'<rom index="0" zip="{setname}.zip|sftm.zip" md5="{SFTM_MD5[setname]}" address="0x30000000">',
            setname,
        )
        text = replace_once(text, "        <part>00</part>",
                            f"        <part>{selector}</part>", setname)
        maps = ("0001", "0010", "0100", "1000")
        program_text = "\n".join(
            f'            <part name="{name}" crc="{crc}" map="{mapping}"/>'
            for (name, crc), mapping in zip(program, maps)
        )
        text = replace_once(text, SFTM_PROGRAM, program_text, setname)
        if alternate_sound:
            sound_text = (
                '        <part name="sfm_snd_v1.11.u23" crc="004854ed" offset="0x38000" length="0x08000"/>\n'
                '        <part name="sfm_snd_v1.11.u23" crc="004854ed" offset="0x00000" length="0x38000"/>'
            )
            text = replace_once(text, SFTM_SOUND, sound_text, setname)
        # Keep the XML title verbatim; Windows filenames cannot contain ':'.
        written.append(write_alternative("Street Fighter - The Movie",
                                         f"{title.replace(':', ' -')}.mra", text))
    return written


# The bloodstm-board parents below share one descriptor layout, written by hand
# from MAME's ROM_START blocks.
def bloodstm_program(program: tuple[str, str, str, str]) -> str:
    p0, c0, p1, c1 = program
    return (
        f'            <part name="{p0}" crc="{c0}" map="01" />\n'
        f'            <part name="{p1}" crc="{c1}" map="10" />'
    )


def bloodstm_sound(name: str, crc: str) -> str:
    return (
        f'        <part name="{name}" crc="{crc}" offset="0x18000" length="0x8000" />\n'
        f'        <part name="{name}" crc="{crc}" offset="0x0" length="0x18000" />'
    )


def retitle(template: str, parent: tuple[str, str, str, str], setname: str, title: str,
            mame_parent: str, md5: str) -> str:
    parent_title, parent_set, parent_zip, parent_md5 = parent
    text = replace_once(template, f"<name>{parent_title}</name>", f"<name>{title}</name>", setname)
    text = replace_once(text, f"<setname>{parent_set}</setname>",
                        f"<setname>{setname}</setname>", setname)
    return replace_once(
        text,
        f'zip="{parent_zip}" address="0x30000000" md5="{parent_md5}"',
        f'zip="{setname}.zip|{mame_parent}.zip" address="0x30000000" md5="{md5}"',
        setname,
    )


HARDYARD_PARENT = ("Hard Yardage (v1.20)", "hardyard", "hardyard.zip",
                   "c248f9036f672fa6ee9426c2e0994cbe")
HARDYARD_PROGRAM = ("fb00_v1.20_u83.u83", "c7497692", "fb01_v1.20_u88.u88", "3320c79a")
HARDYARD_SPECS = (
    ("hardyard11", "Hard Yardage (v1.10)",
     ("fb00_v1.10_u83.u83", "603f8a03", "fb01_v1.10_u88.u88", "7b11db88"), None,
     "f035c59257e8eee290cdb0f898d25c7c"),
    ("hardyard10", "Hard Yardage (v1.00)",
     ("fb00_v1.0_u83.u83", "f839393c", "fb01_v1.0_u88.u88", "ca444702"),
     ("fb_snd_v1.0_u17.u17", "6c6db5b8"), "f3a1140586e82bff53ae700322bf32b3"),
)


def generate_hardyard() -> list[Path]:
    template = (RELEASES / f"{HARDYARD_PARENT[0]}.mra").read_text(encoding="utf-8")
    written = []
    for setname, title, program, sound, md5 in HARDYARD_SPECS:
        text = retitle(template, HARDYARD_PARENT, setname, title, "hardyard", md5)
        text = replace_once(text, bloodstm_program(HARDYARD_PROGRAM), bloodstm_program(program),
                            setname)
        if sound:
            text = replace_once(text, bloodstm_sound("fb_snd_v1.1_u17.u17", "d221b121"),
                                bloodstm_sound(*sound), setname)
        written.append(write_alternative("Hard Yardage", f"{title}.mra", text))
    return written


PAIRS_PARENT = ("Pairs (V1.2)", "pairs", "pairs.zip", "59fb3161b0528949f173b9d2df34dd67")


def generate_pairs() -> list[Path]:
    template = (RELEASES / f"{PAIRS_PARENT[0]}.mra").read_text(encoding="utf-8")
    setname, title = "pairsa", "Pairs (V1)"
    text = retitle(template, PAIRS_PARENT, setname, title, "pairs", "eac2068665983e8e3aad9463fa5a6e7f")
    text = replace_once(
        text,
        bloodstm_program(("pair0_u83_x_v1.2.u83", "a9c761d8", "pair1_u88_x_v1.2.u88", "5141eb86")),
        bloodstm_program(("pair0_u83_x_v1.u83", "774995a3", "pair1_u83_x_v1.u88", "85d0b73a")),
        setname,
    )
    text = replace_once(text, '<part name="srom0.bin" crc="19a857f9" map="01" />',
                        '<part name="srom0_pairs_v1.srom0" crc="1d96c581" map="01" />', setname)
    return [write_alternative("Pairs", f"{title}.mra", text)]


HOTMEMRY_PARENT = ("Hot Memory (V1.2, Germany)", "hotmemry", "hotmemry.zip|pairs.zip",
                   "81d9cadb739215b759976b25c4d496ad")


def generate_hotmemry() -> list[Path]:
    template = (RELEASES / f"{HOTMEMRY_PARENT[0]}.mra").read_text(encoding="utf-8")
    setname, title = "hotmemry11", "Hot Memory (V1.1, Germany)"
    text = retitle(template, HOTMEMRY_PARENT, setname, title, "pairs", "6629b7da49ad8caf60cd6b7aa49c76ba")
    # v1.1 has half-size program EPROMs; MAME erases the region to 0xff.
    text = replace_once(
        text,
        "        <!-- 0x0000000: 68000 program, 512 KiB of the 512 KiB region. -->\n"
        + "        <interleave output=\"16\">\n"
        + bloodstm_program(("hotmem0_u83_v1.2.u83", "5b9d87a2", "hotmem1_u88_v1.2.u88", "aeea087c"))
        + "\n        </interleave>\n",
        "        <!-- 0x0000000: 68000 program, 256 KiB; MAME erases the rest to 0xff. -->\n"
        + "        <interleave output=\"16\">\n"
        + bloodstm_program(("hotmem0_u83_v1.1.u83", "8d614b1b", "hotmem1_u88_v1.1.u88", "009639fb"))
        + "\n        </interleave>\n"
        + '        <part repeat="0x40000">FF</part>\n',
        setname,
    )
    return [write_alternative("Hot Memory", f"{title}.mra", text)]


WCBOWL_PARENT = ("World Class Bowling (v1.5)", "wcbowl15", "wcbowl15.zip|wcbowl.zip",
                 "acf9c6a80036659f7a426a6cf270054d")
WCBOWL_PROGRAM = ("wcb_v1.5_u83.u83", "3ca9ab85", "wcb_v1.5_u88.u88", "d43e6fad")
# setname, title, program, early sound board (v1.0 sound code and 2M samples),
# Japan (selector 06: second trackball and its controls switch), MD5.
WCBOWL_SPECS = (
    ("wcbowl14", "World Class Bowling (v1.4)",
     ("wcb_v1.4_u83.u83", "7086131f", "wcb_v1.4_u88.u88", "0225aac1"), False, False, "97463b038e13a4df62ad8b38eca7cc23"),
    ("wcbowl13", "World Class Bowling (v1.3)",
     ("wcb_v1.3_u83.u83", "2b6d284e", "wcb_v1.3_u88.u88", "039af877"), False, False, "99ef0195dd3e7208c67c74da48d07791"),
    ("wcbowl13j", "World Class Bowling (v1.3J, Japan)",
     ("wcb_v1.3j_u83.u83", "5805fd92", "wcb_v1.3j_u88.u88", "b846660e"), False, True, "1b4c0e28070db812927e613232dba9b2"),
    ("wcbowl12", "World Class Bowling (v1.2)",
     ("wcb_v1.2_u83.u83", "0602c5ce", "wcb_v1.2_u88.u88", "49573493"), False, False, "2d082c03162f3de61b7b0e3471ae5d8b"),
    ("wcbowl11", "World Class Bowling (v1.1)",
     ("wcb_v1.1_u83.u83", "d4902392", "wcb_v1.1_u88.u88", "ea81a95c"), True, False, "4750efd14e1aea21dea603958ee133ee"),
    ("wcbowl10", "World Class Bowling (v1.0)",
     ("wcb_v1.0_u83.u83", "675ad0b1", "wcb_v1.0_u88.u88", "3afbec1c"), True, False, "a6b7595c2a729fe5d97fb05d2f67502f"),
)


def generate_wcbowl() -> list[Path]:
    template = (RELEASES / f"{WCBOWL_PARENT[0]}.mra").read_text(encoding="utf-8")
    written = []
    for setname, title, program, early_sound, japan, md5 in WCBOWL_SPECS:
        parent_title, parent_set, parent_zip, parent_md5 = WCBOWL_PARENT
        text = replace_once(template, f"<name>{parent_title}</name>", f"<name>{title}</name>", setname)
        text = replace_once(text, f"<setname>{parent_set}</setname>",
                            f"<setname>{setname}</setname>", setname)
        text = replace_once(
            text,
            f'zip="{parent_zip}" address="0x30000000" md5="{parent_md5}"',
            f'zip="{setname}.zip|wcbowl.zip" address="0x30000000" md5="{md5}"',
            setname,
        )
        text = replace_once(text, bloodstm_program(WCBOWL_PROGRAM), bloodstm_program(program),
                            setname)
        if early_sound:
            text = replace_once(text, bloodstm_sound("wcb_snd_v2.0.u17", "c14907ba"),
                                bloodstm_sound("wcb_snd_v1.0.u17", "28f14071"), setname)
            text = replace_once(text, '<part name="ensoniq_2mx16u.rom0" crc="0814ab80" map="01" />',
                                '<part name="ensoniq_2m.rom0" crc="9fdc4825" map="01" />', setname)
        if japan:
            text = replace_once(text, "<manufacturer>Incredible Technologies</manufacturer>",
                                "<manufacturer>Incredible Technologies (Excellent System Ltd. license)"
                                "</manufacturer>", setname)
            text = replace_once(text, "<region>World</region>", "<region>Japan</region>", setname)
            text = replace_once(
                text,
                '        <dip name="Service Mode" bits="3" ids="Off,On" />',
                '        <dip name="Controls" bits="2" ids="One Trackball,Two Trackballs" />\n'
                '        <dip name="Service Mode" bits="3" ids="Off,On" />',
                setname,
            )
            text = replace_once(
                text,
                "players take turns on one trackball.-->",
                "with Two Trackballs, player 2 uses the second controller's stick or d-pad."
                " MAME notes this set reads the ball at a 45-degree offset.-->",
                setname,
            )
            text = replace_once(text, "<!--Board selector 05 must", "<!--Board selector 06 must",
                                setname)
            text = replace_once(text, "        <part>05</part>", "        <part>06</part>", setname)
        written.append(write_alternative("World Class Bowling", f"{title}.mra", text))
    return written


def main() -> int:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    written = (generate_timekill() + generate_bloodstorm() + generate_sftm() +
               generate_hardyard() + generate_pairs() + generate_hotmemry() +
               generate_wcbowl())
    expected = {path.resolve() for path in written}
    actual = {path.resolve() for path in OUTPUT.rglob("*.mra")}
    if actual != expected:
        unexpected = sorted(str(path.relative_to(ROOT)) for path in actual - expected)
        missing = sorted(str(path.relative_to(ROOT)) for path in expected - actual)
        raise RuntimeError(f"alternative MRA set mismatch: unexpected={unexpected}, missing={missing}")
    for path in written:
        print(path.relative_to(ROOT).as_posix())
    print(f"PASS: generated {len(written)} supported alternative MRAs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
