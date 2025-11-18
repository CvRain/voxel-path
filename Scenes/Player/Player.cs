using Godot;
using Godot.Collections;
using VoxelPath.Scripts.Blocks;

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
    [Export(PropertyHint.Range, "1,12,0.1")] public float InteractDistance = 6.0f;
    [Export] public NodePath WorldNodePath;
    [Export] public BlockType PlacementBlockType = BlockType.Stone;

    // 飞行相关
    [Export] public float DoubleTapTime = 0.3f;
    [Export] public float FlightVerticalSpeed = 6.0f;
    [Export] public float FlightAccel = 20.0f;
    [Export] public bool EnableFlyDownAction = true;

    // 自动跨越和自动跳跃
    [Export] public bool EnableAutoStepOver = true;
    [Export] public bool EnableAutoJump = true;
    [Export(PropertyHint.Range, "0.1,1.0,0.05")] public float AutoStepOverHeight = 0.5f;
    [Export(PropertyHint.Range, "0.5,2.0,0.05")] public float AutoJumpMaxHeight = 1.0f;
    [Export(PropertyHint.Range, "0.2,2.0,0.05")] public float ObstacleDetectionDistance = 0.6f;

    private float _gravity;
    private Node3D _cameraPivot;
    private Camera3D _camera;
    private bool _isJumpPressed;
    private bool _isJumpHeld;
    private double _jumpInputBufferTimer;
    private double _coyoteTimer;
    private bool _wasOnFloor;

    // 双击空格检测
    private bool _waitingForDoubleTap;
    private double _doubleTapTimer;
    private bool _isFlying;
    private bool _autoJumpTriggered;
    private RayCast3D _interactionRay;
    private World _world;
    public int CurrentPlacementClusterSize { get; private set; } = BlockMetrics.DefaultClusterSize;
    private CollisionShape3D _collisionShape;
    private float _feetOffset = -1.0f;
    private float _bodyRadius = 0.4f;

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
        _interactionRay = _camera.GetNodeOrNull<RayCast3D>("RayCast3D");
        CacheCollisionShapeMetrics();
        SetupInteractionRay();
        ResolveWorldReference();
        Input.MouseMode = Input.MouseModeEnum.Captured;

        // 增加滑动次数以更好地处理方块碰撞
        MaxSlides = 6;
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
            // 检查是否是双击
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
                _autoJumpTriggered = false;
            }
            else if (!_autoJumpTriggered)
            {
                // 开始双击计时（不限制是否在地面）
                _waitingForDoubleTap = true;
                _doubleTapTimer = DoubleTapTime;
            }

            // 正常跳跃输入只在非飞行模式下被捕获
            if (!_isFlying && !_autoJumpTriggered)
            {
                _isJumpPressed = true;
                _isJumpHeld = true;
            }

            // 重置自动跳跃标记
            _autoJumpTriggered = false;
        }        // 检查跳跃释放
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

        if (@event is InputEventMouseButton mouseButton && mouseButton.Pressed &&
            Input.MouseMode == Input.MouseModeEnum.Captured)
        {
            if (mouseButton.ButtonIndex == MouseButton.Left)
            {
                HandleBlockBreak();
            }
            else if (mouseButton.ButtonIndex == MouseButton.Right)
            {
                HandleBlockPlace();
            }
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        UpdatePlacementClusterSize();
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
            float blend = (dir == Vector3.Zero ? deaccel : accel) * (float)delta;
            v.X = Mathf.MoveToward(v.X, target.X, blend);
            v.Z = Mathf.MoveToward(v.Z, target.Z, blend);

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

        // 在移动前处理自动跨越和自动跳跃（仅在地面且有移动输入时）
        if (IsOnFloor() && dir2.LengthSquared() > 0.01f)
        {
            HandleAutoStepAndJump(dir2);
        }

        MoveAndSlide();

        _wasOnFloor = IsOnFloor();
    }

    private void UpdatePlacementClusterSize()
    {
        int newSize = Input.IsActionPressed("sprint")
            ? BlockMetrics.LargeClusterSize
            : BlockMetrics.DefaultClusterSize;
        CurrentPlacementClusterSize = newSize;
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

        EnsureMouseBinding("block_break", MouseButton.Left);
        EnsureMouseBinding("block_place", MouseButton.Right);
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

    private void EnsureMouseBinding(string action, MouseButton button)
    {
        if (!InputMap.HasAction(action))
            InputMap.AddAction(action);

        bool exists = false;
        foreach (var evt in InputMap.ActionGetEvents(action))
        {
            if (evt is InputEventMouseButton mouseEvt && mouseEvt.ButtonIndex == button)
            {
                exists = true;
                break;
            }
        }

        if (!exists)
        {
            var mouseEvent = new InputEventMouseButton { ButtonIndex = button };
            InputMap.ActionAddEvent(action, mouseEvent);
        }
    }

    private void ResolveWorldReference()
    {
        if (WorldNodePath != null && !WorldNodePath.IsEmpty)
            _world = GetNodeOrNull<World>(WorldNodePath);

        _world ??= GetNodeOrNull<World>("../World");
        _world ??= GetNodeOrNull<World>("../../World");
        _world ??= GetTree().Root.GetNodeOrNull<World>("World");
    }

    private void SetupInteractionRay()
    {
        if (_interactionRay == null) return;

        _interactionRay.TargetPosition = new Vector3(0, 0, -InteractDistance);
        _interactionRay.CollideWithAreas = false;
        _interactionRay.CollideWithBodies = true;
        _interactionRay.ExcludeParent = true;
        _interactionRay.AddException(this);
        _interactionRay.Enabled = true;
    }

    private void CacheCollisionShapeMetrics()
    {
        _collisionShape = GetNodeOrNull<CollisionShape3D>("CollisionShape3D");
        _bodyRadius = 0.4f;
        _feetOffset = -1.0f;

        if (_collisionShape?.Shape is CapsuleShape3D capsule)
        {
            _bodyRadius = capsule.Radius;
            _feetOffset = -(capsule.Height * 0.5f + capsule.Radius);
        }
        else if (_collisionShape?.Shape is CylinderShape3D cylinder)
        {
            _bodyRadius = cylinder.Radius;
            _feetOffset = -(cylinder.Height * 0.5f + cylinder.Radius);
        }
        else if (_collisionShape?.Shape is BoxShape3D box)
        {
            _bodyRadius = Mathf.Max(box.Size.X, box.Size.Z) * 0.5f;
            _feetOffset = -(box.Size.Y * 0.5f);
        }
    }

    private float GetFeetLevel()
    {
        return GlobalPosition.Y + _feetOffset;
    }

    private void HandleAutoStepAndJump(Vector3 moveDirection)
    {
        if (!EnableAutoStepOver && !EnableAutoJump)
            return;

        if (!TryGetObstacleHeight(moveDirection, out float estimatedHeight))
            return;

        if (estimatedHeight <= 0.05f || estimatedHeight > AutoJumpMaxHeight)
            return;

        if (EnableAutoStepOver && estimatedHeight <= AutoStepOverHeight)
        {
            var v = Velocity;
            float upwardVelocity = estimatedHeight <= 0.3f ? 2.4f : 3.6f;
            v.Y = Mathf.Max(v.Y, upwardVelocity);
            Velocity = v;
            return;
        }

        if (EnableAutoJump && estimatedHeight > AutoStepOverHeight && estimatedHeight <= AutoJumpMaxHeight)
        {
            if (IsOnFloor() && Velocity.Y <= 0)
            {
                var v = Velocity;
                v.Y = JumpVelocity;
                Velocity = v;
                _autoJumpTriggered = true;
                _waitingForDoubleTap = false;
                _doubleTapTimer = 0;
            }
        }
    }

    private bool TryGetObstacleHeight(Vector3 moveDirection, out float estimatedHeight)
    {
        estimatedHeight = 0f;

        Vector3 planarDirection = new(moveDirection.X, 0, moveDirection.Z);
        if (planarDirection.LengthSquared() < 1e-4f)
            return false;

        var space = GetWorld3D()?.DirectSpaceState;
        if (space == null)
            return false;

        Vector3 checkDir = planarDirection.Normalized();
        float probeHeight = Mathf.Max(BlockMetrics.StandardBlockSize * 2f, _bodyRadius * 0.75f);
        Vector3 horizontalRayStart = GlobalPosition + Vector3.Up * probeHeight;
        Vector3 horizontalRayEnd = horizontalRayStart + checkDir * (ObstacleDetectionDistance + _bodyRadius + 0.05f);

        var exclude = new Array<Rid> { GetRid() };
        var horizontalParams = PhysicsRayQueryParameters3D.Create(horizontalRayStart, horizontalRayEnd);
        horizontalParams.Exclude = exclude;
        var forwardHit = space.IntersectRay(horizontalParams);
        if (!forwardHit.TryGetValue("position", out Variant forwardPosition))
            return false;

        float feetLevel = GetFeetLevel();
        Vector3 contactPoint = (Vector3)forwardPosition;
        Vector3 downRayStart = new(contactPoint.X, feetLevel + AutoJumpMaxHeight + 0.2f, contactPoint.Z);
        Vector3 downRayEnd = new(contactPoint.X, feetLevel - 0.1f, contactPoint.Z);

        var downParams = PhysicsRayQueryParameters3D.Create(downRayStart, downRayEnd);
        downParams.Exclude = exclude;
        var downHit = space.IntersectRay(downParams);
        if (!downHit.TryGetValue("position", out Variant downPosition))
            return false;

        estimatedHeight = ((Vector3)downPosition).Y - feetLevel;
        estimatedHeight = Mathf.Ceil(Mathf.Max(0f, estimatedHeight) / BlockMetrics.StandardBlockSize) * BlockMetrics.StandardBlockSize;
        return estimatedHeight > 0.05f;
    }

    private bool TryGetRayHit(out Vector3 hitPoint, out Vector3 hitNormal)
    {
        hitPoint = default;
        hitNormal = default;

        if (_interactionRay == null || !_interactionRay.IsColliding())
            return false;

        hitPoint = _interactionRay.GetCollisionPoint();
        hitNormal = _interactionRay.GetCollisionNormal();
        return true;
    }

    private void HandleBlockBreak()
    {
        if (_world == null) return;
        if (!TryGetRayHit(out var hitPoint, out var hitNormal)) return;

        var targetPoint = hitPoint - hitNormal * 0.05f;
        _world.TryBreakCluster(targetPoint, CurrentPlacementClusterSize);
    }

    private void HandleBlockPlace()
    {
        if (_world == null) return;
        if (!TryGetRayHit(out var hitPoint, out var hitNormal)) return;

        var targetPoint = hitPoint + hitNormal * 0.05f;
        _world.TryPlaceCluster(targetPoint, CurrentPlacementClusterSize, PlacementBlockType);
    }
}
