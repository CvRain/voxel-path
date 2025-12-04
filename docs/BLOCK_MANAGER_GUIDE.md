# BlockManager 使用指南

## 🎯 概述

BlockManager 是整个方块系统的协调器，负责：
- 加载 Manifest 和方块配置
- 协调 BlockDataLoader、BlockRegistry、BlockStateRegistry
- 提供统一的初始化接口

## 📁 目录结构

```
Data/blocks/
├── _manifest.json          # 主清单文件
└── nature/                 # 分类目录
    ├── config.json         # 分类配置
    ├── stone.json          # 方块定义
    ├── dirt.json
    ├── grass.json
    ├── cobblestone.json
    └── oak_log.json

Assets/Textures/Natural/    # 纹理资源
├── stone.png
├── dirt.png
├── grass_block.png
├── cobblestone.png
├── oak_log.png
└── oak_log_top.png
```

## 🚀 快速开始

### 1. 在场景中使用

```csharp
// 创建 BlockManager 节点
var blockManager = new BlockManager();
AddChild(blockManager);

// 初始化系统
var success = blockManager.Initialize();

if (success)
{
    // 访问注册表
    var registry = blockManager.BlockRegistry;
    var stateRegistry = blockManager.BlockStateRegistry;
    
    // 查询方块
    var stone = registry.GetByString("voxelpath:stone");
}
```

### 2. 运行示例场景

1. 打开场景：`systems/blocks/examples/block_manager_example.tscn`
2. 运行场景（F5）
3. 查看控制台输出

**快捷键：**
- `F1` - 打印所有方块
- `F2` - 打印所有状态
- `F3` - 打印统计信息

## 📝 添加新方块

### 1. 创建方块 JSON 文件

```json
{
  "name": "my_block",
  "display_name": "My Custom Block",
  "category": "nature",
  "description": "A custom block",

  "texture_paths": {
    "north": "res://Assets/Textures/Natural/my_block.png",
    "south": "res://Assets/Textures/Natural/my_block.png",
    "east": "res://Assets/Textures/Natural/my_block.png",
    "west": "res://Assets/Textures/Natural/my_block.png",
    "up": "res://Assets/Textures/Natural/my_block.png",
    "down": "res://Assets/Textures/Natural/my_block.png"
  },

  "hardness": 1.0,
  "resistance": 1.0,
  "is_solid": true,
  "is_transparent": false,
  "has_collision": true,

  "can_place": true,
  "can_break": true,
  "tool_required": "none",
  "mine_time": 1.0
}
```

### 2. 添加到 config.json

```json
{
  "category": "nature",
  "blocks": [
    "stone.json",
    "dirt.json",
    "my_block.json"  // 添加这行
  ]
}
```

### 3. 添加纹理文件

将 `my_block.png` 放到 `Assets/Textures/Natural/` 目录

## 🎨 方块状态示例

带状态的方块（如原木）：

```json
{
  "name": "oak_log",
  "display_name": "Oak Log",
  
  "texture_paths": {
    "north": "res://Assets/Textures/Natural/oak_log.png",
    "south": "res://Assets/Textures/Natural/oak_log.png",
    "east": "res://Assets/Textures/Natural/oak_log.png",
    "west": "res://Assets/Textures/Natural/oak_log.png",
    "up": "res://Assets/Textures/Natural/oak_log_top.png",
    "down": "res://Assets/Textures/Natural/oak_log_top.png"
  },

  "state_definitions_json": "{\"facing\": [\"north\", \"south\", \"east\", \"west\", \"up\", \"down\"]}",
  "default_state_json": "{\"facing\": \"up\"}"
}
```

## 🔍 查询方块和状态

```csharp
// 获取注册表
var registry = blockManager.BlockRegistry;
var stateRegistry = blockManager.BlockStateRegistry;

// 1. 查询方块
var stone = registry.GetByString("voxelpath:stone");
var dirt = registry.GetByNamespacedId(new NamespacedId("voxelpath:dirt"));
var block = registry.GetById(1);

// 2. 获取默认状态
var defaultStateId = stateRegistry.GetDefaultStateId(stone.Id);
var defaultState = stateRegistry.GetStateById(defaultStateId);

// 3. 获取所有状态
var allStates = stateRegistry.GetAllStatesForBlock(oakLog.Id);

// 4. 切换状态属性
var newStateId = stateRegistry.CycleProperty(currentStateId, "facing");
var newState = stateRegistry.GetStateById(newStateId);
```

## 📊 当前已加载的方块

- ✅ stone（石头）
- ✅ dirt（泥土）
- ✅ grass（草方块）
- ✅ cobblestone（圆石）
- ✅ oak_log（橡木原木，6 个状态）

**总计：5 个方块，10 个状态**

## 🛠️ 系统架构

```
BlockManager (协调器)
├── BlockDataLoader (JSON 加载器)
├── BlockRegistry (方块注册表)
│   └── NamespacedId 系统
└── BlockStateRegistry (状态注册表)
    └── 笛卡尔积生成
```

## 🐛 调试

### 打印所有方块
```csharp
blockManager.PrintAllBlocks();
```

### 打印所有状态
```csharp
blockManager.PrintAllStates();
```

### 获取统计信息
```csharp
GD.Print(blockManager.GetStatistics());
```

### 验证完整性
```csharp
blockManager.BlockRegistry.ValidateIntegrity();
blockManager.BlockStateRegistry.ValidateIntegrity();
```

## 📌 注意事项

1. **路径格式**：使用 `res://` 前缀
2. **命名规范**：方块名使用小写蛇形命名（snake_case）
3. **纹理分辨率**：建议使用 16x16 或 32x32 像素
4. **状态定义**：使用 JSON 字符串格式
5. **初始化顺序**：必须在 `_Ready()` 之后调用 `Initialize()`

## 🎓 下一步

- [ ] 添加更多方块类型
- [ ] 实现纹理 Atlas 系统
- [ ] 添加方块行为系统
- [ ] 实现世界生成集成
