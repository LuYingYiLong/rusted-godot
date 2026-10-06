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

## 工厂生产动作 ID

`02b-decompiled/.../game/units/a/l.java` 的 `UnitBuildAction` 初始以 `u_` 和请求类型的 `v()` 结果创建动作 ID；若 `ModUnitRegistry` 将这个原生类型替换为内置自定义单位，构造函数还会再次改写动作 ID 为 `u_` 加替换类型的名字。反编译文件中的枚举字段 `a` 到 `Z` 是混淆后的 Java 标识，不能直接当作协议名；stock `game-lib.jar` 的运行时枚举名由探针读取，`verify_rw_115_production.py` 会把源码字段别名、运行时枚举名和动作 ID 并排核验。项目替换表还会与安装版单位 INI 的 `overrideAndReplace` 对照，18 条映射完全一致。生产动作必须按最终注册的目标单位名生成，因此原版工厂的坦克、炮兵和激光坦克替换动作分别是 `u_c_tank`、`u_c_artillery`、`u_c_laserTank`，未替换的建造者则仍是 `u_builder`。`STOCK_NATIVE_ACTION_IDS` 只描述原生枚举本身，不能拿它覆盖已替换单位的生产动作 ID

此前默认单位注册表把 `include_builtin_custom_actions` 设为 `false`，从工厂菜单中过滤掉了 RWX 自带单位的 `built_from` 关系。原版 1.15 回放实际记录了 `u_c_interceptor` 和 `u_c_helicopter`，而默认空军工厂菜单没有这两项；陆军工厂同样漏掉 `heavyArtillery`、`missileTank` 等自带单位。这是菜单遗漏，不是混淆后的动作名。现在默认注册表保留全部内置生产关系，显式传 `false` 仍可构建仅含原生菜单的对照注册表；生产回归逐项校验各工厂菜单和 `u_<最终单位名>` 动作 ID

如果原版窗口仍看不到生产进度，这时应检查本局实际发送和回显的命令、工厂对象 ID、来源队伍以及远端客户端构建版本；枚举别名映射已与本机 stock jar 对齐，但本机单测不能证明远端房间确实收到并接受了该动作

原版联机自动化已改为直接运行这份核过指纹的 stock jar，六人 AI 长局的启动与报告格式见 [原版 1.15 多人 AI 长局](rw_115_ai_soak.md)

## 早期运动与挤压差异

`02b-decompiled/com/corrodinggames/rts/game/units/y.java:845-1056` 显示，碰撞使用按单位类型划分的碰撞组、空间网格查询、最多 10 个候选和分帧刷新；同队关系只影响推力权重。`BattleMap._separate_mobile_units()` 已纳入敌对单位并按移动状态选择执行推力的单位。建筑命令的格吸附来自 `y.java:5556-5558`：先将命令坐标减去建筑中心偏移并加 `1.0F`，按地图格截断，再加回中心偏移；建造者的路径目标仍使用命令原始坐标。`gameFramework/k/o.java` 的目标处理还规定：目标范围内没有可通行格时，按 x、y 升序选取最近替代终点。AI 轨迹仍会因不同开局在第 602 或 1806 帧失配，下一步要继续核对施工转维修时的车体方向和移动惯性

该源码树的 `03-deobfuscated/.../game/MovementController.java` 虽名为 MovementController，内容实际是带目标、高度、命中逻辑的弹体类。因此该仓库 `docs/06-world/MOVEMENT.md` 对此类的“单位每帧移动控制器”描述不宜直接作为移植依据

## 1.15 武器、弹体与伤害结算

弹体类以调用链确认，不依据解混淆名字或 `mappings.json` 的标签：`02b-decompiled/.../game/f.java` 继承游戏对象基类并保存目标、位置、高度、速度和 `game/g.java` 弹体定义；`game/units/custom/j.java` 的武器开火路径创建该类并复制炮塔和弹体参数；`game/units/custom/bh.java` 负责解析弹体 INI。该调用链也确认了此前被叫作 MovementController 的 `f.java` 实际负责弹体模拟

`bh.java` 分别把 `directDamage`、`areaDamage`、范围半径、无衰减、边缘半径、空地同时命中、水下命中、友军规则及护盾倍率写入定义。`f.java` 命中分支分别提交直击与范围伤害；范围伤害按 `1.1 - distance / radius` 衰减，边缘半径会减去目标碰撞半径。没有 `areaDamage` 时，直击伤害不会自动变成范围伤害。`targetGround` 也不执行直击伤害

