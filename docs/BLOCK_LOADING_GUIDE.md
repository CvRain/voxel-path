# 方块加载系统使用指南

本文档介绍如何使用 `BlockDataLoader` 和 `ConfigParser` 加载方块数据。

---

## 📖 目录

- [系统概述](#系统概述)
- [核心组件](#核心组件)
- [快速开始](#快速开始)
- [配置文件结构](#配置文件结构)
- [高级用法](#高级用法)
- [错误处理](#错误处理)
- [性能优化](#性能优化)

---

## 系统概述

### 架构设计

```
BlockDataLoader (加载器)
    ↓
ConfigParser (解析器)
    ↓
BlockData (数据对象)
```

### 工作流程

```
1. 加载 _manifest.json
   ↓
2. 获取分类列表并按优先级排序
   ↓
3. 加载每个分类的 config.json
   ↓
4. 加载该分类下的所有方块 JSON 文件
   ↓
5. 验证并返回 BlockData 对象列表
```

---

## 核心组件

### BlockDataLoader

**职责：**
- 异步加载方块数据
- 进度反馈
- 错误处理
- 支持取消操作

**关键信号：**
```csharp
[Signal] void LoadingStarted()
[Signal] void LoadingProgress(int current, int total, string message)
[Signal] void LoadingComplete(bool success, int blockCount)
[Signal] void LoadingError(string errorMessage)
```

### ConfigParser

**职责：**
- 解析 JSON 配置文件
- 映射 JSON 到 C# 对象
- 数据类型转换
- 支持多种纹理配置方式

---

## 快速开始

### 1. 基本用法

```csharp
using Godot;
using VoxelPath.systems.blocks.loaders;
using VoxelPath.systems.blocks.data;

public partial class GameManager : Node
{
    private BlockDataLoader _blockLoader;
    
    public override void _Ready()
    {
        // 创建加载器
        _blockLoader = new BlockDataLoader();
        AddChild(_blockLoader);
        
        // 连接信号
        _blockLoader.LoadingStarted += OnLoadingStarted;
        _blockLoader.LoadingProgress += OnLoadingProgress;
        _blockLoader.LoadingComplete += OnLoadingComplete;
        _blockLoader.LoadingError += OnLoadingError;
        
        // 开始加载
        LoadBlocks();
    }
    
    private async void LoadBlocks()
    {
        var blocks = await _blockLoader.LoadAllBlocksAsync(
            "res://Data/blocks/_manifest.json"
        );
        
        GD.Print($"Loaded {blocks.Count} blocks");
        
        // 使用加载的方块
        foreach (var block in blocks)
        {
            GD.Print($"  - {block.DisplayName} ({block.Name})");
        }
    }
    
    private void OnLoadingStarted()
    {
        GD.Print("=== Block Loading Started ===");
    }
    
    private void OnLoadingProgress(int current, int total, string message)
    {
        GD.Print($"Loading: {current}/{total} - {message}");
    }
    
    private void OnLoadingComplete(bool success, int blockCount)
    {
        if (success)
            GD.Print($"✓ Loading complete! Total blocks: {blockCount}");
        else
            GD.PrintErr("✗ Loading failed!");
    }
    
    private void OnLoadingError(string errorMessage)
    {
        GD.PushError($"Error: {errorMessage}");
    }
}
```

### 2. 带进度 UI 的加载

```csharp
public partial class LoadingScreen : Control
{
    [Export] private ProgressBar _progressBar;
    [Export] private Label _statusLabel;
    
    private BlockDataLoader _loader;
    
    public async void StartLoading()
    {
        _loader = new BlockDataLoader();
        AddChild(_loader);
        
        _loader.LoadingProgress += UpdateProgress;
        _loader.LoadingComplete += OnComplete;
        
        var blocks = await _loader.LoadAllBlocksAsync(
            "res://Data/blocks/_manifest.json"
        );
        
        // 加载完成后的逻辑...
    }
    
    private void UpdateProgress(int current, int total, string message)
    {
        _progressBar.Value = (float)current / total * 100;
        _statusLabel.Text = message;
    }
    
    private void OnComplete(bool success, int blockCount)
    {
        if (success)
        {
            _statusLabel.Text = $"加载完成！共 {blockCount} 个方块";
            // 切换到主场景...
        }
    }
}
```

### 3. 支持取消的加载

```csharp
public partial class BlockManager : Node
{
    private BlockDataLoader _loader;
    private bool _isLoading;
    
    public async void LoadBlocks()
    {
        if (_isLoading)
        {
            GD.Print("Already loading...");
            return;
        }
        
        _loader = new BlockDataLoader();
        AddChild(_loader);
        _isLoading = true;
        
        try
        {
            var blocks = await _loader.LoadAllBlocksAsync(
                "res://Data/blocks/_manifest.json"
            );
            
            GD.Print($"Loaded {blocks.Count} blocks");
        }
        finally
        {
            _isLoading = false;
        }
    }
    
    public void CancelLoading()
    {
        if (_isLoading)
        {
            _loader?.CancelLoading();
            GD.Print("Loading cancelled by user");
        }
    }
    
    public override void _Input(InputEvent @event)
    {
        // ESC 键取消加载
        if (@event.IsActionPressed("ui_cancel"))
        {
            CancelLoading();
        }
    }
}
```

---

## 配置文件结构

### Manifest 文件 (_manifest.json)

```json
{
  "format_version": "1.0",
  "categories": [
    {
      "path": "res://Data/blocks/nature",
      "config": "config.json",
      "enabled": true,
      "priority": 10,
      "description": "自然生成的方块"
    },
    {
      "path": "res://Data/blocks/ores",
      "config": "config.json",
      "enabled": true,
      "priority": 20,
      "description": "矿石方块"
    }
  ],
  "modded_categories": [
    {
      "path": "user://mods/example_mod/blocks",
      "config": "config.json",
      "enabled": true,
      "priority": 100,
      "description": "示例模组方块"
    }
  ]
}
```

**字段说明：**
- `format_version`: 配置格式版本
- `categories`: 内置分类列表
- `modded_categories`: 模组分类列表
- `path`: 分类文件夹路径
- `config`: 分类配置文件名
- `enabled`: 是否启用该分类
- `priority`: 加载优先级(数值越小越优先)

### 分类配置文件 (config.json)

```json
{
  "category": "nature",
  "blocks": [
    "stone.json",
    "dirt.json",
    "grass.json",
    "oak_log.json"
  ]
}
```

### 方块配置文件

#### 简单方块 (所有面相同纹理)

```json
{
  "name": "stone",
  "display_name": "石头",
  "description": "坚硬的石头",
  "category": "nature",
  
  "textures": {
    "all": "res://assets/textures/blocks/stone.png"
  },
  
  "hardness": 5.0,
  "tool_required": "pickaxe",
  "mine_level": 0
}
```

#### 方向性方块 (不同面不同纹理)

```json
{
  "name": "oak_log",
  "display_name": "橡木原木",
  "description": "天然的橡木原木",
  "category": "nature",
  
  "textures": {
    "top": "res://assets/textures/blocks/oak_log_top.png",
    "bottom": "res://assets/textures/blocks/oak_log_top.png",
    "north": "res://assets/textures/blocks/oak_log_side.png",
    "south": "res://assets/textures/blocks/oak_log_side.png",
    "east": "res://assets/textures/blocks/oak_log_side.png",
    "west": "res://assets/textures/blocks/oak_log_side.png"
  },
  
  "hardness": 2.0,
  "tool_required": "axe",
  "state_definitions": "{\"facing\":[\"up\",\"down\",\"north\",\"south\",\"east\",\"west\"]}",
  "default_state": "{\"facing\":\"up\"}"
}
```

#### 发光方块

```json
{
  "name": "glowstone",
  "display_name": "荧石",
  "description": "会发光的神奇方块",
  "category": "nature",
  
  "textures": {
    "all": "res://assets/textures/blocks/glowstone.png"
  },
  
  "is_emissive": true,
  "emission_strength": 2.5,
  "hardness": 0.3,
  "custom_properties": "{\"light_color\":\"#FFCC66\"}"
}
```

#### 带法线贴图的方块

```json
{
  "name": "copper_ore",
  "display_name": "铜矿石",
  "category": "ores",
  
  "textures": {
    "all": "res://assets/textures/blocks/copper_ore.png"
  },
  "normals": {
    "all": "res://assets/textures/blocks/copper_ore_normal.png"
  },
  
  "hardness": 3.0,
  "tool_required": "pickaxe",
  "mine_level": 1
}
```

### 完整字段列表

```json
{
  // === 基本信息 ===
  "name": "block_id",              // 必填：方块唯一标识符
  "display_name": "显示名称",       // 必填：UI 显示名称
  "description": "方块描述",        // 可选：工具提示
  "category": "nature",            // 可选：分类，默认 "misc"
  
  // === 纹理配置 ===
  "textures": {
    // 方式1：所有面使用同一纹理
    "all": "path/to/texture.png",
    
    // 方式2：指定各个面
    "top": "path/to/top.png",
    "bottom": "path/to/bottom.png",
    "north": "path/to/north.png",
    "south": "path/to/south.png",
    "east": "path/to/east.png",
    "west": "path/to/west.png"
  },
  
  "normals": {                      // 可选：法线贴图(结构同 textures)
    "all": "path/to/normal.png"
  },
  
  // === 视觉效果 ===
  "is_transparent": false,          // 默认 false
  "opacity": 1.0,                   // 0.0 - 1.0，默认 1.0
  "is_emissive": false,             // 是否自发光，默认 false
  "emission_strength": 1.0,         // 发光强度，默认 1.0
  
  // === 物理属性 ===
  "hardness": 1.0,                  // 硬度，默认 1.0
  "resistance": 1.0,                // 抗爆炸性，默认 1.0
  "has_collision": true,            // 是否有碰撞，默认 true
  "is_solid": true,                 // 是否实心，默认 true
  
  // === 交互属性 ===
  "can_place": true,                // 可放置，默认 true
  "can_break": true,                // 可破坏，默认 true
  "tool_required": "pickaxe",       // 工具类型："none", "axe", "pickaxe", "shovel", "hammer", "scissors", "brush", "scythe", "hoe"
  "mine_level": 0,                  // 最低工具等级，默认 0
  "base_mine_time": 1.0,            // 基础挖掘时间(秒)，默认 1.0
  
  // === 方块状态 ===
  "state_definitions": "{}",        // JSON 字符串，定义状态属性
  "default_state": "{}",            // JSON 字符串，默认状态值
  
  // === 自定义属性 ===
  "custom_properties": "{}"         // JSON 字符串，任意扩展数据
}
```

---

## 高级用法

### 1. 直接使用 ConfigParser

```csharp
using VoxelPath.systems.blocks.loaders;

// 创建解析器
var parser = new ConfigParser();

// 解析单个方块文件
var blockData = await parser.ParseBlockDataAsync(
    "res://Data/blocks/nature/stone.json",
    CancellationToken.None
);

GD.Print($"Loaded: {blockData.DisplayName}");
```

### 2. 自定义加载流程

```csharp
public class CustomBlockLoader
{
    private ConfigParser _parser = new();
    
    public async Task<BlockData> LoadSingleBlock(string path)
    {
        var data = await _parser.ParseBlockDataAsync(path, default);
        
        if (!data.Validate())
        {
            throw new Exception($"Invalid block data: {path}");
        }
        
        return data;
    }
    
    public async Task<List<BlockData>> LoadFromManifest(string manifestPath)
    {
        var manifest = await _parser.ParseManifestAsync(manifestPath, default);
        var blocks = new List<BlockData>();
        
        foreach (var category in manifest.GetCategories())
        {
            if (!category.Enabled) continue;
            
            // 自定义加载逻辑...
        }
        
        return blocks;
    }
}
```

### 3. 批量验证配置

```csharp
public async Task ValidateAllBlocks(string manifestPath)
{
    var loader = new BlockDataLoader();
    AddChild(loader);
    
    var blocks = await loader.LoadAllBlocksAsync(manifestPath);
    var invalidBlocks = new List<string>();
    
    foreach (var block in blocks)
    {
        if (!block.Validate())
        {
            invalidBlocks.Add(block.Name);
        }
    }
    
    if (invalidBlocks.Count > 0)
    {
        GD.PrintErr($"Found {invalidBlocks.Count} invalid blocks:");
        foreach (var name in invalidBlocks)
        {
            GD.PrintErr($"  - {name}");
        }
    }
    else
    {
        GD.Print("✓ All blocks are valid!");
    }
}
```

---

## 错误处理

### 常见错误

#### 1. 文件未找到

```csharp
try
{
    var blocks = await loader.LoadAllBlocksAsync("wrong/path.json");
}
catch (FileNotFoundException ex)
{
    GD.PushError($"Manifest not found: {ex.Message}");
}
```

#### 2. JSON 解析失败

```csharp
loader.LoadingError += (errorMessage) =>
{
    if (errorMessage.Contains("JSON"))
    {
        GD.PushError("JSON 格式错误，请检查配置文件");
    }
};
```

#### 3. 验证失败

```csharp
var blocks = await loader.LoadAllBlocksAsync(manifestPath);

// 过滤掉无效方块
var validBlocks = blocks.Where(b => b.Validate()).ToList();

GD.Print($"Valid: {validBlocks.Count}/{blocks.Count}");
```

### 错误日志分析

加载器会自动输出详细日志：

```
=== Starting Block Loading ===
Loading manifest: res://Data/blocks/_manifest.json
Loading category: res://Data/blocks/nature
Category loaded: nature, Blocks: 15
Loading category: res://Data/blocks/ores
Category loaded: ores, Blocks: 8
Block loading complete. Total blocks: 23
```

错误日志示例：

```
[ERROR] Failed to load block res://Data/blocks/nature/stone.json: Unexpected character
[WARNING] Invalid block config: res://Data/blocks/ores/copper.json
[ERROR] 方块 'stone' 验证失败:
  - Name 不能为空
  - Hardness 不能为负数
```

---

## 性能优化

### 1. 异步加载

```csharp
// ✓ 推荐：异步加载不阻塞主线程
public async void LoadBlocksAsync()
{
    var blocks = await loader.LoadAllBlocksAsync(manifestPath);
    ProcessBlocks(blocks);
}

// ✗ 不推荐：同步加载会冻结 UI
public void LoadBlocksSync()
{
    var blocks = loader.LoadAllBlocksAsync(manifestPath).Result;
}
```

### 2. 进度反馈

```csharp
// 实时显示加载进度，避免用户以为卡死
loader.LoadingProgress += (current, total, message) =>
{
    progressBar.Value = (float)current / total;
    statusLabel.Text = $"{message} ({current}/{total})";
};
```

### 3. 分批处理

```csharp
public async Task LoadAndRegisterBlocks()
{
    var blocks = await loader.LoadAllBlocksAsync(manifestPath);
    
    // 分批注册，避免一次性处理大量数据
    const int batchSize = 50;
    for (int i = 0; i < blocks.Count; i += batchSize)
    {
        var batch = blocks.GetRange(i, Math.Min(batchSize, blocks.Count - i));
        RegisterBatch(batch);
        
        // 等待一帧，保持 UI 响应
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
    }
}
```

### 4. 缓存解析器

```csharp
// ✓ 推荐：复用解析器实例
private static ConfigParser _sharedParser = new();

public async Task<BlockData> LoadBlock(string path)
{
    return await _sharedParser.ParseBlockDataAsync(path, default);
}

// ✗ 不推荐：每次创建新实例
public async Task<BlockData> LoadBlockWrong(string path)
{
    var parser = new ConfigParser(); // 浪费资源
    return await parser.ParseBlockDataAsync(path, default);
}
```

---

## 调试技巧

### 1. 启用详细日志

```csharp
// 在 project.godot 中设置：
// debug/gdscript/verbose_logging=true

// 代码中输出详细信息
var blocks = await loader.LoadAllBlocksAsync(manifestPath);
foreach (var block in blocks)
{
    GD.Print($"[BLOCK] {block.Name}:");
    GD.Print($"  Display: {block.DisplayName}");
    GD.Print($"  Hardness: {block.Hardness}");
    GD.Print($"  Tool: {block.ToolRequired}");
}
```

### 2. 使用断点

```csharp
// 在 MapJsonToBlockData 中添加断点
private BlockData MapJsonToBlockData(BlockDataJson json)
{
    // <- 设置断点检查 JSON 数据
    var blockData = new BlockData { ... };
    // <- 设置断点检查映射结果
    return blockData;
}
```

### 3. 验证配置完整性

```csharp
public async Task DiagnoseConfiguration()
{
    var loader = new BlockDataLoader();
    AddChild(loader);
    
    GD.Print("=== Configuration Diagnosis ===");
    
    try
    {
        var blocks = await loader.LoadAllBlocksAsync(manifestPath);
        
        GD.Print($"✓ Total blocks loaded: {blocks.Count}");
        
        var withTextures = blocks.Count(b => !string.IsNullOrEmpty(b.TextureNorth));
        GD.Print($"✓ Blocks with textures: {withTextures}");
        
        var withStates = blocks.Count(b => b.StateDefinitions.Count > 0);
        GD.Print($"✓ Blocks with states: {withStates}");
        
        var byCategory = blocks.GroupBy(b => b.Category);
        foreach (var group in byCategory)
        {
            GD.Print($"  - {group.Key}: {group.Count()} blocks");
        }
    }
    catch (Exception ex)
    {
        GD.PrintErr($"✗ Diagnosis failed: {ex.Message}");
    }
}
```

---

## 总结

本系统提供了：

✅ **异步加载** - 不阻塞主线程  
✅ **进度反馈** - 实时显示加载状态  
✅ **错误处理** - 完善的异常捕获和日志  
✅ **灵活配置** - 支持多种纹理配置方式  
✅ **类型安全** - C# 强类型检查  
✅ **模组支持** - 可加载用户自定义方块  

下一步：学习如何将加载的 `BlockData` 注册到 `BlockRegistry` 并在游戏中使用！
