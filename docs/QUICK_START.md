# 🚀 快速开始指南

## ✅ 已完成的工作

### 1. **资源文件已复制**
- ✅ 纹理：`Assets/Textures/Natural/`
  - stone.png
  - dirt.png
  - grass_block.png
  - cobblestone.png
  - oak_log.png
  - oak_log_top.png

- ✅ 方块定义：`Data/blocks/nature/`
  - stone.json
  - dirt.json
  - grass.json
  - cobblestone.json
  - oak_log.json (带方向状态)

- ✅ 配置文件：
  - `Data/blocks/_manifest.json`
  - `Data/blocks/nature/config.json`

### 2. **核心系统已实现**
- ✅ `BlockManager.cs` - 主协调器
- ✅ `BlockDataLoader.cs` - JSON 加载器
- ✅ `BlockRegistry.cs` - 方块注册表
- ✅ `BlockStateRegistry.cs` - 状态注册表
- ✅ `BlockManagerExample.cs` - 示例代码

## 🎮 运行示例

### 方法 1：直接运行示例场景
```bash
# 在 Godot 编辑器中
1. 打开 systems/blocks/examples/block_manager_example.tscn
2. 按 F5 运行场景
3. 查看控制台输出
```

### 方法 2：在代码中使用
```csharp
// 在你的场景脚本中
public partial class MyScene : Node
{
    public override void _Ready()
    {
        var blockManager = new BlockManager();
        AddChild(blockManager);
        
        // 初始化（会自动加载所有方块）
        blockManager.Initialize();
        
        // 使用注册表
        var stone = blockManager.BlockRegistry.GetByString("voxelpath:stone");
        GD.Print($"找到方块: {stone.DisplayName}");
    }
}
```

## 📊 预期输出

运行示例场景后，你应该看到：

```
=== BlockManager Initialization Started ===
[BlockManager] Creating components...
[BlockManager] Components created
[BlockManager] Loading manifest: res://Data/blocks/_manifest.json
[BlockManager] Manifest loaded: 1 categories
[BlockManager] Loading categories...
[BlockManager] Loading category: res://Data/blocks/nature
[BlockManager] Category 'nature' loaded: 5 blocks
[BlockManager] Loaded 1 categories
[BlockManager] Registering blocks...
[BlockManager] Registered: voxelpath:stone (ID: 0)
[BlockManager] Registered: voxelpath:dirt (ID: 1)
[BlockManager] Registered: voxelpath:grass (ID: 2)
[BlockManager] Registered: voxelpath:cobblestone (ID: 3)
[BlockManager] Registered: voxelpath:oak_log (ID: 4)
[BlockManager] Registered 5 blocks
[BlockManager] Generating block states...
[BlockStateRegistry] Registered 1 states for block 0 (stone)
[BlockStateRegistry] Registered 1 states for block 1 (dirt)
[BlockStateRegistry] Registered 1 states for block 2 (grass)
[BlockStateRegistry] Registered 1 states for block 3 (cobblestone)
[BlockStateRegistry] Registered 6 states for block 4 (oak_log)
[BlockStateRegistry] Registered 10 total states for 5 blocks
[BlockStateRegistry] Integrity check passed ✓
[BlockRegistry] Integrity check passed ✓
=== BlockManager Initialization Complete ===
Total blocks: 5, Total states: 10

=== Block System Statistics ===
Categories Loaded: 1
Total Blocks: 5
Total States: 10
Namespaces: voxelpath
Initialized: True
```

## 🎯 下一步

### 1. 添加更多方块
```bash
# 复制现有方块 JSON 作为模板
cp Data/blocks/nature/stone.json Data/blocks/nature/new_block.json

# 编辑 new_block.json
# 添加到 config.json 的 blocks 列表
# 重新运行
```

### 2. 测试方块查询
按示例代码中的快捷键：
- **F1** - 打印所有方块
- **F2** - 打印所有状态
- **F3** - 打印统计信息

### 3. 集成到你的游戏
参考 `docs/BLOCK_MANAGER_GUIDE.md` 获取详细的集成说明。

## 🐛 故障排除

### 问题：找不到 JSON 文件
- 检查路径是否正确（必须以 `res://` 开头）
- 确认文件已导入到 Godot 项目

### 问题：方块没有注册
- 检查 `config.json` 中的 blocks 列表
- 查看控制台错误信息
- 确认 JSON 格式正确

### 问题：纹理没有显示
- 纹理系统尚未实现（下一步工作）
- 当前只加载路径，不加载实际纹理

## 📝 系统架构总结

```
BlockManager
├── 加载 _manifest.json
├── 遍历 categories
│   ├── 加载 config.json
│   └── 遍历 blocks
│       ├── 解析 JSON (BlockDataLoader)
│       ├── 注册方块 (BlockRegistry)
│       └── 生成状态 (BlockStateRegistry)
└── 验证完整性
```

## ✨ 成就解锁

- ✅ 完整的方块数据结构
- ✅ NamespacedId 系统（支持模组）
- ✅ 方块状态系统（支持朝向、氧化等）
- ✅ JSON 配置系统
- ✅ 模块化架构
- ✅ 5 个可用方块
- ✅ 10 个方块状态
