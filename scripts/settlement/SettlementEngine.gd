class_name SettlementEngine
## 纯计算类，无副作用。改动：结算单位从"slot"变成"hour"（0-23的单个小时），
## 营业判定改为查 StoreCategorySlot.open_hour_ranges，不再依赖策略。

static func calculate_params(
		region: RegionData,
		storefront: StorefrontData,
		category: CategoryData,
		product: ProductData,
		store_state: StoreState,
		player_state: PlayerState,
		hour: int,
		open_hour_ranges: Array[Vector2i],
		has_key_staff: bool,
) -> Dictionary:
	var p := {
		"is_open": true, "not_open_reason": "",
		"slot_foot_traffic": 0.0, "reachable_traffic": 0.0,
		"entry_rate": 0.0, "visitors": 0,
		"conversion_rate": 0.0, "slot_capacity": 0,
		"missing_key_staff_active": false, "modifiers": [],
	}

	if category.id not in storefront.supported_categories:
		p.is_open = false
		p.not_open_reason = "门面[%s]不支持品类[%s]" % [storefront.name, category.name]
		return p

	if not _hour_in_ranges(hour, open_hour_ranges):
		p.is_open = false
		p.not_open_reason = "品类[%s]未配置%02d:00这个时段营业" % [category.name, hour]
		return p

	var is_off_suggested := not _hour_in_ranges(hour, category.suggested_open_hour_ranges)

	var base_traffic: float = float(region.hourly_foot_traffic_by_hour[hour]) \
		if hour >= 0 and hour < region.hourly_foot_traffic_by_hour.size() else 0.0
	var weekend_mult: float = region.weekend_modifier if _is_weekend_day(store_state.current_day) else 1.0
	var daily_fluctuation: float = _get_daily_traffic_fluctuation(region.id, hour, store_state.current_day)
	p.slot_foot_traffic = base_traffic * weekend_mult * daily_fluctuation
	p.reachable_traffic = p.slot_foot_traffic * storefront.flow_share

	var entry_result := _calc_entry_rate(region, storefront, category, product, store_state, hour, is_off_suggested)
	p.entry_rate = entry_result.rate
	p.modifiers.append_array(entry_result.mods)

	p.visitors = floori(p.reachable_traffic * p.entry_rate)

	var conv_result := _calc_conversion_rate(category, store_state, player_state, has_key_staff)
	p.conversion_rate = conv_result.rate
	p.missing_key_staff_active = conv_result.missing_key_staff_active
	p.modifiers.append_array(conv_result.mods)

	## 每次结算恰好覆盖1小时，容量不再需要乘以"这个slot多少小时"。
	p.slot_capacity = floori(_calc_hourly_capacity(storefront, category, has_key_staff))

	return p


static func finalize_from_simulation(
		params: Dictionary,
		hour: int,
		day: int,
		category: CategoryData,
		product: ProductData,
		inventory_limit: int,
		sim: CustomerSimulator,
) -> SettlementResult:
	var r := SettlementResult.new()
	r.slot = "%02d:00" % hour   # SettlementResult.slot字段沿用String类型，直接存文字化的小时标签
	r.day = day
	r.category_id = category.id
	r.category_name = category.name
	r.product_id = product.id
	r.product_name = product.name
	r.is_open = params.is_open
	r.not_open_reason = params.not_open_reason
	r.missing_key_staff_active = params.missing_key_staff_active

	var typed_modifiers: Array[Dictionary] = []
	typed_modifiers.append_array(params.modifiers)
	r.modifiers = typed_modifiers

	r.slot_foot_traffic = params.slot_foot_traffic
	r.reachable_traffic = params.reachable_traffic
	r.entry_rate = params.entry_rate
	r.conversion_rate = params.conversion_rate
	r.slot_capacity = params.slot_capacity
	r.inventory_limit = inventory_limit

	if not params.is_open or sim == null:
		_build_summary(r)
		return r

	r.visitors = sim.visitors_so_far
	r.theoretical_orders = sim.converted_count
	r.actual_orders = sim.actual_orders
	r.inventory_used = sim.actual_orders

	r.lost_no_entry = maxi(0, floori(params.reachable_traffic) - r.visitors)
	r.lost_no_conversion = maxi(0, r.visitors - r.theoretical_orders)
	r.lost_capacity = sim.rejected_capacity_count
	r.lost_inventory = sim.rejected_inventory_count

	r.revenue = sim.revenue
	r.ingredient_cost = sim.ingredient_cost
	r.staff_cost = 0.0
	r.rent_cost = 0.0
	r.utility_cost = sim.utility_cost
	r.waste_cost = _calc_waste_cost(sim.unit_ingredient_cost, inventory_limit, r.actual_orders)
	r.profit = r.revenue - r.ingredient_cost - r.staff_cost \
		- r.rent_cost - r.utility_cost - r.waste_cost

	_calc_reputation_stress(r, category, GameManager.store_state, GameManager.player_state)
	_build_summary(r)
	return r


