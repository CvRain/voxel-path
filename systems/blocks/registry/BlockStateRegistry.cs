using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Godot;
using VoxelPath.systems.blocks.data;
using VoxelPath.systems.world_settings;

namespace VoxelPath.systems.blocks.registry;

/// <summary>
/// 方块状态注册表 - 管理方块的所有可能状态
/// 
/// 核心职责：
/// 1. 从 JSON 定义生成所有状态组合（笛卡尔积）
/// 2. 将 JSON 属性映射到 BlockState 的强类型属性
/// 3. 每个状态组合分配唯一的 State ID
/// 4. 提供快速状态查询和属性修改
/// 
/// 示例流程：
/// JSON: {"facing": ["north", "south"], "lit": [true, false]}
/// → 生成 4 个 BlockState 实例
/// → State 0: Facing=North, Lit=false [默认]
/// → State 1: Facing=North, Lit=true
/// → State 2: Facing=South, Lit=false
/// → State 3: Facing=South, Lit=true
/// </summary>
public partial class BlockStateRegistry : Node, IBlockStateRegistry
{
    #region 存储结构

    // State ID → BlockState
    private readonly Dictionary<int, BlockState> _stateIdToState = new();

    // Numeric Block ID → 该方块的所有状态 ID 列表
    private readonly Dictionary<int, List<int>> _blockIdToStateIds = new();

    // Numeric Block ID → 默认状态 ID
    private readonly Dictionary<int, int> _blockIdToDefaultStateId = new();

    // 快速查找缓存: (Block ID, State Key) → State ID
    private readonly Dictionary<(int blockId, string stateKey), int> _stateKeyCache = new();

    // BlockRegistry 引用（用于获取 NamespacedId）
    private IBlockRegistry _blockRegistry;

    // State ID 分配器
    private int _nextStateId = 0;

    #endregion

    #region 属性

    public int TotalStateCount => _stateIdToState.Count;
    public int RegisteredBlockCount => _blockIdToStateIds.Count;

    #endregion

    #region 初始化

    /// <summary>
    /// 设置 BlockRegistry 引用（必须在注册状态前调用）
    /// </summary>
    public void SetBlockRegistry(IBlockRegistry blockRegistry)
    {
        _blockRegistry = blockRegistry;
    }

    #endregion

    #region 注册方法

    public int RegisterBlockStates(int numericBlockId, BlockData blockData)
    {
        if (blockData == null)
        {
            GD.PushError("[BlockStateRegistry] Cannot register null BlockData");
            return 0;
        }

        // 检查是否已注册
        if (_blockIdToStateIds.ContainsKey(numericBlockId))
        {
            GD.PushWarning($"[BlockStateRegistry] Block {numericBlockId} states already registered");
            return 0;
        }

        try
        {
            // 解析状态定义
            var stateDefinitions = ParseStateDefinitions(blockData.StateDefinitionsJson);
            var defaultStateDict = ParseDefaultState(blockData.DefaultStateJson);

            // 如果没有状态定义，创建单一默认状态
            if (stateDefinitions.Count == 0)
            {
                return RegisterSingleState(numericBlockId, blockData.Name);
            }

            // 生成所有状态组合（笛卡尔积）
            var allCombinations = GenerateCartesianProduct(stateDefinitions);
            var stateIds = new List<int>();
            var defaultStateId = -1;

            foreach (var propertyDict in allCombinations)
            {
                var stateId = _nextStateId++;

                // 创建 BlockState 并设置强类型属性
                var blockState = CreateBlockState(blockData.Name, stateId, propertyDict);

                _stateIdToState[stateId] = blockState;
                stateIds.Add(stateId);

                // 添加到快速查找缓存（使用 BlockState 的 GetStateKey()）
                var stateKey = ExtractStateKey(blockState);
                _stateKeyCache[(numericBlockId, stateKey)] = stateId;

                // 检查是否为默认状态
                if (IsDefaultState(propertyDict, defaultStateDict))
                {
                    defaultStateId = stateId;
                }
            }

            // 保存映射
            _blockIdToStateIds[numericBlockId] = stateIds;
            _blockIdToDefaultStateId[numericBlockId] = defaultStateId >= 0 ? defaultStateId : stateIds[0];

            GD.Print($"[BlockStateRegistry] Registered {stateIds.Count} states for block {numericBlockId} ({blockData.Name})");
            return stateIds.Count;
        }
        catch (Exception ex)
        {
            GD.PushError($"[BlockStateRegistry] Failed to register states for block {numericBlockId}: {ex.Message}");
            return 0;
        }
    }

