class_name RegionData
extends Resource

@export var id: String = ""
@export var name: String = ""
@export var radiation_population: int = 0
@export var population_density: String = "medium"   # low/medium/high
@export var primary_groups: Array[String] = []
@export var secondary_groups: Array[String] = []
@export var spending_power: String = "medium"        # low/medium/high
@export var dwell_time: String = "medium"            # low/medium/high
@export var traffic_sources: Array[String] = []
@export var competition_level: String = "medium"     # low/medium/high
@export var rent_baseline: String = "medium"
## key: "dawn"/"noon"/"night" → 每小时人流（整型）
@export var hourly_foot_traffic_by_slot: Dictionary = {}
@export var weekend_modifier: float = 1.0
@export var notes: String = ""
