using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using Godot;
using VoxelPath.systems.blocks.data;
using VoxelPath.systems.world_settings;

namespace VoxelPath.systems.blocks.loaders;

/// <summary>
/// 配置解析器 - 负责解析 JSON 配置文件并映射到 C# 对象
/// </summary>
public class ConfigParser : IDisposable
{
    private readonly JsonSerializerOptions _jsonOptions;

    public ConfigParser()
    {
        _jsonOptions = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
            Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) }
        };
    }

    #region Manifest 解析

    /// <summary>
    /// 解析 Manifest 配置文件
    /// </summary>
    public async Task<ManifestConfig> ParseManifestAsync(string path, CancellationToken token)
    {
        var fullPath = ProjectSettings.GlobalizePath(path);
        if (!File.Exists(fullPath))
        {
            throw new FileNotFoundException($"Manifest not found: {fullPath}");
        }

        using var stream = File.OpenRead(fullPath);
        return await JsonSerializer.DeserializeAsync<ManifestConfig>(stream, _jsonOptions, token);
    }

    #endregion

    #region Category 解析

    /// <summary>
    /// 解析分类配置文件
    /// </summary>
    public async Task<CategoryBlocksConfig> ParseCategoryConfigAsync(string path, CancellationToken token)
    {
        var fullPath = ProjectSettings.GlobalizePath(path);
        if (!File.Exists(fullPath))
        {
            throw new FileNotFoundException($"Category config not found: {fullPath}");
        }

        using var stream = File.OpenRead(fullPath);
        return await JsonSerializer.DeserializeAsync<CategoryBlocksConfig>(stream, _jsonOptions, token);
    }

    #endregion

    #region BlockData 解析

    /// <summary>
    /// 解析方块数据配置文件
    /// </summary>
    public async Task<BlockData> ParseBlockDataAsync(string path, CancellationToken token)
    {
        var fullPath = ProjectSettings.GlobalizePath(path);
        if (!File.Exists(fullPath))
        {
            throw new FileNotFoundException($"Block config not found: {fullPath}");
        }

        using var stream = File.OpenRead(fullPath);
        var json = await JsonSerializer.DeserializeAsync<BlockDataJson>(stream, _jsonOptions, token);

        return MapJsonToBlockData(json);
    }

    /// <summary>
    /// 同步解析方块数据（从 JSON 字符串）
    /// 用于 BlockManager 的同步加载流程
    /// </summary>
    /// <param name="jsonText">JSON 文本内容</param>
    /// <returns>解析的 BlockData</returns>
    public BlockData ParseBlockDataFromJson(string jsonText)
    {
        var json = JsonSerializer.Deserialize<BlockDataJson>(jsonText, _jsonOptions);
        if (json == null)
        {
            throw new InvalidOperationException("Failed to deserialize block data JSON");
        }

        return MapJsonToBlockData(json);
    }

    /// <summary>
    /// 将 JSON 数据映射到 BlockData 对象
    /// </summary>
    private BlockData MapJsonToBlockData(BlockDataJson json)
    {
        var blockData = new BlockData
        {
            // 基本信息
            Name = json.Name,
            DisplayName = json.DisplayName,
            Description = json.Description,
            Category = json.Category,

            // 纹理路径 - 优先使用具体方向，如果为空则使用 all
            TextureTop = !string.IsNullOrEmpty(json.Textures?.Top) ? json.Textures.Top : json.Textures?.All ?? string.Empty,
            TextureBottom = !string.IsNullOrEmpty(json.Textures?.Bottom) ? json.Textures.Bottom : json.Textures?.All ?? string.Empty,
            TextureNorth = !string.IsNullOrEmpty(json.Textures?.North) ? json.Textures.North : json.Textures?.All ?? string.Empty,
            TextureSouth = !string.IsNullOrEmpty(json.Textures?.South) ? json.Textures.South : json.Textures?.All ?? string.Empty,
            TextureEast = !string.IsNullOrEmpty(json.Textures?.East) ? json.Textures.East : json.Textures?.All ?? string.Empty,
            TextureWest = !string.IsNullOrEmpty(json.Textures?.West) ? json.Textures.West : json.Textures?.All ?? string.Empty,

            // 法线贴图(如果有)
            NormalTop = json.Normals?.Top ?? json.Normals?.All ?? string.Empty,
            NormalBottom = json.Normals?.Bottom ?? json.Normals?.All ?? string.Empty,
            NormalNorth = json.Normals?.North ?? json.Normals?.All ?? string.Empty,
            NormalSouth = json.Normals?.South ?? json.Normals?.All ?? string.Empty,
            NormalEast = json.Normals?.East ?? json.Normals?.All ?? string.Empty,
            NormalWest = json.Normals?.West ?? json.Normals?.All ?? string.Empty,

            // 视觉效果
            IsTransparent = json.IsTransparent,
            Opacity = json.Opacity,
            IsEmissive = json.IsEmissive,
            EmissionStrength = json.EmissionStrength,

            // 物理属性
            Hardness = json.Hardness,
            Resistance = json.Resistance,
            HasCollision = json.HasCollision,
            IsSolid = json.IsSolid,

            // 交互属性
            CanPlace = json.CanPlace,
            CanBreak = json.CanBreak,
            ToolRequiredInt = ParseToolType(json.ToolRequired),
            MineLevel = json.MineLevel,
            BaseMineTime = json.BaseMineTime,

            // 方块状态
            StateDefinitionsJson = json.StateDefinitionsJson ?? "{}",
            DefaultStateJson = json.DefaultStateJson ?? "{}",

            // 自定义属性
            CustomPropertiesJson = json.CustomPropertiesJson ?? "{}"
        };

        return blockData;
    }

    /// <summary>
    /// 解析工具类型字符串到 int
    /// </summary>
    private int ParseToolType(string toolType)
    {
        if (string.IsNullOrEmpty(toolType))
            return -1;

        return toolType.ToLower() switch
        {
            "none" => -1,
            "axe" => 0,
            "pickaxe" => 1,
            "shovel" => 2,
            "hammer" => 3,
            "scissors" => 4,
            "brush" => 5,
            "scythe" => 6,
            "hoe" => 7,
            _ => -1
        };
    }

    #endregion

    #region 辅助方法

    /// <summary>
    /// 解析枚举值(非空)
    /// </summary>
    private T ParseEnum<T>(string value, T defaultValue) where T : struct, Enum
    {
        if (string.IsNullOrEmpty(value))
            return defaultValue;

        return Enum.TryParse<T>(value, true, out var result) ? result : defaultValue;
    }

    /// <summary>
    /// 解析可空枚举值
    /// </summary>
    private T? ParseNullableEnum<T>(string value) where T : struct, Enum
    {
        if (string.IsNullOrEmpty(value))
            return null;

        return Enum.TryParse<T>(value, true, out var result) ? result : null;
    }

    public void Dispose()
    {
        // 当前无需释放资源，保留接口以便未来扩展
    }

    #endregion
}

