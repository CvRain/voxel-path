using System.Collections.Generic;
using VoxelPath.systems.blocks.data;

namespace VoxelPath.systems.blocks.registry;

/// <summary>
/// 方块注册表接口
/// 职责：
/// 1. 注册方块数据（分配数字 ID）
/// 2. 通过 NamespacedId 或数字 ID 查询方块
/// 3. 管理命名空间（防止模组冲突）
/// 4. 持久化 ID 映射（保存/加载）
/// </summary>
public interface IBlockRegistry
{
    #region 注册方法

    /// <summary>
    /// 注册单个方块
    /// </summary>
    /// <param name="namespacedId">命名空间 ID（如 "voxelpath:stone"）</param>
    /// <param name="blockData">方块数据</param>
    /// <returns>分配的数字 ID，失败返回 -1</returns>
    int Register(NamespacedId namespacedId, BlockData blockData);

    /// <summary>
    /// 批量注册方块
    /// </summary>
    /// <param name="blocks">方块字典（NamespacedId → BlockData）</param>
    /// <returns>成功注册的数量</returns>
    int RegisterAll(Dictionary<NamespacedId, BlockData> blocks);

    /// <summary>
    /// 注销方块（谨慎使用，可能破坏存档兼容性）
    /// </summary>
    bool Unregister(NamespacedId namespacedId);

    #endregion

    #region 查询方法

    /// <summary>
    /// 通过数字 ID 获取方块（最快）
    /// </summary>
    BlockData GetById(int numericId);

    /// <summary>
    /// 通过命名空间 ID 获取方块
    /// </summary>
    BlockData GetByNamespacedId(NamespacedId namespacedId);

    /// <summary>
    /// 通过字符串 ID 获取方块（会自动解析命名空间）
    /// </summary>
    BlockData GetByString(string id);

    /// <summary>
    /// 获取命名空间 ID 对应的数字 ID
    /// </summary>
    int GetNumericId(NamespacedId namespacedId);

    /// <summary>
    /// 获取数字 ID 对应的命名空间 ID
    /// </summary>
    NamespacedId GetNamespacedId(int numericId);

    #endregion

    #region 检查方法

    /// <summary>
    /// 检查方块是否已注册
    /// </summary>
    bool Contains(NamespacedId namespacedId);

    /// <summary>
    /// 检查数字 ID 是否有效
    /// </summary>
    bool IsValidId(int numericId);

    /// <summary>
    /// 获取已注册的命名空间列表（用于检测模组）
    /// </summary>
    IReadOnlyList<string> GetNamespaces();

    /// <summary>
    /// 获取指定命名空间下的所有方块
    /// </summary>
    IReadOnlyList<BlockData> GetBlocksInNamespace(string @namespace);

    #endregion

    #region 统计信息

    /// <summary>
    /// 已注册方块总数
    /// </summary>
    int Count { get; }

    /// <summary>
    /// 下一个可用的数字 ID
    /// </summary>
    int NextId { get; }

    #endregion

    #region 持久化

    /// <summary>
    /// 保存 ID 映射到 JSON 文件
    /// </summary>
    void SaveMappings(string path);

    /// <summary>
    /// 从 JSON 文件加载 ID 映射
    /// </summary>
    void LoadMappings(string path);

    #endregion

    #region 调试工具

    /// <summary>
    /// 打印所有已注册方块的信息
    /// </summary>
    void PrintRegistry();

    /// <summary>
    /// 验证注册表完整性
    /// </summary>
    bool ValidateIntegrity();

    #endregion
}