static func _hour_in_ranges(hour: int, ranges: Array[Vector2i]) -> bool:
	for r in ranges:
		if hour >= r.x and hour < r.y:
			return true
	return false


static func _is_weekend_day(day: int) -> bool:
	return (day % 7) in SettlementConfig.WEEKEND_DAY_REMAINDERS


static func _get_daily_traffic_fluctuation(region_id: String, hour: int, day: int) -> float:
	var seed_str := "%s_%d_%d" % [region_id, hour, day]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_str)
	return rng.randf_range(
		SettlementConfig.TRAFFIC_FLUCTUATION_MIN,
		SettlementConfig.TRAFFIC_FLUCTUATION_MAX
	)


static func _calc_entry_rate(
		region: RegionData,
		storefront: StorefrontData,
		category: CategoryData,
		product: ProductData,
		store_state: StoreState,
		hour: int,
		is_off_suggested: bool,
) -> Dictionary:
	var mods: Array[Dictionary] = []
	var rate: float = category.base_entry_rate
	mods.append({label="品类基础到店率[%s]" % category.name,
				 value=rate, is_positive=true, phase="entry"})

	var primary_hits := _count_overlap(product.target_groups, region.primary_groups)
	var secondary_hits := _count_overlap(product.target_groups, region.secondary_groups)
	var total_target := product.target_groups.size()
	var group_mod: float
	if primary_hits + secondary_hits == 0 and total_target > 0:
		group_mod = SettlementConfig.GROUP_NO_MATCH_PENALTY
		mods.append({label="客群完全不匹配", value=group_mod,
					 is_positive=false, phase="entry"})
	else:
		group_mod = (primary_hits * SettlementConfig.GROUP_MATCH_PRIMARY_WEIGHT
				   + secondary_hits * SettlementConfig.GROUP_MATCH_SECONDARY_WEIGHT)
		mods.append({label="客群匹配(%d主/%d次)" % [primary_hits, secondary_hits],
					 value=group_mod, is_positive=group_mod >= 0, phase="entry"})
	rate += group_mod

	var hour_mod: float
	if _hour_in_ranges(hour, product.preferred_hour_ranges):
		hour_mod = SettlementConfig.SLOT_MATCH_BONUS
		mods.append({label="时段匹配[%02d:00]" % hour,
					 value=hour_mod, is_positive=true, phase="entry"})
	else:
		hour_mod = SettlementConfig.SLOT_MISMATCH_PENALTY
		mods.append({label="时段不匹配[%02d:00]" % hour,
					 value=hour_mod, is_positive=false, phase="entry"})
	rate += hour_mod

	if is_off_suggested:
		var off_pen := SettlementConfig.OFF_SUGGESTED_HOUR_ENTRY_PENALTY
		mods.append({label="偏离推荐营业时段惩罚", value=off_pen,
					 is_positive=false, phase="entry"})
		rate += off_pen

	var spend_key := "%s_%s" % [product.price_tier, region.spending_power]
	var spend_mod: float = SettlementConfig.SPENDING_POWER_MOD.get(spend_key, 0.0)
	mods.append({label="价格[%s]×消费能力[%s]" % [product.price_tier, region.spending_power],
				 value=spend_mod, is_positive=spend_mod >= 0, phase="entry"})
	rate += spend_mod

	var deco_mod: float = SettlementConfig.DECORATION_MOD.get(storefront.decoration_level, 0.0)
	mods.append({label="装修[%s]" % storefront.decoration_level,
				 value=deco_mod, is_positive=deco_mod >= 0, phase="entry"})
	rate += deco_mod

	var diff_mod: float = SettlementConfig.DIFFERENTIATION_ENTRY_MOD.get(product.differentiation, 0.0)
	mods.append({label="差异化[%s]" % product.differentiation,
				 value=diff_mod, is_positive=diff_mod >= 0, phase="entry"})
	rate += diff_mod

	var actual_margin: float = product.get_actual_margin_rate(product.average_price)
	var margin_deviation: float = actual_margin - product.suggested_margin_rate
	var margin_mod: float = clampf(
		-margin_deviation * SettlementConfig.MARGIN_DEVIATION_ENTRY_COEFFICIENT,
		-SettlementConfig.MARGIN_DEVIATION_MAX_PENALTY,
		SettlementConfig.MARGIN_DEVIATION_MAX_BONUS
	)
	mods.append({label="毛利率偏离建议值(实际%.0f%%/建议%.0f%%)" % [
		actual_margin * 100.0, product.suggested_margin_rate * 100.0],
		value=margin_mod, is_positive=margin_mod >= 0, phase="entry"})
	rate += margin_mod

	var rep_mod: float = (store_state.reputation - 50.0) / 50.0 \
					   * SettlementConfig.REPUTATION_MAX_ENTRY_MOD
	mods.append({label="口碑影响(%.0f)" % store_state.reputation,
				 value=rep_mod, is_positive=rep_mod >= 0, phase="entry"})
	rate += rep_mod

	if category.id == "beverage_dessert" and region.dwell_time == "low":
		var dwell_pen := SettlementConfig.DWELL_MISMATCH_PENALTY
		mods.append({label="低停留性区域不适合饮品甜点",
					 value=dwell_pen, is_positive=false, phase="entry"})
		rate += dwell_pen

	var comp_base: float = SettlementConfig.COMPETITION_PENALTY.get(region.competition_level, 0.0)
	var diff_offset: float = SettlementConfig.COMPETITION_DIFF_OFFSET.get(product.differentiation, 0.0)
	var net_comp: float = -(comp_base - diff_offset)
	mods.append({label="竞争压力[%s](差异化抵消%.3f)" % [region.competition_level, diff_offset],
				 value=net_comp, is_positive=false, phase="entry"})
	rate += net_comp

	rate = clampf(rate, SettlementConfig.ENTRY_RATE_MIN, SettlementConfig.ENTRY_RATE_MAX)
	return {rate=rate, mods=mods}