#region 配置数据结构

/// <summary>
/// Manifest 配置结构
/// </summary>
public class ManifestConfig
{
    [JsonPropertyName("format_version")]
    public string FormatVersion { get; set; } = "1.0";

    [JsonPropertyName("categories")]
    public List<CategoryConfig> Categories { get; set; } = new();

    [JsonPropertyName("modded_categories")]
    public List<CategoryConfig> ModdedCategories { get; set; } = new();

    /// <summary>
    /// 获取所有分类(包括 mod)
    /// </summary>
    public List<CategoryConfig> GetCategories()
    {
        var all = new List<CategoryConfig>(Categories);
        all.AddRange(ModdedCategories);
        return all;
    }
}

/// <summary>
/// 分类配置结构
/// </summary>
public class CategoryConfig
{
    [JsonPropertyName("path")]
    public string Path { get; set; } = string.Empty;

    [JsonPropertyName("config")]
    public string Config { get; set; } = "config.json";

    [JsonPropertyName("enabled")]
    public bool Enabled { get; set; } = true;

    [JsonPropertyName("priority")]
    public int Priority { get; set; } = 100;

    [JsonPropertyName("description")]
    public string Description { get; set; } = string.Empty;
}

/// <summary>
/// 分类方块列表配置
/// </summary>
public class CategoryBlocksConfig
{
    [JsonPropertyName("category")]
    public string Category { get; set; } = string.Empty;

