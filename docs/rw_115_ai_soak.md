# 原版 1.15 多人 AI 长局

`tools/run_rw_115_ai_soak.py` 从本机 Steam 安装只读复制运行资源，在 `C:\Users\Administrator\Documents\Codex\rw115-probe\RustedWarfare` 启动隔离的原版进程。启动前检查 `game-lib.jar` 的完整 SHA-256，要求与 `rw_analysis-master` 测试台记录的 1.15 stock jar 指纹一致。运行参数包含 `-nomods`，房间不加载第三方 Mod

原版自动创建本机私人房间，选择六人地图，加入 4 个 AI。Godot `rw_multiplayer_soak.tscn` 以第六个玩家加入后，原版才开局。脚本同时记录原版的玩家数、连接数、失步及重同步计数，以及 Godot 收到的命令、校验、同步帧和单位轨迹。运行结束会关闭本次启动的两个进程，不操作用户当前的原版对局

自动控制入口已从 `rw_analysis-master/02b-decompiled` 核对：`Debug.networkSetPortNumber()`、`Root.hostStartWithPasswordAndMods()`、`Debug.setMultiplayerMap()`、`Multiplayer.addAI()` 和 `Multiplayer.multiplayerStart()`。调用走原版自带的 Debug Socket `function` 通道，在游戏主线程执行；没有修改原版 jar

```powershell
cd C:\Users\Administrator\Documents\GodotProjects\rusted-godot
py -3 tools\run_rw_115_ai_soak.py
```

默认依次在累计运行 300、600、1200、1800 秒时验收，也就是先跑 5 分钟，通过后延长到 10 分钟，再尝试 20 和 30 分钟长验证。任一阶段出现单位校验差异、无法校验、原版失步或重同步，立即结束对局并在 `stages.jsonl` 记下失败；只有当前阶段至少有一次已验证的单位校验且没有差异才进入下一阶段。`--stages 300,600` 可只跑前两阶段，`--duration 35` 可做一次性快速检查。地图为 `[p6]Valley Pass (6p).tmx`，房间端口为 5125，调试端口为 5678；可用 `--map '[p8]Many Islands (8p).tmx' --ai 6` 扩展到八人。房间和调试端口必须空闲；`--port` 与 `--debug-port` 可调整。原版调试服务虽然接受 `:local` 参数，1.15 源码实际调用的是监听所有地址的 `ServerSocket(port)`；不要将调试端口暴露到其他网络

每次运行在隔离副本的 `probe-output/rw115-ai-soak-时间戳` 创建：

| 文件 | 内容 |
| --- | --- |
| `run.json` | 原版指纹、地图、AI 数和采样参数 |
| `summary.json` | 结束状态、最后帧、命令数、首个单位校验差异及分阶段验收结果 |
| `stages.jsonl` | 各阶段通过或失败的即时记录 |
| `godot.jsonl` | 进房、开局、命令、逐次校验与定期采样事件 |
| `godot.tsv` | Godot 单位状态轨迹，默认每 120 帧采样一次 |
| `original-metrics.jsonl` | 原版每 30 秒的玩家、连接、失步和重同步计数 |
| `original.stdout.log` / `godot.stdout.log` | 两边运行日志，另有对应 stderr 文件 |

`summary.json` 还统计每种单位校验字段的首次失配帧和失配次数，并记录原版进程观察到的最高失步、重同步计数。已有记录可用 `py -3 tools\summarize_rw_115_ai_soak.py 'C:\...\rw115-ai-soak-时间戳'` 重新生成摘要

长局探针按原版默认的每 301 帧校验节奏计算单位校验值，其余帧只在 `--trace-interval` 指定的间隔输出单位轨迹。服务端的校验请求可能早于 Godot 模拟到对应帧；采集器会暂存请求并在该帧生成后比较。测试结束时尚未模拟到的未来校验帧列入 `pending_future_checksum_count`，不计为状态“无法校验”

2026-10-04 的首次 35 秒自动化短局推进至第 2131 帧，收到 21 条命令；第 301 帧首次出现 `Unit Pos` 差异。原版 jar 会写 `.replay`，保存在隔离副本的 `replays` 目录

随后完成的首次 30 分钟长局记录为 `rw115-ai-soak-20261004-211519`：第 43,232 帧、1,321 条命令、结束时 426 个单位，原版主机报告 0 次失步和重同步。这轮从第 4515 帧起有 345 次校验未验证，且后期重复提示同步帧边界超出旧的 18,000 帧上限，因此其后期结果只证明持续连接和命令接收，不能证明继续逐帧跟上原版

已将同步帧领先上限调整为可覆盖一小时的 216,000 帧，并减少探针的逐帧校验开销。随后把移动中的转向阈值、碰撞执行单位与施工进度的 32 位浮点累加对齐原版，还修正了建筑格取整、向建造命令原始目标寻路、协助施工结束时的移动时序，以及被占用目标格的替代终点。`rw115-ai-soak-20261004-233119` 到第 1505 帧的单位字段一致，第 1806 帧仍有方向和位置差异。另一轮 AI 选择了不同的开局建筑，`rw115-ai-soak-20261004-233229` 在第 602 帧出现了微小方向和位置差异。随机 AI 开局之间不能用单次最晚失配帧概括整体精度；第一阶段尚未通过，因此没有启动 10、20、30 分钟阶段

该基线取自原版联机，不依赖 OPEN-RW 的单位枚举或 AI 公式。`rw_analysis-master/02b-decompiled` 用来解释原版行为和定位缺失特性；目前其反编译源码不能完整重编译，测试运行的仍是校验过指纹的原版 jar
