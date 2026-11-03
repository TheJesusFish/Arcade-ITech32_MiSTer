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


# The 68000 World Class Bowling template is a hand-written alternative: MAME's
# parent (v1.66) runs on the 68EC020 board and is the release descriptor.
WCBOWL_68000_TEMPLATE = OUTPUT / "_World Class Bowling" / f"{WCBOWL_PARENT[0]}.mra"


def generate_wcbowl() -> list[Path]:
    template = WCBOWL_68000_TEMPLATE.read_text(encoding="utf-8")
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


def program32(parts: tuple[tuple[str, str], ...]) -> str:
    maps = ("0001", "0010", "0100", "1000")
    return "\n".join(
        f'            <part name="{name}" crc="{crc}" map="{mapping}" />'
        for (name, crc), mapping in zip(parts, maps)
    )


def retitle_020(template: str, parent: tuple[str, str, str, str], setname: str, title: str,
                md5: str) -> str:
    parent_title, parent_set, parent_zip, parent_md5 = parent
    text = replace_once(template, f"<name>{parent_title}</name>", f"<name>{title}</name>", setname)
    text = replace_once(text, f"<setname>{parent_set}</setname>",
                        f"<setname>{setname}</setname>", setname)
    return replace_once(
        text,
        f'zip="{parent_zip}" address="0x30000000" md5="{parent_md5}"',
        f'zip="{setname}.zip|{parent_set}.zip" address="0x30000000" md5="{md5}"',
        setname,
    )


# MAME's earlier 68EC020 revisions use Flip Screen on SW1:3 instead of Cabinet,
# and Freeze Screen on SW1:2 (wcbowlo and shufshto input ports).
CABINET_DIP = '        <dip name="Cabinet" bits="1" ids="Upright,Cocktail" />'
FLIP_DIP = '        <dip name="Flip Screen" bits="1" ids="Off,On" />'
FREEZE_DIP = '        <dip name="Freeze Screen" bits="2" ids="Off,On" />'

WCBOWL020_PARENT = ("World Class Bowling (v1.66)", "wcbowl", "wcbowl.zip",
                    "f883f69e59c49365dc07ae9a1cda809e")
WCBOWL020_PROGRAM = (("wcb_prom0_v1.66n.prom0", "f6774112"), ("wcb_prom1_v1.66n.prom1", "931821ae"),
                     ("wcb_prom2_v1.66n.prom2", "c54f5e40"), ("wcb_prom3_v1.66n.prom3", "dd72c796"))
# setname, title, program, earlier sound program (None keeps v4.01 and the
# "_s" sample ROMs), MD5.
WCBOWL020_SPECS = (
    ("wcbowl165", "World Class Bowling (v1.65)",
     (("wcb_prom0_v1.65n.prom0", "cf0f6c25"), ("wcb_prom1_v1.65n.prom1", "076ab158"),
      ("wcb_prom2_v1.65n.prom2", "47259009"), ("wcb_prom3_v1.65n.prom3", "4c6b4e4f")),
     None, "da5703a2fdd35eb0353711bfb43feda9"),
    ("wcbowl161", "World Class Bowling (v1.61)",
     (("wcb_prom0_v1.61n.prom0", "b879d4a7"), ("wcb_prom1_v1.61n.prom1", "49f3ed6a"),
      ("wcb_prom2_v1.61n.prom2", "47259009"), ("wcb_prom3_v1.61n.prom3", "e5081f85")),
     ("wcbsnd_u88_v4.0.u88", "194a51d7"), "0f3c0ca9f5fb557b7893f7fae017232f"),
    ("wcbowl16", "World Class Bowling (v1.6)",
     (("wcb_prom0_v1.6n.prom0", "332c558f"), ("wcb_prom1_v1.6n.prom1", "c5750857"),
      ("wcb_prom2_v1.6n.prom2", "28f4ee8a"), ("wcb_prom3_v1.6n.prom3", "f0a58979")),
     ("wcbsnd_u88_v3.0n.u88", "45c4f659"), "41ffd945703d2a4d00b24b36c3199af1"),
)

# v1.61 and v1.6 carry the original sample ROMs; their srom3 is half size.
WCBOWL020_SAMPLES_ORIGINAL = (
    ('<part name="wcb_srom0_s.srom0" crc="d42dd283" map="01" />',
     '<part name="wcb_srom0.srom0" crc="c3821cb5" map="01" />'),
    ('<part name="wcb_srom1_s.srom1" crc="7a69ab54" map="01" />',
     '<part name="wcb_srom1.srom1" crc="37bfa3c7" map="01" />'),
    ('<part name="wcb_srom2_s.srom2" crc="346530a2" map="01" />',
     '<part name="wcb_srom2.srom2" crc="f82c08fd" map="01" />'),
    ('            <part name="wcb_srom3_s.srom3" crc="1dfe3a31" map="01" />\n'
     '            <part map="10" repeat="0x40000">00</part>\n'
     '        </interleave>\n'
     '        <part repeat="0x180000">00</part>',
     '            <part name="wcb_srom3.srom3" crc="1c2efdee" map="01" />\n'
     '            <part map="10" repeat="0x20000">00</part>\n'
     '        </interleave>\n'
     '        <part repeat="0x1c0000">00</part>'),
)


def generate_wcbowl_020() -> list[Path]:
    template = (RELEASES / f"{WCBOWL020_PARENT[0]}.mra").read_text(encoding="utf-8")
    written = []
    for setname, title, program, sound, md5 in WCBOWL020_SPECS:
        text = retitle_020(template, WCBOWL020_PARENT, setname, title, md5)
        text = replace_once(text, program32(WCBOWL020_PROGRAM), program32(program), setname)
        text = replace_once(text, CABINET_DIP, FLIP_DIP, setname)
        if sound:
            text = replace_once(text, bloodstm_sound("wcbsnd_u88_4.01.u88", "e97a6d28"),
                                bloodstm_sound(*sound), setname)
            for old, new in WCBOWL020_SAMPLES_ORIGINAL:
                text = replace_once(text, old, new, setname)
        written.append(write_alternative("World Class Bowling", f"{title}.mra", text))
    return written


SHUFSHOT_PARENT = ("Shuffleshot (v1.40)", "shufshot", "shufshot.zip",
                   "7fb2a2cf384027ad4ac11e0f3e8dee92")
SHUFSHOT_PROGRAM = (("shot_prom0_v1.40.prom0", "33c0c98b"), ("shot_prom1_v1.40.prom1", "d30a8831"),
                    ("shot_prom2_v1.40.prom2", "ea10ada8"), ("shot_prom3_v1.40.prom3", "4b28f28b"))
SHUFSHOT_GROM3 = (("shfa_grom3_0.grm3_0", "c5afc9d1"), ("shfa_grom3_1.grm3_1", "70dd7b68"),
                  ("shfa_grom3_2.grm3_2", "da56512d"), ("shfa_grom3_3.grm3_3", "21727c50"))
SHUFSHOT_GROM3_OLD = (("shf_grom3_0.grm3_0", "a29763db"), ("shf_grom3_1.grm3_1", "c757084c"),
                      ("shf_grom3_2.grm3_2", "2971cb25"), ("shf_grom3_3.grm3_3", "4fcbee51"))
