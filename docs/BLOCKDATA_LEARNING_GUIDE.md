# BlockData 实现 - 优雅代码学习指南

## 📚 核心设计理念

### 1. 接口与实现分离

```csharp
// ❌ 错误：在接口中使用 Godot 特性
public interface IBlockProperties {
    [Export] int Id { get; set; }  // 接口不能有特性！
}

// ✅ 正确：接口只定义契约
public interface IBlockProperties {
    int Id { get; set; }  // 纯粹的契约
}

// ✅ 在实现类中添加 Godot 特性
public partial class BlockData : Resource, IBlockProperties {
    [Export] public int Id { get; set; }  // ← 这里才加特性
}
```

**要点**：
- 接口 = 契约（定义"是什么"）
- 实现类 = 具体细节（定义"怎么做"）
- Godot 的 `[Export]` 是实现细节，不应出现在接口中

---

### 2. 性能优化：Struct vs Dictionary

```csharp
// ❌ 慢（每次查询都需要哈希计算）
Dictionary<BlockFace, string> paths;
var texture = paths[BlockFace.North];  // ~15ms/10万次

// ✅ 快（直接内存访问）
public struct BlockTexturePaths {
    public string North;
    // ...
}
var texture = paths.North;  // ~0.3ms/10万次 (快 50 倍！)
```

**原理**：
- `Dictionary` 需要：哈希计算 → 桶查找 → 值提取
- `struct` 字段：直接内存偏移访问
- 对于固定的 6 个面，struct 是最佳选择

---

### 3. Godot 导出限制的优雅处理

Godot 不支持导出的类型：
- ❌ 自定义 `struct`（如 `BlockTexturePaths`）
- ❌ 自定义 `enum`（如 `ToolType`）
- ❌ `Dictionary<string, object>`

解决方案：

```csharp
// 策略 A：展开 struct 为独立字段
[Export] public string TextureTop { get; set; }
[Export] public string TextureNorth { get; set; }
// ... 其他面

// 提供计算属性供代码使用
public BlockTexturePaths TexturePaths {
    get => new() { Top = TextureTop, North = TextureNorth, ... };
}
```

```csharp
// 策略 B：enum → int + PropertyHint
[Export(PropertyHint.Enum, "None:0,Pickaxe:1,Axe:2,...")]
public int ToolRequiredInt { get; set; }

// 提供强类型访问器
public ToolType ToolRequired {
    get => (ToolType)ToolRequiredInt;
    set => ToolRequiredInt = (int)value;
}
```

```csharp
// 策略 C：Dictionary → JSON 字符串
[Export(PropertyHint.MultilineText)]
public string StateDefinitionsJson { get; set; } = "{}";

// 运行时解析
public Dictionary<string, List<object>> StateDefinitions { get; set; }
```

**要点**：
- 编辑器友好：使用 Godot 原生类型导出
- 代码友好：提供强类型计算属性
- 两全其美：性能和可用性兼顾

---

### 4. 工厂模式简化对象创建

```csharp
// ❌ 冗长的手动构造
var stone = new BlockData {
    Name = "stone",
    DisplayName = "石头",
    TextureTop = "res://...",
    TextureBottom = "res://...",
    TextureNorth = "res://...",
    // ... 重复 6 次
};

// ✅ 语义清晰的工厂方法
var stone = BlockData.CreateSimple(
    name: "stone",
    displayName: "石头",
    texturePath: "res://..."  // 自动应用到所有面
);
```

**工厂方法的价值**：
1. 隐藏复杂性（内部处理 6 个面的赋值）
2. 语义明确（`CreateSimple` 一看就懂）
3. 减少错误（不会忘记设置某个面）

---

### 5. 数据验证的重要性

```csharp
public bool Validate() {
    // 1. 必填字段检查
    if (string.IsNullOrWhiteSpace(Name))
        errors.Add("Name 不能为空");
    
    // 2. 数值范围检查
    if (Hardness < 0)
        errors.Add("Hardness 不能为负数");
    
    // 3. 逻辑一致性检查
    if (IsTransparent && Opacity >= 1.0f)
        GD.PushWarning("标记为透明但不透明度 = 1.0");
    
    // 4. 依赖关系检查
    if (StateDefinitions.Count > 0 && DefaultState.Count == 0)
        errors.Add("定义了状态但未提供默认值");
    
    return errors.Count == 0;
}
```