    public int RegisterAllBlockStates(Dictionary<int, BlockData> blocks)
    {
        var totalStates = 0;

        foreach (var (blockId, blockData) in blocks)
        {
            totalStates += RegisterBlockStates(blockId, blockData);
        }

        GD.Print($"[BlockStateRegistry] Registered {totalStates} total states for {blocks.Count} blocks");
        return totalStates;
    }

    /// <summary>
    /// 为没有状态的方块注册单一状态
    /// </summary>
    private int RegisterSingleState(int numericBlockId, string namespacedId)
    {
        var stateId = _nextStateId++;
        var blockState = new BlockState(namespacedId, stateId);

        _stateIdToState[stateId] = blockState;
        _blockIdToStateIds[numericBlockId] = [stateId];
        _blockIdToDefaultStateId[numericBlockId] = stateId;

        // 空状态键（无属性）
        _stateKeyCache[(numericBlockId, "")] = stateId;

        return 1;
    }

    #endregion

    #region 查询方法

    public BlockState GetStateById(int stateId)
    {
        return _stateIdToState.GetValueOrDefault(stateId);
    }

    public int GetStateId(int blockId, Dictionary<string, object> properties)
    {
        // 将属性字典转换为状态键
        var stateKey = DictToStateKey(properties);
        return _stateKeyCache.GetValueOrDefault((blockId, stateKey), -1);
    }

    public int GetDefaultStateId(int blockId)
    {
        return _blockIdToDefaultStateId.GetValueOrDefault(blockId, -1);
    }

    public BlockState GetDefaultState(int blockId)
    {
        var stateId = GetDefaultStateId(blockId);
        return stateId >= 0 ? GetStateById(stateId) : null;
    }

    public IReadOnlyList<BlockState> GetAllStatesForBlock(int blockId)
    {
        if (!_blockIdToStateIds.TryGetValue(blockId, out var stateIds))
            return Array.Empty<BlockState>();

        return stateIds.Select(id => _stateIdToState[id]).ToList();
    }

    #endregion

    #region 状态修改

    public int SetProperty(int currentStateId, string propertyName, object newValue)
    {
        var currentState = GetStateById(currentStateId);
        if (currentState == null)
            return -1;

        // 获取当前所有属性
        var properties = ExtractProperties(currentState);

        // 修改指定属性
        properties[propertyName] = newValue;

        // 查找新状态 ID（需要获取 numeric block ID）
        var numericBlockId = GetNumericBlockId(currentState.BlockId);
        if (numericBlockId == -1)
            return -1;

        return GetStateId(numericBlockId, properties);
    }

    public int CycleProperty(int currentStateId, string propertyName)
    {
        var currentState = GetStateById(currentStateId);
        if (currentState == null)
            return currentStateId;

        var numericBlockId = GetNumericBlockId(currentState.BlockId);
        if (numericBlockId == -1)
            return currentStateId;

        // 获取该方块的所有状态，找到此属性的所有可能值
        var allStates = GetAllStatesForBlock(numericBlockId);
        var possibleValues = allStates
            .Select(s => GetPropertyValue(s, propertyName))
            .Where(v => v != null)
            .Distinct()
            .ToList();

        if (possibleValues.Count <= 1)
            return currentStateId;

        // 找到当前值的索引并循环到下一个
        var currentValue = GetPropertyValue(currentState, propertyName);
        var currentIndex = possibleValues.FindIndex(v => Equals(v, currentValue));
        var nextIndex = (currentIndex + 1) % possibleValues.Count;
        var nextValue = possibleValues[nextIndex];

        return SetProperty(currentStateId, propertyName, nextValue);
    }

