using Godot;

namespace VoxelPath.scenes.levels;

/// <summary>
/// 简单的体素世界设置脚本
/// 用于在 level_playground 场景中快速生成一个基础的方块世界
/// </summary>
public partial class SimpleVoxelWorld : Node3D
{
    [Export] public int WorldSize { get; set; } = 64;
    [Export] public int WorldHeight { get; set; } = 32;

    private VoxelTerrain _terrain;
    private VoxelBlockyLibraryBase _library;
    private VoxelMesherBlocky _mesher;
    private VoxelGeneratorFlat _generator;

    public override void _Ready()
    {
        GD.Print("=== SimpleVoxelWorld Initializing ===");

        SetupVoxelLibrary();
        SetupVoxelMesher();
        SetupVoxelGenerator();
        SetupVoxelTerrain();

        GD.Print("=== SimpleVoxelWorld Ready ===");
    }

    /// <summary>
    /// 创建方块库 - 目前只有石头
    /// </summary>
    private void SetupVoxelLibrary()
    {
        _library = new VoxelBlockyLibrary();

        // ID 0 是空气（自动保留）

        // ID 1 - 石头方块
        var stoneModel = new VoxelBlockyModelCube();
        stoneModel.SetMaterialOverride(0, CreateStoneMaterial());

        _library.AddModel(stoneModel);

        GD.Print("[VoxelLibrary] Created with 1 block (Stone)");
    }

    /// <summary>
    /// 创建石头材质
    /// </summary>
    private Material CreateStoneMaterial()
    {
        var material = new StandardMaterial3D();
        material.AlbedoColor = new Color(0.5f, 0.5f, 0.5f); // 灰色

        // 如果有纹理，可以加载
        var texturePath = "res://Assets/Textures/Natural/stone.png";
        if (ResourceLoader.Exists(texturePath))
        {
            var texture = GD.Load<Texture2D>(texturePath);
            material.AlbedoTexture = texture;
            material.TextureFilter = BaseMaterial3D.TextureFilterEnum.Nearest; // 像素风格
            GD.Print("[Material] Loaded stone texture");
        }
        else
        {
            GD.Print("[Material] Using solid gray color (texture not found)");
        }

        return material;
    }

    /// <summary>
    /// 设置方块网格生成器
    /// </summary>
    private void SetupVoxelMesher()
    {
        _mesher = new VoxelMesherBlocky();
        _mesher.Library = _library;

        GD.Print("[VoxelMesher] Blocky mesher configured");
    }

    /// <summary>
    /// 设置世界生成器 - 简单的平坦世界
    /// </summary>
    private void SetupVoxelGenerator()
    {
        _generator = new VoxelGeneratorFlat();
        _generator.Channel = VoxelBuffer.ChannelId.Type;
        _generator.VoxelType = 1; // 石头的 ID
        _generator.Height = 10.0f; // 10 格高的石头层

        GD.Print("[VoxelGenerator] Flat generator: height=10, type=Stone");
    }

    /// <summary>
    /// 设置并添加 VoxelTerrain 节点
    /// </summary>
    private void SetupVoxelTerrain()
    {
        _terrain = new VoxelTerrain();

        // 基本设置
        _terrain.Mesher = _mesher;
        _terrain.Generator = _generator;

        // 视距设置
        _terrain.ViewDistance = 128; // 可视距离
        _terrain.MaxViewDistance = 256;

        // 添加到场景树
        AddChild(_terrain);
        _terrain.Name = "VoxelTerrain";
        _terrain.Owner = GetTree().EditedSceneRoot ?? this;

        GD.Print($"[VoxelTerrain] Created - ViewDistance: {_terrain.ViewDistance}");
        GD.Print("=== World generation started ===");
    }

    /// <summary>
    /// 获取指定位置的方块 ID
    /// </summary>
    public int GetVoxel(Vector3I position)
    {
        if (_terrain == null) return 0;

        var tool = _terrain.GetVoxelTool();
        return tool.GetVoxel(position);
    }

    /// <summary>
    /// 设置指定位置的方块
    /// </summary>
    public void SetVoxel(Vector3I position, int voxelId)
    {
        if (_terrain == null) return;

        var tool = _terrain.GetVoxelTool();
        tool.SetVoxel(position, voxelId);
    }

    /// <summary>
    /// 射线检测 - 用于方块选择
    /// </summary>
    public bool Raycast(Vector3 origin, Vector3 direction, float maxDistance, out VoxelRaycastResult result)
    {
        result = null;
        if (_terrain == null) return false;

        var tool = _terrain.GetVoxelTool();
        result = tool.Raycast(origin, direction, maxDistance);
        return result != null;
    }
}