普通非弹道弹体每帧同时追踪目标高度：高度差按水平剩余距离与当前弹速折算；`ballistic` 弹体走单独的升高和下降阶段。`f.java` 还把目标空中类型与爆炸高度 5、潜水高度 -5 和爆炸高度 -2 比较，分别处理空地筛选和水下例外。此前仅更新水平位置，导致攻击空中单位的弹体停在地面高度而永远无法命中

这里用自定义单位发射调用点消除字段名歧义：`custom/j.java` 创建配置弹体时把 `ballistic_delaymove_height`、`ballistic_height` 写入 `f.aI`、`f.aJ`，并把 `f.aL` 设为 `-1`；所以这类弹体每帧以当前弹速 `t` 升降。`game/f.java` 的构造默认值 `aI=40`、`aJ=60`、`aL=2` 只适用于没有经过该自定义发射初始化的弹体。Godot 按调用链区分了这些默认值：缺省高度和移动阈值采用 60/40，自定义弹道升降速度采用当前弹速，速度加速即使水平移动尚未解锁也会推进。原版在更新高度前检查水平移动阈值，因此弹体必须在高度严格大于阈值的下一帧才开始水平移动

`02b-decompiled/.../game/units/am.java` 的受伤方法在建筑进度低于 1 时先把伤害乘 1.75，再结算护盾。`shieldDamageMultiplier` 只控制护盾扣量；护盾扣完后按 `shieldDefectionMultiplier` 计算传入本体的伤害，最后应用 `hullDamageMultiplier`。这些倍率不能合并成一个泛用护盾倍率，否则护盾仍有余量时会重复吸收本体伤害

坦克替换定义 `RWX-main/assets/units/tanks/tank.ini` 给出的炮弹数据为 25 直击伤害、5 弹速、60 帧寿命，炮塔冷却为 75 帧。炮塔 `size` 与 `turretSize` 是炮塔外观尺寸，不是弹体发射距离；实际发射点来自炮塔挂点，因此无 `muzzleDistance` 定义的单位使用零距离偏移。`f.java` 在移动前缓存目标距离；只有弹体这一步能抵达目标中心时才把缓存值置零，之后用该缓存判定碰撞。建筑类型单位始终使用 `max(碰撞半径 × 0.8, 6)`，不只是在施工中使用。Godot 已按移动前缓存距离和移动后弹道位置判定碰撞，回归覆盖坦克近距离弹与已完工建筑

原版地面目标弹使用相同的移动前距离缓存，但落点碰撞半径固定为 6 世界单位，并继续检查爆炸高度容差；它不是必须到达坐标中心才爆炸。Godot 保留这一步移动后的实际弹体位置，按缓存的落点距离及高度条件判定命中，并有一枚速度为 2、距落点 5 单位时命中的固定回归

`bh.java` 将 `spawnProjectilesOnCreate`、`spawnProjectilesOnExplode` 与 `spawnProjectilesOnEndOfLife` 分别解析为带数量、概率、偏移和递归限制的弹体列表。内置弹药现在生成完整命名弹体目录，战斗系统在相应时机级联生成弹体；`f.java` 在命中后仍保留寿命与爆炸状态，因此到期分裂不能与命中回调合并。`spawnUnit` 也导入到弹体定义，爆炸时由地图创建单位；固定回归覆盖弹体回调、单位生成、鱼雷到期分裂和坦克碰撞位置。单位生成的非默认选项，以及特殊动作 `fireTurretXAtGround` 到弹体发射的调用链仍未与原版逐帧对齐

`areaExpandTime` 会让爆炸半径逐帧从中心向外扩张，已受范围伤害的对象会加入弹体的排除列表，避免后续帧重复扣血。Godot 已导入此字段，按增长中的半径命中一次并保持爆炸状态直到扩张结束；回归以两帧扩张验证内圈先受伤、外圈后受伤且内圈不重复受伤

`f.java` 的炮弹接近目标 15 世界单位时改用 `turnSpeedWhenNear`；未配置该项的原版默认值为直接转向。生成器之前没有读取此 key，也把默认值当作沿用远距离速度；现在按配置读取并在近距离使用独立默认值，回归覆盖近距离立即转向

