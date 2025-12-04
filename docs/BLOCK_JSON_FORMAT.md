# 方块 JSON 格式规范

## 文件位置
- 主清单：`Data/blocks/_manifest.json`
- 分类配置：`Data/blocks/{category}/config.json`
- 方块定义：`Data/blocks/{category}/{block_name}.json`

## 方块 JSON 格式

### 基本示例（统一纹理）
```json
{
  "name": "stone",
  "display_name": "Stone",
  "category": "nature",
  "description": "A common stone block",

  "textures": {
    "all": "res://Assets/Textures/Natural/stone.png"
  },

  "hardness": 1.5,
  "resistance": 2.0,
  "is_solid": true,
  "is_transparent": false,
  "has_collision": true,

  "can_place": true,
  "can_break": true,
  "tool_required": "pickaxe",
  "mine_level": 1,
  "base_mine_time": 1.5
}
```

### 多纹理示例
```json
{
  "name": "grass",
  "display_name": "Grass Block",
  "textures": {
    "top": "res://Assets/Textures/Natural/grass_block.png",
    "bottom": "res://Assets/Textures/Natural/dirt.png",
    "north": "res://Assets/Textures/Natural/grass_block.png",
    "south": "res://Assets/Textures/Natural/grass_block.png",
    "east": "res://Assets/Textures/Natural/grass_block.png",
    "west": "res://Assets/Textures/Natural/grass_block.png"
  }
}
```

### 带状态的方块示例
```json
{
  "name": "oak_log",
  "display_name": "Oak Log",
  "textures": {
    "top": "res://Assets/Textures/Natural/oak_log_top.png",
    "bottom": "res://Assets/Textures/Natural/oak_log_top.png",
    "north": "res://Assets/Textures/Natural/oak_log.png",
    "south": "res://Assets/Textures/Natural/oak_log.png",
    "east": "res://Assets/Textures/Natural/oak_log.png",
    "west": "res://Assets/Textures/Natural/oak_log.png"
  },
  "state_definitions_json": "{\"facing\": [\"north\", \"south\", \"east\", \"west\", \"up\", \"down\"]}",
  "default_state_json": "{\"facing\": \"up\"}"
}
```

## 字段说明

### 必填字段
- `name` (string): 方块内部标识符（小写，下划线分隔）
- `display_name` (string): 显示名称
- `category` (string): 分类名称
- `textures` (object): 纹理路径配置

### 纹理配置
- **统一纹理**: 使用 `"all"` 字段
- **分别指定**: 使用 `top`, `bottom`, `north`, `south`, `east`, `west`
- **优先级**: 具体方向 > `all`

### 物理属性
- `hardness` (float): 硬度，影响破坏时间（默认：1.0）
- `resistance` (float): 抗爆炸性（默认：1.0）
- `is_solid` (bool): 是否为实心方块（默认：true）
- `is_transparent` (bool): 是否透明（默认：false）
- `has_collision` (bool): 是否有碰撞（默认：true）

### 交互属性
- `can_place` (bool): 是否可放置（默认：true）
- `can_break` (bool): 是否可破坏（默认：true）
- `tool_required` (string): 所需工具类型
  - 可选值：`"none"`, `"axe"`, `"pickaxe"`, `"shovel"`, `"hammer"`, `"scissors"`, `"brush"`, `"scythe"`, `"hoe"`
- `mine_level` (int): 所需工具等级（默认：0）
- `base_mine_time` (float): 基础挖掘时间（秒）

### 方块状态（可选）
- `state_definitions_json` (string): JSON 格式的状态定义
- `default_state_json` (string): JSON 格式的默认状态

## 命名规范
- ✅ 使用 `textures` 而非 `texture_paths`
- ✅ 使用 `top`/`bottom` 而非 `up`/`down`
- ✅ 使用 `base_mine_time` 而非 `mine_time`
- ✅ 所有字段名使用蛇形命名（snake_case）

## 示例文件结构
```
Data/blocks/
├── _manifest.json
├── nature/
│   ├── config.json
│   ├── stone.json
│   ├── dirt.json
│   ├── grass.json
│   └── oak_log.json
├── metals/
│   ├── config.json
│   └── ...
└── ores/
    ├── config.json
    └── ...
```
