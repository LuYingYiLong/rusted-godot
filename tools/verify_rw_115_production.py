"""Verify production action IDs, factory menus, and native specs against RW 1.15."""

from __future__ import annotations

import argparse
import hashlib
import math
import os
import re
import subprocess
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROBE_PATH = PROJECT_ROOT / "tools/Rw115ProductionProbe.java"
CATALOG_PATH = PROJECT_ROOT / "scripts/utils/units/rw_vanilla_unit_catalog.gd"
PRODUCTION_PATH = PROJECT_ROOT / "scripts/utils/units/rw_vanilla_production_actions.gd"
SPECS_PATH = PROJECT_ROOT / "scripts/utils/units/rw_native_production_specs.gd"
ACTION_CLASS = Path("02b-decompiled/com/corrodinggames/rts/game/units/a/l.java")
ENUM_CLASS = Path("02b-decompiled/com/corrodinggames/rts/game/units/ar.java")
QUEUE_CLASS = Path("02b-decompiled/com/corrodinggames/rts/game/units/d/k.java")
BASE_UNIT_CLASS = Path("02b-decompiled/com/corrodinggames/rts/game/units/am.java")
EXPECTED_STOCK_SHA256_PREFIX = "8a550a37e2d8a543"
FACTORY_CLASSES = {
	"commandCenter": Path("02b-decompiled/com/corrodinggames/rts/game/units/d/e.java"),
	"landFactory": Path("02b-decompiled/com/corrodinggames/rts/game/units/d/m.java"),
	"airFactory": Path("02b-decompiled/com/corrodinggames/rts/game/units/d/a.java"),
	"seaFactory": Path("02b-decompiled/com/corrodinggames/rts/game/units/d/t.java"),
	"experimentalLandFactory": Path("02b-decompiled/com/corrodinggames/rts/game/units/d/f.java"),
}
EXPECTED_FACTORY_ACTIONS = {
	"commandCenter": [("builder", 1)],
	"landFactory": [
		("builder", 1), ("tank", 1), ("hoverTank", 1), ("artillery", 1),
		("hovercraft", 2), ("heavyTank", 2), ("heavyHoverTank", 2), ("laserTank", 2),
	],
	"airFactory": [("dropship", 2), ("gunShip", 2), ("amphibiousJet", 2)],
	"seaFactory": [
		("builderShip", 1), ("gunBoat", 1), ("missileShip", 1),
		("hovercraft", 1), ("battleShip", 1), ("attackSubmarine", 1),
	],
	"experimentalLandFactory": [("experimentalTank", 1), ("experimentalHoverTank", 1)],
}


def read_source(source_root: Path, relative_path: Path) -> str:
	path = source_root / relative_path
	if not path.is_file():
		raise FileNotFoundError(f"Missing 1.15 source file: {path}")
	return path.read_text(encoding="utf-8")


def source_enum(source: str) -> tuple[dict[str, str], list[str]]:
	declaration = source.split("public enum ar implements as {", 1)
	if len(declaration) != 2:
		raise ValueError("Could not locate the 1.15 native unit enum")
	entries = declaration[1].split(";", 1)[0] + ";"
	matches = re.findall(r'^\s*([A-Za-z])\("([^"]+)",\s*(\d+)\)[,;]', entries, re.MULTILINE)
	if len(matches) != 52:
		raise ValueError(f"Expected 52 native enum entries, received {len(matches)}")
	aliases: dict[str, str] = {}
	names: list[str] = []
	for index, (alias, name, ordinal) in enumerate(matches):
		if int(ordinal) != index:
			raise ValueError(f"Unexpected source ordinal for {name}: {ordinal} != {index}")
		aliases[alias] = name
		names.append(name)
	return aliases, names


def extract_method_body(source: str, signature: str) -> str:
	match = re.search(signature, source)
	if match is None:
		raise ValueError(f"Could not locate source method: {signature}")
	start = source.find("{", match.end())
	if start < 0:
		raise ValueError(f"Method has no body: {signature}")
	depth = 0
	for position in range(start, len(source)):
		if source[position] == "{":
			depth += 1
		elif source[position] == "}":
			depth -= 1
			if depth == 0:
				return source[start + 1 : position]
	raise ValueError(f"Unclosed method body: {signature}")


