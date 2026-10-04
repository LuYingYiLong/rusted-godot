"""Rebuild the compact parity report from a completed original 1.15 AI soak."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from run_rw_115_ai_soak import collect_original_metrics, collect_summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_directory", type=Path)
    arguments = parser.parse_args()
    directory = arguments.run_directory.resolve()
    metadata = json.loads((directory / "run.json").read_text(encoding="utf-8"))
    completed = False
    with (directory / "godot.jsonl").open("r", encoding="utf-8") as stream:
        for line in stream:
            if json.loads(line).get("event") == "transport_completed":
                completed = True
                break
    summary = collect_summary(directory / "godot.jsonl", metadata, 0 if completed else 1)
    summary["original_metrics"] = collect_original_metrics(directory / "original-metrics.jsonl")
    (directory / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({
        "status": summary["status"],
        "last_frame": summary["last_frame"],
        "total_commands": summary["total_commands"],
        "first_difference": summary["first_difference"],
        "first_full_checksum_difference": summary["first_full_checksum_difference"],
        "first_field_difference_frames": summary["first_field_difference_frames"],
        "mismatch_field_counts": summary["mismatch_field_counts"],
        "original_maximum": summary["original_metrics"]["maximum"],
    }, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