目标地面弹在 `bh.java:a(am,f,am,float,float,float)` 的发射分支中将单位目标转成固定弹着点；默认开启 lead targeting 时，`am.java:a(float,float,float,float,float)` 用目标当前速度迭代三次计算拦截点，再按弹体寿命截断提前时间，随后不再追随单位。该分支也对单位目标应用 `targetGroundSpread` 与高度偏移；移动时仍按当前弹体角度逐帧转向这个固定散布点。Godot 现在在发射时快照弹着点并关闭对单位的后续跟踪，同时逐帧转向落点，回归覆盖三次迭代预测、发射后的目标移动与散布后转向。字段类型按 `bh.java` / `bn.java` 的实际读取调用核对：`life`、`delayedStartTimer`、炮塔 `delay` / `warmup` 和 `wobbleFrequency` 走时间解析器，秒后缀乘 60；弹速、转向速度、重力、散布与 `areaExpandTime` 是普通浮点数，不能误乘 60

`bh.java` 也将 `instantReuseLast`、`instantReuseLast_alsoChangeTurretAim`、`instantReuseLast_keepAreaDamageList`、`nukeWeapon`、`deflectionPower`、`flameWeapon` 与雾效可见标志解析到弹体模板。同炮塔弹体复用、复用时保留范围伤害对象表和扫动偏移对瞄准点的联动、弹体雾中可见及揭雾触发已有模拟实现与固定回归；激光防御的弹体偏转规则已按 `units/d/p.java` 接入。核弹持续爆炸效果、火焰专用命中特效和激光拦截粒子的原版细节仍未完整还原，不把 `flameWeapon` 字段名解读成持续灼烧伤害

## 运行限制

按 README 执行 `python tools/cli.py list` 可列出工具；`python tools/cli.py doctor` 的源码树和映射库检查通过，但下载包内没有池目录、交付 jar 或游戏 jar，退出码为 1。复制源码和已核对的游戏 jar、依赖库到可写副本后，以 `PYTHONUTF8=1` 运行 `python tools/gates/javac_gate.py`，结果为 134 个编译错误，主要是解混淆源码所引用的类未解析；错误记录在 `C:\Users\Administrator\Documents\Codex\rw115-probe\compile-errors.csv`。因此当前压缩包未能复现 README 宣称的 0 错误和 V0–V8 全通过，暂时不能把 `03-deobfuscated` 当作可直接改造运行的完整客户端；原版 jar 的枚举和网络序列化代码仍可独立作为核对依据

## 2026-10-05 帧末探针定位补充

参考 `units/y.java` 的 `k(float)`、移动速度判定、路径投入使用方法及软碰撞代码，已经对齐施工转向与命令惯性、候选缓存、寻路计时和邻居展开顺序。`units/d/m.java` 等建筑的 `n` 与 `o` 分别提供物理占地和施工占地，现分别用于单位通行与建筑放置。`units/al.java` 的树木碰撞半径与伤害公式也已接入

原版与复刻版现在可使用同局二进制命令进行固定重放。旧第 602 帧失配已经在施工转向夹具中解决；建筑脱离夹具的单位 305 曾在第 1437 帧出现原版移动因子 0.04、Godot 0.0。原版录像移动输入探针确认，这由建筑生成当帧过早执行新维修目标造成，寻路起始格因此不同；现在新目标推迟到下一同步步执行，固定轨迹已经一致

原生运算参考通过只能验证公式与精度，不能替代模拟阶段顺序、寻路输入时机、单位行为和联机长局验收

`gameFramework/k/i.java:e()` 按单位 `cK` 筛选动态障碍，停工单位即使保留路径也必须计入代价；`RwUnitState.navigation_path_active` 记录本步实际路径决策，避免用残留路径点推断移动状态

`units/y.java:i(float, au, ad)` 推进建造武器的 `ap.f` 预热；同类的战斗更新根据上一帧 `aN` 和当前 `X()` 决定是否冷却。`units/e/b.java:a(float)` 在 `super.a(float)` 后提交 `aN`，其 `f(int)` 冷却速率为 1.3。第一帧预热因上一帧束尚未活动而回落到 0，随后才正常累加。现在单位状态保存预热量和上一帧束状态，按源码处理冷却并在切换命令时保留预热量，替代额外等待一帧的阈值补偿

原生定义补充 `RwNativeProductionSpecs` 中的建造速率，协助施工与原建造者使用同一目标单位速率。固定回归增加配套原版 CSV，逐帧比较施工进度和预热字段，避免仅检查不包含这些字段的网络单位校验和

