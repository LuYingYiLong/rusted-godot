"""Convert captured vanilla room commands into OPEN-RW probe input."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path


def native_types() -> list[str]:
    catalog = (
        Path(__file__).resolve().parents[1]
        / "scripts/utils/units/rw_vanilla_unit_catalog.gd"
    ).read_text(encoding="utf-8")
    section = re.search(r"const NATIVE_TYPES: Array\[String\] = \[(.*?)\]", catalog, re.S)
    if section is None:
        raise ValueError("Could not read the vanilla native unit catalog")
    return re.findall(r'"([^"]+)"', section.group(1))


def vector(value: object) -> tuple[str, str]:
    if not isinstance(value, str):
        return "0.0", "0.0"
    parts = value.strip().strip("()").split(",")
    if len(parts) != 2:
        raise ValueError(f"Invalid vector: {value!r}")
    return parts[0].strip(), parts[1].strip()


def extract(report: Path, output: Path, max_frame: int) -> int:
    names = native_types()
    count = 0
    with report.open("r", encoding="utf-8") as source, output.open(
        "w", encoding="utf-8", newline=""
    ) as destination:
        writer = csv.writer(destination, delimiter="\t", lineterminator="\n")
        writer.writerow(("frame", "unit_id", "order", "x", "y", "build_type", "action_id", "start_x", "start_y", "created_tick", "path", "queued", "high_priority"))
        for line in source:
            record = json.loads(line)
            if record.get("event") != "commands":
                continue
            frame = int(record["frame"])
            if max_frame >= 0 and frame > max_frame:
                continue
            for command in record["commands"]:
                order = str(command.get("order_type", ""))
                action_id = str(command.get("action_id", ""))
                if not order and action_id in ("", "-1"):
                    continue
                build_type = ""
                if order == "build":
                    index = int(command.get("build_unit_index", -1))
                    if index == -2:
                        build_type = str(command.get("custom_build_unit_name", ""))
                    elif 0 <= index < len(names):
                        build_type = names[index]
                    if not build_type:
                        raise ValueError(f"Unknown build type at frame {frame}: {index}")
                for unit_id in command.get("unit_ids", []):
                    target = command.get("target", "(0.0, 0.0)")
                    metadata = command.get("command_targets", {}).get(str(unit_id), {})
                    target = metadata.get("target_position", target)
                    x, y = vector(target)
                    start_x, start_y = vector(metadata.get("start_position"))
                    path = ";".join(
                        ":".join(map(str, re.findall(r"-?\d+", point)))
                        for point in metadata.get("path", [])
                    )
                    writer.writerow((frame, int(unit_id), order, x, y, build_type, action_id, start_x, start_y, metadata.get("created_tick", -1), path, int(bool(command.get("is_queued") or command.get("order_is_queued"))), int(bool(command.get("is_high_priority")))))
                    count += 1
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--max-frame", type=int, default=-1)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    count = extract(args.report, args.output, args.max_frame)
    print(f"Exported {count} commands to {args.output}")


if __name__ == "__main__":
    main()
