class_name CityRegionData
extends Resource
## 固定城市区域（开发者预设）。只提供宏观区位规则和城市背景，
## 不直接参与门店客流结算——具体客流来自其辖属的 BlockData。
## 对照阶段1设计：替代旧 RegionData 的"宏观基调"部分。

@export var id: String = ""
@export var name: String = ""

## 地图边界，用于调查区相交判定、地图UI绘制。
@export var map_bounds: Rect2 = Rect2()

## urban / suburban / town，见 SpatialConfig.CITY_REGION_TYPES
@export var region_type: String = "urban"

## 区位等级 1/2/3，例如核心城区=1，远郊=3（数值含义由具体城市自行约定，
## 阶段2的示例城市里用它表达"越靠核心/越繁华"）。
@export var tier: int = 1

## 背景人口：仅用于城市规模感、事件、剧情、长期招商/租金趋势判断。
## 严禁在SettlementEngine中把它当作门店客流或区块人口的替代/叠加项。
@export var background_population: int = 0

## low / medium / high，纯展示用的密度标签
@export var density_band: String = "medium"

## 区位基调修正，供BlockData的最终数值做整体偏移，而不是直接决定客流。
## 固定包含以下五个key：rent_baseline / traffic_baseline /
## competition_baseline / spending_power_baseline / development_potential
## 取值建议统一用 0.5-1.5 的乘数区间，1.0为中性。
@export var location_modifiers: Dictionary = {
	"rent_baseline": 1.0,
	"traffic_baseline": 1.0,
	"competition_baseline": 1.0,
	"spending_power_baseline": 1.0,
	"development_potential": 1.0,
}

## 周末/工作日整体活跃倍率，1.0为无差异，>1为周末更活跃。
@export var weekend_activity_modifier: float = 1.0

## 辖属区块索引，仅作为数据组织缓存，不是权威数据来源
## （权威关系始终是 BlockData.city_region_id 指回本对象）。
@export var block_ids: Array[String] = []

@export var tags: Array[String] = []
@export var notes: String = ""


func is_valid() -> bool:
	if id.is_empty():
		return false
	if not SpatialConfig.is_valid_tier(tier):
		return false
	if region_type not in SpatialConfig.CITY_REGION_TYPES:
		return false
	return true


func get_modifier(key: String, default_value: float = 1.0) -> float:
	return float(location_modifiers.get(key, default_value))
