# 逐帧状态对照

六人 AI 自动开房与统一特性验收见 [原版特性与同步验收矩阵](rw_feature_matrix.md)

这套探针用于定位联机模拟从哪一帧开始与 OPEN-RW 1.15 分叉。原版探针源码位于 `C:\Users\Administrator\Documents\Codex\open-rw-probe`，它是下载源码的独立副本。默认关闭，只有设置输出路径才会写文件。

## 先验证原版探针

```powershell
cd C:\Users\Administrator\Documents\Codex\open-rw-probe
.\run_probe.ps1 -Interval 5 -MaxFrame 120
```

这会无界面运行 OPEN-RW 的菜单演示战斗，写入 `probe-output\reference.tsv`，然后自行退出。它是探针的冒烟测试，不能直接拿来与 Godot 联机对比。

可以用 Small Island 做一个无需开房的开局基线：OPEN-RW 用 `-MapPath 'maps/skirmish/[p2]Small_Island (2p).tmx' -Interval 10 -MaxFrame 50 -Rebuild` 运行；Godot 设置 `RW_PROBE_PATH` 和 `RW_PROBE_INTERVAL=10` 后运行 `--script tests/rw_small_island_reference_test.gd`。两份输出用比较器对照。这只覆盖 4 个开局单位的前 50 帧，已用来校正指挥中心的内部机身角和炮口角。

若把 OPEN-RW 采样间隔改成 1 并延长到 500 帧，可以设置 `RW_REFERENCE_COMMAND_TRACE` 指向它的 TSV、`RW_REFERENCE_FRAMES=500`，让 Godot 测试脚本重放首批建造命令及逐帧模拟步长。原版建造者的首次路径点为 `(950, 430)`；Godot 现在使用相同路径点、约 16 像素的路径点切换距离，以及按模拟步长计算的转向和加速。原版探针必须记录 `BaseUnit.cm` 作为实际建造进度；`cn` 是另一项进度状态，不能用于比较建筑完成度。一次 2800 帧采样中，建造者第 99–2317 帧连续 2219 帧、抽取器第 411–2160 帧连续 1750 帧通过逐字段对照，抽取器建造进度容差为 `0.0001`。第 2161 帧起原版新增的第二名建造者参与施工，本地脚本尚未重放其生产，因而这之后的施工进度不具可比性。菜单 AI 的命令时间和目标也会变动；这个重放用于定位差异，不作为联机同步通过的依据。

## 全部原生类型的出生状态

独立的 OPEN-RW 探针副本支持 `-SpawnAllNative`，在 Small Island 中额外生成全部 52 种原生类型，并为每个对象输出 `declared_type`。探针副本修复了反编译代码中 `damagingBorder` 与 `tankDestroyer` 的类型构造错误。先运行 `run_probe.ps1 -MapPath 'maps/skirmish/[p2]Small_Island (2p).tmx' -SpawnAllNative -Rebuild -Interval 1 -MaxFrame 1 -OutputPath 'C:\Users\Administrator\Documents\Codex\open-rw-probe\probe-output\all-native-effective.tsv'`，再设置 `RW_NATIVE_REFERENCE` 为该 TSV、设置 `RW_PROBE_PATH` 为 Godot 输出路径，运行 `--script tests/rw_all_native_reference_test.gd`。最后用比较器的 `--declared-only --fields team,x,y,rot,weapon_rot,hp,build` 对照。当前 52 个对象的首帧状态均通过。这一结果只覆盖出生状态，不能证明移动、战斗、生产或联机同步正确。

## 空中单位连续移动基线

