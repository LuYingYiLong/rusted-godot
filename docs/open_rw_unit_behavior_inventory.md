# OPEN-RW 单位行为盘点

参考代码位于 `C:\Users\Administrator\Documents\Codex\open-rw-probe`。本盘点以该源码的命令、寻路和单位更新流程，以及其 `assets/units` 内置 INI 为准；Godot 对照当前工作区。OPEN-RW 是可插桩的反编译参考，其 `UnitTypeEnum` 编号顺序与项目原先的编号不一致，不能拿它推断原版联机编号。项目原有编号及关键行为最终仍需与原版 1.15 对局复验

可重复的 INI 扫描：

```powershell
python tools\audit_open_rw_unit_features.py C:\Users\Administrator\Documents\Codex\open-rw-probe\assets\units --output docs\open_rw_ini_key_inventory.json
```

此次扫描覆盖 **131 个 INI、121 个可加载的内置自定义单位、18 个配置区段族、615 种区段／字段组合**。`open_rw_ini_key_inventory.json` 保存每个字段对应的单位、文件，以及显式声明的移动参数。统计的是显式配置；`copyFrom` 继承的有效值、原生 Java 单位和第三方 Mod 还需分别追踪。配置字段出现、已被解析、模拟中真正执行，是三个不同的结论

## 源码中的行为层

| 层 | OPEN-RW 依据 | Godot 现状与缺口 |
| --- | --- | --- |
| 移动地形 | `UnitMovementType.java` 有 `NONE/LAND/BUILDING/AIR/WATER/HOVER/OVER_CLIFF/OVER_CLIFF_WATER`；`gameFramework/k/l.java` 为八种类型建网格，`gameFramework/k/i.java:350-416` 按水、悬崖、建筑和覆盖层计算费用 | 已分别保存 `BUILDING`、`OVER_CLIFF`、`OVER_CLIFF_WATER` 的移动类型和通行费用；Valley Pass 与 Small Island 的格子差异测试通过。复杂地图的完整路径仍待逐帧核对 |
| 命令类型 | `UnitCommandType.java` 定义 17 类；`units/y.java:2429-2453` 分派命令，`UnitCommand.java` 还带目标、建造数量、动作 ID、队列及过期标记 | `RwBattleCommandReader` 能识别 17 类，`RwUnitOrderController` 主要把目标类或坐标类转成移动；同名命令的完整语义尚未等价，详见下表 |
| 路径申请与释放 | `units/y.java:3942-4169` 包含直线可达、起点陷入障碍时最多 60 像素脱出、共享路径、异步任务、缓存与最多 120 个拐点；`gameFramework/k/l.java` 调度寻路任务 | 已修正建造者路径释放、工厂出口暂缓路径、目标修理的寻路半径和静止修理单位的动态代价；单项路径回归通过。路径缓存、异步实际完成帧、部分拐点裁剪与队形路径共享尚无逐帧等价证据 |
| 队形与跟随 | `units/y.java:2520-2710` 根据队长拐点、队形偏移、时间和距离动态切换跟随或独立寻路；碰撞中还按队形关系调质量 | `RwUnitOrderController` 有命令形成的目标位置，缺少持续的队长／队员状态机及脱队与归队规则 |
| 转向与滑行 | `units/y.java:2820-2980` 根据当前速度、距离、拐点数量、碰撞和是否忽略机身朝向决定速度，`y.java:637-700` 分别积分机身移动及滑行速度 | `RwUnitState.advance_movement()` 已有转向、加减速、滑行与接近目标的部分阈值；多拐点跳过、碰撞后的状态反馈、倒车及特殊朝向仍未完整覆盖 |
| 碰撞与避让 | `units/y.java:880-1135` 限制至多 10 个邻居、按距离排序，并结合质量、队形关系、单位是否移动、穿透深度与近期碰撞记录施加推力 | `battle_map.gd` 与 `RwUnitState` 已有挤压，但邻居收集、优先级、力衰减和对队形／寻路计时的影响尚未逐项对齐，直接影响离厂时侦察机与建造者的位置和角度 |
| 攻击移动 | `UnitBehaviorType.java` 有 `normal/strafing/moveaway/bomber`；`units/y.java:1800-2048` 决定追击、保持距离、轰炸与返航 | 目前战斗和路径是分开的近似处理；`RwUnitDefinition` 无攻击移动类型、速度和散布字段。内置 INI 的 `attackMovement` 显式出现在 bomber 上 |
| 开火策略与目标获取 | `units/a_f.java` 定义 7 种策略；`units/y.java:3390-3460` 按命令和策略调整扫描距离；炮塔还有多目标及被动目标规则 | `RwBattleCombat._find_target()` 只特殊处理 `attack_mode == 3` 和显式目标，随后选最近敌人；其余策略、扫描距离、攻击移动中的目标切换需补齐 |
| 施工、生产与出生 | `units/y.java:1700-1800,2059-2250` 处理建造／维修／回收；工厂类及自定义单位的生产队列和出口逻辑独立 | Godot 已有施工、生产队列、出口和建筑升级基线；施工帧、队列消耗、单位推出、占位冲突与所有特殊生产动作尚需逐帧验收 |
| 运输与卸载 | `UnitCommandType` 包含 `loadInto/loadUp/unloadAt`；`custom/ag.java:2327-2366` 读取运输容量、槽位、类别限制、卸载间隔、死亡处理等 | 当前订单能被解析并使单位靠近目标，但没有完整的载员容器、装卸判定、卸载计时和同步状态 |
| 自定义动作与状态 | `custom/ag.java` 解析转换、资源、能量、自动触发、动作冷却、施工期间临时形态；`custom/j.java` 更新形态、海拔、事件和动作 | Godot 有部分升级、形态转换和资源动作；动作条件、自动触发、临时形态、能量、事件与各类状态效果尚未形成通用模拟层 |
| 武器、投射物、死亡 | INI 中 60 个 turret 字段、65 个 projectile 字段；原生单位另有 Java 实现 | `RwBattleCombat` 有基础弹体、伤害、护盾和炮口状态；多炮塔时序、拦截、特殊弹体、死亡触发和随机性仍属逐帧未验证项 |
| 视觉状态 | INI 中有动画、腿部、挂件、特效、海拔漂浮和机身锁定；`custom/j.java` 更新 `posZ` | 可绘制外观不等于模拟状态一致。海拔、漂浮、移动尾迹、部分腿部和机身随炮塔转向影响视觉，并可能通过类别／碰撞影响其他逻辑 |

