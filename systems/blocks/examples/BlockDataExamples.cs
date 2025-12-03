using Godot;
using VoxelPath.systems.blocks.data;
using VoxelPath.systems.world_settings;

namespace VoxelPath.systems.blocks.examples;

/// <summary>
/// BlockData 使用示例
/// 展示如何优雅地创建和使用方块数据
/// </summary>
public static class BlockDataExamples
{
    #region 示例 1: 使用工厂方法创建简单方块

    /// <summary>
    /// 创建石头方块 - 所有面使用相同纹理
    /// 这是最常见的方块类型
    /// </summary>
    public static BlockData CreateStoneBlock()
    {
        var stone = BlockData.CreateSimple(
            name: "stone",
            displayName: "石头",
            texturePath: "res://Assets/Textures/blocks/stone.png"
        );

        // 设置物理属性
        stone.Hardness = 1.5f;
        stone.Resistance = 6.0f;
        stone.ToolRequired = IWorldItemCategory.ToolCategory.Pickaxe;
        stone.MineLevel = 1; // 需要木镐及以上

        return stone;
    }

    #endregion

    #region 示例 2: 创建定向方块（原木）

    /// <summary>
    /// 创建橡木原木 - 顶部、底部、侧面使用不同纹理
    /// </summary>
    public static BlockData CreateOakLogBlock()
    {
        var log = BlockData.CreateDirectional(
            name: "oak_log",
            displayName: "橡木原木",
            topTexture: "res://Assets/Textures/blocks/oak_log_top.png",
            bottomTexture: "res://Assets/Textures/blocks/oak_log_top.png",
            sideTexture: "res://Assets/Textures/blocks/oak_log_side.png"
        );

        log.Hardness = 2.0f;
        log.ToolRequired = IWorldItemCategory.ToolCategory.Axe;

        return log;
    }

    #endregion

    #region 示例 3: 手动构造复杂方块

    /// <summary>
    /// 创建熔炉方块 - 完全自定义每个面的纹理
    /// </summary>
    public static BlockData CreateFurnaceBlock()
    {
        var furnace = new BlockData
        {
            Name = "furnace",
            DisplayName = "熔炉",
            Description = "用于冶炼矿石和烹饪食物",
            Category = "machines",

            // 每个面使用不同纹理
            TextureTop = "res://Assets/Textures/blocks/furnace_top.png",
            TextureBottom = "res://Assets/Textures/blocks/furnace_top.png",
            TextureNorth = "res://Assets/Textures/blocks/furnace_front.png",  // 前面（有门）
            TextureSouth = "res://Assets/Textures/blocks/furnace_side.png",
            TextureEast = "res://Assets/Textures/blocks/furnace_side.png",
            TextureWest = "res://Assets/Textures/blocks/furnace_side.png",

            // 物理属性
            Hardness = 3.5f,
            Resistance = 3.5f,
            ToolRequired = IWorldItemCategory.ToolCategory.Pickaxe,

            // 方块状态定义（JSON格式）
            StateDefinitionsJson = @"{
                ""facing"": [""north"", ""south"", ""east"", ""west""],
                ""lit"": [true, false]
            }",
            DefaultStateJson = @"{
                ""facing"": ""north"",
                ""lit"": false
            }",

