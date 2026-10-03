"""Report the first unit-state divergence between OPEN-RW and Godot TSV probes."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


NUMERIC_FIELDS = ("x", "y", "rot", "weapon_rot", "hp", "build")
DEFAULT_FIELDS = ("x", "y", "rot", "weapon_rot", "hp", "build", "order")


def load_trace(path: Path) -> dict[tuple[int, int], dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames is None or not {"frame", "id"}.issubset(reader.fieldnames):
            raise ValueError(f"{path} is not a state-probe TSV")
        return {(int(row["frame"]), int(row["id"])): row for row in reader}


def difference(field: str, reference: str, replica: str) -> float | None:
    if field not in NUMERIC_FIELDS:
        return 0.0 if reference == replica else math.inf
    if not reference or not replica:
        return None
    reference_values = [float(value) for value in reference.split("|")]
    replica_values = [float(value) for value in replica.split("|")]
    if len(reference_values) != len(replica_values):
        return math.inf
    if field in {"rot", "weapon_rot"}:
        return max(abs((left - right + 180.0) % 360.0 - 180.0) for left, right in zip(reference_values, replica_values))
    return max(abs(left - right) for left, right in zip(reference_values, replica_values))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path, help="OPEN-RW TSV")
    parser.add_argument("replica", type=Path, help="Godot TSV")
    parser.add_argument("--frame-offset", type=int, default=0, help="Godot frame minus OPEN-RW frame")
    parser.add_argument("--id-map", type=Path, help="JSON object mapping OPEN-RW IDs to Godot IDs")
    parser.add_argument("--unit-id", type=int, action="append", help="compare only this OPEN-RW unit ID; can be repeated")
    parser.add_argument("--fields", default=",".join(DEFAULT_FIELDS))
    parser.add_argument("--position-tolerance", type=float, default=0.5)
    parser.add_argument("--angle-tolerance", type=float, default=1.0)
    parser.add_argument("--value-tolerance", type=float, default=0.01)
    args = parser.parse_args()

    reference = load_trace(args.reference)
    replica = load_trace(args.replica)
    id_map = {int(key): int(value) for key, value in json.loads(args.id_map.read_text(encoding="utf-8")).items()} if args.id_map else {}
    if args.unit_id:
        selected_ids = set(args.unit_id)
        reference = {key: row for key, row in reference.items() if key[1] in selected_ids}
        replica_ids = {id_map.get(unit_id, unit_id) for unit_id in selected_ids}
        replica = {key: row for key, row in replica.items() if key[1] in replica_ids}
    fields = [field.strip() for field in args.fields.split(",") if field.strip()]
    unknown = set(fields) - set(next(iter(reference.values()), {}))
    if unknown:
        parser.error(f"unknown fields: {', '.join(sorted(unknown))}")

    reference_frames = {frame for frame, _ in reference}
    replica_frames = {frame - args.frame_offset for frame, _ in replica}
    shared_frames = reference_frames & replica_frames
    if not shared_frames:
        print("No matching frames; align the frame offset before comparing")
        return 2

    compared = 0
    for (frame, unit_id), expected in sorted(reference.items()):
        if frame not in shared_frames:
            continue
        matched = replica.get((frame + args.frame_offset, id_map.get(unit_id, unit_id)))
        if matched is None:
            print(f"Missing Godot unit: OPEN-RW frame {frame}, ID {unit_id}; expected Godot ID {id_map.get(unit_id, unit_id)}")
            return 1
        compared += 1
        for field in fields:
            error = difference(field, expected[field], matched[field])
            if error is None:
                continue
            tolerance = args.position_tolerance if field in {"x", "y"} else args.angle_tolerance if field in {"rot", "weapon_rot"} else args.value_tolerance if field in {"hp", "build"} else 0.0
            if error > tolerance:
                print(f"First difference: OPEN-RW frame {frame}, ID {unit_id}; Godot frame {frame + args.frame_offset}, ID {id_map.get(unit_id, unit_id)}")
                print(f"  {field}: OPEN-RW={expected[field]!r}, Godot={matched[field]!r}, error={error:g}, tolerance={tolerance:g}")
                return 1
    mapped_reference_keys = {(frame + args.frame_offset, id_map.get(unit_id, unit_id)) for frame, unit_id in reference if frame in shared_frames}
    extra_keys = sorted(key for key in replica if key[0] - args.frame_offset in shared_frames and key not in mapped_reference_keys)
    if extra_keys:
        print(f"Extra Godot unit: frame {extra_keys[0][0]}, ID {extra_keys[0][1]}")
        return 1
    print(f"Compared {compared} frame/ID pairs: no differences above tolerance")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
