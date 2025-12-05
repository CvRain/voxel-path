# SimpleVoxelWorld - 快速开始指南

## 📋 概述

`SimpleVoxelWorld` 是一个快速原型脚本，用于在场景中生成基础的体素世界。

## 🎮 当前功能

### 已实现
- ✅ **平坦石头世界** - 10 格高的石头平台
- ✅ **自动材质** - 加载 `stone.png` 纹理（如果存在）
- ✅ **基础网格** - 使用 VoxelMesherBlocky 生成方块
- ✅ **自动碰撞** - VoxelTerrain 自带物理碰撞

### 场景结构
```
LevelPlayground
├── SimpleVoxelWorld (脚本节点)
│   └── VoxelTerrain (自动创建)
├── DirectionalLight3D
├── WorldEnvironment
├── Player (Y=15，在世界上方)
├── WorldInteractionManager
└── BlockSelector
```

## ⚙️ 配置参数

在 Godot 编辑器中选择 `SimpleVoxelWorld` 节点可以调整：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `world_size` | 64 | 世界大小（未使用，预留） |
| `world_height` | 32 | 世界高度（未使用，预留） |

当前使用 `VoxelGeneratorFlat`：
- 高度：10 格
- 方块类型：石头（ID=1）

## 🔧 如何修改

### 1. 改变世界高度
编辑 `simple_voxel_world.gd` 的 `setup_voxel_generator()` 函数：
```gdscript
generator.height = 20.0  # 改为 20 格高
```

### 2. 添加更多方块类型
编辑 `setup_voxel_library()` 函数：
```gdscript
# 添加泥土方块（ID=2）
var dirt_model = VoxelBlockyModelCube.new()
dirt_model.set_material_override(0, create_dirt_material())
library.add_model(dirt_model)
```

### 3. 切换生成器类型

#### 使用噪声地形：
```gdscript
func setup_voxel_generator():
    generator = VoxelGeneratorNoise.new()
    generator.channel = VoxelBuffer.CHANNEL_TYPE
    # 配置噪声参数...
```

#### 使用自定义生成器：
```gdscript
func setup_voxel_generator():
    generator = VoxelGeneratorScript.new()
    # 编写自定义生成逻辑
```

## 🎨 材质配置

当前材质设置：
- **有纹理**：加载 `res://Assets/Textures/Natural/stone.png`
- **无纹理**：使用纯灰色（Color(0.5, 0.5, 0.5)）
- **过滤模式**：`NEAREST`（像素风格）

修改 `create_stone_material()` 来调整外观。

## 🎯 下一步集成

### 与 BlockRegistry 集成
将来可以这样连接你的方块系统：
```gdscript
# 在 SimpleVoxelWorld 中
var block_manager: Node  # 引用 BlockManager

func setup_voxel_library():
    library = VoxelBlockyLibrary.new()
    
    # 从 BlockRegistry 加载方块
    for block_id in block_manager.get_all_block_ids():
        var block_data = block_manager.get_block(block_id)
        var model = create_model_from_block_data(block_data)
        library.add_model(model)
```

### 方块交互
使用脚本提供的方法：
```gdscript
# 获取方块
var block_id = voxel_world.get_voxel(Vector3i(0, 10, 0))

# 放置方块
voxel_world.set_voxel(Vector3i(0, 11, 0), 1)

# 射线检测
var result = voxel_world.raycast(origin, direction, 10.0)
if result:
    print("Hit block at: ", result.position)
```

## 🐛 故障排除

### 问题：看不到世界
- 检查控制台是否有 "=== World generation started ===" 消息
- 确保 Player 的 Y 坐标在 15（世界上方）
- 按 F 键切换飞行模式，下降到地面

### 问题：没有纹理
- 检查 `res://Assets/Textures/Natural/stone.png` 是否存在
- 如果不存在，会显示纯灰色方块（这是正常的）

### 问题：性能问题
- 降低 `view_distance`（默认 128）
- 减少区块生成范围

## 📚 相关文档

- [godot_voxel 官方文档](https://voxel-tools.readthedocs.io/)
- [VoxelTerrain API](https://voxel-tools.readthedocs.io/en/latest/api/VoxelTerrain/)
- [VoxelBlockyLibrary API](https://voxel-tools.readthedocs.io/en/latest/api/VoxelBlockyLibrary/)

## 🚀 运行测试

1. 打开 Godot 编辑器
2. 加载场景：`scenes/levels/level_playground.tscn`
3. 按 **F5** 运行
4. 观察控制台输出确认世界生成
5. 使用 WASD 移动，Space/Shift 上下飞行
6. 走到世界边缘查看地形

祝你开发愉快！🎮
