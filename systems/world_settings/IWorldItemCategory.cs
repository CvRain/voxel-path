using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace VoxelPath.systems.world_settings;

public interface IWorldItemCategory
{
    /**
     * 工具类别
     */
    public enum ToolCategory
    {
        Axe,
        Pickaxe,
        Shovel,
        Hammer,
        Scissors,
        Brush,
        Scythe,
        Hoe
    }
}