# setname, title, program, earlier GROM3, earlier DIP layout (shufshto), MD5.
SHUFSHOT_SPECS = (
    ("shufshot139", "Shuffleshot (v1.39)",
     (("shot_prom0_v1.39.prom0", "e811fc4a"), ("shot_prom1_v1.39.prom1", "f9d120c5"),
      ("shot_prom2_v1.39.prom2", "9f12414d"), ("shot_prom3_v1.39.prom3", "108a69be")),
     False, False, "1410e243a7e8ec3968e62cf45589b360"),
    ("shufshot138", "Shuffleshot (v1.38)",
     (("shot_prom0_v1.38.prom0", "68f823ff"), ("shot_prom1_v1.38.prom1", "bdd9a8e9"),
      ("shot_prom2_v1.38.prom2", "92008e13"), ("shot_prom3_v1.38.prom3", "723cb9a5")),
     False, True, "347efcebcd6089d15dcfa57fafd60939"),
    ("shufshot137", "Shuffleshot (v1.37)",
     (("shot_prom0_v1.37.prom0", "6499c76f"), ("shot_prom1_v1.37.prom1", "64fb47a4"),
      ("shot_prom2_v1.37.prom2", "e0df3025"), ("shot_prom3_v1.37.prom3", "efa66ad8")),
     True, True, "6075411ee3a5399655107be2884f16a3"),
    ("shufshot135", "Shuffleshot (v1.35)",
     (("shot_prom0_v1.35.prom0", "1a1d510c"), ("shot_prom1_v1.35.prom1", "5d7d5017"),
      ("shot_prom2_v1.35.prom2", "6f27b111"), ("shot_prom3_v1.35.prom3", "bf6fabbb")),
     True, False, "ad2a9b239d3367414b51ebd681819146"),
)


def generate_shufshot() -> list[Path]:
    template = (RELEASES / f"{SHUFSHOT_PARENT[0]}.mra").read_text(encoding="utf-8")
    written = []
    for setname, title, program, old_grom3, old_dips, md5 in SHUFSHOT_SPECS:
        text = retitle_020(template, SHUFSHOT_PARENT, setname, title, md5)
        text = replace_once(text, program32(SHUFSHOT_PROGRAM), program32(program), setname)
        if old_grom3:
            text = replace_once(text, program32(SHUFSHOT_GROM3), program32(SHUFSHOT_GROM3_OLD),
                                setname)
        if old_dips:
            text = replace_once(text, CABINET_DIP, FLIP_DIP + "\n" + FREEZE_DIP, setname)
        written.append(write_alternative("Shuffleshot", f"{title}.mra", text))
    return written


# Golden Tee (MAME sftm machine with init_gt_common). The six releases and
# their alternatives are built from one description, generated from MAME
# 0.288's ROM listing: each set names its board (the selector, trackball
# wiring and ES5506 sample banks follow the GAME() line's init and the
# ROM_START regions) and its MAME input-port group.
GT_BOARDS = {
    # board: (selector, trackballs, sample layout)
    "aama": ("0a", 2, "single"),       # init_aama: AAMA serial numbers 676266 and up
    "gt2kp": ("0b", 2, "single"),      # init_gt2kp
    "gtclasscp": ("0c", 2, "single"),  # init_gtclasscp
    "s": ("0d", 1, "bank2"),           # init_s_ver: P/N 1088 short ROM board
    "3d_short": ("0e", 1, "three"),    # init_gt3d: P/N 1069 short ROM board
    "3d_long": ("0f", 2, "three"),     # init_gt3dl: P/N 1080 long ROM board
    "aama_t": ("11", 2, "single"),     # init_aamat: the single board plus the timekeeper
}
# Boards with MAME's M48T02 timekeeper: its 2 KiB follows the 128 KiB NVRAM
# in the saved image.
GT_TIMEKEEPER_BOARDS = {"aama_t"}
NVRAM_TIMEKEEPER_BYTES = 131072 + 2048

# Labels stay short enough for the OSD line to show the setting.
GT_ORIENTATION = ("Trackball Mount", "Normal,45 Degrees")
GT_CONTROLS = ("Controls", "One Trackball,Two Trackballs")
GT_CABINET = ("Cabinet", "Upright,Cocktail")
GT_FREEZE = ("Freeze Screen", "Off,On")
# MAME input-port groups as (DIP bit, (name, settings)), bit 0 = SW1:4. MAME's
# "Unknown" switches are left out.
GT_DIPS = {
    "gt3d": ((1, GT_ORIENTATION), (2, GT_CONTROLS)),
    "gt97": ((0, GT_FREEZE), (2, GT_CABINET)),
    "gt97o": ((0, GT_FREEZE), (1, GT_ORIENTATION), (2, GT_CONTROLS)),
    "gt97s": ((0, GT_FREEZE), (1, GT_ORIENTATION)),
    "gt98": ((1, GT_CONTROLS), (2, GT_CABINET)),
    "gt98s": (),
    "aama": ((0, GT_ORIENTATION), (1, GT_CABINET), (2, GT_CONTROLS)),
    "s_ver": ((0, GT_ORIENTATION),),
}

