class_name TradeAreaCalculator
## 建议位置：res://scripts/spatial/TradeAreaCalculator.gd
##
## 门面商圈计算核心。把 PopulationSupplyCalculator 给出的区块供给，
## 按距离衰减→可达性→业态匹配→竞争修正的顺序聚合，得出门面在某个
## 业态/小时下的有效客群，对应阶段5设计的完整链路。
##
## 输入不依赖GameManager/StoreState，方便单独做数值调试和单元测试。

## 门面默认只考虑这个半径内的区块，超出视为不参与商圈。
## 逻辑单位，需与地图坐标系统一（阶段2约定的1个逻辑单位）。
const DEFAULT_MAX_RADIUS: float = 1200.0

## 距离衰减曲线形状，>1让近处优势更明显，避免远处大型商业区无条件碾压。
const DISTANCE_DECAY_ALPHA: float = 1.3

## 竞争等级文本 → 0-1数值，供competition_mod计算使用。
const COMPETITION_LEVEL_VALUE: Dictionary = {
	"low": 0.3,
	"medium": 0.6,
	"high": 1.0,
}


static func calculate_snapshot(
	storefront: StorefrontData,
	category_id: String,
	product_id: String,
	hour: int,
	city_region: CityRegionData,
	all_blocks: Array[BlockData],
	is_weekend: bool = false,
	max_radius: float = DEFAULT_MAX_RADIUS,
	block_visitor_multipliers: Dictionary = {},
	city_region_visitor_multiplier: float = 1.0,
	day: int = 1
) -> TradeAreaSnapshot:
	var snapshot := TradeAreaSnapshot.new()
	snapshot.storefront_id = storefront.id if storefront != null else ""
	snapshot.category_id = category_id
	snapshot.product_id = product_id
	snapshot.hour = hour
	snapshot.period = SpatialConfig.get_period_for_hour(hour)

	if storefront == null or city_region == null:
		return snapshot

	var reachable_totals := SpatialConfig.make_empty_group_weights()
	var external_total := 0.0
	var weighted_competition_sum := 0.0
	var weighted_competition_denominator := 0.0

	for block in all_blocks:
		if block == null or not block.is_valid():
			continue
		if block.city_region_id != storefront.city_region_id:
			continue

		var distance := storefront.map_position.distance_to(block.center_position)
		if distance >= max_radius:
			continue

		var decay := _calculate_distance_decay(distance, max_radius)
		if decay <= 0.0:
			continue

		var accessibility_mod := _calculate_accessibility_mod(block, storefront)
		var match_score := _calculate_business_match(block, category_id)
		var competition_mod := _calculate_competition_mod(block, category_id)

		var dynamic_visitor_multiplier := maxf(0.0, float(block_visitor_multipliers.get(block.id, 1.0)))
		var modifier := decay * accessibility_mod * match_score * competition_mod * dynamic_visitor_multiplier * maxf(0.0, city_region_visitor_multiplier)
		if modifier <= 0.0:
			continue

		var group_supply := PopulationSupplyCalculator.calculate_activity_supply_by_group(
			block, snapshot.period, city_region, is_weekend
		)
		var external_flow := PopulationSupplyCalculator.calculate_external_flow(
			block, snapshot.period, city_region, is_weekend
		)

		var block_contribution := 0.0
		var contributed_groups: Dictionary = {}

		for group_id in SpatialConfig.POPULATION_GROUPS:
			var raw_supply := float(group_supply.get(group_id, 0.0)) * DemandPatternCalculator.get_group_multiplier(block, group_id, day, hour)
			var contributed := raw_supply * modifier

			reachable_totals[group_id] = float(reachable_totals[group_id]) + contributed
			contributed_groups[group_id] = contributed
			block_contribution += contributed

		var contributed_external := external_flow * modifier
		external_total += contributed_external
		block_contribution += contributed_external

		snapshot.block_contributions.append({
			"block_id": block.id,
			"distance": distance,
			"distance_decay": decay,
			"accessibility_mod": accessibility_mod,
			"business_match": match_score,
			"competition_mod": competition_mod,
			"dynamic_visitor_multiplier": dynamic_visitor_multiplier,
			"city_region_visitor_multiplier": city_region_visitor_multiplier,
			"group_supply": contributed_groups,
			"spending_profile": block.spending_profile.duplicate(),
			"external_supply": contributed_external,
			"contribution": block_contribution,
		})

		weighted_competition_sum += competition_mod * block_contribution
		weighted_competition_denominator += block_contribution

	snapshot.reachable_groups = reachable_totals
	snapshot.external_traffic = external_total

	var total := external_total
	for group_id in SpatialConfig.POPULATION_GROUPS:
		total += float(reachable_totals.get(group_id, 0.0))
	snapshot.total_effective_audience = total * SettlementConfig.TRAFFIC_SCALE_MULTIPLIER

	if weighted_competition_denominator > 0.0001:
		snapshot.average_competition_modifier = weighted_competition_sum / weighted_competition_denominator
	else:
		snapshot.average_competition_modifier = 1.0

	return snapshot


static func _calculate_distance_decay(distance: float, max_radius: float) -> float:
	if max_radius <= 0.0 or distance >= max_radius:
		return 0.0
	var ratio := distance / max_radius
	return clampf(1.0 - pow(ratio, DISTANCE_DECAY_ALPHA), 0.0, 1.0)


static func _calculate_accessibility_mod(block: BlockData, storefront: StorefrontData) -> float:
	var block_accessibility := clampf(block.accessibility, 0.0, 1.0)
	var storefront_accessibility := clampf(storefront.accessibility_modifier, 0.0, 2.0)
	return block_accessibility * storefront_accessibility


static func _calculate_business_match(block: BlockData, category_id: String) -> float:
	## 业态需求向量与区块人群供给向量的点积，两者均近似归一化到总和1，
	## 因此结果天然落在0-1附近：需求越贴合该区块的人群结构，值越高。
	var demand_weights := BusinessDemandConfig.get_demand_weights(category_id)
	var dot_product := 0.0

	for group_id in SpatialConfig.POPULATION_GROUPS:
		var demand := float(demand_weights.get(group_id, 0.0))
		var supply_weight := block.get_group_weight(group_id)
		dot_product += demand * supply_weight

	return clampf(dot_product, 0.0, 1.0)


static func _calculate_competition_mod(block: BlockData, category_id: String) -> float:
	var level_key := str(block.competition_profile.get("competition_level", "medium"))
	var level_value := float(COMPETITION_LEVEL_VALUE.get(level_key, 0.6))
	var sensitivity := BusinessDemandConfig.get_competition_sensitivity(category_id)

	return clampf(1.0 - sensitivity * level_value, 0.1, 1.0)


## Shared market pools use the same static external-competition model as the
## trade-area report, but deduct it once at pool level rather than per store.
static func get_external_competition_ratio(block: BlockData, category_id: String) -> float:
	return 1.0 - _calculate_competition_mod(block, category_id)


static func get_participant_market_factors(block: BlockData, storefront: StorefrontData, category_id: String) -> Dictionary:
	if block == null or storefront == null:
		return {}
	var distance := storefront.map_position.distance_to(block.center_position)
	if distance >= DEFAULT_MAX_RADIUS:
		return {}
	return {
		"distance": distance,
		"block_accessibility": clampf(block.accessibility, 0.0, 1.0),
		"storefront_accessibility": clampf(storefront.accessibility_modifier, 0.0, 2.0),
		"business_match": _calculate_business_match(block, category_id),
	}
