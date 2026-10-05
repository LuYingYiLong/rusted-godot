"""Compare original frame-end CSV and Godot TSV using float32 bit patterns."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import struct
from itertools import groupby
from functools import lru_cache


FIELDS = {
    "x": "x",
    "y": "y",
    "rotation": "rot",
    "speed": "movement_factor",
    "turn_velocity": "turn_velocity",
    "push_x": "push_x",
    "push_y": "push_y",
    "build": "build",
    "hp": "hp",
    "weapon_warmup": "operation_charge",
    "factory_clearance": "factory_clearance",
    "terrain_blocked_time": "terrain_blocked_time",
    "waypoint_time": "waypoint_time",
    "slide_x": "slide_x",
    "slide_y": "slide_y",
    "formation_x": "formation_x",
    "formation_y": "formation_y",
    "formation_angle": "formation_angle",
    "formation_recovery": "formation_recovery",
    "formation_lag": "formation_lag",
    "arrival_time": "arrival_time",
}

EXACT_FIELDS = ("order", "path_count", "dead", "terrain_clear_steps", "formation_leader", "formation_size", "formation_leader_age")


def bits(value: str) -> str:
    return struct.pack("!f", float(value)).hex()


@lru_cache(maxsize=8192)
def path_bits(value: str) -> tuple[tuple[str, str], ...]:
    """Compare every retained node, including nodes beyond the current waypoint."""
    return tuple(tuple(bits(coordinate) for coordinate in point.split(":")) for point in value.split("|") if point)


def frame_groups(rows):
    for frame, group in groupby(rows, key=lambda row: int(row["frame"])):
        yield frame, {int(row["id"]): row for row in group}


def compare(directory: Path, godot_path: Path | None = None, max_frame: int | None = None, original_path: Path | None = None) -> dict[str, object]:
    compared = 0
    missing = 0
    extra = 0
    coverage: dict[str, int] = {}
    first: dict[str, object] | None = None
    first_gameplay: dict[str, object] | None = None
    divergent_units: dict[int, dict[str, object]] = {}
    fields: dict[str, int] = {}
    with (original_path or directory / "original-units.csv").open(encoding="utf-8") as stream, (godot_path or directory / "godot.tsv").open(encoding="utf-8") as godot_stream:
        godot_frames = iter(frame_groups(csv.DictReader(godot_stream, delimiter="\t")))
        godot_frame, godot_units = next(godot_frames, (-1, {}))
        for source_frame, source_units in frame_groups(csv.DictReader(stream)):
            if max_frame is not None and source_frame > max_frame:
                break
            while godot_frame >= 0 and godot_frame < source_frame:
                godot_frame, godot_units = next(godot_frames, (-1, {}))
            actual_units = godot_units if godot_frame == source_frame else {}
            missing += len(source_units.keys() - actual_units.keys())
            extra += len(actual_units.keys() - source_units.keys())
            for object_id in sorted(source_units.keys() | actual_units.keys()):
                source = source_units.get(object_id)
                actual = actual_units.get(object_id)
                key = (source_frame, object_id)
                if source is None or actual is None:
                    record = {"frame": source_frame, "id": object_id,
                              "type": actual.get("type", "unknown") if actual else "unknown",
                              "differences": {"presence": {"original": source is not None, "godot": actual is not None}}}
                    if first is None:
                        first = record
                    if first_gameplay is None and record["type"] != "tree":
                        first_gameplay = record
                    divergent_units.setdefault(object_id, record)
                    continue
                compared += 1
                differences = {}
                for source_name, godot_name in FIELDS.items():
                    if godot_name not in actual or source_name not in source:
                        continue
                    if source_name == "weapon_warmup" and float(actual.get("construction_warmup", "0")) <= 0.0:
                        continue
                    coverage[source_name] = coverage.get(source_name, 0) + 1
                    if bits(source[source_name]) != bits(actual[godot_name]):
                        differences[source_name] = {
                            "original": float(source[source_name]),
                            "godot": float(actual[godot_name]),
                            "original_bits": bits(source[source_name]),
                            "godot_bits": bits(actual[godot_name]),
                        }
                        fields[source_name] = fields.get(source_name, 0) + 1
                for name in EXACT_FIELDS:
                    if name in source and name in actual:
                        coverage[name] = coverage.get(name, 0) + 1
                    if name in source and name in actual and source[name] != actual[name]:
                        differences[name] = {"original": source[name], "godot": actual[name]}
                        fields[name] = fields.get(name, 0) + 1
                if "path_points" in source and "path_points" in actual:
                    coverage["path_points"] = coverage.get("path_points", 0) + 1
                    if path_bits(source["path_points"]) != path_bits(actual["path_points"]):
                        differences["path_points"] = {"original": source["path_points"], "godot": actual["path_points"]}
                        fields["path_points"] = fields.get("path_points", 0) + 1
                if differences:
                    record = {"frame": key[0], "id": key[1], "type": actual["type"],
                              "original_order": source.get("order", ""), "godot_order": actual["order"],
                              "differences": differences}
                    if first is None:
                        first = record
                    if first_gameplay is None and actual["type"] != "tree":
                        first_gameplay = record
                    divergent_units.setdefault(key[1], record)
    return {
        "directory": str(directory), "compared_unit_frames": compared,
        "maximum_frame": max_frame,
        "missing_godot_unit_frames": missing, "extra_godot_unit_frames": extra, "first_difference": first,
        "compared_fields": coverage,
        "first_gameplay_difference": first_gameplay,
        "first_difference_per_unit": sorted(divergent_units.values(), key=lambda value: (value["frame"], value["id"])),
        "field_difference_counts": fields,
    }


def compare_teams(original_path: Path, godot_path: Path, max_frame: int | None = None) -> dict[str, object]:
    """Compare per-frame credit balances as doubles, with no reconciliation or tolerance."""
    compared = missing = extra = 0
    first = None
    with original_path.open(encoding="utf-8") as source_stream, godot_path.open(encoding="utf-8") as actual_stream:
        source_rows = ({**row, "id": row["slot"]} for row in csv.DictReader(source_stream))
        actual_rows = ({**row, "id": row["slot"]} for row in csv.DictReader(actual_stream, delimiter="\t"))
        actual_frames = iter(frame_groups(actual_rows))
        actual_frame, actual_teams = next(actual_frames, (-1, {}))
        for frame, source_teams in frame_groups(source_rows):
            if max_frame is not None and frame > max_frame:
                break
            while actual_frame >= 0 and actual_frame < frame:
                actual_frame, actual_teams = next(actual_frames, (-1, {}))
            teams = actual_teams if actual_frame == frame else {}
            missing += len(source_teams.keys() - teams.keys())
            extra += len(teams.keys() - source_teams.keys())
            for slot in sorted(source_teams.keys() | teams.keys()):
                source, actual = source_teams.get(slot), teams.get(slot)
                if source is None or actual is None:
                    if first is None:
                        first = {"frame": frame, "slot": slot, "presence": {"original": source is not None, "godot": actual is not None}}
                    continue
                compared += 1
                original_bits = struct.pack("!d", float(source["credits"])).hex()
                godot_bits = struct.pack("!d", float(actual["credits"])).hex()
                if first is None and original_bits != godot_bits:
                    first = {"frame": frame, "slot": slot, "original": float(source["credits"]),
                             "godot": float(actual["credits"]), "original_bits": original_bits, "godot_bits": godot_bits}
    return {"compared_team_frames": compared, "missing_godot_team_frames": missing,
            "extra_godot_team_frames": extra, "first_difference": first}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--godot", type=Path, help="Compare an offline replay TSV against the same original trace")
    parser.add_argument("--max-frame", type=int, help="Limit both traces to the verified replay interval")
    args = parser.parse_args()
    result = compare(args.directory, args.godot, args.max_frame)
    output = args.directory / ("unit-differences.json" if args.godot is None else args.godot.stem + "-differences.json")
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key != "first_difference_per_unit"}, indent=2))
    print(f"Full report: {output}")


if __name__ == "__main__":
    main()
