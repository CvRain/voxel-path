using System.Collections.Generic;
using Godot;

namespace TryWorld.Scripts.Blocks;

public partial class BlockAtlas : Node
    {
        [Export] public string DirtPath = "res://Assets/Block/dirt.png";
        [Export] public string GrassPath = "res://Assets/Block/grass.png";
        [Export] public string LogPath = "res://Assets/Block/log.png";
        [Export] public string LeafPath = "res://Assets/Block/leaf.png";

        public Texture2D AtlasTexture;
        public int TileSize; // 假设所有贴图尺寸一致 (方形)
        public int Columns;
        public int Rows;
        public int TileCount;
        private readonly List<Image> _images = new();

        public override void _Ready()
        {
            LoadImages();
            BuildAtlas();
            BlockRegistry.Init();
        }

        private void LoadImages()
        {
            _images.Clear();
            _images.Add(GD.Load<Texture2D>(DirtPath).GetImage());
            _images.Add(GD.Load<Texture2D>(GrassPath).GetImage());
            _images.Add(GD.Load<Texture2D>(LogPath).GetImage());
            _images.Add(GD.Load<Texture2D>(LeafPath).GetImage());
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
            int x = index % Columns;
            int y = index / Columns;
            float u0 = x / (float)Columns;
            float v0 = y / (float)Rows;
            float u1 = (x + 1) / (float)Columns;
            float v1 = (y + 1) / (float)Rows;
            uvMin = new Vector2(u0, v0);
            uvMax = new Vector2(u1, v1);
        }
    }