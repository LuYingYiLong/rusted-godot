"""Compare global GameObject allocation IDs captured by the stock game and Godot."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def read_rows(path: Path, delimiter: str) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream, delimiter=delimiter))


def latest_frame(path: Path) -> int:
    maximum = 0
    with path.open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            maximum = max(maximum, int(row["frame"]))
    return maximum


def original_category(class_name: str) -> str:
    if class_name == "com.corrodinggames.rts.game.f":
        return "projectile"
    if class_name == "com.corrodinggames.rts.gameFramework.d.f":
        return "death_effect_emitter"
    if class_name == "com.corrodinggames.rts.game.l":
        return "death_scorch_mark"
    if ".game.units." in class_name:
        return "unit"
    return "class:" + class_name


def godot_category(row: dict[str, str]) -> str:
    kind = row["kind"]
    if kind in {"unit", "produced_unit", "building_candidate"}:
        return "unit"
    return kind


def compare(original_path: Path, godot_path: Path, frame_limit: int | None = None) -> dict[str, object]:
    original = read_rows(original_path, ",")
    godot = read_rows(godot_path, "\t")
    if frame_limit is not None:
        original = [row for row in original if int(row["frame"]) <= frame_limit]
        godot = [row for row in godot if int(row["frame"]) <= frame_limit]
    original_by_id = {int(row["id"]): row for row in original}
    godot_by_id = {int(row["id"]): row for row in godot}
    original_ids = set(original_by_id)
    godot_ids = set(godot_by_id)
    shared_ids = sorted(original_ids & godot_ids)
    category_differences: list[dict[str, object]] = []
    for object_id in shared_ids:
        original_row = original_by_id[object_id]
        godot_row = godot_by_id[object_id]
        original_kind = original_category(original_row["class"])
        godot_kind = godot_category(godot_row)
        if original_kind != godot_kind:
            category_differences.append({
                "id": object_id,
                "original": {
                    "frame": int(original_row["frame"]),
                    "class": original_row["class"],
                    "category": original_kind,
                },
                "godot": {
                    "frame": int(godot_row["frame"]),
                    "kind": godot_row["kind"],
                    "type": godot_row["type"],
                    "category": godot_kind,
                },
            })
    first_original_id = min(original_ids, default=0)
    last_original_id = max(original_ids, default=0)
    godot_window_ids = {
        object_id for object_id in godot_ids
        if first_original_id <= object_id <= last_original_id
    }
    first_difference: dict[str, object] | None = None
    missing_godot = sorted(original_ids - godot_ids)
    extra_godot = sorted(godot_window_ids - original_ids)
    if missing_godot:
        object_id = missing_godot[0]
        original_row = original_by_id[object_id]
        first_difference = {
            "id": object_id,
            "original": {"frame": int(original_row["frame"]), "class": original_row["class"]},
            "godot": None,
        }
    elif extra_godot:
        object_id = extra_godot[0]
        godot_row = godot_by_id[object_id]
        first_difference = {
            "id": object_id,
            "original": None,
            "godot": {
                "frame": int(godot_row["frame"]),
                "kind": godot_row["kind"],
                "type": godot_row["type"],
            },
        }
    return {
        "original_allocations": len(original),
        "godot_allocations": len(godot),
        "frame_limit": frame_limit,
        "compared_ids": len(shared_ids),
        "original_ids_missing_in_godot": missing_godot,
        "godot_only_ids_in_original_trace_range": extra_godot,
        "first_difference": first_difference,
        "first_category_difference": category_differences[0] if category_differences else None,
        "allocation_category_mismatch_count": len(category_differences),
        "prefix_status": "mismatch" if first_difference is not None or category_differences else "matched",
        "trace_status": "same_id_range" if len(original) == len(godot_window_ids) else "truncated_or_missing_allocations",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--original", type=Path)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--godot-units", type=Path)
    arguments = parser.parse_args()
    directory: Path = arguments.directory
    original_path: Path = arguments.original or directory / "original-object-ids.csv"
    godot_path: Path = arguments.godot or directory / "godot-object-ids.tsv"
    godot_units_path: Path = arguments.godot_units or directory / "godot.tsv"
    frame_limit: int | None = latest_frame(godot_units_path) if godot_units_path.is_file() else None
    result = compare(original_path, godot_path, frame_limit)
    print(json.dumps(result, indent=2))
    return 1 if result["prefix_status"] == "mismatch" else 0


if __name__ == "__main__":
    raise SystemExit(main())
