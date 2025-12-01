using System.Collections.Generic;
using Godot;
using VoxelPath.entities.player.scripts;
using VoxelPath.Scripts.Core;

namespace VoxelPath.systems;

/// <summary>
/// 世界交互管理器 - 作为玩家与世界交互的协调中心
/// 职责：
/// 1. 监听玩家事件（悬停、点击）
/// 2. 控制视觉反馈（BlockSelector）
/// 3. 执行实际的方块修改逻辑
/// 4. 管理笔刷大小
/// </summary>
public partial class WorldInteractionManager : Node
{
    [ExportGroup("Dependencies")]
    [Export] private Player _player;
    [Export] private BlockSelector _blockSelector;

    [ExportGroup("Settings")]
    [Export] private int _defaultBlockId = 1; // 默认放置的方块 ID（石头）

    private Node _world;

    public override void _Ready()
    {
        if (_player == null)
        {
            GD.PushError("Player not assigned in WorldInteractionManager.");
            return;
        }

        if (_blockSelector == null)
        {
            GD.PushError("BlockSelector not assigned in WorldInteractionManager.");
            return;
        }

        // 获取世界引用
        _world = GetTree().CurrentScene;

        // 订阅玩家事件
        _player.HoveredBlockChanged += OnHoveredBlockChanged;
        _player.HoveredBlockExited += OnHoveredBlockExited;
        _player.LeftClickBlock += OnLeftClickBlock;
        _player.RightClickBlock += OnRightClickBlock;
        _player.BrushSizeChanged += OnBrushSizeChanged;

        // 初始化 BlockSelector
        _blockSelector.SetBrushSize(_player.BrushSize);
        _blockSelector.Hide();
    }

    public override void _ExitTree()
    {
        // 取消订阅防止内存泄漏
        if (_player != null)
        {
            _player.HoveredBlockChanged -= OnHoveredBlockChanged;
            _player.HoveredBlockExited -= OnHoveredBlockExited;
            _player.LeftClickBlock -= OnLeftClickBlock;
            _player.RightClickBlock -= OnRightClickBlock;
            _player.BrushSizeChanged -= OnBrushSizeChanged;
        }
    }

    #region 事件处理

    private void OnHoveredBlockChanged(Vector3I blockPosition, Vector3 blockNormal)
    {
        // 可以在这里添加基于方块类型的特殊逻辑
        // 例如：获取方块 ID，调用对应的行为处理器

        // 默认行为：显示高亮框
        _blockSelector.UpdateSelection(blockPosition, blockNormal);
        _blockSelector.Show();
    }

    private void OnHoveredBlockExited()
    {
        _blockSelector.Hide();
    }

    private void OnLeftClickBlock(Vector3I blockPosition, Vector3 blockNormal)
    {
        // 左键：破坏方块
        DestroyVoxels(blockPosition);
    }

    private void OnRightClickBlock(Vector3I blockPosition, Vector3 blockNormal)
    {
        // 右键：放置方块
        PlaceVoxels(blockPosition, blockNormal);
    }

    private void OnBrushSizeChanged(int newSize)
    {
        _blockSelector.SetBrushSize(newSize);
        GD.Print($"[WorldInteractionManager] Brush size updated to: {newSize}");
    }

    #endregion

    #region 方块操作

    private void DestroyVoxels(Vector3I centerGridPos)
    {
        var targetVoxels = _player.GetVoxelBrush(centerGridPos);
        BatchModifyVoxels(targetVoxels, Constants.AirBlockId);
    }

    private void PlaceVoxels(Vector3I blockPosition, Vector3 blockNormal)
    {
        // 计算放置位置（沿法线向外偏移）
        var placePosWorld = (Vector3)blockPosition * Constants.VoxelSize + (blockNormal * Constants.VoxelSize * 0.5f);
        var centerGridPosPlace = BlockSelector.WorldToVoxelIndex(placePosWorld, Constants.VoxelSize);

        var placeVoxels = _player.GetVoxelBrush(centerGridPosPlace, blockNormal);
        BatchModifyVoxels(placeVoxels, _defaultBlockId);
    }

    /// <summary>
    /// 批量修改体素并更新网格
    /// </summary>
    private void BatchModifyVoxels(List<Vector3I> voxelPositions, int blockId)
    {
        if (_world == null)
        {
            GD.PushWarning("[WorldInteractionManager] World reference is null");
            return;
        }

        // 检查世界场景是否有必要的方法
        if (!_world.HasMethod("set_voxel_at_raw"))
        {
            GD.PushWarning("[WorldInteractionManager] World scene does not have 'set_voxel_at_raw' method. This is a test scene without voxel world.");
            return;
        }

        var maxSections = Mathf.CeilToInt(Constants.VoxelMaxHeight / (float)Constants.ChunkSectionSize);
        var changes = new Godot.Collections.Dictionary(); // Vector2i -> Dictionary<int, bool>

        foreach (var pos in voxelPositions)
        {
            // 设置体素
            _world.Call("set_voxel_at_raw", pos, blockId);

            // 记录需要更新的区块和 Section
            var cx = Mathf.FloorToInt(pos.X / (float)Constants.ChunkSize);
            var cz = Mathf.FloorToInt(pos.Z / (float)Constants.ChunkSize);
            var chunkPos = new Vector2I(cx, cz);

            if (!changes.ContainsKey(chunkPos))
            {
                changes[chunkPos] = new Godot.Collections.Dictionary();
            }

            var chunkChanges = (Godot.Collections.Dictionary)changes[chunkPos];

            var y = pos.Y;
            var sectionIdx = Mathf.FloorToInt(y / (float)Constants.ChunkSectionSize);
            chunkChanges[sectionIdx] = true;

            // 边界情况：可能影响相邻 Section
            var localY = y % Constants.ChunkSectionSize;
            switch (localY)
            {
                case 0 when sectionIdx > 0:
                    chunkChanges[sectionIdx - 1] = true;
                    break;
                case Constants.ChunkSectionSize - 1 when sectionIdx < maxSections - 1:
                    chunkChanges[sectionIdx + 1] = true;
                    break;
            }
        }

        // 更新区块网格
        UpdateChunks(changes);
    }

    private void UpdateChunks(Godot.Collections.Dictionary changes)
    {
        if (_world == null) return;

        if (_world.HasMethod("update_chunks_sections"))
        {
            var finalChanges = new Godot.Collections.Dictionary();
            foreach (var key in changes.Keys)
            {
                var chunkPos = (Vector2I)key;
                var sectionsDict = (Godot.Collections.Dictionary)changes[chunkPos];
                var sectionsArray = new Godot.Collections.Array();
                foreach (var sectionKey in sectionsDict.Keys) sectionsArray.Add(sectionKey);
                finalChanges[chunkPos] = sectionsArray;
            }

            _world.Call("update_chunks_sections", finalChanges);
        }
        else if (_world.HasMethod("update_chunks"))
        {
            var chunksArray = new Godot.Collections.Array();
            foreach (var key in changes.Keys) chunksArray.Add(key);
            _world.Call("update_chunks", chunksArray);
        }
    }

    #endregion
}

