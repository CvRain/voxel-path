using Godot;

namespace VoxelPath.systems.block_behaviors;

/// <summary>
/// 示例：信息方块行为
/// 当玩家看向该方块时显示提示信息
/// 左键点击时防止破坏
/// 右键点击时触发特殊交互
/// </summary>
public partial class InformationBlockBehavior : Node, IBlockInteractable
{
    [Export] private Label _infoLabel;
    [Export] private string _displayText = "这是一个信息方块";

    public void OnPlayerLookAt(Vector3I position, Vector3 normal)
    {
        if (_infoLabel != null)
        {
            _infoLabel.Text = $"{_displayText}\n位置: {position}";
            _infoLabel.Show();
        }

        GD.Print($"[InformationBlock] Player looking at position: {position}");
    }

    public void OnPlayerLookAway()
    {
        if (_infoLabel != null)
        {
            _infoLabel.Hide();
        }
    }

    public void OnLeftClick(Vector3I position, Vector3 normal)
    {
        // 信息方块不可破坏
        GD.Print($"[InformationBlock] This block cannot be destroyed! Position: {position}");
    }

    public void OnRightClick(Vector3I position, Vector3 normal)
    {
        // 右键触发特殊交互（例如打开详细信息面板）
        GD.Print($"[InformationBlock] Opening information panel for block at: {position}");
        // TODO: 打开 UI 界面显示详细信息
    }
}
