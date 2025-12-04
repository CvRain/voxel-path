# EntityStates 通用状态系统 - 设计说明

## 🎯 设计理念

将通用的状态枚举（如氧化等级、损坏等级等）从具体系统中提取出来，放到 `world_settings` 中作为**全局共享配置**。

### 为什么这样设计？

**问题**：之前 `OxidationLevel` 和 `BlockFacing` 定义在 `BlockState` 中，但这些状态不仅仅用于方块。

**场景举例**：

#### 1. 氧化等级（OxidationLevel）

```csharp
// ✅ 方块：铜方块氧化
var copperBlock = new BlockState("copper_block", 1) {
    Oxidation = EntityStates.OxidationLevel.Weathered
};

// ✅ 物品：铁剑生锈
var ironSword = new ItemState("iron_sword") {
    Oxidation = EntityStates.OxidationLevel.Exposed,
    Durability = 0.75f
};

// ✅ 生物：铁傀儡锈蚀
var ironGolem = new EntityComponent {
    Oxidation = EntityStates.OxidationLevel.Oxidized,
    Health = 0.3f  // 锈蚀严重，血量降低
};
```

#### 2. 朝向（Facing）

```csharp
// ✅ 方块：熔炉朝向
var furnace = new BlockState("furnace", 1) {
    Facing = WorldDirection.BaseDirection.North,
    Lit = true
};

// ✅ 生物：傀儡朝向
var golem = new Entity {
    Facing = WorldDirection.BaseDirection.South,
    Position = new Vector3(10, 0, 10)
};

// ✅ 物品：盾牌朝向（放置时）
var shield = new PlacedItem {
    Facing = WorldDirection.BaseDirection.Up
};
```

#### 3. 损坏等级（DamageLevel）

```csharp
// ✅ 方块：铁砧损坏
var anvil = new BlockState("anvil", 1) {
    Damage = EntityStates.DamageLevel.Cracked
};

// ✅ 物品：头盔损坏
var helmet = new ItemState("iron_helmet") {
    Damage = EntityStates.DamageLevel.Damaged,
    Defense = 0.6f  // 损坏降低防御
};

// ✅ 生物：受伤的傀儡
var golem = new Entity {
    Damage = EntityStates.DamageLevel.Broken,
    MovementSpeed = 0.5f  // 损坏严重，移动变慢
};
```

#### 4. 湿度等级（MoistureLevel）

```csharp
// ✅ 方块：海绵吸水
var sponge = new BlockState("sponge", 1) {
    Moisture = EntityStates.MoistureLevel.Saturated
};

// ✅ 生物：苔藓傀儡（湿度影响能力）
var mossGolem = new Entity {
    Moisture = EntityStates.MoistureLevel.Wet,
    RegenerationRate = 2.0f  // 湿润时回血快
};
```

## 🏗️ 架构对比

### ❌ 旧设计（分散定义）

```
blocks/data/BlockState.cs
├── enum OxidationLevel      ← 只能用于方块
└── enum BlockFacing         ← 只能用于方块

items/data/ItemState.cs
├── enum OxidationLevel      ← 重复定义！
└── enum ItemFacing          ← 类型不兼容！

entities/Entity.cs
├── enum OxidationLevel      ← 又重复了！
└── enum EntityFacing        ← 还是不兼容！
```

**问题**：
- ❌ 重复定义（维护噩梦）
- ❌ 类型不兼容（无法统一处理）
- ❌ 逻辑分散（氧化系统要在3个地方实现）

### ✅ 新设计（统一配置）

```
world_settings/
├── EntityStates.cs          ← 统一状态定义
│   ├── OxidationLevel
│   ├── DamageLevel
│   ├── MoistureLevel
│   └── GrowthStage
└── WorldDirection.cs        ← 统一方向定义
    └── BaseDirection

blocks/data/BlockState.cs    ← 引用
items/data/ItemState.cs      ← 引用
entities/Entity.cs           ← 引用
systems/OxidationSystem.cs   ← 统一处理
```

**优势**：
- ✅ 单一数据源
- ✅ 类型统一（方块、物品、生物共用）
- ✅ 逻辑集中（一个氧化系统处理所有对象）

## 💡 实际应用场景

### 场景 1：全局氧化系统

```csharp
public class OxidationSystem : Node
{
    /// <summary>
    /// 处理所有可氧化对象（方块、物品、生物）
    /// </summary>
    public void ProcessOxidation(float deltaTime)
    {
        // 处理方块氧化
        foreach (var block in GetOxidizableBlocks())
        {
            if (ShouldOxidize(block, deltaTime))
            {
                block.Oxidation = EntityStates.GetNextOxidationLevel(block.Oxidation) 
                    ?? block.Oxidation;
            }
        }
        
        // 处理物品氧化（统一逻辑！）
        foreach (var item in GetOxidizableItems())
        {
            if (ShouldOxidize(item, deltaTime))
            {
                item.Oxidation = EntityStates.GetNextOxidationLevel(item.Oxidation) 
                    ?? item.Oxidation;
            }
        }
        
        // 处理生物氧化（还是统一逻辑！）
        foreach (var entity in GetOxidizableEntities())
        {
            if (ShouldOxidize(entity, deltaTime))
            {
                entity.Oxidation = EntityStates.GetNextOxidationLevel(entity.Oxidation) 
                    ?? entity.Oxidation;
                
                // 氧化影响生物属性
                UpdateEntityStats(entity);
            }
        }
    }
}
```

### 场景 2：铜傀儡（结合多种状态）

