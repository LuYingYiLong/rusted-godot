"""Capture stock 1.15 frame and movement state from an existing replay."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from rw_115_debug_socket import DebugSession
from run_rw_115_ai_soak import (
    RUNTIME_ROOT, SOURCE_ROOT, STOCK_JAR_SHA256, build_original_probe,
    original_trace_failure, port_is_available, prepare_runtime, wait_for_debug,
)


def last_frame(path: Path) -> int:
    if not path.is_file():
        return 0
    with path.open("rb") as stream:
        stream.seek(max(0, path.stat().st_size - 8192))
        lines = stream.read().splitlines()
    for line in reversed(lines):
        first = line.partition(b",")[0]
        if first.isdigit():
            return int(first)
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("replay", type=Path)
    parser.add_argument("--output", type=Path, default=RUNTIME_ROOT / "probe-output")
    parser.add_argument("--frame-limit", type=int, default=1505)
    parser.add_argument("--step-unit", type=int)
    parser.add_argument("--step-first-frame", type=int, default=0)
    parser.add_argument("--step-last-frame", type=int, default=2147483647)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--debug-port", type=int, default=5689)
    args = parser.parse_args()
    if not args.replay.is_file():
        raise FileNotFoundError(args.replay)
    if not port_is_available(args.debug_port):
        raise RuntimeError("Debug port is already in use")
    prepare_runtime(SOURCE_ROOT, RUNTIME_ROOT)
    output = args.output / datetime.now().strftime("rw115-replay-%Y%m%d-%H%M%S")
    output.mkdir(parents=True)
    java_runtime = SOURCE_ROOT / "jvm64"
    agent = build_original_probe(output, java_runtime)
    # 用本次测试独占的 ASCII 名称，避免调试协议或字体影响录像选择
    replay_name = output.name + ".replay"
    isolated_replay = RUNTIME_ROOT / "replays" / replay_name
    isolated_replay.parent.mkdir(exist_ok=True)
    shutil.copy2(args.replay, isolated_replay)
    trace = output / "original-units.csv"
    command = [
        str(java_runtime / "bin/java.exe"), "-Xmx1000M", "-Dfile.encoding=UTF-8",
        "-Djava.library.path=.", "--add-exports",
        "java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED",
        f"-javaagent:{agent}={trace}", "-cp", "game-lib.jar;libs/*",
        "com.corrodinggames.rts.java.Main", "-nodisplay", "-nosound", "-nomusic",
        "-nomods", "-debug", f"{args.debug_port}:local",
    ]
    environment = os.environ.copy()
    if args.step_unit is not None:
        environment.update({
            "RW115_STEP_UNIT": str(args.step_unit),
            "RW115_STEP_FIRST_FRAME": str(args.step_first_frame),
            "RW115_STEP_LAST_FRAME": str(args.step_last_frame),
        })
    process = None
    result = {"source_replay": str(args.replay), "stock_jar_sha256": STOCK_JAR_SHA256, "status": "incomplete"}
    try:
        with (output / "original.stdout.log").open("wb") as stdout, (output / "original.stderr.log").open("wb") as stderr:
            process = subprocess.Popen(command, cwd=RUNTIME_ROOT, env=environment, stdout=stdout, stderr=stderr,
                                       creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            wait_for_debug(process, args.debug_port, 60)
            with DebugSession(args.debug_port) as session:
                session.call(f"root.loadReplay('{replay_name}')")
            print(f"Replay loaded; capturing through frame {args.frame_limit}: {output}", flush=True)
            deadline = time.monotonic() + args.timeout
            while last_frame(trace) < args.frame_limit:
                if (output / "original-probe-failure.txt").is_file():
                    raise RuntimeError("Original probe failed: " + (output / "original-probe-failure.txt").read_text(encoding="utf-8"))
                if process.poll() is not None:
                    raise RuntimeError(f"Original replay process exited: {process.returncode}")
                if time.monotonic() > deadline:
                    raise TimeoutError(f"Replay capture stopped at frame {last_frame(trace)}")
                time.sleep(0.5)
            stdout.flush()
            stderr.flush()
            failure = original_trace_failure(output, args.frame_limit)
            if failure:
                raise RuntimeError(failure)
            result.update({"status": "completed", "last_frame": last_frame(trace)})
            print(f"Captured frame {result['last_frame']}: {output}", flush=True)
    except Exception as failure:
        result.update({"status": "failed", "reason": str(failure), "last_frame": last_frame(trace)})
        raise
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        isolated_replay.unlink(missing_ok=True)
        (output / "summary.json").write_text(json.dumps(result, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
