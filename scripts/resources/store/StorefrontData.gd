class_name StorefrontData
extends Resource

@export var id: String = ""
@export var name: String = ""
@export var region_id: String = ""
@export var monthly_rent_wan: float = 1.0       # 配置用万元，加载时换算
## Usable interior area for equipment and operations.
@export var area: float = 10.0
## Ground footprint. Must be an integer multiple of one 3.5m by 3.5m grid cell.
@export var footprint_area: float = 12.25
@export var decoration_level: String = "normal" # poor/normal/good
@export var storefront_flow: String = "main"    # main/secondary/hidden
@export var flow_share: float = 0.4
@export var supported_categories: Array[String] = []
@export var equipment_condition: String = "normal"
@export var notes: String = ""

@export var deposit_months: int = 2
@export var inspection_cost: float = 500.0
@export var inspection_summary: String = ""
@export var deep_inspection_summary: String = ""

## 门面所属固定城市区域，迁移自旧 region_id
@export var city_region_id: String = ""
## 门面地图坐标，用于计算到各区块的距离
@export var map_position: Vector2 = Vector2.ZERO
## Owning map block. This is the authoritative relationship used by the map editor.
@export var block_id: String = ""
## Position relative to the centre of block_id, so a storefront follows its block exactly.
@export var block_local_position: Vector2 = Vector2.ZERO
## Grid cells occupied by this storefront. A storefront always occupies at least one connected cell.
@export var grid_cells: Array[Vector2i] = []
## Nearest RoadSegment id; kept separate from visual storefront flow data.
@export var road_segment_id: String = ""
## The street-facing side used to align facade and interior layout geometry.
@export_enum("north", "south", "east", "west") var frontage_side: String = "south"
## Start cell of the two-cell default entrance on the derived facade grid.
@export var default_entrance_offset: int = -1
## 门面截流/可见度修正，迁移自旧 flow_share 的语义（不再是"整区客流分成比例"）
@export var capture_modifier: float = 1.0
## 门面自身易达性（临街、停车、入口等），配合区块accessibility共同决定可达性
@export var accessibility_modifier: float = 1.0
## 线下知名度影响半径（地图逻辑单位）。仅覆盖范围内的 Block 接收线下曝光与口碑传播。
@export var awareness_radius: float = 35.0
## True only when the map author intentionally overrides the size-based radius formula.
@export var awareness_radius_manual_override: bool = false
## 门面自身被注意、被记住的效率；道路 Exposure 会与此项共同决定线下知名度增长。
@export var awareness_exposure_modifier: float = 1.0

func get_monthly_rent_yuan() -> float:
	return monthly_rent_wan * 10000.0
