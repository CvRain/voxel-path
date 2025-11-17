using Godot;

namespace VoxelPath.Scripts.Blocks;

public static class ChunkMesher
{
    private const int TextureSubtileDivisions = BlockMetrics.BlocksPerMeter;
    private static readonly Vector3[] FaceNormals =
    [
        Vector3.Right, Vector3.Left,
        Vector3.Up, Vector3.Down,
        Vector3.Forward, Vector3.Back
    ];

    private static readonly Vector3[][] FaceVertices =
    [
        // +X
        [new Vector3(1, 0, 0), new Vector3(1, 1, 0), new Vector3(1, 1, 1), new Vector3(1, 0, 1)],
        // -X
        [new Vector3(0, 0, 1), new Vector3(0, 1, 1), new Vector3(0, 1, 0), new Vector3(0, 0, 0)],
        // +Y
        [new Vector3(0, 1, 1), new Vector3(1, 1, 1), new Vector3(1, 1, 0), new Vector3(0, 1, 0)],
        // -Y
        [new Vector3(0, 0, 0), new Vector3(1, 0, 0), new Vector3(1, 0, 1), new Vector3(0, 0, 1)],
        // +Z
        [new Vector3(0, 0, 1), new Vector3(1, 0, 1), new Vector3(1, 1, 1), new Vector3(0, 1, 1)],
        // -Z
        [new Vector3(1, 0, 0), new Vector3(0, 0, 0), new Vector3(0, 1, 0), new Vector3(1, 1, 0)]
    ];

    private static readonly int[] TriangleOrder = { 0, 2, 1, 0, 3, 2 };

    public static Mesh BuildMesh(Chunk chunk, Vector3I chunkCoord, BlockAtlas atlas,
        Material opaqueMaterial, Material transparentMaterial)
    {
        var arrayMesh = new ArrayMesh();
        var stOpaque = new SurfaceTool();
        stOpaque.Begin(Mesh.PrimitiveType.Triangles);
        stOpaque.SetMaterial(opaqueMaterial);

        var stTransparent = new SurfaceTool();
        stTransparent.Begin(Mesh.PrimitiveType.Triangles);
        stTransparent.SetMaterial(transparentMaterial);

        for (int x = 0; x < Chunk.SizeX; x++)
            for (int y = 0; y < Chunk.SizeY; y++)
                for (int z = 0; z < Chunk.SizeZ; z++)
                {
                    var blockType = chunk.Get(x, y, z);
                    if (blockType == BlockType.Air) continue;

                    var def = BlockRegistry.Get(blockType);
                    var st = def.IsTransparent ? stTransparent : stOpaque;
                    Vector3 basePos = new Vector3(x, y, z) * BlockMetrics.StandardBlockSize;
                    int subX = 0;
                    int subY = 0;
                    if (def.UseRandomSubtiles)
                    {
                        var offsets = GetBlockSubtile(chunkCoord, x, y, z);
                        subX = offsets.X;
                        subY = offsets.Y;
                    }

                    AddCube(st, atlas, basePos, BlockMetrics.StandardBlockSize, def, subX, subY,
                        face => ShouldDrawFace(chunk, x, y, z, face, def));
                }

        stOpaque.GenerateNormals();
        arrayMesh = stOpaque.Commit();

        stTransparent.GenerateNormals();
        stTransparent.Commit(arrayMesh);

        return arrayMesh;
    }

    private static bool ShouldDrawFace(Chunk chunk, int x, int y, int z, int face, BlockDefinition def)
    {
        int nx = x, ny = y, nz = z;
        switch (face)
        {
            case 0: nx++; break;
            case 1: nx--; break;
            case 2: ny++; break;
            case 3: ny--; break;
            case 4: nz++; break;
            case 5: nz--; break;
        }

        if (!chunk.InBounds(nx, ny, nz))
            return true;

        var neighborType = chunk.Get(nx, ny, nz);
        if (neighborType == BlockType.Air) return true;

        var neighborDef = BlockRegistry.Get(neighborType);
        if (neighborDef.IsTransparent) return true;
        if (def.IsTransparent && neighborType != def.Type) return true;

        return false;
    }