    [JsonPropertyName("blocks")]
    public List<string> Blocks { get; set; } = new();
}

/// <summary>
/// BlockData JSON 映射结构
/// </summary>
public class BlockDataJson
{
    // 基本信息
    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("display_name")]
    public string DisplayName { get; set; } = string.Empty;

    [JsonPropertyName("description")]
    public string Description { get; set; } = string.Empty;

    [JsonPropertyName("category")]
    public string Category { get; set; } = "misc";

    // 纹理(嵌套结构)
    [JsonPropertyName("textures")]
    public TexturePathsJson Textures { get; set; }

    [JsonPropertyName("normals")]
    public TexturePathsJson Normals { get; set; }

    // 视觉效果
    [JsonPropertyName("is_transparent")]
    public bool IsTransparent { get; set; } = false;

    [JsonPropertyName("opacity")]
    public float Opacity { get; set; } = 1.0f;

    [JsonPropertyName("is_emissive")]
    public bool IsEmissive { get; set; } = false;

    [JsonPropertyName("emission_strength")]
    public float EmissionStrength { get; set; } = 1.0f;

    // 物理属性
    [JsonPropertyName("hardness")]
    public float Hardness { get; set; } = 1.0f;

    [JsonPropertyName("resistance")]
    public float Resistance { get; set; } = 1.0f;

    [JsonPropertyName("has_collision")]
    public bool HasCollision { get; set; } = true;

    [JsonPropertyName("is_solid")]
    public bool IsSolid { get; set; } = true;

    // 交互属性
    [JsonPropertyName("can_place")]
    public bool CanPlace { get; set; } = true;

    [JsonPropertyName("can_break")]
    public bool CanBreak { get; set; } = true;

    [JsonPropertyName("tool_required")]
    public string ToolRequired { get; set; } = null;

    [JsonPropertyName("mine_level")]
    public int MineLevel { get; set; } = 0;

    [JsonPropertyName("base_mine_time")]
    public float BaseMineTime { get; set; } = 1.0f;

    // 方块状态
    [JsonPropertyName("state_definitions")]
    public string StateDefinitionsJson { get; set; } = "{}";

    [JsonPropertyName("default_state")]
    public string DefaultStateJson { get; set; } = "{}";

    // 自定义属性
    [JsonPropertyName("custom_properties")]
    public string CustomPropertiesJson { get; set; } = "{}";
}

/// <summary>
/// 纹理路径 JSON 结构
/// </summary>
public class TexturePathsJson
{
    // 单独面纹理
    [JsonPropertyName("top")]
    public string Top { get; set; } = string.Empty;

    [JsonPropertyName("bottom")]
    public string Bottom { get; set; } = string.Empty;

    [JsonPropertyName("north")]
    public string North { get; set; } = string.Empty;

    [JsonPropertyName("south")]
    public string South { get; set; } = string.Empty;

    [JsonPropertyName("east")]
    public string East { get; set; } = string.Empty;

    [JsonPropertyName("west")]
    public string West { get; set; } = string.Empty;

    // 所有面使用同一纹理
    [JsonPropertyName("all")]
    public string All { get; set; } = string.Empty;
}

#endregion
