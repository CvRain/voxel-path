namespace TryWorld.Scripts.Blocks;

public class MacroBlockData
{
    public ushort BlockId;
    public MicroBlockData Micro; // 细分后不为空

    public bool IsSubdivided => Micro != null;

    public MacroBlockData(ushort blockId)
    {
        BlockId = blockId;
    }

    public void Subdivide()
    {
        if (IsSubdivided) return;
        Micro = new MicroBlockData((byte)BlockId);
    }

    public void TryCollapse()
    {
        if (!IsSubdivided) return;
        if (Micro.IsUniform(out byte uniformType))
        {
            BlockId = uniformType;
            Micro = null;
        }
    }
}