GT3D_GROM_T = (
    ('gtg3_grom0_0.grm0_0', '1b10379d'),
    ('gtg3_grom0_1.grm0_1', '3b852e1a'),
    ('gtg3_grom0_2.grm0_2', 'd43ffb35'),
    ('gtg3_grom0_3.grm0_3', '2d24e93e'),
    ('gtg3_grom1_0.grm1_0', '4476b239'),
    ('gtg3_grom1_1.grm1_1', '0aadfad2'),
    ('gtg3_grom1_2.grm1_2', '27871980'),
    ('gtg3_grom1_3.grm1_3', '7dbc242b'),
    ('gtg3_grom2_0_t.grm2_0', '80ae7148'),
    ('gtg3_grom2_1_t.grm2_1', '0f85a618'),
    ('gtg3_grom2_2_t.grm2_2', '09ca5fbf'),
    ('gtg3_grom2_3_t.grm2_3', 'd136853a'),
)
GT3D_SAMPLES = (
    ('gtg3_srom0_nr.srom0', '44983bd7'),
    ('gtg3_srom1_nr.srom1', '1b3f18b6'),
)
GT3D_GROM = (
    ('gtg3_grom0_0.grm0_0', '1b10379d'),
    ('gtg3_grom0_1.grm0_1', '3b852e1a'),
    ('gtg3_grom0_2.grm0_2', 'd43ffb35'),
    ('gtg3_grom0_3.grm0_3', '2d24e93e'),
    ('gtg3_grom1_0.grm1_0', '4476b239'),
    ('gtg3_grom1_1.grm1_1', '0aadfad2'),
    ('gtg3_grom1_2.grm1_2', '27871980'),
    ('gtg3_grom1_3.grm1_3', '7dbc242b'),
    ('gtg3_grom2_0.grm2_0', '15cb22bc'),
    ('gtg3_grom2_1.grm2_1', '52f3ad44'),
    ('gtg3_grom2_2.grm2_2', 'c7712125'),
    ('gtg3_grom2_3.grm2_3', '77869bcf'),
)
GT3D_LONG_SAMPLES = (
    ('ensoniq_2mx16u.rom0', '0814ab80'),
    ('gtg3_srom1.srom1', 'ac669434'),
    ('gtg3_srom2.srom2', '6853578e'),
    ('gtg3_srom3.srom3', 'd2462965'),
)
GT3D_SHORT_SAMPLES = (
    ('ensoniq_2m.rom0', '9fdc4825'),
    ('gtg3_srom1.srom1', 'ac669434'),
    ('gtg3_srom2.srom2', '6853578e'),
    ('gtg3_srom3.srom3', 'd2462965'),
)
GT97_GROM = (
    ('gt97_grom0_0.grm0_0', '81784aaf'),
    ('gt97_grom0_1.grm0_1', '345bda44'),
    ('gt97_grom0_2.grm0_2', 'b2beb40d'),
    ('gt97_grom0_3.grm0_3', '7cef32ff'),
    ('gt97_grom1_0.grm1_0', '1cc4c309'),
    ('gt97_grom1_1.grm1_1', '512cea45'),
    ('gt97_grom1_2.grm1_2', '0599b505'),
    ('gt97_grom1_3.grm1_3', '257eacc9'),
    ('gt97_grom2_0.grm2_0', '95b6e7ee'),
    ('gt97_grom2_1.grm2_1', 'afd558b4'),
    ('gt97_grom2_2.grm2_2', '5b7a8733'),
    ('gt97_grom2_3.grm2_3', '72e8ae60'),
)
GT97_SAMPLES = (
    ('gt97_srom0_nr.srom0', '44983bd7'),
    ('gt97_srom1_nr.srom1', '1b3f18b6'),
)
GT_S_SAMPLES = (
    ('gtg3_srom1_nr++.srom1', '44983bd7'),
    ('gtg3_srom2_nr+.srom2', '1b3f18b6'),
)
GT98_GROM = (
    ('gt98_grom0_0.grm0_0', '2d79492b'),
    ('gt98_grom0_1.grm0_1', '79afda1a'),
    ('gt98_grom0_2.grm0_2', '8c381f56'),
    ('gt98_grom0_3.grm0_3', '46c35ba6'),
    ('gt98_grom1_0.grm1_0', 'b07bc634'),
    ('gt98_grom1_1.grm1_1', 'b23d59a7'),
    ('gt98_grom1_2.grm1_2', '9c113abc'),
    ('gt98_grom1_3.grm1_3', '231bbe58'),
    ('gt98_grom2_0.grm2_0', 'db5cec87'),
    ('gt98_grom2_1.grm2_1', 'c74fc7d3'),
    ('gt98_grom2_2.grm2_2', '1227609d'),
    ('gt98_grom2_3.grm2_3', '78745131'),
)
GT98_SAMPLES = (
    ('gt98_srom0_nr.srom0', '44983bd7'),
    ('gt98_srom1_nr.srom1', '1b3f18b6'),
)
GT99_GROM = (
    ('gt99_grom0_0.grm0_0', 'c22b50f9'),
    ('gt99_grom0_1.grm0_1', 'd6d6be57'),
    ('gt99_grom0_2.grm0_2', '005d4791'),
    ('gt99_grom0_3.grm0_3', '0c998eb7'),
    ('gt99_grom1_0.grm1_0', '8b79d6e2'),
    ('gt99_grom1_1.grm1_1', '84ef1803'),
    ('gt99_grom1_2.grm1_2', 'd73d8afc'),
    ('gt99_grom1_3.grm1_3', '59f48688'),
    ('gt99_grom2_0.grm2_0', '693d9d68'),
    ('gt99_grom2_1.grm2_1', '2c0b8b8c'),
    ('gt99_grom2_2.grm2_2', 'ba1b5961'),
    ('gt99_grom2_3.grm2_3', 'cfccd5c2'),
)
GT99_SAMPLES = (
    ('gt99_srom0_nr.srom0', '44983bd7'),
    ('gt99_srom1_nr.srom1', '1b3f18b6'),
)
GT2K_GROM = (
    ('gt2k_grom0_0.grm0_0', 'c22b50f9'),
    ('gt2k_grom0_1.grm0_1', 'd6d6be57'),
    ('gt2k_grom0_2.grm0_2', '005d4791'),
    ('gt2k_grom0_3.grm0_3', '0c998eb7'),
    ('gt2k_grom1_0.grm1_0', '8b79d6e2'),
    ('gt2k_grom1_1.grm1_1', '84ef1803'),
    ('gt2k_grom1_2.grm1_2', 'd73d8afc'),
    ('gt2k_grom1_3.grm1_3', '59f48688'),
    ('gt2k_grom2_0.grm2_0', 'cc11b93f'),
    ('gt2k_grom2_1.grm2_1', '1c3a0126'),
    ('gt2k_grom2_2.grm2_2', '97814df5'),
    ('gt2k_grom2_3.grm2_3', 'f0f7373f'),
)
GT2K_SAMPLES = (
    ('gt2k_srom0_nr.srom0', '44983bd7'),
    ('gt2k_srom1_nr.srom1', '1b3f18b6'),
)
GTCLASSIC_GROM = (
    ('gt_classic_grom0_0.grm0_0', 'c22b50f9'),
    ('gt_classic_grom0_1.grm0_1', 'd6d6be57'),
    ('gt_classic_grom0_2.grm0_2', '005d4791'),
    ('gt_classic_grom0_3.grm0_3', '0c998eb7'),
    ('gt_classic_grom1_0.grm1_0', '8b79d6e2'),
    ('gt_classic_grom1_1.grm1_1', '84ef1803'),
    ('gt_classic_grom1_2.grm1_2', 'd73d8afc'),
    ('gt_classic_grom1_3.grm1_3', '59f48688'),
    ('gt_classic_grom2_0.grm2_0', 'c4f54398'),
    ('gt_classic_grom2_1.grm2_1', '2c1f83cf'),
    ('gt_classic_grom2_2.grm2_2', '607657a6'),
    ('gt_classic_grom2_3.grm2_3', '7ad615c1'),
)
GTCLASSIC_SAMPLES = (
    ('gt_classic_srom0.nr', '44983bd7'),
    ('gt_classic_srom1.nr', '1b3f18b6'),
)

