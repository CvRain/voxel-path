using Godot;
using VoxelPath.Scripts.Core;

namespace VoxelPath.entities.player.scripts;

public partial class BlockSelector : MeshInstance3D
{
    private int _brushSize = 1;

    public override void _Ready()
    {
        base._Ready();
        // Create a simple cube mesh for the selector
        var mesh = new BoxMesh();
        mesh.Size = new Vector3(1, 1, 1) * (Constants.VoxelSize + 0.02f); // Slightly larger to avoid z-fighting
        this.Mesh = mesh;

        var material = new StandardMaterial3D();
        material.AlbedoColor = new Color(1, 1, 1, 0.3f);
        material.Transparency = BaseMaterial3D.TransparencyEnum.Alpha;
        this.MaterialOverride = material;
        Hide();
    }

    public void SetBrushSize(int size)
    {
        _brushSize = size;
        var scale = new Vector3(1, 1, 1) * _brushSize * Constants.VoxelSize;
        this.Scale = scale;
    }

    public void UpdateSelection(Vector3I voxelIndex, Vector3 normal)
    {
        var offset = (new Vector3(_brushSize, _brushSize, _brushSize) - Vector3.One) * 0.5f;
        this.GlobalPosition = (voxelIndex - offset) * Constants.VoxelSize;
    }
    
    public static Vector3I WorldToVoxelIndex(Vector3 worldPos, float voxelSize)
    {
        return new Vector3I(
            Mathf.FloorToInt(worldPos.X / voxelSize),
            Mathf.FloorToInt(worldPos.Y / voxelSize),
            Mathf.FloorToInt(worldPos.Z / voxelSize)
        );
    }
}