`units/d/k.java:a(am, float, boolean)` 为生产单位设置独立的 `cl` 临时通行计时；`units/y.java:a(float)` 每帧递减计时，寻路决策在 `cl != 0` 时直接使用当前命令目标。新命令会替换旧出口目标，不要求先走完离厂路径，计时也不会因命令替换而消失。计时结束后按当前地形生成脱离建筑的短路径，随后重新生成正常路径。`rw115_factory_exit_interruption` 已对齐第 1641 帧的攻击移动命令替换，并在第 1806 帧前的 33,695 条单位帧及 7 个校验点一致

`gameFramework/k/l.java:a(i, boolean)` 的直线检查在缓存时间加 30 小于当前帧时刷新单位动态代价；非强制请求另有加 50 的判断。网格现在按移动类型缓存动态代价，命令的路径申请在下一模拟步按单位顺序执行，避免同帧多命令按接收顺序更改共享缓存。当前直线检查入口使用 30 帧刷新规则，其他请求入口的 50 帧分支仍需继续覆盖。净空数组的右侧与下侧虚拟边界在尺寸加一的位置，已修正原先一格偏差。`rw115_dynamic_path_cost_cache` 的 32,308 条单位帧和 7 个校验点一致，新增求解器输入探针及数组摘要回归，用来检查缓存内容本身

`game/i.java:1495-1556` 先按已有对象顺序调用更新，再推进新增对象，最后处理碰撞。施工完成后的命令清理现在在建造者自己的更新阶段进行，避免提前更改尚未更新的协作单位。命令寻路准备也与单位更新次序一致

`gameFramework/k/l.java:b(i, int, int)` 的直线格代价包含地形、建筑及动态单位代价乘 10，累计阈值为 80。此前漏掉动态项，造成原版等待异步路径时复刻版直接移动。`gameFramework/k/i.java` 的建筑局部净空更新还不同于初始全图重算：按建筑物理占地扩展五格的区域重算，查询半径三格且地图外视为障碍。边界净空不能统一套用全图初始化公式

`units/y.java:745-827` 和 `units/aq.java:114-165` 处理格子边缘滑动，线段相交使用 `gameFramework/f.java` 原版 float 公式。新原生 `terrain_slide_position` 保留运算顺序及格子坐标 0.01 的边缘偏移，碰壁后不直接把移动速度清零。运动与碰撞推力的完整组合时序、卡墙计时分支仍需覆盖

`units/y.java:5550-5620` 在建筑放置失败时调用候选建筑的 `bs()` 查找同队、同类型的相交单位；找到后转为维修或协助施工，候选对象的编号仍会消耗。新分支解决了固定对局第 2939 帧建造者提前清空命令的差异


## 收入计时与编队依据

- `game/n.java:C/E/b/c/d`：联机 AI 使用队伍的有效难度 x；倍率 `1 + difficulty * 0.4F`（正难度）或 `0.3F`（非正难度），难度 3 额外加 1，最低 0.1F；收入 float 逐次运算后累加到 double 余额
- `game/n.java:a(k, boolean)` 与 `gameFramework/j/ad.java` 的包 115：对局中忽略房间包整数字段，不能使用该包的取整资金覆盖本地锁步余额
- `units/d/e.java`、`d/g.java`：完成且存活的指挥中心、原生抽取器在自身更新中推进收入计时，`timer > 10F - 0.1F` 时发放 `cy() * 0.25F`
- `units/custom/ag.java`：`generation_delay` 默认 40，0 变为 1；收入率系数为 `40F / delay`
- `units/custom/j.java`：施工完成后推进 o 收入计时；定义转换保留该计时；超过 `delay - 0.1F` 时发放 generation_resources
- `units/y.java:a(float,float,int,boolean,boolean)`：ct() 的飞行单位只保存目标点；普通地面直线路径按每 20 像素生成中间点
- `gameFramework/ab.java`：从整组平均位置计算编队角度，按距离目标最近选择领队，按移动类型、距离和速度差选择跟随者
- `gameFramework/aa.java`：六列编队槽、先处理离可用槽最远的跟随者，再交换槽降低行走距离
- `units/y.java` 的编队跟随方法：跟随者使用领队路径前瞻和偏移，而非独立的固定偏移目标；现已迁移槽位、前瞻、脱队计时、停留与恢复路径申请，复杂在线分支仍需覆盖

`original-units.csv` 已增加只读的 formation_leader、formation_x/y/angle、formation_size、formation_leader_age、formation_recovery 和 formation_lag。Godot 已记录对应编队状态，比较器按字段记录实际覆盖次数


