class_name CategoryData
extends Resource

@export var id: String
@export var name: String
@export var base_entry_rate: float

## 推荐营业时间段（多段，[start_hour, end_hour)），仅用于初始预填+
## "偏离推荐时段到店率惩罚"的判定基准，不再强制限制玩家能不能选。
@export var suggested_open_hour_ranges: Array[Vector2i] = []

@export var preferred_groups: Array[String] = []
@export var preferred_spending_power: Array[String] = []
@export var base_service_speed: String
@export var key_staff_type: String
@export var missing_key_staff_capacity_penalty: float
@export var missing_key_staff_conversion_penalty: float
@export var missing_key_staff_reputation_penalty: float
@export var required_area: float = 10.0
@export var setup_cost_wan: float = 0.3
@export var extra_rent_wan: float = 0.15
