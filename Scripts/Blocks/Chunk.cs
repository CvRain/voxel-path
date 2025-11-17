using Godot;

namespace VoxelPath.Scripts.Blocks;

public class Chunk
{
    public const int SizeX = 64;
    public const int SizeY = 64;
    public const int SizeZ = 64;

    private readonly MacroBlockData[,,] _blocks = new MacroBlockData[SizeX, SizeY, SizeZ];
    public Vector3I ChunkCoord;

    public bool DirtyMesh = true;

    public Chunk(Vector3I coord)
    {
        ChunkCoord = coord;
        // 初始化：简单地在 y==0 做一层 Dirt，其它空气
        for (int x = 0; x < SizeX; x++)
        {
            for (int y = 0; y < SizeY; y++)
            {
                for (int z = 0; z < SizeZ; z++)
                {
                    ushort id = (ushort)(y == 0 ? BlockType.Dirt : BlockType.Air);
                    _blocks[x, y, z] = new MacroBlockData(id);
                }
            }
        }
    }

    public MacroBlockData Get(int x, int y, int z)
    {
        if (x < 0 || y < 0 || z < 0 || x >= SizeX || y >= SizeY || z >= SizeZ) return null;
        return _blocks[x, y, z];
    }

    public void Set(int x, int y, int z, BlockType type)
    {
        if (x < 0 || y < 0 || z < 0 || x >= SizeX || y >= SizeY || z >= SizeZ) return;
        _blocks[x, y, z].BlockId = (ushort)type;
        _blocks[x, y, z].Micro = null;
        DirtyMesh = true;
    }

    public void Subdivide(int x, int y, int z)
    {
        var b = Get(x, y, z);
        if (b == null) return;
        b.Subdivide();
        DirtyMesh = true;
    }

    public void SetMicro(int x, int y, int z, int mx, int my, int mz, BlockType type)
    {
        var b = Get(x, y, z);
        if (b == null) return;
        if (!b.IsSubdivided) b.Subdivide();
        b.Micro.Set(mx, my, mz, (byte)type);
        b.TryCollapse();
        DirtyMesh = true;
    }

    public void RemoveMicro(int x, int y, int z, int mx, int my, int mz)
    {
        var b = Get(x, y, z);
        if (b == null || !b.IsSubdivided) return;
        b.Micro.Remove(mx, my, mz);
        if (b.Micro.Occupancy == 0UL)
        {
            b.BlockId = (ushort)BlockType.Air;
            b.Micro = null;
        }
        else
        {
            b.TryCollapse();
        }

        DirtyMesh = true;
    }
}