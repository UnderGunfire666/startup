class_name SurveyReportBuilder
## 三层了解程度报告生成器：区域情报(0-3级)、区块了解度(0-100/四档)、
## 门面尽调(三态)。三个build函数互相独立，不再依赖调查区聚合权重——
## 了解度本身已经是持久化在StoreState上的真实数值。

const BLOCK_TYPE_LABELS: Dictionary = {
	"school": "学校", "office": "办公", "commercial": "商业",
	"industrial": "工业", "residential": "居民",
}
const TIER_LABELS: Dictionary = {1: "1级", 2: "2级", 3: "3级"}
const REGION_INTEL_LABELS: Dictionary = {
	0: "陌生", 1: "初步了解", 2: "市场掌握", 3: "本地关系网",
}
const DILIGENCE_LABELS: Dictionary = {
	"not_viewed": "未查看", "initial_viewing": "初步看铺", "full_diligence": "完整尽调",
}


## ── 区域情报报告 ──────────────────────────────────────────
static func build_region_report(city_region: CityRegionData, level: int, progress: float) -> Dictionary:
	if city_region == null:
		return {"success": false, "reason": "城市区域不存在"}

	var report := {
		"success": true,
		"city_region_id": city_region.id,
		"name": city_region.name,
		"region_type": city_region.region_type,
		"level": level,
		"level_label": str(REGION_INTEL_LABELS.get(level, "未知")),
		"progress": progress,
	}

	## 0级：仅名称/区位类型/粗略租金/基础标签
	report["rent_band"] = _band_from_modifier(city_region.get_modifier("rent_baseline", 1.0))
	report["tags"] = city_region.tags.duplicate()

	if level >= 1:
		report["density_band"] = city_region.density_band
		report["development_band"] = _band_from_modifier(
			city_region.get_modifier("development_potential", 1.0)
		)

	if level >= 2:
		report["competition_band"] = _band_from_modifier(
			city_region.get_modifier("competition_baseline", 1.0)
		)
		report["spending_power_band"] = _band_from_modifier(
			city_region.get_modifier("spending_power_baseline", 1.0)
		)
		report["weekend_activity_modifier"] = city_region.weekend_activity_modifier

	if level >= 3:
		report["planning_hints"] = city_region.tags.filter(
			func(t: String) -> bool:
				return t.begins_with("planning_") or t.begins_with("policy_") \
					or t.begins_with("investment_") or t.begins_with("risk_")
		)

	return report


## ── 区块了解度报告 ────────────────────────────────────────
static func build_block_report(block: BlockData, understanding: float) -> Dictionary:
	if block == null:
		return {"success": false, "reason": "区块不存在"}

	var tier := SpatialConfig.get_block_understanding_tier(understanding)

	var report := {
		"success": true,
		"block_id": block.id,
		"name": block.name,
		"understanding": understanding,
		"tier": tier,
		"block_type": block.block_type,
		"block_type_label": str(BLOCK_TYPE_LABELS.get(block.block_type, block.block_type)),
		"tier_label": str(TIER_LABELS.get(block.tier, "未知等级")),
		"area_band": _area_band(block.area),
		"traffic_band": _band_from_value(
			PopulationSupplyCalculator.calculate_capacity_base(block), 100.0, 250.0, 500.0
		),
	}

	if tier in ["initial_survey", "market_research", "deep_mastery"]:
		report["population_mix"] = _population_mix_bands(block)
		report["time_heatmap"] = block.active_time_profile.duplicate()
		report["demand_tags"] = block.business_demand_tags.duplicate()

	if tier in ["market_research", "deep_mastery"]:
		report["spending_profile"] = block.spending_profile.duplicate(true)
		report["competition_level"] = str(block.competition_profile.get("competition_level", "medium"))
		report["rent_pressure"] = str(block.competition_profile.get("rent_pressure", "medium"))
		report["rent_trend"] = str(block.competition_profile.get("rent_trend", "stable"))
		report["business_risk"] = str(block.competition_profile.get("business_risk", "medium"))

	if tier == "deep_mastery":
		report["external_attraction"] = float(block.competition_profile.get("external_attraction", 0.0))
		report["tags"] = block.tags.duplicate()
		report["notes"] = block.notes

	return report


## ── 门面尽调报告 ──────────────────────────────────────────
static func build_storefront_report(storefront: StorefrontData, diligence_state: String) -> Dictionary:
	if storefront == null:
		return {"success": false, "reason": "门面不存在"}

	var report := {
		"success": true,
		"storefront_id": storefront.id,
		"name": storefront.name,
		"diligence_state": diligence_state,
		"diligence_label": str(DILIGENCE_LABELS.get(diligence_state, "未知")),
	}

	if diligence_state == "not_viewed":
		return report

	## 初步看铺
	report["monthly_rent_yuan"] = storefront.get_monthly_rent_yuan()
	report["deposit_months"] = storefront.deposit_months
	report["area"] = storefront.area
	report["decoration_level"] = storefront.decoration_level
	report["equipment_condition"] = storefront.equipment_condition
	report["storefront_flow"] = storefront.storefront_flow
	report["inspection_summary"] = storefront.inspection_summary

	if diligence_state != "full_diligence":
		return report

	## 完整尽调
	report["supported_categories"] = storefront.supported_categories.duplicate()
	report["deep_inspection_summary"] = storefront.deep_inspection_summary
	report["inspection_cost"] = storefront.inspection_cost

	return report


static func _band_from_modifier(modifier: float) -> String:
	if modifier < 0.8: return "low"
	if modifier < 1.2: return "medium"
	return "high"


static func _band_from_value(value: float, low_max: float, medium_max: float, high_max: float) -> String:
	if value < low_max: return "low"
	if value < medium_max: return "medium"
	if value < high_max: return "high"
	return "very_high"


static func _area_band(area: float) -> String:
	if area < 100.0: return "small"
	if area < 250.0: return "medium"
	return "large"


static func _population_mix_bands(block: BlockData) -> Dictionary:
	var result: Dictionary = {}
	for group_id in SpatialConfig.POPULATION_GROUPS:
		var weight := block.get_group_weight(group_id)
		result[group_id] = _band_from_value(weight, 0.10, 0.25, 0.45)
	return result
