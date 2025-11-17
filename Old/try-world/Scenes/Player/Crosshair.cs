using Godot;

namespace TryWorld.Scenes.Player;

public partial class Crosshair : Control
{
    [Export] public Color Color = new Color(1f, 1f, 1f, 0.9f);
    [Export] public float Thickness = 2f;    // 线条粗细（像素）
    [Export] public float Length = 8f;       // 单侧线段长度（像素）
    [Export] public float Gap = 4f;          // 中心空隙大小（像素）
    [Export] public bool ShowCenterDot = false;
    [Export] public float CenterDotRadius = 2f;
    [Export] public bool HideWhenMouseFree = true; // ESC 释放鼠标时是否隐藏

    public override void _Ready()
    {
        // 让控件覆盖整个屏幕，方便以屏幕中心为基准绘制
        SetAnchorsPreset(LayoutPreset.FullRect);
        MouseFilter = MouseFilterEnum.Ignore; // 不拦截鼠标事件
    }

    public override void _Process(double delta)
    {
        if (HideWhenMouseFree)
            Visible = Input.MouseMode == Input.MouseModeEnum.Captured;

        // 基本无开销，但确保在窗口尺寸改变或属性修改时重绘
        QueueRedraw();
    }

    public override void _Draw()
    {
        var center = Size / 2f;

        // 水平右
        DrawLine(center + new Vector2(Gap, 0), center + new Vector2(Gap + Length, 0), Color, Thickness);
        // 水平左
        DrawLine(center - new Vector2(Gap, 0), center - new Vector2(Gap + Length, 0), Color, Thickness);

        // 垂直下
        DrawLine(center + new Vector2(0, Gap), center + new Vector2(0, Gap + Length), Color, Thickness);
        // 垂直上
        DrawLine(center - new Vector2(0, Gap), center - new Vector2(0, Gap + Length), Color, Thickness);

        if (ShowCenterDot && CenterDotRadius > 0f)
        {
            DrawCircle(center, CenterDotRadius, Color);
        }
    }
}