# setname, MAME parent, title, year, board, MAME input-port group, program,
# sound program, GROM, sample ROMs, md5.
GT_SETS = (
    ('gt3d', None, 'Golden Tee 3D Golf (v1.93N)', '1995', 'aama', 'gt3d',
     (
         ('gtg3_prom0_v1.93n.prom0', 'cacacb44'),
         ('gtg3_prom1_v1.93n.prom1', '4c172d7f'),
         ('gtg3_prom2_v1.93n.prom2', 'b53fe6f0'),
         ('gtg3_prom3_v1.93n.prom3', '78468761'),
     ), ('gtg3nr_u88_v1.0.u88', '2cee9e98'), GT3D_GROM_T, GT3D_SAMPLES, "8fedd84972a26b1ec1792579802cc3ae"),
    ('gt3dl192', 'gt3d', 'Golden Tee 3D Golf (v1.92L)', '1995', '3d_long', 'gt3d',
     (
         ('gtg3_prom0_v1.92l.prom0', 'b449b939'),
         ('gtg3_prom1_v1.92l.prom1', 'ff986e67'),
         ('gtg3_prom2_v1.92l.prom2', 'eb959447'),
         ('gtg3_prom3_v1.92l.prom3', '0265b798'),
     ), ('gtg3-snd_u23_v2.2.u23', '26fe2e92'), GT3D_GROM, GT3D_LONG_SAMPLES, "352207a32fc6aa5ec66ad2cfb152c3b3"),
    ('gt3dl191', 'gt3d', 'Golden Tee 3D Golf (v1.91L)', '1995', '3d_long', 'gt3d',
     (
         ('gtg3_prom0_v1.91l.prom0', 'a3ea30d8'),
         ('gtg3_prom1_v1.91l.prom1', '3aa87e56'),
         ('gtg3_prom2_v1.91l.prom2', '41720e87'),
         ('gtg3_prom3_v1.91l.prom3', '30946139'),
     ), ('gtg3-snd_u23_v2.1.u23', '6ae2646d'), GT3D_GROM, GT3D_LONG_SAMPLES, "954f15b53a90481fd3993cd81ad20d9a"),
    ('gt3dl19', 'gt3d', 'Golden Tee 3D Golf (v1.9L)', '1995', '3d_long', 'gt3d',
     (
         ('gtg3_prom0_v1.9l.prom0', 'b6293cf6'),
         ('gtg3_prom1_v1.9l.prom1', '270b7936'),
         ('gtg3_prom2_v1.9l.prom2', '3f892e81'),
         ('gtg3_prom3_v1.9l.prom3', 'b63ef2c0'),
     ), ('gtg3-snd_u23_v2.0.u23', '3f69a9ea'), GT3D_GROM, GT3D_LONG_SAMPLES, "83f62bccf18476ceba07c38d4fe548de"),
    ('gt3ds192', 'gt3d', 'Golden Tee 3D Golf (v1.92S)', '1995', '3d_short', 'gt3d',
     (
         ('gtg3_prom0_v1.92s.prom0', 'eee38005'),
         ('gtg3_prom1_v1.92s.prom1', '818ba70e'),
         ('gtg3_prom2_v1.92s.prom2', '7ab661a1'),
         ('gtg3_prom3_v1.92s.prom3', 'f9f96c01'),
     ), ('gtg3-snd_u23_v1.2.u23', 'cbbe41f9'), GT3D_GROM, GT3D_SHORT_SAMPLES, "cd779617150aba729f00407a7c8bd21e"),
    ('gt3dv18', 'gt3d', 'Golden Tee 3D Golf (v1.8)', '1995', '3d_short', 'gt3d',
     (
         ('gtg3_prom0_v1.8.prom0', '0fa53c40'),
         ('gtg3_prom1_v1.8.prom1', 'bef2cbe3'),
         ('gtg3_prom2_v1.8.prom2', '1d5fb128'),
         ('gtg3_prom3_v1.8.prom3', '5542c335'),
     ), ('gtg3-snd_u23_v1.1.u23', '2f4cde9f'), GT3D_GROM, GT3D_SHORT_SAMPLES, "f06f81a2630778ea6f89ca6c84c71a6b"),
    ('gt3dv17', 'gt3d', 'Golden Tee 3D Golf (v1.7)', '1995', '3d_short', 'gt3d',
     (
         ('gtg3_prom0_v1.7.prom0', '9a6fc839'),
         ('gtg3_prom1_v1.7.prom1', '26606578'),
         ('gtg3_prom2_v1.7.prom2', '9c4d348b'),
         ('gtg3_prom3_v1.7.prom3', '53b1d6e7'),
     ), ('gtg3-snd_u23_v1.1.u23', '2f4cde9f'), GT3D_GROM, GT3D_SHORT_SAMPLES, "001c338b9a5bf6dfe45f9738cb8e6e87"),
    ('gt3dv16', 'gt3d', 'Golden Tee 3D Golf (v1.6)', '1995', '3d_short', 'gt3d',
     (
         ('gtg3_prom0_v1.6.prom0', '99d9a7e7'),
         ('gtg3_prom1_v1.6.prom1', '0ec4b307'),
         ('gtg3_prom2_v1.6.prom2', '02ce6085'),
         ('gtg3_prom3_v1.6.prom3', 'e77fa8a2'),
     ), ('gtg3-snd_u23_v1.1.u23', '2f4cde9f'), GT3D_GROM, GT3D_SHORT_SAMPLES, "c680a70bf02988d088a9404ce3f6b66f"),
    ('gt3dv15', 'gt3d', 'Golden Tee 3D Golf (v1.5)', '1995', '3d_short', 'gt3d',
     (
         ('gtg3_prom0_v1.5.prom0', '51a5e811'),
         ('gtg3_prom1_v1.5.prom1', '1e8744ad'),
         ('gtg3_prom2_v1.5.prom2', 'e465c813'),
         ('gtg3_prom3_v1.5.prom3', '3b25e198'),
     ), ('gtg3-snd_u23_v1.1.u23', '2f4cde9f'), GT3D_GROM, GT3D_SHORT_SAMPLES, "66de52b0f7fcb92a1ec1f41741c665d7"),
    ('gt3dv14', 'gt3d', 'Golden Tee 3D Golf (v1.4)', '1995', '3d_short', 'gt3d',
     (
         ('gtg3_prom0_v1.4.prom0', '396934a7'),
         ('gtg3_prom1_v1.4.prom1', '5ba19b8d'),
         ('gtg3_prom2_v1.4.prom2', '23991fcf'),
         ('gtg3_prom3_v1.4.prom3', '2f7b5a26'),
     ), ('gtg3-snd_u23_v1.0.u23', '4f106cd1'), GT3D_GROM, GT3D_SHORT_SAMPLES, "903aa172cda9572ea15def0cb5b68681"),
    ('gt97', None, "Golden Tee '97 (v1.30)", '1997', 'aama', 'gt97',
     (
         ('gt97_prom0_v1.30.prom0', '7490ba4e'),
         ('gt97_prom1_v1.30.prom1', '71f9c5f3'),
         ('gt97_prom2_v1.30.prom2', '8292b51a'),
         ('gt97_prom3_v1.30.prom3', '64539f72'),
     ), ('gt97nr_u88_v1.0.u88', '2cee9e98'), GT97_GROM, GT97_SAMPLES, "23ef1ae17a0f71e1cfcf08a4e4a2cba3"),
    ('gt97v122', 'gt97', "Golden Tee '97 (v1.22)", '1997', 'aama', 'gt97o',
     (
         ('gt97_prom0_v1.22.prom0', '4a543c99'),
         ('gt97_prom1_v1.22.prom1', '27668628'),
         ('gt97_prom2_v1.22.prom2', 'd73a769f'),
         ('gt97_prom3_v1.22.prom3', '03962957'),
     ), ('gt97nr_u88_v1.0.u88', '2cee9e98'), GT97_GROM, GT97_SAMPLES, "125d8bcdfbed3038dcf2140c785075a4"),
    ('gt97v121', 'gt97', "Golden Tee '97 (v1.21)", '1997', 'aama', 'gt97o',
     (
         ('gt97_prom0_v1.21.prom0', 'a210a2c6'),
         ('gt97_prom1_v1.21.prom1', 'a60806f8'),
         ('gt97_prom2_v1.21.prom2', 'a97ce668'),
         ('gt97_prom3_v1.21.prom3', '7a6b1ad8'),
     ), ('gt97nr_u88_v1.0.u88', '2cee9e98'), GT97_GROM, GT97_SAMPLES, "427711789bf59103db98e80fb435a1c7"),
    ('gt97s121', 'gt97', "Golden Tee '97 (v1.21S)", '1997', 's', 'gt97s',
     (
         ('gt97_prom0_v1.21s.prom0', '1143f45b'),
         ('gt97_prom1_v1.21s.prom1', 'e7cfb1ea'),
         ('gt97_prom2_v1.21s.prom2', '0cc24291'),
         ('gt97_prom3_v1.21s.prom3', '922727c2'),
     ), ('gtg3_nr_u23_v2.2.u23', '04effd73'), GT97_GROM, GT_S_SAMPLES, "69dc0fb0196c7620c1f628c023eeed65"),
    ('gt97v120', 'gt97', "Golden Tee '97 (v1.20)", '1997', 'aama', 'gt97o',
     (
         ('gt97_prom0_v1.20.prom0', 'cdc4226f'),
         ('gt97_prom1_v1.20.prom1', 'b36fc43f'),
         ('gt97_prom2_v1.20.prom2', '30b0d97e'),
         ('gt97_prom3_v1.20.prom3', '77281d3a'),
     ), ('gt97nr_u88_v1.0.u88', '2cee9e98'), GT97_GROM, GT97_SAMPLES, "13edd89c835fd06943ff7513e9df4349"),
    ('gt98', None, "Golden Tee '98 (v1.10)", '1998', 'aama', 'aama',
     (
         ('gt98_prom0_v1.10.prom0', 'dd93ab2a'),
         ('gt98_prom1_v1.10.prom1', '6ea92960'),
         ('gt98_prom2_v1.10.prom2', '27a8a15f'),
         ('gt98_prom3_v1.10.prom3', 'd61f2bb2'),
     ), ('gt98nr_u88_v1.0.u88', '2cee9e98'), GT98_GROM, GT98_SAMPLES, "52b7b73997bed06f656134cd1e198068"),
    ('gt98v100', 'gt98', "Golden Tee '98 (v1.00)", '1998', 'aama', 'gt98',
     (
         ('gt98_prom0_v1.00.prom0', 'f2dc0a6c'),
         ('gt98_prom1_v1.00.prom1', 'b0ca22f3'),
         ('gt98_prom2_v1.00.prom2', 'f940acdc'),
         ('gt98_prom3_v1.00.prom3', '22d7e8dc'),
     ), ('gt98nr_u88_v1.0.u88', '2cee9e98'), GT98_GROM, GT98_SAMPLES, "9fc0d6b0120d04ee1cd773d5588ce1a5"),
    ('gt98c100', 'gt98', "Golden Tee '98 (v1.00C)", '1998', 'aama', 'gt98',
     (
         ('gt98_prom0_v1.00c.prom0', 'bb508580'),
         ('gt98_prom1_v1.00c.prom1', '0e414c17'),
         ('gt98_prom2_v1.00c.prom2', '628e84eb'),
         ('gt98_prom3_v1.00c.prom3', '870f2464'),
     ), ('gt98nr_u88_v1.0.u88', '2cee9e98'), GT98_GROM, GT98_SAMPLES, "ccb4befd4c2d6567ac31bb350f83315c"),
    ('gt98s100', 'gt98', "Golden Tee '98 (v1.00S)", '1998', 's', 'gt98s',
     (
         ('gt98_prom0_v1.00s.prom0', '962ff444'),
         ('gt98_prom1_v1.00s.prom1', 'be0ac375'),
         ('gt98_prom2_v1.00s.prom2', '304e881c'),
         ('gt98_prom3_v1.00s.prom3', 'ac04ea81'),
     ), ('gtg3_nr_u23_v2.2.u23', '04effd73'), GT98_GROM, GT_S_SAMPLES, "10a64b7cb10c23dc21d6d40829f0adb5"),
    ('gt99', None, "Golden Tee '99 (v1.00)", '1999', 'aama', 'aama',
     (
         ('gt99_prom0_v1.00.prom0', '1ca05267'),
         ('gt99_prom1_v1.00.prom1', '4fb757fa'),
         ('gt99_prom2_v1.00.prom2', '3eb2b13a'),
         ('gt99_prom3_v1.00.prom3', '03454e7d'),
     ), ('gt99nr_u88_v1.0.u88', '2cee9e98'), GT99_GROM, GT99_SAMPLES, "a3857dacd431e97131c8990199f79d9e"),
    ('gt99s100', 'gt99', "Golden Tee '99 (v1.00S)", '1999', 's', 's_ver',
     (
         ('gt99_prom0_v1.00s.prom0', '58e7c4e1'),
         ('gt99_prom1_v1.00s.prom1', '09f8bdf4'),
         ('gt99_prom2_v1.00s.prom2', 'fd084b68'),
         ('gt99_prom3_v1.00s.prom3', '3ff88ff7'),
     ), ('gtg3_nr_u23_v2.2.u23', '04effd73'), GT99_GROM, GT_S_SAMPLES, "d215ac40614512d698168f3fb4c1db01"),
    ('gt2k', None, 'Golden Tee 2K (v1.00)', '2000', 'aama', 'aama',
     (
         ('gt2k_prom0_v1.00.prom0', 'b83d7b67'),
         ('gt2k_prom1_v1.00.prom1', '89bd952d'),
         ('gt2k_prom2_v1.00.prom2', 'b603d283'),
         ('gt2k_prom3_v1.00.prom3', '85ba9e2d'),
     ), ('gt2knr_u88_v1.0.u88', '2cee9e98'), GT2K_GROM, GT2K_SAMPLES, "33677ebf74f0891006010b33ce47fac0"),
    ('gt2kp100', 'gt2k', 'Golden Tee 2K (v1.00, alternate protection)', '2000', 'gt2kp', 'aama',
     (
         ('gt2kprm0.10p', '16e8502d'),
         ('gt2kprm1.10p', 'bf47cd95'),
         ('gt2kprm2.10p', '204ddf15'),
         ('gt2kprm3.10p', '45b9dd56'),
     ), ('gt2knr_u88_v1.0.u88', '2cee9e98'), GT2K_GROM, GT2K_SAMPLES, "8b858e1fb1f244ede21c2b54e7cc972d"),
    ('gt2ks100', 'gt2k', 'Golden Tee 2K (v1.00S)', '2000', 's', 's_ver',
     (
         ('gt2k_kit_prom0_v1.00m.prom0', '3aab67c8'),
         ('gt2k_kit_prom1_v1.00m.prom1', '47d4a74d'),
         ('gt2k_kit_prom2_v1.00m.prom2', '77a222cc'),
         ('gt2k_kit_prom3_v1.00m.prom3', 'c3e77ad5'),
     ), ('gtg3_nr_u23_v2.2.u23', '04effd73'), GT2K_GROM, GT_S_SAMPLES, "402fb444f1f059b531c1dec66b981c0d"),
    ('gtclassc', None, 'Golden Tee Classic (v1.00)', '2001', 'aama', 'aama',
     (
         ('gt_classic_prom0_v1.00.prom0', 'a57e6ef0'),
         ('gt_classic_prom1_v1.00.prom1', '15f8a831'),
         ('gt_classic_prom2_v1.00.prom2', '2f260a93'),
         ('gt_classic_prom3_v1.00.prom3', '03a1fcdd'),
     ), ('gt_classicnr_u88_v1.0.u88', '2cee9e98'), GTCLASSIC_GROM, GTCLASSIC_SAMPLES, "a0088e72ba38261ad5f68ef26c8206f2"),
    ('gtclasscp', 'gtclassc', 'Golden Tee Classic (v1.00, alternate protection)', '2001', 'gtclasscp', 'aama',
     (
         ('gtcpprm0.100', '21f0e0ea'),
         ('gtcpprm1.100', 'd2a69fbc'),
         ('gtcpprm2.100', 'a8dea029'),
         ('gtcpprm3.100', '6016299e'),
     ), ('gt_classicnr_u88_v1.0.u88', '2cee9e98'), GTCLASSIC_GROM, GTCLASSIC_SAMPLES, "98a9508f047a9a2db86c21e001b30ffa"),
    ('gtclasscs', 'gtclassc', 'Golden Tee Classic (v1.00S)', '2001', 's', 's_ver',
     (
         ('gt_classic_prom0_v1.00m.prom0', '1e41884f'),
         ('gt_classic_prom1_v1.00m.prom1', '31c18b2c'),
         ('gt_classic_prom2_v1.00m.prom2', '8896efcb'),
         ('gt_classic_prom3_v1.00m.prom3', '567a9490'),
     ), ('gtg3_nr_u23_v2.2.u23', '04effd73'), GTCLASSIC_GROM, GT_S_SAMPLES, "285a0406acd2f4e5402b632e958a0f41"),
)