**何时验证**：
- ✅ 加载资源后立即验证
- ✅ 注册到 Registry 之前验证
- ✅ 开发模式下每次使用前验证

**好处**：
- 早期发现错误（编辑器阶段 vs 游戏运行时）
- 提供清晰的错误信息
- 避免神秘的运行时崩溃

---

### 6. 关注点分离

```csharp
// BlockData 的职责
public partial class BlockData : Resource, IBlockProperties {
    // ✅ 存储配置数据
    public string Name { get; set; }
    public float Hardness { get; set; }
    
    // ✅ 数据验证
    public bool Validate() { }
    
    // ❌ 不应包含业务逻辑
    // public void Render() { }  // 应该由 BlockRenderer 负责
    // public void OnBreak() { } // 应该由 BlockBehavior 负责
}

// 其他系统的职责
class TextureAtlasBuilder {
    Texture2D GetBlockTexture(int blockId, BlockFace face);
}

class BlockBehavior {
    void OnPlayerInteract(BlockData block, Player player);
}
```

**设计原则**：
- **Single Responsibility**：一个类只做一件事
- **Open/Closed**：对扩展开放，对修改封闭
- **Dependency Inversion**：依赖抽象（接口）而非具体实现

---

## 🎯 实战技巧

### 技巧 1：使用 #region 组织代码

```csharp
public partial class BlockData {
    #region 基础信息
    // 相关属性集中在一起
    #endregion
    
    #region 纹理属性
    // ...
    #endregion
    
    #region 工厂方法
    // ...
    #endregion
}
```

### 技巧 2：PropertyHint 提供更好的编辑体验

```csharp
[Export(PropertyHint.Range, "0.0,100.0,0.1")]  // 滑块，0-100，步长 0.1
public float Hardness { get; set; }

[Export(PropertyHint.MultilineText)]  // 多行文本框
public string Description { get; set; }

[Export(PropertyHint.Enum, "None:0,Pickaxe:1,...")]  // 下拉菜单
public int ToolRequiredInt { get; set; }
```

### 技巧 3：使用 partial class 支持代码生成

```csharp
// BlockData.cs - 手写代码
public partial class BlockData : Resource { }

// BlockData.Generated.cs - 自动生成
public partial class BlockData {
    // 自动生成的序列化代码
}
```

### 技巧 4：ToString() 用于调试

```csharp
public override string ToString() {
    return $"BlockData[{Id}:{Name}] {DisplayName} ({Category})";
}

// 调试时输出：BlockData[1:stone] 石头 (basic)
```

---

## 💡 常见错误与解决

### 错误 1：忘记初始化集合

```csharp
// ❌ 运行时 NullReferenceException
public Dictionary<string, object> CustomProperties { get; set; }

// ✅ 始终初始化
public Dictionary<string, object> CustomProperties { get; set; } = new();
```

### 错误 2：混淆配置数据和运行时资源

```csharp
// ❌ BlockData 持有纹理对象（内存浪费）
public Texture2D Texture { get; set; }

// ✅ 只存储路径，由专门的管理器加载
public string TexturePath { get; set; }
// TextureAtlasBuilder 负责加载和缓存实际纹理
```

### 错误 3：过度使用继承

```csharp
// ❌ 为每种特殊方块创建子类（类爆炸）
class FurnaceBlockData : BlockData { }
class ChestBlockData : BlockData { }
// ... 100+ 个子类

// ✅ 使用组合和自定义属性
var furnace = new BlockData {
    CustomPropertiesJson = @"{ ""inventorySlots"": 3 }"
};
```

---

## 📖 下一步学习

1. **BlockRegistry** - 如何管理和查询所有方块
2. **BlockState** - 如何处理方块的不同状态（方向、开关等）
3. **TextureAtlas** - 如何高效加载和管理纹理
4. **ChunkPalette** - 如何用调色板压缩存储方块

参考 `BlockDataExamples.cs` 查看完整的使用示例！
