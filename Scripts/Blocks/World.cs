using System;
using System.Collections.Generic;
using Godot;

namespace VoxelPath.Scripts.Blocks;

public partial class World : Node3D
{
    [Export] public NodePath AtlasNodePath;
    [Export] public NodePath PlayerNodePath;
    [Export] public Vector2I SpawnChunkCoord = Vector2I.Zero;
    [Export] public bool UsePlayerInitialPositionAsSpawn = true;
    [Export(PropertyHint.Range, "1,12,1")] public int ChunkGridSize = 4;
    [Export(PropertyHint.Range, "1,6,1")] public int VerticalChunkCount = 2;
    [Export(PropertyHint.Range, "4,80,1")] public int BaseHeight = 20;
    [Export(PropertyHint.Range, "4,64,1")] public int HeightAmplitude = 16;
    [Export(PropertyHint.Range, "0,80,1")] public int SeaLevel = 8;
    [Export(PropertyHint.Range, "4,32,4")] public int GenerationClusterSize = BlockMetrics.ClusterBlockLength;
    [Export(PropertyHint.Range, "0.001,0.02,0.0005")] public float HeightFrequency = 0.0025f;
    [Export(PropertyHint.Range, "0.005,0.05,0.0005")] public float DetailFrequency = 0.01f;
    [Export(PropertyHint.Range, "0.8,3.0,0.05")] public float MountainSharpness = 1.4f;
    [Export(PropertyHint.Range, "0.3,0.9,0.05")] public float TreeDensityThreshold = 0.55f;
    [Export(PropertyHint.Range, "1,4,1")] public int GrassLayerClusters = 2;
    [Export(PropertyHint.Range, "1,6,1")] public int GrassDirtLayerClusters = 2;
    [Export(PropertyHint.Range, "2,10,1")] public int TreeSpacingMeters = 4;
    private BlockAtlas _atlas;

    private readonly Dictionary<Vector3I, Chunk> _chunks = new();
    private readonly Dictionary<Vector3I, StaticBody3D> _chunkBodies = new();
    private Material _opaqueMaterial;
    private Material _transparentMaterial;
    private Node3D _player;
    private FastNoiseLite _heightNoise;
    private FastNoiseLite _stoneNoise;
    private FastNoiseLite _detailNoise;
    private FastNoiseLite _treeNoise;
    private RandomNumberGenerator _rng;
    private const int SoilDepthClusters = 3;
    private const int CobbleDepthClusters = 6;
    private int ChunkHeightClusters => Mathf.Max(1, Chunk.SizeY / BlockMetrics.ClusterBlockLength);
    private int MaxSurfaceBlocks => VerticalChunkCount * Chunk.SizeY - BlockMetrics.ClusterBlockLength;
    private int TreeSpacingBlocks => TreeSpacingMeters * BlockMetrics.BlocksPerMeter;

