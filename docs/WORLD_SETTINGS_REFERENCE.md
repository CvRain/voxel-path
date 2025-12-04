# WorldSettings 配置参考手册

## 📁 配置文件结构

```
systems/world_settings/
├── Constants.cs           # 全局常量
├── WorldDirection.cs      # 方向定义
├── EntityStates.cs        # 物体状态
└── ItemCategories.cs      # 物品分类（原 IWorldItemCategory）
```

## 🗂️ 配置清单

### 1. Constants.cs - 全局常量

```csharp
namespace VoxelPath.Scripts.Core;

public static class Constants
{
    // 版本信息
    public const string Version = "0.1.0";
    public const string GameName = "Voxel Path: Artisan's Realm";
    
    // 世界基础参数
    public const float VoxelSize = 0.25f;              // 微体素大小
    public const int ChunkSize = 64;                   // 区块大小（格子）
    public const float ChunkWorldSize = 16f;           // 区块世界大小（米）
    public const int SeaLevel = 1024;                  // 海平面高度
    public const int MaxTerrainHeight = 3072;          // 最大地形高度
    public const int VoxelMaxHeight = 1024;            // 体素最大高度
    
    // 特殊方块 ID
    public const int AirBlockId = 0;                   // 空气方块
    public const int FirstModBlockId = 256;            // Mod 方块起始 ID
    
    // 路径配置
    public const string DataBlocksPath = "res://Data/blocks";
    public const string DataBlocksManifest = "res://Data/blocks/_manifest.json";
    public const string ModPath = "user://mods";
    
    // 调试开关
    public const bool DebugEnabled = true;
    public const bool DebugBlockLoading = true;
    public const bool DebugTextureLoading = true;
    
    // 性能参数
    public const int MaxChunksPerFrame = 4;
    public const int ViewDistance = 8;
    public const int LodLevels = 3;
    public const int ChunkSectionSize = 64;
}
```

**使用示例**：
```csharp
// 获取世界参数
float voxelSize = Constants.VoxelSize;
int seaLevel = Constants.SeaLevel;

// 检查调试模式
if (Constants.DebugEnabled) {
    GD.Print("Debug mode enabled");
}
```

---

### 2. WorldDirection.cs - 方向定义

```csharp
namespace VoxelPath.systems.world_settings;

public partial class WorldDirection : Node
{
    public enum BaseDirection
    {
        // 主要 6 方向
        Up = 0,
        Down = 1,
        North = 2,
        South = 3,
        East = 4,
        West = 5,
        
        // 别名（映射到主要方向）
        Top = Up,
        Bottom = Down,
        Back = North,
        Forward = South,
        Right = East,
        Left = West
    }
    
    // Vector 映射
    public readonly Dictionary<BaseDirection, Vector3I> DirectionVectors;
}
```

**使用场景**：
- ✅ 方块面朝向
- ✅ 纹理路径映射
- ✅ 实体朝向
- ✅ 物品放置方向
- ✅ 光照传播方向

**使用示例**：
```csharp
// 方块朝向
var furnace = new BlockState("furnace", 1) {
    Facing = WorldDirection.BaseDirection.North
};

// 纹理路径
var texturePath = blockData.TexturePaths.GetPath(WorldDirection.BaseDirection.Top);

// 实体朝向
entity.Facing = WorldDirection.BaseDirection.South;
```

---

### 3. EntityStates.cs - 物体状态

```csharp
namespace VoxelPath.systems.world_settings;

public static class EntityStates
{
    /// <summary>氧化等级</summary>
    public enum OxidationLevel
    {
        None = 0,        // 崭新
        Exposed = 1,     // 轻度氧化
        Weathered = 2,   // 风化
        Oxidized = 3     // 生锈
    }
    
    /// <summary>损坏等级</summary>
    public enum DamageLevel
    {
        Intact = 0,      // 完好
        Damaged = 1,     // 损坏
        Cracked = 2,     // 裂纹
        Broken = 3       // 破碎
    }
    
    /// <summary>湿度等级</summary>
    public enum MoistureLevel
    {
        Dry = 0,         // 干燥
        Damp = 1,        // 潮湿
        Wet = 2,         // 湿润
        Saturated = 3    // 饱和
    }
    
    /// <summary>生长阶段</summary>
    public enum GrowthStage
    {
        Seed = 0,        // 种子
        Sprout = 1,      // 发芽
        Growing = 2,     // 生长
        Mature = 3       // 成熟
    }
    
    // 工具方法
    public static OxidationLevel? GetNextOxidationLevel(OxidationLevel current);
    public static OxidationLevel? GetPreviousOxidationLevel(OxidationLevel current);
    public static string GetOxidationName(OxidationLevel level);
}
```

**使用场景**：
- ✅ 方块状态（铜方块氧化、铁砧损坏、海绵吸水、农作物生长）
- ✅ 物品状态（工具耐久、武器锈蚀）
- ✅ 生物状态（傀儡氧化、生物损伤）

