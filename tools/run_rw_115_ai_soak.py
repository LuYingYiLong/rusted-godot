"""Run a stock Rusted Warfare 1.15 AI room with the Godot multiplayer probe.

The game runs from a writable copy. The installed game is only read, and its
original game-lib.jar hash is checked before the test starts.
"""

from __future__ import annotations

import argparse
from collections import Counter
from contextlib import ExitStack
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time

from rw_115_debug_socket import DebugSession
from compare_rw_115_unit_traces import compare, compare_teams


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Rusted Warfare")
RUNTIME_ROOT = Path(r"C:\Users\Administrator\Documents\Codex\rw115-probe\RustedWarfare")
GODOT_EXECUTABLE = Path(r"C:\Users\Administrator\Documents\Godot\Godot_v4.7.2-stable_win64.exe")
STOCK_JAR_SHA256 = "8a550a37e2d8a5430866090d4e7d5892f9010b47f52a5a09350fc66c620deec9"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def prepare_runtime(source: Path, runtime: Path) -> None:
    source_jar = source / "game-lib.jar"
    if not source_jar.is_file() or sha256(source_jar) != STOCK_JAR_SHA256:
        raise RuntimeError("Installed game-lib.jar does not match stock Rusted Warfare 1.15")
    runtime.mkdir(parents=True, exist_ok=True)
    target_jar = runtime / "game-lib.jar"
    if not target_jar.is_file():
        shutil.copy2(source_jar, target_jar)
    if sha256(target_jar) != STOCK_JAR_SHA256:
        raise RuntimeError("Isolated game-lib.jar does not match stock Rusted Warfare 1.15")
    for directory in ("assets", "res", "font", "libs"):
        if not (runtime / directory).is_dir():
            shutil.copytree(source / directory, runtime / directory)
    for library in source.glob("*.dll"):
        target = runtime / library.name
        if not target.is_file():
            shutil.copy2(library, target)
    (runtime / "mods").mkdir(exist_ok=True)


