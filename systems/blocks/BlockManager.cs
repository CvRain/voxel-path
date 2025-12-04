using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Godot;
using VoxelPath.systems.blocks.data;
using VoxelPath.systems.blocks.loaders;
using VoxelPath.systems.blocks.registry;

namespace VoxelPath.systems.blocks;

/// <summary>
/// 方块管理器 - 整个方块系统的协调器
/// 
/// 职责：
/// 1. 加载 Manifest 和 Category 配置
/// 2. 协调 BlockDataLoader、BlockRegistry、BlockStateRegistry
/// 3. 批量加载和注册方块
/// 4. 提供统一的初始化入口
/// 5. 管理加载进度和错误处理
/// 
/// 使用流程：
/// 1. 创建 BlockManager 实例
/// 2. 调用 Initialize() 或 InitializeAsync()
/// 3. 访问 BlockRegistry 和 BlockStateRegistry
/// </summary>
public partial class BlockManager : Node
{
    #region 组件引用

    private BlockDataLoader _blockDataLoader;
    private BlockRegistry _blockRegistry;
    private BlockStateRegistry _blockStateRegistry;

    #endregion

    #region 配置路径

    private const string ManifestPath = "res://Data/blocks/_manifest.json";
    private const string DefaultNamespace = "voxelpath";

    #endregion

    #region 状态

    private Dictionary<string, CategoryConfig> _loadedCategories = new();
    private ManifestConfig _manifest;
    private bool _isInitialized = false;

    #endregion

    #region 信号

    [Signal]
    public delegate void LoadingStartedEventHandler();

    [Signal]
    public delegate void LoadingProgressEventHandler(int current, int total);

    [Signal]
    public delegate void LoadingCompleteEventHandler(int totalBlocks, int totalStates);

    [Signal]
    public delegate void LoadingErrorEventHandler(string error);

    #endregion

    #region 属性

    public bool IsInitialized => _isInitialized;
    public IBlockRegistry BlockRegistry => _blockRegistry;
    public IBlockStateRegistry BlockStateRegistry => _blockStateRegistry;
    public int TotalBlocksLoaded => _blockRegistry?.Count ?? 0;
    public int TotalStatesGenerated => _blockStateRegistry?.TotalStateCount ?? 0;

    #endregion

    #region 初始化

    public override void _Ready()
    {
        GD.Print("[BlockManager] Node ready, waiting for manual initialization");
    }

    /// <summary>
    /// 初始化方块系统（同步版本）
    /// </summary>
    public bool Initialize()
    {
        if (_isInitialized)
        {
            GD.PushWarning("[BlockManager] Already initialized");
            return true;
        }

        GD.Print("\n=== BlockManager Initialization Started ===");
        EmitSignal(SignalName.LoadingStarted);

        try
        {
            // 1. 创建组件
            CreateComponents();

            // 2. 加载 Manifest
            if (!LoadManifest())
            {
                EmitSignal(SignalName.LoadingError, "Failed to load manifest");
                return false;
            }

            // 3. 加载所有分类
            if (!LoadAllCategories())
            {
                EmitSignal(SignalName.LoadingError, "Failed to load categories");
                return false;
            }

            // 4. 注册所有方块到 BlockRegistry
            if (!RegisterAllBlocks())
            {
                EmitSignal(SignalName.LoadingError, "Failed to register blocks");
                return false;
            }

            // 5. 生成所有方块状态
            if (!GenerateAllBlockStates())
            {
                EmitSignal(SignalName.LoadingError, "Failed to generate block states");
                return false;
            }

            // 6. 验证完整性
            ValidateSystem();

            _isInitialized = true;
            GD.Print($"=== BlockManager Initialization Complete ===");
            GD.Print($"Total blocks: {TotalBlocksLoaded}, Total states: {TotalStatesGenerated}\n");

            EmitSignal(SignalName.LoadingComplete, TotalBlocksLoaded, TotalStatesGenerated);
            return true;
        }
        catch (Exception ex)
        {
            GD.PushError($"[BlockManager] Initialization failed: {ex.Message}");
            GD.PushError($"Stack trace: {ex.StackTrace}");
            EmitSignal(SignalName.LoadingError, ex.Message);
            return false;
        }
    }

