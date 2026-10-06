"""Generate supported stock weapon and projectile settings from RWX INI files."""

from __future__ import annotations

import argparse
import math
import re
from pathlib import Path

from generate_rw_builtin_unit_specs import effective_sections, gd, inherited_part, number
from generate_rw_vanilla_unit_catalog import read_builtin_units, read_native_types


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = PROJECT_ROOT / "scripts/utils/units/rw_builtin_combat_specs.gd"
RWX_UNIT_ASSET_ROOT: Path | None = None
RWX_DRAWABLE_EFFECT_ROOT: Path | None = None


def positive_number(value: str, default: float) -> float:
    parsed = number(value)
    return parsed if parsed > 0.0 else default


def time_number(value: str, default: float = 0.0) -> float:
    normalized = value.strip()
    if normalized.casefold().endswith("s"):
        return number(normalized[:-1]) * 60.0
    return number(normalized, default)


def positive_time_number(value: str, default: float) -> float:
    parsed = time_number(value)
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


def projectile_image_key(unit_path: Path, source: str) -> str:
    normalized: str = source.strip()
    if not normalized or normalized.upper() in {"NONE", "AUTO"} or RWX_UNIT_ASSET_ROOT is None:
        return ""
    if normalized.upper().startswith("SHARED:"):
        image_path: Path = RWX_UNIT_ASSET_ROOT / "shared" / normalized[7:]
    elif normalized.upper().startswith(("CORE:", "ROOT:")):
        image_path = RWX_UNIT_ASSET_ROOT / normalized[5:]
    else:
        image_path = unit_path.parent / normalized
    if not image_path.is_file():
        raise FileNotFoundError(f"Missing projectile image: {unit_path} -> {normalized}")
    return "builtin:" + image_path.relative_to(RWX_UNIT_ASSET_ROOT).as_posix()


def effect_image_key(unit_path: Path, source: str, strip_index: str) -> str:
    image_key: str = projectile_image_key(unit_path, source)
    if image_key:
        return image_key
    normalized_strip: str = strip_index.strip().casefold()
    if not normalized_strip or RWX_DRAWABLE_EFFECT_ROOT is None:
        return ""
    if normalized_strip == "0":
        normalized_strip = "effects"
    image_path: Path = RWX_DRAWABLE_EFFECT_ROOT / f"{normalized_strip}.png"
    if not image_path.is_file():
        return ""
    return image_path.name


def effect_profiles_for(path: Path) -> dict[str, dict[str, object]]:
    sections = effective_sections(path)
    profiles: dict[str, dict[str, object]] = {}
    strip_frame_sizes: dict[str, tuple[int, int]] = {
        "effects": (17, 18),
        "effects2": (33, 32),
        "effects3": (31, 35),
        "projectiles": (20, 20),
        "projectiles2": (20, 20),
        "projectiles_large": (60, 60),
    }
    for section, values in sections.items():
        if not section.startswith("effect_"):
            continue
        strip_index: str = values.get("stripindex", "0").strip()
        default_frame_size: tuple[int, int] = strip_frame_sizes.get(strip_index.casefold(), (0, 0))
        profile: dict[str, object] = {
            "texture_name": effect_image_key(path, values.get("image", ""), strip_index),
            "frame_index": int(number(values.get("frameindex", ""))),
            "frame_index_random": int(number(values.get("frameindexrandom", ""))),
            "total_frames": max(1, int(number(values.get("total_frames", ""), 1.0))),
            "frame_width": int(number(values.get("frame_width", ""), float(default_frame_size[0]))),
            "frame_height": int(number(values.get("frame_height", ""), float(default_frame_size[1]))),
            "life": max(1.0, time_number(values.get("life", ""), 20.0)),
            "scale_from": number(values.get("scalefrom", ""), 1.0),
            "scale_to": number(values.get("scaleto", ""), number(values.get("scalefrom", ""), 1.0)),
            "alpha": number(values.get("alpha", ""), 1.0),
            "color": values.get("color", ""),
            "team_color_ratio": number(values.get("teamcolorratio", "")),
            "fade_in_time": max(0.0, time_number(values.get("fadeintime", ""))),
            "fade_out": bool_value(values.get("fadeout", ""), True),
            "attached_to_unit": bool_value(values.get("attachedtounit", ""), True),
            "live_after_attached_dies": bool_value(values.get("liveafterattacheddies", ""), True),
            "draw_under_units": bool_value(values.get("drawunderunits", "")),
            "x_offset_absolute": number(values.get("xoffsetabsolute", "")),
            "y_offset_absolute": number(values.get("yoffsetabsolute", "")),
            "x_offset_relative": number(values.get("xoffsetrelative", "")),
            "y_offset_relative": number(values.get("yoffsetrelative", "")),
            "x_speed_absolute": number(values.get("xspeedabsolute", "")),
            "y_speed_absolute": number(values.get("yspeedabsolute", "")),
            "x_speed_relative": number(values.get("xspeedrelative", "")),
            "y_speed_relative": number(values.get("yspeedrelative", "")),
            "h_speed": number(values.get("hspeed", "")),
            "dir_offset": number(values.get("diroffset", "")),
            "dir_offset_random": number(values.get("diroffsetrandom", "")),
            "physics": bool_value(values.get("physics", "")),
            "physics_gravity": number(values.get("physicsgravity", ""), 1.0),
            "animate_frame_start": int(number(values.get("animateframestart", ""))),
            "animate_frame_end": int(number(values.get("animateframeend", ""))),
            "animate_frame_speed": number(values.get("animateframespeed", ""), 0.5),
            "animate_frame_looping": bool_value(values.get("animateframelooping", "")),
            "animate_frame_ping_pong": bool_value(values.get("animateframepingpong", "")),
            "also_emit_effects": values.get("alsoemiteffects", ""),
            "also_emit_effects_on_death": values.get("alsoemiteffectsondeath", ""),
        }
        profiles[section.removeprefix("effect_").casefold()] = profile
    return profiles


