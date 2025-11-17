using System.Collections.Generic;

namespace VoxelPath.Scripts.Blocks;

public static class BlockRegistry
{
    // 纹理顺序（atlas 排列）:
    // 0: dirt.png
    // 1: grass_block_top.png (染色后)
    // 2: grass_block_side.png (染色后)
    // 3: grass_block_side_overlay.png (染色后)
    // 4: oak_log.png (侧面)
    // 5: oak_log_top.png (顶部和底部)
    // 6: oak_leaves.png (染色后)
    // 7: stone.png
    // 8: cobblestone.png
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
            allFacesIndex: 0,
            useRandomSubtiles: true
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
            posX: 2,
            negX: 2,
            posY: 1,
            negY: 0,
            posZ: 2,
            negZ: 2,
            useRandomSubtiles: true
        );

        // GrassFull - 全草方块（六面同草顶纹理）
        Definitions[BlockType.GrassFull] = new BlockDefinition(
            BlockType.GrassFull,
            opaque: true,
            canSubdivide: true,
            allFacesIndex: 1,
            useRandomSubtiles: true
        );

        // Stone - 石头
        Definitions[BlockType.Stone] = new BlockDefinition(
            BlockType.Stone,
            opaque: true,
            canSubdivide: true,
            allFacesIndex: 7,
            useRandomSubtiles: true
        );

        // Cobblestone - 圆石
        Definitions[BlockType.Cobblestone] = new BlockDefinition(
            BlockType.Cobblestone,
            opaque: true,
            canSubdivide: true,
            allFacesIndex: 8,
            useRandomSubtiles: true
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
            allFacesIndex: 6,
            useRandomSubtiles: true
        );

        // Debug - 调试用方块
        // 使用已有贴图集中 0~5 的索引，让每个面都不一样：
        // +X: dirt(0), -X: grass_top(1), +Y: grass_side(2), -Y: grass_side_overlay(3), +Z: oak_log(4), -Z: oak_log_top(5)
        Definitions[BlockType.Debug] = new BlockDefinition(
            BlockType.Debug,
            opaque: true,
            canSubdivide: false,
            posX: 0,
            negX: 1,
            posY: 2,
            negY: 3,
            posZ: 4,
            negZ: 5
        );
    }

    public static BlockDefinition Get(BlockType type) => Definitions[type];
}