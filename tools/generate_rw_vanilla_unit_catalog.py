"""Generate a source-backed catalog of RWX native and bundled custom units."""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from functools import lru_cache
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = PROJECT_ROOT / "scripts/utils/units/rw_vanilla_unit_catalog.gd"
DOCUMENT_PATH = PROJECT_ROOT / "docs/vanilla_unit_catalog.md"
ENUM_PATH = Path("core/src/main/java/com/corrodinggames/rts/game/units/UnitTypeEnum.java")
UNIT_DIRECTORY = Path("assets/units")
NATIVE_PATTERN = re.compile(r"^    ([A-Za-z][A-Za-z0-9_]*) \{", re.MULTILINE)
ENTRY_PATTERN = re.compile(r"^\s*([^:=]+?)\s*[:=]\s*(.*?)\s*$")
HASH_PATTERN = re.compile(r'^\s*"([^"]+)":\s*-?\d+,?$', re.MULTILINE)
DEFINITION_PATTERN = re.compile(r"\b[A-Za-z_]+\.unit_name\s*=\s*\"([^\"]+)\"")
SPEC_PATTERN = re.compile(r'^\s*"([^"]+)":\s*\{"index":', re.MULTILINE)
SENTINELS = {"", "NONE", "IGNORE", "NULL"}


def read_native_types(rwx_root: Path) -> list[str]:
    path = rwx_root / ENUM_PATH
    names = NATIVE_PATTERN.findall(path.read_text(encoding="utf-8"))
    if not names or len(names) != len(set(names)):
        raise ValueError(f"Invalid native unit enum: {path}")
    return names


@lru_cache(maxsize=None)
def read_effective_core(path: Path) -> dict[str, str]:
    section = ""
    own_core: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].casefold()
            continue
        if section != "core" or not line or line.startswith(("#", ";")):
            continue
        match = ENTRY_PATTERN.match(line)
        if match is not None:
            own_core[match.group(1).strip().casefold()] = match.group(2).strip()
    inherited: dict[str, str] = {}
    for source in own_core.get("copyfrom", "").split(","):
        source = source.strip()
        if not source:
            continue
        parent_path = path.parent / source
        if not parent_path.is_file():
            raise FileNotFoundError(f"Missing core copyFrom: {path} -> {source}")
        inherited.update(read_effective_core(parent_path))
    inherited.update(own_core)
    return inherited


def read_ini(path: Path) -> dict[str, object] | None:
    section = ""
    core: dict[str, str] = {}
    upgrades: list[str] = []
    temporary_forms: list[str] = []
    upgraded_from: list[str] = []
    for raw_line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].casefold()
            continue
        if not line or line.startswith(("#", ";")) or section.startswith("comment_"):
            continue
        match = ENTRY_PATTERN.match(line)
        if match is None:
            continue
        key, value = match.group(1).strip().casefold(), match.group(2).strip()
        if section == "core":
            core[key] = value
        if key == "convertto" or (
            section == "core" and re.fullmatch(r"action_.+_convertto", key)
        ):
            if value.upper() not in SENTINELS and value not in upgrades:
                upgrades.append(value)
        if key == "whenbuilding_temporarilyconvertto":
            if value.upper() not in SENTINELS and value not in temporary_forms:
                temporary_forms.append(value)
        if section == "ai" and key == "upgradedfrom":
            if value.upper() not in SENTINELS and value not in upgraded_from:
                upgraded_from.append(value)

    name = core.get("name", "")
    if core.get("dont_load", "").casefold() == "true" or name.upper() in SENTINELS:
        return None
    effective_core = read_effective_core(path)
    built_from = [
        (int(match.group(1)), value)
        for key, value in effective_core.items()
        if (match := re.fullmatch(r"builtfrom_(\d+)_name", key))
        and value.upper() not in SENTINELS
    ]
    built_from.sort()
    tech_level = effective_core.get("techlevel", "")
    if tech_level and not tech_level.isdecimal():
        raise ValueError(f"Invalid techLevel in {path}: {tech_level}")
    replacement = effective_core.get("overrideandreplace", "")
    return {
        "name": name,
        "path": path,
        "replaces": "" if replacement.upper() in SENTINELS else replacement,
        "tech_level": int(tech_level) if tech_level else 0,
        "built_from": [value for _, value in built_from],
        "converts_to": upgrades,
        "temporary_forms": temporary_forms,
        "upgraded_from": upgraded_from,
    }


