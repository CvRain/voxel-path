using Godot;
using System;

namespace VoxelPath.entities.player.scripts;

public partial class Crosshair : Control
{
    [Export] public Color Color { get; set; } = Colors.White;
    [Export] public float Thickness { get; set; } = 2.0f;
    [Export] public float Length { get; set; } = 8.0f;
    [Export] public float Gap { get; set; } = 4.0f;
    [Export] public bool ShowCenterDot { get; set; } = false;
    [Export] public float CenterDotRadius { get; set; } = 3.0f;
    [Export] public bool HideWhenFree { get; set; } = true;

    public override void _Ready()
    {
        SetAnchorsPreset(LayoutPreset.FullRect);
        MouseFilter = MouseFilterEnum.Ignore;
    }

    public override void _Process(double delta)
    {
        if (HideWhenFree)
        {
            Visible = Input.MouseMode != Input.MouseModeEnum.Visible;
        }
        QueueRedraw();
    }

    public override void _Draw()
    {
        var center = GetSize() / 2.0f;

        // Horizontal Right
        DrawLine(center + new Vector2(Gap, 0), center + new Vector2(Gap + Length, 0), Color, Thickness);

        // Horizontal Left
        DrawLine(center - new Vector2(Gap, 0), center - new Vector2(Gap + Length, 0), Color, Thickness);

        // Vertical Top
        DrawLine(center - new Vector2(0, Gap), center - new Vector2(0, Gap + Length), Color, Thickness);

        // Vertical Bottom
        DrawLine(center + new Vector2(0, Gap), center + new Vector2(0, Gap + Length), Color, Thickness);

        if (ShowCenterDot)
        {
            DrawCircle(center, CenterDotRadius, Color);
        }
    }
}
