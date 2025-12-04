using System.Collections.Generic;
using System.Linq;
using VoxelPath.systems.world_settings;

namespace VoxelPath.systems.blocks.data;

/**
 * 方块状态
 * 表示方块的一个特定状态组合
 * 1. 预定义的强类型属性（使用 world_settings 中的通用枚举）
 * 2. 动态扩展属性（用于特殊方块的自定义状态）
 * 3. 生成状态键（用于调色板压缩存储）
 */
public class BlockState
{
    public string BlockId { get; }
    public int StateId { get; }

    // 预定义的强类型属性（使用全局配置）
    public EntityStates.OxidationLevel Oxidation { get; set; } = EntityStates.OxidationLevel.None;
    public WorldDirection.BaseDirection Facing { get; set; } = WorldDirection.BaseDirection.North;
    public bool Lit { get; set; } = false;

    // 其他可能的状态属性示例
    public EntityStates.DamageLevel? Damage { get; set; }  // 可选：损坏等级
    public EntityStates.MoistureLevel? Moisture { get; set; }  // 可选：湿度等级

    // 动态扩展属性
    private Dictionary<string, object> _extraProperties = new();

    public BlockState(string blockId, int stateId)
    {
        BlockId = blockId;
        StateId = stateId;
    }

    // 动态属性访问
    public void SetExtraProperty<T>(string name, T value)
    {
        _extraProperties[name] = value;
    }

    public T GetExtraProperty<T>(string name, T defaultValue = default)
    {
        return _extraProperties.TryGetValue(name, out var value) && value is T typedValue
            ? typedValue
            : defaultValue;
    }

    // 生成状态键（用于调色板）
    public string GetStateKey()
    {
        var parts = new List<string>();

        // 强类型属性
        if (Oxidation != EntityStates.OxidationLevel.None)
            parts.Add($"oxidation={Oxidation}");
        if (Facing != WorldDirection.BaseDirection.North)
            parts.Add($"facing={Facing}");
        if (Lit)
            parts.Add("lit=true");

        // 可选状态属性
        if (Damage.HasValue)
            parts.Add($"damage={Damage.Value}");
        if (Moisture.HasValue)
            parts.Add($"moisture={Moisture.Value}");

        // 动态属性
        parts.AddRange(_extraProperties.Select(kvp => $"{kvp.Key}={kvp.Value}"));

        return parts.Count > 0 ? $"{BlockId}[{string.Join(",", parts)}]" : BlockId;
    }
}