    public override void _Ready()
    {
        _atlas = GetNode<BlockAtlas>(AtlasNodePath);
        if (PlayerNodePath != null && !PlayerNodePath.IsEmpty)
            _player = GetNode<Node3D>(PlayerNodePath);
        else
            _player = GetNodeOrNull<Node3D>("Player");
    GenerationClusterSize = NormalizeClusterSize(GenerationClusterSize, true);
        _rng = new RandomNumberGenerator();
        _rng.Randomize();

        _heightNoise = new FastNoiseLite
        {
            Seed = (int)_rng.Randi(),
            NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex,
            Frequency = HeightFrequency,
            FractalOctaves = 4,
            FractalLacunarity = 2.0f,
            FractalGain = 0.55f
        };

        _detailNoise = new FastNoiseLite
        {
            Seed = _heightNoise.Seed + 57,
            NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex,
            Frequency = DetailFrequency,
            FractalOctaves = 3,
            FractalGain = 0.8f
        };

        _stoneNoise = new FastNoiseLite
        {
            Seed = _heightNoise.Seed + 101,
            NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex,
            Frequency = DetailFrequency * 1.5f,
            FractalOctaves = 2,
            FractalGain = 0.6f
        };

        _treeNoise = new FastNoiseLite
        {
            Seed = _heightNoise.Seed + 777,
            NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex,
            Frequency = 0.012f,
            FractalOctaves = 2,
            FractalGain = 0.5f
        };

        // 不透明方块材质 - 使用 AlphaScissor 模式，开启深度写入
        _opaqueMaterial = new StandardMaterial3D
        {
            AlbedoTexture = _atlas?.AtlasTexture,
            Transparency = BaseMaterial3D.TransparencyEnum.AlphaScissor,
            AlphaScissorThreshold = 0.5f,
            CullMode = BaseMaterial3D.CullModeEnum.Back,
            DepthDrawMode = BaseMaterial3D.DepthDrawModeEnum.Always,
            // 禁用环境光反射以避免灰蒙蒙的效果
            AlbedoColor = new Color(1.0f, 1.0f, 1.0f, 1.0f),
            ShadingMode = BaseMaterial3D.ShadingModeEnum.PerVertex,
            // 增强纹理过滤
            TextureFilter = BaseMaterial3D.TextureFilterEnum.NearestWithMipmaps,
            // 禁用环境光以获得更清晰的色彩
            DisableAmbientLight = true
        };

        // 透明方块材质 - 对树叶等半透明使用 AlphaScissor，保持深度写入避免“远近树叶叠在一起”
        _transparentMaterial = new StandardMaterial3D
        {
            AlbedoTexture = _atlas?.AtlasTexture,
            Transparency = BaseMaterial3D.TransparencyEnum.AlphaScissor,
            AlphaScissorThreshold = 0.25f,
            CullMode = BaseMaterial3D.CullModeEnum.Back,
            DepthDrawMode = BaseMaterial3D.DepthDrawModeEnum.Always,
            // 禁用环境光反射以避免灰蒙蒙的效果
            AlbedoColor = new Color(1.0f, 1.0f, 1.0f, 1.0f),
            ShadingMode = BaseMaterial3D.ShadingModeEnum.PerVertex,
            // 增强纹理过滤
            TextureFilter = BaseMaterial3D.TextureFilterEnum.NearestWithMipmaps,
            // 禁用环境光以获得更清晰的色彩
            DisableAmbientLight = true
        };

        if (UsePlayerInitialPositionAsSpawn && _player != null)
        {
            float playerGridX = _player.GlobalPosition.X / BlockMetrics.StandardBlockSize;
            float playerGridZ = _player.GlobalPosition.Z / BlockMetrics.StandardBlockSize;
            SpawnChunkCoord = new Vector2I(
                Mathf.FloorToInt(playerGridX / Chunk.SizeX),
                Mathf.FloorToInt(playerGridZ / Chunk.SizeZ)
            );
        }

        // 以玩家出生 Chunk 为中心生成 ChunkGridSize * ChunkGridSize 的地形
        GenerateChunksAroundSpawn();
        RebuildAllChunkMeshes();

        if (_player != null)
        {
            PositionPlayerOnSurface();
        }
    }

    private void GenerateChunksAroundSpawn()
    {
        int startX = SpawnChunkCoord.X - ChunkGridSize / 2;
        int startZ = SpawnChunkCoord.Y - ChunkGridSize / 2;

        for (int cx = 0; cx < ChunkGridSize; cx++)
        {
            for (int cz = 0; cz < ChunkGridSize; cz++)
            {
                for (int cy = 0; cy < VerticalChunkCount; cy++)
                {
                    var coord = new Vector3I(startX + cx, cy, startZ + cz);
                    LoadChunk(coord);
                }
            }
        }
    }

    public void LoadChunk(Vector3I coord)
    {
        if (_chunks.ContainsKey(coord)) return;
        var chunk = new Chunk(coord);
        _chunks[coord] = chunk;
        GenerateChunkTerrain(chunk);
    }

