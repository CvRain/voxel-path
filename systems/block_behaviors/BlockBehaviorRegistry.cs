using System;
using System.Collections.Generic;
using Godot;

namespace VoxelPath.systems.block_behaviors;

/// <summary>
/// 方块行为注册表 - 管理方块 ID 到行为处理器的映射
/// 使用示例：
/// BlockBehaviorRegistry.RegisterBehavior(5, typeof(InformationBlockBehavior));
/// </summary>
public static class BlockBehaviorRegistry
{
    private static readonly Dictionary<int, Type> Behaviors = new();

    /// <summary>
    /// 注册方块行为
    /// </summary>
    /// <param name="blockId">方块 ID</param>
    /// <param name="behaviorType">行为类型（必须实现 IBlockInteractable）</param>
    /// <exception cref="ArgumentException">如果类型未实现接口</exception>
    public static void RegisterBehavior(int blockId, Type behaviorType)
    {
        if (!typeof(IBlockInteractable).IsAssignableFrom(behaviorType))
        {
            throw new ArgumentException(
                $"Type {behaviorType.Name} must implement IBlockInteractable interface",
                nameof(behaviorType));
        }

        if (Behaviors.ContainsKey(blockId))
        {
            GD.PushWarning($"Overriding existing behavior for block ID {blockId}");
        }

        Behaviors[blockId] = behaviorType;
        GD.Print($"[BlockBehaviorRegistry] Registered behavior '{behaviorType.Name}' for block ID {blockId}");
    }

    /// <summary>
    /// 获取指定方块的行为实例
    /// </summary>
    /// <param name="blockId">方块 ID</param>
    /// <returns>行为实例，如果未注册则返回 null</returns>
    public static IBlockInteractable GetBehavior(int blockId)
    {
        if (!Behaviors.TryGetValue(blockId, out var behaviorType))
        {
            return null;
        }

        try
        {
            return (IBlockInteractable)Activator.CreateInstance(behaviorType);
        }
        catch (Exception ex)
        {
            GD.PushError($"[BlockBehaviorRegistry] Failed to create instance of {behaviorType.Name}: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// 检查是否为指定方块注册了行为
    /// </summary>
    public static bool HasBehavior(int blockId)
    {
        return Behaviors.ContainsKey(blockId);
    }

    /// <summary>
    /// 移除方块行为注册
    /// </summary>
    public static bool UnregisterBehavior(int blockId)
    {
        return Behaviors.Remove(blockId);
    }

    /// <summary>
    /// 清空所有注册的行为
    /// </summary>
    public static void Clear()
    {
        Behaviors.Clear();
        GD.Print("[BlockBehaviorRegistry] Cleared all registered behaviors");
    }

    /// <summary>
    /// 获取已注册行为的数量
    /// </summary>
    public static int Count => Behaviors.Count;
}
