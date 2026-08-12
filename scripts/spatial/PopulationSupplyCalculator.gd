class_name PopulationSupplyCalculator
## 建议位置：res://scripts/spatial/PopulationSupplyCalculator.gd
##
## 区块人群供给纯计算器。
## 负责：区块容量基线 → 五类人群容量 → 当前时段活动供给 → 商业外来客流。
## 不负责：调查范围、门面距离、门面可达性、业态匹配、竞争、到店率与经营结算。
##
## 重要边界：
## - CityRegionData.background_population 永远不参与这里的计算。
## - BlockData 是经营人口/活动供给的唯一来源。
## - 返回的数值都是“供给潜力”，不是实际进入某家门店的顾客数。


static func calculate_capacity_base(block: BlockData) -> float:
	## 区块容量 = 类型基础密度 × 等级系数 × 面积 × 开发系数。
	## 此处不乘城市区位倍率，避免把城市背景和区块原始供给混为一层；
	## 城市的traffic_baseline在时段活动供给阶段作为宏观活动修正加入。
	if block == null or not block.is_valid():
		return 0.0

	var density := BlockConfig.get_base_density(block.block_type)
	var tier_multiplier := BlockConfig.get_tier_multiplier(block.block_type, block.tier)
	var safe_area := maxf(0.0, block.area)
	var safe_development := clampf(block.development_factor, 0.0, 2.0)

	return density * tier_multiplier * safe_area * safe_development


static func calculate_group_capacity(block: BlockData, group_id: String) -> float:
	## 返回某一人群在区块中的静态供给容量；不考虑时段和周末。
	if not SpatialConfig.is_valid_population_group(group_id):
		return 0.0

	var weights := _get_normalized_group_weights(block)
	return calculate_capacity_base(block) * float(weights.get(group_id, 0.0))


static func calculate_group_capacities(block: BlockData) -> Dictionary:
	## 返回五类人群的静态容量字典：{group_id: float}。
	var result := SpatialConfig.make_empty_group_weights()
	var capacity_base := calculate_capacity_base(block)
	var weights := _get_normalized_group_weights(block)

	for group_id in SpatialConfig.POPULATION_GROUPS:
		result[group_id] = capacity_base * float(weights.get(group_id, 0.0))

	return result


static func calculate_activity_multiplier(
		block: BlockData,
		period: String,
		city_region: CityRegionData = null,
		is_weekend: bool = false
) -> float:
	## 返回区块在某个四时段内的活动倍率。
	## 城市区域只提供宏观活跃度修正，不提供额外人口来源。
	if block == null or period not in SpatialConfig.TIME_PERIODS:
		return 0.0

	var multiplier := maxf(0.0, block.get_time_activity(period))

	if city_region != null:
		multiplier *= maxf(0.0, city_region.get_modifier("traffic_baseline", 1.0))
		if is_weekend:
			multiplier *= maxf(0.0, city_region.weekend_activity_modifier)

	return multiplier


static func calculate_group_activity_supply(
		block: BlockData,
		group_id: String,
		period: String,
		city_region: CityRegionData = null,
		is_weekend: bool = false
) -> float:
	## 返回某区块、某人群、某时段的活动供给。
	if not SpatialConfig.is_valid_population_group(group_id):
		return 0.0

	return calculate_group_capacity(block, group_id) * calculate_activity_multiplier(
		block, period, city_region, is_weekend
	)


static func calculate_activity_supply_by_group(
		block: BlockData,
		period: String,
		city_region: CityRegionData = null,
		is_weekend: bool = false
) -> Dictionary:
	## 返回五类人群在当前时段的活动供给：{group_id: float}。
	var result := SpatialConfig.make_empty_group_weights()
	var multiplier := calculate_activity_multiplier(block, period, city_region, is_weekend)
	var capacities := calculate_group_capacities(block)

	for group_id in SpatialConfig.POPULATION_GROUPS:
		result[group_id] = float(capacities.get(group_id, 0.0)) * multiplier

	return result


static func calculate_activity_supply_for_hour(
		block: BlockData,
		hour: int,
		city_region: CityRegionData = null,
		is_weekend: bool = false
) -> Dictionary:
	## 供现有TimeManager/SettlementEngine按小时调用的便利接口。
	return calculate_activity_supply_by_group(
		block,
		SpatialConfig.get_period_for_hour(hour),
		city_region,
		is_weekend
	)


static func calculate_total_activity_supply(
		block: BlockData,
		period: String,
		city_region: CityRegionData = null,
		is_weekend: bool = false
) -> float:
	## 返回五类人群的活动供给总和，不含商业区块的额外外来客流。
	var groups := calculate_activity_supply_by_group(block, period, city_region, is_weekend)
	var total := 0.0
	for group_id in SpatialConfig.POPULATION_GROUPS:
		total += float(groups.get(group_id, 0.0))
	return total


static func calculate_external_flow(
		block: BlockData,
		period: String,
		city_region: CityRegionData = null,
		is_weekend: bool = false
) -> float:
	## 外来客流是商业吸引力产生的额外“活动机会”，不是永久居民人口。
	## external_attraction应为0-1；非商业区块通常为0，交通枢纽等特殊区块可手工配置。
	if block == null or period not in SpatialConfig.TIME_PERIODS:
		return 0.0

	var attraction := clampf(float(block.competition_profile.get("external_attraction", 0.0)), 0.0, 1.0)
	if attraction <= 0.0:
		return 0.0

	return calculate_capacity_base(block) * attraction * calculate_activity_multiplier(
		block, period, city_region, is_weekend
	)


static func calculate_supply_snapshot(
		block: BlockData,
		period: String,
		city_region: CityRegionData = null,
		is_weekend: bool = false
) -> Dictionary:
	## 为调查报告和未来TradeAreaCalculator提供统一快照结构。
	## 它不包含门面相关的距离/可达性/业态/竞争修正。
	var group_capacities := calculate_group_capacities(block)
	var group_activity_supply := calculate_activity_supply_by_group(
		block, period, city_region, is_weekend
	)
	var external_flow := calculate_external_flow(block, period, city_region, is_weekend)
	var total_group_activity := 0.0

	for group_id in SpatialConfig.POPULATION_GROUPS:
		total_group_activity += float(group_activity_supply.get(group_id, 0.0))

	return {
		"block_id": block.id if block != null else "",
		"period": period,
		"capacity_base": calculate_capacity_base(block),
		"activity_multiplier": calculate_activity_multiplier(block, period, city_region, is_weekend),
		"group_capacities": group_capacities,
		"group_activity_supply": group_activity_supply,
		"external_flow": external_flow,
		"total_group_activity_supply": total_group_activity,
		"total_activity_supply": total_group_activity + external_flow,
	}


static func _get_normalized_group_weights(block: BlockData) -> Dictionary:
	## 不修改Resource本身，避免结算/预览时意外污染编辑器资源或运行时共享数据。
	var result := SpatialConfig.make_empty_group_weights()
	if block == null:
		return result

	var total := 0.0
	for group_id in SpatialConfig.POPULATION_GROUPS:
		var weight := maxf(0.0, block.get_group_weight(group_id))
		result[group_id] = weight
		total += weight

	if total <= 0.0001:
		return result

	for group_id in SpatialConfig.POPULATION_GROUPS:
		result[group_id] = float(result[group_id]) / total

	return result
