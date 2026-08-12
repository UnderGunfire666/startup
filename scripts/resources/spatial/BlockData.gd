class_name BlockData
extends Resource
## 区块（开发者预设）。人口、活动供给、竞争与业态机会的唯一真实来源。
## 门店客流绝不能跳过区块直接从CityRegionData或"辐射人口"获取。
## 对照阶段2/3设计。

@export var id: String = ""
@export var name: String = ""

@export var city_region_id: String = ""

## 地图边界：调查区相交判定用。
@export var map_bounds: Rect2 = Rect2()
## 区块中心点：门店距离计算、调查区距离权重计算的锚点。
@export var center_position: Vector2 = Vector2.ZERO

## school / office / commercial / industrial / residential
@export var block_type: String = "residential"

## 1/2/3
@export var tier: int = 1

## 面积，逻辑单位（不强制等于㎡），用于容量公式。
@export var area: float = 100.0

## 0-2，默认1.0。政策/事件/升级可调整，代表区块当前开发程度。
@export var development_factor: float = 1.0

## 0-1，区块向外输送客群的基础便利度（道路、入口、隔离带等抽象值）。
@export var accessibility: float = 0.8

## 早/午/晚/夜四时段的相对活跃系数，默认全1（由BlockConfig按类型/等级
## 给出模板，这里的@export值用于策划手工覆盖模板）。
@export var active_time_profile: Dictionary = {
	"morning": 1.0, "noon": 1.0, "evening": 1.0, "night": 1.0,
}

## 五类人群的供给权重，key见SpatialConfig.POPULATION_GROUPS，
## 值建议总和≈1（允许±0.05误差，使用前调用normalize_group_weights()归一）。
@export var group_supply_weights: Dictionary = {
	"student": 0.0, "office_worker": 0.0, "worker": 0.0,
	"family_household": 0.0, "high_spend_household": 0.0,
}

## 客单潜力、价格敏感度、品质偏好等，key暂定：
## price_sensitivity(0-1，越高越敏感) / quality_preference(0-1) /
## spend_potential_tier("low"/"medium"/"high")
@export var spending_profile: Dictionary = {
	"price_sensitivity": 0.5,
	"quality_preference": 0.5,
	"spend_potential_tier": "medium",
}

## 该区块倾向的业态标签，例如"cafe"/"quick_meal"/"convenience"/"printing"
@export var business_demand_tags: Array[String] = []

## 竞争与商业影响。key暂定：
## competition_level("low"/"medium"/"high") / rent_pressure("low"/"medium"/"high")
## rent_trend("up"/"stable"/"down") / business_risk("low"/"medium"/"high")
## external_attraction(0-1，商业区块吸引外来客流的能力)
@export var competition_profile: Dictionary = {
	"competition_level": "medium",
	"rent_pressure": "medium",
	"rent_trend": "stable",
	"business_risk": "medium",
	"external_attraction": 0.0,
}

@export var tags: Array[String] = []
@export var notes: String = ""


func is_valid() -> bool:
	if id.is_empty() or city_region_id.is_empty():
		return false
	if not SpatialConfig.is_valid_block_type(block_type):
		return false
	if not SpatialConfig.is_valid_tier(tier):
		return false
	return true


func get_group_weight(group_id: String) -> float:
	return float(group_supply_weights.get(group_id, 0.0))


func get_time_activity(period: String) -> float:
	return float(active_time_profile.get(period, 1.0))


func normalize_group_weights() -> void:
	## 把group_supply_weights归一化到总和=1，避免策划配置误差累积
	## 到容量计算里被放大。原地修改。
	var total := 0.0
	for g in SpatialConfig.POPULATION_GROUPS:
		total += get_group_weight(g)
	if total <= 0.0:
		return
	for g in SpatialConfig.POPULATION_GROUPS:
		group_supply_weights[g] = get_group_weight(g) / total
