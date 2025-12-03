using System.Collections.Generic;
using Godot;
using VoxelPath.systems.world_settings;

namespace VoxelPath.systems.blocks.data;

/// <summary>
/// 方块数据类 - IBlockProperties 的 Godot Resource 实现
/// 继承 Resource 使其可以在 Godot 编辑器中编辑和序列化
/// 使用 partial 关键字允许后续扩展（如自动生成的代码）
/// </summary>
[GlobalClass]
public partial class BlockData : Resource, IBlockProperties
{
    #region 基础信息

    [ExportGroup("基础信息")] 
    [Export] public int Id { get; set; }     //方块 ID - 由 BlockRegistry 自动分配，不要手动设置
                                             
    /// <summary>方块唯一标识符（如 "stone", "oak_log", "iron_ore"）</summary>
    [Export]
    public string Name { get; set; } = string.Empty;

    /// <summary>方块显示名称（用于 UI 显示）</summary>
    [Export]
    public string DisplayName { get; set; } = string.Empty;

    /// <summary>方块描述（显示在工具提示中）</summary>
    [Export(PropertyHint.MultilineText)]
    public string Description { get; set; } = string.Empty;

    /// <summary>方块分类（如 "nature", "ores", "machines"）</summary>
    [Export]
    public string Category { get; set; } = "misc";

    #endregion

    #region 纹理属性

    [ExportGroup("纹理配置")]
    [ExportSubgroup("漫反射贴图路径")]  // Godot 编辑器中分别导出各个面的纹理路径
    [Export] public string TextureTop { get; set; } = string.Empty;
    [Export] public string TextureBottom { get; set; } = string.Empty;
    [Export] public string TextureNorth { get; set; } = string.Empty;
    [Export] public string TextureSouth { get; set; } = string.Empty;
    [Export] public string TextureEast { get; set; } = string.Empty;
    [Export] public string TextureWest { get; set; } = string.Empty;

    [ExportSubgroup("法线贴图路径")] 
    [Export] public string NormalTop { get; set; } = string.Empty;
    [Export] public string NormalBottom { get; set; } = string.Empty;
    [Export] public string NormalNorth { get; set; } = string.Empty;
    [Export] public string NormalSouth { get; set; } = string.Empty;
    [Export] public string NormalEast { get; set; } = string.Empty;
    [Export] public string NormalWest { get; set; } = string.Empty;

    /// <summary>
    /// 纹理路径配置 - 内部使用的高性能结构体
    /// 从导出的字段自动构建
    /// </summary>
    public BlockTexturePaths TexturePaths
    {
        get => new()
        {
            Top = TextureTop,
            Bottom = TextureBottom,
            North = TextureNorth,
            South = TextureSouth,
            East = TextureEast,
            West = TextureWest
        };
        set
        {
            TextureTop = value.Top;
            TextureBottom = value.Bottom;
            TextureNorth = value.North;
            TextureSouth = value.South;
            TextureEast = value.East;
            TextureWest = value.West;
        }
    }

    /// <summary>
    /// 法线贴图路径配置 - 内部使用的高性能结构体
    /// </summary>
    public BlockTexturePaths NormalPaths
    {
        get => new()
        {
            Top = NormalTop,
            Bottom = NormalBottom,
            North = NormalNorth,
            South = NormalSouth,
            East = NormalEast,
            West = NormalWest
        };
        set
        {
            NormalTop = value.Top;
            NormalBottom = value.Bottom;
            NormalNorth = value.North;
            NormalSouth = value.South;
            NormalEast = value.East;
            NormalWest = value.West;
        }
    }

    [ExportSubgroup("视觉效果")]
    [Export]
    public bool IsTransparent { get; set; } //是否透明（影响渲染顺序）

    [Export(PropertyHint.Range, "0.0,1.0,0.01")]
    public float Opacity { get; set; } = 1.0f; //透明度（0.0 完全透明 - 1.0 完全不透明）

    [Export]
    public bool IsEmissive { get; set; } //是否自发光

