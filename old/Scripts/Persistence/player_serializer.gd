class_name PlayerSerializer
extends RefCounted

const FILE_NAME = "player.json"

static func save_player(player: Node3D, folder_path: String) -> void:
	# 确保目录存在
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(folder_path):
		dir.make_dir_recursive(folder_path)
		
	var data = {
		"position": {
			"x": player.global_position.x,
			"y": player.global_position.y,
			"z": player.global_position.z
		},
		"rotation": {
			"y": player.rotation.y,
			"head_x": 0.0
		}
	}
	
	var head = player.get_node_or_null("Head")
	if head:
		data.rotation.head_x = head.rotation.x
		
	var full_path = folder_path.path_join(FILE_NAME)
	var file = FileAccess.open(full_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		# print("Saved player state to %s" % full_path)

static func load_player(player: Node3D, folder_path: String) -> bool:
	var full_path = folder_path.path_join(FILE_NAME)
	if not FileAccess.file_exists(full_path):
		return false
		
	var file = FileAccess.open(full_path, FileAccess.READ)
	if not file:
		return false
		
	var json_text = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("Failed to parse player data: %s" % json.get_error_message())
		return false
		
	var data = json.data
	
	if "position" in data:
		var pos = data.position
		player.global_position = Vector3(pos.x, pos.y, pos.z)
		
	if "rotation" in data:
		var rot = data.rotation
		player.rotation.y = rot.y
		
		var head = player.get_node_or_null("Head")
		if head:
			head.rotation.x = rot.head_x
			
		# 更新 ProtoController 的内部状态
		# ProtoController 使用 _look_rotation 来控制每一帧的旋转
		# 如果不更新它，下一帧玩家视角会跳回原来的位置
		if "_look_rotation" in player:
			player._look_rotation = Vector2(rot.head_x, rot.y)
			
	return true
