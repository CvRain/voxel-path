using System;
using System.Collections.Generic;
using System.Linq;
using Godot;
using VoxelPath.Scripts.Core;

namespace VoxelPath.entities.player.scripts;

public partial class Player : CharacterBody3D
{
    [ExportGroup("Configuration")]
    [Export]
    public PlayerAttribution PlayerAttribution { get; set; }

    [Export] public ActionAttribution ActionAttribution { get; set; }

    [ExportGroup("Debug")]
    [Export] public bool EnableDebug { get; set; }
    [Export] public float DebugInterval { get; set; } = 1.0f;

    private const float DoubleJumpTime = 0.3f;
    private const float InteractDelay = 0.2f;

    public enum MoveState
    {
        Grounded,
        Flying,
        Noclip
    }

    private bool _mouseCaptured;
    private Vector2 _lookRotation = Vector2.Zero;
    private float _gravity;
    private float _debugTimer;

    private MoveState _currentMoveState = MoveState.Grounded;
    private float _lastJumpPressTime = 1.0f;

    // 阶梯平滑相关变量
    private bool _steppingUp;
    private Vector3 _stepStartPosition = Vector3.Zero;
    private Vector3 _stepTargetPosition = Vector3.Zero;
    private float _stepElapsedTime;
    private float _stepTargetHeight;

    //节点引用
    private Camera3D _camera;
    private CollisionShape3D _bodyCollision;
    private RayCast3D _rayCast;
    private Node3D _head;

    // 交互变量
    private int _brushSize = 1;
    private float _lastInteractTime;
    private Vector3I? _lastHoveredVoxel;

    // 公开属性供外部访问
    public int BrushSize => _brushSize;
    public RayCast3D RayCast => _rayCast;

    // 射线检测事件
    public event Action<Vector3I, Vector3> HoveredBlockChanged;
    public event Action HoveredBlockExited;

    // 交互事件
    public event Action<Vector3I, Vector3> LeftClickBlock;
    public event Action<Vector3I, Vector3> RightClickBlock;

    // 笔刷事件
    public event Action<int> BrushSizeChanged;


    public override void _Ready()
    {
        base._Ready();
        AddToGroup("player");

        _gravity = (float)ProjectSettings.GetSetting("physics/3d/default_gravity");

        InitializeNodes();
        InitializeState();
        InitializeInteraction();

        CaptureMouse();
        CheckInputMapping();
    }

    private void InitializeNodes()
    {
        _head = GetNode<Node3D>("Head");
        _camera = _head.GetNode<Camera3D>("Camera3D");
        _bodyCollision = GetNode<CollisionShape3D>("BodyCollision");
        _rayCast = _head.GetNode<RayCast3D>("RayCast3D");
    }

    private void InitializeState()
    {
        _lookRotation.Y = Rotation.Y;
        _lookRotation.X = _head.Rotation.X;
        SetState(MoveState.Grounded);
    }

    private void InitializeInteraction()
    {
        if (_rayCast != null)
        {
            _rayCast.TargetPosition = new Vector3(0, 0, -PlayerAttribution.InteractionDistance);
            _rayCast.AddException(this);
        }
    }

    public override void _Input(InputEvent @event)
    {
        HandleMouseInput(@event);
        HandleKeyboardInput(@event);
    }

    private void HandleMouseInput(InputEvent @event)
    {
        if (Input.IsKeyPressed(Key.Escape))
        {
            ReleaseMouse();
        }

        if (@event is InputEventMouseButton mouseBtn && mouseBtn.ButtonIndex == MouseButton.Left && !_mouseCaptured)
        {
            CaptureMouse();
        }

        if (_mouseCaptured && @event is InputEventMouseMotion mouseMotion)
        {
            HandleMouseLook(mouseMotion.Relative);
        }
    }

