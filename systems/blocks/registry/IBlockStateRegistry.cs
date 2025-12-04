using System.Collections.Generic;
using VoxelPath.systems.blocks.data;

namespace VoxelPath.systems.blocks.registry;

/// <summary>
/// 方块状态注册表接口
/// 职责：
/// 1. 生成方块的所有可能状态（笛卡尔积）
/// 2. 管理 State ID 映射
/// 3. 提供快速状态查找
/// 4. 支持状态序列化
/// </summary>
public interface IBlockStateRegistry
{
    #region 注册方法

    /// <summary>
    /// 为方块生成并注册所有可能的状态
    /// </summary>
    /// <param name="blockId">方块的数字 ID</param>
    /// <param name="blockData">方块数据（包含状态定义）</param>
    /// <returns>生成的状态数量</returns>
    int RegisterBlockStates(int blockId, BlockData blockData);

    /// <summary>
    /// 批量注册多个方块的状态
    /// </summary>
    /// <param name="blocks">方块字典（BlockId → BlockData）</param>
    /// <returns>总共生成的状态数量</returns>
    int RegisterAllBlockStates(Dictionary<int, BlockData> blocks);

    #endregion

    #region 查询方法

    /// <summary>
    /// 通过 State ID 获取方块状态
    /// </summary>
    /// <param name="stateId">状态 ID</param>
    /// <returns>方块状态，不存在返回 null</returns>
    BlockState GetStateById(int stateId);

    /// <summary>
    /// 通过方块 ID 和属性获取状态 ID
    /// </summary>
    /// <param name="blockId">方块 ID</param>
    /// <param name="properties">状态属性字典</param>
    /// <returns>状态 ID，不存在返回 -1</returns>
    int GetStateId(int blockId, Dictionary<string, object> properties);

    /// <summary>
    /// 获取方块的默认状态 ID
    /// </summary>
    /// <param name="blockId">方块 ID</param>
    /// <returns>默认状态 ID</returns>
    int GetDefaultStateId(int blockId);

    /// <summary>
    /// 获取方块的默认状态
    /// </summary>
    /// <param name="blockId">方块 ID</param>
    /// <returns>默认状态</returns>
    BlockState GetDefaultState(int blockId);

    /// <summary>
    /// 获取方块的所有可能状态
    /// </summary>
    /// <param name="blockId">方块 ID</param>
    /// <returns>状态列表</returns>
    IReadOnlyList<BlockState> GetAllStatesForBlock(int blockId);

    #endregion

    #region 状态修改

    /// <summary>
    /// 修改状态的单个属性
    /// </summary>
    /// <param name="currentStateId">当前状态 ID</param>
    /// <param name="propertyName">属性名</param>
    /// <param name="newValue">新值</param>
    /// <returns>新状态 ID，失败返回 -1</returns>
    int SetProperty(int currentStateId, string propertyName, object newValue);

    /// <summary>
    /// 循环切换属性值（用于交互）
    /// 例如：facing: north → east → south → west → north
    /// </summary>
    /// <param name="currentStateId">当前状态 ID</param>
    /// <param name="propertyName">属性名</param>
    /// <returns>新状态 ID</returns>
    int CycleProperty(int currentStateId, string propertyName);

    #endregion

    #region 统计信息

    /// <summary>
    /// 已注册的状态总数
    /// </summary>
    int TotalStateCount { get; }

    /// <summary>
    /// 已注册方块数量
    /// </summary>
    int RegisteredBlockCount { get; }

    #endregion

    #region 调试工具

    /// <summary>
    /// 打印所有已注册状态的信息
    /// </summary>
    void PrintStates();

    /// <summary>
    /// 验证状态注册表完整性
    /// </summary>
    bool ValidateIntegrity();

    #endregion
}
