class_name ProductData
extends Resource

@export var id: String = ""
@export var category_id: String = ""
@export var name: String = ""
@export var target_groups: Array[String] = []
@export var preferred_slots: Array[String] = []
@export var price_tier: String = "medium"           # low/medium/high
@export var average_price: float = 15.0
@export var ingredient_cost_ratio: float = 0.40
@export var complexity: String = "normal"           # simple/normal/complex
@export var differentiation: String = "normal"      # normal/special/strong_special
@export var extra_service_speed_modifier: float = 1.0
@export var notes: String = ""
