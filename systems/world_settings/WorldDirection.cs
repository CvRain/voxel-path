using System.IO;
using Godot;
using Godot.Collections;

namespace VoxelPath.systems.world_settings;

public partial class WorldDirection : Node
{
    public enum BaseDirection
    {
        East,
        West,
        North,
        South,
        Up,
        Down,
        Left,
        Right,
        Forward,
        Back
    }

    public readonly Dictionary<BaseDirection, Vector3I> DirectionVectors = new()
    {
        { BaseDirection.East, Vector3I.Right },
        { BaseDirection.West, Vector3I.Left },
        { BaseDirection.North, Vector3I.Back },
        { BaseDirection.South, Vector3I.Forward },
        { BaseDirection.Up, Vector3I.Up },
        { BaseDirection.Down, Vector3I.Down },
        { BaseDirection.Left, Vector3I.Left },
        { BaseDirection.Right, Vector3I.Right },
        { BaseDirection.Forward, Vector3I.Forward },
        { BaseDirection.Back, Vector3I.Back }
    };
}