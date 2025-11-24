# Voxel Palette System (调色板系统) 技术文档

## 1. 核心概念与背景

在早期的体素引擎实现中，我们通常直接使用 `PackedByteArray` (8-bit) 来存储方块数据。这意味着每个体素直接存储方块的 **全局 ID**。

### 传统方式的局限性
1.  **ID 数量限制**: 8-bit 只能存储 0-255 个 ID。如果游戏包含模组，方块数量很容易超过 256 个。
2.  **内存浪费**: 一个只包含“空气”和“石头”的区块，依然需要为每个体素使用 8-bit 甚至 16-bit 的空间，无法利用数据的低熵特性。
3.  **缺乏灵活性**: 难以支持“方块状态”（Block States），例如 `furnace[facing=north, lit=true]`。如果为每种状态分配一个 ID，ID 空间会瞬间爆炸。

### Palette (调色板) 解决方案
Palette 系统引入了 **“间接层”** 的概念。区块不再直接存储全局 ID，而是存储一个指向 **本地调色板 (Local Palette)** 的 **索引 (Index)**。

*   **全局 ID (Global Runtime ID)**: 整个游戏运行期间唯一的 ID，对应具体的方块类型（如 `core:stone` -> `1`）。
*   **本地索引 (Local Index)**: 仅在当前区块内有效的短 ID。
*   **调色板 (Palette)**: 一个映射表，记录了 `Local Index` -> `Global ID` 的对应关系。

---

## 2. 架构设计

### 2.1 数据结构对比

**无 Palette (当前):**
```
Chunk Data: [1, 1, 0, 2, 1, ...] (直接存储全局 ID)
```

**有 Palette (目标):**
```
Palette List: [0: Air, 1: Stone, 2: Dirt] (本区块只用了这3种)

Chunk Data: [1, 1, 0, 2, 1, ...] (存储的是 Palette List 的下标)
```

### 2.2 核心组件

1.  **Global Block Registry (全局注册表)**
    *   **职责**: 维护 `String ID` (如 "core:stone") 到 `Runtime ID` (如 12) 的映射。
    *   **特点**: 游戏启动时动态生成，确保 ID 紧凑且唯一。

2.  **Chunk Palette (区块调色板)**
    *   **职责**: 维护当前区块的 `Local Index` 到 `Global Runtime ID` 的映射。
    *   **数据结构**: 通常是一个动态数组 `Array[int]`。
        *   `palette[0] = 0` (Air)
        *   `palette[1] = 12` (Stone)
        *   `palette[2] = 56` (Iron Ore)
    *   **操作**:
        *   `id_for(index)`: 读数据时，将存储的索引转为真实 ID。
        *   `index_for(id)`: 写数据时，查找该 ID 是否已在表中。如果不在，添加之并返回新索引。

3.  **Chunk Storage (区块存储)**
    *   **职责**: 存储体素的 Palette 索引。
    *   **优化**: 可以根据 Palette 的大小动态调整位深 (Bit Depth)。
        *   如果 Palette 大小 <= 16，每个体素只需 4-bit (用 PackedByteArray 紧凑存储，内存减半)。
        *   如果 Palette 大小 <= 256，使用 8-bit。
        *   如果 Palette 大小 > 256，自动升级到 16-bit 数组。

---

## 3. 工作流程 (Data Flow)

### 3.1 读取方块 (`get_voxel`)
1.  **定位**: 找到体素在数组中的位置 `i`。
2.  **读取索引**: `local_index = data[i]`。
3.  **查表**: `global_id = palette.get(local_index)`。
4.  **返回**: 返回 `global_id` 给游戏逻辑。

### 3.2 写入方块 (`set_voxel`)
假设我们要放置一个 `Diamond Block` (Global ID: 100)。
1.  **查找**: 询问 Palette：“你有 ID 为 100 的记录吗？”
2.  **分配 (如果不存在)**:
    *   Palette 发现没有，将其添加到列表末尾。
    *   假设列表原本长度为 5，现在新索引为 5。
    *   `palette[5] = 100`。
3.  **写入**: 将索引 `5` 写入到体素数组 `data[i] = 5`。

---

## 4. 阶段性实现计划

### Phase 1: 基础映射 (Basic Mapping)
*   **目标**: 引入 `ChunkPalette` 类，但底层存储依然保持 `PackedByteArray` (8-bit)。
*   **限制**: 单个区块内最多只能有 256 种不同的方块（通常足够）。
*   **收益**: 解耦了存储与逻辑 ID，为未来支持 >256 种全局方块打下基础。

### Phase 2: 动态位深 (Adaptive Bit Depth) - *高级优化*
*   **目标**: 根据 Palette 大小动态压缩数据。
*   **实现**:
    *   当 Palette.size < 16 时，使用 `BitPackedArray` (4 bits/voxel)。
    *   当 Palette.size 超过 16 时，自动重组数据，升级到 8 bits/voxel。
*   **收益**: 极大降低内存占用（对于只有空气和石头的区块，内存占用减少 50%~75%）。

### Phase 3: 方块状态 (Block States)
*   **目标**: 支持复杂方块数据。
*   **实现**: Palette 映射的不再是简单的 `int ID`，而是一个 `BlockState` 对象或结构体。
    *   `Palette[3] = { id: "furnace", properties: { facing: "north" } }`
*   **收益**: 彻底解决元数据存储问题。

---

## 5. 示例代码结构

```gdscript
class_name ChunkPalette
extends Resource

# 映射表: Local Index -> Global ID
var _id_map: Array[int] = []
# 反向查找缓存: Global ID -> Local Index
var _reverse_map: Dictionary = {}

func get_global_id(local_index: int) -> int:
    if local_index >= 0 and local_index < _id_map.size():
        return _id_map[local_index]
    return 0 # Default to Air

func get_local_index(global_id: int) -> int:
    # 1. 尝试缓存查找
    if global_id in _reverse_map:
        return _reverse_map[global_id]
    
    # 2. 新增映射
    var new_index = _id_map.size()
    # TODO: 检查是否超过 255 (对于 8-bit 存储)
    
    _id_map.append(global_id)
    _reverse_map[global_id] = new_index
    return new_index
```