def split_spawn_list(value: str) -> list[str]:
    entries: list[str] = []
    depth = 0
    start = 0
    for index, character in enumerate(value):
        if character == "(":
            depth += 1
        elif character == ")":
            depth = max(depth - 1, 0)
        elif character == "," and depth == 0:
            entries.append(value[start:index].strip())
            start = index + 1
    entries.append(value[start:].strip())
    return [entry for entry in entries if entry]


def parse_options(raw_options: str) -> dict[str, str]:
    options: dict[str, str] = {}
    for option in raw_options.split(","):
        if "=" in option:
            key, option_value = option.split("=", 1)
            options[key.strip().casefold()] = option_value.strip()
    return options


def projectile_spawn_specs(
    raw_spawn_list: str,
    sections: dict[str, dict[str, str]],
    unit_path: Path,
    trail: tuple[str, ...],
    depth: int,
) -> list[dict[str, object]]:
    spawn_specs: list[dict[str, object]] = []
    if depth >= 8 or not raw_spawn_list or raw_spawn_list.casefold() == "none":
        return spawn_specs
    for entry in split_spawn_list(raw_spawn_list):
        entry_match = re.fullmatch(r"([^*(]+?)(?:\*(\d+))?(?:\((.*)\))?", entry)
        if entry_match is None:
            continue
        child_name = entry_match.group(1).strip()
        options: dict[str, str] = parse_options(entry_match.group(3) or "")
        child_profile = projectile_profile(child_name, sections, unit_path, trail, depth + 1)
        if not child_profile:
            continue
        random_offset: float = number(options.get("offsetrandomxy", ""))
        spawn_specs.append({
            "projectile_name": child_name,
            "count": max(int(entry_match.group(2) or "1"), 1),
            "spawn_chance": number(options.get("spawnchance", ""), 1.0),
            "max_spawn_limit": int(number(options.get("maxspawnlimit", ""), 2147483647.0)),
            "offset_dir": number(options.get("offsetdir", "")),
            "offset_random_dir": number(options.get("offsetrandomdir", "")),
            "offset_x": number(options.get("offsetx", options.get("xoffsetabsolute", ""))),
            "offset_y": number(options.get("offsety", options.get("yoffsetabsolute", ""))),
            "offset_x_relative": number(options.get("xoffsetrelative", "")),
            "offset_y_relative": number(options.get("yoffsetrelative", "")),
            "offset_random_x": number(options.get("offsetrandomx", ""), random_offset),
            "offset_random_y": number(options.get("offsetrandomy", ""), random_offset),
            "offset_height": number(options.get("offsetheight", "")),
            "recursion_limit": int(number(options.get("recursionlimit", ""), 3.0)),
            "profile": child_profile,
        })
    return spawn_specs