    /// <summary>
    /// 创建所有组件
    /// </summary>
    private void CreateComponents()
    {
        GD.Print("[BlockManager] Creating components...");

        // 创建 BlockDataLoader
        _blockDataLoader = new BlockDataLoader();
        AddChild(_blockDataLoader);
        _blockDataLoader.Name = "BlockDataLoader";

        // 创建 BlockRegistry
        _blockRegistry = new BlockRegistry();
        AddChild(_blockRegistry);
        _blockRegistry.Name = "BlockRegistry";

        // 创建 BlockStateRegistry
        _blockStateRegistry = new BlockStateRegistry();
        AddChild(_blockStateRegistry);
        _blockStateRegistry.Name = "BlockStateRegistry";

        // 设置引用关系
        _blockStateRegistry.SetBlockRegistry(_blockRegistry);

        GD.Print("[BlockManager] Components created");
    }

    #endregion

    #region Manifest 加载

    /// <summary>
    /// 加载主 Manifest 文件
    /// </summary>
    private bool LoadManifest()
    {
        GD.Print($"[BlockManager] Loading manifest: {ManifestPath}");

        var jsonText = LoadJsonFile(ManifestPath);
        if (string.IsNullOrEmpty(jsonText))
        {
            GD.PushError($"[BlockManager] Failed to read manifest file: {ManifestPath}");
            return false;
        }

        try
        {
            _manifest = JsonSerializer.Deserialize<ManifestConfig>(jsonText);
            if (_manifest == null || _manifest.Categories == null)
            {
                GD.PushError("[BlockManager] Invalid manifest structure");
                return false;
            }

            GD.Print($"[BlockManager] Manifest loaded: {_manifest.Categories.Count} categories");
            return true;
        }
        catch (Exception ex)
        {
            GD.PushError($"[BlockManager] Failed to parse manifest: {ex.Message}");
            return false;
        }
    }

    #endregion

    #region Category 加载

    /// <summary>
    /// 加载所有分类
    /// </summary>
    private bool LoadAllCategories()
    {
        GD.Print("[BlockManager] Loading categories...");

        var categories = _manifest.Categories
            .Where(c => c.Enabled)
            .OrderBy(c => c.Priority)
            .ToList();

        var current = 0;
        var total = categories.Count;

        foreach (var categoryInfo in categories)
        {
            current++;
            EmitSignal(SignalName.LoadingProgress, current, total);

            if (!LoadCategory(categoryInfo))
            {
                GD.PushWarning($"[BlockManager] Failed to load category: {categoryInfo.Path}");
                continue;
            }
        }

        GD.Print($"[BlockManager] Loaded {_loadedCategories.Count} categories");
        return _loadedCategories.Count > 0;
    }

    /// <summary>
    /// 加载单个分类
    /// </summary>
    private bool LoadCategory(CategoryInfo categoryInfo)
    {
        GD.Print($"[BlockManager] Loading category: {categoryInfo.Path}");

        var configPath = $"{categoryInfo.Path}/{categoryInfo.Config}";
        var jsonText = LoadJsonFile(configPath);

        if (string.IsNullOrEmpty(jsonText))
        {
            GD.PushError($"[BlockManager] Failed to read category config: {configPath}");
            return false;
        }

        try
        {
            var categoryConfig = JsonSerializer.Deserialize<CategoryConfig>(jsonText);
            if (categoryConfig == null)
            {
                GD.PushError($"[BlockManager] Invalid category config: {configPath}");
                return false;
            }

            categoryConfig.BasePath = categoryInfo.Path;
            _loadedCategories[categoryConfig.Category] = categoryConfig;

            GD.Print($"[BlockManager] Category '{categoryConfig.Category}' loaded: {categoryConfig.Blocks.Count} blocks");
            return true;
        }
        catch (Exception ex)
        {
            GD.PushError($"[BlockManager] Failed to parse category config: {ex.Message}");
            return false;
        }
    }

    #endregion

    #region 方块注册

    /// <summary>
    /// 注册所有方块到 BlockRegistry
    /// </summary>
    private bool RegisterAllBlocks()
    {
        GD.Print("[BlockManager] Registering blocks...");

        var totalBlocks = 0;

        foreach (var (categoryName, categoryConfig) in _loadedCategories)
        {
            foreach (var blockFile in categoryConfig.Blocks)
            {
                var blockPath = $"{categoryConfig.BasePath}/{blockFile}";

                // 直接读取 JSON 文件
                var jsonText = LoadJsonFile(blockPath);
                if (string.IsNullOrEmpty(jsonText))
                {
                    GD.PushWarning($"[BlockManager] Failed to load block: {blockPath}");
                    continue;
                }

                // 使用 BlockDataLoader 解析
                var blockData = _blockDataLoader.ParseBlockData(jsonText);
                if (blockData == null)
                {
                    GD.PushWarning($"[BlockManager] Failed to parse block: {blockPath}");
                    continue;
                }

                // 构建 NamespacedId
                var namespacedId = new NamespacedId($"{DefaultNamespace}:{blockData.Name}");

                // 注册到 BlockRegistry
                var assignedId = _blockRegistry.Register(namespacedId, blockData);
                if (assignedId >= 0)
                {
                    totalBlocks++;
                    GD.Print($"[BlockManager] Registered: {namespacedId.FullId} (ID: {assignedId})");
                }
                else
                {
                    GD.PushWarning($"[BlockManager] Failed to register: {namespacedId.FullId}");
                }
            }
        }

        GD.Print($"[BlockManager] Registered {totalBlocks} blocks");
        return totalBlocks > 0;
    }

