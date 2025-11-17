using Godot;

namespace VoxelPath.Scripts.Blocks;

public static class ChunkMesher
{
    private static readonly Vector3[] FaceNormals =
    [
        Vector3.Right, Vector3.Left,
        Vector3.Up, Vector3.Down,
        Vector3.Forward, Vector3.Back
    ];

    private static readonly Vector3[][] FaceVertices =
    [
        [new Vector3(1, 0, 0), new Vector3(1, 1, 0), new Vector3(1, 1, 1), new Vector3(1, 0, 1)], // +X
        [new Vector3(0, 0, 1), new Vector3(0, 1, 1), new Vector3(0, 1, 0), new Vector3(0, 0, 0)], // -X
        [new Vector3(0, 1, 0), new Vector3(1, 1, 0), new Vector3(1, 1, 1), new Vector3(0, 1, 1)], // +Y
        [new Vector3(0, 0, 1), new Vector3(1, 0, 1), new Vector3(1, 0, 0), new Vector3(0, 0, 0)], // -Y
        [new Vector3(0, 0, 1), new Vector3(0, 1, 1), new Vector3(1, 1, 1), new Vector3(1, 0, 1)], // +Z
        [new Vector3(1, 0, 0), new Vector3(1, 1, 0), new Vector3(0, 1, 0), new Vector3(0, 0, 0)] // -Z
    ];

    private static readonly int[] TriangleOrder = { 0, 1, 2, 0, 2, 3 };

    public static Mesh BuildMesh(Chunk chunk, BlockAtlas atlas, Material opaqueMaterial, Material transparentMaterial)
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
                    var block = chunk.Get(x, y, z);
                    if (block == null) continue;
                    if ((BlockType)block.BlockId == BlockType.Air) continue;

                    var def = BlockRegistry.Get((BlockType)block.BlockId);
                    var st = def.IsTransparent ? stTransparent : stOpaque;

                    if (!block.IsSubdivided)
                    {
                        AddMacroBlock(st, atlas, chunk, x, y, z, block);
                    }
                    else
                    {
                        for (int mx = 0; mx < 4; mx++)
                            for (int my = 0; my < 4; my++)
                                for (int mz = 0; mz < 4; mz++)
                                {
                                    if (!block.Micro.Has(mx, my, mz)) continue;
                                    byte t = block.Micro.Types[MicroBlockData.ToIndex(mx, my, mz)];
                                    var microDef = BlockRegistry.Get((BlockType)t);
                                    var microSt = microDef.IsTransparent ? stTransparent : stOpaque;
                                    Vector3 basePos = new Vector3(x, y, z) + new Vector3(mx, my, mz) * 0.25f;
                                    AddCube(microSt, atlas, basePos, 0.25f, microDef, null);
                                }
                    }
                }

        stOpaque.GenerateNormals();
        arrayMesh = stOpaque.Commit();

        stTransparent.GenerateNormals();
        stTransparent.Commit(arrayMesh);

        return arrayMesh;
    }

    private static void AddMacroBlock(SurfaceTool st, BlockAtlas atlas, Chunk chunk, int x, int y, int z,
        MacroBlockData block)
    {
        var def = BlockRegistry.Get((BlockType)block.BlockId);
        AddCube(st, atlas, new Vector3(x, y, z), 1f, def, face => ShouldDrawFace(chunk, x, y, z, face, def));
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

        if (nx < 0 || nx >= Chunk.SizeX || ny < 0 || ny >= Chunk.SizeY || nz < 0 || nz >= Chunk.SizeZ)
            return true;

        var neighbor = chunk.Get(nx, ny, nz);
        if (neighbor == null) return true;
        var neighborType = (BlockType)neighbor.BlockId;
        if (neighborType == BlockType.Air) return true;

        var neighborDef = BlockRegistry.Get(neighborType);
        if (neighborDef.IsTransparent) return true;
        if (def.IsTransparent && neighborType != def.Type) return true;

        return false;
    }

    private static void AddCube(SurfaceTool st, BlockAtlas atlas, Vector3 basePos, float size,
        BlockDefinition def, System.Func<int, bool> shouldDrawFace)
    {
        for (int face = 0; face < 6; face++)
        {
            if (shouldDrawFace != null && !shouldDrawFace(face))
                continue;

            int atlasIndex = def.FaceAtlasIndices[face];
            atlas.GetTileUv(atlasIndex, out Vector2 uvMin, out Vector2 uvMax);

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
            case 0: // +X
                u = p.Z;
                v = p.Y;
                break;
            case 1: // -X
                u = 1f - p.Z;
                v = p.Y;
                break;
            case 2: // +Y (Top)
                u = p.X;
                v = 1f - p.Z;
                break;
            case 3: // -Y (Bottom)
                u = p.X;
                v = p.Z;
                break;
            case 4: // +Z (Front)
                u = p.X;
                v = p.Y;
                break;
            case 5: // -Z (Back)
                u = 1f - p.X;
                v = p.Y;
                break;
            default:
                u = p.X;
                v = p.Y;
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
}