## 建筑清场与树木参考

`units/y.java:br()` 用 `cd()` 的整数边界乘地图格尺寸，加单位位置、减 `cZ()/da()` 半格偏移并向四侧扩展 10 像素。`am.a(RectF)` 按圆形边界与矩形严格相交检查；相交的树木调用 `al.k()`，已死亡的 y 类残骸则移除

`units/al.java:n()` 将 `ep * 5F + eo * 3F` 归一化到 [-180, 180]。`k()` 置死亡与不可碰撞状态、帧号 2；普通与雪地树木沿当前方向偏移 `(et / 2 - 3)`，30 像素高度对应 12 像素。清场不扣生命值，接触伤害则先扣生命值并在倒下前改变方向

原版录像 `rw115-replay-20261005-111936` 的树木 14 在第 1537 帧位于 (1890, 230)、生命 100、存活，第 1538 帧位于 (1901.2782, 225.90105)、生命仍 100、死亡。该树在复刻中未清除，造成第 3211 帧工厂出厂单位额外推力；补齐后该同局截至第 3311 帧移动单位轨迹一致


`units/y.java` 建造重试检查 `utility/y.a(Q, 200)`，其中 `Q + 200 < engine.by` 为严格超过 200 毫秒。冷却期间仍在建造范围内时不启用导航目标，普通移动速度继续衰减；不能提前返回后让旧路径重新加速，也不能用固定 12 帧近似


## 路径结束、卡墙和建筑占地脱离

- `units/y.java:745–827` 的地形移动入口只在 `ay && I()` 时调用；转向本身不会推进无阻挡移动计数
- `units/y.java:2943–3048` 在没有路径点时根据 `s` 和 `u` 重新申请路径，普通请求设置 `s=500`；部分路径可以在 `s<450` 时继续申请
- `units/y.java:3200–3225` 弹出最后路径点后，普通移动仅在非部分路径且没有领队时结束命令，攻击移动保留命令
- `units/y.java:1870–1900` 建造目标在范围外时限制 `s<=90`，卡墙清空路径也需重新申请；没有路径目标时不自行转向最终目标
- `units/y.java:4265–4314` 起点被建筑覆盖且基础地形可通行时生成不超过 60 像素的单点路径，超过 60 像素则标记 `u`，限制重新申请计时为 10
- `units/y.java:4330–4370` 的直线路径最多 119 点；`b(l)` 在异步路径释放时最多保存 120 点，并标记 `u`，因此路径容量限制也影响命令生命周期

对应已修正的固定案例及尚未修复的长路径差异记录见 [AI 对局验证](rw_115_ai_soak.md)


## 编队领队的直线通行余量

`game/units/y.java:a(l,float,au,ad)` 在申请路径前使用 `ae && ah > 1` 作为领队编队标志，传给 `a(float,float,int,boolean,boolean)` 的第四参数。后者将 `aq.a` 的最小通行余量设为 3，普通单位为 0；成本阈值 80 与跳过起点一个成本格的规则不变

`game/units/aq.java:a(ao,int,int,int,int,int,int,int)` 在每个 Bresenham 路径格先检查 `bU.c(i,x,y) < minimumClearance`，该检查包括起点。`gameFramework/k/l.java:c(i,int,int)` 返回 clearance 网格值，飞行类型为 4，地图外或缺少缓存为 -1。余量不足时必须进入异步路径分支，不能再由另一套视觉线段检测改回直线


## 点命令的累计到达等待

`units/y.java:a(float,au,ad,boolean)`（约 1663–1745 行）在目标距离平方小于 1681 时累加 `Y`，到达半径按严格大于 240 / 340 分别扩大到 16 / 36，默认 7。`av.h` 攻击移动只有在没有仍可攻击的 `R` 时完成；`av.j` 巡逻还有队列轮换、30 / 80 等另外规则，尚未与此方法合并实现

`ay()`、`az()` 及插入首条命令时清零 `Y`；`a(float,float,int,boolean,boolean)` 的重新申请路径保留 `Y`。同一字段还用于接近建筑目标的另外命令分支，不能将这些分支一概按移动半径处理


## 攻击移动首次切换到追击目标

`02b-decompiled/.../game/units/y.java` 的武器更新分支在 `R` 超出 `o(R)` 但仍有效、攻击模式允许追击且 `k` 尚未置位时，立即将临时导航坐标 `l/m` 指向 `R`，并将追击路径计时 `n` 设为 0。这里是首次进入追击的状态转换；普通路径计时不能延迟这次切换。之后沿用原有路径节流，等待下一次计时到期再跟随移动中的目标。

