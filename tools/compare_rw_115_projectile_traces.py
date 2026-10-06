"""Compare live original and Godot projectile trajectories by global object ID."""

from __future__ import annotations

import argparse
import itertools
import json
from pathlib import Path
import struct


FLOAT_FIELDS = {
    "x": ("eo", "x"),
    "y": ("ep", "y"),
    "height": ("eq", "height"),
    "velocity_x": ("u", "velocity_x"),
    "velocity_y": ("v", "velocity_y"),
    "height_velocity": ("w", "height_velocity"),
    "heading": ("az", "heading"),
    "remaining": ("h", "remaining"),
    "age": ("J", "age"),
    "target_x": ("n", "target_x"),
    "target_y": ("o", "target_y"),
    "direct_damage": ("U", "direct_damage"),
}
EXACT_FIELDS = {
    "target_id": ("target_id", "target_id"),
    "owner_id": ("owner_id", "owner_id"),
    "impacted": ("bn", "impacted"),
    "target_ground": ("m", "target_ground"),
}


def float32_bits(value: object) -> bytes:
    return struct.pack("!f", float(value))


def frame_groups(path: Path):
    with path.open(encoding="utf-8") as stream:
        rows = (json.loads(line) for line in stream if line.strip())
        for frame, grouped_rows in itertools.groupby(rows, key=lambda row: int(row["frame"])):
            yield frame, {int(row["id"]): row for row in grouped_rows}


def compare(original_path: Path, godot_path: Path) -> dict[str, object]:
    original_frames = iter(frame_groups(original_path))
    godot_frames = iter(frame_groups(godot_path))
    original_frame, original_rows = next(original_frames, (-1, {}))
    godot_frame, godot_rows = next(godot_frames, (-1, {}))
    compared = 0
    missing = 0
    extra = 0
    field_counts: dict[str, int] = {}
    first_difference: dict[str, object] | None = None
    first_common_projectile: dict[str, object] | None = None
    while original_frame >= 0 or godot_frame >= 0:
        if original_frame < 0:
            extra += len(godot_rows)
            godot_frame, godot_rows = next(godot_frames, (-1, {}))
            continue
        if godot_frame < 0:
            missing += len(original_rows)
            original_frame, original_rows = next(original_frames, (-1, {}))
            continue
        if godot_frame < original_frame:
            extra += len(godot_rows)
            godot_frame, godot_rows = next(godot_frames, (-1, {}))
            continue
        if original_frame < godot_frame:
            missing += len(original_rows)
            original_frame, original_rows = next(original_frames, (-1, {}))
            continue
        common_ids = original_rows.keys() & godot_rows.keys()
        missing += len(original_rows.keys() - godot_rows.keys())
        extra += len(godot_rows.keys() - original_rows.keys())
        for projectile_id in sorted(common_ids):
            original = original_rows[projectile_id]
            godot = godot_rows[projectile_id]
            original_state = original["projectile"]
            compared += 1
            if first_common_projectile is None:
                first_common_projectile = {
                    "frame": original_frame,
                    "id": projectile_id,
                    "owner": original.get("owner", ""),
                    "target": original.get("target", ""),
                }
            differences: dict[str, object] = {}
            for name, (original_name, godot_name) in FLOAT_FIELDS.items():
                if original_name not in original_state or godot_name not in godot:
                    continue
                original_value = original_state[original_name]
                godot_value = godot[godot_name]
                if float32_bits(original_value) != float32_bits(godot_value):
                    differences[name] = {"original": original_value, "godot": godot_value}
            for name, (original_name, godot_name) in EXACT_FIELDS.items():
                if original_name not in original or godot_name not in godot:
                    continue
                if original[original_name] != godot[godot_name]:
                    differences[name] = {"original": original[original_name], "godot": godot[godot_name]}
            for name in differences:
                field_counts[name] = field_counts.get(name, 0) + 1
            if differences and first_difference is None:
                first_difference = {
                    "frame": original_frame,
                    "id": projectile_id,
                    "owner": original.get("owner", ""),
                    "target": original.get("target", ""),
                    "differences": differences,
                }
        original_frame, original_rows = next(original_frames, (-1, {}))
        godot_frame, godot_rows = next(godot_frames, (-1, {}))
    return {
        "compared_projectile_frames": compared,
        "missing_godot_projectile_frames": missing,
        "extra_godot_projectile_frames": extra,
        "field_difference_counts": field_counts,
        "first_common_projectile": first_common_projectile,
        "first_difference": first_difference,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path, help="original-projectiles.jsonl from --projectile-trace")
    parser.add_argument("godot", type=Path, help="godot-projectiles.jsonl from the same soak")
    args = parser.parse_args()
    result = compare(args.original, args.godot)
    output = args.godot.with_name("projectile-differences.json")
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    print(f"Full report: {output}")


if __name__ == "__main__":
    main()
