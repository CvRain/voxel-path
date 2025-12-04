using Godot;
using VoxelPath.systems.blocks.data;
using VoxelPath.systems.blocks.registry;

namespace VoxelPath.systems.blocks.examples;

/// <summary>
/// BlockRegistry 使用示例
/// 演示如何注册和查询方块，以及命名空间的使用
/// </summary>
public partial class BlockRegistryExample : Node
{
    private BlockRegistry _registry;

    public override void _Ready()
    {
        GD.Print("\n=== BlockRegistry Example ===\n");

        // 创建注册表
        _registry = new BlockRegistry();
        AddChild(_registry);

        // 等待 _Ready 执行（注册空气方块）
        CallDeferred(nameof(RunExamples));
    }

    private void RunExamples()
    {
        Example1_BasicRegistration();
        Example2_NamespacedIds();
        Example3_ModConflict();
        Example4_QueryMethods();
        Example5_Persistence();
        Example6_Validation();

        GD.Print("\n=== All Examples Complete ===\n");
    }

    /// <summary>
    /// 示例 1：基本注册
    /// </summary>
    private void Example1_BasicRegistration()
    {
        GD.Print("--- Example 1: Basic Registration ---");

        // 创建方块数据
        var stone = BlockData.CreateSimple(
            name: "stone",
            displayName: "石头",
            texturePath: "res://textures/stone.png"
        );

        stone.Hardness = 5.0f;
        stone.ToolRequiredInt = 1; // Pickaxe

        // 注册方块（使用默认命名空间 "voxelpath"）
        var stoneId = new NamespacedId("stone"); // 等同于 "voxelpath:stone"
        var numericId = _registry.Register(stoneId, stone);

        GD.Print($"✓ Registered stone with ID: {numericId}");
        GD.Print($"✓ Full ID: {stoneId.FullId}");
    }

    /// <summary>
    /// 示例 2：使用命名空间
    /// </summary>
    private void Example2_NamespacedIds()
    {
        GD.Print("\n--- Example 2: Namespaced IDs ---");

        // 方式 1：从完整 ID 字符串创建
        var oakLog = new NamespacedId("voxelpath:oak_log");

        // 方式 2：指定命名空间和路径
        var birchLog = new NamespacedId("voxelpath", "birch_log");

        // 方式 3：省略命名空间（使用默认）
        var spruceLog = new NamespacedId("spruce_log");

        GD.Print($"Oak: {oakLog.FullId} (namespace: {oakLog.Namespace}, path: {oakLog.Path})");
        GD.Print($"Birch: {birchLog.FullId}");
        GD.Print($"Spruce: {spruceLog.FullId}");

        // 注册这些方块
        var oakData = BlockData.CreateSimple("oak_log", "橡木原木", "");
        var birchData = BlockData.CreateSimple("birch_log", "白桦原木", "");
        var spruceData = BlockData.CreateSimple("spruce_log", "云杉原木", "");

        _registry.Register(oakLog, oakData);
        _registry.Register(birchLog, birchData);
        _registry.Register(spruceLog, spruceData);

        GD.Print("✓ All logs registered");
    }

    /// <summary>
    /// 示例 3：模组冲突处理
    /// </summary>
    private void Example3_ModConflict()
    {
        GD.Print("\n--- Example 3: Mod Conflict Handling ---");

        // 场景：两个科技模组都有铜矿
        var techModCopper = new NamespacedId("techmod:copper_ore");
        var magicModCopper = new NamespacedId("magicmod:copper_ore");

        var techData = BlockData.CreateSimple("copper_ore", "铜矿石（科技）", "");
        techData.Description = "来自科技模组的铜矿";

        var magicData = BlockData.CreateSimple("copper_ore", "铜矿石（魔法）", "");
        magicData.Description = "来自魔法模组的铜矿";

        var techId = _registry.Register(techModCopper, techData);
        var magicId = _registry.Register(magicModCopper, magicData);

        GD.Print($"Tech Mod Copper: {techModCopper} → ID {techId}");
        GD.Print($"Magic Mod Copper: {magicModCopper} → ID {magicId}");
        GD.Print("✓ Both copper ores registered successfully (no conflict!)");

        // 注意：BlockData.Name 相同但不冲突，因为命名空间不同
        GD.Print($"Tech copper name: {techData.Name}");
        GD.Print($"Magic copper name: {magicData.Name}");
    }

    /// <summary>
    /// 示例 4：查询方法
    /// </summary>
    private void Example4_QueryMethods()
    {
        GD.Print("\n--- Example 4: Query Methods ---");

        // 方法 1：通过数字 ID 查询（最快）
        var block1 = _registry.GetById(1);
        GD.Print($"By numeric ID (1): {block1?.DisplayName}");

        // 方法 2：通过 NamespacedId 查询
        var stoneId = new NamespacedId("stone");
        var block2 = _registry.GetByNamespacedId(stoneId);
        GD.Print($"By NamespacedId: {block2?.DisplayName}");

        // 方法 3：通过字符串查询
        var block3 = _registry.GetByString("voxelpath:oak_log");
        GD.Print($"By string: {block3?.DisplayName}");

        // 检查是否存在
        var exists = _registry.Contains(new NamespacedId("stone"));
        GD.Print($"Stone exists: {exists}");

        // 获取所有命名空间
        var namespaces = _registry.GetNamespaces();
        GD.Print($"Namespaces: {string.Join(", ", namespaces)}");

        // 获取特定命名空间的所有方块
        var voxelpathBlocks = _registry.GetBlocksInNamespace("voxelpath");
        GD.Print($"Voxelpath blocks: {voxelpathBlocks.Count}");
    }

    /// <summary>
    /// 示例 5：持久化
    /// </summary>
    private void Example5_Persistence()
    {
        GD.Print("\n--- Example 5: Persistence ---");

        // 保存 ID 映射
        var savePath = "user://block_mappings.json";
        _registry.SaveMappings(savePath);
        GD.Print($"✓ Mappings saved to: {savePath}");

        // 模拟重新加载
        var newRegistry = new BlockRegistry();
        AddChild(newRegistry);

        newRegistry.LoadMappings(savePath);
        GD.Print($"✓ Mappings loaded, next ID: {newRegistry.NextId}");

        // 验证映射恢复
        var restoredId = newRegistry.GetNumericId(new NamespacedId("stone"));
        GD.Print($"Restored stone ID: {restoredId}");

        newRegistry.QueueFree();
    }

    /// <summary>
    /// 示例 6：验证和调试
    /// </summary>
    private void Example6_Validation()
    {
        GD.Print("\n--- Example 6: Validation & Debug ---");

        // 打印注册表内容
        _registry.PrintRegistry();

        // 验证完整性
        var isValid = _registry.ValidateIntegrity();
        GD.Print($"Registry valid: {isValid}");

        // 获取统计信息
        GD.Print($"Total blocks: {_registry.Count}");
        GD.Print($"Next available ID: {_registry.NextId}");
    }
}
