using System.Collections.Generic;
using Godot;

namespace VoxelPath.Scripts.Blocks;

public partial class World : Node3D
{
    [Export] public NodePath AtlasNodePath;
    private BlockAtlas _atlas;

    private Dictionary<Vector3I, Chunk> _chunks = new();
    private Material _opaqueMaterial;
    private Material _transparentMaterial;

    public override void _Ready()
    {
        _atlas = GetNode<BlockAtlas>(AtlasNodePath);

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

        // 透明方块材质 - 使用 Alpha 模式，禁用深度写入但启用深度测试
        _transparentMaterial = new StandardMaterial3D
        {
            AlbedoTexture = _atlas?.AtlasTexture,
            Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
            CullMode = BaseMaterial3D.CullModeEnum.Back,
            DepthDrawMode = BaseMaterial3D.DepthDrawModeEnum.OpaqueOnly,
            // 禁用环境光反射以避免灰蒙蒙的效果
            AlbedoColor = new Color(1.0f, 1.0f, 1.0f, 1.0f),
            ShadingMode = BaseMaterial3D.ShadingModeEnum.PerVertex,
            // 增强纹理过滤
            TextureFilter = BaseMaterial3D.TextureFilterEnum.NearestWithMipmaps,
            // 禁用环境光以获得更清晰的色彩
            DisableAmbientLight = true
        };

        // 简单创建一个 Chunk
        LoadChunk(Vector3I.Zero);
        RebuildAllChunkMeshes();
    }

    public void LoadChunk(Vector3I coord)
    {
        if (_chunks.ContainsKey(coord)) return;
        var chunk = new Chunk(coord);
        _chunks[coord] = chunk;

        // 清空默认生成的方块，改为手动放置测试方块
        for (int x = 0; x < Chunk.SizeX; x++)
            for (int y = 0; y < Chunk.SizeY; y++)
                for (int z = 0; z < Chunk.SizeZ; z++)
                {
                    chunk.Set(x, y, z, BlockType.Air);
                }

        // 创建一个简单的地面层（y=0，使用草方块）
        for (int x = 0; x < 16; x++)
            for (int z = 0; z < 16; z++)
            {
                chunk.Set(x, 0, z, BlockType.Grass);
            }

        // 在地面上方创建展示平台，展示四种方块
        // 泥土方块 (Dirt) - 位置 (2, 1, 2)
        chunk.Set(2, 1, 2, BlockType.Dirt);
        chunk.Set(2, 2, 2, BlockType.Dirt);

        // 草方块 (Grass) - 位置 (5, 1, 2)
        chunk.Set(5, 1, 2, BlockType.Grass);
        chunk.Set(5, 2, 2, BlockType.Grass);

        // 橡木原木 (OakLog) - 创建一棵小树
        // 树干
        chunk.Set(8, 1, 2, BlockType.OakLog);
        chunk.Set(8, 2, 2, BlockType.OakLog);
        chunk.Set(8, 3, 2, BlockType.OakLog);
        chunk.Set(8, 4, 2, BlockType.OakLog);

        // 树叶 (OakLeaves) - 围绕树顶
        for (int dx = -1; dx <= 1; dx++)
            for (int dz = -1; dz <= 1; dz++)
                for (int dy = 0; dy <= 1; dy++)
                {
                    int lx = 8 + dx;
                    int ly = 4 + dy;
                    int lz = 2 + dz;
                    // 中心是树干，不放树叶
                    if (dx == 0 && dz == 0 && dy == 0) continue;
                    if (lx >= 0 && lx < Chunk.SizeX && lz >= 0 && lz < Chunk.SizeZ)
                        chunk.Set(lx, ly, lz, BlockType.OakLeaves);
                }

        // 额外放置一些单独的树叶方块用于展示
        chunk.Set(11, 1, 2, BlockType.OakLeaves);
        chunk.Set(11, 2, 2, BlockType.OakLeaves);
    }

    public void RebuildAllChunkMeshes()
    {
        // 清理旧的 StaticBody3D（包含网格和碰撞）
        foreach (Node child in GetChildren())
        {
            if (child is StaticBody3D sb && sb.Name.ToString().StartsWith("ChunkBody_"))
                child.QueueFree();
        }

        int idx = 0;
        foreach (var kv in _chunks)
        {
            var chunk = kv.Value;
            Mesh m = ChunkMesher.BuildMesh(chunk, _atlas, _opaqueMaterial, _transparentMaterial);

            // 创建 StaticBody3D 作为父节点
            var staticBody = new StaticBody3D { Name = $"ChunkBody_{idx}" };
            staticBody.Transform = new Transform3D(Basis.Identity, new Vector3(
                chunk.ChunkCoord.X * Chunk.SizeX,
                chunk.ChunkCoord.Y * Chunk.SizeY,
                chunk.ChunkCoord.Z * Chunk.SizeZ
            ));

            // 添加 MeshInstance3D
            var mi = new MeshInstance3D { Mesh = m, Name = "ChunkMesh" };
            staticBody.AddChild(mi);

            // 从网格创建碰撞形状
            var collisionShape = new CollisionShape3D { Name = "ChunkCollision" };
            collisionShape.Shape = m.CreateTrimeshShape();
            staticBody.AddChild(collisionShape);

            AddChild(staticBody);
            idx++;
        }
    }
}