在独立 OPEN-RW 探针副本中运行 `run_probe.ps1 -MapPath 'maps/skirmish/[p2]Small_Island (2p).tmx' -SpawnAllNative -Rebuild -Interval 1 -MaxFrame 100 -OutputPath 'C:\Users\Administrator\Documents\Codex\open-rw-probe\probe-output\all-native-move.tsv'`。探针在第 1 帧给可移动的原生单位插入相对起点 `(80, 60)` 的移动命令。设置 `RW_NATIVE_REFERENCE` 为该 TSV，设置 `RW_PROBE_PATH` 为 Godot 输出路径，再运行 `--script tests/rw_native_movement_reference_test.gd`。Godot 测试重放第 1 帧的起点、命令和每帧模拟步长；默认使用原版第 2 帧的首个路径点，设置 `RW_NATIVE_USE_GODOT_PATH=1` 后改由 Godot 自己寻路。测试不读取原版后续的位置和角度。可用 `RW_NATIVE_UNIT_IDS` 指定逗号分隔的原版单位 ID，默认对照 ID 8、9、23、37。

用比较器加上 `--unit-id 8 --unit-id 9 --unit-id 23 --unit-id 37 --fields x,y,rot,order,order_x,order_y,path_x,path_y --end-frame 90 --min-shared-frames 90`，目前 90 帧、360 个单位帧对均在默认容差内。运输机、直升机、拦截机、两栖喷气机包含普通移动和滑行移动两种模式。第 91 帧以后，个别原版单位改变路径或命令；此测试未重放地图上的 AI 和其他单位，因此不把后续分叉视作同条件移动误差。该测试仍不覆盖多段寻路、碰撞、攻击和联机校验。

探针还输出 `speed`、`turn_speed`、`turn_accel`、`move_accel`、`move_decel`、`sliding` 和 `ignores_body`。`tests/rw_native_movement_parameters_test.gd` 以这些字段核对全部 52 种原生类型；建筑和隐藏物体不参与移动参数判断，原生 Gunship 出生时尚未升空，速度为动态值。当前检查通过。设置 `RW_NATIVE_UNIT_IDS=6,8,9,12,15,17,19,20,21,23,29,37,40,55,56` 与 `RW_NATIVE_USE_GODOT_PATH=1`，同一个连续轨迹测试会让 Godot 自己寻路并对照 15 种地面、悬浮、海上和空中单位。前 93 帧共 1395 个单位帧对通过，位置最大误差约 0.27 像素、角度最大误差约 0.062°。第 94 帧原版 AI 改写了部分单位命令，测试未重放该行为。现有对照只证明这些特定单位及时间区间，不代表全部单位的长期联机状态已同步。

## 单位校验值

OPEN-RW 探针还写出 `all-native-move.tsv.checksum.tsv`。设置 `RW_NATIVE_REFERENCE` 为对应单位轨迹、`RW_CHECKSUM_REFERENCE` 为该校验轨迹，运行 `--script tests/rw_native_checksum_reference_test.gd`。目前主校验值及可从单位状态还原的七项字段在 100 帧、每帧 54 个参与校验的单位上通过。在这个从单位轨迹重建状态的测试中，`UnitPaths` 只有首帧通过逐项对照；其余帧的轨迹只记录当前路径点，无法凭该文件还原完整待走路径。树木和 Spreading Fire 在原版不是参与此校验的可命令单位。

在 OPEN-RW 探针轨迹中额外记录每个单位的 `path_sum` 与完整 `path_points` 后，可以用 `RW_NATIVE_CHECKSUM_OUTPUT` 让 `tests/rw_native_movement_reference_test.gd` 输出 Godot 的逐单位 `UnitPaths`。此前第 2 帧的 23 个移动单位中有 11 个路径校验不同：原版使用角度与三角函数查表，再以 32 位浮点逐段累加，所以 Hover Tank 的路径点是 `412.0091, 223.98785`，而不是精确直线插值的 `412.0, 224.0`。Godot 现已复现该算法，并在找不到可通行路径时保留原版的起始格中心点；空闲减速与该路径点的清除也已接入。`tests/rw_native_path_checksum_reference_test.gd` 对照 23 个单位首次生成路径的原版校验值，全部通过。完整 100 帧轨迹的第 1–93 帧共 2139 个单位帧对中，逐单位 `UnitPaths` 校验值一致，位置、角度、命令和当前路径点均在比较器容差内。这个轨迹重放仍从原版读取首次路径出现的帧，所以尚未证明联机寻路调度时间一致；位置和角度也没有逐位一致。联机校验仍须以同局服务器结果为准，不能只依据画面相似判定同步成功。