GT3D_GROM_T211 = (
    ('gtg3_grom0_0++.grm0_0', '22c481b7'),
    ('gtg3_grom0_1++.grm0_1', '40e4032b'),
    ('gtg3_grom0_2++.grm0_2', '67a02ef9'),
    ('gtg3_grom0_3++.grm0_3', '1173a710'),
    ('gtg3_grom1_0+.grm1_0', '80ae7148'),
    ('gtg3_grom1_1+.grm1_1', '0f85a618'),
    ('gtg3_grom1_2+.grm1_2', '09ca5fbf'),
    ('gtg3_grom1_3+.grm1_3', 'd136853a'),
)
GT98_GROM_DIAMOND = (
    ('gt98_grom0_0.grm0_0', '2d79492b'),
    ('gt98_grom0_1.grm0_1', '79afda1a'),
    ('gt98_grom0_2.grm0_2', '8c381f56'),
    ('gt98_grom0_3.grm0_3', '46c35ba6'),
    ('gt98_grom1_0.grm1_0', 'b07bc634'),
    ('gt98_grom1_1.grm1_1', 'b23d59a7'),
    ('gt98_grom1_2.grm1_2', '9c113abc'),
    ('gt98_grom1_3.grm1_3', '231bbe58'),
    ('gt98_grome2_0.grm2_0', '0c898920'),
    ('gt98_grome2_1.grm2_1', 'cbe5b2b2'),
    ('gt98_grome2_2.grm2_2', '71bd4441'),
    ('gt98_grome2_3.grm2_3', '86149804'),
)
GT2K_GROM_SUPREME = (
    ('gt2k_grom0_0.grm0_0', 'c22b50f9'),
    ('gt2k_grom0_1.grm0_1', 'd6d6be57'),
    ('gt2k_grom0_2.grm0_2', '005d4791'),
    ('gt2k_grom0_3.grm0_3', '0c998eb7'),
    ('gt2k_grom1_0.grm1_0', '8b79d6e2'),
    ('gt2k_grom1_1.grm1_1', '84ef1803'),
    ('gt2k_grom1_2.grm1_2', 'd73d8afc'),
    ('gt2k_grom1_3.grm1_3', '59f48688'),
    ('gt_supreme_grom2_0.grm2_0', '33998a3e'),
    ('gt_supreme_grom2_1.grm2_1', 'afa937ef'),
    ('gt_supreme_grom2_2.grm2_2', '8f39c061'),
    ('gt_supreme_grom2_3.grm2_3', 'c3c2337a'),
)

