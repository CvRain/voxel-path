using Godot;

namespace VoxelPath.Scenes.Player;

public partial class Crosshair : Control
{
    [Export] public Color Color = new Color(1f, 1f, 1f, 0.9f);
    [Export] public float Thickness = 2f;
    [Export] public float Length = 8f;
    [Export] public float Gap = 4f;
    [Export] public bool ShowCenterDot = false;
    [Export] public float CenterDotRadius = 2f;
    [Export] public bool HideWhenMouseFree = true;

    public override void _Ready()
    {
        SetAnchorsPreset(LayoutPreset.FullRect);
        MouseFilter = MouseFilterEnum.Ignore;
    }

    public override void _Process(double delta)
    {
        if (HideWhenMouseFree)
            Visible = Input.MouseMode == Input.MouseModeEnum.Captured;

        QueueRedraw();
    }

    public override void _Draw()
    {
        var center = Size / 2f;

        DrawLine(center + new Vector2(Gap, 0), center + new Vector2(Gap + Length, 0), Color, Thickness);
        DrawLine(center - new Vector2(Gap, 0), center - new Vector2(Gap + Length, 0), Color, Thickness);
        DrawLine(center + new Vector2(0, Gap), center + new Vector2(0, Gap + Length), Color, Thickness);
        DrawLine(center - new Vector2(0, Gap), center - new Vector2(0, Gap + Length), Color, Thickness);

        if (ShowCenterDot && CenterDotRadius > 0f)
            DrawCircle(center, CenterDotRadius, Color);
    }
}
