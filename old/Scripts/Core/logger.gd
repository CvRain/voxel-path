# Scripts/Core/logger.gd
class_name MyLogger
extends Node

enum LogLevel {DEBUG, INFO, WARN, ERROR}

var _log_level: LogLevel = LogLevel.DEBUG
var _file_logging_enabled: bool = false
var _log_file: FileAccess = null

func _ready() -> void:
	if _file_logging_enabled:
		_log_file = FileAccess.open("user://logs/voxel_path.log", FileAccess.WRITE)

static func debug(msg: String) -> void:
	if Constants.DEBUG_ENABLED:
		print("[DEBUG] ", msg)

static func info(msg: String) -> void:
	print("[INFO] ", msg)

static func warn(msg: String) -> void:
	print_rich("[color=yellow][WARN] %s[/color]" % msg)

static func error(msg: String) -> void:
	print_rich("[color=red][ERROR] %s[/color]" % msg)
	push_error(msg)

static func success(msg: String) -> void:
	print_rich("[color=green][SUCCESS] %s[/color]" % msg)
