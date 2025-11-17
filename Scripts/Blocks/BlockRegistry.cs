using System.Collections.Generic;

namespace VoxelPath.Scripts.Blocks;

public static class BlockRegistry
{
    // 纹理顺序（atlas 排列）:
    // 0: dirt.png
    // 1: grass_block_top.png (染色后)
    // 2: grass_block_side.png
    // 3: grass_block_side_overlay.png (染色后)
    // 4: oak_log.png (侧面)
    // 5: oak_log_top.png (顶部和底部)
    // 6: oak_leaves.png (染色后)
    public static readonly Dictionary<BlockType, BlockDefinition> Definitions = new();

    public static void Init()
    {
        if (Definitions.Count > 0) return;

        // Air - 空气方块
        Definitions[BlockType.Air] = new BlockDefinition(
            BlockType.Air,
            opaque: false,
            canSubdivide: false,
            allFacesIndex: 0
        );

        // Dirt - 泥土（全部使用 dirt.png，atlas index 0）
        Definitions[BlockType.Dirt] = new BlockDefinition(
            BlockType.Dirt,
            opaque: true,
            canSubdivide: true,
            allFacesIndex: 0
        );

        // Grass - 草方块
        // 顶部(+Y): grass_block_top.png (index 1)
        // 底部(-Y): dirt.png (index 0)
        // 四个侧面: grass_block_side.png (index 2) + grass_block_side_overlay.png (index 3)
        // 注意：这里先使用简单的单层贴图，如需叠加效果需要在着色器中处理
        Definitions[BlockType.Grass] = new BlockDefinition(
            BlockType.Grass,
            opaque: true,
            canSubdivide: true,
            posX: 2,  // 右侧面
            negX: 2,  // 左侧面
            posY: 1,  // 顶部（草地）
            negY: 0,  // 底部（泥土）
            posZ: 2,  // 前侧面
            negZ: 2   // 后侧面
        );

        // OakLog - 橡木原木
        // 顶部和底部(+Y, -Y): oak_log_top.png (index 5)
        // 四个侧面: oak_log.png (index 4)
        Definitions[BlockType.OakLog] = new BlockDefinition(
            BlockType.OakLog,
            opaque: true,
            canSubdivide: true,
            posX: 4,  // 右侧面
            negX: 4,  // 左侧面
            posY: 5,  // 顶部
            negY: 5,  // 底部
            posZ: 4,  // 前侧面
            negZ: 4   // 后侧面
        );

        // OakLeaves - 橡木树叶（使用染色后的 oak_leaves.png，index 6）
        // 树叶是半透明的
        Definitions[BlockType.OakLeaves] = new BlockDefinition(
            BlockType.OakLeaves,
            opaque: false,
            canSubdivide: true,
            allFacesIndex: 6
        );
    }

    public static BlockDefinition Get(BlockType type) => Definitions[type];
}