def read_builtin_units(rwx_root: Path, native_types: list[str]) -> dict[str, dict[str, object]]:
    unit_root = rwx_root / UNIT_DIRECTORY
    native_lookup = {name.casefold(): name for name in native_types}
    units: dict[str, dict[str, object]] = {}
    for path in sorted(unit_root.rglob("*.ini")):
        unit = read_ini(path)
        if unit is None:
            continue
        name = str(unit.pop("name"))
        if name in units:
            raise ValueError(f"Duplicate bundled unit name: {name}")
        unit["source"] = (UNIT_DIRECTORY / path.relative_to(unit_root)).as_posix()
        unit.pop("path")
        replacement = str(unit["replaces"])
        if replacement and replacement not in native_types:
            raise ValueError(f"Unknown overrideAndReplace target: {name} -> {replacement}")
        units[name] = unit

    custom_lookup = {name.casefold(): name for name in units}
    if len(custom_lookup) != len(units):
        raise ValueError("Bundled unit names differ only in letter case")
    replacements = [str(unit["replaces"]) for unit in units.values() if unit["replaces"]]
    if len(replacements) != len(set(replacements)):
        raise ValueError("Multiple bundled units replace one native type")
    lookup = native_lookup | custom_lookup
    for unit in units.values():
        for field in ("built_from", "converts_to", "temporary_forms", "upgraded_from"):
            values = unit[field]
            assert isinstance(values, list)
            unit[field] = [lookup.get(value.casefold(), value) for value in values]
    return units


def assign_variant_roots(units: dict[str, dict[str, object]]) -> None:
    parent = {name: name for name in units}

    def find(name: str) -> str:
        while parent[name] != name:
            parent[name] = parent[parent[name]]
            name = parent[name]
        return name

    for name, unit in units.items():
        for target in [*unit["converts_to"], *unit["temporary_forms"]]:
            if target in units:
                parent[find(target)] = find(name)

    families: dict[str, list[str]] = defaultdict(list)
    for name in units:
        families[find(name)].append(name)
    for members in families.values():
        if len(members) == 1:
            units[members[0]]["variant_of"] = ""
            continue
        root = min(
            members,
            key=lambda name: (
                not bool(units[name]["replaces"]),
                not bool(units[name]["built_from"]),
                units[name]["tech_level"] or 99,
                name.count("_"),
                -len(units[name]["converts_to"]),
                len(name),
                name.casefold(),
            ),
        )
        for name in members:
            units[name]["variant_of"] = "" if name == root else root


