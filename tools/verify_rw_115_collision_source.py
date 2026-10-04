"""Verify the collision rules used by the Rusted Warfare 1.15 reference test.

Usage:
    python tools/verify_rw_115_collision_source.py --source-root PATH
"""

from __future__ import annotations

import argparse
from pathlib import Path


SOURCE_DIRECTORY = Path("02b-decompiled/com/corrodinggames/rts/game/units")
SOURCE_MARKERS = {
    "default_group": "byte var1 = 1;",
    "group_assignment": "this.bU = var1;",
    "group_filter": "var5 != -1 && var5 == var1.bU",
    "team_weight": "if(this.bX == var1.bX)",
    "candidate_limit": "this.aJ = new am[10];",
    "active_refresh": "var7.aL = var2 + 50 + var6 % 50;",
    "idle_refresh": "var7.aL = var2 + 250 + var6 % 50;",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    args = parser.parse_args()
    directory = args.source_root / SOURCE_DIRECTORY
    try:
        unit_source = (directory / "am.java").read_text(encoding="utf-8")
        collision_source = (directory / "y.java").read_text(encoding="utf-8")
    except FileNotFoundError as error:
        print(f"RW_115_COLLISION_SOURCE_ERROR {error}")
        return 1

    for name, marker in SOURCE_MARKERS.items():
        source = unit_source if name in {"default_group", "group_assignment"} else collision_source
        if marker not in source:
            print(f"RW_115_COLLISION_SOURCE_ERROR Missing {name}: {marker}")
            return 1

    print("RW_115_COLLISION_SOURCE_OK group_filter=1 team_weight=1 candidate_limit=10 refresh=staggered")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
