# 原版 1.15 源码参考核对

本次检查使用 `C:\Users\Administrator\Downloads\rw_analysis-master\rw_analysis-master`。该项目 README 和 `tools/rig/README.md` 将其原版目标标为 Rusted Warfare 1.15。Steam 安装目录的 `game-lib.jar` SHA-256 为 `8a550a37e2d8a5430866090d4e7d5892f9010b47f52a5a09350fc66c620deec9`，与该仓库测试台文档所列原版 jar 指纹前缀相同；直接运行该 jar 的枚举也得到下述 52 项顺序。这里优先核对 `02b-decompiled` 的原始混淆类；`03-deobfuscated` 的语义类名和说明文档可能有误，不能单凭名称修改模拟公式

## 原生单位网络编号

`02b-decompiled/com/corrodinggames/rts/game/units/ar.java` 明确列出 52 个枚举常量，编号为 0–51。从 `extractor=0`、`commandCenter=4`、`builder=7` 到 `dummyNonUnitWithTeam=51`，其完整顺序与项目现有 `RwVanillaUnitCatalog.NATIVE_TYPES` 逐项一致，因此应继续保留项目原来的编号

`02b-decompiled/com/corrodinggames/rts/gameFramework/j/as.java:230-239` 将原生单位类型写成枚举 `ordinal()` 的 32 位整数，自定义单位先写 `-2` 再写名称。对应的 `j/k.java:161-193` 按原生编号取枚举项。这解释了编号顺序为何直接影响建造命令。自动核对命令：

```powershell
python tools/verify_rw_115_native_catalog.py `
  --source-root 'C:\Users\Administrator\Downloads\rw_analysis-master\rw_analysis-master' `
  --game-jar 'C:\Program Files (x86)\Steam\steamapps\common\Rusted Warfare\game-lib.jar' `
  --java 'C:\Program Files (x86)\Steam\steamapps\common\Rusted Warfare\jvm64\bin\java.exe'
```

结果：`RW_115_BINARY_OK native_types=52` 与 `RW_115_CATALOG_OK native_types=52 ordinal_writer=confirmed ordinal_reader=confirmed`

## 运动与挤压的下一处差异

`02b-decompiled/com/corrodinggames/rts/game/units/y.java:845-1056` 显示，碰撞使用按单位类型划分的碰撞组、空间网格查询、最多 10 个候选和分帧刷新；同队关系只影响推力权重。项目目前在 `BattleMap._separate_mobile_units()` 每帧枚举同队移动单位对，并对双方施加推力。这是侦察机出厂挤压与长期轨迹偏离的具体候选原因，但还需要基于 1.15 实际对局或可运行探针验证处理顺序，不能只移植其中一条公式

该源码树的 `03-deobfuscated/.../game/MovementController.java` 虽名为 MovementController，内容实际是带目标、高度、命中逻辑的弹体类。因此该仓库 `docs/06-world/MOVEMENT.md` 对此类的“单位每帧移动控制器”描述不宜直接作为移植依据

## 运行限制

按 README 执行 `python tools/cli.py list` 可列出工具；`python tools/cli.py doctor` 的源码树和映射库检查通过，但下载包内没有池目录、交付 jar 或游戏 jar，退出码为 1。复制源码和已核对的游戏 jar、依赖库到可写副本后，以 `PYTHONUTF8=1` 运行 `python tools/gates/javac_gate.py`，结果为 134 个编译错误，主要是解混淆源码所引用的类未解析；错误记录在 `C:\Users\Administrator\Documents\Codex\rw115-probe\compile-errors.csv`。因此当前压缩包未能复现 README 宣称的 0 错误和 V0–V8 全通过，暂时不能把 `03-deobfuscated` 当作可直接改造运行的完整客户端；原版 jar 的枚举和网络序列化代码仍可独立作为核对依据
