"""Generate baseline visual and movement specs for RWX bundled INI units."""

from __future__ import annotations

import argparse
import json
import re
from functools import lru_cache
from pathlib import Path

from generate_rw_vanilla_unit_catalog import read_builtin_units, read_native_types


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = PROJECT_ROOT / "scripts/utils/units/rw_builtin_unit_specs.gd"
ENTRY_PATTERN = re.compile(r"^\s*([^:=]+?)\s*[:=]\s*(.*?)\s*$")
NUMBER_PATTERN = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$")
IMAGE_ROOT: Path


@lru_cache(maxsize=None)
def read_sections(path: Path) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    section = ""
    for raw_line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].casefold()
            sections.setdefault(section, {})
            continue
        if not line or line.startswith(("#", ";")):
            continue
        match = ENTRY_PATTERN.match(line)
        if match is not None:
            sections.setdefault(section, {})[match.group(1).strip().casefold()] = match.group(2).strip()
    return sections


@lru_cache(maxsize=None)
def effective_sections(path: Path) -> dict[str, dict[str, str]]:
    own = read_sections(path)
    copy_from = own.get("core", {}).get("copyfrom", "")
    merged: dict[str, dict[str, str]] = {}
    for source in copy_from.split(","):
        source = source.strip()
        if source:
            parent = path.parent / source
            if not parent.is_file():
                raise FileNotFoundError(f"Missing copyFrom: {path} -> {source}")
            for section, entries in effective_sections(parent).items():
                merged.setdefault(section, {}).update(entries)
    for section, entries in own.items():
        if section.startswith("comment_"):
            continue
        if entries.get("@copyfrom_skipthissection", "").casefold() == "true":
            merged.pop(section, None)
        merged.setdefault(section, {}).update(entries)
    return merged


def number(value: str, default: float = 0.0) -> float:
    return float(value) if NUMBER_PATTERN.fullmatch(value) else default


def integer(value: str, default: int = 0) -> int:
    return int(value) if re.fullmatch(r"[+-]?\d+", value) else default


def build_rate(value: str) -> float:
    if value.strip().casefold().endswith("s"):
        seconds = number(value.strip()[:-1])
        return 1.0 / (seconds * 60.0) if seconds > 0.0 else 0.0
    return number(value)


def image_key(ini_path: Path, source: str) -> tuple[str, bool]:
    source = source.strip()
    if source.upper() in {"", "NONE", "AUTO"}:
        return "", False
    silhouette = False
    if source.upper().startswith("SHADOW:"):
        source = source[7:]
        silhouette = True
    if source.upper().startswith("SHARED:"):
        image_path = IMAGE_ROOT / "shared" / source[7:]
    elif source.upper().startswith("CORE:"):
        image_path = IMAGE_ROOT / source[5:]
    elif source.upper().startswith("ROOT:"):
        image_path = IMAGE_ROOT / source[5:]
    else:
        image_path = ini_path.parent / source
    if not image_path.is_file():
        raise FileNotFoundError(f"Missing unit image: {ini_path} -> {source}")
    return "builtin:" + image_path.relative_to(IMAGE_ROOT).as_posix(), silhouette


def footprint(value: str) -> list[int]:
    parts = [part.strip() for part in value.split(",")]
    return [int(part) for part in parts] if len(parts) == 4 and all(
        re.fullmatch(r"[+-]?\d+", part) for part in parts
    ) else []


def inherited_part(sections: dict[str, dict[str, str]], section_name: str, prefix: str, trail: tuple[str, ...] = ()) -> dict[str, str]:
    if section_name in trail:
        raise ValueError(f"Circular part inheritance: {section_name}")
    own = sections.get(section_name, {})
    parent_name = own.get("copyfrom", "").strip().casefold()
    values: dict[str, str] = {}
    if parent_name:
        parent_section = parent_name if parent_name.startswith(prefix) else prefix + parent_name
        if parent_section not in sections:
            raise ValueError(f"Missing part inheritance: {section_name} -> {parent_name}")
        values.update(inherited_part(sections, parent_section, prefix, trail + (section_name,)))
    values.update(own)
    return values