def unit_spawn_specs(raw_spawn_list: str) -> list[dict[str, object]]:
    spawn_specs: list[dict[str, object]] = []
    if not raw_spawn_list or raw_spawn_list.casefold() == "none":
        return spawn_specs
    for entry in split_spawn_list(raw_spawn_list):
        entry_match = re.fullmatch(r"([^*(]+?)(?:\*(\d+))?(?:\((.*)\))?", entry)
        if entry_match is None:
            continue
        options: dict[str, str] = parse_options(entry_match.group(3) or "")
        random_offset: float = number(options.get("offsetrandomxy", ""))
        spawn_specs.append({
            "unit_name": entry_match.group(1).strip(),
            "count": max(int(entry_match.group(2) or "1"), 1),
            "spawn_chance": number(options.get("spawnchance", ""), 1.0),
            "max_spawn_limit": int(number(options.get("maxspawnlimit", ""), 2147483647.0)),
            "neutral_team": bool_value(options.get("neutralteam", "")),
            "aggressive_team": bool_value(options.get("aggressiveteam", "")),
            "set_to_team_of_last_attacker": bool_value(options.get("settoteamoflastattacker", "")),
            "tech_level": int(number(options.get("techlevel", ""), -1.0)),
            "grid_align": bool_value(options.get("gridalign", "")),
            "skip_if_overlapping": bool_value(options.get("skipifoverlapping", "")),
            "falling": bool_value(options.get("falling", "")),
            "always_start_dir_at_zero": bool_value(options.get("alwaysstartdiratzero", options.get("alwaystartdiratzero", ""))),
            "offset_x": number(options.get("offsetx", "")),
            "offset_y": number(options.get("offsety", "")),
            "offset_random_x": number(options.get("offsetrandomx", ""), random_offset),
            "offset_random_y": number(options.get("offsetrandomy", ""), random_offset),
            "offset_random_dir": number(options.get("offsetrandomdir", "")),
            "offset_dir": number(options.get("offsetdir", "")),
            "offset_height": number(options.get("offsetheight", "")),
        })
    return spawn_specs