def port_is_available(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as check:
        try:
            check.bind(("0.0.0.0", port))
        except OSError:
            return False
    return True


def build_original_probe(output: Path, java_runtime: Path) -> Path:
    """Build the read-only frame-end agent for the bundled Java 13 runtime."""
    javac = shutil.which("javac")
    if javac is None:
        candidates = sorted((Path.home() / ".jdks").glob("*/bin/javac.exe"))
        if not candidates:
            raise RuntimeError("--original-trace requires a JDK with javac")
        javac = str(candidates[-1])
    build = output / "agent-build"
    build.mkdir()
    source = PROJECT_ROOT / "tools" / "probe" / "Rw115UnitProbeAgent.java"
    compilation = subprocess.run([
        javac, "-source", "11", "-target", "11", "-Xlint:-options", "-encoding", "UTF-8",
        "--system", str(java_runtime),
        "--add-exports", "java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED",
        "-d", str(build), str(source),
    ], capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    if compilation.returncode != 0:
        raise RuntimeError("Original probe compilation failed: " + compilation.stderr.decode("utf-8", errors="replace"))
    import zipfile

    jar = output / "rw115-unit-probe.jar"
    with zipfile.ZipFile(jar, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\nPremain-Class: Rw115UnitProbeAgent\n\n")
        for compiled in sorted(build.glob("*.class")):
            archive.write(compiled, compiled.name)
    return jar


def debug_call(port: int, expression: str) -> str:
    with DebugSession(port) as session:
        return session.call(expression).strip()


def wait_for_debug(process: subprocess.Popen[bytes], port: int, timeout: int) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"Original game exited during startup: {process.returncode}")
        try:
            version = debug_call(port, "root.getVersionName()")
            screen = debug_call(port, "root.getCurrentDocumentPath()")
            if version == "v1.15" and screen == "mainMenu.rml":
                return
        except (OSError, RuntimeError):
            pass
        time.sleep(1.0)
    raise TimeoutError("Original game did not reach its main menu")


def report_has_event(path: Path, event_name: str, message: str = "") -> bool:
    if not path.is_file():
        return False
    with path.open("r", encoding="utf-8") as stream:
        for line in stream:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if event.get("event") == event_name and (not message or message in event.get("message", "")):
                return True
    return False


def original_trace_failure(output: Path, minimum_frame: int = 1) -> str | None:
    failure = output / "original-probe-failure.txt"
    if failure.is_file():
        return failure.read_text(encoding="utf-8", errors="replace")
    log = (output / "original.stdout.log").read_text(encoding="utf-8", errors="replace")
    if "RW115 probe hooked main-thread simulation frame end" not in log:
        return "Original frame-end hook was not installed"
    trace = output / "original-units.csv"
    last_frame = 0
    if trace.is_file():
        with trace.open("rb") as stream:
            stream.seek(max(0, trace.stat().st_size - 8192))
            for line in reversed(stream.read().splitlines()):
                first = line.partition(b",")[0]
                if first.isdigit():
                    last_frame = int(first)
                    break
    if last_frame < minimum_frame:
        return f"Original trace reached only frame {last_frame}; expected at least {minimum_frame}"
    return None


class ReportCursor:
    """Read only complete new JSONL records while the Godot process appends them."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.offset = 0

    def read(self) -> list[dict[str, object]]:
        if not self.path.is_file():
            return []
        events: list[dict[str, object]] = []
        with self.path.open("rb") as stream:
            stream.seek(self.offset)
            while line := stream.readline():
                if not line.endswith(b"\n"):
                    break
                self.offset = stream.tell()
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
        return events


def wait_for_event(
    path: Path,
    event_name: str,
    message: str,
    client: subprocess.Popen[bytes],
    host: subprocess.Popen[bytes],
    timeout: int,
) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if report_has_event(path, event_name, message):
            return
        if client.poll() is not None:
            raise RuntimeError(f"Godot client exited before {event_name}: {client.returncode}")
        if host.poll() is not None:
            raise RuntimeError(f"Original host exited before {event_name}: {host.returncode}")
        time.sleep(0.5)
    raise TimeoutError(f"Timed out waiting for Godot {event_name}")


def collect_summary(report_path: Path, metadata: dict[str, object], godot_exit: int) -> dict[str, object]:
    counts: Counter[str] = Counter()
    mismatch_fields: Counter[str] = Counter()
    first_difference: dict[str, object] | None = None
    first_full_checksum_difference: dict[str, object] | None = None
    first_field_difference: dict[str, int] = {}
    last_sample: dict[str, object] | None = None
    total_commands = 0
    pending_future_checksums = 0
    legacy_future_checksums = 0
    with report_path.open("r", encoding="utf-8") as stream:
        for line in stream:
            event = json.loads(line)
            name = str(event.get("event", ""))
            counts[name] += 1
            if name == "checksum_pending_at_end" or (name == "checksum_unverified" and event.get("reason") == "pending_at_end"):
                pending_future_checksums += 1
                if name == "checksum_unverified":
                    legacy_future_checksums += 1
            if name == "commands":
                total_commands += len(event.get("commands", []))
            elif name == "sample":
                last_sample = event
            elif name == "checksum_unit_mismatch" and first_difference is None:
                first_difference = {
                    "frame": event.get("frame"),
                    "fields": sorted(event.get("differences", {}).keys()),
                    "differences": event.get("differences", {}),
                }
            if name == "checksum_unit_mismatch":
                frame = int(event.get("frame", -1))
                for field in event.get("differences", {}):
                    mismatch_fields[field] += 1
                    first_field_difference.setdefault(field, frame)
                if "checksum" in event.get("differences", {}) and first_full_checksum_difference is None:
                    first_full_checksum_difference = {
                        "frame": frame,
                        "fields": sorted(event["differences"].keys()),
                    }
    return {
        **metadata,
        "status": "completed" if counts["transport_completed"] and godot_exit == 0 else "failed",
        "godot_exit_code": godot_exit,
        "event_counts": dict(counts),
        "checksums_complete": counts["checksum_unverified"] == legacy_future_checksums,
        "verified_checksum_count": counts["checksum_unit_match"] + counts["checksum_unit_mismatch"],
        "unverified_checksum_count": counts["checksum_unverified"] - legacy_future_checksums,
        "pending_future_checksum_count": pending_future_checksums,
        "total_commands": total_commands,
        "last_frame": last_sample.get("frame") if last_sample else None,
        "last_unit_count": last_sample.get("units") if last_sample else None,
        "first_difference": first_difference,
        "first_full_checksum_difference": first_full_checksum_difference,
        "first_field_difference_frames": first_field_difference,
        "mismatch_field_counts": dict(mismatch_fields),
    }


def collect_original_metrics(path: Path) -> dict[str, object]:
    samples = 0
    last: dict[str, object] = {}
    maximum = {"desync_errors": 0, "resyncs": 0}
    with path.open("r", encoding="utf-8") as stream:
        for line in stream:
            sample = json.loads(line)
            samples += 1
            last = sample
            for field in maximum:
                value = sample.get(field)
                if isinstance(value, int):
                    maximum[field] = max(maximum[field], value)
    return {"samples": samples, "last": last, "maximum": maximum}


def run(arguments: argparse.Namespace) -> Path:
    source = arguments.source.resolve()
    runtime = arguments.runtime.resolve()
    godot = arguments.godot.resolve()
    if not godot.is_file():
        raise FileNotFoundError(godot)
    if not 1 <= arguments.ai <= 8:
        raise ValueError("AI count must be between 1 and 8")
    capacity = re.search(r"\[[^\]]*p(\d+)\]", arguments.map)
    if capacity and arguments.ai + 2 > int(capacity.group(1)):
        raise ValueError("Map has fewer player slots than host + AI + Godot")
    if not 1 <= arguments.port <= 65535 or not 1 <= arguments.debug_port <= 65535:
        raise ValueError("Ports must be between 1 and 65535")
    if arguments.port == arguments.debug_port:
        raise ValueError("Room and debug ports must differ")
    if "'" in arguments.map or "\n" in arguments.map:
        raise ValueError("Map name contains unsupported debug expression characters")
    if not (source / "assets" / "maps" / "skirmish" / arguments.map).is_file():
        raise FileNotFoundError(f"Stock skirmish map not found: {arguments.map}")
    if not port_is_available(arguments.port) or not port_is_available(arguments.debug_port):
        raise RuntimeError("Room or debug port is already in use")
    prepare_runtime(source, runtime)
    java = source / "jvm64" / "bin" / "java.exe"
    if not java.is_file():
        raise FileNotFoundError(java)

    run_id = datetime.now().strftime("%Y%m%d-%H%M%S")
    output = arguments.output / f"rw115-ai-soak-{run_id}"
    output.mkdir(parents=True, exist_ok=False)
    report = output / "godot.jsonl"
    control = output / "stop-request.txt"
    stage_report = output / "stages.jsonl"
    duration = arguments.stages[-1]
    metadata: dict[str, object] = {
        "source": "stock Rusted Warfare v1.15",
        "stock_jar_sha256": STOCK_JAR_SHA256,
        "map": arguments.map,
        "ai_count": arguments.ai,
        "room_address": f"127.0.0.1:{arguments.port}",
        "duration_seconds": duration,
        "stage_seconds": arguments.stages,
        "trace_interval_frames": arguments.trace_interval,
        "original_frame_end_trace": arguments.original_trace,
        "original_object_id_trace": arguments.original_trace,
        "original_weapon_catalog": arguments.weapon_catalog,
        "original_projectile_trace": arguments.projectile_trace,
        "full_unit_trace_comparison": arguments.original_trace and arguments.trace_interval == 1 and not arguments.trace_units,
        "trace_through_first_mismatch": arguments.trace_through_first_mismatch,
        "stage_time_basis": "verified_simulation_seconds",
        "output_directory": str(output),
    }
    (output / "run.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    java_args = [
        str(java), "-Xmx1000M", "-Dfile.encoding=UTF-8", "-Djava.library.path=.",
        "-cp", "game-lib.jar;libs/*", "com.corrodinggames.rts.java.Main",
        "-nodisplay", "-nosound", "-nomusic", "-nomods",
        "-debug", f"{arguments.debug_port}:local",
    ]
    if arguments.original_trace:
        probe_jar = build_original_probe(output, java.parent.parent)
        java_args[1:1] = [
            "--add-exports", "java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED",
            f"-javaagent:{probe_jar}={output / 'original-units.csv'}",
        ]
    godot_args = [str(godot), "--headless", "--path", str(PROJECT_ROOT), "--scene", "res://tests/rw_multiplayer_soak.tscn"]
    environment = os.environ.copy()
    roaming_data = output / "godot-user-data" / "Roaming"
    local_data = output / "godot-user-data" / "Local"
    roaming_data.mkdir(parents=True)
    local_data.mkdir(parents=True)
    environment["APPDATA"] = str(roaming_data)
    environment["LOCALAPPDATA"] = str(local_data)
    environment.update({
        "RW_SOAK_ADDRESS": f"127.0.0.1:{arguments.port}",
        "RW_SOAK_EXPECT_MAP": arguments.map.split("]", 1)[-1].split("(", 1)[0].strip(),
        "RW_SOAK_MIN_PLAYERS": str(arguments.ai + 2),
        "RW_SOAK_DURATION": str(duration * 4 + 60),
        "RW_SOAK_CONTROL_PATH": str(control),
        "RW_SOAK_START_TIMEOUT": str(arguments.start_timeout),
        "RW_SOAK_REPORT_PATH": str(report),
        "RW_PROBE_CHECKSUMS": "1",
        "RW_PROBE_CHECKSUM_STRIDE": "301",
        "RW_PROBE_PATH": str(output / "godot.tsv"),
        "RW_PROBE_PROJECTILES": str(output / "godot-projectiles.jsonl") if arguments.projectile_trace else "",
        "RW_PROBE_INTERVAL": str(arguments.trace_interval),
        "RW_PROBE_UNIT_IDS": arguments.trace_units,
    })
    host_environment = environment
    if arguments.weapon_catalog:
        host_environment = environment | {"RW115_WEAPON_CATALOG": str(output / "original-weapons.jsonl")}
    if arguments.projectile_trace:
        host_environment = host_environment | {"RW115_PROJECTILE_TRACE": str(output / "original-projectiles.jsonl")}

    host: subprocess.Popen[bytes] | None = None
    client: subprocess.Popen[bytes] | None = None
    with ExitStack() as stack:
        host_out = stack.enter_context((output / "original.stdout.log").open("wb"))
        host_err = stack.enter_context((output / "original.stderr.log").open("wb"))
        godot_out = stack.enter_context((output / "godot.stdout.log").open("wb"))
        godot_err = stack.enter_context((output / "godot.stderr.log").open("wb"))
        metrics = stack.enter_context((output / "original-metrics.jsonl").open("w", encoding="utf-8"))
        try:
            host = subprocess.Popen(java_args, cwd=runtime, env=host_environment, stdout=host_out, stderr=host_err, creationflags=creation_flags)
            print(f"Original v1.15 PID={host.pid}; waiting for main menu", flush=True)
            wait_for_debug(host, arguments.debug_port, arguments.startup_timeout)
            with DebugSession(arguments.debug_port) as session:
                if session.call(f"debug.networkSetPortNumber({arguments.port})").strip() != "true":
                    raise RuntimeError("Could not set original server port")
                session.call("root.hostStartWithPasswordAndMods(false,null,false)")
                if session.call("debug.isNetworkGameActive()").strip() != "true":
                    raise RuntimeError("Original server did not enter network mode")
                session.call(f"debug.setMultiplayerMap(0,'{arguments.map}')")
                for _ in range(arguments.ai):
                    session.call("mp.addAI()")
                count = int(session.call("debug.numberOfPlayersPlusAI()").strip())
                if count != arguments.ai + 1:
                    raise RuntimeError(f"Expected {arguments.ai + 1} original players, found {count}")
            print(f"Room ready: 127.0.0.1:{arguments.port}, {arguments.ai} AI, map={arguments.map}", flush=True)
            client = subprocess.Popen(godot_args, cwd=PROJECT_ROOT, env=environment, stdout=godot_out, stderr=godot_err, creationflags=creation_flags)
            wait_for_event(report, "connection", "Entered a vanilla non-mod room", client, host, arguments.room_timeout)
            with DebugSession(arguments.debug_port) as session:
                count = int(session.call("debug.numberOfPlayersPlusAI()").strip())
                if count != arguments.ai + 2:
                    raise RuntimeError(f"Godot joined, but original host has {count} players")
                session.call("mp.multiplayerStart()")
            wait_for_event(report, "game_started", "", client, host, arguments.start_timeout)
            print("Battle started; collecting original metrics and Godot checksums", flush=True)
            started = time.monotonic()
            next_sample = 0.0
            stage_index = 0
            stage_results: list[dict[str, object]] = []
            report_cursor = ReportCursor(report)
            verified_checksums = 0
            parity_failure: dict[str, object] | None = None
            stop_requested = False
            last_verified_frame = 0
            last_verified_seconds = 0.0
            while client.poll() is None:
                if host.poll() is not None:
                    raise RuntimeError(f"Original host exited during battle: {host.returncode}")
                elapsed = time.monotonic() - started
                for event in report_cursor.read():
                    event_name = event.get("event")
                    if event_name in ("checksum_unit_match", "checksum_unit_mismatch"):
                        verified_checksums += 1
                        last_verified_frame = max(last_verified_frame, int(event.get("frame", 0)))
                        last_verified_seconds = max(last_verified_seconds, float(event.get("simulated_seconds", -1.0)))
                    if event_name in ("checksum_unit_mismatch", "checksum_unverified", "failed") and parity_failure is None:
                        parity_failure = {
                            "event": event_name,
                            "frame": event.get("frame"),
                            "differences": event.get("differences", {}),
                            "reason": event.get("reason", ""),
                        }
                if elapsed >= next_sample:
                    sample: dict[str, object] = {"elapsed_seconds": round(elapsed, 1), "verified_simulation_seconds": last_verified_seconds}
                    try:
                        with DebugSession(arguments.debug_port) as session:
                            for key, expression in (
                                ("players", "debug.numberOfPlayersPlusAI()"),
                                ("connections", "debug.numberOfPlayerConnections()"),
                                ("desync_errors", "debug.getNumberOfDesyncErrors()"),
                                ("desync_passes", "debug.getNumberOfDesyncPasses()"),
                                ("resyncs", "debug.getNumberOfResyncSendsOrRecv()"),
                            ):
                                sample[key] = int(session.call(expression).strip())
                    except (OSError, RuntimeError, ValueError) as error:
                        sample["error"] = str(error)
                    metrics.write(json.dumps(sample) + "\n")
                    metrics.flush()
                    print(f"t={elapsed:.0f}s players={sample.get('players')} desync={sample.get('desync_errors')} resync={sample.get('resyncs')}", flush=True)
                    if (sample.get("desync_errors", 0) or sample.get("resyncs", 0)) and parity_failure is None:
                        parity_failure = {"event": "original_desync_or_resync", "sample": sample}
                    next_sample += arguments.metrics_interval
                if arguments.original_trace and verified_checksums > 0 and parity_failure is None:
                    probe_failure = original_trace_failure(output, last_verified_frame)
                    if probe_failure:
                        parity_failure = {"event": "original_probe_failed", "reason": probe_failure}
                if parity_failure is not None and not stop_requested and not arguments.trace_through_first_mismatch:
                    stop_requested = True
                    control.write_text("parity_difference\n", encoding="utf-8")
                    result = {"stage_seconds": arguments.stages[stage_index], "status": "failed", "elapsed_seconds": round(elapsed, 1), "failure": parity_failure}
                    stage_results.append(result)
                    stage_report.write_text(json.dumps(result) + "\n", encoding="utf-8")
                    print(f"Parity difference; stopping before the {arguments.stages[stage_index]}s gate: {parity_failure}", flush=True)
                elif not stop_requested and stage_index < len(arguments.stages) and last_verified_seconds + 1e-6 >= arguments.stages[stage_index]:
                    if verified_checksums == 0:
                        parity_failure = {"event": "no_verified_checksums"}
                        continue
                    if metadata["full_unit_trace_comparison"] and not (arguments.trace_through_first_mismatch and parity_failure is not None):
                        unit_comparison = compare(output, max_frame=last_verified_frame)
                        team_comparison = compare_teams(output / "original-teams.csv", output / "godot.teams.tsv", last_verified_frame)
                        (output / f"team-differences-{arguments.stages[stage_index]}s.json").write_text(json.dumps(team_comparison, indent=2), encoding="utf-8")
                        if team_comparison["first_difference"] is not None or not team_comparison["compared_team_frames"]:
                            parity_failure = {"event": "team_trace_mismatch", "frame": last_verified_frame, "team_trace": team_comparison}
                            continue
                        (output / f"unit-differences-{arguments.stages[stage_index]}s.json").write_text(json.dumps(unit_comparison, indent=2), encoding="utf-8")
                        if unit_comparison["first_difference"] is not None or not unit_comparison["compared_unit_frames"]:
                            parity_failure = {"event": "unit_trace_mismatch", "frame": last_verified_frame,
                                              "first_difference": unit_comparison["first_difference"],
                                              "missing_unit_frames": unit_comparison["missing_godot_unit_frames"],
                                              "extra_unit_frames": unit_comparison["extra_godot_unit_frames"]}
                            continue
                    result = {"stage_seconds": arguments.stages[stage_index], "status": "diagnostic_complete" if arguments.trace_through_first_mismatch and parity_failure is not None else "passed", "elapsed_seconds": round(elapsed, 1), "verified_checksums": verified_checksums,
                              "verified_simulation_seconds": last_verified_seconds, "last_verified_frame": last_verified_frame}
                    stage_results.append(result)
                    with stage_report.open("a", encoding="utf-8") as stream:
                        stream.write(json.dumps(result) + "\n")
                    print(f"Stage {arguments.stages[stage_index]}s passed ({verified_checksums} verified checksums)", flush=True)
                    stage_index += 1
                    if stage_index == len(arguments.stages):
                        stop_requested = True
                        control.write_text("stage_complete\n", encoding="utf-8")
                time.sleep(1.0)
            summary = collect_summary(report, metadata, client.returncode or 0)
            summary["original_metrics"] = collect_original_metrics(output / "original-metrics.jsonl")
            summary["stages"] = stage_results
            summary["requested_duration_reached"] = stage_index == len(arguments.stages)
            if metadata["full_unit_trace_comparison"] and verified_checksums > 0:
                unit_comparison = compare(output, max_frame=last_verified_frame)
                (output / "unit-differences.json").write_text(json.dumps(unit_comparison, indent=2), encoding="utf-8")
                summary["unit_trace_comparison"] = {key: value for key, value in unit_comparison.items() if key != "first_difference_per_unit"}
                team_comparison = compare_teams(output / "original-teams.csv", output / "godot.teams.tsv", last_verified_frame)
                summary["team_trace_comparison"] = team_comparison
                (output / "team-differences.json").write_text(json.dumps(team_comparison, indent=2), encoding="utf-8")
            summary["parity_status"] = "diagnostic_mismatch_recorded" if arguments.trace_through_first_mismatch and parity_failure is not None else ("failed" if parity_failure is not None else ("passed" if stage_index == len(arguments.stages) else "incomplete"))
            (output / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
            print(f"Status={summary['status']} frame={summary['last_frame']} commands={summary['total_commands']}", flush=True)
            if summary["first_difference"]:
                print(f"First parity difference: {summary['first_difference']}", flush=True)
            if summary["status"] != "completed":
                raise RuntimeError(f"Godot soak did not complete; see {output}")
            if arguments.trace_through_first_mismatch and summary["status"] == "completed":
                print(f"Diagnostic run ended; recorded parity status={summary['parity_status']}; requested_duration_reached={summary['requested_duration_reached']}; see {output}")
                return output
            if summary["parity_status"] != "passed":
                raise RuntimeError(f"Parity gate {summary['parity_status']}; see {output}")
            return output
        finally:
            for process in (client, host):
                if process is not None and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=10)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE_ROOT)
    parser.add_argument("--runtime", type=Path, default=RUNTIME_ROOT)
    parser.add_argument("--godot", type=Path, default=GODOT_EXECUTABLE)
    parser.add_argument("--output", type=Path, default=RUNTIME_ROOT / "probe-output")
    parser.add_argument("--map", default="[p6]Valley Pass (6p).tmx")
    parser.add_argument("--ai", type=int, default=4)
    parser.add_argument("--port", type=int, default=5125)
    parser.add_argument("--debug-port", type=int, default=5678)
    parser.add_argument("--stages", default="300,600,1200,1800", help="Cumulative parity gates in seconds")
    parser.add_argument("--duration", type=int, help="Run one fixed-duration gate instead of staged gates")
    parser.add_argument("--trace-interval", type=int, default=120)
    parser.add_argument("--trace-units", default="", help="Comma-separated unit IDs for high-frequency Godot tracing")
    parser.add_argument("--original-trace", action="store_true", help="Capture stock unit states on the simulation thread at every frame end")
    parser.add_argument("--weapon-catalog", action="store_true", help="Probe each stock unit turret once and record native projectile parameters; requires --original-trace")
    parser.add_argument("--projectile-trace", action="store_true", help="Record every live original and Godot projectile at each simulation frame end; requires --original-trace")
    parser.add_argument("--trace-through-first-mismatch", action="store_true", help="Continue collecting object and unit traces until the requested duration after a parity mismatch; diagnostic only")
    parser.add_argument("--metrics-interval", type=int, default=30)
    parser.add_argument("--startup-timeout", type=int, default=90)
    parser.add_argument("--room-timeout", type=int, default=45)
    parser.add_argument("--start-timeout", type=int, default=90)
    arguments = parser.parse_args()
    try:
        arguments.stages = [arguments.duration] if arguments.duration is not None else [int(value) for value in arguments.stages.split(",")]
    except ValueError:
        parser.error("Stages must be comma-separated positive integers")
    if not arguments.stages or any(value <= 0 for value in arguments.stages) or arguments.stages != sorted(set(arguments.stages)):
        parser.error("Stages must be strictly increasing positive seconds")
    if arguments.trace_interval <= 0 or arguments.metrics_interval <= 0:
        parser.error("Sampling intervals must be positive")
    if arguments.weapon_catalog and not arguments.original_trace:
        parser.error("--weapon-catalog requires --original-trace")
    if arguments.projectile_trace and not arguments.original_trace:
        parser.error("--projectile-trace requires --original-trace")
    try:
        print(f"Output: {run(arguments)}")
    except (OSError, RuntimeError, TimeoutError, ValueError) as error:
        print(f"RW115_AI_SOAK_FAILED: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
