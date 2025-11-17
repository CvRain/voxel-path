namespace VoxelPath.Scripts.Blocks;

/// <summary>
/// Defines the properties and appearance of a block type in the voxel world.
/// </summary>
public class BlockDefinition
{
    /// <summary>
    /// The type of the block (e.g., Dirt, Grass, Air).
    /// </summary>
    public BlockType Type;
    
    /// <summary>
    /// Indicates whether the block is opaque. Opaque blocks completely block light.
    /// </summary>
    public bool IsOpaque;
    
    /// <summary>
    /// Indicates whether the block can be subdivided into smaller voxels.
    /// </summary>
    public bool CanSubdivide;
    
    /// <summary>
    /// Indicates whether the block is transparent. This is the inverse of IsOpaque.
    /// </summary>
    public bool IsTransparent => !IsOpaque;
    
    /// <summary>
    /// Atlas indices for each face of the block cube.
    /// Order: +X, -X, +Y, -Y, +Z, -Z
    /// </summary>
    public int[] FaceAtlasIndices = new int[6];

    /// <summary>
    /// Constructor for blocks where all faces use the same texture.
    /// </summary>
    /// <param name="type">The type of the block.</param>
    /// <param name="opaque">Whether the block is opaque.</param>
    /// <param name="canSubdivide">Whether the block can be subdivided.</param>
    /// <param name="allFacesIndex">The texture atlas index used for all faces.</param>
    public BlockDefinition(BlockType type, bool opaque, bool canSubdivide, int allFacesIndex)
    {
        Type = type;
        IsOpaque = opaque;
        CanSubdivide = canSubdivide;
        for (var i = 0; i < 6; i++)
            FaceAtlasIndices[i] = allFacesIndex;
    }

    /// <summary>
    /// Constructor for blocks where each face can have a different texture.
    /// </summary>
    /// <param name="type">The type of the block.</param>
    /// <param name="opaque">Whether the block is opaque.</param>
    /// <param name="canSubdivide">Whether the block can be subdivided.</param>
    /// <param name="posX">Texture atlas index for the positive X face (+X).</param>
    /// <param name="negX">Texture atlas index for the negative X face (-X).</param>
    /// <param name="posY">Texture atlas index for the positive Y face (+Y).</param>
    /// <param name="negY">Texture atlas index for the negative Y face (-Y).</param>
    /// <param name="posZ">Texture atlas index for the positive Z face (+Z).</param>
    /// <param name="negZ">Texture atlas index for the negative Z face (-Z).</param>
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