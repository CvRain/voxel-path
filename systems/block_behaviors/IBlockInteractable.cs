using Godot;

namespace VoxelPath.systems.block_behaviors;

/// <summary>
/// 方块交互行为接口
/// 实现此接口可以为特定方块类型添加自定义交互逻辑
/// </summary>
public interface IBlockInteractable
{
    /// <summary>
    /// 当玩家准星指向该方块时调用
    /// </summary>
    /// <param name="position">方块的网格坐标</param>
    /// <param name="normal">碰撞面的法线方向</param>
    void OnPlayerLookAt(Vector3I position, Vector3 normal);

    /// <summary>
    /// 当玩家准星离开该方块时调用
    /// </summary>
    void OnPlayerLookAway();

    /// <summary>
    /// 当玩家左键点击该方块时调用
    /// </summary>
    /// <param name="position">方块的网格坐标</param>
    /// <param name="normal">碰撞面的法线方向</param>
    void OnLeftClick(Vector3I position, Vector3 normal);

    /// <summary>
    /// 当玩家右键点击该方块时调用
    /// </summary>
    /// <param name="position">方块的网格坐标</param>
    /// <param name="normal">碰撞面的法线方向</param>
    void OnRightClick(Vector3I position, Vector3 normal);
}
