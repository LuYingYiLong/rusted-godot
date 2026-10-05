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

原版联机自动化已改为直接运行这份核过指纹的 stock jar，六人 AI 长局的启动与报告格式见 [原版 1.15 多人 AI 长局](rw_115_ai_soak.md)

## 早期运动与挤压差异

`02b-decompiled/com/corrodinggames/rts/game/units/y.java:845-1056` 显示，碰撞使用按单位类型划分的碰撞组、空间网格查询、最多 10 个候选和分帧刷新；同队关系只影响推力权重。`BattleMap._separate_mobile_units()` 已纳入敌对单位并按移动状态选择执行推力的单位。建筑命令的格吸附来自 `y.java:5556-5558`：先将命令坐标减去建筑中心偏移并加 `1.0F`，按地图格截断，再加回中心偏移；建造者的路径目标仍使用命令原始坐标。`gameFramework/k/o.java` 的目标处理还规定：目标范围内没有可通行格时，按 x、y 升序选取最近替代终点。AI 轨迹仍会因不同开局在第 602 或 1806 帧失配，下一步要继续核对施工转维修时的车体方向和移动惯性

该源码树的 `03-deobfuscated/.../game/MovementController.java` 虽名为 MovementController，内容实际是带目标、高度、命中逻辑的弹体类。因此该仓库 `docs/06-world/MOVEMENT.md` 对此类的“单位每帧移动控制器”描述不宜直接作为移植依据

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
