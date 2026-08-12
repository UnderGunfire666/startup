class_name RegionData
extends Resource

@export var id: String = ""
@export var name: String = ""
@export var radiation_population: int = 0
@export var population_density: String = "medium"
@export var primary_groups: Array[String] = []
@export var secondary_groups: Array[String] = []
@export var spending_power: String = "medium"
@export var dwell_time: String = "medium"
@export var traffic_sources: Array[String] = []
@export var competition_level: String = "medium"
@export var rent_baseline: String = "medium"

## 按小时存储客流基准值，数组长度固定24，下标即小时(0-23)。
@export var hourly_foot_traffic_by_hour: Array[int] = []

@export var weekend_modifier: float = 1.0
@export var notes: String = ""
@export var research_cost: float = 800.0