Godot 现已在首次满足追击条件时立即启用临时目标、清零寻路计时并请求路径；后续目标更新仍受 90 帧上限约束。重寻路继续保留同步命令的最终坐标，避免攻击移动被追击目标覆盖


## 移动单位死亡后的对象编号

`02b-decompiled/.../game/units/y.java:a(ab, boolean)` 的普通移动单位死亡分支，在非液体地形且死亡类型不是 `verySmall` 或 `buildingNoShockwaveOrSmoke` 时，依次创建 `gameFramework/d/f` 的烟雾与火焰发射器，再尝试创建 `game/l` 焦痕。`d/f` 和 `game/l` 都继承 `gameFramework/w`，构造时会消耗全局对象编号；只播放 Godot 爆炸动画不会推进该编号。原生建造者 `units/e/b.java:e()` 使用 `ab.b`（small），也会创建烟雾和火焰发射器；不能按单位名把 builder 排除

焦痕由 `game/l.b(x, y, type)` 控制：同类焦痕在 25 世界单位邻域达到 3 个，或 5 单位内已有一个时，本次不创建焦痕对象。液体地形由 `units/am.cK()` 检查，最终调用 `gameFramework/utility/y.d(x, y)`。标准坦克在陆地死亡且附近没有焦痕时，原版因此会比此前的 Godot 多消耗 3 个对象编号；下一辆坦克虽然能在 Godot 本地移动，发送的却是原版尚未分配给该坦克的 ID，原版会忽略该移动命令

Godot 现在在移动单位死亡回调中按原版顺序消耗两个特效编号，并按焦痕邻域规则消耗可选的焦痕编号。新增回归检查覆盖普通陆地死亡、焦痕邻近去重、原生建造者和液体地形。实际联机中第二辆坦克的移动仍需再跑一次验证；此前的短时 AI 轨迹没有原版单位死亡，不能证明这条在线链路


## 弹药发射、弹道与同步随机数

本轮以 `02b-decompiled` 的解析器、弹体工厂、弹体更新及自定义单位发射调用链交叉核对，不按混淆字段字母猜行为：`game/units/custom/bh.java` 解析配置键并写入弹体对象，`game/f.java` 创建及逐帧更新弹体，`game/units/custom/j.java` 决定自定义单位何时发射、复用弹体和递增对象随机计数。RWX 的单位 ini 用来验证具体炮弹配置；最终行为以 1.15 的这些读取点和调用顺序为准

`game/f.java` 的弹体继承 `gameFramework/w.java`，新建时由游戏的全局对象分配器赋一次唯一编号。`custom/j.java` 的 `instantReuseLast` 分支会重新初始化同一个弹体对象，不会再次运行对象构造函数。复刻此前每次 `projectile_fired` 都递增全局编号，复用即时弹体时会多吃一个编号，之后新生产单位可能因此拿到和原版不同的网络对象编号；现在只给尚无编号的弹体分配 ID，并新增复用不消耗编号的回归

