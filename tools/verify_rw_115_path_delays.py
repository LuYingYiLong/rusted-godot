"""Compare the 1.15 path request delay bands with the Godot implementation.

Usage:
    python tools/verify_rw_115_path_delays.py --source-root PATH
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = Path("02b-decompiled/com/corrodinggames/rts/gameFramework/k/l.java")
GODOT_PATH = PROJECT_ROOT / "scripts/utils/units/rw_path_grid.gd"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    args = parser.parse_args()

    try:
        source = (args.source_root / SOURCE_PATH).read_text(encoding="utf-8")
        godot = GODOT_PATH.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        print(f"RW_115_PATH_DELAY_ERROR {error}")
        return 1

    source_function = source.split("public strictfp void a(k var1, boolean var2, boolean var3)", 1)
    godot_function = godot.split("func network_path_delay_frames(", 1)
    if len(source_function) != 2 or len(godot_function) != 2:
        print("RW_115_PATH_DELAY_ERROR Missing a path delay function")
        return 1
    source_bands = re.findall(
        r"var6 < (\d+) && var7 < \1\)\s*\{\s*var1\.t = ([\d.]+)F;",
        source_function[1].split("if(!var4.bX.B", 1)[0],
    )
    godot_bands = re.findall(
        r"difference\.x < (\d+) and difference\.y < \1:\s*return (\d+)",
        godot_function[1].split("func _straight_line_waypoints", 1)[0],
    )
    normalized_source = [(int(limit), int(float(delay))) for limit, delay in source_bands]
    normalized_godot = [(int(limit), int(delay)) for limit, delay in godot_bands]
    if not normalized_source or normalized_source != normalized_godot:
        print(f"RW_115_PATH_DELAY_MISMATCH source={normalized_source} godot={normalized_godot}")
        return 1
    if "var1.t = 300.0F;" not in source_function[1] or "return 300" not in godot_function[1]:
        print("RW_115_PATH_DELAY_MISMATCH Default 300-frame delay differs")
        return 1

    print(f"RW_115_PATH_DELAY_OK bands={len(normalized_source) + 1}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