            // 自定义属性
            CustomPropertiesJson = @"{
                ""inventorySlots"": 3,
                ""maxFuelBurnTime"": 1600
            }"
        };

        return furnace;
    }

    #endregion

    #region 示例 4: 透明/发光方块

    /// <summary>
    /// 创建萤石方块 - 发光且稍微透明
    /// </summary>
    public static BlockData CreateGlowstoneBlock()
    {
        var glowstone = BlockData.CreateSimple(
            name: "glowstone",
            displayName: "萤石",
            texturePath: "res://Assets/Textures/blocks/glowstone.png"
        );

        // 发光属性
        glowstone.IsEmissive = true;
        glowstone.EmissionStrength = 1.0f;

        // 轻微透明
        glowstone.IsTransparent = true;
        glowstone.Opacity = 0.95f;

        glowstone.Hardness = 0.3f;

        return glowstone;
    }

    #endregion

    #region 示例 5: 不可破坏方块

    /// <summary>
    /// 创建基岩 - 完全不可破坏
    /// </summary>
    public static BlockData CreateBedrockBlock()
    {
        return BlockData.CreateIndestructible(
            name: "bedrock",
            displayName: "基岩",
            texturePath: "res://Assets/Textures/blocks/bedrock.png"
        );
    }

    #endregion

    #region 示例 6: 从 Godot Resource 文件加载

    /// <summary>
    /// 从 .tres 文件加载方块数据
    /// 推荐用于生产环境 - 在编辑器中可视化编辑
    /// </summary>
    public static BlockData LoadFromResource(string resourcePath)
    {
        var blockData = GD.Load<BlockData>(resourcePath);

        if (blockData == null)
        {
            GD.PushError($"无法加载方块数据: {resourcePath}");
            return null;
        }

        // 验证数据有效性
        if (!blockData.Validate())
        {
            GD.PushWarning($"方块数据验证失败: {resourcePath}");
        }

        return blockData;
    }

    #endregion

    #region 示例 7: 批量创建方块注册表

    /// <summary>
    /// 批量创建基础方块集合
    /// 实际项目中可以从 JSON 或 YAML 配置文件读取
    /// </summary>
    public static BlockData[] CreateBasicBlocks()
    {
        // 泥土
        var dirt = BlockData.CreateSimple("dirt", "泥土", "res://Assets/Textures/blocks/dirt.png");
        dirt.Hardness = 0.5f;
        dirt.ToolRequired = IWorldItemCategory.ToolCategory.Shovel;

        // 草方块
        var grassBlock = BlockData.CreateDirectional(
            "grass_block",
            "草方块",
            "res://Assets/Textures/blocks/grass_top.png",
            "res://Assets/Textures/blocks/dirt.png",
            "res://Assets/Textures/blocks/grass_side.png"
        );
        grassBlock.Hardness = 0.6f;
        grassBlock.ToolRequired = IWorldItemCategory.ToolCategory.Shovel;

        return new[]
        {
            CreateStoneBlock(),
            CreateOakLogBlock(),
            CreateFurnaceBlock(),
            CreateGlowstoneBlock(),
            CreateBedrockBlock(),
            dirt,
            grassBlock
        };
    }

    #endregion

    #region 示例 8: 使用属性的高级技巧

    /// <summary>
    /// 展示如何访问和使用 BlockData 的各种属性
    /// </summary>
    public static void DemonstrateBlockDataUsage()
    {
        var furnace = CreateFurnaceBlock();

        // 1. 访问基本属性
        GD.Print($"方块名称: {furnace.DisplayName}");
        GD.Print($"方块ID: {furnace.Id}");
        GD.Print($"分类: {furnace.Category}");

        // 2. 使用高性能纹理路径访问
        var texturePaths = furnace.TexturePaths;
        GD.Print($"北面纹理: {texturePaths.GetPath(WorldDirection.BaseDirection.North)}");
        GD.Print($"顶面纹理: {texturePaths.Top}");

        // 3. 检查物理属性
        if (furnace.HasCollision)
        {
            GD.Print($"硬度: {furnace.Hardness}");
            GD.Print($"需要工具: {furnace.ToolRequired}");
        }

        // 4. 验证数据
        if (furnace.Validate())
        {
            GD.Print("方块数据有效 ✓");
        }

        // 5. 访问状态定义（需要先解析 JSON）
        // 实际使用中，这应该由 BlockRegistry 自动处理
        GD.Print($"状态定义: {furnace.StateDefinitionsJson}");
        GD.Print($"默认状态: {furnace.DefaultStateJson}");
    }

    #endregion

    #region 学习要点总结

    /*
     * ======================================
     * 优雅代码的关键要素
     * ======================================
     * 
     * 1. 关注点分离 (Separation of Concerns)
     *    - BlockData 只负责存储配置数据
     *    - 不包含业务逻辑（如渲染、碰撞检测）
     *    - 纹理路径 vs 纹理资源分离
     *    
     * 2. 数据验证 (Data Validation)
     *    - Validate() 方法确保数据完整性
     *    - 提供有意义的错误信息
     *    - 在加载时就发现问题，而非运行时崩溃
     *    
     * 3. 工厂模式 (Factory Pattern)
     *    - CreateSimple(), CreateDirectional() 等
     *    - 隐藏复杂的构造细节
     *    - 提供语义清晰的 API
     *    
     * 4. 类型安全 (Type Safety)
     *    - 使用 enum (ToolType) 而非 string
     *    - 使用 struct (BlockTexturePaths) 提高性能
     *    - 编译时检查，减少运行时错误
     *    
     * 5. 灵活性 vs 便捷性 (Flexibility vs Convenience)
     *    - 提供工厂方法满足 80% 的常见需求
     *    - 同时支持完全自定义构造
     *    - JSON 字段用于编辑器，强类型属性用于代码
     *    
     * 6. 性能优化 (Performance)
     *    - struct 而非 Dictionary（50倍速度提升）
     *    - 只存储路径，延迟加载纹理
     *    - 使用 partial class 支持代码生成
     *    
     * 7. Godot 集成 (Godot Integration)
     *    - 继承 Resource 以支持序列化
     *    - 使用 [Export] 在编辑器中编辑
     *    - PropertyHint 提供更好的编辑体验
     *    - [GlobalClass] 使其在整个项目可见
     *    
     * 8. 文档化 (Documentation)
     *    - /// 注释生成 IntelliSense
     *    - 每个属性都有清晰的说明
     *    - 提供使用示例
     */

    #endregion
}