- `gameFramework/f.java:a(w,int,int,int)` 是对象同步随机范围公式。输入包含下一模拟帧、全局种子、对象 ID、对象位置、对象随机计数器和随机流编号。全局种子来自 1.15 房间设置包 106 的版本 8 整数字段；`gameFramework/j/ah.java` 的 `randomSeed` 序列化顺序和 `gameFramework/j/ad.java` 的网络读取顺序都确认该字段是 `ay.q`，开局时 `game/i.java` 将它复制到随机公式读取的 `bJ`。项目此前忽略这个字段，导致真实房间的弹体随机输入错误；现在 `_read_server_settings` 读取并在每个战斗同步帧传给战斗模拟，协议夹具覆盖非零种子。`game/f.java:a(am,float,float,float,int)` 创建弹体时以流 `0` 取 `[0,1]` 相位并递增单位计数器；自定义单位发射点在 `custom/j.java` 中先将计数器增加 `1 + object_id`。之后速度散布用流 `1`；目标单位地面弹的散布依次用流 `2`、`7`，不改随机计数器；纯坐标地面弹依次用流 `2`、`3`，每次散布后再按原版 float32 顺序把落点坐标加到计数器。`custom/bi.java` 的集束弹生成遍历还使用跨所有配置项递增的候选序号：命中概率用该序号，方向、横向和纵向偏移分别用 `序号*4+3`、`序号*2+1`、`序号*3+2`；子弹方向基准是父弹当前 `az`，不是当前速度向量。Godot 已接入并固定随机流、目标继承、总生成上限、弹着点转向和子弹位置回归
- `custom/j.java` 的自定义武器发射方法先依炮塔索引查找可复用弹体，再调用弹体重置位置；保留已有弹体时不重新抽取创建相位。弹体更新 `game/f.java:a(float)` 先处理延迟起动，再递减寿命；处于延迟期间不会推进普通弹道。运行年龄从首次有效更新累积，扫动使用 `sin((360 * phase + age) * PI / 180)` 和 `sin((360 * phase + age * 1.5) * PI / 180)`，振幅是 `sweepOffset + target.collisionRadius * sweepOffsetFromTargetRadius`。Godot 已接入延迟、原相位扫动及同炮塔 `instantReuseLast` 弹体复用
- `custom/bh.java` 对 `moveWithParent`、`turnSpeedWhenNear`、`sweepOffset`、`sweepOffsetFromTargetRadius`、`delayedStartTimer` 和 `instantReuseLast` 的键读取，确认它们分别进入弹体更新、转向或发射复用路径；Godot 当前已实现这些配置对应的主要弹体行为。父对象移动时按当前炮塔挂点与弹体保存的上次挂点之差平移弹体起终点，爆炸留场期间也继续跟随
- `custom/j.java` 的炮塔挂点方法将 ini 中的 `turret_x/turret_y` 用炮塔当前角度旋转后加到单位世界位置。Godot 现在以开火时炮塔角度变换挂点，保留原版世界坐标 Y 方向，并将创建出的相位保存在弹体上供扫动/摆动使用
- 普通目标弹每帧先缓存移动前目标距离，再把本步位移限制为剩余距离（严格小于本步弹速时）；原版用移动前距离判断碰撞，只有本步能够抵达目标中心时才把缓存距离置零。命中位置仍是转向后的实际弹道位置，不能拿移动后的距离重新判定，否则会提前一帧命中目标半径边缘。Godot 已按这一顺序处理原生弹体碰撞，并保留地面目标弹的固定弹着点规则

目前仍有源码已证实、但需要单独接入的行为：特殊动作 `fireTurretXAtGround` 与弹体发射的同步入口，以及核弹、火焰等专用命中特效。`instantReuseLast_alsoChangeTurretAim` 已按运行时调用关系使用复用弹体的当前扫动偏移修正下一次瞄准点，并有固定角度回归。普通坦克炮弹的发射点、速度/目标散布、扫动/摆动相位、延迟起动、目标接近步长和命中时机已有固定回归；这不等于所有原版弹药或整局联机状态已逐帧等价

### 激光防御与弹体偏转

这里按 `02b-decompiled` 的原生弹体工厂和 `units/d/p.java` 交叉确认字段语义：`custom/j.java` 创建弹体时，`deflectionPower < 0.5` 会置弹体的不可拦截标志；否则将该值复制为弹体拦截耐久。原生炮弹默认耐久为 1，轰炸机炸弹为 3，`-1` 弹药不接受激光防御拦截。每次有效命中使耐久减 1，降到 0 后移除弹体。

原生 `laserDefence` 初始充能为 1.0。单位更新每步补充 `0.0004`，升级后补充 `0.0006`；未升级射程 160、每次消耗 `0.11`，升级后射程 210、每次消耗 `0.05`。充能耗尽后要回满才重新启用。原版每步按弹体列表顺序最多拦一枚：弹体不能是即时弹或不可拦截弹，需已飞行超过 7 帧，或超过 2 帧且速度大于 8；高度不得低于 -1；距离必须小于防御射程。其目标是防御方盟友，或发射方为防御方敌人。检测点是建筑中心上移 13 个世界单位。

Godot 已按这些原生条件更新充能、识别目标、递减弹体耐久并销毁，固定回归覆盖默认坦克弹、三级轰炸机弹、不可拦截弹、升级射程与升级耗能。拦截光束和火花当前是简化表现，原版粒子参数与命中音效还需要进一步对照


## 原版弹药倍率、图集与表现分支

这一轮按 `02b-decompiled` 的明确配置键与读写位置追踪，不用 `var0` / `var3` 这类临时变量名猜语义：

