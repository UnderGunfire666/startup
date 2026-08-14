class_name CategoryData
extends Resource

@export var id: String
@export var name: String
## 大类只用于目录展示；实际加入店铺的是子类。
@export var parent_category: String = ""
@export var base_entry_rate: float

## 推荐营业时间段（多段，[start_hour, end_hour)），仅用于初始预填+
## "偏离推荐时段到店率惩罚"的判定基准，不再强制限制玩家能不能选。

@export var preferred_groups: Array[String] = []
@export var preferred_spending_power: Array[String] = []
@export var base_service_speed: String
@export var required_staff: String = ""
@export var required_staff_count: int = 1
@export var required_equipment: String = ""
@export var required_equipment_ids: Array[String] = []
@export var setup_cost_wan: float = 0.3
@export var extra_rent_wan: float = 0.15
