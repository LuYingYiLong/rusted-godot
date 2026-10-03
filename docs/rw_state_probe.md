# 逐帧状态对照

这套探针用于定位联机模拟从哪一帧开始与 OPEN-RW 1.15 分叉。原版探针源码位于 `C:\Users\Administrator\Documents\Codex\open-rw-probe`，它是下载源码的独立副本。默认关闭，只有设置输出路径才会写文件。

## 先验证原版探针

```powershell
cd C:\Users\Administrator\Documents\Codex\open-rw-probe
.\run_probe.ps1 -Interval 5 -MaxFrame 120
```

这会无界面运行 OPEN-RW 的菜单演示战斗，写入 `probe-output\reference.tsv`，然后自行退出。它是探针的冒烟测试，不能直接拿来与 Godot 联机对比。

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

比较器按帧号和单位 ID 对齐，报告第一个超出容差的字段。若两端帧号相差固定值，用 `--frame-offset`；单位 ID 不同，用 `--id-map mapping.json`，文件内容例如 `{"2": 7}`。`--unit-id` 可重复使用。默认比较位置、机身角、炮口角、血量、建造进度和命令；`--fields x,y,rot,weapon_rot` 可以缩小范围。

OPEN-RW 还输出碰撞推力偏移 `push_x`、`push_y`。Godot 目前没有独立保存这两个值，所以对应列为空；比较器会跳过空的数值列。要精确校准出厂挤压，还需要让 Godot 在碰撞步骤中保存当帧位移，并建立完全相同的初始单位与命令回放。
