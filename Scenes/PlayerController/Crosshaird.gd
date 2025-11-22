extends Control


@export var color: Color = Color.WHITE
@export var thickness: float = 2.0
@export var length: float = 8.0
@export var gap: float = 4.0
@export var show_center_dot: bool = false
@export var center_dot_readius: float = 3.0
@export var hide_when_free: bool = true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_anchors_preset(LayoutPreset.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if (hide_when_free):
		visible = Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE
	queue_redraw()

func _draw() -> void:
	var center = get_size() / 2.0

	# 水平右侧
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + length, 0), color, thickness)

	# 水平左侧
	draw_line(center - Vector2(gap, 0), center - Vector2(gap + length, 0), color, thickness)

	# 垂直上方
	draw_line(center - Vector2(0, gap), center - Vector2(0, gap + length), color, thickness)

	# 垂直下方
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + length), color, thickness)

	if show_center_dot:
		draw_circle(center, center_dot_readius, color)
