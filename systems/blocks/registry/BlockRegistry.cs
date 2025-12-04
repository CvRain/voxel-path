using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Godot;
using VoxelPath.systems.blocks.data;

namespace VoxelPath.systems.blocks.registry;

/// <summary>
/// 方块注册表 - 管理所有方块的注册和查询
/// 
/// 设计要点：
/// 1. 使用 NamespacedId 防止模组冲突
/// 2. 内部使用数字 ID 提高性能（数组访问）
/// 3. 双向映射：NamespacedId ↔ NumericId ↔ BlockData
/// 4. 支持 ID 持久化（存档兼容性）
/// </summary>
public partial class BlockRegistry : Node, IBlockRegistry
{
    #region 常量

    /// <summary>空气方块的固定 ID</summary>
    public const int AirId = 0;

    /// <summary>最大方块数量（16 位足够）</summary>
    private const int MaxBlocks = 65536;

    #endregion

    #region 存储结构

    // 核心映射表
    private readonly Dictionary<NamespacedId, int> _nameToId = new();
    private readonly Dictionary<int, NamespacedId> _idToName = new();
    private readonly Dictionary<int, BlockData> _idToData = new();

    // 命名空间索引（加速按命名空间查询）
    private readonly Dictionary<string, List<int>> _namespaceIndex = new();

    // ID 分配器
    private int _nextId = 1; // 0 保留给空气

    #endregion

    #region 属性

    public int Count => _idToData.Count;
    public int NextId => _nextId;

    #endregion

    #region 初始化

    public override void _Ready()
    {
        // 注册空气方块（ID = 0）
        RegisterAirBlock();
    }

    /// <summary>
    /// 注册空气方块（特殊方块，ID 固定为 0）
    /// </summary>
    private void RegisterAirBlock()
    {
        var airId = NamespacedId.Air;
        var airData = BlockData.CreateSimple(
            name: "air",
            displayName: "空气",
            texturePath: "" // 空气无纹理
        );

        airData.Id = AirId;
        airData.IsSolid = false;
        airData.HasCollision = false;
        airData.IsTransparent = true;
        airData.CanPlace = false;
        airData.CanBreak = false;

        _nameToId[airId] = AirId;
        _idToName[AirId] = airId;
        _idToData[AirId] = airData;

        AddToNamespaceIndex(airId, AirId);

        GD.Print($"[BlockRegistry] Air block registered: {airId} → ID {AirId}");
    }

    #endregion

    #region 注册方法

    public int Register(NamespacedId namespacedId, BlockData blockData)
    {
        // 1. 验证参数
        if (blockData == null)
        {
            GD.PushError($"[BlockRegistry] Cannot register null BlockData");
            return -1;
        }

        if (!blockData.Validate())
        {
            GD.PushError($"[BlockRegistry] BlockData validation failed: {namespacedId}");
            return -1;
        }

        // 2. 检查是否已注册
        if (_nameToId.TryGetValue(namespacedId, out var value))
        {
            GD.PushWarning($"[BlockRegistry] Block already registered: {namespacedId}");
            return value;
        }

        // 3. 检查 ID 是否用尽
        if (_nextId >= MaxBlocks)
        {
            GD.PushError($"[BlockRegistry] Maximum block limit reached: {MaxBlocks}");
            return -1;
        }

        // 4. 分配数字 ID
        var numericId = _nextId++;

        // 5. 建立映射
        _nameToId[namespacedId] = numericId;
        _idToName[numericId] = namespacedId;
        _idToData[numericId] = blockData;

        // 6. 更新 BlockData 的 ID
        blockData.Id = numericId;

        // 7. 添加到命名空间索引
        AddToNamespaceIndex(namespacedId, numericId);

        GD.Print($"[BlockRegistry] Registered: {namespacedId} → ID {numericId} ({blockData.DisplayName})");

        return numericId;
    }

    public int RegisterAll(Dictionary<NamespacedId, BlockData> blocks)
    {
        var successCount = 0;

        foreach (var (namespacedId, blockData) in blocks)
        {
            if (Register(namespacedId, blockData) >= 0)
                successCount++;
        }

        GD.Print($"[BlockRegistry] Batch registration complete: {successCount}/{blocks.Count}");
        return successCount;
    }

    public bool Unregister(NamespacedId namespacedId)
    {
        // 警告：注销方块可能破坏存档兼容性
        if (!_nameToId.TryGetValue(namespacedId, out var numericId))
            return false;

        // 不允许注销空气
        if (numericId == AirId)
        {
            GD.PushError("[BlockRegistry] Cannot unregister air block");
            return false;
        }

        _nameToId.Remove(namespacedId);
        _idToName.Remove(numericId);
        _idToData.Remove(numericId);

        RemoveFromNamespaceIndex(namespacedId, numericId);

        GD.Print($"[BlockRegistry] Unregistered: {namespacedId} (ID {numericId})");
        return true;
    }

    #endregion

    #region 查询方法

    public BlockData GetById(int numericId)
    {
        return _idToData.GetValueOrDefault(numericId);
    }

    public BlockData GetByNamespacedId(NamespacedId namespacedId)
    {
        if (_nameToId.TryGetValue(namespacedId, out var numericId))
            return GetById(numericId);
        return null;
    }

    public BlockData GetByString(string id)
    {
        if (!NamespacedId.TryParse(id, out var namespacedId))
        {
            GD.PushWarning($"[BlockRegistry] Invalid ID format: {id}");
            return null;
        }

        return GetByNamespacedId(namespacedId);
    }