def source_factory_actions(source: str, aliases: dict[str, str]) -> list[str]:
	body = extract_method_body(source, r"public static strictfp void a\(ArrayList var0, int var1\)")
	entries = re.findall(r"var0\.add\(new [\w.$]+\(ar\.([A-Za-z]),\s*[\d.]+F\)\)", body)
	result: list[str] = []
	for alias in entries:
		if alias not in aliases:
			raise ValueError(f"Unknown native enum alias in factory action list: {alias}")
		result.append(aliases[alias])
	return result


def stock_binary_specs(
	game_jar: Path, java: str
) -> tuple[dict[str, tuple[float, float, int]], dict[str, str], str]:
	digest = hashlib.sha256(game_jar.read_bytes()).hexdigest()
	if not digest.startswith(EXPECTED_STOCK_SHA256_PREFIX):
		raise ValueError(f"Game jar is not the documented 1.15 stock build: {digest}")
	classpath = os.pathsep.join((str(game_jar), str(game_jar.parent / "libs" / "*")))
	completed = subprocess.run(
		[java, "--class-path", classpath, str(PROBE_PATH)],
		check=True,
		capture_output=True,
		text=True,
		encoding="utf-8",
	)
	rows = re.findall(r"^UNIT\t(\d+)\t([^\t]+)\t[^\t]+\t([^\t]+)\t([^\t]+)$", completed.stdout, re.MULTILINE)
	frame_rows = re.findall(r"^FRAMES\t([^\t]+)\t(\d+)$", completed.stdout, re.MULTILINE)
	action_rows = re.findall(r"^ACTION\t([^\t]+)\t([^\t]+)$", completed.stdout, re.MULTILINE)
	if len(rows) != 52:
		raise ValueError(f"Expected 52 stock enum rows, received {len(rows)}")
	if len(frame_rows) != 52:
		raise ValueError(f"Expected 52 stock completion frame rows, received {len(frame_rows)}")
	if len(action_rows) != 52:
		raise ValueError(f"Expected 52 binary production action IDs, received {len(action_rows)}")
	for native_name, action_id in action_rows:
		if action_id != f"u_{native_name}":
			raise ValueError(f"Stock binary action ID differs for {native_name}: {action_id}")
	production_action_ids = {native_name: action_id for native_name, action_id in action_rows}
	completion_frames: dict[str, int] = {name: int(frames) for name, frames in frame_rows}
	specs: dict[str, tuple[float, float, int]] = {}
	for expected_ordinal, (ordinal, name, cost, rate) in enumerate(rows):
		if int(ordinal) != expected_ordinal:
			raise ValueError(f"Unexpected binary ordinal for {name}: {ordinal} != {expected_ordinal}")
		specs[name] = (float(cost), float(rate), completion_frames[name])
	return specs, production_action_ids, digest


def parse_specs(source: str) -> dict[str, tuple[float, float]]:
	declaration = source.split("const SPECS: Dictionary = {", 1)
	if len(declaration) != 2:
		raise ValueError("Could not locate native production specs")
	rows = re.findall(r'^\s*"([^"]+)": \{"cost": ([\d.Ee+-]+), "rate": ([\d.Ee+-]+), "completion_frames": (\d+),\},$', declaration[1], re.MULTILINE)
	return {name: (float(cost), float(rate), int(frames)) for name, cost, rate, frames in rows}


def parse_factory_actions(source: str, producer_name: str) -> list[tuple[str, int]]:
	declaration = source.split("const NATIVE_PRODUCTION: Dictionary = {", 1)
	if len(declaration) != 2:
		raise ValueError("Could not locate project native production actions")
	producer = re.search(rf'"{re.escape(producer_name)}":\s*', declaration[1])
	if producer is None:
		raise ValueError(f"Missing project production menu for {producer_name}")
	start = declaration[1].find("[", producer.end())
	depth = 0
	end = -1
	for position in range(start, len(declaration[1])):
		if declaration[1][position] == "[":
			depth += 1
		elif declaration[1][position] == "]":
			depth -= 1
			if depth == 0:
				end = position
				break
	if start < 0 or end < 0:
		raise ValueError(f"Unclosed project production menu for {producer_name}")
	return [
		(name, int(tech))
		for name, tech in re.findall(r'\["([^"]+)",\s*(\d+),\]', declaration[1][start : end + 1])
	]


