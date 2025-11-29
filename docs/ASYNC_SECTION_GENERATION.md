# 异步 Section 生成（变更日志）

日期: 2025-11-28
作者: 自动补丁（由协同助手实作）

## 概述
本次提交将体素区块生成的“Section 级体素计算”迁移到后台工作线程，以显著降低主线程峰值 CPU 占用，改善游戏启动与运行时的卡顿现象。

主要目标：
- 把重 CPU 的噪声计算与列/层填充移到后台线程（WorkerThreadPool），主线程只负责将计算结果回写到 `Chunk` 并触发网格更新。
- 把原来的“整区同步生成”替换为“按 Section 拆分并入队”的机制，配合已有的分帧调度降低单帧压力。
- 修复了将邻居 `voxels` 直接传给工作线程导致的竞态（改为复制）。

## 修改文件（摘要）
- `Scripts/Voxel/world_generator.gd`
  - 新增 `generate_chunk_section_async(chunk, section_index, stage)` 接口，将 section 级生成任务提交到 worker。
  - 新增 `_thread_generate_section(...)`：在工作线程中建立本地噪声实例（确定性）、计算该 section 内的 voxel（以 `PackedInt32Array` 返回），并使用 `call_deferred` 将结果传回 `Chunk`。

- `Scripts/Voxel/chunk.gd`
  - 新增 `_apply_section_voxels(section_index, voxel_data, stage)`：在主线程回写 worker 结果（批量调用 `set_voxel_raw`），标记该 section 已生成，并安排该 section 的网格生成。
  - 修复：对传入后台线程的邻居 `voxels` 使用 `.duplicate()`（避免竞态）。

- `Scenes/RandomWorld/RandomWorld.gd`
  - 将原本直接在主线程执行的 `generate_chunk_section` 调用替换为异步提交 `generate_chunk_section_async`。
  - 将“整区入队”拆成 Section 级入队（已在此前改动完成），并添加 `_on_chunk_section_complete` 回调以在 section 回写后推进阶段。
  - 保持并发控制（`_max_generations_per_frame` 与 `GENERATION_INTERVAL`）以限制每帧提交的任务量。

## 设计注意点与限制
- 线程安全：后台线程不会触碰 SceneTree 或节点数据；只使用任务快照（整型、Vector3i 等）和本地创建的 `FastNoiseLite` 实例进行计算，结果通过 `call_deferred` 安全回写。
- 一致性：后台使用与主生成器相同的噪声配置（频率、分形参数等）以保证生成结果可重复且一致。
- 数据格式：工作线程返回 `PackedInt32Array`，以 4 个整数为单元 (x, y, z, block_id)，主线程按序写回以减少对象分配。
- 目前为了简化实现，矿石/洞穴生成在 worker 中做了简化（可在后续迭代中丰富），并保留了阶段化流程（BASE_TERRAIN -> WATER_AND_SURFACE -> ORES_AND_CAVES -> DECORATIONS）。

## 推荐的后续改进（优先级）
1. 实现工作线程中更完整的矿脉/洞穴算法，并在 worker 端尽量减少返回数据量（使用本地小型 palette、压缩格式等）。
2. 为生成队列实现显式上限（如 `MAX_SECTION_QUEUE`），并对超出队列的请求采取降级（例如延迟或拒绝）。
3. 将 `WorldGenerator` 的更多逻辑转为线程可运行（惰性初始化本地资源、避免共享状态）。
4. 引入配置化线程数与队列限流（参考 luanti 的 emerge 设计，根据可用内存和 CPU 自动调节线程数）。

## 如何验证（本地运行步骤）
1. 启动项目并进入主场景（`Scenes/RandomWorld/RandomWorld.tscn`）。
2. 观察首次进入世界时的 CPU 使用率与 FPS。应比之前明显平滑，避免长时间 100% 占用和大幅帧掉落。
3. 若需要更高吞吐量：在 `Scenes/RandomWorld/RandomWorld.gd` 中调整 `_max_generations_per_frame`（建议在 1..4 之间逐步测试）。

---
如果你希望我继续，我可以：
- 把矿石/洞穴生成也完整迁移到 worker（并实现更紧凑的返回格式）；
- 添加队列上限与动态线程数配置；
- 将本次修改写入主 CHANGELOG，并把 README 中的“生成流程”部分更新为异步实现说明。

如果现在就要我继续实现第 2 步（队列上限或 worker 端更完整的 ore/cave），告诉我优先级，我会继续。