static func _calc_conversion_rate(
		cat: CategoryData, store_state: StoreState, player_state: PlayerState, has_key_staff: bool
) -> Dictionary:
	var mods: Array[Dictionary] = []
	var rate: float = SettlementConfig.BASE_CONVERSION_RATE
	var missing := false

	if cat.key_staff_type != "none" and not has_key_staff:
		missing = true
		var pen := -cat.missing_key_staff_conversion_penalty
		mods.append({label="缺%s：成交率惩罚" % cat.key_staff_type,
					 value=pen, is_positive=false, phase="conversion"})
		rate += pen

	if store_state.owner_present:
		mods.append({label="亲自坐镇加成", value=0.03, is_positive=true, phase="conversion"})
		rate += 0.03

	if player_state.stress >= SettlementConfig.STRESS_HIGH_THRESHOLD:
		var pen := -SettlementConfig.STRESS_CONVERSION_PENALTY
		mods.append({label="高压力(%.0f)影响服务质量" % player_state.stress,
					 value=pen, is_positive=false, phase="conversion"})
		rate += pen

	rate = clampf(rate, SettlementConfig.CONVERSION_RATE_MIN, SettlementConfig.CONVERSION_RATE_MAX)
	return {rate=rate, mods=mods, missing_key_staff_active=missing}


