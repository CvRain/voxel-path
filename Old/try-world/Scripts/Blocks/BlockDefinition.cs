using System.Collections.Generic;

namespace TryWorld.Scripts.Blocks;

public class BlockDefinition
{
    public BlockType Type;
    public bool IsOpaque;
    public bool CanSubdivide;
    public bool IsTransparent => !IsOpaque;
    // 每个面的 atlas 索引：顺序 +X -X +Y -Y +Z -Z
    public int[] FaceAtlasIndices = new int[6];

    public BlockDefinition(BlockType type, bool opaque, bool canSubdivide, int allFacesIndex)
    {
        Type = type;
        IsOpaque = opaque;
        CanSubdivide = canSubdivide;
        for (int i = 0; i < 6; i++)
            FaceAtlasIndices[i] = allFacesIndex;
    }

    public BlockDefinition(BlockType type, bool opaque, bool canSubdivide, int posX, int negX, int posY, int negY, int posZ, int negZ)
    {
        Type = type;
        IsOpaque = opaque;
        CanSubdivide = canSubdivide;
        FaceAtlasIndices[0] = posX;
        FaceAtlasIndices[1] = negX;
        FaceAtlasIndices[2] = posY;
        FaceAtlasIndices[3] = negY;
        FaceAtlasIndices[4] = posZ;
        FaceAtlasIndices[5] = negZ;
    }
}