"""Generate stock INI production links and conversion actions."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from generate_rw_builtin_unit_specs import effective_sections, gd, number
from generate_rw_vanilla_unit_catalog import read_builtin_units, read_native_types


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = PROJECT_ROOT / "scripts/utils/units/rw_builtin_action_specs.gd"
SKIPPED_TARGETS = {"", "none", "ignore"}


def targets(value: str) -> list[str]:
    return [name.strip() for name in value.split(",") if name.strip().casefold() not in SKIPPED_TARGETS]


def build_rate(value: str) -> float:
    value = value.strip().casefold()
    if value.endswith("s"):
        seconds = number(value[:-1])
        return 1.0 / (seconds * 60.0) if seconds > 0.0 else 1000.0
    parsed = number(value, 1000.0)
    return parsed if parsed > 0.0 else 1000.0


def create_spec(path: Path) -> dict[str, object]:
    sections = effective_sections(path)
    core = sections.get("core", {})
    built_from: list[dict[str, object]] = []
    for index in range(1, 4):
        prefix = f"builtfrom_{index}_"
        for producer in targets(core.get(prefix + "name", "")):
            built_from.append({
                "producer": producer,
                "tech": int(number(core.get(prefix + "techlevel", ""), 1.0)),
                "position": number(core.get(prefix + "pos", ""), 999.0),
                "force_nano": core.get(prefix + "forcenano", "").casefold() == "true",
            })
    can_build: list[dict[str, object]] = []
    for index in range(51):
        prefix = f"canbuild_{index}_"
        for target in targets(core.get(prefix + "name", "")):
            can_build.append({
                "target": target,
                "tech": int(number(core.get(prefix + "tech", ""), 1.0)),
                "force_nano": core.get(prefix + "forcenano", "").casefold() == "true",
            })
    for section, entries in sections.items():
        if not section.startswith("canbuild_"):
            continue
        for target in targets(entries.get("name", "")):
            can_build.append({
                "target": target,
                "tech": int(number(entries.get("tech", ""), 1.0)),
                "force_nano": entries.get("forcenano", "").casefold() == "true",
            })
    conversions: list[dict[str, object]] = []
    resource_actions: list[dict[str, object]] = []
    action_index = len(can_build)
    for index in range(51):
        prefix = f"action_{index}_"
        if not any(key.startswith(prefix) for key in core):
            continue
        action = {key.removeprefix(prefix): value for key, value in core.items() if key.startswith(prefix)}
        append_conversion(conversions, action, f"action_{index}", action_index)
        append_resource_action(resource_actions, action, f"action_{index}", action_index)
        action_index += 1
    for section, entries in sections.items():
        if not section.startswith("action_"):
            continue
        append_conversion(conversions, entries, section, action_index)
        append_resource_action(resource_actions, entries, section, action_index)
        action_index += 1
    result: dict[str, object] = {}
    if built_from:
        result["built_from"] = built_from
    if can_build:
        result["can_build"] = can_build
    if conversions:
        result["conversions"] = conversions
    if resource_actions:
        result["resource_actions"] = resource_actions
    return result


def append_conversion(conversions: list[dict[str, object]], action: dict[str, str], section: str, index: int) -> None:
    target = action.get("convertto", "").strip()
    if target.casefold() in SKIPPED_TARGETS:
        return
    custom_id = action.get("id", "").strip()
    conversions.append({
        "action_id": section.removeprefix("action_"),
        "network_id": "c" + custom_id if custom_id else target + "_" + str(index),
        "target": target,
        "cost": number(action.get("price", "")),
        "rate": build_rate(action.get("buildspeed", "")),
        "visible": action.get("isvisible", "true").casefold() != "false",
        "text": action.get("text", ""),
    })


def append_resource_action(resource_actions: list[dict[str, object]], action: dict[str, str], section: str, index: int) -> None:
    if "convertto" in action or action.get("displaytype", "").casefold().startswith("infoonly"):
        return
    resource_match = re.fullmatch(r"\s*([A-Za-z_][A-Za-z_0-9]*)\s*=\s*([0-9.]+)\s*", action.get("addresources", ""))
    cost = number(action.get("price", ""))
    if resource_match is None or cost <= 0.0:
        return
    resource_name = resource_match.group(1)
    if resource_name.casefold() in {"credits", "hp", "setflag"}:
        return
    stockpile_match = re.search(r"ammoIncludingQueued\(lessThan\s*=\s*(\d+)\)", action.get("isactive", ""), re.IGNORECASE)
    custom_id = action.get("id", "").strip()
    resource_actions.append({
        "action_id": section.removeprefix("action_"),
        "network_id": "c" + custom_id if custom_id else "_" + str(index),
        "resource": resource_name,
        "amount": number(resource_match.group(2)),
        "cost": cost,
        "rate": build_rate(action.get("buildspeed", "")),
        "max_stockpile": int(stockpile_match.group(1)) if stockpile_match else 0,
        "text": action.get("text", ""),
        "visible": action.get("isvisible", "true").casefold() != "false",
    })


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rwx_root", type=Path)
    arguments = parser.parse_args()
    units = read_builtin_units(arguments.rwx_root, read_native_types(arguments.rwx_root))
    specs = {
        name: create_spec(arguments.rwx_root / str(unit["source"]))
        for name, unit in units.items()
    }
    lines = [
        "extends RefCounted",
        "class_name RwBuiltinActionSpecs",
        "## 保存 RWX 内置单位的生产来源、建造动作及形态切换动作",
        "",
        "# Generated by tools/generate_rw_builtin_action_specs.py",
        "const SPECS: Dictionary = {",
    ]
    for name in sorted(specs, key=str.casefold):
        if specs[name]:
            lines.append(f"\t{gd(name)}: {gd(specs[name], 1)},")
    lines.extend(["}", ""])
    OUTPUT_PATH.write_bytes("\n".join(lines).encode("utf-8"))
    print(f"Generated action specs for {len(specs)} bundled units")


if __name__ == "__main__":
    main()