def spec_for(path: Path) -> dict[str, object]:
    sections = effective_sections(path)
    core = sections.get("core", {})
    graphics = sections.get("graphics", {})
    movement = sections.get("movement", {})
    attack = sections.get("attack", {})
    body, _ = image_key(path, graphics.get("image", ""))
    if not body:
        raise ValueError(f"Bundled unit has no body image: {path}")
    dead, _ = image_key(path, graphics.get("image_wreak", ""))
    shadow, shadow_is_silhouette = image_key(path, graphics.get("image_shadow", ""))
    back, _ = image_key(path, graphics.get("image_back", ""))
    front, _ = image_key(path, graphics.get("image_front", ""))
    turret, _ = image_key(path, graphics.get("image_turret", ""))
    radius = number(core.get("radius", ""), 10.0)
    hp = number(core.get("maxhp", ""), 1.0)
    movement_type = movement.get("movementtype", "NONE" if core.get("isbuilding", "").casefold() == "true" else "LAND").upper()
    turret_parts: list[dict[str, object]] = []
    turret_names = [name for name in sections if name.startswith("turret_")]
    ordered_turrets: list[str] = []

    def append_turret(name: str, trail: tuple[str, ...] = ()) -> None:
        if name in ordered_turrets:
            return
        if name in trail:
            raise ValueError(f"Circular turret attachment: {path} -> {name}")
        entries = inherited_part(sections, name, "turret_")
        parent_name = entries.get("attachedto", "").strip().casefold()
        if parent_name:
            parent = parent_name if parent_name.startswith("turret_") else "turret_" + parent_name
            if parent in sections:
                append_turret(parent, trail + (name,))
        ordered_turrets.append(name)

    for turret_name in turret_names:
        append_turret(turret_name)
    for name in ordered_turrets:
        entries = inherited_part(sections, name, "turret_")
        if entries.get("invisible", "").casefold() == "true":
            continue
        part_image, _ = image_key(path, entries.get("image", graphics.get("image_turret", "")))
        if not part_image:
            continue
        part: dict[str, object] = {
            "name": name.removeprefix("turret_"),
            "image": part_image,
            "x": number(entries.get("x", "")),
            "y": number(entries.get("y", "")),
        }
        attached_to = entries.get("attachedto", "").strip()
        if attached_to:
            part["parent"] = attached_to.removeprefix("turret_")
        if entries.get("image_applyteamcolors", graphics.get("teamcolorsonturret", "false")).casefold() == "true":
            part["team_colored"] = True
        if entries.get("image_drawlayeronbottom", "").casefold() == "true":
            part["draw_order"] = -1
        turret_parts.append(part)
    leg_parts: list[dict[str, object]] = []
    for name in sorted(sections):
        if not name.startswith(("leg_", "arm_")):
            continue
        prefix = name.split("_", 1)[0] + "_"
        entries = inherited_part(sections, name, prefix)
        leg_image, _ = image_key(path, entries.get("image_leg", ""))
        foot_image, _ = image_key(path, entries.get("image_foot", ""))
        foot_shadow_image, _ = image_key(path, entries.get("image_foot_shadow", ""))
        if not leg_image and not foot_image:
            continue
        leg_parts.append({
            "image_leg": leg_image,
            "image_foot": foot_image,
            "image_foot_shadow": foot_shadow_image,
            "x": number(entries.get("x", "")),
            "y": number(entries.get("y", "")),
            "attach_x": number(entries.get("attach_x", "")),
            "attach_y": number(entries.get("attach_y", "")),
            "draw_over_body": entries.get("drawunderallunits", "").casefold() == "false",
            "team_colored": entries.get("image_applyteamcolors", "").casefold() == "true",
        })
    spec: dict[str, object] = {
        "body": body,
        "health": hp,
        "radius": radius,
        "movement_type": movement_type,
    }
    credit_income_match = re.search(r"(?:^|[,;])\s*credits\s*=\s*([0-9.]+)", core.get("generation_resources", ""), re.IGNORECASE)
    optional: dict[str, object] = {
        "display_name": core.get("displaytext", ""),
        "description": core.get("displaydescription", ""),
        "dead": dead,
        "shadow": shadow,
        "shadow_silhouette": shadow_is_silhouette,
        "generated_shadow": graphics.get("image_shadow", "").upper() == "AUTO",
        "back": back,
        "front": front,
        "turret": turret if not turret_parts else "",
        "turret_parts": turret_parts,
        "leg_parts": leg_parts,
        "shadow_offset_x": number(graphics.get("shadowoffsetx", "")),
        "shadow_offset_y": number(graphics.get("shadowoffsety", "")),
        "frames": max(1, integer(graphics.get("total_frames", ""), 1)),
        "idle_animation_start": integer(graphics.get("animation_idle_start", "")),
        "idle_animation_end": integer(graphics.get("animation_idle_end", "")),
        "idle_animation_step": number(graphics.get("animation_idle_speed", "")),
        "idle_animation_ping_pong": graphics.get("animation_idle_pingpong", "").casefold() == "true",
        "moving_animation_start": integer(graphics.get("animation_moving_start", "")),
        "moving_animation_end": integer(graphics.get("animation_moving_end", "")),
        "moving_animation_step": number(graphics.get("animation_moving_speed", "")),
        "moving_animation_ping_pong": graphics.get("animation_moving_pingpong", "").casefold() == "true",
        "scale": number(graphics.get("imagescale", ""), 1.0),
        "turret_scale": number(graphics.get("turretimagescale", ""), 1.0),
        "team_colored": graphics.get("teamcolorsonbody", "true").casefold() != "false",
        "turret_team_colored": graphics.get("teamcolorsonturret", "false").casefold() == "true",
        "shield": number(core.get("maxshield", "")),
        "mass": number(core.get("mass", ""), 3000.0),
        "sight": integer(core.get("fogofwarsightrange", ""), 15),
        "speed": number(movement.get("movespeed", "")),
        "turn_speed": number(movement.get("maxturnspeed", "")),
        "turn_accel": number(movement.get("turnacceleration", "")),
        "move_accel": number(movement.get("moveaccelerationspeed", "")),
        "move_decel": number(movement.get("movedecelerationspeed", "")),
        "attack_range": number(attack.get("maxattackrange", "")),
        "building": core.get("isbuilding", "").casefold() == "true",
        "footprint": footprint(core.get("footprint", "")),
        "water_placement": core.get("isbuilding", "").casefold() == "true" and movement_type == "WATER",
        "resource_pool": core.get("placeonlyonrespool", "").casefold() == "true",
        "builder": core.get("isbuilder", "").casefold() == "true",
        "reclaim": core.get("canreclaimresources", "").casefold() == "true",
        "price": number(core.get("price", "")),
        "build_rate": build_rate(core.get("buildspeed", "")),
        "credit_income": number(credit_income_match.group(1)) if credit_income_match else 0.0,
        "tech_level": integer(core.get("techlevel", ""), 1),
        "hide_on_death": not dead,
    }
    defaults: dict[str, object] = {
        "frames": 1, "scale": 1.0, "turret_scale": 1.0,
        "team_colored": True, "mass": 3000.0, "sight": 15,
        "tech_level": 1,
    }
    spec.update({key: value for key, value in optional.items() if value != defaults.get(key, None) and value not in ("", [], False, 0, 0.0)})
    if spec.get("building") and spec.get("footprint"):
        spec["blocks_movement"] = True
    return spec


