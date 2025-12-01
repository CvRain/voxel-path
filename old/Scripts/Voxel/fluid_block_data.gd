class_name FluidBlockData
extends BlockData

@export_group("Fluid Properties")
@export var viscosity: float = 0.8 # Drag factor (0-1)
@export var density: float = 1.0 # Buoyancy factor
@export var flow_speed: int = 5 # How far it flows
@export var is_source: bool = true
@export var infinite_threshold: int = 25 # Number of connected blocks to be infinite

func _init() -> void:
	super._init()
	is_solid = false
	has_collision = false # Fluids don't block movement directly
	is_transparent = true
	hardness = 100.0 # Hard to break with pickaxe? Maybe handled by bucket
