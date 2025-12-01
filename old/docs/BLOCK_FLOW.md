# 方块系统完整实现流程 (Block System Implementation Flow)

本文档详细描述了从创建一个方块的配置文件，到该方块最终被放置在游戏世界中的完整技术流程。

## 1. 定义方块 (Configuration)

一切始于 JSON 配置文件。开发者在 `Data/blocks` 目录下创建方块定义。

**示例: `Data/blocks/core/copper.json`**
```json
{
  "name": "copper_block",
  "display_name": "Copper Block",
  "textures": { "all": "res://Assets/Textures/copper.png" },
  
  // 定义状态属性 (Block States)
  "states": {
    "oxidization": [0, 1, 2, 3],
    "waxed": [true, false]
  },
  "default_state": {
    "oxidization": 0,
    "waxed": false
  }
}
```

---

## 2. 加载与注册 (Loading & Registration)

游戏启动时，`BlockManager` 负责加载流程。

### 2.1 读取配置
*   `BlockManager` 扫描 `Data/blocks` 目录。
*   解析 JSON，创建 `BlockData` 实例。
*   此时 `BlockData` 包含名称、贴图路径和状态定义，但还没有 ID。

### 2.2 注册方块 (Block Registration)
*   调用 `BlockRegistry.register_block(block)`。
*   **ID 分配**:
    *   检查 `user://level_block_mappings.json` (Level ID Mapping)。
    *   如果该方块名已存在，复用旧 ID。
    *   如果是新方块，分配 `_next_free_id` 并持久化到磁盘。
*   **结果**: `core:copper_block` 被分配了 **Global Block ID** (例如 `15`)。

### 2.3 生成状态 (State Generation)
*   调用 `BlockStateRegistry.register_block_states(block)`。
*   **笛卡尔积计算**: 系统计算所有可能的属性组合。
    *   `{ox:0, wax:true}`, `{ox:0, wax:false}`, `{ox:1, wax:true}` ... 共 4 * 2 = 8 种组合。
*   **State ID 分配**: 为每种组合分配唯一的 **Global State ID**。
    *   State 1000 -> Block 15 + `{ox:0, wax:false}` (默认)
    *   State 1001 -> Block 15 + `{ox:0, wax:true}`
    *   ...
*   **缓存**: 建立 `BlockID + Properties -> StateID` 的快速查找表。

---

## 3. 放置方块 (Placement)

当玩家或世界生成器想要在 `(x, y, z)` 放置一个方块时：

### 3.1 确定目标状态
*   **输入**: "我要放一个铜块，氧化度为 2"。
*   **查找**: 调用 `BlockStateRegistry.get_state_id_by_properties(15, {"oxidization": 2})`。
*   **结果**: 获取到 **Global State ID** (例如 `1004`)。

### 3.2 区块存储 (Chunk Storage)
*   **定位**: 找到对应的 `Chunk` 对象。
*   **Palette 映射**:
    *   调用 `chunk.palette.get_local_index(1004)`。
    *   Palette 检查内部列表：
        *   如果 `1004` 已存在（例如在索引 `5`），返回 `5`。
        *   如果不存在，将 `1004` 追加到列表末尾（分配新索引 `6`），返回 `6`。
*   **写入数组**: `chunk.voxels[index] = 6`。
    *   注意：`voxels` 数组只存储 8-bit 的 **Local Index**，极大地节省了内存。

---

## 4. 渲染与网格生成 (Rendering)

当 Chunk 需要更新网格时：

### 4.1 准备数据
*   主线程创建 `voxels` 数组和 `palette` 映射表的 **快照 (Snapshot)**。
*   将快照发送给后台线程 (`WorkerThreadPool`)。

### 4.2 遍历与解析
*   后台线程遍历 16x16x16 的体素。
*   **读取**: 获取 Local Index (例如 `6`)。
*   **还原**: 查快照表 `palette_map[6]` -> 得到 Global State ID `1004`。
*   **获取数据**:
    *   调用 `BlockStateRegistry.get_state(1004)` 获取 `BlockState` 对象。
    *   从 `BlockState` 中获取 `Block ID` (15)。
    *   从 `BlockRegistry` 获取 `BlockData` (贴图、模型)。

### 4.3 构建网格
*   根据 `BlockData` 的贴图信息，生成顶点和 UV。
*   **状态影响 (未来)**: 如果状态是 `facing: north`，网格生成器会旋转 UV 或模型。
*   最终生成 `ArrayMesh` 并提交给 GPU。

---

## 总结

1.  **JSON**: 定义属性。
2.  **Registry**: 分配 `Block ID` 和 `State ID`。
3.  **Palette**: 将 `State ID` 压缩为 `Local Index` 存入 Chunk。
4.  **Mesh Gen**: 将 `Local Index` 还原为 `State ID` -> `Block Data` 进行渲染。

这个架构确保了：
*   **灵活性**: 支持无限的方块和状态。
*   **内存效率**: Chunk 存储极其紧凑。
*   **存档兼容**: ID 映射保证了存档的长期稳定性。
