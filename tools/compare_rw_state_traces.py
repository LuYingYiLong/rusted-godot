"""Report the first unit-state divergence between OPEN-RW and Godot TSV probes."""

from __future__ import annotations

import argparse
import csv
import json
import math
from collections.abc import Iterator
from pathlib import Path


NUMERIC_FIELDS = ("x", "y", "push_x", "push_y", "rot", "weapon_rot", "hp", "build", "order_x", "order_y", "path_x", "path_y")
POSITION_FIELDS = {"x", "y", "push_x", "push_y", "order_x", "order_y", "path_x", "path_y"}
DEFAULT_FIELDS = ("type", "team", "x", "y", "rot", "weapon_rot", "hp", "build", "order", "order_x", "order_y", "build_type", "path_x", "path_y")


def iter_frames(path: Path) -> Iterator[tuple[int, dict[int, dict[str, str]]]]:
    """Read one frame at a time so multi-hour traces do not fill memory."""
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames is None or not {"frame", "id"}.issubset(reader.fieldnames):
            raise ValueError(f"{path} is not a state-probe TSV")
        current_frame: int | None = None
        units: dict[int, dict[str, str]] = {}
        for row in reader:
            frame = int(row["frame"])
            unit_id = int(row["id"])
            if current_frame is not None and frame < current_frame:
                raise ValueError(f"{path} has out-of-order frame {frame} after {current_frame}")
            if current_frame is not None and frame != current_frame:
                yield current_frame, units
                units = {}
            if unit_id in units:
                raise ValueError(f"{path} has duplicate unit {unit_id} at frame {frame}")
            units[unit_id] = row
            current_frame = frame
        if current_frame is not None:
            yield current_frame, units


def difference(field: str, reference: str, replica: str) -> float | None:
    if field not in NUMERIC_FIELDS:
        return 0.0 if reference == replica else math.inf
    if not reference and not replica:
        return None
    if not reference or not replica:
        return None if field in {"push_x", "push_y"} else math.inf
    reference_values = [float(value) for value in reference.split("|")]
    replica_values = [float(value) for value in replica.split("|")]
    if len(reference_values) != len(replica_values):
        return math.inf
    if field in {"rot", "weapon_rot"}:
        return max(abs((left - right + 180.0) % 360.0 - 180.0) for left, right in zip(reference_values, replica_values))
    return max(abs(left - right) for left, right in zip(reference_values, replica_values))


