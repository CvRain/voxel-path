# Scripts/Core/constants.gd
class_name Constants
extends Node

const VERSION: String = "0.1.0"
const GAME_NAME: String = "Voxel Path: Artisan's Realm"

const VOXEL_SIZE: float = 0.25
const CHUNK_SIZE: int = 64 # 16 meters wide (64 * 0.25)
const CHUNK_WORLD_SIZE: float = CHUNK_SIZE * VOXEL_SIZE
const SEA_LEVEL: int = 1024 # 海平面高度（格子），对应256方块（1024*0.25），地表与水体主要分布于此
const MAX_TERRAIN_HEIGHT: int = 3072 # 自然方块生成上限（格子），对应768方块（3072*0.25），用于山地/悬崖等地形
const VOXEL_MAX_HEIGHT: int = 1024 # 256 meters high (1024 * 0.25) - Adjusted from 4096 for initial stability

const AIR_BLOCK_ID: int = 0
const FIRST_MOD_BLOCK_ID: int = 256

const DATA_BLOCKS_PATH: String = "res://Data/blocks"
const DATA_BLOCKS_MANIFEST: String = "res://Data/blocks/_manifest.json"
const MOD_PATH: String = "user://mods"

#const DEBUG_ENABLED: bool = OS.is_debug_build()
const DEBUG_ENABLED: bool = true
const DEBUG_BLOCK_LOADING: bool = true
const DEBUG_TEXTURE_LOADING: bool = true
 
const MAX_CHUNKS_PER_FRAME: int = 4
const VIEW_DISTANCE: int = 8
const LOD_LEVELS: int = 3

const CHUNK_SECTION_SIZE: int = 64 # Height of each sub-chunk section