    public int GetNumericId(NamespacedId namespacedId)
    {
        return _nameToId.GetValueOrDefault(namespacedId, -1);
    }

    public NamespacedId GetNamespacedId(int numericId)
    {
        return _idToName.GetValueOrDefault(numericId);
    }

    #endregion

    #region 检查方法

    public bool Contains(NamespacedId namespacedId)
    {
        return _nameToId.ContainsKey(namespacedId);
    }

    public bool IsValidId(int numericId)
    {
        return _idToData.ContainsKey(numericId);
    }

    public IReadOnlyList<string> GetNamespaces()
    {
        return _namespaceIndex.Keys.ToList();
    }

    public IReadOnlyList<BlockData> GetBlocksInNamespace(string @namespace)
    {
        if (!_namespaceIndex.TryGetValue(@namespace, out var ids))
            return Array.Empty<BlockData>();

        return ids.Select(id => _idToData[id]).ToList();
    }

    #endregion

    #region 命名空间索引管理

    private void AddToNamespaceIndex(NamespacedId namespacedId, int numericId)
    {
        if (!_namespaceIndex.ContainsKey(namespacedId.Namespace))
            _namespaceIndex[namespacedId.Namespace] = new List<int>();

        _namespaceIndex[namespacedId.Namespace].Add(numericId);
    }

    private void RemoveFromNamespaceIndex(NamespacedId namespacedId, int numericId)
    {
        if (_namespaceIndex.TryGetValue(namespacedId.Namespace, out var list))
        {
            list.Remove(numericId);
            if (list.Count == 0)
                _namespaceIndex.Remove(namespacedId.Namespace);
        }
    }

    #endregion

    #region 持久化

    public void SaveMappings(string path)
    {
        var fullPath = ProjectSettings.GlobalizePath(path);
        var directory = Path.GetDirectoryName(fullPath);

        if (!Directory.Exists(directory))
            if (directory != null)
                Directory.CreateDirectory(directory);

        var mappings = new Dictionary<string, int>();
        foreach (var (namespacedId, numericId) in _nameToId)
        {
            mappings[namespacedId.FullId] = numericId;
        }

        var json = JsonSerializer.Serialize(new
        {
            version = "1.0",
            next_id = _nextId,
            mappings = mappings
        }, new JsonSerializerOptions { WriteIndented = true });

        File.WriteAllText(fullPath, json);
        GD.Print($"[BlockRegistry] Saved mappings to: {fullPath}");
    }

    public void LoadMappings(string path)
    {
        var fullPath = ProjectSettings.GlobalizePath(path);
        if (!File.Exists(fullPath))
        {
            GD.PushWarning($"[BlockRegistry] Mapping file not found: {fullPath}");
            return;
        }

        try
        {
            var json = File.ReadAllText(fullPath);
            var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            // 恢复 next_id
            if (root.TryGetProperty("next_id", out var nextIdElement))
            {
                _nextId = nextIdElement.GetInt32();
            }

            // 恢复映射（注意：这里只恢复 ID，不重新加载 BlockData）
            if (root.TryGetProperty("mappings", out var mappingsElement))
            {
                foreach (var property in mappingsElement.EnumerateObject())
                {
                    var namespacedId = new NamespacedId(property.Name);
                    var numericId = property.Value.GetInt32();

                    // 仅更新映射，不创建 BlockData
                    _nameToId[namespacedId] = numericId;
                    _idToName[numericId] = namespacedId;
                }
            }

            GD.Print($"[BlockRegistry] Loaded mappings from: {fullPath}");
        }
        catch (Exception ex)
        {
            GD.PushError($"[BlockRegistry] Failed to load mappings: {ex.Message}");
        }
    }

    #endregion

    #region 调试工具

    public void PrintRegistry()
    {
        GD.Print("\n=== Block Registry ===");
        GD.Print($"Total blocks: {Count}");
        GD.Print($"Next ID: {_nextId}");
        GD.Print($"Namespaces: {string.Join(", ", GetNamespaces())}");
        GD.Print("\nRegistered blocks:");

        foreach (var (numericId, namespacedId) in _idToName.OrderBy(x => x.Key))
        {
            var blockData = _idToData[numericId];
            GD.Print($"  [{numericId:D4}] {namespacedId} - {blockData.DisplayName}");
        }

        GD.Print("======================\n");
    }

    public bool ValidateIntegrity()
    {
        var errors = new List<string>();

        // 1. 检查映射一致性
        foreach (var (namespacedId, numericId) in _nameToId)
        {
            if (!_idToName.ContainsKey(numericId))
                errors.Add($"Missing reverse mapping: {namespacedId} → {numericId}");

            if (!_idToData.ContainsKey(numericId))
                errors.Add($"Missing BlockData: {namespacedId} → {numericId}");
        }

        // 2. 检查 BlockData.Id 一致性
        foreach (var (numericId, blockData) in _idToData)
        {
            if (blockData.Id != numericId)
                errors.Add($"ID mismatch: BlockData.Id={blockData.Id}, expected {numericId}");
        }

        // 3. 检查空气方块
        if (!_idToData.ContainsKey(AirId))
            errors.Add("Air block not registered");

        if (errors.Count > 0)
        {
            GD.PushError("[BlockRegistry] Integrity check failed:");
            foreach (var error in errors)
                GD.PushError($"  - {error}");
            return false;
        }

        GD.Print("[BlockRegistry] Integrity check passed ✓");
        return true;
    }

    #endregion
}