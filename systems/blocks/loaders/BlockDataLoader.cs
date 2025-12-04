using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Godot;

namespace VoxelPath.systems.blocks.loaders;

/// <summary>
/// 方块数据加载器 - 负责从 JSON 配置文件异步加载方块数据
/// 支持进度反馈、错误处理、取消操作
/// </summary>
public partial class BlockDataLoader : Node
{
    #region 信号定义

    /// <summary>加载开始</summary>
    [Signal]
    public delegate void LoadingStartedEventHandler();

    /// <summary>
    /// 加载进度更新
    /// </summary>
    /// <param name="current">当前已加载数量</param>
    /// <param name="total">总数量</param>
    /// <param name="message">当前操作描述</param>
    [Signal]
    public delegate void LoadingProgressEventHandler(int current, int total, string message);

    /// <summary>加载完成</summary>
    /// <param name="success">是否成功</param>
    /// <param name="blockCount">加载的方块数量</param>
    [Signal]
    public delegate void LoadingCompleteEventHandler(bool success, int blockCount);

    /// <summary>
    /// 加载错误
    /// </summary>
    /// <param name="errorMessage">错误信息</param>
    [Signal]
    public delegate void LoadingErrorEventHandler(string errorMessage);

    #endregion

    #region 私有字段

    private ConfigParser _configParser;
    private CancellationTokenSource _cancellationTokenSource;
    private bool _isLoading;

    #endregion

    #region 生命周期

    public override void _Ready()
    {
        _configParser = new ConfigParser();
    }

    public override void _ExitTree()
    {
        // 清理资源
        CancelLoading();
        _configParser?.Dispose();
    }

    #endregion

    #region 公共方法

    /// <summary>
    /// 加载所有方块数据
    /// </summary>
    /// <param name="manifestPath">Manifest 文件路径</param>
    /// <returns>加载的方块数据列表</returns>
    public async Task<List<data.BlockData>> LoadAllBlocksAsync(string manifestPath)
    {
        if (_isLoading)
        {
            GD.PushWarning("Block loading already in progress");
            return new List<data.BlockData>();
        }

        _isLoading = true;
        _cancellationTokenSource = new CancellationTokenSource();
        var token = _cancellationTokenSource.Token;

        try
        {
            EmitSignal(SignalName.LoadingStarted);
            GD.Print("=== Starting Block Loading ===");

            // 1. 加载 Manifest
            var manifest = await LoadManifestAsync(manifestPath, token);
            if (manifest == null)
            {
                EmitSignal(SignalName.LoadingError, "Failed to load manifest");
                return new List<data.BlockData>();
            }

            // 2. 获取分类列表并排序
            var categories = manifest.GetCategories();
            categories.Sort((a, b) => a.Priority.CompareTo(b.Priority));

            // 3. 加载每个分类
            var allBlocks = new List<data.BlockData>();
            var current = 0;
            var total = categories.Count;

            foreach (var category in categories)
            {
                token.ThrowIfCancellationRequested();

                if (!category.Enabled)
                {
                    GD.Print($"Skipping disabled category: {category.Path}");
                    current++;
                    continue;
                }

                EmitSignal(SignalName.LoadingProgress, current, total,
                    $"Loading category: {category.Path}");

                var categoryBlocks = await LoadCategoryAsync(category, token);
                allBlocks.AddRange(categoryBlocks);

                current++;
            }

            // 4. 加载完成
            GD.Print($"Block loading complete. Total blocks: {allBlocks.Count}");
            EmitSignal(SignalName.LoadingComplete, true, allBlocks.Count);

            return allBlocks;
        }
        catch (OperationCanceledException)
        {
            GD.Print("Block loading cancelled");
            EmitSignal(SignalName.LoadingComplete, false, 0);
            return new List<data.BlockData>();
        }
        catch (Exception ex)
        {
            GD.PushError($"Block loading failed: {ex.Message}");
            EmitSignal(SignalName.LoadingError, ex.Message);
            EmitSignal(SignalName.LoadingComplete, false, 0);
            return new List<data.BlockData>();
        }
        finally
        {
            _isLoading = false;
            _cancellationTokenSource?.Dispose();
            _cancellationTokenSource = null;
        }
    }

    /// <summary>
    /// 取消正在进行的加载
    /// </summary>
    public void CancelLoading()
    {
        if (_isLoading && _cancellationTokenSource != null)
        {
            GD.Print("Cancelling block loading...");
            _cancellationTokenSource.Cancel();
        }
    }

    #endregion

    #region 私有方法

    /// <summary>
    /// 加载 Manifest 文件
    /// </summary>
    private async Task<ManifestConfig> LoadManifestAsync(string path, CancellationToken token)
    {
        try
        {
            GD.Print($"Loading manifest: {path}");
            return await _configParser.ParseManifestAsync(path, token);
        }
        catch (Exception ex)
        {
            GD.PushError($"Failed to load manifest: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// 加载指定分类的方块
    /// </summary>
    private async Task<List<data.BlockData>> LoadCategoryAsync(
        CategoryConfig category,
        CancellationToken token)
    {
        try
        {
            GD.Print($"Loading category: {category.Path}");

            // 1. 加载分类配置
            var configPath = Path.Combine(category.Path, category.Config);
            var categoryConfig = await _configParser.ParseCategoryConfigAsync(configPath, token);

            if (categoryConfig == null)
            {
                GD.PushError($"Failed to load category config: {configPath}");
                return new List<data.BlockData>();
            }

            // 2. 加载该分类下的所有方块文件
            var blocks = new List<data.BlockData>();
            foreach (var blockFile in categoryConfig.Blocks)
            {
                token.ThrowIfCancellationRequested();

                var blockPath = Path.Combine(category.Path, blockFile);
                var blockData = await LoadBlockDataAsync(blockPath, token);

                if (blockData != null && blockData.Validate())
                {
                    blocks.Add(blockData);
                }
                else
                {
                    GD.PushWarning($"Invalid block config: {blockPath}");
                }
            }

            GD.Print($"Category loaded: {categoryConfig.Category}, Blocks: {blocks.Count}");
            return blocks;
        }
        catch (Exception ex)
        {
            GD.PushError($"Failed to load category {category.Path}: {ex.Message}");
            return new List<data.BlockData>();
        }
    }

    /// <summary>
    /// 加载单个方块数据
    /// </summary>
    private async Task<data.BlockData> LoadBlockDataAsync(string path, CancellationToken token)
    {
        try
        {
            return await _configParser.ParseBlockDataAsync(path, token);
        }
        catch (Exception ex)
        {
            GD.PushError($"Failed to load block {path}: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// 同步解析方块数据（从 JSON 字符串）
    /// 用于 BlockManager 的同步加载流程
    /// </summary>
    /// <param name="jsonText">JSON 文本内容</param>
    /// <returns>解析的 BlockData,失败返回 null</returns>
    public data.BlockData ParseBlockData(string jsonText)
    {
        try
        {
            return _configParser.ParseBlockDataFromJson(jsonText);
        }
        catch (Exception ex)
        {
            GD.PushError($"[BlockDataLoader] Failed to parse block data: {ex.Message}");
            return null;
        }
    }

    #endregion
}