def gd(value: object, indent: int = 0) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        if not value:
            return "[]"
        items = "\n".join(f"{'\t' * (indent + 1)}{gd(item, indent + 1)}," for item in value)
        return f"[\n{items}\n{'\t' * indent}]"
    if isinstance(value, dict):
        if not value:
            return "{}"
        items = "\n".join(f"{'\t' * (indent + 1)}{gd(key)}: {gd(item, indent + 1)}," for key, item in value.items())
        return f"{{\n{items}\n{'\t' * indent}}}"
    raise TypeError(value)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rwx_root", type=Path)
    args = parser.parse_args()
    global IMAGE_ROOT
    IMAGE_ROOT = args.rwx_root / "assets/units"
    native_types = read_native_types(args.rwx_root)
    units = read_builtin_units(args.rwx_root, native_types)
    specs = {
        name: spec_for(args.rwx_root / str(unit["source"]))
        for name, unit in units.items()
    }
    imported = (
        PROJECT_ROOT / "scripts/utils/rw_builtin_unit_image_catalog.gd"
    ).read_text(encoding="utf-8")
    for name, spec in specs.items():
        for key in ("body", "dead", "shadow", "back", "front", "turret"):
            image = spec.get(key, "")
            if image and json.dumps(str(image)[8:]) not in imported:
                raise ValueError(f"Missing imported image for {name}: {image}")
    lines = [
        "extends RefCounted",
        "class_name RwBuiltinUnitSpecs",
        "## 保存 RWX 游戏自带 INI 单位的基础外观和移动数据",
        "",
        "# Generated by tools/generate_rw_builtin_unit_specs.py",
        "const SPECS: Dictionary = {",
    ]
    for name in sorted(specs, key=str.casefold):
        lines.append(f"\t{gd(name)}: {gd(specs[name], 1)},")
    lines.extend([
        "}",
        "",
        "",
        "## 返回内置单位的数据副本",
        "static func get_spec(unit_name: String) -> Dictionary:",
        "\tvar spec: Dictionary = SPECS.get(unit_name, {})",
        "\treturn spec.duplicate(true)",
        "",
    ])
    with OUTPUT_PATH.open("w", encoding="utf-8", newline="\n") as output:
        output.write("\n".join(lines))
    print(f"Generated {len(specs)} bundled unit visual specs")


if __name__ == "__main__":
    main()
