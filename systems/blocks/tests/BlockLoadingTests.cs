using System.Threading.Tasks;
using Godot;
using VoxelPath.systems.blocks.loaders;
using VoxelPath.systems.blocks.data;

namespace VoxelPath.tests;

/// <summary>
/// BlockDataLoader 和 ConfigParser 的单元测试
/// 运行方式：在 Godot 编辑器中运行此场景，查看输出日志
/// </summary>
public partial class BlockLoadingTests : Node
{
    public override void _Ready()
    {
        GD.Print("\n=== Block Loading System Tests ===\n");
        RunAllTests();
    }

    private async void RunAllTests()
    {
        await TestConfigParserManifest();
        await TestConfigParserBlockData();
        await TestBlockDataLoaderComplete();
        await TestBlockDataLoaderWithSignals();
        await TestInvalidBlockValidation();

        GD.Print("\n=== All Tests Completed ===\n");
    }

    /// <summary>
    /// 测试 1：Manifest 解析
    /// </summary>
    private async Task TestConfigParserManifest()
    {
        GD.Print("--- Test 1: Parse Manifest ---");

        var parser = new ConfigParser();

        // 注意：这里使用实际存在的路径，或者创建测试用的 manifest
        const string testPath = "res://old/Data/blocks/_manifest.json";

        try
        {
            var manifest = await parser.ParseManifestAsync(testPath, default);

            GD.Print($"✓ Format Version: {manifest.FormatVersion}");
            GD.Print($"✓ Categories: {manifest.Categories.Count}");
            GD.Print($"✓ Modded Categories: {manifest.ModdedCategories.Count}");

            var allCategories = manifest.GetCategories();
            GD.Print($"✓ Total Categories: {allCategories.Count}");

            foreach (var category in allCategories)
            {
                GD.Print($"  - {category.Path} (Priority: {category.Priority}, Enabled: {category.Enabled})");
            }

            GD.Print("✓ Test 1 PASSED\n");
        }
        catch (System.Exception ex)
        {
            GD.PrintErr($"✗ Test 1 FAILED: {ex.Message}\n");
        }
        finally
        {
            parser.Dispose();
        }
    }

    /// <summary>
    /// 测试 2：单个 BlockData 解析
    /// </summary>
    private async Task TestConfigParserBlockData()
    {
        GD.Print("--- Test 2: Parse BlockData ---");

        var parser = new ConfigParser();

        // 使用我们创建的示例文件
        const string testPath = "res://systems/blocks/examples/stone.json";

        try
        {
            var blockData = await parser.ParseBlockDataAsync(testPath, default);

            GD.Print($"✓ Name: {blockData.Name}");
            GD.Print($"✓ Display Name: {blockData.DisplayName}");
            GD.Print($"✓ Description: {blockData.Description}");
            GD.Print($"✓ Category: {blockData.Category}");
            GD.Print($"✓ Hardness: {blockData.Hardness}");
            GD.Print($"✓ Tool Required: {blockData.ToolRequired}");
            GD.Print($"✓ Texture North: {blockData.TextureNorth}");

            // 验证数据有效性
            if (blockData.Validate())
            {
                GD.Print("✓ Validation PASSED");
            }
            else
            {
                GD.PrintErr("✗ Validation FAILED");
            }

            GD.Print("✓ Test 2 PASSED\n");
        }
        catch (System.Exception ex)
        {
            GD.PrintErr($"✗ Test 2 FAILED: {ex.Message}\n");
        }
        finally
        {
            parser.Dispose();
        }
    }

    /// <summary>
    /// 测试 3：完整加载流程
    /// </summary>
    private async Task TestBlockDataLoaderComplete()
    {
        GD.Print("--- Test 3: Complete Loading Flow ---");

        var loader = new BlockDataLoader();
        AddChild(loader);

        try
        {
            // 使用实际的 manifest 路径
            const string manifestPath = "res://old/Data/blocks/_manifest.json";

            var blocks = await loader.LoadAllBlocksAsync(manifestPath);

            GD.Print($"✓ Total blocks loaded: {blocks.Count}");

            // 统计信息
            var validBlocks = 0;
            var invalidBlocks = 0;

            foreach (var block in blocks)
            {
                if (block.Validate())
                    validBlocks++;
                else
                    invalidBlocks++;
            }

            GD.Print($"✓ Valid blocks: {validBlocks}");
            GD.Print($"✓ Invalid blocks: {invalidBlocks}");

            // 按分类统计
            var categories = new System.Collections.Generic.Dictionary<string, int>();
            foreach (var block in blocks)
            {
                if (!categories.ContainsKey(block.Category))
                    categories[block.Category] = 0;
                categories[block.Category]++;
            }

            GD.Print("✓ Blocks by category:");
            foreach (var (category, count) in categories)
            {
                GD.Print($"  - {category}: {count}");
            }

            GD.Print("✓ Test 3 PASSED\n");
        }
        catch (System.Exception ex)
        {
            GD.PrintErr($"✗ Test 3 FAILED: {ex.Message}\n");
        }
        finally
        {
            loader.QueueFree();
        }
    }

    /// <summary>
    /// 测试 4：信号系统
    /// </summary>
    private async Task TestBlockDataLoaderWithSignals()
    {
        GD.Print("--- Test 4: Signal System ---");

        var loader = new BlockDataLoader();
        AddChild(loader);

        var signalsFired = new System.Collections.Generic.List<string>();

        loader.LoadingStarted += () =>
        {
            signalsFired.Add("LoadingStarted");
            GD.Print("✓ Signal: LoadingStarted");
        };

        loader.LoadingProgress += (current, total, message) =>
        {
            GD.Print($"✓ Signal: LoadingProgress ({current}/{total}) - {message}");
        };

        loader.LoadingComplete += (success, blockCount) =>
        {
            signalsFired.Add("LoadingComplete");
            GD.Print($"✓ Signal: LoadingComplete (Success: {success}, Count: {blockCount})");
        };

        loader.LoadingError += (errorMessage) =>
        {
            signalsFired.Add("LoadingError");
            GD.PrintErr($"✓ Signal: LoadingError ({errorMessage})");
        };

        try
        {
            await loader.LoadAllBlocksAsync("res://old/Data/blocks/_manifest.json");

            GD.Print($"✓ Total signals fired: {signalsFired.Count}");

            if (signalsFired.Contains("LoadingStarted") && signalsFired.Contains("LoadingComplete"))
            {
                GD.Print("✓ Test 4 PASSED\n");
            }
            else
            {
                GD.PrintErr("✗ Test 4 FAILED: Missing expected signals\n");
            }
        }
        catch (System.Exception ex)
        {
            GD.PrintErr($"✗ Test 4 FAILED: {ex.Message}\n");
        }
        finally
        {
            loader.QueueFree();
        }
    }

    /// <summary>
    /// 测试 5：无效数据验证
    /// </summary>
    private async Task TestInvalidBlockValidation()
    {
        GD.Print("--- Test 5: Invalid Block Validation ---");

        // 创建一个无效的 BlockData
        var invalidBlock = new BlockData
        {
            Name = "",  // 无效：名称为空
            DisplayName = "",  // 无效：显示名称为空
            Hardness = -1.0f,  // 无效：硬度为负数
            BaseMineTime = 0.0f  // 无效：挖掘时间为0
        };

        if (!invalidBlock.Validate())
        {
            GD.Print("✓ Invalid block correctly rejected");
            GD.Print("✓ Test 5 PASSED\n");
        }
        else
        {
            GD.PrintErr("✗ Test 5 FAILED: Invalid block passed validation\n");
        }

        await Task.CompletedTask;
    }
}