    private void GenerateChunkTerrain(Chunk chunk)
    {
        int baseX = chunk.ChunkCoord.X * Chunk.SizeX;
        int baseZ = chunk.ChunkCoord.Z * Chunk.SizeZ;
        int cluster = GenerationClusterSize;
        int chunkClusterOrigin = chunk.ChunkCoord.Y * ChunkHeightClusters;

        for (int x = 0; x < Chunk.SizeX; x += cluster)
        {
            for (int z = 0; z < Chunk.SizeZ; z += cluster)
            {
                int worldBlockX = baseX + x;
                int worldBlockZ = baseZ + z;

                var surfaceInfo = SampleSurface(worldBlockX, worldBlockZ);
                int worldSurfaceCluster = surfaceInfo.heightBlocks / BlockMetrics.ClusterBlockLength;
                int localSurfaceCluster = worldSurfaceCluster - chunkClusterOrigin;
                if (localSurfaceCluster < 0)
                    continue;

                bool chunkContainsSurface = localSurfaceCluster < ChunkHeightClusters;
                int clampedSurfaceCluster = Mathf.Clamp(localSurfaceCluster, 0, ChunkHeightClusters - 1);

                FillClusterColumn(chunk, x, z, cluster, clampedSurfaceCluster, surfaceInfo, chunkContainsSurface);

                if (chunkContainsSurface && surfaceInfo.surfaceType == BlockType.GrassFull)
                {
                    int treeBaseX = Mathf.Clamp(
                        BlockMetrics.SnapValueToGrid(x + cluster / 2 - BlockMetrics.ClusterBlockLength / 2,
                            BlockMetrics.ClusterBlockLength),
                        0,
                        Chunk.SizeX - BlockMetrics.ClusterBlockLength);
                    int treeBaseZ = Mathf.Clamp(
                        BlockMetrics.SnapValueToGrid(z + cluster / 2 - BlockMetrics.ClusterBlockLength / 2,
                            BlockMetrics.ClusterBlockLength),
                        0,
                        Chunk.SizeZ - BlockMetrics.ClusterBlockLength);

                    TryPlaceTree(chunk, treeBaseX, clampedSurfaceCluster, treeBaseZ, worldBlockX, worldBlockZ);
                }
            }
        }
    }

    private void FillClusterColumn(Chunk chunk, int startX, int startZ, int clusterSize, int surfaceClusterY,
        (int heightBlocks, BlockType surfaceType, float rockSample) surface, bool chunkContainsSurface)
    {
        if (surfaceClusterY < 0) return;
        int clampedCluster = Mathf.Clamp(surfaceClusterY, 0, ChunkHeightClusters - 1);
        BlockType topLayerType = chunkContainsSurface ? surface.surfaceType : BlockType.Stone;
        bool useGrassStack = chunkContainsSurface && surface.surfaceType == BlockType.GrassFull;
        int effectiveGrassLayers = Mathf.Clamp(GrassLayerClusters, 1, clampedCluster + 1);
        int effectiveDirtLayers = Mathf.Clamp(GrassDirtLayerClusters, 1, clampedCluster + 1);
        int grassStart = clampedCluster - effectiveGrassLayers + 1;
        int dirtStart = grassStart - effectiveDirtLayers;

        for (int clusterY = 0; clusterY <= clampedCluster; clusterY++)
        {
            BlockType placeType = BlockType.Stone;
            if (useGrassStack)
            {
                if (clusterY >= grassStart)
                    placeType = BlockType.GrassFull;
                else if (clusterY >= dirtStart)
                    placeType = BlockType.Dirt;
                else if (surface.rockSample > 0.65f &&
                         clusterY >= dirtStart - CobbleDepthClusters)
                    placeType = BlockType.Cobblestone;
                else
                    placeType = BlockType.Stone;
            }
            else
            {
                if (clusterY == clampedCluster)
                    placeType = topLayerType;
                else if (clusterY >= clampedCluster - SoilDepthClusters)
                    placeType = BlockType.Dirt;
                else if (surface.rockSample > 0.65f &&
                         clusterY >= clampedCluster - SoilDepthClusters - CobbleDepthClusters)
                    placeType = BlockType.Cobblestone;
            }

            FillClusterVolume(chunk, startX, clusterY * BlockMetrics.ClusterBlockLength, startZ,
                clusterSize, BlockMetrics.ClusterBlockLength, placeType);
        }
    }

