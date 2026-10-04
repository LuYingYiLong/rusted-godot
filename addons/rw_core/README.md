# rw_core

原版 1.15 数值兼容层使用现有 godot-cpp 4.5 子模块构建，已经在 Godot 4.7.2 Windows x86_64 中验证。`RwGameMath` 是注册到 ClassDB 的原生 RefCounted 类，GDScript 可以继续调用 `RwGameMath.direction_degrees()` 等静态方法。旧 `scripts/utils/units/rw_game_math.gd` 与其 UID 已删除

## 构建与加载

在此目录执行：

```powershell
scons platform=windows target=template_debug arch=x86_64 -j8
scons platform=windows target=template_release arch=x86_64 -j8
```

运行库和加载描述文件位于 `project/bin`。Debug 用于编辑器和调试导出，Release 用于发布导出；Godot 根据 `.gdextension` 的平台特征选择并导出 DLL。修改原生代码后重新构建并重启编辑器加载新库。当前只配置 Windows x86_64 平台

MSVC 使用 `/utf-8 /fp:strict`，默认添加 `/wd4819` 关闭中文代码页警告；`suppress_utf8_warnings=no` 可恢复此项警告。其他编译器使用 `-fno-fast-math -ffp-contract=off`。这些选项只作用于 rw_core 的源码，不更改 godot-cpp 的构建选项

## 数值语义

内部显式使用 IEEE 754 binary32，按 Java 原版的中间运算顺序保存结果。原生入口把 GDScript double 参数转换为 float；返回时转回 double 不丢失 float 位值。转向保留原版 `> 180` / `< -180` 的边界判断，加减速使用原版 `f.a` 的比较顺序

`rw_math_tables.inc` 保存 8 张反正切表与 2 张三角函数表，共 24,584 个浮点位模式。由 Java `StrictMath` 按原版 `gameFramework/f.java:1256–1274` 的公式生成，运行时查表不依赖 C++ 数学库的三角函数实现。仅异常超大输入导致索引越界时使用 `std::atan2` 回退；此异常路径没有跨平台逐位一致保证

`rw_unit_state.gd` 已把非滑行位移、转向、减速滑行的数值步骤交给 `turn_toward`、`advance_speed`、`movement_position`。路径选择、碰撞推力、状态切换、滑行向量、武器与其他单位行为仍由现有脚本执行，数值测试通过不等于整个游戏模拟同步

## 参考测试

安装 JDK 17 或更新版本后，在项目根目录生成参考文件：

```powershell
java addons/rw_core/tools/Rw115MathReference.java addons/rw_core/src/rw_math_tables.inc C:/path/rw115-math-reference.tsv
$env:RW_MATH_REFERENCE = "C:/path/rw115-math-reference.tsv"
& "C:/Users/Administrator/Documents/Godot/Godot_v4.7.2-stable_win64.exe" --headless --path . --script tests/rw_115_math_reference_test.gd
```

参考生成器只在开发时使用，运行游戏不需要 Java。重新生成位表后需重新编译扩展

`tests/rw_115_ai_trace_replay_test.gd` 可重放同一局六人 AI 命令，用于迁移前后比较：

```powershell
$env:RW_SOAK_REPORT_PATH = "C:/path/godot.jsonl"
$env:RW_REPLAY_OUTPUT_PATH = "C:/path/replay-result.json"
$env:RW_REPLAY_ALLOW_DIFFERENCES = "1"
& "C:/Users/Administrator/Documents/Godot/Godot_v4.7.2-stable_win64.exe" --headless --path . --script tests/rw_115_ai_trace_replay_test.gd
```

当前重放器针对默认初始单位、4,000 初始资金及默认步长的已记录房间。旧日志将命令坐标保存成 Vector2 字符串，会损失部分小数精度，因此重放产生的微小路径校验差异不能直接当作在线差异；迁移前后使用同一份解析后的命令可以比较相对变化。严格在线验收继续使用 `tools/run_rw_115_ai_soak.py --stages 300`，通过后才延长测试

## 2026-10-05 验证结果

- 旧脚本对 30,729 个原版 float 输入样本逐位一致；额外 2,048 个 double 角度输入中有 1,359 个角差结果与 Java float 参数语义不同
- Debug 与 Release 原生库对 38,921 个参考样本均全部逐位一致，覆盖三角查表、目标角度、角差、生产出口、转向、加减速和位移
- 对 `rw115-ai-soak-20261004-233229` 的同局重放，第 602 帧主要差异迁移前后相同：`Unit Dir` 汇总差 3,148，`Unit Pos` 汇总差 -50，主校验差 -8。这些是校验整数差，不是角度或像素差。旧日志舍入导致第 301 帧路径字段出现相同的重放误差
- 新原版 AI 房间 `rw115-ai-soak-20261005-011340` 在第 301 帧出现位置差异，5 分钟阶段失败并自动停止，未进入更长测试。该房间采用随机 AI 开局，不能直接用其首次失配帧与其他开局比较收益
- 生产出口、建筑吸附、不可达终点及跨队碰撞回归测试通过

结果记录在 `C:/Users/Administrator/Documents/Codex/rw115-probe/test-results`，包含 `rw115-math-before.log`、`rw115-math-after.log`、`rw115-ai-replay-before.json`、`rw115-ai-replay-after.json`
