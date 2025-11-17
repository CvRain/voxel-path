using System.Collections.Generic;
using Godot;

namespace VoxelPath.Scripts.Blocks;

public partial class BlockAtlas : Node
{
    [Export] public string DirtPath = "res://Assets/Blocks/dirt.png";
    [Export] public string GrassTopPath = "res://Assets/Blocks/grass_block_top.png";
    [Export] public string GrassSidePath = "res://Assets/Blocks/grass_block_side.png";
    [Export] public string GrassSideOverlayPath = "res://Assets/Blocks/grass_block_side_overlay.png";
    [Export] public string OakLogPath = "res://Assets/Blocks/oak_log.png";
    [Export] public string OakLogTopPath = "res://Assets/Blocks/oak_log_top.png";
    [Export] public string OakLeavesPath = "res://Assets/Blocks/oak_leaves.png";
    [Export] public string StonePath = "res://Assets/Blocks/stone.png";
    [Export] public string CobblestonePath = "res://Assets/Blocks/cobblestone.png";

    // 草方块和树叶的颜色（参考 Minecraft）
    [Export] public Color GrassColor = new Color(0.49f, 0.78f, 0.33f); // 草绿色
    [Export] public Color OakLeavesColor = new Color(0.38f, 0.70f, 0.20f); // 深绿色

    public Texture2D AtlasTexture;
    public int TileSize; // 假设所有贴图尺寸一致 (方形)
    public int Columns;
    public int Rows;
    public int TileCount;
    private readonly List<Image> _images = [];

    public override void _Ready()
    {
        LoadImages();
        BuildAtlas();
        BlockRegistry.Init();
    }

    private void LoadImages()
    {
        _images.Clear();

        // 0: dirt.png
        _images.Add(GD.Load<Texture2D>(DirtPath).GetImage());

        // 1: grass_block_top.png (灰度图需要染色)
        var grassTop = GD.Load<Texture2D>(GrassTopPath).GetImage();
        _images.Add(TintGrayscaleImage(grassTop, GrassColor));

        // 2: grass_block_side.png (灰度图需要染色)
        var grassSide = GD.Load<Texture2D>(GrassSidePath).GetImage();
        _images.Add(TintGrayscaleImage(grassSide, GrassColor));

        // 3: grass_block_side_overlay.png (灰度图需要染色)
        var grassSideOverlay = GD.Load<Texture2D>(GrassSideOverlayPath).GetImage();
        _images.Add(TintGrayscaleImage(grassSideOverlay, GrassColor));

        // 4: oak_log.png (侧面)
        _images.Add(GD.Load<Texture2D>(OakLogPath).GetImage());

        // 5: oak_log_top.png (顶部和底部)
        _images.Add(GD.Load<Texture2D>(OakLogTopPath).GetImage());

        // 6: oak_leaves.png (灰度图需要染色)
        var oakLeaves = GD.Load<Texture2D>(OakLeavesPath).GetImage();
        _images.Add(TintGrayscaleImage(oakLeaves, OakLeavesColor));

        // 7: stone.png
        _images.Add(GD.Load<Texture2D>(StonePath).GetImage());

        // 8: cobblestone.png
        _images.Add(GD.Load<Texture2D>(CobblestonePath).GetImage());
    }

    /// <summary>
    /// 智能染色：只对灰度像素进行染色，保留已有颜色的像素
    /// 适用于部分灰度部分彩色的纹理（如 grass_block_side.png）
    /// </summary>
    private Image TintGrayscaleImage(Image source, Color tintColor)
    {
        var tinted = Image.CreateEmpty(source.GetWidth(), source.GetHeight(), false, Image.Format.Rgba8);

        for (int y = 0; y < source.GetHeight(); y++)
        {
            for (int x = 0; x < source.GetWidth(); x++)
            {
                var pixel = source.GetPixel(x, y);

                // 检查像素是否为灰度（RGB 值相近）
                if (IsGrayscalePixel(pixel, out float brightness))
                {
                    // 是灰度像素，进行染色
                    var newColor = new Color(
                        tintColor.R * brightness,
                        tintColor.G * brightness,
                        tintColor.B * brightness,
                        pixel.A
                    );
                    tinted.SetPixel(x, y, newColor);
                }
                else
                {
                    // 不是灰度像素，保留原色
                    tinted.SetPixel(x, y, pixel);
                }
            }
        }

        return tinted;
    }

    /// <summary>
    /// 判断像素是否为灰度（RGB 值相近）
    /// </summary>
    /// <param name="pixel">输入像素</param>
    /// <param name="brightness">输出亮度值（0-1）</param>
    /// <param name="threshold">灰度判定阈值，RGB 差异小于此值视为灰度</param>
    /// <returns>是否为灰度像素</returns>
    private bool IsGrayscalePixel(Color pixel, out float brightness, float absoluteThreshold = 0.025f,
        float relativeThreshold = 0.08f)
    {
        float r = pixel.R;
        float g = pixel.G;
        float b = pixel.B;

        // 如果完全透明，不处理
        if (pixel.A < 0.01f)
        {
            brightness = 0;
            return false;
        }

        brightness = (r + g + b) / 3.0f;

    float maxChannel = Mathf.Max(r, Mathf.Max(g, b));
    float minChannel = Mathf.Min(r, Mathf.Min(g, b));
        float delta = maxChannel - minChannel;

        // 只有在“非常低饱和度”或“相对亮度下差异极小”时才判定为灰度
        bool lowSaturation = delta <= absoluteThreshold || delta <= brightness * relativeThreshold;

        return lowSaturation;
    }

    private void BuildAtlas()
    {
        // 简单垂直拼接或水平拼接：这里用垂直拼接
        TileCount = _images.Count;
        TileSize = _images[0].GetWidth();
        Columns = 1;
        Rows = TileCount;

        var atlasImg = Image.CreateEmpty(TileSize * Columns, TileSize * Rows, false, _images[0].GetFormat());
        for (int i = 0; i < _images.Count; i++)
        {
            atlasImg.BlitRect(_images[i], new Rect2I(0, 0, TileSize, TileSize), new Vector2I(0, i * TileSize));
        }

        AtlasTexture = ImageTexture.CreateFromImage(atlasImg);
    }

    // 获取某个 atlas 索引的 UV（归一化 min/max）
    public void GetTileUv(int index, out Vector2 uvMin, out Vector2 uvMax)
    {
        var x = index % Columns;
        var y = index / Columns;
        var u0 = x / (float)Columns;
        var v0 = y / (float)Rows;
        var u1 = (x + 1) / (float)Columns;
        var v1 = (y + 1) / (float)Rows;
        uvMin = new Vector2(u0, v0);
        uvMax = new Vector2(u1, v1);
    }

    public void GetTileUvSubRegion(int index, int subdivisions, int subX, int subY,
        out Vector2 uvMin, out Vector2 uvMax)
    {
        GetTileUv(index, out var tileMin, out var tileMax);
        float stepU = (tileMax.X - tileMin.X) / Mathf.Max(1, subdivisions);
        float stepV = (tileMax.Y - tileMin.Y) / Mathf.Max(1, subdivisions);
        subX = Mathf.Clamp(subX, 0, Mathf.Max(0, subdivisions - 1));
        subY = Mathf.Clamp(subY, 0, Mathf.Max(0, subdivisions - 1));
        uvMin = new Vector2(tileMin.X + subX * stepU, tileMin.Y + subY * stepV);
        uvMax = new Vector2(uvMin.X + stepU, uvMin.Y + stepV);
    }
}