    private (int heightBlocks, BlockType surfaceType, float rockSample) SampleSurface(int worldBlockX, int worldBlockZ)
    {
        float worldMetersX = worldBlockX * BlockMetrics.StandardBlockSize;
        float worldMetersZ = worldBlockZ * BlockMetrics.StandardBlockSize;

        float baseSample = _heightNoise.GetNoise2D(worldMetersX, worldMetersZ);
        float detailSample = _detailNoise.GetNoise2D(worldMetersX * 1.25f, worldMetersZ * 1.25f);
        float normalizedBase = Mathf.Clamp((baseSample + 1f) * 0.5f, 0f, 1f);
        float ridged = Mathf.Pow(normalizedBase, MountainSharpness);
        float normalizedDetail = Mathf.Clamp((detailSample + 1f) * 0.5f, 0f, 1f);
        float combined = Mathf.Clamp(ridged * 0.85f + normalizedDetail * 0.35f, 0f, 1f);
        float heightOffset = (combined - 0.5f) * HeightAmplitude * 2f;
        float surfaceMeters = BaseHeight + heightOffset;
        int surfaceBlocks = BlockMetrics.ToBlockCount(surfaceMeters);
        int seaBlocks = BlockMetrics.ToBlockCount(SeaLevel);
        surfaceBlocks = Mathf.Clamp(surfaceBlocks, seaBlocks, MaxSurfaceBlocks);

        float rockSample = _stoneNoise.GetNoise2D(worldMetersX * 0.5f, worldMetersZ * 0.5f);
    BlockType surfaceType = BlockType.GrassFull;
        if (rockSample > 0.55f)
            surfaceType = BlockType.Stone;
        if (rockSample > 0.7f)
            surfaceType = BlockType.Cobblestone;

        return (surfaceBlocks, surfaceType, rockSample);
    }

    private void TryPlaceTree(Chunk chunk, int startX, int groundClusterY, int startZ, int worldBlockX, int worldBlockZ)
    {
        int clusterPadding = BlockMetrics.ClusterBlockLength;
        if (startX < clusterPadding || startZ < clusterPadding ||
            startX >= Chunk.SizeX - clusterPadding || startZ >= Chunk.SizeZ - clusterPadding)
            return;

        int spacingBlocks = Mathf.Max(TreeSpacingBlocks, BlockMetrics.ClusterBlockLength);
        int anchorX = worldBlockX + BlockMetrics.ClusterBlockLength / 2;
        int anchorZ = worldBlockZ + BlockMetrics.ClusterBlockLength / 2;
        if (Mathf.PosMod(anchorX, spacingBlocks) != 0 || Mathf.PosMod(anchorZ, spacingBlocks) != 0)
            return;

        float raw = _treeNoise.GetNoise2D(
            worldBlockX * BlockMetrics.StandardBlockSize,
            worldBlockZ * BlockMetrics.StandardBlockSize);
        float value = Mathf.Clamp((raw + 1f) * 0.5f, 0f, 1f);
        if (value < TreeDensityThreshold)
            return;

        float normalized = Mathf.InverseLerp(TreeDensityThreshold, 1f, value);
        int trunkHeightClusters = Mathf.Clamp(Mathf.RoundToInt(Mathf.Lerp(4f, 7f, normalized)), 4, 7);
        if (groundClusterY + trunkHeightClusters + 3 >= ChunkHeightClusters)
            return;

        for (int c = 1; c <= trunkHeightClusters; c++)
        {
            int yBlocks = (groundClusterY + c) * BlockMetrics.ClusterBlockLength;
            FillClusterVolume(chunk, startX, yBlocks, startZ,
                BlockMetrics.ClusterBlockLength, BlockMetrics.ClusterBlockLength, BlockType.OakLog);
        }

        int leavesStartCluster = groundClusterY + trunkHeightClusters - 1;
        for (int dy = 0; dy <= 2; dy++)
        {
            int radius = 2 - dy;
            for (int dx = -radius; dx <= radius; dx++)
            {
                for (int dz = -radius; dz <= radius; dz++)
                {
                    if (dx == 0 && dz == 0 && dy == 0) continue;
                    int lx = startX + dx * BlockMetrics.ClusterBlockLength;
                    int lz = startZ + dz * BlockMetrics.ClusterBlockLength;
                    if (lx < 0 || lz < 0 || lx >= Chunk.SizeX || lz >= Chunk.SizeZ) continue;

                    int ly = (leavesStartCluster + dy) * BlockMetrics.ClusterBlockLength;
                    FillClusterVolume(chunk, lx, ly, lz,
                        BlockMetrics.ClusterBlockLength, BlockMetrics.ClusterBlockLength, BlockType.OakLeaves);
                }
            }
        }

        int topLeafY = (leavesStartCluster + 3) * BlockMetrics.ClusterBlockLength;
        FillClusterVolume(chunk, startX, topLeafY, startZ,
            BlockMetrics.ClusterBlockLength, BlockMetrics.ClusterBlockLength, BlockType.OakLeaves);
    }

