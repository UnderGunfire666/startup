class_name StorefrontData
extends Resource

@export var id: String = ""
@export var name: String = ""
@export var region_id: String = ""
@export var monthly_rent_wan: float = 1.0       # 配置用万元，加载时换算
@export var area: int = 20
@export var decoration_level: String = "normal" # poor/normal/good
@export var storefront_flow: String = "main"    # main/secondary/hidden
@export var flow_share: float = 0.4
@export var supported_categories: Array[String] = []
@export var equipment_condition: String = "normal"
@export var hourly_capacity_base: int = 20
@export var notes: String = ""

@export var deposit_months: int = 2
@export var inspection_cost: float = 500.0
@export var inspection_summary: String = ""
@export var deep_inspection_summary: String = ""

## 门面所属固定城市区域，迁移自旧 region_id
@export var city_region_id: String = ""
## 门面地图坐标，用于计算到各区块的距离
@export var map_position: Vector2 = Vector2.ZERO
## Nearest RoadSegment id; kept separate from visual storefront flow data.
@export var road_segment_id: String = ""
## 门面截流/可见度修正，迁移自旧 flow_share 的语义（不再是"整区客流分成比例"）
@export var capture_modifier: float = 1.0
## 门面自身易达性（临街、停车、入口等），配合区块accessibility共同决定可达性
@export var accessibility_modifier: float = 1.0

func get_monthly_rent_yuan() -> float:
	return monthly_rent_wan * 10000.0
