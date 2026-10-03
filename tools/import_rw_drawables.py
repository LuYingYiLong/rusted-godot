"""Copy and catalog the raster images from RWX assets/drawable.

Run once to copy images, let the Godot editor import them, then run again with
--catalog-only to refresh the UID catalog. Android drawable XML files are not
textures and are intentionally excluded.
"""

from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DESTINATION_ROOT = PROJECT_ROOT / "assets" / "rwx" / "drawable"
CATALOG_PATH = PROJECT_ROOT / "scripts" / "utils" / "rw_drawable_catalog.gd"
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg"}

CATEGORY_PREFIXES: dict[str, tuple[str, ...]] = {
    "units/air": (
        "amphibious_jet", "dropship", "gunship", "helicopter", "large_gunship",
    ),
    "units/naval": (
        "attack_submarine", "battle_ship", "builder_ship", "gun_boat",
        "hovercraft", "scout_ship", "ship",
    ),
    "units/buildings": (
        "air_factory", "anti_air_top", "antinuke_launcher", "base",
        "experimental_unit_factory", "extractor", "land_factory",
        "laser_defence", "nuke_launcher", "power", "repair_bay",
        "sea_factory", "supply_depot", "turret_", "wall_",
    ),
    "units/land": (
        "artillery", "builder", "experimental_hovertank", "experimental_tank",
        "heavy_hover_tank", "heavy_tank", "hover_tank", "laser_tank",
        "mammoth_tank", "mega_tank", "tank1", "tank2",
    ),
    "units/creatures": ("ladybug", "queenbug"),
    "world/props": ("crystal", "palm_", "small_trees", "trees"),
    "world/overlays": ("fog_", "lava_bubble", "water_cloud", "water_layer"),
    "effects": (
        "blood_mark", "dust", "effects", "explode", "fire", "flame",
        "light_", "lighting_charge", "noise", "plasma_shot",
        "projectiles", "ripple_", "scorch_mark", "shield_mid",
        "shockwave", "smoke_",
    ),
    "ui/errors": ("error",),
    "ui/help": ("help",),
    "ui/hud": ("metal", "replay_leaderboard", "stats_"),
    "ui/icons": ("icon_", "lock_icon_menu", "unit_icon_"),
    "ui/controls": (
        "back", "btn_", "button_", "fast", "menu", "pause", "pointer",
        "replay_pause", "touch_indicator", "zoom_button",
    ),
    "ui/panels": ("rounded_",),
    "ui/branding": ("icon.png", "icon2.png", "logo", "title"),
    "system/debug": ("temp_workaround_bug_image",),
}


def classify(name: str) -> str:
    if name.startswith("builder_ship"):
        return "units/naval"
    matches = [
        category
        for category, prefixes in CATEGORY_PREFIXES.items()
        if any(name.startswith(prefix) for prefix in prefixes)
    ]
    if len(matches) != 1:
        raise ValueError(f"Expected one category for {name}, found {matches}")
    return matches[0]


def find_source_images(source: Path) -> dict[str, str]:
    if not source.is_dir():
        raise FileNotFoundError(f"RWX drawable directory is missing: {source}")
    images: dict[str, str] = {}
    for path in sorted(source.iterdir()):
        if not path.is_file() or path.suffix.lower() not in IMAGE_SUFFIXES:
            continue
        images[path.name] = classify(path.name)
    if not images:
        raise ValueError(f"No raster images found in {source}")
    return images


def copy_images(source: Path, images: dict[str, str]) -> None:
    for name, category in images.items():
        target = DESTINATION_ROOT / category / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or target.read_bytes() != (source / name).read_bytes():
            shutil.copyfile(source / name, target)


def generate_catalog(images: dict[str, str]) -> None:
    catalog: dict[str, str] = {}
    uid_pattern = re.compile(r'^uid="(uid://[^"]+)"$', re.MULTILINE)
    for name, category in images.items():
        path = DESTINATION_ROOT / category / name
        metadata_path = path.with_name(f"{name}.import")
        if not metadata_path.is_file():
            raise FileNotFoundError(f"Import in Godot before generating the catalog: {path}")
        match = uid_pattern.search(metadata_path.read_text(encoding="utf-8"))
        if match is None:
            raise ValueError(f"Imported image has no UID: {metadata_path}")
        catalog[name] = match.group(1)

    lines = [
        "class_name RwDrawableCatalog",
        "extends RefCounted",
        "",
        "const TEXTURES: Dictionary = {",
    ]
    for name, uid in sorted(catalog.items()):
        lines.append(f'\t"{name}": "{uid}",')
    lines += [
        "}",
        "",
        "",
        "static func load_texture(name: String) -> Texture2D:",
        "\tvar uid: String = str(TEXTURES.get(name, \"\"))",
        "\tif uid.is_empty():",
        "\t\treturn null",
        "\treturn ResourceLoader.load(uid) as Texture2D",
        "",
    ]
    CATALOG_PATH.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="RWX assets/drawable directory")
    parser.add_argument("--catalog-only", action="store_true")
    arguments = parser.parse_args()

    if arguments.catalog_only:
        images: dict[str, str] = {}
        for path in DESTINATION_ROOT.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in IMAGE_SUFFIXES:
                continue
            if path.name in images:
                raise ValueError(f"Duplicate drawable image name: {path.name}")
            images[path.name] = path.parent.relative_to(DESTINATION_ROOT).as_posix()
        if not images:
            raise ValueError("No imported drawable images found")
        for name, category in images.items():
            if classify(name) != category:
                raise ValueError(f"Unexpected drawable path: {category}/{name}")
        generate_catalog(images)
        print(f"Cataloged {len(images)} drawable textures")
        return

    if arguments.source is None:
        parser.error("--source is required when copying RWX drawables")
    images = find_source_images(arguments.source)
    copy_images(arguments.source, images)
    print(f"Copied {len(images)} drawable textures into {DESTINATION_ROOT}")


if __name__ == "__main__":
    main()