static func _calc_hourly_capacity(sf: StorefrontData, cat: CategoryData, has_key_staff: bool) -> float:
	var cap: float = float(sf.hourly_capacity_base)
	cap *= SettlementConfig.SERVICE_SPEED_MOD.get(cat.base_service_speed, 1.0)
	cap *= SettlementConfig.EQUIPMENT_CAPACITY_MOD.get(sf.equipment_condition, 1.0)
	if cat.key_staff_type != "none" and not has_key_staff:
		cap *= (1.0 - cat.missing_key_staff_capacity_penalty)
	return cap


static func _calc_waste_cost(unit_ingredient_cost: float, inventory: int, sold: int) -> float:
	var threshold := int(sold * SettlementConfig.WASTE_THRESHOLD_RATIO)
	if inventory <= threshold:
		return 0.0
	var excess := inventory - threshold
	return excess * unit_ingredient_cost * SettlementConfig.WASTE_COST_RATIO_OF_INGREDIENT


static func _calc_reputation_stress(r: SettlementResult,
		cat: CategoryData, store_state: StoreState, _player_state: PlayerState) -> void:
	var order_completion_rate: float = 0.0
	if r.theoretical_orders > 0:
		order_completion_rate = float(r.actual_orders) / float(r.theoretical_orders)

	var rep_delta: float = 0.0
	if order_completion_rate >= SettlementConfig.REPUTATION_GOOD_THRESHOLD:
		rep_delta += 1.5
	elif order_completion_rate < SettlementConfig.REPUTATION_BAD_THRESHOLD:
		rep_delta -= 2.0
	if r.lost_inventory > 0:
		rep_delta -= 1.0
	if cat.key_staff_type != "none" and r.missing_key_staff_active:
		rep_delta -= cat.missing_key_staff_reputation_penalty
	r.reputation_delta = clampf(rep_delta,
		-SettlementConfig.REPUTATION_PER_SLOT_MAX_CHANGE,
		 SettlementConfig.REPUTATION_PER_SLOT_MAX_CHANGE)

	var stress_delta: float = 0.0
	if r.profit < 0:
		stress_delta += SettlementConfig.STRESS_LOSS_PER_SLOT
	if r.lost_capacity > 0:
		stress_delta += SettlementConfig.STRESS_OVERLOAD_PER_SLOT * \
						minf(float(r.lost_capacity) / maxf(float(r.slot_capacity), 1.0), 1.0)
	if store_state.owner_present:
		stress_delta += 2.0
	if r.missing_key_staff_active:
		stress_delta += 1.5
	r.stress_delta = stress_delta


static func _build_summary(r: SettlementResult) -> void:
	var pos_mods := r.modifiers.filter(func(m): return m.is_positive and m.value > 0.001)
	var neg_mods := r.modifiers.filter(func(m): return not m.is_positive and m.value < -0.001)
	pos_mods.sort_custom(func(a, b): return a.value > b.value)
	neg_mods.sort_custom(func(a, b): return a.value < b.value)

	r.top_positive = []
	for m in pos_mods.slice(0, 3):
		r.top_positive.append("%s (+%.4f)" % [m.label, m.value])

	r.top_negative = []
	if r.lost_inventory > 0:
		r.top_negative.append("库存不足：损失%d单" % r.lost_inventory)
	if r.lost_capacity > 0:
		r.top_negative.append("容量不足：损失%d单" % r.lost_capacity)
	for m in neg_mods.slice(0, maxi(0, 3 - r.top_negative.size())):
		r.top_negative.append("%s (%.4f)" % [m.label, m.value])


static func _count_overlap(a: Array, b: Array) -> int:
	var count := 0
	for x in a:
		if x in b:
			count += 1
	return count
