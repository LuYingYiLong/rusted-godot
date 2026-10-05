"""Replay captured stock 1.15 commands and reject script errors as well as checksum differences."""

from __future__ import annotations

import argparse
import csv
import json
import hashlib
import os
from pathlib import Path
import subprocess
import struct

from compare_rw_115_unit_traces import compare, compare_teams

PROJECT = Path(__file__).resolve().parents[1]
GODOT = Path(r"C:\Users\Administrator\Documents\Godot\Godot_v4.7.2-stable_win64.exe")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=GODOT)
    parser.add_argument("--output", type=Path, default=PROJECT / ".godot/rw115-regressions")
    parser.add_argument("--collision-reference", type=Path)
    parser.add_argument("--terrain-reference", type=Path)
    parser.add_argument("--sliding-reference", type=Path)
    parser.add_argument("--formation-reference", type=Path)
    parser.add_argument("--case", action="append", help="Run only named checks; repeat to select multiple checks")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    for key in ("RW_PROBE_PATH", "RW_PROBE_UNIT_IDS", "RW_PROBE_CHECKSUMS", "RW_SOAK_REPORT_PATH", "RW_REPLAY_ALLOW_DIFFERENCES", "RW_PATH_PROBE_DIRECTORY"):
        environment.pop(key, None)
    environment["APPDATA"] = str(args.output / "appdata")
    environment["LOCALAPPDATA"] = str(args.output / "localappdata")
    cases = [(name, f"tests/{name}.gd", {}) for name in (
        "rw_115_cross_team_collision_test", "rw_structure_grid_test", "rw_115_build_snap_test",
        "rw_factory_exit_reference_test", "rw_115_fake_goal_test",
        "rw_battle_collision_test", "rw_battle_command_reader_test",
        "rw_115_building_tree_clear_test",
    )]
    references = {}
    team_references = {}
    path_references = {}
    for fixture in sorted((PROJECT / "tests/fixtures").glob("*.jsonl")):
        variables = {
            "RW_SOAK_REPORT_PATH": str(fixture),
            "RW_REPLAY_OUTPUT_PATH": str(args.output / (fixture.stem + ".json")),
        }
        reference = fixture.with_suffix(".csv")
        path_reference = fixture.with_suffix(".paths.json")
        team_reference = fixture.with_suffix(".teams.csv")
        if team_reference.is_file():
            team_references[fixture.stem] = team_reference
        if path_reference.is_file():
            variables["RW_PATH_PROBE_DIRECTORY"] = str(args.output / (fixture.stem + "-paths"))
            path_references[fixture.stem] = path_reference
        if reference.is_file():
            with reference.open(encoding="utf-8") as stream:
                ids = sorted({int(row["id"]) for row in csv.DictReader(stream)})
            variables.update({
                "RW_PROBE_PATH": str(args.output / (fixture.stem + ".tsv")),
                "RW_PROBE_UNIT_IDS": ",".join(map(str, ids)),
            })
            references[fixture.stem] = reference
        cases.append((fixture.stem, "tests/rw_115_ai_trace_replay_test.gd", variables))
    if args.collision_reference:
        cases.append(("rw_115_collision_math", "tests/rw_115_collision_math_test.gd", {
            "RW_COLLISION_REFERENCE": str(args.collision_reference.resolve()),
        }))
    if args.terrain_reference:
        cases.append(("rw_115_terrain_math", "tests/rw_115_terrain_math_test.gd", {
            "RW_TERRAIN_REFERENCE": str(args.terrain_reference.resolve()),
        }))
    if args.sliding_reference:
        cases.append(("rw_115_sliding_math", "tests/rw_115_sliding_math_test.gd", {
            "RW_SLIDING_REFERENCE": str(args.sliding_reference.resolve()),
        }))
    if args.formation_reference:
        cases.append(("rw_115_formation_math", "tests/rw_115_formation_math_test.gd", {
            "RW_FORMATION_REFERENCE": str(args.formation_reference.resolve()),
        }))
    if args.case:
        selected = set(args.case)
        unknown = selected - {name for name, _, _ in cases}
        if unknown:
            parser.error("Unknown checks: " + ", ".join(sorted(unknown)))
        cases = [case for case in cases if case[0] in selected]
    results = []
    for name, script, variables in cases:
        if "RW_PATH_PROBE_DIRECTORY" in variables:
            for stale in Path(variables["RW_PATH_PROBE_DIRECTORY"]).glob("*.json"):
                stale.unlink()
        try:
            process = subprocess.run(
                [str(args.godot), "--headless", "--path", str(PROJECT), "--script", script],
                cwd=PROJECT, env=environment | variables, capture_output=True, text=True,
                encoding="utf-8", errors="replace",
                timeout=120, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
            )
            output = process.stdout + process.stderr
            status = "passed" if process.returncode == 0 and "SCRIPT ERROR" not in output else "failed"
            code = process.returncode
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or b"").decode("utf-8", errors="replace") + (error.stderr or b"").decode("utf-8", errors="replace")
            status, code = "timeout", -1
        (args.output / (name + ".log")).write_text(output, encoding="utf-8")
        detail = {"name": name, "status": status, "exit_code": code}
        if status == "passed" and name in references:
            comparison = compare(references[name].parent, Path(variables["RW_PROBE_PATH"]), original_path=references[name])
            (args.output / (name + "-units.json")).write_text(json.dumps(comparison, indent=2), encoding="utf-8")
            detail["compared_unit_frames"] = comparison["compared_unit_frames"]
            if comparison["first_difference"] is not None or not comparison["compared_unit_frames"]:
                detail["status"] = status = "failed"
                detail["unit_difference"] = comparison["first_difference"]
                detail["missing_unit_frames"] = comparison["missing_godot_unit_frames"]
                detail["extra_unit_frames"] = comparison["extra_godot_unit_frames"]
        if status == "passed" and name in team_references:
            comparison = compare_teams(team_references[name], Path(variables["RW_PROBE_PATH"]).with_suffix(".teams.tsv"))
            detail["team_trace"] = comparison
            if comparison["first_difference"] is not None or not comparison["compared_team_frames"]:
                detail["status"] = status = "failed"
        if status == "passed" and name in path_references:
            captured = [json.loads(path.read_text(encoding="utf-8")) for path in Path(variables["RW_PATH_PROBE_DIRECTORY"]).glob("*.json")]
            path_results = []
            for expected in json.loads(path_references[name].read_text(encoding="utf-8")):
                matches = [entry for entry in captured if all(entry[key] == expected[key] for key in ("frame", "start", "goal", "goal_radius", "size"))
                           and struct.pack("!f", entry["heading"]).hex() == expected["heading_bits"]]
                result = {"frame": expected["frame"], "matching_requests": len(matches), "differences": []}
                if len(matches) == 1:
                    result["differences"] = [key for key, digest in expected["cost_sha256"].items()
                                             if hashlib.sha256(bytes(value & 255 for value in matches[0][key])).hexdigest() != digest]
                if len(matches) != 1 or result["differences"]:
                    detail["status"] = status = "failed"
                path_results.append(result)
            detail["path_inputs"] = path_results
        results.append(detail)
        print(f"{name}: {status}", flush=True)
    (args.output / "summary.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    raise SystemExit(0 if all(item["status"] == "passed" for item in results) else 1)


if __name__ == "__main__":
    main()
