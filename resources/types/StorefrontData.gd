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

func get_monthly_rent_yuan() -> float:
	return monthly_rent_wan * 10000.0
