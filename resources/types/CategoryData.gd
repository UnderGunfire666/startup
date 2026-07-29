class_name CategoryData
extends Resource

@export var id: String = ""
@export var name: String = ""
@export var base_entry_rate: float = 0.025
@export var default_open_slots: Array[String] = []  # ["dawn","noon","night"]
@export var preferred_groups: Array[String] = []
@export var preferred_spending_power: Array[String] = []
@export var preferred_slots: Array[String] = []
@export var base_service_speed: String = "high"     # high/medium/slow
@export var key_staff_type: String = "none"         # chef/baker/none
@export var missing_key_staff_capacity_penalty: float = 0.0
@export var missing_key_staff_conversion_penalty: float = 0.0
@export var missing_key_staff_reputation_penalty: float = 0.0
@export var allowed_strategies: Array[String] = ["standard", "extend", "shorten"]