def compare_frame(
    frame: int,
    reference: dict[int, dict[str, str]],
    replica: dict[int, dict[str, str]],
    id_map: dict[int, int],
    selected_ids: set[int] | None,
    fields: list[str],
    args: argparse.Namespace,
) -> int:
    selected_reference = {
        unit_id: row
        for unit_id, row in reference.items()
        if (selected_ids is None or unit_id in selected_ids)
        and (not args.declared_only or row.get("declared_type"))
        and row.get("type") not in args.exclude_type
    }
    selected_replica_ids = {id_map.get(unit_id, unit_id) for unit_id in selected_ids} if selected_ids is not None else None
    if args.declared_only or args.exclude_type:
        selected_replica_ids = {id_map.get(unit_id, unit_id) for unit_id in selected_reference}
    selected_replica = {unit_id: row for unit_id, row in replica.items() if selected_replica_ids is None or unit_id in selected_replica_ids}
    expected_replica_ids = {id_map.get(unit_id, unit_id) for unit_id in selected_reference}
    for unit_id, expected in sorted(selected_reference.items()):
        replica_id = id_map.get(unit_id, unit_id)
        matched = selected_replica.get(replica_id)
        if matched is None:
            print(f"Missing Godot unit: OPEN-RW frame {frame}, ID {unit_id}; expected Godot ID {replica_id}")
            return -1
        for field in fields:
            error = difference(field, expected[field], matched[field])
            if error is None:
                continue
            tolerance = args.position_tolerance if field in POSITION_FIELDS else args.angle_tolerance if field in {"rot", "weapon_rot"} else args.value_tolerance if field in {"hp", "build"} else 0.0
            if error > tolerance:
                print(f"First difference: OPEN-RW frame {frame}, ID {unit_id}; Godot frame {frame + args.frame_offset}, ID {replica_id}")
                print(f"  {field}: OPEN-RW={expected[field]!r}, Godot={matched[field]!r}, error={error:g}, tolerance={tolerance:g}")
                return -1
    extra_ids = sorted(set(selected_replica) - expected_replica_ids)
    if extra_ids:
        print(f"Extra Godot unit: frame {frame + args.frame_offset}, ID {extra_ids[0]}")
        return -1
    return len(selected_reference)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path, help="OPEN-RW TSV")
    parser.add_argument("replica", type=Path, help="Godot TSV")
    parser.add_argument("--frame-offset", type=int, default=0, help="Godot frame minus OPEN-RW frame")
    parser.add_argument("--start-frame", type=int, default=0, help="first OPEN-RW frame to compare")
    parser.add_argument("--end-frame", type=int, help="last OPEN-RW frame to compare")
    parser.add_argument("--id-map", type=Path, help="JSON object mapping OPEN-RW IDs to Godot IDs")
    parser.add_argument("--unit-id", type=int, action="append", help="compare only this OPEN-RW unit ID; can be repeated")
    parser.add_argument("--declared-only", action="store_true", help="compare only units injected by the native-unit probe")
    parser.add_argument("--exclude-type", action="append", default=[], help="skip this reference unit type; can be repeated")
    parser.add_argument("--fields", default=",".join(DEFAULT_FIELDS))
    parser.add_argument("--position-tolerance", type=float, default=0.5)
    parser.add_argument("--angle-tolerance", type=float, default=1.0)
    parser.add_argument("--value-tolerance", type=float, default=0.01)
    parser.add_argument("--min-shared-frames", type=int, default=1, help="fail when the aligned overlap is shorter")
    args = parser.parse_args()

    id_map = {int(key): int(value) for key, value in json.loads(args.id_map.read_text(encoding="utf-8")).items()} if args.id_map else {}
    selected_ids = set(args.unit_id) if args.unit_id else None
    fields = [field.strip() for field in args.fields.split(",") if field.strip()]
    with args.reference.open("r", encoding="utf-8-sig", newline="") as stream:
        header = set(next(csv.reader(stream, delimiter="\t"), []))
    with args.replica.open("r", encoding="utf-8-sig", newline="") as stream:
        replica_header = set(next(csv.reader(stream, delimiter="\t"), []))
    unknown = set(fields) - (header & replica_header)
    if unknown:
        parser.error(f"unknown fields: {', '.join(sorted(unknown))}")
    if args.declared_only and "declared_type" not in header:
        parser.error("the reference has no declared_type column")

    reference_iter = iter_frames(args.reference)
    replica_iter = iter_frames(args.replica)
    reference_frame = next(reference_iter, None)
    replica_frame = next(replica_iter, None)
    shared_frames = 0
    compared_units = 0
    while reference_frame is not None and replica_frame is not None:
        reference_number, reference_units = reference_frame
        replica_number, replica_units = replica_frame
        if args.end_frame is not None and reference_number > args.end_frame:
            break
        if reference_number < args.start_frame:
            reference_frame = next(reference_iter, None)
            continue
        aligned_replica_number = replica_number - args.frame_offset
        if reference_number < aligned_replica_number:
            reference_frame = next(reference_iter, None)
            continue
        if aligned_replica_number < reference_number:
            replica_frame = next(replica_iter, None)
            continue
        compared = compare_frame(reference_number, reference_units, replica_units, id_map, selected_ids, fields, args)
        if compared < 0:
            return 1
        compared_units += compared
        shared_frames += 1
        reference_frame = next(reference_iter, None)
        replica_frame = next(replica_iter, None)
    if shared_frames < args.min_shared_frames or compared_units == 0:
        print(f"Insufficient overlap: {shared_frames} frames, {compared_units} unit comparisons; required {args.min_shared_frames} shared frames")
        return 2
    print(f"Compared {shared_frames} frames and {compared_units} frame/ID pairs: no differences above tolerance")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