    #endregion

    #region 属性映射（JSON → 强类型）

    /// <summary>
    /// 从 JSON 属性字典创建 BlockState 并设置强类型属性
    /// </summary>
    private BlockState CreateBlockState(string namespacedId, int stateId, Dictionary<string, object> properties)
    {
        var state = new BlockState(namespacedId, stateId);

        foreach (var (key, value) in properties)
        {
            SetBlockStateProperty(state, key, value);
        }

        return state;
    }

    /// <summary>
    /// 设置 BlockState 的属性（将字符串/数字映射到枚举）
    /// </summary>
    private void SetBlockStateProperty(BlockState state, string propertyName, object value)
    {
        switch (propertyName.ToLowerInvariant())
        {
            case "oxidation":
            case "oxidization":
                state.Oxidation = ParseEnum<EntityStates.OxidationLevel>(value);
                break;

            case "facing":
            case "direction":
                state.Facing = ParseEnum<WorldDirection.BaseDirection>(value);
                break;

            case "lit":
            case "powered":
                state.Lit = Convert.ToBoolean(value);
                break;

            case "damage":
                state.Damage = ParseEnum<EntityStates.DamageLevel>(value);
                break;

            case "moisture":
            case "wetness":
                state.Moisture = ParseEnum<EntityStates.MoistureLevel>(value);
                break;

            default:
                // 未知属性存入 _extraProperties
                state.SetExtraProperty(propertyName, value);
                break;
        }
    }

    /// <summary>
    /// 从 BlockState 提取所有属性到字典
    /// </summary>
    private Dictionary<string, object> ExtractProperties(BlockState state)
    {
        var props = new Dictionary<string, object>();

        // 强类型属性
        if (state.Oxidation != EntityStates.OxidationLevel.None)
            props["oxidation"] = state.Oxidation.ToString().ToLowerInvariant();

        if (state.Facing != WorldDirection.BaseDirection.North)
            props["facing"] = state.Facing.ToString().ToLowerInvariant();

        if (state.Lit)
            props["lit"] = true;

        if (state.Damage.HasValue)
            props["damage"] = state.Damage.Value.ToString().ToLowerInvariant();

        if (state.Moisture.HasValue)
            props["moisture"] = state.Moisture.Value.ToString().ToLowerInvariant();

        // 动态属性（需要反射或者 BlockState 需要提供访问器）
        // 暂时跳过，因为 _extraProperties 是 private

        return props;
    }

    /// <summary>
    /// 获取 BlockState 的指定属性值
    /// </summary>
    private object GetPropertyValue(BlockState state, string propertyName)
    {
        return propertyName.ToLowerInvariant() switch
        {
            "oxidation" or "oxidization" => state.Oxidation,
            "facing" or "direction" => state.Facing,
            "lit" or "powered" => state.Lit,
            "damage" => state.Damage,
            "moisture" or "wetness" => state.Moisture,
            _ => state.GetExtraProperty<object>(propertyName)
        };
    }

    /// <summary>
    /// 从 BlockState 提取状态键（用于缓存查找）
    /// </summary>
    private string ExtractStateKey(BlockState state)
    {
        var parts = new List<string>();

        if (state.Oxidation != EntityStates.OxidationLevel.None)
            parts.Add($"oxidation={state.Oxidation}");

        if (state.Facing != WorldDirection.BaseDirection.North)
            parts.Add($"facing={state.Facing}");

        if (state.Lit)
            parts.Add("lit=true");

        if (state.Damage.HasValue)
            parts.Add($"damage={state.Damage.Value}");

        if (state.Moisture.HasValue)
            parts.Add($"moisture={state.Moisture.Value}");

        parts.Sort(); // 保证顺序一致
        return string.Join(",", parts);
    }

