using Godot;
using VoxelPath.systems.blocks;
using VoxelPath.systems.blocks.registry;

namespace VoxelPath.systems.blocks.examples;

/// <summary>
/// BlockManager 使用示例
/// 演示如何初始化和使用整个方块系统
/// </summary>
public partial class BlockManagerExample : Node
{
    private BlockManager _blockManager;

    public override void _Ready()
    {
        GD.Print("\n=== BlockManager Example Started ===\n");

        // 创建 BlockManager
        _blockManager = new BlockManager();
        AddChild(_blockManager);

        // 连接信号
        _blockManager.LoadingStarted += OnLoadingStarted;
        _blockManager.LoadingProgress += OnLoadingProgress;
        _blockManager.LoadingComplete += OnLoadingComplete;
        _blockManager.LoadingError += OnLoadingError;

        // 初始化系统
        CallDeferred(nameof(InitializeSystem));
    }

    private void InitializeSystem()
    {
        var success = _blockManager.Initialize();

        if (success)
        {
            GD.Print("\n=== Initialization Successful ===\n");

            // 打印统计信息
            GD.Print(_blockManager.GetStatistics());

            // 测试方块查询
            TestBlockQueries();

            // 测试方块状态
            TestBlockStates();
        }
        else
        {
            GD.PushError("Initialization failed!");
        }
    }

    #region 信号处理

    private void OnLoadingStarted()
    {
        GD.Print("[Example] Loading started...");
    }

    private void OnLoadingProgress(int current, int total)
    {
        GD.Print($"[Example] Loading progress: {current}/{total}");
    }

    private void OnLoadingComplete(int totalBlocks, int totalStates)
    {
        GD.Print($"[Example] Loading complete! Blocks: {totalBlocks}, States: {totalStates}");
    }

    private void OnLoadingError(string error)
    {
        GD.PushError($"[Example] Loading error: {error}");
    }

    #endregion

    #region 测试方法

    private void TestBlockQueries()
    {
        GD.Print("\n--- Testing Block Queries ---");

        var registry = _blockManager.BlockRegistry;

        // 1. 通过字符串查询
        var stone = registry.GetByString("voxelpath:stone");
        if (stone != null)
        {
            GD.Print($"✓ Found stone: {stone.DisplayName} (ID: {stone.Id})");
            GD.Print($"  Hardness: {stone.Hardness}, Tool: {stone.ToolRequired}");
        }

        // 2. 通过 NamespacedId 查询
        var dirt = registry.GetByNamespacedId(new NamespacedId("voxelpath:dirt"));
        if (dirt != null)
        {
            GD.Print($"✓ Found dirt: {dirt.DisplayName} (ID: {dirt.Id})");
        }

        // 3. 通过数字 ID 查询
        var grass = registry.GetById(2); // 假设 grass 是 ID 2
        if (grass != null)
        {
            GD.Print($"✓ Found by ID 2: {grass.DisplayName}");
        }

        // 4. 列出所有方块
        GD.Print($"\nTotal blocks in registry: {_blockManager.TotalBlocksLoaded}");
        GD.Print($"Namespaces: {string.Join(", ", registry.GetNamespaces())}");
    }

    private void TestBlockStates()
    {
        GD.Print("\n--- Testing Block States ---");

        var stateRegistry = _blockManager.BlockStateRegistry;
        var blockRegistry = _blockManager.BlockRegistry;

        // 获取 oak_log 方块
        var oakLog = blockRegistry.GetByString("voxelpath:oak_log");
        if (oakLog != null)
        {
            GD.Print($"\n✓ Testing {oakLog.DisplayName}:");

            // 获取默认状态
            var defaultStateId = stateRegistry.GetDefaultStateId(oakLog.Id);
            var defaultState = stateRegistry.GetStateById(defaultStateId);

            if (defaultState != null)
            {
                GD.Print($"  Default state ID: {defaultStateId}");
                GD.Print($"  Default facing: {defaultState.Facing}");
            }

            // 获取所有状态
            var allStates = stateRegistry.GetAllStatesForBlock(oakLog.Id);
            GD.Print($"  Total states: {allStates.Count}");

            // 测试状态切换
            if (defaultStateId >= 0)
            {
                var newStateId = stateRegistry.CycleProperty(defaultStateId, "facing");
                var newState = stateRegistry.GetStateById(newStateId);

                if (newState != null)
                {
                    GD.Print($"  Cycled facing: {defaultState.Facing} → {newState.Facing}");
                }
            }
        }

        // 测试简单方块（无状态）
        var stone = blockRegistry.GetByString("voxelpath:stone");
        if (stone != null)
        {
            GD.Print($"\n✓ Testing {stone.DisplayName}:");
            var states = stateRegistry.GetAllStatesForBlock(stone.Id);
            GD.Print($"  Total states: {states.Count} (should be 1)");
        }
    }

    #endregion

    public override void _Input(InputEvent @event)
    {
        if (@event is InputEventKey keyEvent && keyEvent.Pressed)
        {
            switch (keyEvent.Keycode)
            {
                case Key.F1:
                    _blockManager?.PrintAllBlocks();
                    break;

                case Key.F2:
                    _blockManager?.PrintAllStates();
                    break;

                case Key.F3:
                    GD.Print(_blockManager?.GetStatistics());
                    break;
            }
        }
    }
}
