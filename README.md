# Leaf Cluster Light · 叶簇受光

让相邻叶团共享明暗，保留植物原来的轮廓、枝干、植株疏密和叶片几何。工具计算叶冠的着色法线，随引擎里的灯光实时受光。无需 Blender、Python、API 密钥或云服务。使用 Godot 4.6 Standard，本项目在 4.6.3 测试。

## 一键转换

在 Windows 上将 Godot 加入 PATH（命令名为 godot），或把环境变量 GODOT_BIN 设为 Godot 可执行文件的完整路径。下载并解压本仓库，把一个 .glb 模型拖到 **Relight.cmd**。输出会出现在输入文件旁，名称为 **原名-relit.glb**。原文件保留。再次转换前请给已有输出改名。

自动查找名字以 Crown、Foliage、Leaves 或 Leaf 开头的网格，忽略大小写。花冠若也叫 Crown，请显式指定叶网格。选择对象使用 glTF **mesh 名称**，一个 mesh 可以有多个材质面。未找到时程序会列出 mesh 名称。若枝干与叶片合在同一个 mesh，请先在建模软件中按材质拆开。

在 macOS、Linux 或 Windows 终端可以直接运行。以下示例在工具目录执行，建议使用模型的绝对路径。

```sh
godot --headless --path . --script res://convert.gd -- "/path/to/tree.glb"
godot --headless --path . --script res://convert.gd -- "/path/to/tree.glb" Foliage blade
```

## 选择效果

- **auto** 根据连通叶团与原法线的朝向估计模式。适合第一次试用。
- **outward / inward** 用于封闭的叶团。inward 对应原法线朝内、靠双面材质显示的模型。请在实际游戏光照下对照原件。
- **blade** 用于蕉叶、枇杷等大片薄叶，在共享受光基础上保留正反面和少量叶面弯曲。对逐株有器官数据的 Godot 生成器，`leaf_cluster_light.gd` 另提供 `tagged_blades` 接口，按 UV/UV2 里的叶柄位置与相位聚合；具体编码见函数注释。

每个 triangle primitive 独立计算。同位置的顶点用于识别连通叶团，以邻近叶团中心和整冠位置估计受光方向。全连通树冠、仅一张大平面或烘焙进颜色贴图的球形高光，通常需要先整理源资产。此工具在 mesh 局部 Y-up 坐标中工作，建议先应用植物朝向。普通有光照的漫反射材质最容易观察效果，法线贴图会影响最后画面。

## 文件兼容性

支持 GLB 2.0、一个内嵌 BIN、三角面、FLOAT VEC3 位置及法线，支持索引和交错存储。目标面上的稀疏属性、形变目标和压缩几何需要先展开。工具追加独立的 NORMAL 数据并更新所选面引用，其他面即使共享原法线也能保留原样。位置、索引、贴图、动画和关节数据沿用输入文件；风动、季节或开花行为由游戏负责。

## English

An offline, shape-preserving foliage relighter for Godot 4.6. Drag a GLB onto Relight.cmd or use the command above. Select a foliage-only mesh and compare the new sibling file under your scene lights. The converter appends shading normals only. Original geometry, rigging and textures are retained. The local Y axis is up. MIT licensed.