# Tournament editions (MAME init_aamat): the single board plus the M48T02
# timekeeper. Same fields as GT_SETS.
GT_TOURNAMENT_SETS = (
    ('gt3dt231', 'gt3d', 'Golden Tee 3D Golf Tournament (v2.31)', '1995', 'aama_t', 'gt3d',
     (
         ('gtg3_prom0_v2.31t.prom0', '92a5c3e9'),
         ('gtg3_prom1_v2.31t.prom1', 'a3b60226'),
         ('gtg3_prom2_v2.31t.prom2', 'd1659616'),
         ('gtg3_prom3_v2.31t.prom3', '1d231ea2'),
     ), ('gtg3nr_u88_v1.0.u88', '2cee9e98'), GT3D_GROM_T, GT3D_SAMPLES, "ea6504dfc3615e253de4a85108b6edc1"),
    ('gt3dt230', 'gt3d', 'Golden Tee 3D Golf Tournament (v2.30)', '1995', 'aama_t', 'gt3d',
     (
         ('gtg3_prom0_v2.30t.prom0', '4c658915'),
         ('gtg3_prom1_v2.30t.prom1', 'f79fd0aa'),
         ('gtg3_prom2_v2.30t.prom2', '372d24d7'),
         ('gtg3_prom3_v2.30t.prom3', '82392f2c'),
     ), ('gtg3nr_u88_v1.0.u88', '2cee9e98'), GT3D_GROM_T, GT3D_SAMPLES, "8d08f9a790bc7d3ff9501f1646a51f69"),
    ('gt3dt211', 'gt3d', 'Golden Tee 3D Golf Tournament (v2.11)', '1995', 'aama_t', 'gt3d',
     (
         ('gtg3_prom0_v2.11t.prom0', '54360fdf'),
         ('gtg3_prom1_v2.11t.prom1', '9142ebb7'),
         ('gtg3_prom2_v2.11t.prom2', '058b906a'),
         ('gtg3_prom3_v2.11t.prom3', '8dbeee1b'),
     ), ('gtg3nr_u88_v1.0.u88', '2cee9e98'), GT3D_GROM_T211, GT3D_SAMPLES, "b6f2f855600ed7f99bde899fc6df586a"),
    ('gt97t243', 'gt97', "Golden Tee '97 Tournament (v2.43)", '1997', 'aama_t', 'gt97o',
     (
         ('gt97_prom0_v2.43t.prom0', 'b8de60f1'),
         ('gt97_prom1_v2.43t.prom1', '8152e5d3'),
         ('gt97_prom2_v2.43t.prom2', 'b80061be'),
         ('gt97_prom3_v2.43t.prom3', 'd184968d'),
     ), ('gt97nr_u88_v1.0.u88', '2cee9e98'), GT97_GROM, GT97_SAMPLES, "7105721a2262a9759ca05bc7c5080870"),
    ('gt97t240', 'gt97', "Golden Tee '97 Tournament (v2.40)", '1997', 'aama_t', 'gt97o',
     (
         ('gt97_prom0_v2.40t.prom0', '88a386d0'),
         ('gt97_prom1_v2.40t.prom1', 'b0d751aa'),
         ('gt97_prom2_v2.40t.prom2', '451be534'),
         ('gt97_prom3_v2.40t.prom3', '70da8ca5'),
     ), ('gt97nr_u88_v1.0.u88', '2cee9e98'), GT97_GROM, GT97_SAMPLES, "0323d768918e4dcace3a7537c26f675f"),
    ('gt98t303', 'gt98', "Golden Tee '98 Tournament (v3.03)", '1998', 'aama_t', 'gt98s',
     (
         ('gt98_prom0_v3.03t.prom0', 'e3879c30'),
         ('gt98_prom1_v3.03t.prom1', '6a42ab1e'),
         ('gt98_prom2_v3.03t.prom2', 'a695c1bc'),
         ('gt98_prom3_v3.03t.prom3', 'bd7f5c7a'),
     ), ('gt98nr_u88_v1.0.u88', '2cee9e98'), GT98_GROM, GT98_SAMPLES, "94aa8cefa7f24d5e2fa837340327c85f"),
    ('gt98t302', 'gt98', "Golden Tee '98 Tournament (v3.02)", '1998', 'aama_t', 'gt98s',
     (
         ('gt98_prom0_v3.02t.prom0', '744e0d9b'),
         ('gt98_prom1_v3.02t.prom1', 'b25508a1'),
         ('gt98_prom2_v3.02t.prom2', '98a3466e'),
         ('gt98_prom3_v3.02t.prom3', '17c3152a'),
     ), ('gt98nr_u88_v1.0.u88', '2cee9e98'), GT98_GROM, GT98_SAMPLES, "2cac70975c3e7b7dedeb9977225c1b62"),
    ('gtdiamond', 'gt98', 'Golden Tee Diamond Edition Tournament (v3.05T ELC)', '1998', 'aama_t', 'gt98s',
     (
         ('gt98_golf_elc_prom0_v3.05tl.prom0', 'b6b0e3b8'),
         ('gt98_golf_elc_prom1_v3.05tl.prom1', 'ba15f3a3'),
         ('gt98_golf_elc_prom2_v3.05tl.prom2', '015e1c94'),
         ('gt98_golf_elc_prom3_v3.05tl.prom3', 'd990528b'),
     ), ('gt98nr_u88_v1.0.u88', '2cee9e98'), GT98_GROM_DIAMOND, GT98_SAMPLES, "4ce4854829cdef81a640f953045228b0"),
    ('gt99t400', 'gt99', "Golden Tee '99 Tournament (v4.00)", '1999', 'aama_t', 'gt98s',
     (
         ('gt99_prom0_v4.00t.prom0', 'bc58e0a2'),
         ('gt99_prom1_v4.00t.prom1', '89d8cc6b'),
         ('gt99_prom2_v4.00t.prom2', '891e26c1'),
         ('gt99_prom3_v4.00t.prom3', '127f7aa7'),
     ), ('gt99nr_u88_v1.0.u88', '2cee9e98'), GT99_GROM, GT99_SAMPLES, "2ed36c1633fa38611edf67398a6fa526"),
    ('gtroyal', 'gt99', 'Golden Tee Royal Edition Tournament (v4.02T EDM)', '1999', 'aama_t', 'gt98s',
     (
         ('gtr_prom0_v4.02t_edm.prom0', 'ae499ea3'),
         ('gtr_prom1_v4.02t_edm.prom1', '87ee04b5'),
         ('gtr_prom2_v4.02t_edm.prom2', 'a925d392'),
         ('gtr_prom3_v4.02t_edm.prom3', '1c442664'),
     ), ('gt99nr_u88_v1.0.u88', '2cee9e98'), GT99_GROM, GT99_SAMPLES, "dc91435698d2b8fea02c6debd1eec490"),
    ('gt2kt500', 'gt2k', 'Golden Tee 2K Tournament (v5.00)', '2000', 'aama_t', 'gt98s',
     (
         ('gt2k_prom0_v5.00t.prom0', '8f20f9eb'),
         ('gt2k_prom1_v5.00t.prom1', 'bdecc1f5'),
         ('gt2k_prom2_v5.00t.prom2', '46666c15'),
         ('gt2k_prom3_v5.00t.prom3', '89544fbc'),
     ), ('gt2knr_u88_v1.0.u88', '2cee9e98'), GT2K_GROM, GT2K_SAMPLES, "19ea2b2e6a54586c1bb47f178dfb6fc9"),
    ('gtsupreme', 'gt2k', 'Golden Tee Supreme Edition Tournament (v5.10T ELC S)', '2002', 'aama_t', 'gt98s',
     (
         ('gtg_sup_elc_prom0_5.10t.prom0', 'a14f7e2b'),
         ('gtg_sup_elc_prom1_5.10t.prom1', '772f4dc9'),
         ('gtg_sup_elc_prom2_5.10t.prom2', 'fbaae916'),
         ('gtg_sup_elc_prom3_5.10t.prom3', '69b13204'),
     ), ('gt2knr_u88_v1.0.u88', '2cee9e98'), GT2K_GROM_SUPREME, GT2K_SAMPLES, "55a25ea2f92fecdb20c8a47380c9d9d9"),
)


