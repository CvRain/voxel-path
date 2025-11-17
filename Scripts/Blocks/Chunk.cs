using Godot;

namespace VoxelPath.Scripts.Blocks;

public class Chunk
{
    public const int SizeX = 64;
    public const int SizeY = 64;
    public const int SizeZ = 64;

    private readonly BlockType[,,] _blocks = new BlockType[SizeX, SizeY, SizeZ];
    public Vector3I ChunkCoord;

    public bool DirtyMesh = true;

    public Chunk(Vector3I coord)
    {
        ChunkCoord = coord;
        // 默认填充空气即可
        for (int x = 0; x < SizeX; x++)
        {
            for (int y = 0; y < SizeY; y++)
            {
                for (int z = 0; z < SizeZ; z++)
                {
                    _blocks[x, y, z] = BlockType.Air;
                }
            }
        }
    }

    public bool InBounds(int x, int y, int z)
    {
        return x >= 0 && x < SizeX && y >= 0 && y < SizeY && z >= 0 && z < SizeZ;
    }

    public BlockType Get(int x, int y, int z)
    {
        if (!InBounds(x, y, z)) return BlockType.Air;
        return _blocks[x, y, z];
    }

    public bool Set(int x, int y, int z, BlockType type)
    {
        if (!InBounds(x, y, z)) return false;
        if (_blocks[x, y, z] == type) return false;
        _blocks[x, y, z] = type;
        DirtyMesh = true;
        return true;
    }
}