首次路径校验的运行方法：让 OPEN-RW 探针以 `-SpawnAllNative -Interval 1 -MaxFrame 10` 输出 `all-native-path-points.tsv`，设置 `RW_NATIVE_REFERENCE` 指向该文件，然后运行 Godot `--script tests/rw_native_path_checksum_reference_test.gd`。

## 同一局联机对照

从 PowerShell 启动 Godot，使游戏进程继承环境变量：

```powershell
$env:RW_PROBE_PATH='C:\Users\Administrator\Documents\Codex\godot-battle.tsv'
$env:RW_PROBE_INTERVAL='1'
& 'C:\Users\Administrator\Documents\Godot\Godot_v4.7.2-stable_win64.exe' --path 'C:\Users\Administrator\Documents\GodotProjects\rusted-godot' --editor
```

启动带探针的 OPEN-RW 客户端并加入同一个原版无模组房间：

```powershell
cd C:\Users\Administrator\Documents\Codex\open-rw-probe
.\run_probe.ps1 -Interactive -MaxFrame -1 -Interval 1
```

交互模式的完整联机流程尚未验证。两端应使用同一地图、玩家顺序和服务器命令。结束对局后执行：

```powershell
cd C:\Users\Administrator\Documents\GodotProjects\rusted-godot
py -3 tools\compare_rw_state_traces.py C:\Users\Administrator\Documents\Codex\open-rw-probe\probe-output\reference.tsv C:\Users\Administrator\Documents\Codex\godot-battle.tsv --unit-id 2
```

比较器按帧号和单位 ID 对齐，报告第一个超出容差的字段。若两端帧号相差固定值，用 `--frame-offset`；单位 ID 不同，用 `--id-map mapping.json`，文件内容例如 `{"2": 7}`。`--unit-id` 可重复使用。默认比较位置、机身角、炮口角、血量、建造进度和命令；`--fields x,y,rot,weapon_rot` 可以缩小范围，`--start-frame` 和 `--end-frame` 可指定对照区间。

OPEN-RW 还输出碰撞推力偏移 `push_x`、`push_y`。Godot 目前没有独立保存这两个值，所以对应列为空；比较器会跳过空的数值列。要精确校准出厂挤压，还需要让 Godot 在碰撞步骤中保存当帧位移，并建立完全相同的初始单位与命令回放。

## 无人值守长测

原版创建无模组 `Small Island (2p)` 私有房间后，可用下面的命令让 Godot 自动加入。原版需要随后开始对局，并保持运行至少 30 分钟：

```powershell
$env:RW_SOAK_ADDRESS='192.168.169.1:5123'
$env:RW_SOAK_REPORT_PATH='C:\Users\Administrator\Documents\Codex\small-island-soak.jsonl'
$env:RW_PROBE_PATH='C:\Users\Administrator\Documents\Codex\small-island-godot.tsv'
$env:RW_PROBE_INTERVAL='30'
& 'C:\Users\Administrator\Documents\Godot\Godot_v4.7.2-stable_win64.exe' --headless --path 'C:\Users\Administrator\Documents\GodotProjects\rusted-godot' 'res://tests/rw_multiplayer_soak.tscn'
```

`RW_SOAK_DURATION` 可调整对局秒数，默认 1800 秒。`RW_SOAK_START_TIMEOUT` 默认 300 秒，等待房主开始；`RW_SOAK_STALL_TIMEOUT` 默认 20 秒。报告每 10 秒记录帧号、下一同步边界、单位数量和命令数量；断线、地图不符、开局加载失败或同步帧停滞时返回非零退出码。

2026-10-04 的两次在线对照分别推进到第 45,770 帧和第 25,410 帧，结束原因依次为连接关闭与原版返回房间。第二次测试记录到服务端返回房间消息，已将这种结束原因与真正的同步帧停滞区分开。两次都没有完成 1800 秒目标。开始静止状态的单位校验可以一致；执行建造和生产命令后仍有状态差异，不能据此宣称兼容完成。

