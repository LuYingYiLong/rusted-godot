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

`rw_unit_state.gd` 已把非滑行位移、转向、减速滑行的数值步骤交给 `turn_toward`、`advance_speed`、`movement_position`。路径选择、碰撞候选管理、状态切换、滑行向量、武器与其他单位行为仍由现有脚本执行；碰撞推力公式已迁入原生 collision_offsets，数值测试通过不等于整个游戏模拟同步

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

## 2026-10-05 后续差异定位

新增 `collision_offsets`，按照原版 float 运算顺序计算软碰撞推力；Debug 和 Release 对 4,096 个独立 Java 样本逐位一致

原版探针改为在游戏线程帧末采集，避免后台线程读取半帧状态。命令记录增加二进制载荷，Godot TSV 输出保留足够的小数位，避免日志舍入干扰逐位比较

已修正施工转向、命令切换惯性、放置失败消耗对象编号、碰撞候选缓存、建筑施工占地、树木碰撞和路径邻居顺序。对应同局重放夹具已加入 `tests/fixtures`。这些修复解决了上面历史记录中的部分差异，不代表全部单位同步

原版录像重放探针确认，建筑生成当帧替换命令后，新维修目标要下一帧才开始寻路。修正后 `rw115_building_escape` 的 6 个校验点及截至第 1505 帧的 26,616 条单位帧记录一致。后续修正了停工单位的动态寻路代价、协助建造速率以及建造预热冷却；`rw115_repair_path_turn` 的 7 个校验点及截至第 1806 帧的 33,763 条单位帧记录一致，其中包含建造者预热量。5 分钟 AI 阶段仍未通过

出厂阶段的命令替换不再强制走完旧出口路径，原版 `cl` 临时通行计时独立保存；脱离建筑后重新生成正常路径。`rw115_factory_exit_interruption` 的 7 个校验点和 33,695 条单位帧记录一致。完整轨迹采集模式下，AI 阶段验收同时检查这些逐单位字段，不能只凭网络校验通过就延长测试

新增 `terrain_slide_position` 对齐原版地形格边缘与线段相交的 float 运算顺序。`Rw115TerrainReference.java` 使用 stock jar 的相交函数生成 8,192 个参考样本，`rw_115_terrain_math_test.gd` 在 Debug 和 Release 均逐位一致。参考生成时 classpath 需要同时包含 `game-lib.jar` 及其 `libs/*` 依赖；游戏运行不依赖 Java

后续定位说明：模拟执行顺序和行为分支仍会在运算逐位一致的前提下产生差异。已修正逐单位施工结束顺序、离厂路径切换时机、动态寻路直线代价和重叠建筑的协助施工；最新固定案例第 3010 帧前的 65,507 条单位帧与 11 个校验点一致，尚未通过五分钟 AI 对局验收


## 2026-10-05 收入、施工范围和后续编队差异

- 已修正建造者直线可达后又被第二次角落检测改为 A* 路线的分支
- 补齐遇墙累计计时、长时间停留路径点的跳过与重新寻路，以及最终命令 7 像素和路径终点 4 像素两种到达判断
- 新增原生 `sliding_velocity`，Debug 与 Release 各通过 8,192 个 stock Java 滑动速度参考样本
- 房间包正确读取 AI 难度；按 `n.E/b/c/d` 先计算 float AI 倍率与房间倍率，再累计 double 资金
- 指挥中心及收入建筑按各自单位更新计时；内置 INI 的 `generation_delay` 默认 40，原生收入建筑为 10。施工完成当帧计时，转换保留计时且同一编号每帧只更新一次
- 建筑生成后按实际建筑位置检查施工范围；飞行单位直线路径只保存终点
- 新增帧末队伍资金探针，逐位比较 double；逐单位比较同时拒绝多出单位、缺少单位和空轨迹，并输出实际比较字段的覆盖次数

`rw115-ai-soak-20261005-101450` 原始运行在第 4214 帧失配。修正前首次单位差异为第 3551 帧施工预热；同局重放修正后首次单位差异推进到第 4061 帧悬浮坦克的编队跟随。到第 4214 帧的 25,284 条队伍资金记录全部一致，但单位轨迹仍有差异，因此五分钟阶段仍未通过，不能进入十分钟或更长验收

原版录像探针 `rw115-replay-20261005-102711` 确认该悬浮坦克 320 跟随领队 316，编队偏移为 `(-0.27342567, 22.998375)`，编队角度为 `-179.38455`。第 4061 帧动态跟随目标为 `(1828.785, 2120.1304)`，来自领队的第三个路径点加编队偏移，跟随者自身路径为空。该次对照时复刻只分配固定偏移终点，缺少领队动态跟随、路径前瞻、脱队恢复和编队碰撞权重，后续按以下章节实现 `gameFramework/ab.java`、`aa.java` 与 `units/y.java` 的对应规则

