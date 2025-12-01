using Godot;

namespace VoxelPath.entities.player.scripts;

public partial class ActionAttribution : Resource
{
    [Export] public string InputLeft { get; set; } = "player_left";
    [Export] public string InputRight { get; set; } = "player_right";
    [Export] public string InputForward { get; set; } = "player_forward";
    [Export] public string InputBackward { get; set; } = "player_backward";
    [Export] public string InputJump { get; set; } = "player_jump";
    [Export] public string InputSprint { get; set; } = "player_sprint";
    [Export] public string InputFlyDown { get; set; } = "player_down";
    [Export] public string InputNoclipToggle { get; set; } = "player_noclip_toggle";
    [Export] public string InputRightClick { get; set; } = "player_right_click";
    [Export] public string InputLeftClick { get; set; } = "player_left_click";
}