    #endregion

    #region 状态生成

    /// <summary>
    /// 为所有方块生成状态
    /// </summary>
    private bool GenerateAllBlockStates()
    {
        GD.Print("[BlockManager] Generating block states...");

        // 获取所有已注册的方块
        var allBlocks = new Dictionary<int, BlockData>();
        var blockCount = _blockRegistry.Count;

        for (int id = 0; id < blockCount; id++)
        {
            var blockData = _blockRegistry.GetById(id);
            if (blockData != null)
            {
                allBlocks[id] = blockData;
            }
        }

        // 批量生成状态
        var totalStates = _blockStateRegistry.RegisterAllBlockStates(allBlocks);

        GD.Print($"[BlockManager] Generated {totalStates} states for {allBlocks.Count} blocks");
        return totalStates > 0;
    }

    #endregion

    #region 验证

    /// <summary>
    /// 验证系统完整性
    /// </summary>
    private void ValidateSystem()
    {
        GD.Print("[BlockManager] Validating system integrity...");

        var registryValid = _blockRegistry.ValidateIntegrity();
        var stateRegistryValid = _blockStateRegistry.ValidateIntegrity();

        if (registryValid && stateRegistryValid)
        {
            GD.Print("[BlockManager] System validation passed ✓");
        }
        else
        {
            GD.PushWarning("[BlockManager] System validation failed!");
        }
    }

    #endregion

    #region 调试工具

    /// <summary>
    /// 打印所有已加载的方块
    /// </summary>
    public void PrintAllBlocks()
    {
        _blockRegistry?.PrintRegistry();
    }

    /// <summary>
    /// 打印所有方块状态
    /// </summary>
    public void PrintAllStates()
    {
        _blockStateRegistry?.PrintStates();
    }

    /// <summary>
    /// 获取系统统计信息
    /// </summary>
    public string GetStatistics()
    {
        return $@"
=== Block System Statistics ===
Categories Loaded: {_loadedCategories.Count}
Total Blocks: {TotalBlocksLoaded}
Total States: {TotalStatesGenerated}
Namespaces: {string.Join(", ", _blockRegistry?.GetNamespaces() ?? [])}
Initialized: {_isInitialized}
================================
";
    }

    #endregion

    #region 辅助方法

    /// <summary>
    /// 加载 JSON 文件
    /// </summary>
    private string LoadJsonFile(string path)
    {
        if (!FileAccess.FileExists(path))
        {
            GD.PushError($"[BlockManager] File not found: {path}");
            return null;
        }

        using var file = FileAccess.Open(path, FileAccess.ModeFlags.Read);
        if (file == null)
        {
            GD.PushError($"[BlockManager] Failed to open file: {path}");
            return null;
        }

        return file.GetAsText();
    }

    #endregion

    #region 配置数据结构

    private class ManifestConfig
    {
        public string format_version { get; set; }
        public string description { get; set; }
        public List<CategoryInfo> categories { get; set; }

        public List<CategoryInfo> Categories => categories ?? new List<CategoryInfo>();
    }

    private class CategoryInfo
    {
        public string path { get; set; }
        public string config { get; set; } = "config.json";
        public bool enabled { get; set; } = true;
        public int priority { get; set; }
        public string description { get; set; }

        public string Path => path;
        public string Config => config;
        public bool Enabled => enabled;
        public int Priority => priority;
    }

    private class CategoryConfig
    {
        public string category { get; set; }
        public string display_name { get; set; }
        public int priority { get; set; }
        public string description { get; set; }
        public string version { get; set; }
        public List<string> blocks { get; set; }

        public string Category => category ?? "unknown";
        public List<string> Blocks => blocks ?? new List<string>();
        public string BasePath { get; set; }
    }

    #endregion
}