    private void HandleKeyboardInput(InputEvent @event)
    {
        if (@event.IsActionPressed("ui_focus_next")) // Tab
        {
            ToggleBrushSize();
        }

        if (PlayerAttribution.EnableFly && Input.IsActionJustPressed(ActionAttribution.InputJump))
        {
            if (_lastJumpPressTime < DoubleJumpTime)
            {
                ToggleFlyMode();
            }
            _lastJumpPressTime = 0.0f;
        }

        if (PlayerAttribution.EnableNoclip && Input.IsActionJustPressed(ActionAttribution.InputNoclipToggle))
        {
            ToggleNoclipMode();
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        var dt = (float)delta;
        _lastJumpPressTime += dt;

        UpdateDebug(dt);

        if (_steppingUp)
        {
            UpdateStepSmoothing(dt);
            return;
        }

        HandleMovement(dt);
        HandleInteraction();
    }

    private void UpdateDebug(float delta)
    {
        if (!EnableDebug) return;

        _debugTimer += delta;
        if (!(_debugTimer >= DebugInterval)) return;
        _debugTimer = 0.0f;
        GD.Print($"Player Pos: {GlobalPosition} | State: {_currentMoveState} | Stepping: {_steppingUp}");
    }

    private void ToggleFlyMode()
    {
        SetState(_currentMoveState == MoveState.Grounded ? MoveState.Flying : MoveState.Grounded);
    }

    private void ToggleNoclipMode()
    {
        SetState(_currentMoveState == MoveState.Noclip ? MoveState.Flying : MoveState.Noclip);
    }

    private void HandleMovement(float delta)
    {
        switch (_currentMoveState)
        {
            case MoveState.Grounded:
                GroundPhysics(delta);
                break;
            case MoveState.Flying:
            case MoveState.Noclip:
                FlyingPhysics(delta);
                break;
        }
    }

    private void GroundPhysics(float delta)
    {
        var vel = Velocity;

        // Apply gravity
        if (PlayerAttribution.EnableGravity && !IsOnFloor())
        {
            vel.Y -= _gravity * delta;
        }

        // Handle jumping
        if (PlayerAttribution.EnableJump && Input.IsActionPressed(ActionAttribution.InputJump) && IsOnFloor())
        {
            vel.Y = PlayerAttribution.JumpVelocity;
        }

        // Get input direction
        var inputDir = Input.GetVector(ActionAttribution.InputLeft, ActionAttribution.InputRight,
            ActionAttribution.InputForward, ActionAttribution.InputBackward);
        var moveDir = (Transform.Basis * new Vector3(inputDir.X, 0, inputDir.Y)).Normalized();

        // Determine target speed
        var currentSpeed = GetCurrentSpeed();

        var targetVelocity = moveDir * currentSpeed;

        // Apply acceleration/deacceleration
        var accel = inputDir == Vector2.Zero ? PlayerAttribution.Deceleration : PlayerAttribution.Acceleration;
        vel.X = Mathf.MoveToward(vel.X, targetVelocity.X, accel * delta);
        vel.Z = Mathf.MoveToward(vel.Z, targetVelocity.Z, accel * delta);

        Velocity = vel;
        MoveAndSlide();

        // 检查并处理阶梯
        if (IsOnWall() && !_steppingUp)
        {
            AttemptStepUp(moveDir);
        }
    }

    private float GetCurrentSpeed()
    {
        return PlayerAttribution.EnableSprint && Input.IsActionPressed(ActionAttribution.InputSprint)
            ? PlayerAttribution.SprintSpeed
            : PlayerAttribution.BaseSpeed;
    }

    private void FlyingPhysics(float delta)
    {
        var vel = Velocity;

        // Get input direction
        var inputDir2D = Input.GetVector(ActionAttribution.InputLeft, ActionAttribution.InputRight,
            ActionAttribution.InputForward, ActionAttribution.InputBackward);
        var moveDir = (_head.GlobalBasis * new Vector3(inputDir2D.X, 0, inputDir2D.Y)).Normalized();

        // Vertical movement
        if (IsActionPressed(ActionAttribution.InputJump))
            moveDir.Y += 1.0f;
        if (IsActionPressed(ActionAttribution.InputFlyDown))
            moveDir.Y -= 1.0f;

        var targetVelocity = moveDir.Normalized() * PlayerAttribution.FlySpeed;

        var isMoving = inputDir2D != Vector2.Zero || IsActionPressed(ActionAttribution.InputJump) ||
                        IsActionPressed(ActionAttribution.InputFlyDown);
        var accel = !isMoving ? PlayerAttribution.Deceleration : PlayerAttribution.Acceleration;

        vel = vel.MoveToward(targetVelocity, accel * delta);

        Velocity = vel;
        MoveAndSlide();
    }

    private void SetState(MoveState newState)
    {
        if (_currentMoveState == newState) return;

        _currentMoveState = newState;
        Velocity = Vector3.Zero;

        if (_bodyCollision != null)
        {
            switch (_currentMoveState)
            {
                case MoveState.Grounded:
                    _bodyCollision.Disabled = false;
                    PlayerAttribution.EnableGravity = true;
                    break;
                case MoveState.Flying:
                    _bodyCollision.Disabled = false;
                    PlayerAttribution.EnableGravity = false;
                    break;
                case MoveState.Noclip:
                    _bodyCollision.Disabled = true;
                    PlayerAttribution.EnableGravity = false;
                    break;
            }
        }
    }

    private void HandleMouseLook(Vector2 relativeMotion)
    {
        _lookRotation.Y -= relativeMotion.X * PlayerAttribution.LookSpeed;
        _lookRotation.X -= relativeMotion.Y * PlayerAttribution.LookSpeed;
        _lookRotation.X = Mathf.Clamp(_lookRotation.X, Mathf.DegToRad(-PlayerAttribution.MaxPitchDegrees),
            Mathf.DegToRad(PlayerAttribution.MaxPitchDegrees));

        Transform = new Transform3D(Basis.Identity, Position);
        RotateObjectLocal(Vector3.Up, _lookRotation.Y);

        _head.Rotation = new Vector3(_lookRotation.X, _head.Rotation.Y, _head.Rotation.Z);
    }

    private void CaptureMouse()
    {
        Input.MouseMode = Input.MouseModeEnum.Captured;
        _mouseCaptured = true;
    }

    private void ReleaseMouse()
    {
        Input.MouseMode = Input.MouseModeEnum.Visible;
        _mouseCaptured = false;
    }

    // Step Smoothing Logic
    private void AttemptStepUp(Vector3 moveDir)
    {
        if (!IsOnFloor()) return;

        var horizontalDir = (moveDir * new Vector3(1, 0, 1)).Normalized();
        if (horizontalDir.Length() < 0.5f) return;

        if (!TestMove(GlobalTransform, horizontalDir * 0.15f)) return; // Not blocked

        var stepHeightFound = ScanStepHeight(horizontalDir);
        if (stepHeightFound > 0.0f && stepHeightFound <= PlayerAttribution.StepHeight)
        {
            StartStepUp(horizontalDir, stepHeightFound);
        }
    }

    private float ScanStepHeight(Vector3 direction)
    {
        const float scanDistance = 0.2f;
        const float stepIncrement = 0.05f;
        var maxScanHeight = PlayerAttribution.StepHeight;
        var currentHeight = stepIncrement;

        while (currentHeight <= maxScanHeight)
        {
            var upOffset = new Vector3(0, currentHeight, 0);
            var testPos = GlobalTransform.Translated(upOffset);

            if (TestMove(GlobalTransform, upOffset)) return 0.0f; // Hit ceiling

            if (!TestMove(testPos, direction * scanDistance))
            {
                return currentHeight;
            }

            currentHeight += stepIncrement;
        }

        return 0.0f;
    }

    private void StartStepUp(Vector3 direction, float height)
    {
        _steppingUp = true;
        _stepStartPosition = GlobalPosition;
        _stepTargetHeight = height;
        _stepTargetPosition = _stepStartPosition + new Vector3(0, height, 0) + direction * 0.1f;
        _stepElapsedTime = 0.0f;
        Velocity = Vector3.Zero;
    }

    private void UpdateStepSmoothing(float delta)
    {
        _stepElapsedTime += delta;
        var progress = Mathf.Clamp(_stepElapsedTime / PlayerAttribution.StepSmoothTime, 0.0f, 1.0f);
        var easedProgress = EaseOutCubic(progress);

        GlobalPosition = _stepStartPosition.Lerp(_stepTargetPosition, easedProgress);

        if (progress >= 1.0f)
        {
            _steppingUp = false;
            GlobalPosition = _stepTargetPosition;
            Velocity = Vector3.Zero;
        }
    }

    private float EaseOutCubic(float t)
    {
        var tNorm = t - 1.0f;
        return tNorm * tNorm * tNorm + 1.0f;
    }

    // Interaction Logic
    private void ToggleBrushSize()
    {
        if (_brushSize == 4) _brushSize = 2;
        else if (_brushSize == 2) _brushSize = 1;
        else if (_brushSize == 1) _brushSize = 4;

        BrushSizeChanged?.Invoke(_brushSize);
        GD.Print($"Brush size: {_brushSize}x{_brushSize}x{_brushSize}");
    }

    private bool CanInteractDelay()
    {
        var currentTime = Time.GetTicksMsec() / 1000.0f;
        if (!(currentTime - _lastInteractTime > InteractDelay)) return false;
        _lastInteractTime = currentTime;
        return true;

    }

    private void HandleInteraction()
    {
        if (_rayCast == null || !_rayCast.IsColliding())
        {
            if (!_lastHoveredVoxel.HasValue) return;
            _lastHoveredVoxel = null;
            HoveredBlockExited?.Invoke();
            return;
        }

        var hitPoint = _rayCast.GetCollisionPoint();
        var normal = _rayCast.GetCollisionNormal();

        var hitBlockCenter = hitPoint - (normal * Constants.VoxelSize * 0.1f);
        var centerGridPos = BlockSelector.WorldToVoxelIndex(hitBlockCenter, Constants.VoxelSize);

        if (!_lastHoveredVoxel.HasValue || _lastHoveredVoxel.Value != centerGridPos)
        {
            _lastHoveredVoxel = centerGridPos;
            HoveredBlockChanged?.Invoke(centerGridPos, normal);
        }

        if (Input.IsMouseButtonPressed(MouseButton.Left))
        {
            if (CanInteractDelay())
            {
                LeftClickBlock?.Invoke(centerGridPos, normal);
            }
        }
        else if (Input.IsMouseButtonPressed(MouseButton.Right))
        {
            if (CanInteractDelay())
            {
                RightClickBlock?.Invoke(centerGridPos, normal);
            }
        }
    }

    // 工具方法：计算笔刷覆盖的体素列表（供外部使用）
    public List<Vector3I> GetVoxelBrush(Vector3I center, Vector3? normal = null)
    {
        var voxels = new List<Vector3I>();
        var offsetStart = -Mathf.FloorToInt(_brushSize / 2.0f);
        var startOffset = new Vector3I(offsetStart, offsetStart, offsetStart);

        if (normal.HasValue)
        {
            var axisNormal = new Vector3I(Mathf.RoundToInt(normal.Value.X), Mathf.RoundToInt(normal.Value.Y), Mathf.RoundToInt(normal.Value.Z));
            if (axisNormal.X != 0) startOffset.X = axisNormal.X > 0 ? 0 : -(_brushSize - 1);
            else if (axisNormal.Y != 0) startOffset.Y = axisNormal.Y > 0 ? 0 : -(_brushSize - 1);
            else if (axisNormal.Z != 0) startOffset.Z = axisNormal.Z > 0 ? 0 : -(_brushSize - 1);
        }

        for (var x = 0; x < _brushSize; x++)
        {
            for (var y = 0; y < _brushSize; y++)
            {
                for (var z = 0; z < _brushSize; z++)
                {
                    var targetPos = center + startOffset + new Vector3I(x, y, z);
                    voxels.Add(targetPos);
                }
            }
        }
        return voxels;
    }



    /// <summary>
    /// 检查玩家输入映射是否正确
    /// </summary>
    private void CheckInputMapping()
    {
        var actions = new Dictionary<string, (bool Enabled, List<string> Inputs)>
        {
            {
                "Movement",
                (PlayerAttribution.EnableMove,
                [
                    ActionAttribution.InputLeft, ActionAttribution.InputRight, ActionAttribution.InputForward,
                    ActionAttribution.InputBackward
                ])
            },
            { "Jumping", (PlayerAttribution.EnableJump, [ActionAttribution.InputJump]) },
            { "Sprinting", (PlayerAttribution.EnableSprint, [ActionAttribution.InputSprint]) },
            { "Flying", (PlayerAttribution.EnableFly, [ActionAttribution.InputFlyDown]) },
            { "Noclip", (PlayerAttribution.EnableNoclip, [ActionAttribution.InputNoclipToggle]) }
        };

        foreach (var kvp in actions.Where(kvp => kvp.Value.Enabled))
        {
            foreach (var actionName in kvp.Value.Inputs.Where(actionName => !InputMap.HasAction(actionName)))
            {
                GD.PushWarning($"{kvp.Key} disabled. No InputAction found for: {actionName}");
                break;
            }
        }
    }

    private bool IsActionPressed(string action)
    {
        if (string.IsNullOrEmpty(action) || !InputMap.HasAction(action)) return false;
        return Input.IsActionPressed(action);
    }
}