固定夹具 `rw115_ai_income_build` 覆盖第 3010 帧，含 64,307 条单位帧、18,060 条资金帧和 11 个网络校验点；`rw115_repair_range_air_path` 是该新对局截至第 4040 帧的修复切片，后续编队差异保留在完整失败对局报告中。切片测试不代表完整对局通过


最新固定回归 `simulation-20261005-income-repair-air`：29 项全部通过，12 份配套单位 CSV 合计 572,473 条单位帧一致，2 份队伍资金 CSV 合计 42,300 条资金帧逐位一致，7 次寻路输入检查通过。比较器的 4 项故障注入检查通过；改动后的生产接口与本地战斗回归另各通过 1 项。编辑器扫描未报告脚本解析错误；隔离环境仍输出 Windows 根证书读取提示，部分重放退出仍有 ObjectDB 清理提示，这些不是对局一致性证明


## 2026-10-05 编队跟随与建筑树木清场

- 新增 `RwUnitFormationController`，按战场对象顺序选择领队、分配六列槽位，使用整组选中单位的平均位置计算方向
- 跟随者使用领队路径前瞻，清空自身路径；接入跟随速度调整、等待领队完成、脱队恢复路径申请及同队编队碰撞质量权重
- 原版 `au.j` 是宽松编队标志，命令包 `e.e` 才是排队标志。读取器现在输出 `formation_loose`，旧二进制命令夹具中的 `order_is_queued` 仅用于兼容读取编队标志
- 原生 `distance_squared`、`rounded_distance`、`formation_offsets` 与 `formation_target` 保留 float 运算顺序。`Rw115FormationReference.java` 对槽位直接调用 stock `aa.a`，对距离直接调用 stock `f`，对路径前瞻使用 `y.java` 提取的公式；共 17,408 组样本在 Debug 和 Release 均逐位一致
- Godot 与原版探针现同时记录领队编号、偏移、方向、编队规模、领队年龄、脱队恢复及落后计时，比较器按实际字段分别统计覆盖次数

固定案例 `rw115_formation_follow` 截至第 4214 帧，109,915 条单位帧、25,284 条资金帧及 15 个网络校验点一致。此案例解决了之前第 4061 帧悬浮坦克 320 的独立路径与领队跟随分歧，仍不代表所有编队分支都已通过在线验证

新对局 `rw115-ai-soak-20261005-110741` 在第 3311 帧网络校验失配，首次逐单位差异为第 3211 帧出厂悬浮坦克 317 的碰撞推力。原版录像指定障碍物探针确认：树木 14 已在第 1538 帧被新建筑清场放倒；复刻遗漏此规则，后来仍让新单位撞到该树

依据 `units/y.java:br()`，新增建筑按其 `cd()` 放置范围转换为世界矩形、减半格偏移并扩展 10 像素，用树木圆形边界检查相交并放倒。树木初始角度按位置计算，倒下保持清场前生命值，普通及雪地树木使用原版 12 像素残骸位移，视觉切到第 2 帧。`rw115_factory_tree_clear` 截至第 3311 帧的 72,843 条移动单位帧和 12 个网络校验点一致；`rw_115_building_tree_clear_test` 另对照原版树木 14 的第 1537/1538 帧位置、生命和死亡状态

原版指定障碍物采样可设置 `RW115_OBSTACLE_IDS=14`，输出 `original-obstacles.csv`；重放探针失败现在立即终止。只输出轨迹的离线重放不再保存无需使用的 640 帧校验快照，在线校验采集继续由 `RW_PROBE_CHECKSUMS=1` 启用

尚需继续覆盖排队命令的编队重建、复杂脱队恢复、密集碰撞与战斗状态；五分钟 AI 阶段未通过时仍禁止延长到十分钟、二十分钟或三十分钟


## 建造重试冷却修正

新对局 `rw115-ai-soak-20261005-113134` 首次单位差异发生在第 4707 帧：资金不足后的建造尝试冷却期间，复刻的建造者 294 又朝旧路径加速，原版保持停止导航并继续减速，且保留之前的转向速度。第 4778 帧出现过早扣费，第 4816 帧网络校验失配

原版 `units/y.java` 的建造分支和 `gameFramework/utility/y.java:a(int,int)` 按模拟毫秒时钟要求距上次失败尝试严格超过 200 毫秒。复刻原来用固定 12 帧近似，并在提前返回时丢失了停止状态。现在冷却等待保留导航停止、暂停主动转向，重试由原版模拟毫秒时钟判断

固定案例 `rw115_build_retry_clock` 的同局重放截至第 4816 帧，130,830 条单位帧、28,896 条资金帧和 17 个网络单位校验点一致，包含对象编号；尚未完成五分钟在线验收，仍不进入更长阶段