    private static void AddCube(SurfaceTool st, BlockAtlas atlas, Vector3 basePos, float size,
        BlockDefinition def, int subX, int subY, System.Func<int, bool> shouldDrawFace)
    {
        for (int face = 0; face < 6; face++)
        {
            if (shouldDrawFace != null && !shouldDrawFace(face))
                continue;

            int atlasIndex = def.FaceAtlasIndices[face];
            Vector2 uvMin;
            Vector2 uvMax;
            if (def.UseRandomSubtiles)
                atlas.GetTileUvSubRegion(atlasIndex, TextureSubtileDivisions, subX, subY, out uvMin, out uvMax);
            else
                atlas.GetTileUv(atlasIndex, out uvMin, out uvMax);

            var vtx = FaceVertices[face];
            var normal = FaceNormals[face];

            foreach (int i in TriangleOrder)
            {
                Vector3 local = vtx[i];
                Vector3 worldPos = basePos + local * size;

                GetLocalUv(face, local, out float u, out float v);
                Vector2 uv = new Vector2(
                    Mathf.Lerp(uvMin.X, uvMax.X, u),
                    Mathf.Lerp(uvMin.Y, uvMax.Y, v)
                );

                st.SetNormal(normal);
                st.SetUV(uv);
                st.AddVertex(worldPos);
            }
        }
    }

    private static void GetLocalUv(int face, Vector3 p, out float u, out float v)
    {
        switch (face)
        {
            case 0: // +X 面：U=Z, V=1-Y（保持顶部朝上）
                u = p.Z; v = 1f - p.Y;
                break;
            case 1: // -X 面：U=1-Z, V=1-Y（水平翻转 + 顶部向上）
                u = 1f - p.Z; v = 1f - p.Y;
                break;
            case 2: // +Y 面：U=X, V=1-Z（让顶部看起来与 +Z 面方向一致）
                u = p.X; v = 1f - p.Z;
                break;
            case 3: // -Y 面：U=X, V=Z
                u = p.X; v = p.Z;
                break;
            case 4: // +Z 面：U=X, V=1-Y
                u = p.X; v = 1f - p.Y;
                break;
            case 5: // -Z 面：U=1-X, V=1-Y（Godot 默认面向 -Z，即玩家视角正面，应保持纹理朝上）
                u = 1f - p.X; v = 1f - p.Y;
                break;
            default:
                u = p.X; v = p.Y;
                break;
        }
    }

    // 可选调试：确认 atlas 面顺序是否与本类一致
    public static void DebugFaceOrder(BlockDefinition def)
    {
        GD.Print($"Face order(+X,-X,+Y,-Y,+Z,-Z) indices: " +
                 $"{def.FaceAtlasIndices[0]}, {def.FaceAtlasIndices[1]}, {def.FaceAtlasIndices[2]}, " +
                 $"{def.FaceAtlasIndices[3]}, {def.FaceAtlasIndices[4]}, {def.FaceAtlasIndices[5]}");
    }

    private static Vector2I GetBlockSubtile(Vector3I chunkCoord, int x, int y, int z)
    {
        unchecked
        {
            uint hash = 2166136261u;
            hash = (hash ^ (uint)chunkCoord.X) * 16777619u;
            hash = (hash ^ (uint)chunkCoord.Y) * 16777619u;
            hash = (hash ^ (uint)chunkCoord.Z) * 16777619u;
            hash = (hash ^ (uint)x) * 16777619u;
            hash = (hash ^ (uint)y) * 16777619u;
            hash = (hash ^ (uint)z) * 16777619u;

            int subX = (int)(hash % (uint)TextureSubtileDivisions);
            hash = (hash ^ 0x9e3779b9u) * 16777619u;
            int subY = (int)(hash % (uint)TextureSubtileDivisions);
            return new Vector2I(subX, subY);
        }
    }
}