    private void PositionPlayerOnSurface()
    {
        Vector3 spawnWorldPos = GetSpawnWorldPosition();
        _player.GlobalPosition = spawnWorldPos;
    }

    private Vector3 GetSpawnWorldPosition()
    {
        float gridX = SpawnChunkCoord.X * Chunk.SizeX + Chunk.SizeX / 2f;
        float gridZ = SpawnChunkCoord.Y * Chunk.SizeZ + Chunk.SizeZ / 2f;
        var surfaceInfo = SampleSurface(Mathf.RoundToInt(gridX), Mathf.RoundToInt(gridZ));
        float worldX = BlockMetrics.ToWorld(gridX + 0.5f);
        float worldZ = BlockMetrics.ToWorld(gridZ + 0.5f);
        float worldY = BlockMetrics.ToWorld(surfaceInfo.heightBlocks + BlockMetrics.ClusterBlockLength * 2);
        return new Vector3(worldX, worldY, worldZ);
    }

    public void RebuildAllChunkMeshes()
    {
        foreach (var body in _chunkBodies.Values)
        {
            if (GodotObject.IsInstanceValid(body))
            {
                body.QueueFree();
            }
        }

        _chunkBodies.Clear();

        foreach (var kv in _chunks)
        {
            RebuildChunkMeshInternal(kv.Key, kv.Value);
        }
    }

    public bool TryBreakCluster(Vector3 worldPosition, int clusterSize)
    {
        int size = NormalizeClusterSize(clusterSize);
        var start = BlockMetrics.SnapToGrid(BlockMetrics.WorldToBlockCoords(worldPosition), size);

        var touchedChunks = new HashSet<Vector3I>();
        bool changed = false;
        ForEachBlock(start, size, coords =>
        {
            changed |= SetBlockGlobal(coords, BlockType.Air, touchedChunks);
        });

        if (!changed) return false;
        RebuildChunks(touchedChunks);
        return true;
    }

    public bool TryPlaceCluster(Vector3 worldPosition, int clusterSize, BlockType blockType)
    {
        int size = NormalizeClusterSize(clusterSize);
        var start = BlockMetrics.SnapToGrid(BlockMetrics.WorldToBlockCoords(worldPosition), size);

        if (!CanPlaceCluster(start, size))
            return false;

        var touchedChunks = new HashSet<Vector3I>();
        ForEachBlock(start, size, coords =>
        {
            SetBlockGlobal(coords, blockType, touchedChunks);
        });

        RebuildChunks(touchedChunks);
        return true;
    }

    private void RebuildChunkMesh(Vector3I chunkCoord)
    {
        if (!_chunks.TryGetValue(chunkCoord, out var chunk))
            return;

        RebuildChunkMeshInternal(chunkCoord, chunk);
    }

    private void RebuildChunkMeshInternal(Vector3I chunkCoord, Chunk chunk)
    {
        if (_chunkBodies.TryGetValue(chunkCoord, out var existing) && GodotObject.IsInstanceValid(existing))
        {
            existing.QueueFree();
            _chunkBodies.Remove(chunkCoord);
        }

        var chunkBody = CreateChunkBody(chunkCoord, chunk);
        if (chunkBody == null)
            return;

        AddChild(chunkBody);
        _chunkBodies[chunkCoord] = chunkBody;
    }