    /// <summary>
    /// 将属性字典转换为状态键
    /// </summary>
    private string DictToStateKey(Dictionary<string, object> properties)
    {
        if (properties.Count == 0)
            return "";

        var parts = properties
            .OrderBy(p => p.Key)
            .Select(p => $"{p.Key}={p.Value}")
            .ToList();

        return string.Join(",", parts);
    }

    /// <summary>
    /// 解析枚举值（支持字符串或数字）
    /// </summary>
    private T ParseEnum<T>(object value) where T : struct, Enum
    {
        if (value is string strValue)
        {
            // 尝试解析字符串（不区分大小写）
            if (Enum.TryParse<T>(strValue, true, out var result))
                return result;
        }
        else if (value is int intValue)
        {
            // 直接转换数字
            return (T)(object)intValue;
        }
        else if (value is JsonElement jsonElement)
        {
            // 处理 JSON 元素
            if (jsonElement.ValueKind == JsonValueKind.String)
                return ParseEnum<T>(jsonElement.GetString());
            else if (jsonElement.ValueKind == JsonValueKind.Number)
                return ParseEnum<T>(jsonElement.GetInt32());
        }

        return default;
    }

    /// <summary>
    /// 获取 Numeric Block ID（从 NamespacedId 查询）
    /// </summary>
    private int GetNumericBlockId(string namespacedId)
    {
        if (_blockRegistry == null)
        {
            GD.PushError("[BlockStateRegistry] BlockRegistry not set!");
            return -1;
        }

        var blockData = _blockRegistry.GetByString(namespacedId);
        return blockData?.Id ?? -1;
    }

    #endregion

    #region 笛卡尔积生成

    /// <summary>
    /// 生成状态属性的笛卡尔积
    /// 例如: {facing: [north, south], lit: [true, false]}
    /// 生成: [{facing: north, lit: true}, {facing: north, lit: false}, ...]
    /// </summary>
    private List<Dictionary<string, object>> GenerateCartesianProduct(
        Dictionary<string, List<object>> stateDefinitions)
    {
        if (stateDefinitions.Count == 0)
            return [new Dictionary<string, object>()];

        var keys = stateDefinitions.Keys.ToList();
        var values = stateDefinitions.Values.ToList();

        return GenerateCartesianProductRecursive(keys, values, 0, new Dictionary<string, object>());
    }

    private List<Dictionary<string, object>> GenerateCartesianProductRecursive(
        List<string> keys,
        List<List<object>> valueLists,
        int index,
        Dictionary<string, object> current)
    {
        if (index >= keys.Count)
            return [new Dictionary<string, object>(current)];

        var results = new List<Dictionary<string, object>>();
        var key = keys[index];
        var values = valueLists[index];

        foreach (var value in values)
        {
            current[key] = value;
            results.AddRange(GenerateCartesianProductRecursive(keys, valueLists, index + 1, current));
        }

        current.Remove(key);
        return results;
    }

    #endregion

    #region JSON 解析

    /// <summary>
    /// 解析状态定义 JSON
    /// 示例: {"facing": ["north", "south"], "oxidation": [0, 1, 2]}
    /// </summary>
    private Dictionary<string, List<object>> ParseStateDefinitions(string json)
    {
        if (string.IsNullOrWhiteSpace(json) || json == "{}")
            return new Dictionary<string, List<object>>();

        try
        {
            using var doc = JsonDocument.Parse(json);
            var result = new Dictionary<string, List<object>>();

            foreach (var property in doc.RootElement.EnumerateObject())
            {
                var values = new List<object>();
                foreach (var item in property.Value.EnumerateArray())
                {
                    values.Add(GetJsonValue(item));
                }
                result[property.Name] = values;
            }

            return result;
        }
        catch (Exception ex)
        {
            GD.PushError($"[BlockStateRegistry] Failed to parse state definitions: {ex.Message}");
            return new Dictionary<string, List<object>>();
        }
    }