    [Export(PropertyHint.Range, "0.0,10.0,0.1")]
    public float EmissionStrength { get; set; } = 1.0f; // 自发光强度（HDR 值，可以 > 1.0）

    #endregion

    #region 物理属性

    [ExportGroup("物理属性")]
    [Export(PropertyHint.Range, "0.0,100.0,0.1")]
    public float Hardness { get; set; } = 1.0f; //硬度 - 影响挖掘速度（0 = 无法破坏，如基岩）

    [Export(PropertyHint.Range, "0.0,100.0,0.1")]
    public float Resistance { get; set; } = 1.0f; //抗爆炸性 - 影响爆炸抵抗力

    [Export] public bool HasCollision { get; set; } = true;//是否有碰撞体积

    [Export] public bool IsSolid { get; set; } = true; //是否为实心方块（影响光照传播、AI 寻路等）

    #endregion

    #region 交互属性

    [ExportGroup("交互属性")]
    [Export] public bool CanPlace { get; set; } = true; //是否可以被玩家放置

    [Export] public bool CanBreak { get; set; } = true; //是否可以被破坏

    /// <summary>
    /// 需要的工具类型（使用 int 以便在 Godot 编辑器中编辑）
    /// -1=None(无需工具), 0=Axe, 1=Pickaxe, 2=Shovel, 3=Hammer, 4=Scissors, 5=Brush, 6=Scythe, 7=Hoe
    /// </summary>
    [Export(PropertyHint.Enum, "None:-1,Axe:0,Pickaxe:1,Shovel:2,Hammer:3,Scissors:4,Brush:5,Scythe:6,Hoe:7")]
    public int ToolRequiredInt { get; set; } = -1;

    /// <summary>需要的工具类型（强类型访问器）</summary>
    public IWorldItemCategory.ToolCategory? ToolRequired
    {
        get => ToolRequiredInt == -1 ? null : (IWorldItemCategory.ToolCategory)ToolRequiredInt;
        set => ToolRequiredInt = value.HasValue ? (int)value.Value : -1;
    }

    /// <summary>需要的最低工具等级（0 = 任意工具）</summary>
    [Export(PropertyHint.Range, "0,5,1")]
    public int MineLevel { get; set; }

    /// <summary>基础挖掘时间（秒）- 实际时间会受工具和等级影响</summary>
    [Export(PropertyHint.Range, "0.1,60.0,0.1")]
    public float BaseMineTime { get; set; } = 1.0f;

    #endregion

    #region 方块状态

    [ExportGroup("方块状态系统")]
    /// <summary>
    /// 方块状态定义（JSON 格式）
    /// 示例：{"facing":["north","south","east","west"],"lit":[true,false]}
    /// 注意：Godot 不支持导出复杂字典，使用 JSON 字符串存储
    /// </summary>
    [Export(PropertyHint.MultilineText)]
    public string StateDefinitionsJson { get; set; } = "{}";

    /// <summary>
    /// 默认状态值（JSON 格式）
    /// 示例：{"facing":"north","lit":false}
    /// </summary>
    [Export]
    public string DefaultStateJson { get; set; } = "{}";

    /// <summary>
    /// 方块状态定义（运行时使用，从 JSON 解析）
    /// </summary>
    public Dictionary<string, List<object>> StateDefinitions { get; set; } = new();

    /// <summary>
    /// 默认状态值（运行时使用，从 JSON 解析）
    /// </summary>
    public Dictionary<string, object> DefaultState { get; set; } = new();

    #endregion

    #region 扩展属性

    [ExportGroup("扩展属性")]
    /// <summary>
    /// 自定义属性（JSON 格式）
    /// 用于存储模组或特殊方块的额外数据
    /// 示例：{"burnTime":200,"fuelValue":1600}
    /// </summary>
    [Export(PropertyHint.MultilineText)]
    public string CustomPropertiesJson { get; set; } = "{}";

    /// <summary>
    /// 自定义属性（运行时使用，从 JSON 解析）
    /// </summary>
    public Dictionary<string, object> CustomProperties { get; set; } = new();

