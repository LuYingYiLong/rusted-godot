# RWX drawable 资源分类

从 RWX 的 `assets/drawable` 复制图片到 `assets/rwx/drawable`。源文件名保持不变，目录按用途区分：

| 目录 | 内容 |
| --- | --- |
| `units/land`、`units/air`、`units/naval`、`units/buildings`、`units/creatures` | 单位本体及与该单位配套的炮塔、阴影、残骸和动画部件 |
| `world/props`、`world/overlays` | 地图场景物件、水层和迷雾等覆盖层 |
| `effects` | 弹丸、爆炸、烟雾、火焰和地面痕迹等效果 |
| `ui/branding`、`ui/controls`、`ui/icons`、`ui/panels`、`ui/hud`、`ui/help`、`ui/errors` | 界面素材 |
| `system/debug` | 原版调试占位图片 |

`tools/import_rw_drawables.py` 保存了分类规则，遇到未归类或重复归类的文件会报错。复制时只处理 PNG/JPG；原版的 7 个 Android UI XML 不属于图片纹理，暂不导入。`.9.png` 仍是原始 Android nine-patch 图片，若用于 Godot 界面，需要另行处理其边框标记和九宫格边距。

新增或更新图片时，在项目根目录执行：

```powershell
py -3 tools/import_rw_drawables.py --source "<RWX_ROOT>\assets\drawable"
# 先用 Godot 编辑器打开项目，让新图片完成导入
py -3 tools/import_rw_drawables.py --catalog-only
```

`scripts/utils/rw_drawable_catalog.gd` 按原始文件名保存导入资源的 UID，例如 `RwDrawableCatalog.load_texture("tank2_turret.png")`。资源查找不依赖运行时扫描目录；当前导出预设使用 `all_resources`，新增图片完成导入并刷新 catalog 后会进入导出包。
