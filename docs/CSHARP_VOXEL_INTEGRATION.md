# C# 与 godot_voxel 集成指南

## 🔍 问题说明

godot_voxel 是 GDExtension 插件，**当前不直接支持 C# 绑定**。

## ✅ 解决方案：混合开发架构

### 架构图
```
┌──────────────────────────────────────────┐
│          C# 层（游戏逻辑）                │
│  ┌────────────────────────────────────┐  │
│  │  BlockRegistry                     │  │
│  │  BlockManager                      │  │
│  │  Player                            │  │
│  │  GameLogic                         │  │
│  └──────────┬─────────────────────────┘  │
└────────────┼────────────────────────────┘
             │ VoxelWorldBridge (桥接)
┌────────────▼────────────────────────────┐
│        GDScript 层（渲染）               │
│  ┌────────────────────────────────────┐  │
│  │  SimpleVoxelWorld                  │  │
│  │  VoxelTerrain                      │  │
│  │  VoxelMesher                       │  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

## 📦 组件说明

### 1. VoxelWorldBridge.cs
C# 和 GDScript 之间的桥接器，提供：
- ✅ `GetVoxel(position)` - 获取方块
- ✅ `SetVoxel(position, id)` - 设置方块
- ✅ `PlaceBlock(position, namespacedId)` - 使用 C# 方块系统放置
- ✅ `GetBlockData(position)` - 获取完整方块数据

### 2. simple_voxel_world.gd
GDScript 世界管理器，封装 godot_voxel API

## 🚀 使用示例

### 在 C# 中使用

```csharp
public partial class PlayerController : CharacterBody3D
{
    private VoxelWorldBridge _voxelBridge;
    private BlockRegistry _blockRegistry;

    public override void _Ready()
    {
        // 获取桥接器
        _voxelBridge = GetNode<VoxelWorldBridge>("/root/LevelPlayground/VoxelWorldBridge");
        
        // 连接 GDScript 世界
        var voxelWorld = GetNode("/root/LevelPlayground/SimpleVoxelWorld");
        _voxelBridge.ConnectToVoxelWorld(voxelWorld);
        
        // 设置方块注册表
        _voxelBridge.SetBlockRegistry(_blockRegistry);
    }

    public void BreakBlock(Vector3I position)
    {
        // 获取方块数据
        var blockData = _voxelBridge.GetBlockData(position);
        if (blockData != null)
        {
            GD.Print($"Breaking: {blockData.DisplayName}");
        }
        
        // 破坏方块
        _voxelBridge.SetVoxel(position, 0); // 0 = 空气
    }

    public void PlaceBlock(Vector3I position)
    {
        // 使用 NamespacedId 放置
        var stoneId = new NamespacedId("voxelpath:stone");
        _voxelBridge.PlaceBlock(position, stoneId);
    }
}
```

### 信号监听

```csharp
public override void _Ready()
{
    _voxelBridge.BlockPlaced += OnBlockPlaced;
    _voxelBridge.BlockBroken += OnBlockBroken;
}

private void OnBlockPlaced(Vector3I position, int blockId)
{
    GD.Print($"Block {blockId} placed at {position}");
}

private void OnBlockBroken(Vector3I position)
{
    GD.Print($"Block broken at {position}");
}
```

## 🔧 场景设置

### level_playground.tscn 结构
```
LevelPlayground (Node3D)
├── SimpleVoxelWorld (Node3D + GDScript)
│   └── VoxelTerrain (自动创建)
├── VoxelWorldBridge (Node + C#)
├── Player (CharacterBody3D + C#)
└── ...
```

### 在编辑器中设置
1. 添加 `VoxelWorldBridge` 节点到场景
2. 在 Player 脚本中获取引用
3. 调用 `ConnectToVoxelWorld()` 连接世界

## 💡 优势

### C# 层负责：
- ✅ 方块数据管理（BlockRegistry）
- ✅ 游戏逻辑
- ✅ 玩家控制
- ✅ UI 系统
- ✅ 保存/加载

### GDScript 层负责：
- ✅ 体素渲染（godot_voxel）
- ✅ 网格生成
- ✅ 碰撞检测
- ✅ LOD 管理

## 🎯 未来迁移

如果 godot_voxel 未来支持 C#，或你决定自己实现：
1. **数据层完全不变**（BlockRegistry等）
2. **只需替换 VoxelWorldBridge 实现**
3. **游戏逻辑代码零改动**

## 📚 相关文件

- `/systems/voxel/VoxelWorldBridge.cs` - C# 桥接器
- `/scenes/levels/simple_voxel_world.gd` - GDScript 世界
- `/docs/SIMPLE_VOXEL_WORLD.md` - 世界设置文档
