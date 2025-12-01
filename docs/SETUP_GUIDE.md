# 交互系统设置指南

## 快速开始

### 1. 场景结构设置

在您的主场景中（例如 `level_playground.tscn`），按以下结构组织节点：

```
Level (Node3D 或 Node)
├── Player (CharacterBody3D)
│   ├── Head (Node3D)
│   │   ├── Camera3D
│   │   └── RayCast3D
│   └── CollisionShape3D
│
├── WorldInteractionManager (Node)  ← 新建这个节点
│
└── World (你的世界场景 Node3D)
    ├── BlockSelector (MeshInstance3D)  ← 新建这个节点
    └── ... (其他世界相关节点)
```

### 2. 创建 BlockSelector 节点

**重要**：BlockSelector 应该在 World 中，**不是** Player 的子节点！

1. 在 World 节点下右键 → 添加子节点 → 选择 `MeshInstance3D`
2. 命名为 `BlockSelector`
3. 在检查器中点击"脚本"图标 → 加载脚本
4. 选择 `entities/player/scripts/BlockSelector.cs`
5. 保存场景

BlockSelector 会自动创建立方体网格和半透明材质。

### 3. 创建 WorldInteractionManager 节点

1. 在场景根节点下右键 → 添加子节点 → 选择 `Node`
2. 命名为 `WorldInteractionManager`
3. 在检查器中点击"脚本"图标 → 加载脚本
4. 选择 `systems/WorldInteractionManager.cs`
5. 在检查器中配置导出变量：
   - **Player**: 从场景树拖拽 Player 节点到这里
   - **Block Selector**: 从场景树拖拽 BlockSelector 节点到这里
   - **Default Block Id**: 设置默认放置的方块 ID（默认为 1 = 石头）
6. 保存场景

### 4. 验证设置

运行游戏，您应该看到：
- ✅ 准星对准方块时出现白色半透明高亮框
- ✅ 准星离开方块时高亮框消失
- ✅ 按 Tab 键切换笔刷大小，高亮框会相应变化
- ✅ 左键破坏方块
- ✅ 右键放置方块

如果出现问题，检查控制台是否有错误信息。

---

## 进阶：添加自定义方块行为

### 场景 1：为现有方块添加行为

假设您想让方块 ID 5 成为"信息方块"，不可破坏且右键显示信息。

#### 步骤 1：创建行为脚本

```csharp
// systems/block_behaviors/MyCustomBehavior.cs
using Godot;
using VoxelPath.systems.block_behaviors;

public partial class MyCustomBehavior : Node, IBlockInteractable
{
    public void OnPlayerLookAt(Vector3I position, Vector3 normal)
    {
        GD.Print($"Looking at special block at {position}");
    }
    
    public void OnPlayerLookAway()
    {
        // 可选：清理状态
    }
    
    public void OnLeftClick(Vector3I position, Vector3 normal)
    {
        GD.Print("This block is protected!");
        // 不执行破坏逻辑
    }
    
    public void OnRightClick(Vector3I position, Vector3 normal)
    {
        GD.Print("Opening special interface...");
        // 打开 UI 等
    }
}
```

#### 步骤 2：注册行为

在您的游戏初始化脚本中（例如主场景的 `_Ready()` 方法）：

```csharp
using VoxelPath.systems.block_behaviors;

public override void _Ready()
{
    // 注册方块行为
    BlockBehaviorRegistry.RegisterBehavior(5, typeof(MyCustomBehavior));
}
```

#### 步骤 3：修改 WorldInteractionManager

在 `WorldInteractionManager.cs` 的事件处理方法中添加行为查询：

```csharp
private void OnLeftClickBlock(Vector3I blockPosition, Vector3 blockNormal)
{
    // 获取方块 ID
    int blockId = GetBlockIdAt(blockPosition);
    
    // 检查是否有自定义行为
    var behavior = BlockBehaviorRegistry.GetBehavior(blockId);
    if (behavior != null)
    {
        behavior.OnLeftClick(blockPosition, blockNormal);
        return; // 使用自定义行为，不执行默认逻辑
    }
    
    // 默认行为：破坏方块
    DestroyVoxels(blockPosition);
}

// 添加辅助方法
private int GetBlockIdAt(Vector3I position)
{
    var world = GetTree().CurrentScene;
    if (world.HasMethod("get_voxel_at"))
    {
        return (int)world.Call("get_voxel_at", position);
    }
    return 0; // Air
}
```