def projectile_profile(
    projectile_name: str,
    sections: dict[str, dict[str, str]],
    unit_path: Path,
    trail: tuple[str, ...] = (),
    depth: int = 0,
) -> dict[str, object]:
    projectile_section = projectile_name.casefold()
    if not projectile_section.startswith("projectile_"):
        projectile_section = "projectile_" + projectile_section
    if projectile_section not in sections or projectile_section in trail:
        return {}
    projectile = section_values(sections, projectile_section, "projectile_")
    ballistic = bool_value(projectile.get("ballistic", ""))
    direct_damage = number(projectile.get("directdamage", ""))
    splash_damage = number(projectile.get("areadamage", ""))
    projectile_speed = number(projectile.get("speed", "5"), 5.0)
    target_speed = number(projectile.get("targetspeed", ""), projectile_speed)
    trail_effect_value: str = projectile.get("traileffect", "").strip()
    friendly_fire_value = projectile.get("friendlyfire", "").strip().casefold()
    spawn_on_end_of_life = projectile_spawn_specs(
        projectile.get("spawnprojectilesonendoflife", "").strip(),
        sections,
        unit_path,
        trail + (projectile_section,),
        depth,
    )
    spawn_on_explode = projectile_spawn_specs(
        projectile.get("spawnprojectilesonexplode", "").strip(),
        sections,
        unit_path,
        trail + (projectile_section,),
        depth,
    )
    spawn_on_create = projectile_spawn_specs(
        projectile.get("spawnprojectilesoncreate", "").strip(),
        sections,
        unit_path,
        trail + (projectile_section,),
        depth,
    )
    return {
        "projectile": projectile_name,
        "direct_damage": direct_damage,
        "image": projectile_image_key(unit_path, projectile.get("image", "")),
        "shadow_image": projectile_image_key(unit_path, projectile.get("shadowimage", "")),
        "beam_image": projectile_image_key(unit_path, projectile.get("beamimage", "")),
        "beam_image_start": projectile_image_key(unit_path, projectile.get("beamimagestart", "")),
        "beam_image_end": projectile_image_key(unit_path, projectile.get("beamimageend", "")),
        "beam_image_offset_rate": number(projectile.get("beamimageoffsetrate", "")),
        "beam_image_start_rotated": bool_value(projectile.get("beamimagestartrotated", "")),
        "beam_image_end_rotated": bool_value(projectile.get("beamimageendrotated", "")),
        "team_color_ratio": number(projectile.get("teamcolorratio", "")),
        "team_color_source_ratio": number(
            projectile.get("teamcolorratio_sourceratio", ""),
            1.0 - number(projectile.get("teamcolorratio", "")),
        ),
        "draw_type": int(number(projectile.get("drawtype", ""))),
        "shadow_frame": int(number(projectile.get("shadowframe", ""), -1.0)),
        "invisible": bool_value(projectile.get("invisible", "")),
        "draw_under_units": bool_value(projectile.get("drawunderunits", "")),
        "large_hit_effect": bool_value(projectile.get("largehiteffect", "")),
        "nuke_weapon": bool_value(projectile.get("nukeweapon", "")),
        "always_visible_in_fog": bool_value(projectile.get("alwaysvisibleinfog", "")),
        "should_reveal_fog": bool_value(projectile.get("shouldrevealfog", "")),
        "hit_sound": bool_value(projectile.get("hitsound", ""), True),
        "flame_weapon": bool_value(projectile.get("flameweapon", "")),
        "explode_effect": projectile.get("explodeeffect", ""),
        "explode_effect_on_shield": projectile.get("explodeeffectonshield", ""),
        "effect_on_create": projectile.get("effectoncreate", ""),
        "teleport_source": bool_value(projectile.get("teleportsource", "")),
        "convert_hit_to_source_team": bool_value(projectile.get("converthittosourceteam", "")),
        "tags": [tag.strip() for tag in projectile.get("tags", "").split(",") if tag.strip()],
        "intercept_projectile_remove_target_life_only": bool_value(projectile.get("interceptprojectile_removetargetlifeonly", "")),
        "splash_damage": splash_damage,
        "deflection_power": number(projectile.get("deflectionpower", ""), 1.0),
        "splash_radius": number(projectile.get("arearadius", "")),
        "area_expand_time": number(projectile.get("areaexpandtime", "")),
        "area_no_falloff": bool_value(projectile.get("areadamagenofalloff", "")),
        "area_from_edge": bool_value(projectile.get("arearadiusfromedge", "")),
        "area_minimum_distance": number(projectile.get("areaignoreunitscloserthan", "")),
        "area_hit_air_and_land_at_same_time": bool_value(projectile.get("areahitairandlandatsametime", "")),
        "area_hit_underwater_always": bool_value(projectile.get("areahitunderwateralways", "")),
        "speed": projectile_speed,
        "target_speed": target_speed,
        "speed_acceleration": number(projectile.get("targetspeedacceleration", ""), 0.1) if target_speed > 0.0 else 0.0,
        "projectile_turn_speed": number(projectile.get("turnspeed", ""), -1.0),
        "projectile_turn_speed_near": number(projectile.get("turnspeedwhennear", ""), -1.0),
        "lifetime": max(0, math.ceil(time_number(projectile.get("life", ""), 60.0))),
        "delayed_start": max(0.0, time_number(projectile.get("delayedstarttimer", ""))),
        "instant": bool_value(projectile.get("instant", "")),
        "instant_reuse_last": bool_value(projectile.get("instantreuselast", "")),
        "instant_reuse_last_also_change_turret_aim": bool_value(projectile.get("instantreuselast_alsochangeturretaim", "")),
        "instant_reuse_last_keep_area_damage_list": bool_value(projectile.get("instantreuselast_keepareadamagelist", "")),
        "move_with_parent": bool_value(projectile.get("movewithparent", "")),
        "beam": bool_value(projectile.get("lasereffect", "")) or bool_value(projectile.get("lightingeffect", "")) or bool(projectile.get("beamimage", "").strip()),
        "target_ground": bool_value(projectile.get("targetground", "")),
        "target_ground_include_target_height": bool_value(projectile.get("targetground_includetargetheight", "")),
        "target_ground_spread": number(projectile.get("targetgroundspread", "")),
        "target_ground_height_offset": number(projectile.get("targetgroundheightoffset", "")),
        "lead_target": not bool_value(projectile.get("disableleadtargeting", "")),
        "lead_target_speed_calculation": number(projectile.get("leadtargetingspeedcalculation", ""), -1.0),
        "sweep_speed": number(projectile.get("sweepspeed", "")),
        "sweep_offset": number(projectile.get("sweepoffset", "")),
        "sweep_offset_from_target_radius": number(projectile.get("sweepoffsetfromtargetradius", "")),
        "friendly_fire": friendly_fire_value == "true",
        "friendly_fire_mode": "only-ignore-enemy" if friendly_fire_value == "only-ignoreenemy" else friendly_fire_value,
        "frame": int(number(projectile.get("frame", ""), -1.0)),
        "draw_size": positive_number(projectile.get("drawsize", ""), 1.0),
        "texture_scale": positive_number(projectile.get("drawsize", ""), 1.0) * 2.0,
        "color": projectile.get("color", ""),
        "light_color": projectile.get("lightcolor", ""),
        "light_size": number(projectile.get("lightsize", "")),
        "light_cast_on_ground": bool_value(projectile.get("lightcastonground", "")),
        "ballistic": ballistic,
        "ballistic_height": number(projectile.get("ballistic_height", ""), 60.0 if ballistic else 0.0),
        "ballistic_delay_move_height": number(projectile.get("ballistic_delaymove_height", ""), 40.0 if ballistic else 0.0),
        "initial_unguided_speed_x": number(projectile.get("initialunguidedspeedx", "")),
        "initial_unguided_speed_y": number(projectile.get("initialunguidedspeedy", "")),
        "initial_unguided_speed_height": number(projectile.get("initialunguidedspeedheight", "")),
        "speed_spread": number(projectile.get("speedspread", "")),
        "gravity": number(projectile.get("gravity", "")),
        "true_gravity": number(projectile.get("truegravity", "")),
        "wobble_amplitude": number(projectile.get("wobbleamplitude", "")),
        "wobble_frequency": positive_time_number(projectile.get("wobblefrequency", ""), 5.0),
        "trail_effect": trail_effect_value.casefold() not in {"", "false", "none"},
        "trail_effect_name": (
            trail_effect_value
            if trail_effect_value.casefold() not in {"", "true", "false", "none"}
            else ""
        ),
        "trail_effect_rate": positive_number(projectile.get("traileffectrate", ""), 3.0),
        "auto_target_dead": bool_value(projectile.get("autotargetingondeadtarget", "")),
        "auto_target_range": positive_number(projectile.get("autotargetingondeadtargetrange", ""), 120.0),
        "auto_target_lead": positive_number(projectile.get("autotargetingondeadtargetlead", ""), 15.0),
        "retarget_in_flight": bool_value(projectile.get("retargetinginflight", "")),
        "retarget_search_delay": positive_number(projectile.get("retargetinginflightsearchdelay", ""), 5.0),
        "retarget_search_range": positive_number(projectile.get("retargetinginflightsearchrange", ""), 120.0),
        "retarget_search_lead": positive_number(projectile.get("retargetinginflightsearchlead", ""), 15.0),
        "explode_on_end_of_life": bool_value(projectile.get("explodeonendoflife", "")),
        "ignore_parent_shoot_damage_multiplier": bool_value(projectile.get("ignoreparentshootdamagemultiplier", "")),
        "building_damage_multiplier": number(projectile.get("buildingdamagemultiplier", ""), 1.0),
        "air_damage_multiplier": number(projectile.get("damagetoair", ""), 1.0),
        "shield_damage_multiplier": number(projectile.get("shielddamagemultiplier", ""), 1.0),
        "shield_deflection_multiplier": number(projectile.get("shielddefectionmultiplier", ""), 1.0),
        "hull_damage_multiplier": number(projectile.get("hulldamagemultiplier", ""), 1.0),
        "armor_ignore": number(projectile.get("armourignoreamount", projectile.get("armorignoreamount", projectile.get("armourignore", projectile.get("armorignore", ""))))),
        "push_force": number(projectile.get("pushforce", "")),
        "push_velocity": number(projectile.get("pushvelocity", "")),
        "spawn_on_end_of_life": spawn_on_end_of_life,
        "spawn_on_explode": spawn_on_explode,
        "spawn_on_create": spawn_on_create,
        "spawn_units_on_explode": unit_spawn_specs(projectile.get("spawnunit", "").strip()),
    }


