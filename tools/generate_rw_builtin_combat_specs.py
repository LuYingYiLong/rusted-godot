"""Generate supported stock weapon and projectile settings from RWX INI files."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from generate_rw_builtin_unit_specs import effective_sections, gd, inherited_part, number
from generate_rw_vanilla_unit_catalog import read_builtin_units, read_native_types


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = PROJECT_ROOT / "scripts/utils/units/rw_builtin_combat_specs.gd"


def positive_number(value: str, default: float) -> float:
    parsed = number(value)
    return parsed if parsed > 0.0 else default


def bool_value(value: str, default: bool = False) -> bool:
    return value.strip().casefold() != "false" if value.strip() else default


def section_values(sections: dict[str, dict[str, str]], section: str, prefix: str) -> dict[str, str]:
    values = inherited_part(sections, section, prefix)
    reference = values.get("@copyfromsection", "").strip().casefold()
    if reference:
        parent = reference if reference.startswith(prefix) else prefix + reference
        if parent in sections:
            values = {**inherited_part(sections, parent, prefix), **values}
    return values


def spec_for(path: Path) -> list[dict[str, object]]:
    sections = effective_sections(path)
    attack = sections.get("attack", {})
    if not bool_value(attack.get("canattack", "")):
        return []
    attack_range = number(attack.get("maxattackrange", ""))
    if attack_range <= 0.0:
        return []
    result: list[dict[str, object]] = []
    for turret_name in sections:
        if not turret_name.startswith("turret_"):
            continue
        turret = section_values(sections, turret_name, "turret_")
        if not bool_value(turret.get("canshoot", ""), True):
            continue
        projectile_name = turret.get("projectile", "1").strip()
        projectile_section = projectile_name.casefold()
        if not projectile_section.startswith("projectile_"):
            projectile_section = "projectile_" + projectile_section
        if projectile_section not in sections:
            continue
        projectile = section_values(sections, projectile_section, "projectile_")
        direct_damage = number(projectile.get("directdamage", ""))
        splash_damage = number(projectile.get("areadamage", ""))
        if direct_damage <= 0.0 and splash_damage <= 0.0:
            continue
        range_value = positive_number(turret.get("limitingrange", ""), attack_range)
        reload_value = positive_number(turret.get("delay", ""), positive_number(attack.get("shootdelay", ""), 60.0))
        instant = bool_value(projectile.get("instant", "")) or bool_value(attack.get("ismelee", ""))
        projectile_speed = number(projectile.get("speed", "5"))
        target_speed = number(projectile.get("targetspeed", ""), projectile_speed)
        speed_acceleration = number(projectile.get("targetspeedacceleration", ""), 0.1)
        if projectile_speed <= 0.0:
            instant = True
        friendly_fire_value = projectile.get("friendlyfire", "").strip().casefold()
        friendly_fire_mode = "only-ignore-enemy" if friendly_fire_value == "only-ignoreenemy" else friendly_fire_value
        weapon: dict[str, object] = {
            "turret": turret_name.removeprefix("turret_"),
            "projectile": projectile_name,
            "range": range_value,
            "minimum_range": number(turret.get("limitingminrange", "")),
            "reload": max(1, math.ceil(reload_value)),
            "warmup": max(0, math.ceil(number(turret.get("warmup", "")))),
            "turn_speed": number(turret.get("turnspeed", ""), number(attack.get("turretturnspeed", ""), 8.0)),
            "muzzle_x": number(turret.get("x", "")),
            "muzzle_y": number(turret.get("y", "")),
            "muzzle_distance": number(turret.get("muzzledistance", ""), number(attack.get("muzzledistance", ""))),
            "ground": bool_value(turret.get("canattacklandunits", ""), bool_value(attack.get("canattacklandunits", ""))),
            "air": bool_value(turret.get("canattackflyingunits", ""), bool_value(attack.get("canattackflyingunits", ""))),
            "underwater": bool_value(turret.get("canattackunderwaterunits", ""), bool_value(attack.get("canattackunderwaterunits", ""))),
            "direct_damage": direct_damage,
            "splash_damage": splash_damage,
            "splash_radius": number(projectile.get("arearadius", "")),
            "area_no_falloff": bool_value(projectile.get("areadamagenofalloff", "")),
            "area_from_edge": bool_value(projectile.get("arearadiusfromedge", "")),
            "area_minimum_distance": number(projectile.get("areaignoreunitscloserthan", "")),
            "area_hit_air_and_land_at_same_time": bool_value(projectile.get("areahitairandlandatsametime", "")),
            "area_hit_underwater_always": bool_value(projectile.get("areahitunderwateralways", "")),
            "speed": projectile_speed,
            "target_speed": target_speed,
            "speed_acceleration": speed_acceleration if target_speed > 0.0 else 0.0,
            "projectile_turn_speed": number(projectile.get("turnspeed", ""), -1.0),
            "lifetime": max(1, math.ceil(positive_number(projectile.get("life", ""), 60.0))),
            "instant": instant,
            "beam": bool_value(projectile.get("lasereffect", "")) or bool_value(projectile.get("lightingeffect", "")) or bool(projectile.get("beamimage", "").strip()),
            "target_ground": bool_value(projectile.get("targetground", "")),
            "target_ground_include_target_height": bool_value(projectile.get("targetground_includetargetheight", "")),
            "target_ground_spread": number(projectile.get("targetgroundspread", "")),
            "target_ground_height_offset": number(projectile.get("targetgroundheightoffset", "")),
            "friendly_fire": friendly_fire_value == "true",
            "friendly_fire_mode": friendly_fire_mode,
            "frame": int(number(projectile.get("frame", ""), -1.0)),
            "draw_size": positive_number(projectile.get("drawsize", ""), 1.0),
            "texture_scale": positive_number(projectile.get("drawsize", ""), 1.0) * 2.0,
            "color": projectile.get("color", ""),
            "ballistic": bool_value(projectile.get("ballistic", "")),
            "ballistic_height": number(projectile.get("ballistic_height", "")),
            "ballistic_delay_move_height": max(0.0, number(projectile.get("ballistic_delaymove_height", ""))),
            "initial_unguided_speed_x": number(projectile.get("initialunguidedspeedx", "")),
            "initial_unguided_speed_y": number(projectile.get("initialunguidedspeedy", "")),
            "initial_unguided_speed_height": number(projectile.get("initialunguidedspeedheight", "")),
            "speed_spread": number(projectile.get("speedspread", "")),
            "gravity": number(projectile.get("gravity", "")),
            "true_gravity": number(projectile.get("truegravity", "")),
            "wobble_amplitude": number(projectile.get("wobbleamplitude", "")),
            "wobble_frequency": positive_number(projectile.get("wobblefrequency", ""), 5.0),
            "trail_effect": bool_value(projectile.get("traileffect", "")),
            "trail_effect_rate": positive_number(projectile.get("traileffectrate", ""), 3.0),
            "auto_target_dead": bool_value(projectile.get("autotargetingondeadtarget", "")),
            "auto_target_range": positive_number(projectile.get("autotargetingondeadtargetrange", ""), 120.0),
            "auto_target_lead": positive_number(projectile.get("autotargetingondeadtargetlead", ""), 15.0),
            "retarget_in_flight": bool_value(projectile.get("retargetinginflight", "")),
            "retarget_search_delay": positive_number(projectile.get("retargetinginflightsearchdelay", ""), 5.0),
            "retarget_search_range": positive_number(projectile.get("retargetinginflightsearchrange", ""), 120.0),
            "retarget_search_lead": positive_number(projectile.get("retargetinginflightsearchlead", ""), 15.0),
            "explode_on_end_of_life": bool_value(projectile.get("explodeonendoflife", "")),
            "building_damage_multiplier": number(projectile.get("buildingdamagemultiplier", ""), 1.0),
            "air_damage_multiplier": number(projectile.get("damagetoair", ""), 1.0),
            "shield_damage_multiplier": number(projectile.get("shielddamagemultiplier", ""), 1.0),
            "shield_deflection_multiplier": number(projectile.get("shielddefectionmultiplier", ""), 1.0),
            "hull_damage_multiplier": number(projectile.get("hulldamagemultiplier", ""), 1.0),
            "armor_ignore": number(projectile.get("armourignoreamount", projectile.get("armorignoreamount", projectile.get("armourignore", projectile.get("armorignore", ""))))),
            "push_force": number(projectile.get("pushforce", "")),
            "push_velocity": number(projectile.get("pushvelocity", "")),
        }
        result.append(weapon)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rwx_root", type=Path)
    arguments = parser.parse_args()
    units = read_builtin_units(arguments.rwx_root, read_native_types(arguments.rwx_root))
    specs = {
        name: spec_for(arguments.rwx_root / str(info["source"]))
        for name, info in units.items()
    }
    lines = [
        "extends RefCounted",
        "class_name RwBuiltinCombatSpecs",
        "## 保存 RWX 内置单位的炮塔和弹体数值",
        "",
        "# Generated by tools/generate_rw_builtin_combat_specs.py",
        "const SPECS: Dictionary = {",
    ]
    for name in sorted(specs, key=str.casefold):
        if specs[name]:
            lines.append(f"\t{gd(name)}: {gd(specs[name], 1)},")
    lines.extend(["}", ""])
    OUTPUT_PATH.write_bytes("\n".join(lines).encode("utf-8"))
    print(f"Generated combat specs for {sum(bool(value) for value in specs.values())} bundled units")


if __name__ == "__main__":
    main()