第三次对照完整运行 1800 秒，到第 108,009 帧，收到 258 条命令和 359 次服务端校验请求，连接未中断。第 0 帧及第 301 帧的单位校验一致；其余 357 次请求均报告差异，第一次在第 602 帧，涉及单位位置、方向和 `UnitPaths`。报告位于 `C:\Users\Administrator\Documents\Codex\small-island-soak-round3.jsonl`。这证明本轮客户端能够保持 30 分钟联机和同步帧推进，但不证明战斗模拟状态兼容。

第 602 帧的差异可从 OPEN-RW 的寻路调度解释：同一组命令的离线 OPEN-RW 在第 602 帧与旧版 Godot 的 `UnitPaths` 完全一致，而服务端第 602 帧的单位位置、方向和路径校验均与离线 OPEN-RW 第 589 帧一致。OPEN-RW `gameFramework/k/l.java` 对短距离异步寻路设置 12 帧计时器；计时归零后，还要等待一次检查与单位更新才能使用路径。Godot 现在仅在联机且直线路径受阻时按原版的格子距离分档等待；Small Island 首条建造路径在命令后的第 14 次单位更新中使用。`tests/rw_path_delay_reference_test.gd` 验证计时，`tests/rw_online_trace_replay_test.gd` 用第三轮真实命令及第 602 帧服务端校验重放。此代码是在第三次长测进程启动后写入，未包含在第三次结果中；其他路径类型和长期轨迹仍须新的同局测试确认。

第四次在线对照完整运行 1800 秒，到第 108,013 帧正常结束，收到 23 条命令和 359 次校验请求。命令记录位于 `C:\Users\Administrator\Documents\Codex\small-island-soak-round4.jsonl`，Godot 逐单位轨迹位于同名 `.tsv`。这一轮有 18 次单位主校验一致，但七项单位字段全部一致的只有第 0、301、602 帧；首个主校验差异在第 5418 帧。第 5200 帧开始建造陆军工厂时，Godot 原先强制逐格寻路，首个路径点为 `(1030, 1730)`，而原版在通畅路线上生成 `(1023.30237, 1707.685)`。建造命令现在先检查直线路径：通畅时使用原版的 20 像素分段，受阻时保留逐格路径。用本轮命令离线重放后，第 7224 帧单位主校验与服务端一致，都是 `13503620`；原始浮点位仍有微小差异。可设置 `RW_SOAK_REPORT_PATH` 为本轮 JSONL、`RW_REPLAY_TARGET_FRAME=7224`、`RW_REPLAY_EXPECT_MAIN_MATCH=1`，再运行 `--script tests/rw_online_trace_replay_test.gd` 重现这一检查。`tools/extract_rw_soak_commands.py` 可以将 JSONL 命令导出为独立 OPEN-RW 探针接受的 TSV。第四次在线进程启动于该修正之前，因此其在线差异仍是旧代码的实测结果，修正后的联网长期状态尚未验证。

第四轮第 7220 帧的长距离受阻路径已用双向网格搜索修正。源码探针与 Godot 导出的 Small Island 陆地寻路网格有 12,100 格，静态代价、建筑阻挡和障碍间距逐格一致。原版从前方搜索 400 次后开始前后交替搜索，并以单位朝向限制相邻转角；Godot 按这些规则生成的 34 个路径点与原版第 7250 帧完全一致。用第四轮真实命令离线重放到第 8127 帧，`UnitPaths` 与服务端同为 `9213313024`，单位主校验值只差 11；到第 8428 帧，两端已在相同 ID 和格子生成抽取器，主校验值只差 1。逐字段位置和方向仍有浮点与碰撞差异，且这些修正没有包含在第四轮已运行的在线进程中。

第六轮在线对照完整运行 1800 秒，到第 108,003 帧正常结束，收到 224 条命令和 359 次服务端校验请求，未断线或停帧。房间使用默认初始单位，实际初始资金预设为 200,000；第 0 帧单位校验一致，单位主校验第一次失配在第 1806 帧，当时原版指挥中心刚生产侦察机并下达移动命令。报告在 `C:\Users\Administrator\Documents\Codex\small-island-soak-round6.jsonl`，逐单位轨迹在同名 `.tsv`。这次在线进程启动于本段修正之前，其 358 次分项校验失配不能用来判定修正后的在线结果。

