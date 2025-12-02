using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace VoxelPath.systems.blocks.data;

/**
 * 方块状态
 * 非常粗线的想法， 只是用来表示当先的设计思路
 * 1. 预定义的强类型属性
 * 2. 动态扩展属性
 * 3. 生成状态键（用于调色板）
 */
public class BlockState
{
    public string BlockId { get; }
    public int StateId { get; }

    // 预定义的强类型属性
    public OxidationLevel Oxidation { get; set; } = OxidationLevel.None;
    public BlockFacing Facing { get; set; } = BlockFacing.North;
    public bool Lit { get; set; } = false;

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
        if (Oxidation != OxidationLevel.None)
            parts.Add($"oxidation={Oxidation}");
        if (Facing != BlockFacing.North)
            parts.Add($"facing={Facing}");
        if (Lit)
            parts.Add("lit=true");

        // 动态属性
        foreach (var kvp in _extraProperties)
        {
            parts.Add($"{kvp.Key}={kvp.Value}");
        }

        return parts.Count > 0 ? $"{BlockId}[{string.Join(",", parts)}]" : BlockId;
    }
}

// 枚举定义
public enum OxidationLevel { None, Exposed, Weathered, Oxidized }
public enum BlockFacing { North, South, East, West, Up, Down }