```csharp
public class CopperGolem : Entity
{
    // 使用统一的状态枚举
    public EntityStates.OxidationLevel Oxidation { get; set; }
    public EntityStates.DamageLevel Damage { get; set; }
    public WorldDirection.BaseDirection Facing { get; set; }
    
    public override void UpdateStats()
    {
        // 氧化影响移动速度
        float speedMultiplier = Oxidation switch
        {
            EntityStates.OxidationLevel.None => 1.0f,
            EntityStates.OxidationLevel.Exposed => 0.9f,
            EntityStates.OxidationLevel.Weathered => 0.7f,
            EntityStates.OxidationLevel.Oxidized => 0.5f,
            _ => 1.0f
        };
        
        // 损坏影响生命值上限
        float healthMultiplier = Damage switch
        {
            EntityStates.DamageLevel.Intact => 1.0f,
            EntityStates.DamageLevel.Damaged => 0.8f,
            EntityStates.DamageLevel.Cracked => 0.5f,
            EntityStates.DamageLevel.Broken => 0.2f,
            _ => 1.0f
        };
        
        MovementSpeed = BaseSpeed * speedMultiplier;
        MaxHealth = BaseHealth * healthMultiplier;
    }
}
```

### 场景 3：可修复的工具

```csharp
public class Tool : Item
{
    public EntityStates.OxidationLevel Oxidation { get; set; }
    public EntityStates.DamageLevel Damage { get; set; }
    
    /// <summary>
    /// 使用工具时考虑状态影响
    /// </summary>
    public float GetEfficiency()
    {
        float efficiency = BaseEfficiency;
        
        // 氧化降低效率
        efficiency *= Oxidation switch
        {
            EntityStates.OxidationLevel.None => 1.0f,
            EntityStates.OxidationLevel.Exposed => 0.95f,
            EntityStates.OxidationLevel.Weathered => 0.85f,
            EntityStates.OxidationLevel.Oxidized => 0.7f,
            _ => 1.0f
        };
        
        // 损坏降低效率
        efficiency *= Damage switch
        {
            EntityStates.DamageLevel.Intact => 1.0f,
            EntityStates.DamageLevel.Damaged => 0.8f,
            EntityStates.DamageLevel.Cracked => 0.5f,
            EntityStates.DamageLevel.Broken => 0.1f,
            _ => 1.0f
        };
        
        return efficiency;
    }
    
    /// <summary>
    /// 修复工具（去氧化 + 修复损坏）
    /// </summary>
    public void Repair()
    {
        // 使用统一的工具方法
        Oxidation = EntityStates.GetPreviousOxidationLevel(Oxidation) 
            ?? EntityStates.OxidationLevel.None;
        
        if (Damage > EntityStates.DamageLevel.Intact)
        {
            Damage = (EntityStates.DamageLevel)((int)Damage - 1);
        }
    }
}
```

## 📊 状态组合示例

### 示例 1：铜方块的完整生命周期

```csharp
var copperBlock = new BlockState("copper_block", 1);

// 阶段 1：刚放置（崭新）
copperBlock.Oxidation = EntityStates.OxidationLevel.None;

// 阶段 2：几天后（轻度氧化）
copperBlock.Oxidation = EntityStates.GetNextOxidationLevel(copperBlock.Oxidation).Value;
// copperBlock.Oxidation == EntityStates.OxidationLevel.Exposed

// 阶段 3：一周后（风化）
copperBlock.Oxidation = EntityStates.GetNextOxidationLevel(copperBlock.Oxidation).Value;
// copperBlock.Oxidation == EntityStates.OxidationLevel.Weathered

// 阶段 4：完全氧化
copperBlock.Oxidation = EntityStates.GetNextOxidationLevel(copperBlock.Oxidation).Value;
// copperBlock.Oxidation == EntityStates.OxidationLevel.Oxidized

// 玩家使用斧头刮掉氧化层
copperBlock.Oxidation = EntityStates.GetPreviousOxidationLevel(copperBlock.Oxidation).Value;
// copperBlock.Oxidation == EntityStates.OxidationLevel.Weathered
```

### 示例 2：农作物生长 + 湿度影响

```csharp
var wheat = new BlockState("wheat", 1) {
    GrowthStage = EntityStates.GrowthStage.Seed,
    Moisture = EntityStates.MoistureLevel.Damp
};

// 湿度影响生长速度
float growthSpeed = wheat.Moisture switch {
    EntityStates.MoistureLevel.Dry => 0.5f,
    EntityStates.MoistureLevel.Damp => 1.0f,
    EntityStates.MoistureLevel.Wet => 1.5f,
    EntityStates.MoistureLevel.Saturated => 0.8f,  // 太湿反而慢
    _ => 1.0f
};
```

## 🎓 设计原则总结

1. **通用性优先** - 状态枚举设计要考虑多种应用场景
2. **可扩展性** - 新增状态类型不影响现有系统
3. **类型安全** - 使用强类型枚举而非字符串
4. **工具方法** - 提供状态转换的辅助方法（如 `GetNextOxidationLevel`）

## 💡 未来扩展建议

可以继续添加其他通用状态：

```csharp
// systems/world_settings/EntityStates.cs

/// <summary>温度等级</summary>
public enum TemperatureLevel {
    Frozen, Cold, Normal, Warm, Hot, Burning
}

/// <summary>魔法充能等级</summary>
public enum EnchantmentLevel {
    None, Minor, Moderate, Major, Legendary
}

/// <summary>清洁度等级</summary>
public enum CleanlinessLevel {
    Filthy, Dirty, Normal, Clean, Pristine
}
```

你的设计思路完全正确！把通用状态放在 `world_settings` 中可以：
- ✅ 避免重复定义
- ✅ 实现统一逻辑
- ✅ 支持跨系统复用
- ✅ 便于未来扩展

这就是优秀的架构设计！🎉