def gt_pad(size: int) -> str:
    return f'        <part repeat="{size:#x}">00</part>'


def gt_sample_rom(rom: tuple[str, str], size: int) -> str:
    # ROM_LOAD16_BYTE fills the even byte of each 16-bit sample word.
    name, crc = rom
    return (
        '        <interleave output="16">\n'
        f'            <part name="{name}" crc="{crc}" map="01" />\n'
        f'            <part map="10" repeat="{size:#x}">00</part>\n'
        '        </interleave>'
    )


def golden_tee_mra(spec: tuple) -> str:
    setname, parent, title, year, board, ports, program, sound, grom, samples, md5 = spec
    selector, trackballs, layout = GT_BOARDS[board]
    timekeeper = board in GT_TIMEKEEPER_BOARDS
    # The tournament programs fill the 4 MiB region; the others use half.
    program_bytes = 0x400000 if timekeeper else 0x200000
    zip_names = f"{setname}.zip" if parent is None else f"{setname}.zip|{parent}.zip"
    dips = [f'        <dip name="{name}" bits="{bit}" ids="{ids}" />'
            for bit, (name, ids) in GT_DIPS[ports]]
    dips.append('        <dip name="Service Mode" bits="3" ids="Off,On" />')
    if trackballs == 2:
        controls = ("The mouse, left stick or d-pad moves trackball 1; with Two Trackballs set, "
                    "player 2 uses the second controller's stick or d-pad.")
    else:
        controls = "The mouse, left stick or d-pad moves this board's single trackball."
    sound_name, sound_crc = sound
    lines = [
        "<?xml version='1.0' encoding='utf-8'?>",
        "<misterromdescription>",
        f"    <name>{title}</name>",
        f"    <setname>{setname}</setname>",
        "    <rbf>ITech32</rbf>",
        "    <mameversion>0288</mameversion>",
        f"    <year>{year}</year>",
        "    <manufacturer>Incredible Technologies</manufacturer>",
        "    <players>4</players>",
        "    <joystick>Trackball</joystick>",
        "    <rotation>Horizontal</rotation>",
        "    <region>World</region>",
        "    <platform>Incredible Technologies 32-bit</platform>",
        "    <category>Sports</category>",
        "    <!--DIP bits0..3 map to native masks10/20/40/80, physical SW1:4/3/2/1.-->",
        '    <switches default="00">',
        *dips,
        "    </switches>",
        "    <!--MAME: B1 Face Left, B2 Face Right; player 1's B3/B4 are the cabinet's Volume "
        f"Up/Down. {controls}-->",
        '    <buttons names="Face Left,Face Right,Volume Up,Volume Down,-,-,Start,Coin" '
        'default="A,B,X,Y,Start,Select" count="4" />',
        f"    <!--Board selector {selector} must precede the address30000000 bulk stream.-->",
        '    <rom index="1">',
        f"        <part>{selector}</part>",
        "    </rom>",
        *(("    <!-- 128 KiB battery-backed NVRAM at CPU 0x600000-0x61ffff, then the 2 KiB "
            "M48T02 timekeeper at 0x681000-0x6817ff. -->",
            f'    <nvram index="2" size="{NVRAM_TIMEKEEPER_BYTES}" />') if timekeeper else
          ("    <!-- 128 KiB battery-backed NVRAM at CPU 0x600000-0x61ffff. -->",
           '    <nvram index="2" size="131072" />')),
        f'    <rom index="0" zip="{zip_names}" address="0x30000000" md5="{md5}">',
        "        <!-- 0x0000000: 68EC020 program, 4 MiB. -->" if timekeeper else
        "        <!-- 0x0000000: 68EC020 program, 2 MiB of the 4 MiB region. -->",
        '        <interleave output="32">',
        program32(program),
        "        </interleave>",
        *([] if timekeeper else [gt_pad(0x400000 - program_bytes)]),
        "        <!-- 0x0400000: 6809 sound region; bank 0 at 0x10000. -->",
        gt_pad(0x8000),
        f'        <part name="{sound_name}" crc="{sound_crc}" offset="0x18000" length="0x8000" />',
        f'        <part name="{sound_name}" crc="{sound_crc}" offset="0x0" length="0x18000" />',
        gt_pad(0xd8000),
        "        <!-- 0x0500000: GROM; the blitter wraps at the 0x600000 MAME region. -->",
    ]
    # Three 2 MiB groups, or (GT 3D v2.11) one 4 MiB and one 2 MiB group.
    for group in range(len(grom) // 4):
        lines += ['        <interleave output="32">', program32(grom[group * 4:group * 4 + 4]),
                  "        </interleave>"]
    if layout == "three":
        rom0, srom1, srom2, srom3 = samples
        lines += [
            gt_pad(0x1700000),
            "        <!-- 0x2200000: ES5506 bank 3 (ensoniq.3), slot C at the top of the GROM "
            "window. -->",
            gt_sample_rom(srom3, 0x20000), gt_pad(0x3c0000),
            "        <!-- 0x2600000: ES5506 bank 0 (ensoniq.0), slot A. -->",
            gt_sample_rom(rom0, 0x200000),
            "        <!-- 0x2a00000: ES5506 bank 2 (ensoniq.2), slot B. -->",
            gt_sample_rom(srom1, 0x80000), gt_pad(0x100000),
            gt_sample_rom(srom2, 0x80000), gt_pad(0x100000),
        ]
    else:
        low, high = samples
        bank = "bank 0 (ensoniq.0)" if layout == "single" else "bank 2 (ensoniq.2)"
        lines += [
            gt_pad(0x1b00000),
            f"        <!-- 0x2600000: ES5506 {bank}, slot A. -->",
            gt_sample_rom(low, 0x100000), gt_sample_rom(high, 0x80000), gt_pad(0x100000),
            "        <!-- 0x2a00000: slot B, unused. -->",
            gt_pad(0x400000),
        ]
    lines += ["    </rom>", "</misterromdescription>"]
    return "\n".join(lines) + "\n"


def generate_golden_tee() -> list[Path]:
    # The releases are checked, not written: they stay reviewable files.
    titles = {spec[0]: spec[2] for spec in GT_SETS}
    written = []
    for spec in GT_SETS + GT_TOURNAMENT_SETS:
        setname, parent, title = spec[:3]
        text = golden_tee_mra(spec)
        if parent is None:
            release = RELEASES / f"{title}.mra"
            if release.read_text(encoding="utf-8") != text:
                raise RuntimeError(f"{release.name} differs from its Golden Tee description")
        else:
            group = titles[parent].rsplit(" (", 1)[0]
            written.append(write_alternative(group, f"{title}.mra", text))
    return written


# World Class Bowling Tournament (MAME init_wcbowlt): the Deluxe board's
# protection address, GROM data and samples, plus the M48T02 timekeeper.
WCBOWLDX_PARENT = ("World Class Bowling Deluxe (v2.00)", "wcbowldx", "wcbowldx.zip|wcbowl.zip",
                   "9b306690bcaad3461611b62fe28eba04")
WCBOWLDX_PROGRAM = (("wcbd_prom0_2.00.prom0", "280df7f0"), ("wcbd_prom1_2.00.prom1", "526eded0"),
                    ("wcbd_prom2_2.00.prom2", "cb263173"), ("wcbd_prom3_2.00.prom3", "43ecad0b"))
# setname, title, program, MAME input-port group, MD5.
WCBOWL_TOURNAMENT_SPECS = (
    ("wcbowl140", "World Class Bowling Tournament (v1.40)",
     (("wcbf_prom0_1.40.prom0", "9d31ceb1"), ("wcbf_prom1_1.40.prom1", "c6669452"),
      ("wcbf_prom2_1.40.prom2", "d2fc4d09"), ("wcbf_prom3_1.40.prom3", "c41258a4")),
     "wcbowldx", "da5e20d5f0a7c3a039e7926b31e55927"),
    ("wcbowl130", "World Class Bowling Tournament (v1.30)",
     (("wcb_prom0_v1.30t.prom0", "fbcde4e0"), ("wcb_prom1_v1.30t.prom1", "f4b8e7c3"),
      ("wcb_prom2_v1.30t.prom2", "f441afae"), ("wcb_prom3_v1.30t.prom3", "47e26d4b")),
     "wcbowlo", "cd7f16ad6661dc5aa925c7d06ad66b9d"),
)


def generate_wcbowl_tournament() -> list[Path]:
    template = (RELEASES / f"{WCBOWLDX_PARENT[0]}.mra").read_text(encoding="utf-8")
    written = []
    for setname, title, program, ports, md5 in WCBOWL_TOURNAMENT_SPECS:
        # MAME makes these clones of wcbowl, not of the Deluxe set.
        text = retitle_020(template, WCBOWLDX_PARENT, setname, title, md5)
        text = replace_once(text, f'zip="{setname}.zip|wcbowldx.zip"',
                            f'zip="{setname}.zip|wcbowl.zip"', setname)
        text = replace_once(text, "<year>1999</year>", "<year>1997</year>", setname)
        text = replace_once(text, program32(WCBOWLDX_PROGRAM), program32(program), setname)
        text = replace_once(text, "<!--Board selector 08 must", "<!--Board selector 12 must",
                            setname)
        text = replace_once(text, "        <part>08</part>", "        <part>12</part>", setname)
        text = replace_once(
            text,
            "    <!-- 128 KiB battery-backed NVRAM at CPU 0x600000-0x61ffff. -->\n"
            '    <nvram index="2" size="131072" />',
            "    <!-- 128 KiB battery-backed NVRAM at CPU 0x600000-0x61ffff, then the 2 KiB "
            "M48T02 timekeeper at 0x681000-0x6817ff. -->\n"
            f'    <nvram index="2" size="{NVRAM_TIMEKEEPER_BYTES}" />',
            setname)
        for group in (0, 1):
            for part in range(4):
                text = replace_once(text, f'name="wcbd_grom{group}_{part}_s.grm{group}_{part}"',
                                    f'name="wcb_grom{group}_{part}_s.grm{group}_{part}"', setname)
        for part in range(4):
            text = replace_once(text, f'name="wcbd_grom2_{part}_s.grm2_{part}"',
                                f'name="wcbf_grom2_{part}.grm2_{part}"', setname)
        if ports == "wcbowlo":
            text = replace_once(text, FLIP_DIP, FLIP_DIP + "\n" + FREEZE_DIP, setname)
        written.append(write_alternative("World Class Bowling", f"{title}.mra", text))
    return written


def main() -> int:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    written = (generate_timekill() + generate_bloodstorm() + generate_sftm() +
               generate_hardyard() + generate_pairs() + generate_hotmemry() +
               generate_wcbowl() + generate_wcbowl_020() + generate_shufshot() +
               generate_wcbowl_tournament() + generate_golden_tee())
    expected = {path.resolve() for path in written} | {WCBOWL_68000_TEMPLATE.resolve()}
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
