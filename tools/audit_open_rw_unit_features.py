"""Inventory every explicit INI key in the bundled OpenRW unit definitions.

The output keeps source locations so a missing behavior can be traced to the
unit that uses it. It does not infer that parsing a key implements its behavior.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path


ENTRY_PATTERN = re.compile(r"^\s*([^:=]+?)\s*[:=]\s*(.*?)\s*$")


def section_family(section: str) -> str:
    prefix = section.split("_", 1)[0]
    if prefix in {"turret", "projectile", "action", "hiddenaction", "canbuild", "effect", "animation", "leg", "arm", "attachment", "decal", "resource", "placementrule"}:
        return prefix
    return section


def read_keys(path: Path) -> tuple[str, bool, dict[str, set[str]], dict[str, str]]:
    section = ""
    name = ""
    disabled = False
    keys: dict[str, set[str]] = defaultdict(set)
    movement_values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].casefold()
            continue
        if not line or line.startswith(("#", ";")) or section.startswith("comment_"):
            continue
        match = ENTRY_PATTERN.match(line)
        if match is None:
            continue
        key, value = match.group(1).strip().casefold(), match.group(2).strip()
        keys[section_family(section)].add(key)
        if section == "movement":
            movement_values[key] = value
        if section == "core" and key == "name":
            name = value
        if section == "core" and key == "dont_load" and value.casefold() == "true":
            disabled = True
    return name, disabled, keys, movement_values


def inventory(assets_root: Path) -> dict[str, object]:
    if not assets_root.is_dir():
        raise FileNotFoundError(assets_root)
    family_keys: dict[str, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))
    loaded_units: dict[str, str] = {}
    movement_by_unit: dict[str, dict[str, str]] = {}
    ini_files = sorted(assets_root.rglob("*.ini"))
    for path in ini_files:
        name, disabled, keys, movement_values = read_keys(path)
        if not name or name.upper() in {"NONE", "IGNORE", "NULL"} or disabled:
            continue
        relative_path = path.relative_to(assets_root).as_posix()
        if name in loaded_units:
            raise ValueError(f"Duplicate unit name: {name}")
        loaded_units[name] = relative_path
        if movement_values:
            movement_by_unit[name] = movement_values
        for family, family_entries in keys.items():
            for key in family_entries:
                family_keys[family][key].append(name)
    return {
        "ini_file_count": len(ini_files),
        "loadable_unit_count": len(loaded_units),
        "loadable_units": dict(sorted(loaded_units.items())),
        "movement_by_unit": dict(sorted(movement_by_unit.items())),
        "families": {
            family: {key: sorted(units) for key, units in sorted(entries.items())}
            for family, entries in sorted(family_keys.items())
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets_root", type=Path, help="OpenRW assets/units directory")
    parser.add_argument("--output", type=Path, help="Write UTF-8 JSON inventory here")
    args = parser.parse_args()
    result = inventory(args.assets_root)
    output = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output is None:
        print(output, end="")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8", newline="\n")
        print(
            f"Scanned {result['ini_file_count']} INIs, "
            f"{result['loadable_unit_count']} units, "
            f"{len(result['families'])} section families -> {args.output}"
        )


if __name__ == "__main__":
    main()
