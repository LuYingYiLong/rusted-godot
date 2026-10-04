# 原版特性与同步验收矩阵

本清单把“类型已定义”“行为可执行”“逐帧一致”分开。单位纹理、出生参数或某个操作能显示，不代表联机状态已与原版一致。统一入口是 `RwUnitDefinition`、`RwUnitState`、`RwUnitBehavior`、`RwUnitOrderController`、`RwBattleCombat` 和 `RwProductionQueue`；原生单位与内置自定义单位都应通过这些接口接入

原版 1.15 的优先核对结果和自动测试入口见 [1.15 特性差异](rw_115_feature_diff.md)。[OPEN-RW 单位行为盘点](open_rw_unit_behavior_inventory.md)保留为辅助线索，其网络编号和长局结果不能替代 1.15 验收

## OPEN-RW 历史对照

| 特性 | OPEN-RW 辅助线索 | Godot 当前入口 | 已有证据与下一项验收 |
| --- | --- | --- | --- |
| 地图、出生物与玩家槽位 | `GameLogic.startGame`、`TileMap`、`PlayerTeam` | `RwTmxLoader`、`RwTmxUnitReader`、`RwRoomClient` | Small Island 双人及 Valley Pass 六人能开局；六人局第 0 帧单位校验一致。继续核对其他 6/8/10 人地图、随机种子与初始资金预设 |
| 原生单位与内置自定义单位的定义 | `UnitTypeEnum`、`assets/units/*.ini` | `RwVanillaUnitCatalog`、`RwUnitRegistry`、`RwVanillaCustomDefinitions` | 52 种原生类型的出生状态和移动参数测试通过；内置自定义单位已经注册，但其完整动作和长期状态未逐种核验 |
| 移动、转向、寻路、碰撞 | `UnitCommand`、`PathEngine`、单位更新与碰撞代码 | `RwUnitOrderController`、`RwPathGrid`、`RwUnitState` | 已分别验证跨悬崖移动网格、修理路径五个拐点与侦察机离厂前 100 帧。六人 AI 对照的首次轨迹误差从第 70 帧推迟到第 880 帧；第 880 帧建造者挤压仍有差异，最终需和原版 1.15 复验 |
| 建造、维修、回收、工厂生产 | 单位动作、建造者施工、工厂队列与出生出口 | `RwUnitBehavior`、`RwVanillaBuildings`、`RwProductionQueue`、`battle_map.gd` | 双人房间的抽取器建造双向可见，施工距离与生产出口有基线；六人 AI 局已收到 build、queue、repair 命令。需分别验证资源扣费、队列时间、完成帧、离厂挤压和特殊动作 |
| 武器、弹体、护盾、死亡 | 原生武器类和自定义单位炮塔/弹体配置 | `RwBattleCombat`、`RwWeaponDefinition`、`RwProjectileState`、`RwShieldBehavior` | 已有目标类别、弹体和基础伤害测试。炮口静置转动、命中帧、死亡顺序及战斗中的随机数尚未证明逐帧一致 |
| 资金和额外资源 | `PlayerTeam`、自定义资源定义 | `RwVanillaEconomy`、`RwResourceCatalog` | Credits、收入增长和资源接口已接入；应在 AI 的建造与升级中核对资金校验，并为自定义资源保留同一账本接口 |
| 战争迷雾、视野和小地图 | 地图视野与单位可见性 | `RwFogOfWar`、`hud_layer` | 三种迷雾模式可运行；需用多队伍和不同阵营检查共享视野、隐蔽单位、未探索资源点 |
| 命令和联机同步 | `NetworkEngine`、命令包、同步帧、校验包 | `RwBattleCommandReader`、`RwBattleTimeline`、`RwBattleStateProbe` | 双人房间 30 分钟传输稳定；六人 AI 局能自动入房、开局和收取命令/校验。第 0 帧校验一致，第 301 帧首次失配，说明传输成功还不足以判定模拟兼容 |
| AI 和多人对局 | `AIController`、`NetworkEngine.ap()` | Godot 作为客户端读取 AI 命令并本地模拟 | OPEN-RW 探针可私有开 6 人地图、加入 4 个 AI、等待 Godot 后自动开局。Godot 不需要复制 AI 决策算法，但必须正确执行服务器发来的全部 AI 命令 |
| 视觉、音效和 HUD | 原版渲染与音效资源 | `RwUnitVisual`、`RwAudioManager`、HUD 场景 | 视觉表现应跟随模拟状态；不能用视觉结果替代单位位置、炮口角或生产进度的状态校验 |

## OPEN-RW 辅助自动化对照

运行以下命令会在本机 5125 端口创建 OPEN-RW 私有房间，使用 `Valley Pass (6p)`，加入 4 个 AI，待 Godot 入房后自动开局，持续两分钟并保存双方记录。可用 `-MapName '[p8]Many Islands (8p).tmx' -AiCount 6` 扩展到八人地图。端口占用时用 `-Port` 指定其他端口

```powershell
cd C:\Users\Administrator\Documents\GodotProjects\rusted-godot
.\tools\run_open_rw_ai_soak.ps1 -DurationSeconds 120
```

脚本输出首次失配帧与字段，并保存 JSONL 报告和 OPEN-RW 的 TSV 逐单位轨迹。`checksum_unit_match` 只表示已核对的单位字段一致；资金、玩家信息、单位数量等字段仍需要独立计算。运行结束会关闭本次创建的本地房间。首次修改 OPEN-RW 探针源码后加 `-Rebuild`

2026-10-04 的基线记录 `ai-soak-20261004-190152` 首次轨迹差异在第 70 帧，单位位置差约 1.44 像素；第 301 帧校验差异包含 `Unit Dir` 和 `Unit Pos`。修正路径等待、180 度转向、目标寻路半径、静止单位避让和建造命令原始目标后，15 秒记录 `ai-soak-20261004-194227` 的首次轨迹差异推迟到第 880 帧，单位位置差约 0.14 像素；第 301 帧只剩 `Unit Pos` 差异，当时逐单位最大位置差约 0.0025 像素。40 秒记录 `ai-soak-20261004-194459` 也首次在第 880 帧偏离，之后碰撞、生产和单位数量差异继续累积。以上记录目录均在 `C:\Users\Administrator\Documents\Codex\open-rw-probe\probe-output` 下

OPEN-RW 的原生 `UnitTypeEnum` 网络编号顺序与此项目原先的编号不一致。曾尝试套用 OPEN-RW 编号来解释其 AI 建造命令，随后已撤回；当前目录和建筑编号保持原样。新加入的 [1.15 源码与原版 jar 核对](rw_115_source_reference.md) 已确认其 52 个原生枚举编号与项目目录逐项一致，且源码按枚举序号读写原生类型；本机原版 jar 的 SHA-256 与源码项目所列 stock 指纹一致，并已直接运行枚举探针。OPEN-RW AI 长时对照可用于定位运动算法候选，但其原生建造命令无法作为原版 1.15 协议验收依据