### 内置 INI 的 19 个移动字段

这些字段全部由扫描器列出。右栏只说明当前定义层能否承载对应值，不代表逐帧行为已经验证

| 字段 | 含义与当前状态 |
| --- | --- |
| `movementType` | 八种通行类型；Godot 已保持 `OVER_CLIFF`、`OVER_CLIFF_WATER` 的独立通行语义 |
| `moveSpeed`, `moveAccelerationSpeed`, `moveDecelerationSpeed` | 速度与加减速；已有定义和积分，逐帧待验 |
| `maxTurnSpeed`, `turnAcceleration` | 角速度和转向加速度；已有定义和积分，逐帧待验 |
| `moveSlidingMode`, `moveIgnoringBody` | 独立滑行速度及按路径方向移动；已为显式设为 true 的 27 种内置单位启用 |
| `moveSlidingDir` | 被 `custom/ag.java` 解析，但此源码未找到运行时引用；暂列待证实参数 |
| `reverseSpeedPercentage` | 倒车速度比例，`custom/j.java:3909-3911` 供 `units/y.java` 使用；Godot 无同名定义字段 |
| `joinsGroupFormations` | 能否加入群体队形；Godot 无对应单位字段及完整队形状态机 |
| `ignoreMoveOrders` | 静态单位拒绝移动命令；Godot 以移动速度和建筑逻辑近似，没有独立语义 |
| `targetHeight`, `targetHeightDrift`, `heightChangeRate` | 海拔目标、漂浮、上升下降速度；Godot 出生海拔有状态，但缺完整逐帧高度行为 |
| `landOnGround` | 在地面着陆或仅空闲着陆；Godot 缺对应状态机 |
| `fallingAcceleration`, `slowDeathFall`, `slowDeathFallSmoke` | 坠落和死亡阶段表现；Godot 缺完整高度／死亡联动 |

`custom/ag.java` 还能解析内置 INI **未显式使用** 的 `moveYAxisScaling` 等参数，因此本表是内置单位的实际字段全集，并非第三方 Mod 配置语法的全集

## 17 类命令的执行语义

命令枚举和网络解码覆盖全部 17 类；以下“部分”指 Godot 有入口，但未证明与 `units/y.java:2429-2453` 的状态机一致