    private StaticBody3D CreateChunkBody(Vector3I chunkCoord, Chunk chunk)
    {
    Mesh mesh = ChunkMesher.BuildMesh(chunk, chunkCoord, _atlas, _opaqueMaterial, _transparentMaterial);
        if (mesh == null || mesh.GetSurfaceCount() == 0)
            return null;

        var staticBody = new StaticBody3D
        {
            Name = $"ChunkBody_{chunkCoord.X}_{chunkCoord.Y}_{chunkCoord.Z}"
        };

        staticBody.Transform = new Transform3D(Basis.Identity, new Vector3(
            chunkCoord.X * Chunk.SizeX * BlockMetrics.StandardBlockSize,
            chunkCoord.Y * Chunk.SizeY * BlockMetrics.StandardBlockSize,
            chunkCoord.Z * Chunk.SizeZ * BlockMetrics.StandardBlockSize
        ));

        var meshInstance = new MeshInstance3D { Mesh = mesh, Name = "ChunkMesh" };
        staticBody.AddChild(meshInstance);

        var collisionShape = new CollisionShape3D { Name = "ChunkCollision" };
        collisionShape.Shape = mesh.CreateTrimeshShape();
        staticBody.AddChild(collisionShape);

        return staticBody;
    }

    private void FillClusterVolume(Chunk chunk, int startX, int startY, int startZ, int sizeXZ, int sizeY, BlockType type)
    {
        int maxX = Mathf.Min(Chunk.SizeX, startX + sizeXZ);
        int maxY = Mathf.Min(Chunk.SizeY, startY + sizeY);
        int maxZ = Mathf.Min(Chunk.SizeZ, startZ + sizeXZ);

        for (int x = Mathf.Max(0, startX); x < maxX; x++)
            for (int y = Mathf.Max(0, startY); y < maxY; y++)
                for (int z = Mathf.Max(0, startZ); z < maxZ; z++)
                    chunk.Set(x, y, z, type);
    }

    private void ForEachBlock(Vector3I start, int size, Action<Vector3I> action)
    {
        for (int x = start.X; x < start.X + size; x++)
            for (int y = start.Y; y < start.Y + size; y++)
                for (int z = start.Z; z < start.Z + size; z++)
                    action(new Vector3I(x, y, z));
    }

    private bool CanPlaceCluster(Vector3I start, int size)
    {
        for (int x = start.X; x < start.X + size; x++)
        {
            for (int y = start.Y; y < start.Y + size; y++)
            {
                for (int z = start.Z; z < start.Z + size; z++)
                {
                    var coords = new Vector3I(x, y, z);
                    if (!TryGetChunkForBlock(coords, out var chunk, out var local, out _))
                        return false;
                    if (chunk.Get(local.X, local.Y, local.Z) != BlockType.Air)
                        return false;
                }
            }
        }

        return true;
    }

    private bool SetBlockGlobal(Vector3I blockCoords, BlockType blockType, HashSet<Vector3I> touchedChunks)
    {
        if (!TryGetChunkForBlock(blockCoords, out var chunk, out var local, out var chunkCoord))
            return false;
        bool changed = chunk.Set(local.X, local.Y, local.Z, blockType);
        if (changed)
            touchedChunks.Add(chunkCoord);
        return changed;
    }

    private void RebuildChunks(IEnumerable<Vector3I> chunkCoords)
    {
        foreach (var coord in chunkCoords)
        {
            RebuildChunkMesh(coord);
        }
    }

    private int NormalizeClusterSize(int size, bool enforceClusterMultiple = false)
    {
        int abs = Mathf.Max(1, Mathf.Abs(size));
        if (enforceClusterMultiple)
        {
            if (abs < BlockMetrics.ClusterBlockLength)
                abs = BlockMetrics.ClusterBlockLength;
            int remainder = abs % BlockMetrics.ClusterBlockLength;
            if (remainder != 0)
                abs += BlockMetrics.ClusterBlockLength - remainder;
        }

        return Mathf.Clamp(abs, 1, Chunk.SizeX);
    }

    private bool TryGetChunkForBlock(Vector3I blockCoords, out Chunk chunk, out Vector3I localCoords,
        out Vector3I chunkCoord)
    {
        chunkCoord = new Vector3I(
            Mathf.FloorToInt(blockCoords.X / (float)Chunk.SizeX),
            Mathf.FloorToInt(blockCoords.Y / (float)Chunk.SizeY),
            Mathf.FloorToInt(blockCoords.Z / (float)Chunk.SizeZ)
        );

        localCoords = new Vector3I(
            Mathf.PosMod(blockCoords.X, Chunk.SizeX),
            Mathf.PosMod(blockCoords.Y, Chunk.SizeY),
            Mathf.PosMod(blockCoords.Z, Chunk.SizeZ)
        );

        return _chunks.TryGetValue(chunkCoord, out chunk);
    }
}