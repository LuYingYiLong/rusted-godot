"""Compare the Godot native unit IDs with a Rusted Warfare 1.15 source tree.

Usage:
    python tools/verify_rw_115_native_catalog.py --source-root PATH
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = PROJECT_ROOT / "scripts/utils/units/rw_vanilla_unit_catalog.gd"
SOURCE_PATHS = {
    "registry": Path("02b-decompiled/com/corrodinggames/rts/game/units/ar.java"),
    "writer": Path("02b-decompiled/com/corrodinggames/rts/gameFramework/j/as.java"),
    "reader": Path("02b-decompiled/com/corrodinggames/rts/gameFramework/j/k.java"),
}
ENUM_PROBE_PATH = PROJECT_ROOT / "tools/Rw115NativeEnumProbe.java"
EXPECTED_STOCK_SHA256_PREFIX = "8a550a37e2d8a543"


def _read_source(root: Path, key: str) -> str:
    path = root / SOURCE_PATHS[key]
    if not path.is_file():
        raise FileNotFoundError(f"Missing {key}: {path}")
    return path.read_text(encoding="utf-8")


def _source_native_types(source: str) -> list[str]:
    declaration = source.split("public enum ar implements as {", 1)
    if len(declaration) != 2:
        raise ValueError("Could not locate the 1.15 native unit enum")
    entries = declaration[1].split(";", 1)[0] + ";"
    matches = re.findall(r'^\s*([A-Za-z])\("([^"]+)",\s*(\d+)\)[,;]', entries, re.MULTILINE)
    if not matches:
        raise ValueError("No native unit enum entries found")
    types = [name for _, name, _ in matches]
    for index, (_, name, ordinal) in enumerate(matches):
        if int(ordinal) != index:
            raise ValueError(f"Unexpected source ordinal for {name}: {ordinal} != {index}")
    return types


def _godot_native_types(source: str) -> list[str]:
    declaration = source.split("const NATIVE_TYPES: Array[String] = [", 1)
    if len(declaration) != 2:
        raise ValueError("Could not locate the Godot native type catalog")
    entries = declaration[1].split("\n]", 1)[0]
    types = re.findall(r'^\s*"([^"]+)",\s*$', entries, re.MULTILINE)
    if not types:
        raise ValueError("No Godot native types found")
    return types


def _binary_native_types(game_jar: Path, java: str) -> list[str]:
    if not game_jar.is_file():
        raise FileNotFoundError(f"Missing game jar: {game_jar}")
    classpath = os.pathsep.join((str(game_jar), str(game_jar.parent / "libs" / "*")))
    completed = subprocess.run(
        [java, "--class-path", classpath, str(ENUM_PROBE_PATH)],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    matches = re.findall(r"^(\d+):([^\r\n]+)$", completed.stdout, re.MULTILINE)
    if not matches:
        raise ValueError(f"No enum entries from game jar: {completed.stderr.strip()}")
    for expected, (ordinal, name) in enumerate(matches):
        if int(ordinal) != expected:
            raise ValueError(f"Unexpected binary ordinal for {name}: {ordinal} != {expected}")
    return [name for _, name in matches]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--game-jar", type=Path)
    parser.add_argument("--java", default="java")
    args = parser.parse_args()

    try:
        registry = _read_source(args.source_root, "registry")
        writer = _read_source(args.source_root, "writer")
        reader = _read_source(args.source_root, "reader")
        source_types = _source_native_types(registry)
        godot_types = _godot_native_types(CATALOG_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError) as error:
        print(f"RW_115_CATALOG_ERROR {error}")
        return 1

    if "((com.corrodinggames.rts.game.units.ar)var1).ordinal()" not in writer:
        print("RW_115_CATALOG_ERROR Source writer does not use the native enum ordinal")
        return 1
    if "com.corrodinggames.rts.game.units.ar.class.getEnumConstants()" not in reader:
        print("RW_115_CATALOG_ERROR Source reader does not load the native enum constants")
        return 1
    if "return (com.corrodinggames.rts.game.units.ar)var2[var1]" not in reader:
        print("RW_115_CATALOG_ERROR Source reader does not index the native enum")
        return 1

    if len(source_types) != len(godot_types):
        print(f"RW_115_CATALOG_MISMATCH counts source={len(source_types)} godot={len(godot_types)}")
        return 1
    differences = [
        f"{index}: source={source_name} godot={godot_name}"
        for index, (source_name, godot_name) in enumerate(zip(source_types, godot_types))
        if source_name != godot_name
    ]
    if differences:
        print("RW_115_CATALOG_MISMATCH " + "; ".join(differences))
        return 1

    if args.game_jar is not None:
        try:
            binary_types = _binary_native_types(args.game_jar, args.java)
        except (FileNotFoundError, ValueError, OSError, subprocess.CalledProcessError) as error:
            print(f"RW_115_CATALOG_ERROR Binary probe failed: {error}")
            return 1
        if binary_types != source_types:
            print("RW_115_CATALOG_MISMATCH Binary enum differs from the source enum")
            return 1
        digest = hashlib.sha256(args.game_jar.read_bytes()).hexdigest()
        if not digest.startswith(EXPECTED_STOCK_SHA256_PREFIX):
            print(f"RW_115_CATALOG_MISMATCH Game jar is not the documented 1.15 stock build: {digest}")
            return 1
        print(f"RW_115_BINARY_OK native_types={len(binary_types)} sha256={digest}")

    print(f"RW_115_CATALOG_OK native_types={len(source_types)} ordinal_writer=confirmed ordinal_reader=confirmed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
