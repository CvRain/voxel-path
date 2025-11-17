using Godot;
using System;
using System.Collections.Generic;

namespace TryWorld.Scripts.Blocks;

public partial class World : Node3D
{
    [Export] public NodePath AtlasNodePath;
    [Export] public int WorldSeed = 12345;
    [Export] public float TerrainScale = 0.05f;
    [Export] public int BaseHeight = 3;
    [Export] public int HeightVariation = 4;
    
    private BlockAtlas _atlas;
    private Dictionary<Vector3I, Chunk> _chunks = new();
    private Material _blockMaterial;
    private FastNoiseLite _noise;

    public override void _Ready()
    {
        _atlas = GetNode<BlockAtlas>(AtlasNodePath);
        _blockMaterial = new StandardMaterial3D
        {
            AlbedoTexture = _atlas?.AtlasTexture,
            Transparency = BaseMaterial3D.TransparencyEnum.Disabled,
            CullMode = BaseMaterial3D.CullModeEnum.Back,
            DepthDrawMode = BaseMaterial3D.DepthDrawModeEnum.Always
        };

        // 初始化噪声生成器用于地形
        _noise = new FastNoiseLite();
        _noise.Seed = WorldSeed;
        _noise.NoiseType = FastNoiseLite.NoiseTypeEnum.Perlin;
        _noise.Frequency = TerrainScale;

        // 生成 2x2 的 chunk 区域
        GenerateWorld();
        RebuildAllChunkMeshes();
    }

    private void GenerateWorld()
    {
        // 生成 4 个 chunk (2x2 布局)
        for (int cx = 0; cx < 2; cx++)
        for (int cz = 0; cz < 2; cz++)
        {
            LoadChunk(new Vector3I(cx, 0, cz));
        }

        // 生成树木
        GenerateTrees();
    }

    public void LoadChunk(Vector3I coord)
    {
        if (_chunks.ContainsKey(coord)) return;
        var chunk = new Chunk(coord);
        _chunks[coord] = chunk;

        // 生成地形
        GenerateTerrain(chunk);
    }

    private void GenerateTerrain(Chunk chunk)
    {
        // 先清空
        for (int x = 0; x < Chunk.SizeX; x++)
        for (int y = 0; y < Chunk.SizeY; y++)
        for (int z = 0; z < Chunk.SizeZ; z++)
        {
            chunk.Set(x, y, z, BlockType.Air);
        }

        // 生成地形
        for (int x = 0; x < Chunk.SizeX; x++)
        for (int z = 0; z < Chunk.SizeZ; z++)
        {
            // 计算世界坐标
            int worldX = chunk.ChunkCoord.X * Chunk.SizeX + x;
            int worldZ = chunk.ChunkCoord.Z * Chunk.SizeZ + z;

            // 使用噪声生成高度
            float noiseValue = _noise.GetNoise2D(worldX, worldZ);
            int height = BaseHeight + Mathf.RoundToInt(noiseValue * HeightVariation);
            height = Mathf.Clamp(height, 1, Chunk.SizeY - 1);

            // 生成方块柱
            for (int y = 0; y <= height; y++)
            {
                if (y == height)
                {
                    // 顶层：草方块
                    chunk.Set(x, y, z, BlockType.Grass);
                }
                else if (y >= height - 2)
                {
                    // 草方块下面2层：泥土
                    chunk.Set(x, y, z, BlockType.Dirt);
                }
                else
                {
                    // 更深层：泥土（可以改成石头）
                    chunk.Set(x, y, z, BlockType.Dirt);
                }
            }
        }
    }

    private void GenerateTrees()
    {
        var random = new Random(WorldSeed);

        // 在每个 chunk 中随机生成 1-2 棵树
        foreach (var kv in _chunks)
        {
            var chunk = kv.Value;
            int treeCount = random.Next(1, 3); // 1-2棵树

            for (int i = 0; i < treeCount; i++)
            {
                // 随机位置
                int x = random.Next(2, Chunk.SizeX - 2);
                int z = random.Next(2, Chunk.SizeZ - 2);

                // 找到地面高度
                int groundY = FindGroundHeight(chunk, x, z);
                if (groundY > 0 && groundY < Chunk.SizeY - 6)
                {
                    GenerateTree(chunk, x, groundY + 1, z, random);
                }
            }
        }
    }

    private int FindGroundHeight(Chunk chunk, int x, int z)
    {
        for (int y = Chunk.SizeY - 1; y >= 0; y--)
        {
            var block = chunk.Get(x, y, z);
            if (block != null && (BlockType)block.BlockId == BlockType.Grass)
            {
                return y;
            }
        }
        return -1;
    }

    private void GenerateTree(Chunk chunk, int baseX, int baseY, int baseZ, Random random)
    {
        int trunkHeight = random.Next(4, 6); // 树干高度 4-5

        // 生成树干
        for (int y = 0; y < trunkHeight; y++)
        {
            chunk.Set(baseX, baseY + y, baseZ, BlockType.Log);
        }

        // 生成树叶（简单的球形）
        int leavesY = baseY + trunkHeight;
        int leavesRadius = 2;

        for (int dx = -leavesRadius; dx <= leavesRadius; dx++)
        for (int dy = -1; dy <= 2; dy++)
        for (int dz = -leavesRadius; dz <= leavesRadius; dz++)
        {
            // 跳过树干中心
            if (dy <= 0 && dx == 0 && dz == 0) continue;

            // 简单的球形判断
            float dist = Mathf.Sqrt(dx * dx + dy * dy * 0.5f + dz * dz);
            if (dist <= leavesRadius + 0.5f)
            {
                int lx = baseX + dx;
                int ly = leavesY + dy;
                int lz = baseZ + dz;

                if (lx >= 0 && lx < Chunk.SizeX && 
                    ly >= 0 && ly < Chunk.SizeY && 
                    lz >= 0 && lz < Chunk.SizeZ)
                {
                    var block = chunk.Get(lx, ly, lz);
                    if (block != null && (BlockType)block.BlockId == BlockType.Air)
                    {
                        chunk.Set(lx, ly, lz, BlockType.Leaf);
                    }
                }
            }
        }
    }

    public void RebuildAllChunkMeshes()
    {
        // 清理旧的 MeshInstance3D 和 StaticBody3D
        foreach (Node child in GetChildren())
        {
            if (child.Name.ToString().StartsWith("ChunkMesh_") || 
                child.Name.ToString().StartsWith("ChunkCollision_"))
            {
                child.QueueFree();
            }
        }

        int idx = 0;
        foreach (var kv in _chunks)
        {
            var chunk = kv.Value;
            Vector3 chunkWorldPos = new Vector3(
                chunk.ChunkCoord.X * Chunk.SizeX,
                chunk.ChunkCoord.Y * Chunk.SizeY,
                chunk.ChunkCoord.Z * Chunk.SizeZ
            );

            // 创建网格
            Mesh m = ChunkMesher.BuildMesh(chunk, _atlas, _blockMaterial);
            var mi = new MeshInstance3D 
            { 
                Mesh = m, 
                Name = $"ChunkMesh_{idx}" 
            };
            mi.Transform = new Transform3D(Basis.Identity, chunkWorldPos);
            AddChild(mi);

            // 使用网格三角形创建碰撞体（更高效）
            if (m != null)
            {
                mi.CreateTrimeshCollision();
                // 重命名碰撞节点以便追踪
                if (mi.GetChildCount() > 0)
                {
                    var collisionNode = mi.GetChild(0);
                    collisionNode.Name = $"ChunkCollision_{idx}";
                }
            }
            
            idx++;
        }
    }
}