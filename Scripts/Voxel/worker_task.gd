# Scripts/Voxel/worker_task.gd
# 区块/Section生成的异步worker任务封装

class_name WorkerTask
extends RefCounted

var chunk_pos: Vector2i
var stage: int
var params: Dictionary = {}
var result: Dictionary = {}

func _init(_chunk_pos: Vector2i, _stage: int, _params: Dictionary = {}):
	chunk_pos = _chunk_pos
	stage = _stage
	params = _params

# 结果回调（主线程应用）
func set_result(res: Dictionary):
	result = res
