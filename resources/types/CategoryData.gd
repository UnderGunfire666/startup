class_name CategoryData
extends Resource

@export var id: String
@export var name: String
@export var base_entry_rate: float
@export var default_open_slots: Array[String] = []
@export var preferred_groups: Array[String] = []
@export var preferred_spending_power: Array[String] = []
@export var preferred_slots: Array[String] = []
@export var base_service_speed: String
@export var key_staff_type: String
@export var missing_key_staff_capacity_penalty: float
@export var missing_key_staff_conversion_penalty: float
@export var missing_key_staff_reputation_penalty: float
@export var allowed_strategies: Array[String] = []
@export var required_area: float = 10.0
@export var setup_cost_wan: float = 0.3
@export var extra_rent_wan: float = 0.15