    /// <summary>
    /// 解析默认状态 JSON
    /// 示例: {"facing": "north", "oxidation": 0}
    /// </summary>
    private Dictionary<string, object> ParseDefaultState(string json)
    {
        if (string.IsNullOrWhiteSpace(json) || json == "{}")
            return new Dictionary<string, object>();

        try
        {
            using var doc = JsonDocument.Parse(json);
            var result = new Dictionary<string, object>();

            foreach (var property in doc.RootElement.EnumerateObject())
            {
                result[property.Name] = GetJsonValue(property.Value);
            }

            return result;
        }
        catch (Exception ex)
        {
            GD.PushError($"[BlockStateRegistry] Failed to parse default state: {ex.Message}");
            return new Dictionary<string, object>();
        }
    }

    /// <summary>
    /// 从 JsonElement 提取值
    /// </summary>
    private static object GetJsonValue(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.String => element.GetString(),
            JsonValueKind.Number => element.TryGetInt32(out var i) ? i : element.GetDouble(),
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => element.ToString()
        };
    }

    /// <summary>
    /// 检查是否为默认状态
    /// </summary>
    private static bool IsDefaultState(
        Dictionary<string, object> current,
        Dictionary<string, object> defaultState)
    {
        if (defaultState.Count == 0)
            return false;

        foreach (var (key, value) in defaultState)
        {
            if (!current.TryGetValue(key, out var currentValue))
                return false;

            // 规范化比较（字符串统一转小写）
            var normalizedCurrent = NormalizeValue(currentValue);
            var normalizedDefault = NormalizeValue(value);

            if (!Equals(normalizedCurrent, normalizedDefault))
                return false;
        }

        return true;
    }

    private static object NormalizeValue(object value)
    {
        if (value is string str)
            return str.ToLowerInvariant();
        return value;
    }

    #endregion

    #region 调试工具

    public void PrintStates()
    {
        GD.Print("\n=== Block State Registry ===");
        GD.Print($"Total states: {TotalStateCount}");
        GD.Print($"Registered blocks: {RegisteredBlockCount}");
        GD.Print("\nStates by block:");

        foreach (var (blockId, stateIds) in _blockIdToStateIds.OrderBy(x => x.Key))
        {
            var defaultStateId = _blockIdToDefaultStateId[blockId];
            GD.Print($"\nBlock {blockId}: {stateIds.Count} states (default: {defaultStateId})");

            foreach (var stateId in stateIds.Take(10)) // 限制显示数量
            {
                var state = _stateIdToState[stateId];
                var isDefault = stateId == defaultStateId ? " [DEFAULT]" : "";
                var stateKey = ExtractStateKey(state);
                GD.Print($"  [{stateId:D6}] {state.BlockId} {{{stateKey}}}{isDefault}");
            }

            if (stateIds.Count > 10)
                GD.Print($"  ... and {stateIds.Count - 10} more states");
        }

        GD.Print("============================\n");
    }

    public bool ValidateIntegrity()
    {
        var errors = new List<string>();

        // 1. 检查每个方块都有默认状态
        foreach (var blockId in _blockIdToStateIds.Keys)
        {
            if (!_blockIdToDefaultStateId.ContainsKey(blockId))
                errors.Add($"Block {blockId} missing default state");
        }

        // 2. 检查默认状态 ID 有效
        foreach (var (blockId, defaultStateId) in _blockIdToDefaultStateId)
        {
            if (!_stateIdToState.ContainsKey(defaultStateId))
                errors.Add($"Block {blockId} default state {defaultStateId} not found");
        }

        // 3. 检查状态引用有效性
        foreach (var (numericBlockId, stateIds) in _blockIdToStateIds)
        {
            foreach (var stateId in stateIds)
            {
                if (!_stateIdToState.ContainsKey(stateId))
                    errors.Add($"State {stateId} referenced but not found");
            }
        }

        if (errors.Count > 0)
        {
            GD.PushError("[BlockStateRegistry] Integrity check failed:");
            foreach (var error in errors)
                GD.PushError($"  - {error}");
            return false;
        }

        GD.Print("[BlockStateRegistry] Integrity check passed ✓");
        return true;
    }

    #endregion
}