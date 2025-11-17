using Godot;

namespace VoxelPath.Scenes.Player;

public partial class Player : CharacterBody3D
{
    [Export] public float Speed = 6.0f;
    [Export] public float SprintMultiplier = 1.5f;
    [Export] public float JumpVelocity = 4.8f;
    [Export] public float MouseSensitivity = 0.0035f;
    [Export] public float MaxPitchDegrees = 89f;
    [Export] public float FallGravityMultiplier = 2.0f;
    [Export] public float JumpInputBufferTime = 0.2f;
    [Export] public float CoyoteTime = 0.1f;

    // 飞行相关
    [Export] public float DoubleTapTime = 0.3f;
    [Export] public float FlightVerticalSpeed = 6.0f;
    [Export] public float FlightAccel = 20.0f;
    [Export] public bool EnableFlyDownAction = true;

    private float _gravity;
    private Node3D _cameraPivot;
    private Camera3D _camera;
    private bool _isJumpPressed = false;
    private bool _isJumpHeld = false;
    private double _jumpInputBufferTimer = 0;
    private double _coyoteTimer = 0;
    private bool _wasOnFloor = false;

    // 双击空格检测
    private bool _waitingForDoubleTap = false;
    private double _doubleTapTimer = 0;
    private bool _isFlying = false;

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

        // 双击空格检测并切换飞行模式
        if (Input.IsActionJustPressed("jump"))
        {
            if (_waitingForDoubleTap && _doubleTapTimer > 0)
            {
                // 双击：切换飞行
                _isFlying = !_isFlying;
                _waitingForDoubleTap = false;
                _doubleTapTimer = 0;
                // 重置跳跃/缓冲相关状态
                _isJumpHeld = false;
                _isJumpPressed = false;
                _jumpInputBufferTimer = 0;
                _coyoteTimer = 0;
            }
            else
            {
                _waitingForDoubleTap = true;
                _doubleTapTimer = DoubleTapTime;
            }

            // 正常跳跃输入只在非飞行模式下被捕获
            if (!_isFlying)
            {
                _isJumpPressed = true;
                _isJumpHeld = true;
            }
        }

        // 检查跳跃释放
        if (Input.IsActionJustReleased("jump"))
        {
            _isJumpHeld = false;
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

        // 双击计时器更新
        if (_waitingForDoubleTap)
        {
            _doubleTapTimer -= delta;
            if (_doubleTapTimer <= 0)
            {
                _waitingForDoubleTap = false;
                _doubleTapTimer = 0;
            }
        }

        // 飞行模式逻辑
        if (_isFlying)
        {
            // 水平输入（保留原移动逻辑）
            Vector2 input = Input.GetVector("move_left", "move_right", "move_back", "move_forward");
            Vector3 forward = -GlobalTransform.Basis.Z;
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

            // 垂直控制：space 上升，fly_down 下降
            float verticalTarget = 0f;
            if (Input.IsActionPressed("jump"))
                verticalTarget = FlightVerticalSpeed;
            else if (EnableFlyDownAction && Input.IsActionPressed("fly_down"))
                verticalTarget = -FlightVerticalSpeed;
            else
                verticalTarget = 0f;

            v.Y = Mathf.MoveToward(v.Y, verticalTarget, FlightAccel * (float)delta);

            Velocity = v;
            MoveAndSlide();
            _wasOnFloor = IsOnFloor();
            return;
        }

        // 非飞行：原重力/跳跃逻辑

        // Handle coyote time and jump buffering
        if (IsOnFloor())
        {
            _coyoteTimer = CoyoteTime;
        }
        else
        {
            _coyoteTimer -= delta;
        }

        if (_isJumpPressed)
        {
            _jumpInputBufferTimer = JumpInputBufferTime;
            _isJumpPressed = false;
        }
        else
        {
            _jumpInputBufferTimer -= delta;
        }

        // Apply gravity with different values for上升/下降
        if (!IsOnFloor())
        {
            float currentGravity = _gravity;
            // Increase gravity when moving downward or when jump isn't held
            if (v.Y < 0 || !_isJumpHeld)
            {
                currentGravity *= FallGravityMultiplier;
            }
            v.Y -= currentGravity * (float)delta;
        }

        // Handle jumping with coyote time and input buffering
        if (((_jumpInputBufferTimer > 0 && _coyoteTimer > 0) ||
            (Input.IsActionJustPressed("jump") && _coyoteTimer > 0)) ||
            (_isJumpHeld && IsOnFloor()))
        {
            v.Y = JumpVelocity;
            _coyoteTimer = 0;
            _jumpInputBufferTimer = 0;
        }
        // Variable jump height - reduce upward velocity if jump button is released early
        else if (!_isJumpHeld && v.Y > 0)
        {
            v.Y = Mathf.MoveToward(v.Y, 0, _gravity * (float)delta * 2);
        }

        // 修复：交换 move_forward / move_back 参数顺序，保证 W 为正向前
        Vector2 input2 = Input.GetVector("move_left", "move_right", "move_back", "move_forward");

        Vector3 forward2 = -GlobalTransform.Basis.Z; // Godot 的前方向
        Vector3 right2 = GlobalTransform.Basis.X;

        Vector3 dir2 = forward2 * input2.Y + right2 * input2.X;
        if (dir2.LengthSquared() > 1e-6f)
            dir2 = dir2.Normalized();

        float curSpeed2 = Speed * (Input.IsActionPressed("sprint") ? SprintMultiplier : 1f);

        const float accel2 = 12f;
        const float deaccel2 = 16f;

        Vector3 target2 = dir2 * curSpeed2;
        v.X = Mathf.MoveToward(v.X, target2.X, (dir2 == Vector3.Zero ? deaccel2 : accel2) * (float)delta);
        v.Z = Mathf.MoveToward(v.Z, target2.Z, (dir2 == Vector3.Zero ? deaccel2 : accel2) * (float)delta);

        Velocity = v;
        MoveAndSlide();

        _wasOnFloor = IsOnFloor();
    }

    private void SetupInputMap()
    {
        EnsureKeyBinding("move_forward", Key.W);
        EnsureKeyBinding("move_back", Key.S);
        EnsureKeyBinding("move_left", Key.A);
        EnsureKeyBinding("move_right", Key.D);
        EnsureKeyBinding("jump", Key.Space);
        EnsureKeyBinding("sprint", Key.Shift);

        if (EnableFlyDownAction)
            EnsureKeyBinding("fly_down", Key.Shift);
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
