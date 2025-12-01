using Godot;

namespace VoxelPath.entities.player.scripts;

public partial class PlayerAttribution: Resource
{
    [ExportGroup("Movement Settings")]
    [Export] public bool EnableMove { get; set; } = true;
    [Export] public bool EnableGravity { get; set; } = true;
    [Export] public bool EnableJump { get; set; } = true;
    [Export] public bool EnableSprint { get; set; } = true;
    [Export] public bool EnableFly { get; set; } = true;
    [Export] public bool EnableNoclip { get; set; } = true;
    [Export] public bool EnableSwim { get; set; } = true;

    [ExportSubgroup("Player movement steps")]
    [Export] public float StepHeight { get; set; } = 1.1f;
    [Export] public float StepSmoothTime { get; set; } = 0.15f;
    
    [ExportGroup("Speeds")]
    [Export] public float LookSpeed { get; set; } = 0.0035f;
    [Export] public float BaseSpeed { get; set; } = 4.4f;
    [Export] public float SprintSpeed { get; set; } = 6.0f;
    [Export] public float JumpVelocity { get; set; } = 4.5f;
    [Export] public float FlySpeed { get; set; } = 12.0f;
    [Export] public float SwimSpeed { get; set; } = 4.0f;

    [ExportGroup("Interaction")]
    [Export] public float InteractionDistance { get; set; } = 5.0f;

    [ExportGroup("Tuning")] 
    [Export] public float Acceleration { get; set; } = 12.0f;
    [Export] public float Deceleration { get; set; } = 16.0f;
    [Export] public float MaxPitchDegrees { get; set; } = 89.0f;
    // [Export] public float FluidBuoyancy { get; set; } = 1.2f;
    // [Export] public float FluidDrag { get; set; } = 0.98f;
}