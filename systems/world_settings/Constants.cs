namespace VoxelPath.Scripts.Core;

public static class Constants
{
    public const string Version = "0.1.0";
    public const string GameName = "Voxel Path: Artisan's Realm";

    public const float VoxelSize = 0.25f;
    public const int ChunkSize = 64; // 16 meters wide (64 * 0.25)
    public const float ChunkWorldSize = ChunkSize * VoxelSize;
    public const int SeaLevel = 1024; // 海平面高度（格子），对应256方块（1024*0.25）
    public const int MaxTerrainHeight = 3072; // 自然方块生成上限（格子）
    public const int VoxelMaxHeight = 1024; // 256 meters high

    public const int AirBlockId = 0;
    public const int FirstModBlockId = 256;

    public const string DataBlocksPath = "res://Data/blocks";
    public const string DataBlocksManifest = "res://Data/blocks/_manifest.json";
    public const string ModPath = "user://mods";

    public const bool DebugEnabled = true;
    public const bool DebugBlockLoading = true;
    public const bool DebugTextureLoading = true;

    public const int MaxChunksPerFrame = 4;
    public const int ViewDistance = 8;
    public const int LodLevels = 3;

    public const int ChunkSectionSize = 64; // Height of each sub-chunk section
}
