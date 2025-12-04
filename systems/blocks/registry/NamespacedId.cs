using System;
using System.Text.RegularExpressions;

namespace VoxelPath.systems.blocks.registry;

/// <summary>
/// 命名空间 ID - 用于唯一标识方块，支持模组扩展
/// 格式：namespace:name
/// 示例：
/// - voxelpath:stone (内置方块)
/// - techmod:copper_ore (科技模组的铜矿)
/// - magicmod:copper_ore (魔法模组的铜矿)
/// </summary>
public readonly partial struct NamespacedId : IEquatable<NamespacedId>
{
    private static readonly Regex ValidPattern = MyRegex();

    /// <summary>默认命名空间（游戏内置内容）</summary>
    public const string DefaultNamespace = "voxelpath";

    /// <summary>命名空间（模组 ID）</summary>
    public string Namespace { get; }

    /// <summary>路径（方块名称，可包含子路径）</summary>
    public string Path { get; }

    /// <summary>完整 ID 字符串</summary>
    public string FullId => $"{Namespace}:{Path}";

    #region 构造函数

    /// <summary>
    /// 从完整 ID 字符串创建
    /// </summary>
    /// <param name="fullId">格式: "namespace:path" 或 "path"(使用默认命名空间)</param>
    public NamespacedId(string fullId)
    {
        if (string.IsNullOrWhiteSpace(fullId))
            throw new ArgumentException("ID 不能为空", nameof(fullId));

        fullId = fullId.ToLowerInvariant().Trim();

        // 如果没有冒号，使用默认命名空间
        if (!fullId.Contains(':'))
        {
            Namespace = DefaultNamespace;
            Path = fullId;
        }
        else
        {
            var parts = fullId.Split(':', 2);
            Namespace = parts[0];
            Path = parts[1];
        }

        // 验证格式
        if (!ValidPattern.IsMatch(FullId))
        {
            throw new ArgumentException(
                $"ID 格式无效: '{fullId}'. 必须匹配模式: namespace:path (仅允许小写字母、数字、下划线和斜杠)",
                nameof(fullId)
            );
        }
    }

    /// <summary>
    /// 从命名空间和路径创建
    /// </summary>
    public NamespacedId(string @namespace, string path)
    {
        if (string.IsNullOrWhiteSpace(@namespace))
            throw new ArgumentException("命名空间不能为空", nameof(@namespace));

        if (string.IsNullOrWhiteSpace(path))
            throw new ArgumentException("路径不能为空", nameof(path));

        Namespace = @namespace.ToLowerInvariant().Trim();
        Path = path.ToLowerInvariant().Trim();

        if (!ValidPattern.IsMatch(FullId))
        {
            throw new ArgumentException(
                $"ID 格式无效: '{FullId}'. 必须匹配模式: namespace:path",
                nameof(@namespace)
            );
        }
    }

    #endregion

    #region 相等性比较

    public bool Equals(NamespacedId other)
    {
        return Namespace == other.Namespace && Path == other.Path;
    }

    public override bool Equals(object obj)
    {
        return obj is NamespacedId other && Equals(other);
    }

    public override int GetHashCode()
    {
        return HashCode.Combine(Namespace, Path);
    }

    public static bool operator ==(NamespacedId left, NamespacedId right)
    {
        return left.Equals(right);
    }

    public static bool operator !=(NamespacedId left, NamespacedId right)
    {
        return !left.Equals(right);
    }

    #endregion

    #region 转换和工具方法

    /// <summary>
    /// 隐式转换为字符串
    /// </summary>
    public static implicit operator string(NamespacedId id) => id.FullId;

    /// <summary>
    /// 显式从字符串转换
    /// </summary>
    public static explicit operator NamespacedId(string id) => new(id);

    /// <summary>
    /// 尝试解析字符串为 NamespacedId
    /// </summary>
    public static bool TryParse(string input, out NamespacedId result)
    {
        try
        {
            result = new NamespacedId(input);
            return true;
        }
        catch
        {
            result = default;
            return false;
        }
    }

    public override string ToString() => FullId;

    #endregion

    #region 常用内置 ID（可选，方便使用）

    public static NamespacedId Air => new(DefaultNamespace, "air");
    public static NamespacedId Stone => new(DefaultNamespace, "stone");
    public static NamespacedId Dirt => new(DefaultNamespace, "dirt");

    [GeneratedRegex(@"^[a-z0-9_]+:[a-z0-9_/]+$", RegexOptions.Compiled)]
    private static partial Regex MyRegex();

    #endregion
}