    #endregion

    #region 验证和初始化

    /// <summary>
    /// 验证方块属性是否有效
    /// 在加载时自动调用，确保数据完整性
    /// </summary>
    public bool Validate()
    {
        var errors = new List<string>();

        // 1. 检查必填字段
        if (string.IsNullOrWhiteSpace(Name))
            errors.Add("Name 不能为空");

        if (string.IsNullOrWhiteSpace(DisplayName))
            errors.Add("DisplayName 不能为空");

        // 2. 检查数值范围
        if (Hardness < 0)
            errors.Add("Hardness 不能为负数");

        if (Resistance < 0)
            errors.Add("Resistance 不能为负数");

        if (Opacity is < 0 or > 1)
            errors.Add("Opacity 必须在 0-1 范围内");

        if (BaseMineTime <= 0)
            errors.Add("BaseMineTime 必须大于 0");

        // 3. 检查逻辑一致性
        if (IsTransparent && Opacity >= 1.0f)
            GD.PushWarning($"方块 '{Name}' 标记为透明但 Opacity = 1.0");

        if (Hardness == 0 && CanBreak)
            GD.PushWarning($"方块 '{Name}' 硬度为 0 但标记为可破坏");

        if (!CanPlace && !CanBreak)
            GD.PushWarning($"方块 '{Name}' 既不能放置也不能破坏");

        // 4. 检查纹理路径
        if (string.IsNullOrWhiteSpace(TexturePaths.North))
            errors.Add("至少需要提供 North 纹理路径作为默认纹理");

        // 5. 检查状态定义一致性
        if (StateDefinitions.Count > 0 && DefaultState.Count == 0)
            errors.Add("定义了 StateDefinitions 但未提供 DefaultState");

        foreach (var (key, _) in DefaultState)
        {
            if (!StateDefinitions.ContainsKey(key))
                errors.Add($"DefaultState 包含未定义的属性: {key}");
        }

        // 输出错误
        if (errors.Count > 0)
        {
            GD.PushError($"方块 '{Name}' 验证失败:");
            foreach (var error in errors)
            {
                GD.PushError($"  - {error}");
            }

            return false;
        }

        return true;
    }

    /// <summary>
    /// 获取方块的人类可读描述（用于调试）
    /// </summary>
    public override string ToString()
    {
        return $"BlockData[{Id}:{Name}] {DisplayName} ({Category})";
    }

    #endregion

    #region 工厂方法和便捷构造

    /// <summary>
    /// 创建一个简单的方块（所有面使用相同纹理）
    /// 适用于大多数基础方块（石头、泥土等）
    /// </summary>
    public static BlockData CreateSimple(string name, string displayName, string texturePath)
    {
        return new BlockData
        {
            Name = name,
            DisplayName = displayName,
            TexturePaths = BlockTexturePaths.FromAll(texturePath),
            Category = "basic"
        };
    }

    /// <summary>
    /// 创建一个定向方块（顶部、底部、侧面使用不同纹理）
    /// 适用于原木、熔炉等有方向性的方块
    /// </summary>
    public static BlockData CreateDirectional(
        string name,
        string displayName,
        string topTexture,
        string bottomTexture,
        string sideTexture)
    {
        return new BlockData
        {
            Name = name,
            DisplayName = displayName,
            TexturePaths = new BlockTexturePaths
            {
                Top = topTexture,
                Bottom = bottomTexture,
                North = sideTexture,
                South = sideTexture,
                East = sideTexture,
                West = sideTexture
            },
            Category = "directional"
        };
    }

    /// <summary>
    /// 创建一个不可破坏的方块（如基岩）
    /// </summary>
    public static BlockData CreateIndestructible(string name, string displayName, string texturePath)
    {
        var block = CreateSimple(name, displayName, texturePath);
        block.Hardness = 0;
        block.CanBreak = false;
        block.Resistance = float.MaxValue;
        return block;
    }

    #endregion
}