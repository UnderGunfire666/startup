class_name ProductData
extends Resource

@export var id: String
@export var category_id: String
## 通用商品会出现在每一个子类的菜单中。
@export var is_universal: bool = false
@export var name: String
@export var target_groups: Array[String] = []
@export var preferred_hour_ranges: Array[Vector2i] = []
@export var price_tier: String
@export var average_price: float
@export var ingredient_cost_per_unit: float = 3.0
@export var utility_cost_per_unit: float = 0.5
@export var suggested_margin_rate: float = 0.6
@export var complexity: String
@export var differentiation: String
@export var extra_service_speed_modifier: float = 1.0
@export var notes: String = ""
@export var recipe: Array[Dictionary] = []

func get_actual_margin_rate(price: float) -> float:
	if price <= 0.0:
		return 0.0
	return (price - ingredient_cost_per_unit - utility_cost_per_unit) / price