| 命令 | OPEN-RW 关键行为 | Godot 判定 |
| --- | --- | --- |
| `move` | 到点、路径耗尽、速度归零或滑行 | 部分；基础路径可运行 |
| `attack` | 追踪目标，按射程及行为类型接近／撤离 | 部分；目标移动与战斗分开模拟 |
| `build` | 放置、接近、创建施工单位、持续施工 | 部分；抽取器已双向可见 |
| `repair` | 接近、修复生命与施工进度、扣资源 | 部分 |
| `loadInto` | 接近并登上指定运输工具 | 缺完整装载 |
| `unloadAt` | 驶往地点，按规则逐个卸载 | 缺完整卸载 |
| `reclaim` | 接近、拆解目标、返还资源 | 部分 |
| `attackMove` | 路径上搜索并攻击敌人，再继续移动 | 部分；当前主要走移动路径 |
| `loadUp` | 运输工具主动接近并装载单位 | 缺完整装载 |
| `patrol` | 往返／循环巡逻，同时搜索目标 | 缺循环状态机 |
| `guard` | 保持动态距离，保护并协助目标 | 部分；当前以目标追踪为主 |
| `guardAt` | 守护坐标区域并搜索目标 | 部分；当前以到点为主 |
| `touchTarget` | 接触特定目标并触发相应行为 | 缺完整到达动作 |
| `follow` | 根据目标移动及距离动态跟随 | 部分；缺原版跟随阈值和队形规则 |
| `triggerAction` | 执行指定动作 ID | 部分；取决于动作具体类型 |
| `triggerActionWhenInRange` | 接近目标后再执行动作 | 缺完整范围门槛与动作状态 |
| `setPassiveTarget` | 设置被动攻击目标并结束该命令 | 部分；当前留作显式目标引用 |

## 侦察机专项结论

内置 `assets/units/scout/scout.ini:131-146` 将 `scout` 定为 **HOVER**，移动速度 `1.0`、加速 `0.03`、减速 `0.06`、最大转速 `2.4`、转向加速度 `0.2`，同时启用 `moveSlidingMode`、`moveIgnoringBody`，配置 `moveSlidingDir:181`。Godot 已载入前六项，并通过 `SLIDING_UNIT_TYPES` 启用两个滑行开关。扫描的 27 个显式设为 `moveSlidingMode:true` 的内置单位都在这张硬编码名单中；这里没有发现漏配侦察机滑行开关

`moveSlidingDir` 在该 OPEN-RW 源码的 `custom/ag.java:2582` 被解析进元数据 `dZ`，全源码搜索没有找到它的运行时读取。不能把该字段当作已证实的运动公式，也不能仅因此修改 Godot 的路径。`targetHeight/targetHeightDrift` 则在 `custom/j.java:1570-1655` 更新海拔和漂浮，主要解释绘制高度，不直接解释平面 X/Y 路径

更可能产生平面路径差异的候选是：

1. **路径任务时机和拐点**：Godot 用固定 `network_path_delay_frames()` 近似异步任务；OPEN-RW 可共享已有路径，按实际寻路任务返回并重写最后一个拐点
2. **离厂和碰撞**：侦察机由指挥中心生产时，出口路径与建造者相撞；邻居选择、质量及推力会改变随后每一帧的位置和朝向
3. **战斗中机身方向**：`scout.ini:44` 的 `lock_body_rotation_with_main_turret` 在 `custom/j.java:2360-2375` 影响机身角度；OPEN-RW 的 `units/y.java:2845-2847` 还会在有目标时改变忽略机身朝向单位的移动朝向。Godot 尚未把这些规则完整接入侦察机
4. **地图类型成本**：侦察机走 HOVER 网格；直达检测、资源点、悬崖、覆盖层和临近建筑的成本必须与源代码逐格相同

2026-10-04 已用 Small Island 的 OPEN-RW 指挥中心生产记录核对侦察机出生后的前 100 帧：位置、机身朝向和第 30 帧形成的 60 像素离厂路径点在 0.1 像素／0.1 度容差内一致。此项测试包含指挥中心占地阻挡；此前不包含该阻挡的孤立测试会在第 79 帧才出现差异，不能用作离厂结论。尚需继续比较**与建造者实际碰撞**、障碍绕行、攻击中路径和长期运行

Valley Pass 的一条修理订单还确认了原版目标半径 1 格及静止修理单位的动态避让代价。对应的五个寻路点已在单项测试中一致。六人 AI 对局首次轨迹误差由第 70 帧推迟到第 880 帧；第 880 帧开始的建造者挤压仍有差异。OPEN-RW 与原版 1.15 的联机编号不同，**这些测试不证明原版 1.15 的建造编号或所有运动规则一致**

## 实施顺序

1. 将侦察机的四组场景加入 OPEN-RW 探针和 Godot 自动对照；先定位第一个失配帧
2. 对齐八类移动网格、直达判定、路径释放与拐点状态，再校准滑行和碰撞
3. 实现命令状态机的巡逻、护卫、攻击移动、装卸与动作触发语义
4. 将自定义单位的移动／攻击／运输／能量／自动动作参数从 INI 映射到统一定义，而非继续增补按单位名硬编码的特例
5. 逐项用原版客户端复验，并把已证明一致的特性标记到 `rw_feature_matrix.md`
