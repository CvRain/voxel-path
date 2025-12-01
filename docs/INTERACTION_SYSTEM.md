# 玩家交互系统 (Player Interaction System)

本文档介绍了基于事件的玩家-世界交互系统。该系统旨在将玩家的输入和射线检测与具体的交互逻辑（如方块高亮、方块行为等）解耦。

## 核心设计

该系统的核心是 `Player` 类中的两个事件：

-   `HoveredBlockChanged`: 当玩家的准星指向一个新的方块时触发。
    -   **参数**: `Vector3I blockPosition`, `Vector3 blockNormal`
-   `HoveredBlockExited`: 当玩家的准星从一个方块上移开时触发。

`Player` 类本身不关心指向的是什么方块，也不关心指向后应该发生什么。它只负责通过 `RayCast3D` 检测目标，并在状态变化时发出通知。

这种设计使得我们可以创建独立的系统来监听这些事件并执行相应的操作，而无需修改 `Player` 的代码。

## `WorldInteractionManager`

`WorldInteractionManager` 是该系统的一个核心实现。它是一个独立的节点，负责处理默认的交互行为，例如高亮玩家指向的方块。

### 功能

1.  **监听玩家事件**: 监听 `Player` 的 `HoveredBlockChanged` 和 `HoveredBlockExited` 事件。
2.  **控制方块选择器**: 根据接收到的事件，调用 `BlockSelector` 的方法来显示、隐藏或更新高亮线框的位置。

### 如何设置

1.  **创建节点**: 在你的主场景中（例如 `level_playground.tscn`），创建一个新的 `Node` 节点，并将其命名为 `WorldInteractionManager`。
2.  **附加脚本**: 将 `systems/WorldInteractionManager.cs` 脚本附加到此节点上。
3.  **分配依赖**: 在 Godot 编辑器的检查器中，将 `Player` 节点和场景中的 `BlockSelector` 节点拖拽到 `WorldInteractionManager` 脚本的 `Player` 和 `BlockSelector` 导出变量中。

## 如何扩展：实现自定义方块行为

这个事件驱动的系统使得添加自定义方块交互变得非常简单。例如，当玩家指向一个“信息方块”时，在屏幕上显示信息。

以下是如何实现它的示例：

1.  **创建一个新的交互处理器**

    创建一个新的脚本，例如 `InformationBlockHandler.cs`。

    ```csharp
    using Godot;
    using VoxelPath.entities.player.scripts;

    public partial class InformationBlockHandler : Node
    {
        [Export] private Player _player;
        [Export] private Label _infoLabel; // 用于显示信息的UI标签

        // 假设 "信息方块" 的 ID 是 5
        private const int InformationBlockId = 5;

        public override void _Ready()
        {
            if (_player == null) return;
            _player.HoveredBlockChanged += OnHoveredBlockChanged;
            _player.HoveredBlockExited += OnHoveredBlockExited;
            _infoLabel.Hide();
        }

        private void OnHoveredBlockChanged(Vector3I blockPosition, Vector3 blockNormal)
        {
            // 调用世界方法来获取方块ID
            var world = GetTree().CurrentScene;
            if (world.HasMethod("get_voxel_at"))
            {
                int blockId = (int)world.Call("get_voxel_at", blockPosition);

                if (blockId == InformationBlockId)
                {
                    _infoLabel.Text = $"你正在看着一个信息方块，位于: {blockPosition}";
                    _infoLabel.Show();
                }
                else
                {
                    _infoLabel.Hide();
                }
            }
        }

        private void OnHoveredBlockExited()
        {
            _infoLabel.Hide();
        }
    }
    ```

2.  **在场景中设置**

    -   将此脚本附加到场景中的一个新节点上。
    -   将 `Player` 节点和你的 `Label` UI节点分配给脚本的导出变量。

通过这种方式，你可以为不同类型的方块创建任意数量的独立处理器，而无需触及 `Player` 或 `WorldInteractionManager` 的代码，从而保持了系统的整洁和模块化。