def interceptor_specs_for(path: Path) -> list[dict[str, object]]:
    sections = effective_sections(path)
    result: list[dict[str, object]] = []
    for turret_name in sections:
        if not turret_name.startswith("turret_"):
            continue
        turret = section_values(sections, turret_name, "turret_")
        raw_tags = turret.get("interceptprojectiles_withtags", "").strip()
        projectile_name = turret.get("projectile", "1").strip()
        projectile_spec = projectile_profile(projectile_name, sections, path)
        if not raw_tags or not projectile_spec:
            continue
        resource_usage: dict[str, float] = {}
        for entry in turret.get("resourceusage", "").split(","):
            if "=" not in entry:
                continue
            resource_name, raw_amount = entry.split("=", 1)
            if resource_name.strip():
                resource_usage[resource_name.strip()] = number(raw_amount.strip())
        result.append({
            "turret": turret_name.removeprefix("turret_"),
            "shoot_sound": turret.get("shoot_sound", "").strip(),
            "shoot_sound_volume": number(turret.get("shoot_sound_vol", ""), 0.3),
            "shoot_flame": turret.get("shoot_flame", "").strip(),
            "shoot_light": turret.get("shoot_light", "").strip(),
            "tags": [tag.strip() for tag in raw_tags.split(",") if tag.strip()],
            "target_ground_under_distance": number(turret.get("interceptprojectiles_andtargetinggroundunderdistance", ""), -1.0),
            "projectile_under_distance": number(turret.get("interceptprojectiles_andunderdistance", "")),
            "projectile_over_height": number(turret.get("interceptprojectiles_andoverheight", "")),
            "muzzle_x": number(turret.get("x", "")),
            "muzzle_y": number(turret.get("y", "")),
            "resource_usage": resource_usage,
            "projectile_profile": projectile_spec,
        })
    return result


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
        projectile_profile_spec: dict[str, object] = projectile_profile(projectile_name, sections, path)
        has_projectile_behavior: bool = any(
            projectile_profile_spec[key]
            for key in ("spawn_on_end_of_life", "spawn_on_explode", "spawn_on_create", "spawn_units_on_explode")
        )
        if direct_damage <= 0.0 and splash_damage <= 0.0 and not has_projectile_behavior:
            continue
        range_value = positive_number(turret.get("limitingrange", ""), attack_range)
        reload_value = positive_time_number(turret.get("delay", ""), positive_time_number(attack.get("shootdelay", ""), 60.0))
        instant = bool_value(projectile.get("instant", "")) or bool_value(attack.get("ismelee", ""))
        projectile_speed = number(projectile.get("speed", "5"), 5.0)
        target_speed = number(projectile.get("targetspeed", ""), projectile_speed)
        speed_acceleration = number(projectile.get("targetspeedacceleration", ""), 0.1)
        if projectile_speed <= 0.0:
            instant = True
        friendly_fire_value = projectile.get("friendlyfire", "").strip().casefold()
        friendly_fire_mode = "only-ignore-enemy" if friendly_fire_value == "only-ignoreenemy" else friendly_fire_value
        weapon: dict[str, object] = {
            "turret": turret_name.removeprefix("turret_"),
            "projectile": projectile_name,
            "shoot_sound": turret.get("shoot_sound", "").strip(),
            "shoot_sound_volume": number(turret.get("shoot_sound_vol", ""), 0.3),
            "shoot_flame": turret.get("shoot_flame", "").strip(),
            "shoot_light": turret.get("shoot_light", "").strip(),
            "range": range_value,
            "minimum_range": number(turret.get("limitingminrange", "")),
            "reload": max(1, math.ceil(reload_value)),
            "warmup": max(0, math.ceil(time_number(turret.get("warmup", "")))),
            "turn_speed": number(turret.get("turnspeed", ""), number(attack.get("turretturnspeed", ""), 8.0)),
            "muzzle_x": number(turret.get("x", "")),
            "muzzle_y": number(turret.get("y", "")),
            "muzzle_distance": number(turret.get("muzzledistance", ""), number(attack.get("muzzledistance", ""))),
            "ground": bool_value(turret.get("canattacklandunits", ""), bool_value(attack.get("canattacklandunits", ""))),
            "air": bool_value(turret.get("canattackflyingunits", ""), bool_value(attack.get("canattackflyingunits", ""))),
            "underwater": bool_value(turret.get("canattackunderwaterunits", ""), bool_value(attack.get("canattackunderwaterunits", ""))),
            "direct_damage": direct_damage,
            "splash_damage": splash_damage,
            "deflection_power": number(projectile.get("deflectionpower", ""), 1.0),
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
            "projectile_turn_speed_near": number(projectile.get("turnspeedwhennear", ""), -1.0),
            "lifetime": max(1, math.ceil(positive_time_number(projectile.get("life", ""), 60.0))),
            "delayed_start": max(0.0, time_number(projectile.get("delayedstarttimer", ""))),
            "instant": instant,
            "instant_reuse_last": bool_value(projectile.get("instantreuselast", "")),
            "instant_reuse_last_also_change_turret_aim": bool_value(projectile.get("instantreuselast_alsochangeturretaim", "")),
            "instant_reuse_last_keep_area_damage_list": bool_value(projectile.get("instantreuselast_keepareadamagelist", "")),
            "move_with_parent": bool_value(projectile.get("movewithparent", "")),
            "beam": bool_value(projectile.get("lasereffect", "")) or bool_value(projectile.get("lightingeffect", "")) or bool(projectile.get("beamimage", "").strip()),
            "target_ground": bool_value(projectile.get("targetground", "")),
            "target_ground_include_target_height": bool_value(projectile.get("targetground_includetargetheight", "")),
            "target_ground_spread": number(projectile.get("targetgroundspread", "")),
            "target_ground_height_offset": number(projectile.get("targetgroundheightoffset", "")),
            "lead_target": not bool_value(projectile.get("disableleadtargeting", "")),
            "lead_target_speed_calculation": number(projectile.get("leadtargetingspeedcalculation", ""), -1.0),
            "sweep_speed": number(projectile.get("sweepspeed", "")),
            "sweep_offset": number(projectile.get("sweepoffset", "")),
            "sweep_offset_from_target_radius": number(projectile.get("sweepoffsetfromtargetradius", "")),
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
            "wobble_frequency": positive_time_number(projectile.get("wobblefrequency", ""), 5.0),
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
        weapon.update(projectile_profile_spec)
        weapon["instant"] = instant
        result.append(weapon)
    return result


def projectile_profiles_for(path: Path) -> dict[str, dict[str, object]]:
    sections = effective_sections(path)
    profiles: dict[str, dict[str, object]] = {}
    for section in sections:
        if not section.startswith("projectile_"):
            continue
        projectile_name = section.removeprefix("projectile_")
        profile = projectile_profile(projectile_name, sections, path)
        if profile:
            profiles[projectile_name.casefold()] = profile
    return profiles


def main() -> None:
    global RWX_UNIT_ASSET_ROOT, RWX_DRAWABLE_EFFECT_ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rwx_root", type=Path)
    arguments = parser.parse_args()
    RWX_UNIT_ASSET_ROOT = arguments.rwx_root / "assets/units"
    RWX_DRAWABLE_EFFECT_ROOT = arguments.rwx_root / "assets/drawable/effects"
    units = read_builtin_units(arguments.rwx_root, read_native_types(arguments.rwx_root))
    specs = {
        name: spec_for(arguments.rwx_root / str(info["source"]))
        for name, info in units.items()
    }
    projectile_profiles = {
        name: projectile_profiles_for(arguments.rwx_root / str(info["source"]))
        for name, info in units.items()
    }
    interceptor_specs = {
        name: interceptor_specs_for(arguments.rwx_root / str(info["source"]))
        for name, info in units.items()
    }
    effect_profiles = {
        name: effect_profiles_for(arguments.rwx_root / str(info["source"]))
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
    lines.extend(["}", "", "const PROJECTILE_PROFILES: Dictionary = {"])
    for name in sorted(projectile_profiles, key=str.casefold):
        if projectile_profiles[name]:
            lines.append(f"\t{gd(name)}: {gd(projectile_profiles[name], 1)},")
    lines.extend(["}", "", "const INTERCEPTOR_SPECS: Dictionary = {"])
    for name in sorted(interceptor_specs, key=str.casefold):
        if interceptor_specs[name]:
            lines.append(f"\t{gd(name)}: {gd(interceptor_specs[name], 1)},")
    lines.extend(["}", "", "const EFFECT_PROFILES: Dictionary = {"])
    for name in sorted(effect_profiles, key=str.casefold):
        if effect_profiles[name]:
            lines.append(f"\t{gd(name)}: {gd(effect_profiles[name], 1)},")
    lines.extend(["}", ""])
    OUTPUT_PATH.write_bytes("\n".join(lines).encode("utf-8"))
    print(f"Generated combat specs for {sum(bool(value) for value in specs.values())} bundled units")


if __name__ == "__main__":
    main()