第六轮命令中的移动路径已经携带原版预先算好的格子序列。Godot 旧版错误地再次平滑路径，并为已经携带路径的命令等待异步寻路。现在保留服务器路径的格子顺序，按原版略去最后一个格子中心、改用精确目标坐标；收到现成路径后立即开始移动。独立 OPEN-RW 探针副本可以将命令 TSV 中的路径注入原版单位，重放第 1806 帧得到和在线服务端完全相同的 `UnitPaths=32219363867`。Godot 当前用第六轮命令离线重放也得到同一数值，侦察机位置与该原版探针相差约 0.2 像素，单位主校验仍相差 1872，机身方向约差 9.7 度。新出厂单位的离厂寻路延迟与受阻起点的 60 像素临时路径点已接入，但碰撞推力和转向仍未逐帧对齐。下轮在线对照需要确认这些离线修正是否保持同局同步。

这些在线日志与独立的 OPEN-RW 探针定位了两项可复现差异：原版原生工厂在没有集结点时用角度查表计算离厂目标，指挥中心在 `(990, 1670)` 生产时的目标 X 为约 `988.9655`；原版建造者放置海军基地的有效施工距离为 `85 + 110 = 195`。修正后的离线重放在第 3182 帧生成海军基地，OPEN-RW 在第 3180 帧生成。未完工的工厂现在也会暂停生产队列，等待建筑进度达到 1.0。对应的 Godot 检查为 `tests/rw_factory_exit_reference_test.gd` 与 `tests/rw_build_range_reference_test.gd`。

这个长测只验证连接和帧持续推进。原版的 `PACKET_SYNCCHECKSUM` 到来时，Godot 当前仍返回“无法提供完整校验”；报告会尽量写 `checksum_unit_match` 或 `checksum_unit_mismatch`，对照主校验值与单位位置、方向、血量、ID、命令、命令位置和路径字段。如果请求的帧超出最近 640 帧的快照窗口，报告写 `checksum_unverified`。团队资金、单位计数、团队信息和指挥中心内部计数尚未参与本地对照，因此 `checksum_unit_match` 及 `transport_completed` 都不能作为全部状态完全同步的证明。完整验证还需要同一局的 OPEN-RW 探针日志通过上面的逐帧比较器，并补齐服务端校验及重同步处理。比较器按帧流式读取，可直接处理长测日志；`--min-shared-frames` 可要求至少多少个共同帧。

第八轮在 2026-10-04 完整运行 1800 秒，到第 107,959 帧正常结束，收到 166 条命令和 359 次服务端校验请求，没有断线或停帧。记录在 `C:\Users\Administrator\Documents\Codex\small-island-soak-round8.jsonl`。这一轮运行时尚未包含下面的修正，所以原日志里的失配仍是旧版本的结果。离线探针必须设置本局的 200,000 初始资金，并保留建造命令的排队标志，才能复现建筑生成。Godot 现已按原版将建造者附近的移动单位计入寻路代价，校正原生寻路的转角限制与生产队列的 32 位浮点累加，并补上指挥中心的攻击弹体。建造者进入施工范围后继续减速、转向，朝向目标 30° 以内才生成建筑。直线路径建造命令的路径在下一帧投入使用。使用本局命令重放到第 6,622 帧，Godot 和服务端的单位主校验值同为 `22,721,364`，单位 ID、血量、命令和路径字段也一致；单位位置仍有微小浮点差异。第 9,933 帧的主校验仅差 4，路径字段仅差 252 个原始位整数单位，单位 ID、血量、命令字段仍一致。方向分项有一项持续失配：服务端侦察机的校验角与 OPEN-RW 探针的运动朝向一致，但与探针及 Godot 的机身角不同，仍需确认原版客户端实际绘制角度。修正后的联机长期状态尚未重新验证。
