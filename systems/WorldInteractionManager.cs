using Godot;
using VoxelPath.entities.player.scripts;
using VoxelPath.Scripts.Core;
using BlockSelector = VoxelPath.entities.player.scripts.BlockSelector;

namespace VoxelPath.systems;

public partial class WorldInteractionManager : Node
{
    [Export] private Player _player;
    [Export] private BlockSelector _blockSelector;

    public override void _Ready()
    {
        if (_player == null)
        {
            GD.PushError("Player not assigned in WorldInteractionManager.");
            return;
        }

        if (_blockSelector == null)
        {
            GD.PushError("BlockSelector not assigned in WorldInteractionManager.");
            return;
        }

        _player.HoveredBlockChanged += OnHoveredBlockChanged;
        _player.HoveredBlockExited += OnHoveredBlockExited;
        
        _blockSelector.Hide();
    }

    private void OnHoveredBlockChanged(Vector3I blockPosition, Vector3 blockNormal)
    {
        // Here you could add logic based on the block type later on.
        // For now, we just show the selector.
        _blockSelector.UpdateSelection(blockPosition, blockNormal);
        _blockSelector.Show();
    }

    private void OnHoveredBlockExited()
    {
        _blockSelector.Hide();
    }
}