def read_project_coverage() -> tuple[set[str], dict[str, str]]:
    definition_source = (
        PROJECT_ROOT / "scripts/utils/units/rw_vanilla_unit_definitions.gd"
    ).read_text(encoding="utf-8")
    building_source = (
        PROJECT_ROOT / "scripts/utils/units/rw_vanilla_buildings.gd"
    ).read_text(encoding="utf-8")
    defined = set(DEFINITION_PATTERN.findall(definition_source))
    defined.update(SPEC_PATTERN.findall(building_source))
    match = re.search(
        r"const BUILTIN_CUSTOM_REPLACEMENTS: Dictionary = \{(.*?)^\}",
        building_source,
        re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise ValueError("Could not read current built-in build aliases")
    aliases = dict(re.findall(r'^\s*"([^"]+)":\s*"([^"]+)",', match.group(1), re.MULTILINE))
    return defined, aliases


def verify_hash_catalog(units: dict[str, dict[str, object]]) -> None:
    hashes = set(
        HASH_PATTERN.findall(
            (PROJECT_ROOT / "scripts/utils/rw_vanilla_units.gd").read_text(encoding="utf-8")
        )
    )
    if hashes != set(units):
        raise ValueError(
            "Bundled INI names differ from network hashes: "
            f"hash-only={sorted(hashes - set(units))}, ini-only={sorted(set(units) - hashes)}"
        )


def gd(value: object) -> str:
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        return "[" + "".join(f"{gd(item)}, " for item in value).rstrip() + "]"
    raise TypeError(f"Unsupported GDScript literal: {value!r}")


def render_catalog(native_types: list[str], units: dict[str, dict[str, object]]) -> str:
    replacement_map = {
        str(unit["replaces"]): name
        for name, unit in units.items()
        if unit["replaces"]
    }
    lines = [
        "## 保存 RWX 原生类型及游戏自带自定义单位的静态目录",
        "class_name RwVanillaUnitCatalog",
        "extends RefCounted",
        "",
        "# Generated by tools/generate_rw_vanilla_unit_catalog.py",
        "# Source paths are RWX references, not runtime resource paths",
        "const NATIVE_TYPES: Array[String] = [",
    ]
    lines.extend(f"\t{gd(name)}," for name in native_types)
    lines.extend(["]", "", "const NATIVE_REPLACEMENTS: Dictionary = {"])
    lines.extend(
        f"\t{gd(name)}: {gd(replacement_map[name])},"
        for name in native_types
        if name in replacement_map
    )
    lines.extend(["}", "", "const BUILTIN_CUSTOM_UNITS: Dictionary = {"])
    fields = (
        "source", "replaces", "tech_level", "built_from", "converts_to",
        "temporary_forms", "upgraded_from", "variant_of",
    )
    for name in sorted(units, key=str.casefold):
        unit = units[name]
        values = " ".join(
            f"{gd(field)}: {gd(unit[field])}," for field in fields if unit[field]
        )
        lines.append(f"\t{gd(name)}: {{{values}}},")
    lines.extend([
        "}",
        "",
        "",
        "## 返回原生枚举名，索引与联机协议中的原生单位编号一致",
        "static func native_name(index: int) -> String:",
        "\tif index < 0 or index >= NATIVE_TYPES.size():",
        "\t\treturn \"\"",
        "\treturn NATIVE_TYPES[index]",
        "",
        "",
        "## 返回原生枚举编号，找不到时返回 -1",
        "static func native_index(name: String) -> int:",
        "\treturn NATIVE_TYPES.find(name)",
        "",
        "",
        "## 返回 RWX 内置配置声明的原生类型替换名称",
        "static func native_replacement(name: String) -> String:",
        "\treturn str(NATIVE_REPLACEMENTS.get(name, \"\"))",
        "",
        "",
        "## 返回内置自定义单位的目录记录",
        "static func builtin_info(name: String) -> Dictionary:",
        "\tvar entry: Dictionary = BUILTIN_CUSTOM_UNITS.get(name, {})",
        "\treturn entry.duplicate(true)",
        "",
        "",
        "## 返回指定目录项的原生编号或内置自定义单位网络标识",
        "static func network_identity(name: String) -> Dictionary:",
        "\tif BUILTIN_CUSTOM_UNITS.has(name):",
        "\t\treturn {\"index\": -2, \"custom_name\": name,}",
        "\tvar index: int = native_index(name)",
        "\tif index < 0:",
        "\t\treturn {}",
        "\treturn {\"index\": index, \"custom_name\": \"\",}",
        "",
        "",
        "## 按 RWX 内置替换配置返回实际优先使用的网络标识",
        "static func preferred_network_identity(native_type_name: String) -> Dictionary:",
        "\tvar replacement: String = native_replacement(native_type_name)",
        "\tif not replacement.is_empty():",
        "\t\treturn network_identity(replacement)",
        "\treturn network_identity(native_type_name)",
        "",
    ])
    return "\n".join(lines)


def table_cell(value: object) -> str:
    if isinstance(value, list):
        return ", ".join(str(item) for item in value) or "—"
    return str(value) if value else "—"


def render_document(
    native_types: list[str],
    units: dict[str, dict[str, object]],
    defined: set[str],
    aliases: dict[str, str],
) -> str:
    replacement_map = {
        str(unit["replaces"]): name
        for name, unit in units.items()
        if unit["replaces"]
    }
    all_names = set(native_types) | set(units)
    unresolved = sorted({
        target
        for unit in units.values()
        for field in ("built_from", "converts_to", "temporary_forms", "upgraded_from")
        for target in unit[field]
        if target not in all_names
    }, key=str.casefold)
    lines = [
        "# 原版单位目录",
        "",
        "由 `tools/generate_rw_vanilla_unit_catalog.py` 从 RWX 的 `UnitTypeEnum.java` 与 "
        "`assets/units/**/*.ini` 生成。`RwVanillaUnitCatalog` 是打包时可用的静态目录；"
        "源 INI 路径仅供核对，不表示文件已复制进 Godot 项目",
        "",
        f"- 原生枚举类型：{len(native_types)} 个，索引从 0 开始；包含环境与编辑器辅助对象",
        f"- 可载入的内置自定义单位：{len(units)} 个，网络类型为 `-2` 加单位名；"
        "已与 `RwVanillaUnits.HASHES` 全量核对",
        f"- 覆盖原生类型的内置自定义单位：{len(replacement_map)} 个；"
        "`overrideAndReplace: NONE` 不算覆盖",
        f"- 当前 Godot 已注册的名称定义：{len(defined)} 个；"
        f"已配置的建筑建造别名：{len(aliases)} 个。这些数字不代表行为已完成",
        "",
        "`变体归属` 根据 INI 中的 `convertTo` 和临时转换关系分组。空白表示关系图中的"
        "基础项或独立项；它不保证该项能被玩家生产。`生产来源` 合并同目录 `copyFrom` "
        "后读取 `builtFrom_*_name`；转换目标只读取本文件声明的动作，未展开动作段继承或动态脚本动作。"
        "`[comment_*]` 配置段不计入有效动作",
        "",
        "## 原生类型",
        "",
        "| 网络索引 | 原生名称 | 内置替换名 | Godot 定义 |",
        "| ---: | --- | --- | --- |",
    ]
    for index, name in enumerate(native_types):
        lines.append(
            f"| {index} | `{name}` | {table_cell(replacement_map.get(name, ''))} | "
            f"{'已注册' if name in defined else '仅收录'} |"
        )
    lines.extend([
        "",
        "## 内置自定义单位",
        "",
        "| 名称 | 变体归属 | 覆盖原生类型 | 科技等级 | 生产来源 | 转换目标 | 临时形态 | Godot 状态 | RWX INI |",
        "| --- | --- | --- | ---: | --- | --- | --- | --- | --- |",
    ])
    for name in sorted(units, key=str.casefold):
        unit = units[name]
        status = "建筑建造别名" if name in aliases.values() else "仅收录"
        lines.append(
            f"| `{name}` | {table_cell(unit['variant_of'])} | {table_cell(unit['replaces'])} | "
            f"{table_cell(unit['tech_level'])} | {table_cell(unit['built_from'])} | "
            f"{table_cell(unit['converts_to'])} | {table_cell(unit['temporary_forms'])} | "
            f"{status} | `{unit['source']}` |"
        )
    lines.extend([
        "",
        "## 源数据中待核对的关系",
        "",
    ])
    if unresolved:
        lines.append(
            "下列名称出现在生产或转换关系中，但不在上述 52 个原生类型和 121 个内置"
            "单位名中；目录保留源值，后续实现相关动作时需逐一核对："
        )
        lines.append("")
        lines.extend(f"- `{name}`" for name in unresolved)
    else:
        lines.append("所有直接引用都能在本目录中解析")
    lines.extend([
        "",
        "## 重新生成",
        "",
        "```powershell",
        "python tools/generate_rw_vanilla_unit_catalog.py "
        "'C:\\Users\\Administrator\\Downloads\\RWX-main\\RWX-main'",
        "```",
        "",
        "运行时仅使用生成的 GDScript 常量，不会扫描 RWX 目录。第三方 Mod 不属于本目录",
        "",
    ])
    return "\n".join(lines)


def write_or_check(path: Path, content: str, check: bool) -> None:
    if check:
        if not path.is_file() or path.read_text(encoding="utf-8") != content:
            raise ValueError(f"Catalog is out of date: {path}")
        return
    with path.open("w", encoding="utf-8", newline="\n") as output:
        output.write(content)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rwx_root", type=Path, help="Root of the RWX checkout")
    parser.add_argument("--check", action="store_true", help="Verify generated files")
    args = parser.parse_args()
    native_types = read_native_types(args.rwx_root)
    units = read_builtin_units(args.rwx_root, native_types)
    verify_hash_catalog(units)
    assign_variant_roots(units)
    defined, aliases = read_project_coverage()
    for native_name, custom_name in aliases.items():
        if custom_name not in units or units[custom_name]["replaces"] != native_name:
            raise ValueError(f"Incorrect Godot building alias: {native_name} -> {custom_name}")
    write_or_check(CATALOG_PATH, render_catalog(native_types, units), args.check)
    write_or_check(DOCUMENT_PATH, render_document(native_types, units, defined, aliases), args.check)
    print(f"Catalog: {len(native_types)} native types, {len(units)} bundled custom units")


if __name__ == "__main__":
    main()