def parse_project_action_ids(catalog_source: str) -> dict[str, str]:
	declaration = catalog_source.split("const STOCK_NATIVE_ACTION_IDS: Dictionary = {", 1)
	if len(declaration) != 2:
		raise ValueError("Could not locate the project's stock action ID catalog")
	rows = re.findall(r'^\s*"([^"]+)": "([^"]+)",$', declaration[1].split("\n}", 1)[0], re.MULTILINE)
	return dict(rows)


def parse_project_replacements(catalog_source: str) -> dict[str, str]:
	declaration = catalog_source.split("const NATIVE_REPLACEMENTS: Dictionary = {", 1)
	if len(declaration) != 2:
		raise ValueError("Could not locate the project's native replacement catalog")
	rows = re.findall(r'^\s*"([^"]+)": "([^"]+)",$', declaration[1].split("\n}", 1)[0], re.MULTILINE)
	return dict(rows)


def stock_replacements(assets_root: Path) -> dict[str, str]:
	if not assets_root.is_dir():
		raise FileNotFoundError(f"Missing stock unit assets: {assets_root}")
	replacements: dict[str, str] = {}
	for path in sorted(assets_root.rglob("*.ini")):
		text = path.read_text(encoding="utf-8", errors="replace")
		name_match = re.search(r"(?im)^\s*name\s*:\s*(\S+)", text)
		replacement_match = re.search(r"(?im)^\s*overrideAndReplace\s*:\s*(\S+)", text)
		if name_match is None or replacement_match is None:
			continue
		native_name = replacement_match.group(1)
		if native_name.upper() == "NONE":
			continue
		custom_name = name_match.group(1)
		previous_name: str = replacements.get(native_name, "")
		if previous_name and previous_name != custom_name:
			raise ValueError(f"Conflicting stock replacements for {native_name}: {previous_name} and {custom_name}")
		replacements[native_name] = custom_name
	if not replacements:
		raise ValueError(f"No stock overrideAndReplace entries found in {assets_root}")
	return replacements


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--source-root", required=True, type=Path)
	parser.add_argument("--game-jar", required=True, type=Path)
	parser.add_argument("--assets-root", required=True, type=Path)
	parser.add_argument("--java", required=True)
	args = parser.parse_args()
	try:
		enum_source = read_source(args.source_root, ENUM_CLASS)
		action_source = read_source(args.source_root, ACTION_CLASS)
		queue_source = read_source(args.source_root, QUEUE_CLASS)
		base_unit_source = read_source(args.source_root, BASE_UNIT_CLASS)
		aliases, enum_names = source_enum(enum_source)
		for producer_name, source_path in FACTORY_CLASSES.items():
			factory_source = read_source(args.source_root, source_path)
			source_actions = source_factory_actions(factory_source, aliases)
			expected_actions = EXPECTED_FACTORY_ACTIONS[producer_name]
			if source_actions != [name for name, _ in expected_actions]:
				raise ValueError(f"Unexpected 1.15 {producer_name} action list: {source_actions}")
		if 'super("u_" + var1.v())' not in action_source:
			raise ValueError("Original production action does not initialize from the requested type name")
		if 'this.a("u_" + var3.v())' not in action_source:
			raise ValueError("Original production action does not replace its ID with the resolved replacement type")
		if not re.search(r"public String v\(\)\s*\{\s*return this\.name\(\);", enum_source):
			raise ValueError("Original native type v() does not return Enum.name()")
		if not re.search(r"public float e;", queue_source) or "this.e += var3;" not in queue_source or "if(this.e >= 1.0F)" not in queue_source:
			raise ValueError("Original production queue no longer matches float progress accumulation")
		if not re.search(r"public strictfp float cx\(\)\s*\{\s*return 1\.0F;", base_unit_source):
			raise ValueError("Original base unit production multiplier is not 1.0F")
		production_source = PRODUCTION_PATH.read_text(encoding="utf-8")
		for producer_name, expected_actions in EXPECTED_FACTORY_ACTIONS.items():
			runtime_actions = parse_factory_actions(production_source, producer_name)
			if runtime_actions != expected_actions:
				raise ValueError(f"Project {producer_name} menu differs from 1.15 source: {runtime_actions}")
		catalog_source = CATALOG_PATH.read_text(encoding="utf-8")
		project_action_ids = parse_project_action_ids(catalog_source)
		project_replacements = parse_project_replacements(catalog_source)
		binary_replacements = stock_replacements(args.assets_root)
		binary_specs, binary_action_ids, digest = stock_binary_specs(args.game_jar, args.java)
		if list(binary_specs) != enum_names:
			raise ValueError("Stock binary enum differs from the 1.15 source enum")
		if set(project_action_ids) != set(enum_names):
			missing = sorted(set(enum_names) - set(project_action_ids))
			extra = sorted(set(project_action_ids) - set(enum_names))
			raise ValueError(f"Project stock action ID catalog differs from the binary enum; missing={missing}, extra={extra}")
		for native_name, action_id in binary_action_ids.items():
			if project_action_ids[native_name] != action_id:
				raise ValueError(f"Project stock action ID differs for {native_name}: project={project_action_ids[native_name]} binary={action_id}")
		if project_replacements != binary_replacements:
			missing = sorted(set(binary_replacements) - set(project_replacements))
			extra = sorted(set(project_replacements) - set(binary_replacements))
			wrong = {
				native_name: (project_replacements[native_name], binary_replacements[native_name])
				for native_name in set(project_replacements) & set(binary_replacements)
				if project_replacements[native_name] != binary_replacements[native_name]
			}
			raise ValueError(f"Native replacement catalog differs from stock unit INIs: missing={missing}, extra={extra}, wrong={wrong}")
		factory_unit_names = {
			native_name
			for actions in EXPECTED_FACTORY_ACTIONS.values()
			for native_name, _ in actions
		}
		source_action_ids = {
			native_name: f"u_{alias}"
			for alias, native_name in aliases.items()
		}
		source_binary_action_mismatches = {
			native_name: (source_action_ids[native_name], binary_action_ids[native_name])
			for native_name in factory_unit_names
			if source_action_ids[native_name] != binary_action_ids[native_name]
		}
		project_specs = parse_specs(SPECS_PATH.read_text(encoding="utf-8"))
		if set(project_specs) != set(binary_specs):
			missing = sorted(set(binary_specs) - set(project_specs))
			extra = sorted(set(project_specs) - set(binary_specs))
			raise ValueError(f"Native production data coverage mismatch; missing={missing}, extra={extra}")
		for name, (expected_cost, expected_rate, expected_frames) in binary_specs.items():
			actual_cost, actual_rate, actual_frames = project_specs[name]
			if not math.isclose(actual_cost, expected_cost, rel_tol=1e-9, abs_tol=1e-9):
				raise ValueError(f"Wrong stock cost for {name}: project={actual_cost} stock={expected_cost}")
			if not math.isclose(actual_rate, expected_rate, rel_tol=1e-9, abs_tol=1e-9):
				raise ValueError(f"Wrong stock rate for {name}: project={actual_rate} stock={expected_rate}")
			if actual_frames != expected_frames:
				raise ValueError(f"Wrong stock float32 completion frames for {name}: project={actual_frames} stock={expected_frames}")
	except (FileNotFoundError, OSError, ValueError, subprocess.CalledProcessError) as error:
		print(f"RW_115_PRODUCTION_ERROR {error}")
		return 1

	print(f"RW_115_PRODUCTION_SOURCE_OK factory_menus={len(EXPECTED_FACTORY_ACTIONS)} enum_identifiers=decompiled_aliases")
	print(f"RW_115_PRODUCTION_BINARY_OK native_specs={len(binary_specs)} native_enum_ids=stock_runtime_enum_names sha256={digest}")
	print(f"RW_115_PRODUCTION_PROJECT_IDS_OK native_types={len(project_action_ids)} factory_types={len(factory_unit_names)} source_action_class=UnitBuildAction replacement_ids=resolved_type_names")
	print(f"RW_115_PRODUCTION_REPLACEMENTS_OK mappings={len(project_replacements)} source=stock_unit_ini_overrideAndReplace")
	if source_binary_action_mismatches:
		mismatch_text = ",".join(
			f"{name}:{source_id}->{binary_id}"
			for name, (source_id, binary_id) in sorted(source_binary_action_mismatches.items())
		)
		print(f"RW_115_PRODUCTION_SOURCE_ALIAS_MAP {mismatch_text}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
