using System.Linq;
using System.Threading.Tasks;
using Godot;
using VoxelPath.systems.blocks.data;
using VoxelPath.systems.blocks.loaders;
using VoxelPath.systems.blocks.registry;

namespace VoxelPath.systems.blocks.tests;

/// <summary>
/// BlockRegistry 单元测试
/// 测试注册表的各种功能
/// </summary>
public partial class BlockRegistryTests : Node
{
    public override void _Ready()
    {
        GD.Print("\n=== BlockRegistry Tests ===\n");
        RunAllTests();
    }

    private async void RunAllTests()
    {
        await TestNamespacedId();
        await TestBasicRegistration();
        await TestModConflict();
        await TestQueryMethods();
        await TestPersistence();
        await TestValidation();
        await TestIntegrationWithLoader();

        GD.Print("\n=== All Tests Passed ===\n");
    }

    /// <summary>
    /// 测试 1：NamespacedId 功能
    /// </summary>
    private async Task TestNamespacedId()
    {
        GD.Print("--- Test 1: NamespacedId ---");

        // 测试各种创建方式
        var id1 = new NamespacedId("stone");
        var id2 = new NamespacedId("voxelpath:stone");
        var id3 = new NamespacedId("voxelpath", "stone");

        // 应该全部相等
        if (id1 == id2 && id2 == id3)
        {
            GD.Print("✓ NamespacedId creation works");
        }
        else
        {
            GD.PrintErr("✗ NamespacedId equality failed");
        }

        // 测试命名空间分离
        var modId = new NamespacedId("mymod:copper_ore");
        if (modId.Namespace == "mymod" && modId.Path == "copper_ore")
        {
            GD.Print("✓ Namespace parsing works");
        }

        // 测试格式验证
        try
        {
            var invalid = new NamespacedId("Invalid:ID!");
            GD.PrintErr("✗ Should reject invalid ID format");
        }
        catch
        {
            GD.Print("✓ Invalid format rejected");
        }

        // 测试 TryParse
        if (NamespacedId.TryParse("voxelpath:dirt", out var parsedId))
        {
            GD.Print($"✓ TryParse works: {parsedId.FullId}");
        }

        await Task.CompletedTask;
    }

    /// <summary>
    /// 测试 2：基本注册功能
    /// </summary>
    private async Task TestBasicRegistration()
    {
        GD.Print("\n--- Test 2: Basic Registration ---");

        var registry = new BlockRegistry();
        AddChild(registry);
        await ToSignal(registry, Node.SignalName.Ready);

        // 测试注册
        var stone = BlockData.CreateSimple("stone", "石头", "");
        var stoneId = new NamespacedId("stone");
        var numericId = registry.Register(stoneId, stone);

        if (numericId > 0)
        {
            GD.Print($"✓ Registration successful: ID {numericId}");
        }

        // 测试重复注册
        var duplicate = registry.Register(stoneId, stone);
        if (duplicate == numericId)
        {
            GD.Print("✓ Duplicate registration handled");
        }

        // 测试查询
        var retrieved = registry.GetById(numericId);
        if (retrieved?.Name == "stone")
        {
            GD.Print("✓ Retrieval works");
        }

        registry.QueueFree();
    }

    /// <summary>
    /// 测试 3：模组冲突处理
    /// </summary>
    private async Task TestModConflict()
    {
        GD.Print("\n--- Test 3: Mod Conflict ---");

        var registry = new BlockRegistry();
        AddChild(registry);
        await ToSignal(registry, Node.SignalName.Ready);

        // 注册两个同名但不同命名空间的方块
        var mod1Copper = new NamespacedId("mod1:copper");
        var mod2Copper = new NamespacedId("mod2:copper");

        var data1 = BlockData.CreateSimple("copper", "铜（模组1）", "");
        var data2 = BlockData.CreateSimple("copper", "铜（模组2）", "");

        var id1 = registry.Register(mod1Copper, data1);
        var id2 = registry.Register(mod2Copper, data2);

        if (id1 != id2 && id1 > 0 && id2 > 0)
        {
            GD.Print($"✓ No conflict: mod1={id1}, mod2={id2}");
        }

        // 验证可以分别获取
        var retrieved1 = registry.GetByNamespacedId(mod1Copper);
        var retrieved2 = registry.GetByNamespacedId(mod2Copper);

        if (retrieved1?.DisplayName == "铜（模组1）" && retrieved2?.DisplayName == "铜（模组2）")
        {
            GD.Print("✓ Both blocks retrievable independently");
        }

        registry.QueueFree();
    }

