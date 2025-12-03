using System.Collections.Generic;
using VoxelPath.systems.world_settings;

namespace VoxelPath.systems.blocks.data;

/// <summary>
/// 方块属性接口 - 定义方块的基本属性契约
/// 注意：接口只定义契约，具体的 [Export] 特性在实现类（BlockData）中添加
/// </summary>
public interface IBlockProperties
{
    // ===== 基础信息 =====

    /// <summary>方块 ID（由 BlockRegistry 分配，不应手动设置）</summary>
    int Id { get; set; }

    /// <summary>方块唯一标识符（如 "stone", "oak_log"）</summary>
    string Name { get; set; }

    /// <summary>方块显示名称（用于 UI 显示）</summary>
    string DisplayName { get; set; }

    /// <summary>方块描述</summary>
    string Description { get; set; }

    /// <summary>方块分类（如 "nature", "ores", "machines"）</summary>
    string Category { get; set; }

    // ===== 纹理属性 =====

    /// <summary>纹理路径配置（仅存储路径，不加载实际纹理）</summary>
    BlockTexturePaths TexturePaths { get; set; }

    /// <summary>法线贴图路径配置</summary>
    BlockTexturePaths NormalPaths { get; set; }

    /// <summary>是否透明</summary>
    bool IsTransparent { get; set; }

    /// <summary>透明度（0.0 = 完全透明, 1.0 = 不透明）</summary>
    float Opacity { get; set; }

    /// <summary>是否自发光</summary>
    bool IsEmissive { get; set; }

    /// <summary>自发光强度（仅当 IsEmissive = true 时有效）</summary>
    float EmissionStrength { get; set; }

    // ===== 物理属性 =====

    /// <summary>硬度（影响挖掘速度，0 = 无法破坏，如基岩）</summary>
    float Hardness { get; set; }

    /// <summary>抗爆炸性（影响爆炸抵抗力）</summary>
    float Resistance { get; set; }

    /// <summary>是否有碰撞体积</summary>
    bool HasCollision { get; set; }

    /// <summary>是否为实心方块（影响光照传播和 AI 寻路）</summary>
    bool IsSolid { get; set; }

    // ===== 交互属性 =====

    /// <summary>是否可以被玩家放置</summary>
    bool CanPlace { get; set; }

    /// <summary>是否可以被破坏</summary>
    bool CanBreak { get; set; }

    /// <summary>需要的工具类型（如 Pickaxe, Axe, Shovel）</summary>
    IWorldItemCategory.ToolCategory? ToolRequired { get; set; }

    /// <summary>需要的最低工具等级（0=任意, 1=木制, 2=石制, 3=铁制, 4=钻石制）</summary>
    int MineLevel { get; set; }

    /// <summary>基础挖掘时间（秒，实际时间受工具影响）</summary>
    float BaseMineTime { get; set; }

    // ===== 方块状态 =====

    /// <summary>
    /// 方块状态定义（定义此方块可能的状态属性）
    /// 例如：{ "facing": ["north", "south", "east", "west"], "lit": [true, false] }
    /// </summary>
    Dictionary<string, List<object>> StateDefinitions { get; set; }

    /// <summary>
    /// 默认状态值（当方块被放置时的初始状态）
    /// 例如：{ "facing": "north", "lit": false }
    /// </summary>
    Dictionary<string, object> DefaultState { get; set; }

    // ===== 扩展属性 =====

    /// <summary>自定义属性（用于存储额外的键值对数据）</summary>
    Dictionary<string, object> CustomProperties { get; set; }

    /// <summary>验证方块属性是否有效</summary>
    bool Validate();
}

/// <summary>
/// 方块纹理路径配置结构体（高性能访问）
/// 使用结构体而非 Dictionary，避免频繁查询开销
/// </summary>
public struct BlockTexturePaths
{
    /// <summary>顶面纹理路径</summary>
    public string Top;

    /// <summary>底面纹理路径</summary>
    public string Bottom;

    /// <summary>北面纹理路径</summary>
    public string North;

    /// <summary>南面纹理路径</summary>
    public string South;

    /// <summary>东面纹理路径</summary>
    public string East;

    /// <summary>西面纹理路径</summary>
    public string West;

    /// <summary>
    /// 获取指定方向的纹理路径
    /// </summary>
    public readonly string GetPath(WorldDirection.BaseDirection direction)
    {
        return direction switch
        {
            WorldDirection.BaseDirection.Up => Top ?? North,
            WorldDirection.BaseDirection.Down => Bottom ?? North,
            WorldDirection.BaseDirection.North => North,
            WorldDirection.BaseDirection.South => South ?? North,
            WorldDirection.BaseDirection.East => East ?? North,
            WorldDirection.BaseDirection.West => West ?? North,
            // 额外的方向别名支持
            WorldDirection.BaseDirection.Back => North,
            WorldDirection.BaseDirection.Forward => South,
            WorldDirection.BaseDirection.Right => East,
            WorldDirection.BaseDirection.Left => West,
            _ => North
        };
    }

    /// <summary>
    /// 根据方向设置纹理路径
    /// </summary>
    public void SetPath(WorldDirection.BaseDirection direction, string path)
    {
        switch (direction)
        {
            case WorldDirection.BaseDirection.Up:
                Top = path;
                break;
            case WorldDirection.BaseDirection.Down:
                Bottom = path;
                break;
            case WorldDirection.BaseDirection.North:
            case WorldDirection.BaseDirection.Back:
                North = path;
                break;
            case WorldDirection.BaseDirection.South:
            case WorldDirection.BaseDirection.Forward:
                South = path;
                break;
            case WorldDirection.BaseDirection.East:
            case WorldDirection.BaseDirection.Right:
                East = path;
                break;
            case WorldDirection.BaseDirection.West:
            case WorldDirection.BaseDirection.Left:
                West = path;
                break;
        }
    }

    /// <summary>
    /// 从 "all" 路径创建（所有面使用相同纹理）
    /// </summary>
    public static BlockTexturePaths FromAll(string path)
    {
        return new BlockTexturePaths
        {
            Top = path,
            Bottom = path,
            North = path,
            South = path,
            East = path,
            West = path
        };
    }
}

