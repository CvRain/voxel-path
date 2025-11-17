using Godot;

namespace TryWorld.Scenes.Player;

public partial class Player : CharacterBody3D
{
    [Export] public float Speed = 6.0f;
    [Export] public float SprintMultiplier = 1.5f;
    [Export] public float JumpVelocity = 4.8f;
    [Export] public float MouseSensitivity = 0.0035f;
    [Export] public float MaxPitchDegrees = 89f;
    // 飞行相关参数
    [Export] public float FlightVerticalSpeed = 6.0f; // 飞行模式垂直速度
    [Export] public float DoubleTapThreshold = 0.3f;  // 双击空格时间窗口秒

    private float _gravity;
    private Node3D _cameraPivot;
    private Camera3D _camera;

    private bool _flightMode = false;
    private double _lastSpacePressTime = -100.0;

    public override void _EnterTree()
    {
        var g = ProjectSettings.GetSetting("physics/3d/default_gravity");
        _gravity = g.VariantType == Variant.Type.Float ? g.AsSingle() : 9.8f;
        SetupInputMap();
    }

    public override void _Ready()
    {
        _cameraPivot = GetNode<Node3D>("CameraPivot");
        _camera = _cameraPivot.GetNode<Camera3D>("Camera3D");
        Input.MouseMode = Input.MouseModeEnum.Captured;
    }

    public override void _Input(InputEvent @event)
    {
        if (Input.IsActionJustPressed("ui_cancel"))
        {
            Input.MouseMode = Input.MouseMode == Input.MouseModeEnum.Captured
                ? Input.MouseModeEnum.Visible
                : Input.MouseModeEnum.Captured;
        }

        if (@event is InputEventMouseMotion motion && Input.MouseMode == Input.MouseModeEnum.Captured)
        {
            RotateY(-motion.Relative.X * MouseSensitivity);

            float pitchDelta = -motion.Relative.Y * MouseSensitivity;
            _cameraPivot.RotateX(pitchDelta);

            var rot = _cameraPivot.Rotation;
            rot.X = Mathf.Clamp(rot.X, Mathf.DegToRad(-MaxPitchDegrees), Mathf.DegToRad(MaxPitchDegrees));
            _cameraPivot.Rotation = rot;
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        var v = Velocity;

        // 处理双击空格切换飞行模式 / 跳跃
        if (Input.IsActionJustPressed("jump"))
        {
            double now = Time.GetTicksMsec() / 1000.0;
            if (now - _lastSpacePressTime <= DoubleTapThreshold)
            {
                _flightMode = !_flightMode;
                // 切换飞行模式时重置垂直速度，避免瞬间加速或坠落
                v.Y = 0;
                GD.Print($"Flight mode: {_flightMode}");
            }
            else
            {
                if (!_flightMode && IsOnFloor())
                {
                    v.Y = JumpVelocity; // 正常跳跃
                }
            }
            _lastSpacePressTime = now;
        }

        // 重力处理（非飞行模式）
        if (!_flightMode)
        {
            if (!IsOnFloor())
                v.Y -= _gravity * (float)delta;
        }
        else
        {
            // 飞行模式垂直控制：Space 上升，Shift 下降（仍保留 Shift 的冲刺对水平速度影响）
            float verticalInput = 0f;
            if (Input.IsActionPressed("jump")) verticalInput += 1f; // 上升
            if (Input.IsActionPressed("sprint")) verticalInput -= 1f; // 下降
            // 平滑过渡垂直速度
            v.Y = Mathf.MoveToward(v.Y, verticalInput * FlightVerticalSpeed, 20f * (float)delta);
        }

        // 水平移动（与原逻辑一致）
        Vector2 input = Input.GetVector("move_left", "move_right", "move_back", "move_forward");

        Vector3 forward = -GlobalTransform.Basis.Z; // Godot 的前方向
        Vector3 right = GlobalTransform.Basis.X;

        Vector3 dir = forward * input.Y + right * input.X;
        if (dir.LengthSquared() > 1e-6f)
            dir = dir.Normalized();

        float curSpeed = Speed * (Input.IsActionPressed("sprint") ? SprintMultiplier : 1f);

        const float accel = 12f;
        const float deaccel = 16f;

        Vector3 target = dir * curSpeed;
        v.X = Mathf.MoveToward(v.X, target.X, (dir == Vector3.Zero ? deaccel : accel) * (float)delta);
        v.Z = Mathf.MoveToward(v.Z, target.Z, (dir == Vector3.Zero ? deaccel : accel) * (float)delta);

        Velocity = v;
        MoveAndSlide();
    }

    private void SetupInputMap()
    {
        EnsureKeyBinding("move_forward", Key.W);
        EnsureKeyBinding("move_back", Key.S);
        EnsureKeyBinding("move_left", Key.A);
        EnsureKeyBinding("move_right", Key.D);
        EnsureKeyBinding("jump", Key.Space);
        EnsureKeyBinding("sprint", Key.Shift);
    }

    private void EnsureKeyBinding(string action, Key key)
    {
        if (!InputMap.HasAction(action))
            InputMap.AddAction(action);

        bool exists = false;
        foreach (var evt in InputMap.ActionGetEvents(action))
        {
            if (evt is InputEventKey k && k.PhysicalKeycode == key)
            {
                exists = true;
                break;
            }
        }

        if (!exists)
        {
            var e = new InputEventKey { PhysicalKeycode = key };
            InputMap.ActionAddEvent(action, e);
        }
    }
}