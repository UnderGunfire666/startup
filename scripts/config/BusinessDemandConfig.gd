class_name BusinessDemandConfig
## 建议位置：res://scripts/config/BusinessDemandConfig.gd
##
## 业态对五类人群的需求权重配置，以及业态对同业竞争的敏感系数。
## 用category_id索引；找不到配置时退回DEFAULT_WEIGHTS（五类人群均等权重），
## 不会因为某个品类没配置而让business_match直接归零。

## 各category_id对五类人群的需求权重，建议每个品类总和≈1。
## 这里给出几个示例业态，供阶段2/5案例中的平价餐饮/高客单/午餐咖啡对照；
## 实际接入时按你项目里真实的CategoryData.id补全或调整。
const DEMAND_WEIGHTS: Dictionary = {
	"quick_meal": {
		"student": 0.35, "office_worker": 0.35, "worker": 0.20,
		"family_household": 0.08, "high_spend_household": 0.02,
	},
	"beverage_dessert": {
		"student": 0.40, "office_worker": 0.30, "worker": 0.10,
		"family_household": 0.15, "high_spend_household": 0.05,
	},
	"cafe": {
		"student": 0.20, "office_worker": 0.50, "worker": 0.05,
		"family_household": 0.10, "high_spend_household": 0.15,
	},
	"convenience": {
		"student": 0.20, "office_worker": 0.25, "worker": 0.20,
		"family_household": 0.25, "high_spend_household": 0.10,
	},
	"community_service": {
		"student": 0.05, "office_worker": 0.10, "worker": 0.05,
		"family_household": 0.55, "high_spend_household": 0.25,
	},
	"premium_dining": {
		"student": 0.02, "office_worker": 0.18, "worker": 0.0,
		"family_household": 0.20, "high_spend_household": 0.60,
	},
	"printing_stationery": {
		"student": 0.60, "office_worker": 0.35, "worker": 0.0,
		"family_household": 0.05, "high_spend_household": 0.0,
	},
}

## 未配置权重时的兜底：五类人群均等，business_match不会异常偏向某一类。
const DEFAULT_WEIGHTS: Dictionary = {
	"student": 0.2, "office_worker": 0.2, "worker": 0.2,
	"family_household": 0.2, "high_spend_household": 0.2,
}

## 各业态对"同业竞争"的敏感系数，0-1，越高表示该业态越容易受同类竞争压制。
## 大众化、易复制的业态（快餐、饮品）敏感系数更高；
## 差异化强的业态（社区服务、高客单）敏感系数更低。
const COMPETITION_SENSITIVITY: Dictionary = {
	"quick_meal": 0.45,
	"beverage_dessert": 0.45,
	"cafe": 0.40,
	"convenience": 0.30,
	"community_service": 0.20,
	"premium_dining": 0.25,
	"printing_stationery": 0.25,
}

const DEFAULT_COMPETITION_SENSITIVITY: float = 0.35


static func get_demand_weights(category_id: String) -> Dictionary:
	var weights: Dictionary = DEMAND_WEIGHTS.get(category_id, {})
	if weights.is_empty():
		return DEFAULT_WEIGHTS.duplicate()
	return weights.duplicate()


static func get_competition_sensitivity(category_id: String) -> float:
	return float(COMPETITION_SENSITIVITY.get(category_id, DEFAULT_COMPETITION_SENSITIVITY))
