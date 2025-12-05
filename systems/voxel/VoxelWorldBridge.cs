using Godot;
using VoxelPath.systems.blocks.registry;
using VoxelPath.systems.blocks.data;

namespace VoxelPath.systems.voxel;

/// <summary>
/// C# 和 GDScript VoxelWorld 之间的桥接器
/// 允许 C# 代码与 godot_voxel 交互
/// </summary>
public partial class VoxelWorldBridge : Node
{
    [Signal]
    public delegate void BlockPlacedEventHandler(Vector3I position, int blockId);

    [Signal]
    public delegate void BlockBrokenEventHandler(Vector3I position);

    private Node _voxelWorld;
    private BlockRegistry _blockRegistry;

    public override void _Ready()
    {
        GD.Print("[VoxelWorldBridge] C# <-> GDScript bridge ready");
    }

    public void ConnectToVoxelWorld(Node voxelWorldNode)
    {
        _voxelWorld = voxelWorldNode;
        GD.Print($"[VoxelWorldBridge] Connected to: {voxelWorldNode.Name}");
    }

    public void SetBlockRegistry(BlockRegistry registry)
    {
        _blockRegistry = registry;
        GD.Print($"[VoxelWorldBridge] BlockRegistry: {registry.Count} blocks");
    }

    public int GetVoxel(Vector3I position)
    {
        if (_voxelWorld == null) return 0;
        var result = _voxelWorld.Call("get_voxel", position);
        return result.As<int>();
    }

    public void SetVoxel(Vector3I position, int voxelId)
    {
        if (_voxelWorld == null) return;
        _voxelWorld.Call("set_voxel", position, voxelId);
        EmitSignal(SignalName.BlockPlaced, position, voxelId);
    }

    public void PlaceBlock(Vector3I position, NamespacedId blockId)
    {
        if (_blockRegistry == null) return;
        var numericId = _blockRegistry.GetNumericId(blockId);
        if (numericId == -1) return;
        SetVoxel(position, numericId);
    }

    public BlockData GetBlockData(Vector3I position)
    {
        if (_blockRegistry == null) return null;
        var numericId = GetVoxel(position);
        return _blockRegistry.GetById(numericId);
    }
}