- `game/units/custom/bh.java:a(...)` 读取 `[projectile_X]` 的英文配置键。`drawType` 写入弹体绘制类别，`frame` 与 `shadowFrame` 分别指定主图和阴影帧；`largeHitEffect`、`nukeWeapon`、`flameWeapon`、`hitSound`、`lightColor`、`lightSize`、`lightCastOnGround`、`alwaysVisibleInFog`、`shouldRevealFog` 等都在解析器中有各自独立的读取点
- `game/units/custom/j.java:a(...)` 创建发射弹体时先将 `directDamage`、`areaDamage` 复制到弹体。如果 `ignoreParentShootDamageMultiplier` 未启用，且发射者是自定义单位，则两项都乘发射单位 `[attack] shootDamageMultiplier`。Godot 现在在发射时保存倍率，在直击与溅射结算时各应用一次；子弹继承相同发射倍率，显式跳过标志则倍率固定为 1.0。测试覆盖倍率生效、范围伤害衰减及跳过倍率
- `custom/j.java` 将含发射倍率的直击伤害写入弹体 `U`；`game/f.java` 用 `目标生命值 > 10 + U` 决定是否使用 `1.1 × 目标碰撞半径`，因此半径分支也必须使用倍率后的直击伤害。Godot 已修正该阈值并添加一条会在旧逻辑首帧误命中的建筑回归
- 同一个发射方法把 `frame`、`drawType`、`shadowFrame`、`invisible` 写入游戏弹体；`game/f.java` 绘制分支确认 `drawType=0` 使用 `projectiles.png` 的 20×20 格，`1` 使用 `projectiles_large.png` 的 60×60 格，`2` 使用 `projectiles2.png` 的 20×20 格。Godot 现在按类别选图集，使用指定主帧和阴影帧，并把 `drawUnderUnits` 弹体放入单位下方图层
- `game/f.java` 更新结束时将图像旋转角以每帧最多 12 度逐步逼近弹体朝向。Godot 新增独立的平滑绘制角，模拟朝向和图像朝向分开保存，避免导弹或转弯弹体的贴图每帧硬切角度
- 原版发射方法还复制 `lightColor`、`lightSize`、`lightCastOnGround` 作为弹体动态光源参数。Godot 已接入光色、大小和贴地绘制；炮兵配置回归确认图集帧、大爆炸标志与贴地光效均有值
- `game/f.java:a(float)` 的原版碰撞分支在没有自定义爆炸效果时仍调用通用命中特效。`gameFramework/d/c.java:c(float,float,float)` 将普通命中特效设为 `explode_big2` 图集第 3 至第 7 帧，39×40 像素帧、40 像素步距、0.5 缩放和半帧动画速度；`b(float,float,float)` 为大型命中特效使用 `explode_big` 图集第 0 至第 12 帧，缩放随机落在 0.8 至 1.0。Godot 已为普通原版弹药补上通用命中特效，并修正大型爆炸图集帧尺寸、边距、帧数和缩放
- `game/units/custom/bh.java` 还解析 `teleportSource` 与 `convertHitToSourceTeam`，`game/f.java` 命中时先传送发射者，再执行命中阵营转换和伤害。原版实验武装直升机的 `projectile_blink` 使用 `teleportSource=true`、`targetGround=true`、`instant=true`；Godot 已接入发射者瞬移，并用该原版弹药做命中回归
- `nukeWeapon` 在原版大型命中特效之外还触发多组持续时间不同的爆炸、冲击波、烟尘、火光与音效；当前只保留大型命中主效果，整套持续核爆效果仍待专门的 VFX emitter 支持。`flameWeapon` 命中时会调用寿命 21 帧的火焰粒子发射器；Godot 当前只显示简化的火焰图集命中动画，未复刻该发射器的逐粒子参数。这里的 `flameWeapon` 是命中特效分支，不代表额外的持续灼烧伤害。`shouldRevealFog` 已接入命中与弹道下降至高度 30 以下的触发点，并创建半径 15 世界单位、持续 360 个同步帧的临时视野源；`alwaysVisibleInFog` 和弹体可见性也已接入绘制判断。护盾专用爆炸和其他自定义粒子发射器仍未完整接入

对标准原版坦克，`assets/units/tanks/tank.ini` 的弹体配置为 25 直击伤害、60 帧寿命、速度 5、帧 1、绘制大小 1；这些值与其余已生成弹道数据一致。原版 `shootDamageMultiplier` 是自定义单位攻击配置，不应臆测套在没有该字段的标准原生坦克上。现有测试分别核对标准坦克数据与一个显式倍率的自定义发射者，避免把两个来源混为一谈