**使用示例**：
```csharp
// 铜方块氧化
var copperBlock = new BlockState("copper_block", 1) {
    Oxidation = EntityStates.OxidationLevel.Weathered
};

// 铁剑生锈
var ironSword = new ItemState("iron_sword") {
    Oxidation = EntityStates.OxidationLevel.Exposed
};

// 铁傀儡锈蚀
var ironGolem = new Entity {
    Oxidation = EntityStates.OxidationLevel.Oxidized,
    Damage = EntityStates.DamageLevel.Cracked
};

// 状态转换
var next = EntityStates.GetNextOxidationLevel(copperBlock.Oxidation);
var name = EntityStates.GetOxidationName(EntityStates.OxidationLevel.Weathered);
// name == "风化"
```

---

### 4. ItemCategories.cs - 物品分类

```csharp
namespace VoxelPath.systems.world_settings;

public interface IWorldItemCategory
{
    /// <summary>工具类型</summary>
    public enum ToolCategory
    {
        Axe,        // 斧头
        Pickaxe,    // 镐
        Shovel,     // 铲
        Hammer,     // 锤子
        Scissors,   // 剪刀
        Brush,      // 刷子
        Scythe,     // 镰刀
        Hoe         // 锄头
    }
}
```

**使用场景**：
- ✅ 方块挖掘需求
- ✅ 工具类型定义
- ✅ 物品分类系统

**使用示例**：
```csharp
// 方块需要的工具
var stone = new BlockData {
    Name = "stone",
    ToolRequired = IWorldItemCategory.ToolCategory.Pickaxe,
    MineLevel = 1  // 木镐及以上
};

// 工具定义
var pickaxe = new ItemData {
    Name = "iron_pickaxe",
    Category = IWorldItemCategory.ToolCategory.Pickaxe,
    MiningLevel = 2  // 铁镐
};
```

---

## 🔄 跨系统使用示例

### 示例 1：统一氧化系统

```csharp
public class OxidationSystem : Node
{
    public void ProcessOxidation<T>(T target, float deltaTime) 
        where T : IHasOxidation
    {
        if (!ShouldOxidize(target, deltaTime)) return;
        
        // 统一的氧化逻辑（方块、物品、生物通用）
        target.Oxidation = EntityStates.GetNextOxidationLevel(target.Oxidation) 
            ?? target.Oxidation;
    }
}

// 接口定义
public interface IHasOxidation
{
    EntityStates.OxidationLevel Oxidation { get; set; }
}

// 实现
public class BlockState : IHasOxidation { ... }
public class ItemState : IHasOxidation { ... }
public class Entity : IHasOxidation { ... }
```

### 示例 2：方向统一处理

```csharp
public interface IHasFacing
{
    WorldDirection.BaseDirection Facing { get; set; }
}

public class RotationSystem : Node
{
    public void Rotate<T>(T target, bool clockwise) 
        where T : IHasFacing
    {
        target.Facing = clockwise 
            ? GetClockwiseDirection(target.Facing)
            : GetCounterClockwiseDirection(target.Facing);
    }
}
```

---

## 📊 配置使用统计

| 配置项 | 定义位置 | 使用场景 |
|--------|----------|----------|
| **VoxelSize** | Constants | 世界生成、渲染、碰撞检测 |
| **BaseDirection** | WorldDirection | 方块、物品、生物的朝向 |
| **OxidationLevel** | EntityStates | 方块、物品、生物的氧化 |
| **DamageLevel** | EntityStates | 方块、物品、生物的损坏 |
| **ToolCategory** | ItemCategories | 方块挖掘、工具定义 |

---

## ✅ 设计原则检查清单

在添加新配置时，问自己：

- [ ] 这个配置是否会在**多个系统**中使用？
- [ ] 这个配置是否是**游戏世界的基础规则**？
- [ ] 这个配置是否适用于**多种对象类型**（方块、物品、生物）？
- [ ] 这个配置是否需要在**编辑器中可视化编辑**？

如果以上有 ≥2 个答案是"是"，那么应该放在 `world_settings` 中。

---

## 🎓 最佳实践

### ✅ 推荐做法

```csharp
// 1. 引用全局配置
using VoxelPath.systems.world_settings;

// 2. 使用强类型枚举
public EntityStates.OxidationLevel Oxidation { get; set; }

// 3. 使用工具方法
var next = EntityStates.GetNextOxidationLevel(current);
```

### ❌ 避免做法

```csharp
// ❌ 不要重复定义枚举
public enum MyOxidationLevel { ... }

// ❌ 不要使用字符串
public string Oxidation { get; set; }  // "none", "exposed" ...

// ❌ 不要硬编码魔法数字
if (oxidation == 2) { ... }  // 什么是 2？
```

---

## 📝 添加新配置的流程

1. **评估** - 确认配置是全局通用的
2. **设计** - 选择合适的文件（Constants/WorldDirection/EntityStates/ItemCategories）
3. **实现** - 添加枚举/常量，编写工具方法
4. **文档** - 更新此参考手册
5. **重构** - 移除其他地方的重复定义
6. **测试** - 确保所有系统正常工作

---

这个配置系统是你项目架构的**基石**！保持它的整洁和一致性非常重要。👍
