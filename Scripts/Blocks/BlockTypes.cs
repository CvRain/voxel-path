using Godot;
using System;

namespace VoxelPath.Scripts.Blocks;

public enum BlockType : ushort
{
    Air,
    Dirt,
    Grass,
    GrassFull,
    Stone,
    Cobblestone,
    OakLog,
    OakLeaves,
    // 调试用方块：6 个面全部使用不同贴图，方便检查朝向
    Debug
}