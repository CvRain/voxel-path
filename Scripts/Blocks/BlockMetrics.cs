using Godot;

namespace VoxelPath.Scripts.Blocks;

/// <summary>
/// Centralizes block scale definitions so world generation, meshing, and tools stay in sync.
/// </summary>
public static class BlockMetrics
{
    /// <summary>
    /// Physical size (in meters) of a single standard (macro) block.
    /// </summary>
    public const float StandardBlockSize = 0.25f;

    /// <summary>
    /// Each placement cluster spans this many base blocks per axis (1m volume).
    /// </summary>
    public const int BlocksPerMeter = 4;

    public const int ClusterBlockLength = BlocksPerMeter;

    /// <summary>
    /// Default placement cluster size (single micro block, 0.25m cube).
    /// </summary>
    public const int DefaultClusterSize = 1;

    /// <summary>
    /// Alternate placement cluster size for coarse editing (1m cube when sprinting).
    /// </summary>
    public const int LargeClusterSize = BlocksPerMeter;

    public const float MicroBlockSize = StandardBlockSize;

    public static float ToWorld(float gridUnits) => gridUnits * StandardBlockSize;

    public static Vector3 ToWorld(Vector3 grid) => grid * StandardBlockSize;

    public static int ToBlockCount(float meters) => Mathf.RoundToInt(meters / StandardBlockSize);

    public static Vector3I ClampToChunk(Vector3I pos)
    {
        return new Vector3I(
            Mathf.Clamp(pos.X, 0, Chunk.SizeX - 1),
            Mathf.Clamp(pos.Y, 0, Chunk.SizeY - 1),
            Mathf.Clamp(pos.Z, 0, Chunk.SizeZ - 1)
        );
    }

    public static Vector3I WorldToBlockCoords(Vector3 worldPosition)
    {
        return new Vector3I(
            Mathf.FloorToInt(worldPosition.X / StandardBlockSize),
            Mathf.FloorToInt(worldPosition.Y / StandardBlockSize),
            Mathf.FloorToInt(worldPosition.Z / StandardBlockSize)
        );
    }

    public static int SnapValueToGrid(int value, int gridSize)
    {
        if (gridSize <= 0) return value;
        return value - Mathf.PosMod(value, gridSize);
    }

    public static Vector3I SnapToGrid(Vector3I coords, int gridSize)
    {
        return new Vector3I(
            SnapValueToGrid(coords.X, gridSize),
            SnapValueToGrid(coords.Y, gridSize),
            SnapValueToGrid(coords.Z, gridSize)
        );
    }
}
