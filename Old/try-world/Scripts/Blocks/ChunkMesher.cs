using Godot;

namespace TryWorld.Scripts.Blocks;

public static class ChunkMesher
{
    private static readonly Vector3[] FaceNormals =
    {
        Vector3.Right, Vector3.Left,
        Vector3.Up, Vector3.Down,
        Vector3.Forward, Vector3.Back
    };

    // 每个面 4 个顶点（右手坐标系下标准立方体）
    private static readonly Vector3[][] FaceVertices =
    {
        // +X
        new[] { new Vector3(1, 0, 0), new Vector3(1, 1, 0), new Vector3(1, 1, 1), new Vector3(1, 0, 1) },
        // -X
        new[] { new Vector3(0, 0, 1), new Vector3(0, 1, 1), new Vector3(0, 1, 0), new Vector3(0, 0, 0) },
        // +Y
        new[] { new Vector3(0, 1, 1), new Vector3(1, 1, 1), new Vector3(1, 1, 0), new Vector3(0, 1, 0) },
        // -Y
        new[] { new Vector3(0, 0, 0), new Vector3(1, 0, 0), new Vector3(1, 0, 1), new Vector3(0, 0, 1) },
        // +Z
        new[] { new Vector3(0, 0, 1), new Vector3(1, 0, 1), new Vector3(1, 1, 1), new Vector3(0, 1, 1) },
        // -Z
        new[] { new Vector3(1, 0, 0), new Vector3(0, 0, 0), new Vector3(0, 1, 0), new Vector3(1, 1, 0) }
    };

    public static Mesh BuildMesh(Chunk chunk, BlockAtlas atlas, Material baseMaterial)
    {
        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        st.SetMaterial(baseMaterial);

        for (int x = 0; x < Chunk.SizeX; x++)
        for (int y = 0; y < Chunk.SizeY; y++)
        for (int z = 0; z < Chunk.SizeZ; z++)
        {
            var block = chunk.Get(x, y, z);
            if (block == null) continue;
            if ((BlockType)block.BlockId == BlockType.Air) continue;

            if (!block.IsSubdivided)
            {
                AddMacroBlock(st, atlas, x, y, z, block);
            }
            else
            {
                for (int mx = 0; mx < 4; mx++)
                for (int my = 0; my < 4; my++)
                for (int mz = 0; mz < 4; mz++)
                {
                    if (!block.Micro.Has(mx, my, mz)) continue;
                    byte t = block.Micro.Types[MicroBlockData.ToIndex(mx, my, mz)];
                    var def = BlockRegistry.Get((BlockType)t);
                    Vector3 basePos = new Vector3(x, y, z) + new Vector3(mx, my, mz) * 0.25f;
                    AddCube(st, atlas, basePos, 0.25f, def);
                }
            }
        }

        st.GenerateNormals();
        return st.Commit();
    }

    private static void AddMacroBlock(SurfaceTool st, BlockAtlas atlas, int x, int y, int z, MacroBlockData block)
    {
        var def = BlockRegistry.Get((BlockType)block.BlockId);
        Vector3 pos = new Vector3(x, y, z);
        AddCube(st, atlas, pos, 1f, def);
    }

    // 使用正确的局部平面坐标生成 UV，避免贴图沿某轴拉伸
    private static void AddCube(SurfaceTool st, BlockAtlas atlas, Vector3 basePos, float size, BlockDefinition def)
    {
        for (int face = 0; face < 6; face++)
        {
            int atlasIndex = def.FaceAtlasIndices[face];
            atlas.GetTileUv(atlasIndex, out Vector2 uvMin, out Vector2 uvMax);

            Vector3[] vtx = FaceVertices[face];
            // 反转顶点顺序，使三角形逆时针绕序，法线朝外
            int[] order = { 0, 2, 1, 0, 3, 2 };

            foreach (int i in order)
            {
                Vector3 local01 = vtx[i]; // 立方体局部坐标（0..1）
                Vector3 worldPos = basePos + local01 * size;
                Vector3 normal = FaceNormals[face];

                // 计算该面的本地 U/V（0..1）
                GetLocalUvForFace(face, local01, out float u, out float v);

                // 将 0..1 的 U/V 映射到 atlas 的 uvMin..uvMax
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

    // 为不同法线的面选择正确的两个轴，并做少量翻转以保持贴图方向一致
    private static void GetLocalUvForFace(int face, Vector3 p, out float u, out float v)
    {
        switch (face)
        {
            case 0: // +X 面：U=Z, V=Y
                u = p.Z; v = p.Y;
                break;
            case 1: // -X 面：U=1-Z, V=Y（水平翻转保证方向一致）
                u = 1f - p.Z; v = p.Y;
                break;
            case 2: // +Y 面：U=X, V=1-Z（让顶部看起来与 +Z 面方向一致）
                u = p.X; v = 1f - p.Z;
                break;
            case 3: // -Y 面：U=X, V=Z
                u = p.X; v = p.Z;
                break;
            case 4: // +Z 面：U=X, V=Y
                u = p.X; v = p.Y;
                break;
            case 5: // -Z 面：U=1-X, V=Y（水平翻转保证方向一致）
                u = 1f - p.X; v = p.Y;
                break;
            default:
                u = p.X; v = p.Y;
                break;
        }
    }
}

