using System.Collections.Generic;

namespace TryWorld.Scripts.Blocks;

public static class BlockRegistry
{
    // 纹理顺序（可根据需要改成真正打包的 atlas 排列）
    // 例如 atlas 排列：
    // 0: dirt.png
    // 1: grass.png (顶)
    // 2: log.png
    // 3: leaf.png
    // 将来可增加 grass_side.png 等
    public static readonly Dictionary<BlockType, BlockDefinition> Definitions = new();

    public static void Init()
    {
        if (Definitions.Count > 0) return;

        Definitions[BlockType.Air] = new BlockDefinition(BlockType.Air, opaque:false, canSubdivide:false, allFacesIndex:0);

        // Dirt（全部 dirt.png -> atlas index 0）
        Definitions[BlockType.Dirt] = new BlockDefinition(BlockType.Dirt, opaque:true, canSubdivide:true, allFacesIndex:0);

        // Grass：顶部 grass(1)，底部 dirt(0)，侧面暂用 dirt(0)
          Definitions[BlockType.Grass] = new BlockDefinition(
            BlockType.Grass,
            opaque:true,
            canSubdivide:true,
            posX:0, negX:0, posY:1, negY:0, posZ:0, negZ:0
        );

        // Log：全部 log.png(index 2)（以后可区分端面和侧面）
        Definitions[BlockType.Log] = new BlockDefinition(BlockType.Log, opaque:true, canSubdivide:true, allFacesIndex:2);

        // Leaf：使用 leaf.png(index 3)，半透明
        Definitions[BlockType.Leaf] = new BlockDefinition(BlockType.Leaf, opaque:false, canSubdivide:true, allFacesIndex:3);
    }

    public static BlockDefinition Get(BlockType type) => Definitions[type];
}