    /// <summary>
    /// 测试 4：查询方法
    /// </summary>
    private async Task TestQueryMethods()
    {
        GD.Print("\n--- Test 4: Query Methods ---");

        var registry = new BlockRegistry();
        AddChild(registry);
        await ToSignal(registry, Node.SignalName.Ready);

        // 注册测试数据
        var dirt = BlockData.CreateSimple("dirt", "泥土", "");
        var dirtId = new NamespacedId("dirt");
        var numericId = registry.Register(dirtId, dirt);

        // 测试各种查询方式
        var byId = registry.GetById(numericId);
        var byNsId = registry.GetByNamespacedId(dirtId);
        var byString = registry.GetByString("voxelpath:dirt");

        if (byId == byNsId && byNsId == byString)
        {
            GD.Print("✓ All query methods return same block");
        }

        // 测试 Contains
        if (registry.Contains(dirtId))
        {
            GD.Print("✓ Contains check works");
        }

        // 测试 GetNamespaces
        var namespaces = registry.GetNamespaces();
        var hasVoxelpath = false;
        foreach (var ns in namespaces)
        {
            if (ns == "voxelpath")
            {
                hasVoxelpath = true;
                break;
            }
        }

        if (hasVoxelpath)
        {
            GD.Print($"✓ Namespaces: {string.Join(", ", namespaces)}");
        }

        registry.QueueFree();
    }

    /// <summary>
    /// 测试 5：持久化
    /// </summary>
    private async Task TestPersistence()
    {
        GD.Print("\n--- Test 5: Persistence ---");

        var registry1 = new BlockRegistry();
        AddChild(registry1);
        await ToSignal(registry1, Node.SignalName.Ready);

        // 注册一些方块
        var grass = BlockData.CreateSimple("grass", "草方块", "");
        var grassId = new NamespacedId("grass");
        var originalId = registry1.Register(grassId, grass);

        // 保存映射
        var savePath = "user://test_mappings.json";
        registry1.SaveMappings(savePath);
        var originalNextId = registry1.NextId;

        registry1.QueueFree();

        // 创建新注册表并加载
        var registry2 = new BlockRegistry();
        AddChild(registry2);
        await ToSignal(registry2, Node.SignalName.Ready);

        registry2.LoadMappings(savePath);

        // 验证恢复
        var restoredNumericId = registry2.GetNumericId(grassId);

        if (restoredNumericId == originalId && registry2.NextId == originalNextId)
        {
            GD.Print("✓ Persistence works correctly");
        }
        else
        {
            GD.PrintErr($"✗ Persistence failed: {restoredNumericId} vs {originalId}");
        }

        registry2.QueueFree();
    }

    /// <summary>
    /// 测试 6：验证功能
    /// </summary>
    private async Task TestValidation()
    {
        GD.Print("\n--- Test 6: Validation ---");

        var registry = new BlockRegistry();
        AddChild(registry);
        await ToSignal(registry, Node.SignalName.Ready);

        // 注册一些方块
        var sand = BlockData.CreateSimple("sand", "沙子", "");
        registry.Register(new NamespacedId("sand"), sand);

        // 验证完整性
        if (registry.ValidateIntegrity())
        {
            GD.Print("✓ Integrity validation passed");
        }

        // 测试无效方块拒绝
        var invalid = new BlockData { Name = "" }; // 无效：名称为空
        var result = registry.Register(new NamespacedId("invalid"), invalid);

        if (result == -1)
        {
            GD.Print("✓ Invalid block rejected");
        }

        registry.QueueFree();
    }

    /// <summary>
    /// 测试 7：与 BlockDataLoader 集成
    /// </summary>
    private async Task TestIntegrationWithLoader()
    {
        GD.Print("\n--- Test 7: Integration with Loader ---");

        var loader = new BlockDataLoader();
        var registry = new BlockRegistry();

        AddChild(loader);
        AddChild(registry);

        await ToSignal(registry, Node.SignalName.Ready);

        try
        {
            // 加载方块数据
            var blocks = await loader.LoadAllBlocksAsync("res://old/Data/blocks/_manifest.json");

            if (blocks.Count > 0)
            {
                GD.Print($"✓ Loaded {blocks.Count} blocks from JSON");

                // 注册所有方块
                var registered = 0;
                foreach (var block in blocks)
                {
                    // 使用方块的 Name 创建 NamespacedId
                    var nsId = new NamespacedId(block.Name);
                    if (registry.Register(nsId, block) > 0)
                        registered++;
                }

                GD.Print($"✓ Registered {registered}/{blocks.Count} blocks");

                // 验证可以查询
                var testBlock = registry.GetByString("voxelpath:stone");
                if (testBlock != null)
                {
                    GD.Print($"✓ Can query registered block: {testBlock.DisplayName}");
                }

                // 打印统计
                registry.PrintRegistry();
            }
        }
        catch (System.Exception ex)
        {
            GD.PrintErr($"✗ Integration test failed: {ex.Message}");
        }
        finally
        {
            loader.QueueFree();
            registry.QueueFree();
        }
    }
}
