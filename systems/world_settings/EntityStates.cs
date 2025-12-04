namespace VoxelPath.systems.world_settings;

/// <summary>
/// 物体状态定义 - 通用的状态枚举（用于方块、物品、生物等）
/// </summary>
public static class EntityStates
{
    /// <summary>
    /// 氧化等级 - 适用于金属类物体
    /// 应用场景：
    /// - 方块：铜方块、铁栅栏等
    /// - 物品：铁剑、铜盔甲等
    /// - 生物：铁傀儡、铜傀儡等
    /// </summary>
    public enum OxidationLevel
    {
        None = 0,        // 无氧化（新鲜状态）
        Exposed = 1,     // 轻度氧化（暴露在外）
        Weathered = 2,   // 中度氧化（风化）
        Oxidized = 3     // 完全氧化（生锈）
    }

    /// <summary>
    /// 损坏等级 - 适用于可损坏的物体
    /// 应用场景：
    /// - 方块：裂纹方块
    /// - 物品：工具耐久度
    /// - 生物：傀儡损坏状态
    /// </summary>
    public enum DamageLevel
    {
        Intact = 0,      // 完好无损
        Damaged = 1,     // 轻度损坏
        Cracked = 2,     // 严重损坏
        Broken = 3       // 破碎
    }

    /// <summary>
    /// 湿度等级 - 适用于可吸水的物体
    /// 应用场景：
    /// - 方块：海绵、泥土等
    /// - 生物：苔藓傀儡等
    /// </summary>
    public enum MoistureLevel
    {
        Dry = 0,         // 干燥
        Damp = 1,        // 潮湿
        Wet = 2,         // 湿润
        Saturated = 3    // 饱和
    }

    /// <summary>
    /// 生长阶段 - 适用于可生长的物体
    /// 应用场景：
    /// - 方块：农作物、树苗等
    /// - 生物：幼年傀儡等
    /// </summary>
    public enum GrowthStage
    {
        Seed = 0,        // 种子/幼苗
        Sprout = 1,      // 发芽
        Growing = 2,     // 生长中
        Mature = 3       // 成熟
    }

    /// <summary>
    /// 获取氧化等级的显示名称
    /// </summary>
    public static string GetOxidationName(OxidationLevel level)
    {
        return level switch
        {
            OxidationLevel.None => "崭新",
            OxidationLevel.Exposed => "轻度氧化",
            OxidationLevel.Weathered => "风化",
            OxidationLevel.Oxidized => "生锈",
            _ => level.ToString()
        };
    }

    /// <summary>
    /// 获取下一个氧化等级（用于氧化进程）
    /// </summary>
    public static OxidationLevel? GetNextOxidationLevel(OxidationLevel current)
    {
        return current switch
        {
            OxidationLevel.None => OxidationLevel.Exposed,
            OxidationLevel.Exposed => OxidationLevel.Weathered,
            OxidationLevel.Weathered => OxidationLevel.Oxidized,
            OxidationLevel.Oxidized => null, // 已经完全氧化
            _ => null
        };
    }

    /// <summary>
    /// 获取上一个氧化等级（用于去氧化/修复）
    /// </summary>
    public static OxidationLevel? GetPreviousOxidationLevel(OxidationLevel current)
    {
        return current switch
        {
            OxidationLevel.Oxidized => OxidationLevel.Weathered,
            OxidationLevel.Weathered => OxidationLevel.Exposed,
            OxidationLevel.Exposed => OxidationLevel.None,
            OxidationLevel.None => null, // 已经是崭新状态
            _ => null
        };
    }
}