### 场景 2：带 UI 的交互方块

创建一个需要 UI 反馈的方块（例如箱子）：

```csharp
public partial class ChestBlockBehavior : Node, IBlockInteractable
{
    [Export] private Control _chestUI;
    
    public void OnPlayerLookAt(Vector3I position, Vector3 normal)
    {
        // 显示提示："按 E 打开箱子"
    }
    
    public void OnPlayerLookAway()
    {
        // 隐藏提示
    }
    
    public void OnLeftClick(Vector3I position, Vector3 normal)
    {
        // 破坏箱子并掉落物品
        GD.Print("Breaking chest, dropping items...");
    }
    
    public void OnRightClick(Vector3I position, Vector3 normal)
    {
        // 打开箱子 UI
        if (_chestUI != null)
        {
            _chestUI.Show();
            // 加载箱子内容
        }
    }
}
```

---

## 常见问题

### Q: BlockSelector 不显示？

**检查清单**：
1. BlockSelector 是否附加了正确的脚本？
2. WorldInteractionManager 中是否正确分配了 BlockSelector 引用？
3. 控制台是否有错误信息？
4. RayCast3D 的 TargetPosition 是否正确设置？（应该是负 Z 方向）

### Q: 点击方块没有反应？

**检查清单**：
1. WorldInteractionManager 是否正确订阅了 Player 事件？
2. 检查 `_world.Call("set_voxel_at_raw", ...)` 是否工作（世界场景是否有此方法）
3. 查看控制台日志，看事件是否被触发

### Q: 笔刷大小改变后高亮框没有更新？

确保 WorldInteractionManager 订阅了 `BrushSizeChanged` 事件：
```csharp
_player.BrushSizeChanged += OnBrushSizeChanged;
```

### Q: 如何禁用某个方块的默认破坏行为？

在自定义行为的 `OnLeftClick` 中不调用 `DestroyVoxels`，直接返回即可。

---

## 调试技巧

### 启用事件日志

在 WorldInteractionManager 的事件处理方法中添加日志：

```csharp
private void OnHoveredBlockChanged(Vector3I blockPosition, Vector3 blockNormal)
{
    GD.Print($"[Debug] Hovering block at {blockPosition}, normal: {blockNormal}");
    // ... 其余逻辑
}
```

### 检查方块 ID

在 WorldInteractionManager 中添加辅助方法：

```csharp
private void DebugBlockInfo(Vector3I position)
{
    var world = GetTree().CurrentScene;
    if (world.HasMethod("get_voxel_at"))
    {
        int blockId = (int)world.Call("get_voxel_at", position);
        GD.Print($"Block at {position}: ID = {blockId}");
        
        if (BlockBehaviorRegistry.HasBehavior(blockId))
        {
            GD.Print($"  -> Has custom behavior registered");
        }
    }
}
```

在 `OnHoveredBlockChanged` 中调用：
```csharp
DebugBlockInfo(blockPosition);
```

---

## 性能优化提示

1. **避免频繁创建行为对象**：考虑使用对象池或单例模式
2. **批量操作**：使用 `BatchModifyVoxels` 一次修改多个方块
3. **延迟更新**：对于非紧急的 UI 更新，使用 `CallDeferred`
4. **事件订阅管理**：确保在节点销毁时取消订阅（已在 `_ExitTree()` 中实现）

---

## 下一步

现在您已经设置好了基础交互系统，可以尝试：

- 🎨 为不同方块类型实现独特的视觉反馈
- 🔧 创建可交互的机器方块
- 📦 实现带库存系统的容器方块
- 🚪 制作可开关的门和活板门
- 💡 添加发光方块或动态光源

查看 `docs/INTERACTION_SYSTEM.md` 了解更多高级用法和示例代码。
