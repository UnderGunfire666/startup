class_name SettlementEngine
## 纯计算类，无副作用，不读写任何全局状态。
## 所有输入通过参数传入，输出为 SettlementResult。
## 注：has_key_staff 与 strategy 现在由调用方（GameManager）针对每个品类实例
## 显式传入，不再从 state 上读取，因为一个门店可以同时经营多个品类，
## 每个品类的关键员工配置和营业策略是独立的。

static func calculate(
		region: RegionData,
		storefront: StorefrontData,
		category: CategoryData,
		product: ProductData,
		state: StoreState,
		slot: String,
		day: int,
		has_key_staff: bool,
		strategy: String,
		product_inventory: int,
		unit_ingredient_cost: float,
		debug_ignore_category_restriction: bool = false
) -> SettlementResult:

	var r := SettlementResult.new()
	r.slot = slot
	r.day  = day
	r.category_id = category.id
	r.category_name = category.name
	r.product_id = product.id

	# ── 0. 品类适配检查 ─────────────────────────────────────
	if not debug_ignore_category_restriction:
		if category.id not in storefront.supported_categories:
			r.is_open = false
			r.not_open_reason = "门面[%s]不支持品类[%s]" % [storefront.name, category.name]
			return r

	# ── 1. 营业时段判断 ──────────────────────────────────────
	var active_slots := _get_active_slots(category, strategy)
	if slot not in active_slots:
		r.is_open = false
		r.not_open_reason = "策略[%s]下品类[%s]在[%s]不营业" % [
			strategy,
			category.name,
			SettlementConfig.SLOT_NAMES[slot]
		]
		return r
	r.is_open = true

	var is_non_default_slot := (slot not in category.default_open_slots)

	# ── 2. 区域时段人流（接入周末系数 + 每日随机波动，让人流更真实） ──
	var base_traffic: float = float(region.hourly_foot_traffic_by_slot.get(slot, 0))
	var weekend_mult: float = region.weekend_modifier if _is_weekend_day(day) else 1.0
	var daily_fluctuation: float = _get_daily_traffic_fluctuation(region.id, slot, day)
	r.slot_foot_traffic = base_traffic * weekend_mult * daily_fluctuation

	# ── 3. 可触达人流 ────────────────────────────────────────
	r.reachable_traffic = r.slot_foot_traffic * storefront.flow_share

	# ── 4. 到店率 ────────────────────────────────────────────
	var entry_result := _calc_entry_rate(
		region, storefront, category, product, state, slot,
		is_non_default_slot, debug_ignore_category_restriction
	)
	r.entry_rate = entry_result.rate
	r.modifiers.append_array(entry_result.mods)

	# ── 5. 进店人数 ──────────────────────────────────────────
	r.visitors = floori(r.reachable_traffic * r.entry_rate)

	# ── 6. 成交率 ────────────────────────────────────────────
	var conv_result := _calc_conversion_rate(category, state, has_key_staff)
	r.conversion_rate = conv_result.rate
	r.missing_key_staff_active = conv_result.missing_key_staff_active
	r.modifiers.append_array(conv_result.mods)

	# ── 7. 服务容量 ──────────────────────────────────────────
	var hourly_cap := _calc_hourly_capacity(storefront, category, has_key_staff)
	r.slot_capacity = floori(hourly_cap * SettlementConfig.SLOT_HOURS[slot])

	# ── 8. 实际订单 ──────────────────────────────────────────
	r.theoretical_orders = floori(r.visitors * r.conversion_rate)
	r.inventory_limit = product_inventory
	
	var after_cap      := mini(r.theoretical_orders, r.slot_capacity)
	r.actual_orders    = mini(after_cap, r.inventory_limit)
	r.inventory_used   = r.actual_orders

	r.lost_no_entry     = floori(r.reachable_traffic) - r.visitors
	r.lost_no_conversion = maxi(0, r.visitors - r.theoretical_orders)
	r.lost_capacity     = maxi(0, r.theoretical_orders - r.slot_capacity)
	r.lost_inventory    = maxi(0, after_cap - r.actual_orders)

	# ── 9. 财务 ──────────────────────────────────────────────
	r.revenue = r.actual_orders * product.average_price
	r.ingredient_cost = r.actual_orders * unit_ingredient_cost
	r.staff_cost = _calc_staff_cost(has_key_staff, strategy, is_non_default_slot)
	r.rent_cost = storefront.get_monthly_rent_yuan() / 30.0 / 3.0
	r.waste_cost = _calc_waste_cost(
		unit_ingredient_cost,
		product_inventory,
		r.actual_orders
	)
	r.profit = r.revenue - r.ingredient_cost - r.staff_cost \
		- r.rent_cost - r.waste_cost

	# ── 10. 口碑与压力 ───────────────────────────────────────
	_calc_reputation_stress(r, category, state)

	# ── 11. 原因摘要 ─────────────────────────────────────────
	_build_summary(r)

	return r

# ── 私有：判断是否周末 ────────────────────────────────────
static func _is_weekend_day(day: int) -> bool:
	return (day % 7) in SettlementConfig.WEEKEND_DAY_REMAINDERS


# ── 私有：每日人流随机波动（确定性种子，同一天同一区域同一时段结果稳定，
#          方便复盘和存档读取后结果一致，但天与天之间会自然涨跌） ──────
static func _get_daily_traffic_fluctuation(region_id: String, slot: String, day: int) -> float:
	var seed_str := "%s_%s_%d" % [region_id, slot, day]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_str)
	return rng.randf_range(
		SettlementConfig.TRAFFIC_FLUCTUATION_MIN,
		SettlementConfig.TRAFFIC_FLUCTUATION_MAX
	)

# ── 私有：营业时段列表 ────────────────────────────────────
static func _get_active_slots(cat: CategoryData, strategy: String) -> Array:
	match strategy:
		"standard":
			return cat.default_open_slots
		"extend":
			return SettlementConfig.SLOT_ORDER  # 全时段
		"shorten":
			return cat.preferred_slots
	return cat.default_open_slots


# ── 私有：到店率计算 ──────────────────────────────────────
static func _calc_entry_rate(
		region: RegionData,
		storefront: StorefrontData,
		category: CategoryData,
		product: ProductData,
		state: StoreState,
		slot: String,
		is_non_default_slot: bool,
		debug_ignore_cat: bool
) -> Dictionary:

	var mods: Array[Dictionary] = []
	var rate: float = category.base_entry_rate
	mods.append({label="品类基础到店率[%s]" % category.name,
				 value=rate, is_positive=true, phase="entry"})

	# 客群匹配
	var primary_hits   := _count_overlap(product.target_groups, region.primary_groups)
	var secondary_hits := _count_overlap(product.target_groups, region.secondary_groups)
	var total_target   := product.target_groups.size()
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

	# 时段匹配
	var slot_mod: float
	if slot in product.preferred_slots:
		slot_mod = SettlementConfig.SLOT_MATCH_BONUS
		mods.append({label="时段匹配[%s]" % SettlementConfig.SLOT_NAMES[slot],
					 value=slot_mod, is_positive=true, phase="entry"})
	else:
		slot_mod = SettlementConfig.SLOT_MISMATCH_PENALTY
		mods.append({label="时段不匹配[%s]" % SettlementConfig.SLOT_NAMES[slot],
					 value=slot_mod, is_positive=false, phase="entry"})
	rate += slot_mod

	# 非默认时段营业（extend策略）
	if is_non_default_slot:
		var ext_pen := SettlementConfig.STRATEGY_EXTEND_ENTRY_PENALTY
		mods.append({label="延长营业时段惩罚", value=ext_pen,
					 is_positive=false, phase="entry"})
		rate += ext_pen

	# 消费能力匹配
	var spend_key := "%s_%s" % [product.price_tier, region.spending_power]
	var spend_mod: float = SettlementConfig.SPENDING_POWER_MOD.get(spend_key, 0.0)
	mods.append({label="价格[%s]×消费能力[%s]" % [product.price_tier, region.spending_power],
				 value=spend_mod, is_positive=spend_mod >= 0, phase="entry"})
	rate += spend_mod

	# 装修
	var deco_mod: float = SettlementConfig.DECORATION_MOD.get(storefront.decoration_level, 0.0)
	mods.append({label="装修[%s]" % storefront.decoration_level,
				 value=deco_mod, is_positive=deco_mod >= 0, phase="entry"})
	rate += deco_mod

	# 差异化
	var diff_mod: float = SettlementConfig.DIFFERENTIATION_ENTRY_MOD.get(
		product.differentiation, 0.0)
	mods.append({label="差异化[%s]" % product.differentiation,
				 value=diff_mod, is_positive=diff_mod >= 0, phase="entry"})
	rate += diff_mod

		# 毛利率偏离建议值（价格相对成本过高会吓跑客人，过低则吸引客人但压缩利润）
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
	
	# 口碑
	var rep_mod: float = (state.reputation - 50.0) / 50.0 \
					   * SettlementConfig.REPUTATION_MAX_ENTRY_MOD
	mods.append({label="口碑影响(%.0f)" % state.reputation,
				 value=rep_mod, is_positive=rep_mod >= 0, phase="entry"})
	rate += rep_mod

	# 停留性 × 品类（饮品甜点在低停留区额外惩罚）
	if category.id == "beverage_dessert" and region.dwell_time == "low":
		var dwell_pen := SettlementConfig.DWELL_MISMATCH_PENALTY
		mods.append({label="低停留性区域不适合饮品甜点",
					 value=dwell_pen, is_positive=false, phase="entry"})
		rate += dwell_pen

	# 品类不适配（调试模式强行开店时加惩罚）
	if debug_ignore_cat and category.id not in storefront.supported_categories:
		var cat_pen := -0.010
		mods.append({label="门面设备/品类不适配惩罚(调试)",
					 value=cat_pen, is_positive=false, phase="entry"})
		rate += cat_pen

	# 竞争（差异化部分抵消）
	var comp_base: float = SettlementConfig.COMPETITION_PENALTY.get(
		region.competition_level, 0.0)
	var diff_offset: float = SettlementConfig.COMPETITION_DIFF_OFFSET.get(
		product.differentiation, 0.0)
	var net_comp: float = -(comp_base - diff_offset)
	mods.append({label="竞争压力[%s](差异化抵消%.3f)" % [region.competition_level, diff_offset],
				 value=net_comp, is_positive=false, phase="entry"})
	rate += net_comp

	rate = clampf(rate, SettlementConfig.ENTRY_RATE_MIN, SettlementConfig.ENTRY_RATE_MAX)
	return {rate=rate, mods=mods}


# ── 私有：成交率计算 ──────────────────────────────────────
static func _calc_conversion_rate(
		cat: CategoryData, state: StoreState, has_key_staff: bool
) -> Dictionary:
	var mods: Array[Dictionary] = []
	var rate: float = SettlementConfig.BASE_CONVERSION_RATE
	var missing := false

	# 关键员工缺失
	if cat.key_staff_type != "none" and not has_key_staff:
		missing = true
		var pen := -cat.missing_key_staff_conversion_penalty
		mods.append({label="缺%s：成交率惩罚" % cat.key_staff_type,
					 value=pen, is_positive=false, phase="conversion"})
		rate += pen

	# 亲自坐镇小加成（增加压力）
	if state.owner_present:
		mods.append({label="亲自坐镇加成", value=0.03,
					 is_positive=true, phase="conversion"})
		rate += 0.03

	# 高压力惩罚
	if state.stress >= SettlementConfig.STRESS_HIGH_THRESHOLD:
		var pen := -SettlementConfig.STRESS_CONVERSION_PENALTY
		mods.append({label="高压力(%.0f)影响服务质量" % state.stress,
					 value=pen, is_positive=false, phase="conversion"})
		rate += pen

	rate = clampf(rate, SettlementConfig.CONVERSION_RATE_MIN,
						SettlementConfig.CONVERSION_RATE_MAX)
	return {rate=rate, mods=mods, missing_key_staff_active=missing}


# ── 私有：每小时服务容量 ──────────────────────────────────
static func _calc_hourly_capacity(
		sf: StorefrontData, cat: CategoryData, has_key_staff: bool
) -> float:
	var cap: float = float(sf.hourly_capacity_base)
	cap *= SettlementConfig.SERVICE_SPEED_MOD.get(cat.base_service_speed, 1.0)
	cap *= SettlementConfig.EQUIPMENT_CAPACITY_MOD.get(sf.equipment_condition, 1.0)
	if cat.key_staff_type != "none" and not has_key_staff:
		cap *= (1.0 - cat.missing_key_staff_capacity_penalty)
	return cap


# ── 私有：员工成本 ────────────────────────────────────────
static func _calc_staff_cost(
		has_key_staff: bool, strategy: String, is_non_default: bool
) -> float:
	var base: float = SettlementConfig.BASE_STAFF_COST_PER_SLOT
	if has_key_staff:
		base += SettlementConfig.KEY_STAFF_EXTRA_COST_PER_SLOT
	if strategy == "extend" and is_non_default:
		base *= SettlementConfig.STRATEGY_EXTEND_COST_MULTIPLIER
	elif strategy == "shorten":
		base *= SettlementConfig.STRATEGY_SHORTEN_COST_MULTIPLIER
	return base


# ── 私有：损耗成本 ────────────────────────────────────────
static func _calc_waste_cost(
		unit_ingredient_cost: float,
		inventory: int,
		sold: int
) -> float:
	var threshold := int(sold * SettlementConfig.WASTE_THRESHOLD_RATIO)
	if inventory <= threshold:
		return 0.0

	var excess := inventory - threshold
	return excess * unit_ingredient_cost \
		* SettlementConfig.WASTE_COST_RATIO_OF_INGREDIENT

# ── 私有：口碑与压力 ──────────────────────────────────────
static func _calc_reputation_stress(r: SettlementResult,
		cat: CategoryData, state: StoreState) -> void:

	var order_completion_rate: float = 0.0
	if r.theoretical_orders > 0:
		order_completion_rate = float(r.actual_orders) / float(r.theoretical_orders)

	# 口碑
	var rep_delta: float = 0.0
	if order_completion_rate >= SettlementConfig.REPUTATION_GOOD_THRESHOLD:
		rep_delta += 1.5
	elif order_completion_rate < SettlementConfig.REPUTATION_BAD_THRESHOLD:
		rep_delta -= 2.0
	if r.lost_inventory > 0:
		rep_delta -= 1.0   # 缺货损失口碑
	if cat.key_staff_type != "none" and r.missing_key_staff_active:
		rep_delta -= cat.missing_key_staff_reputation_penalty
	r.reputation_delta = clampf(rep_delta,
		-SettlementConfig.REPUTATION_PER_SLOT_MAX_CHANGE,
		 SettlementConfig.REPUTATION_PER_SLOT_MAX_CHANGE)

	# 压力
	var stress_delta: float = 0.0
	if r.profit < 0:
		stress_delta += SettlementConfig.STRESS_LOSS_PER_SLOT
	if r.lost_capacity > 0:
		stress_delta += SettlementConfig.STRESS_OVERLOAD_PER_SLOT * \
						minf(float(r.lost_capacity) / maxf(float(r.slot_capacity), 1.0), 1.0)
	if state.owner_present:
		stress_delta += 2.0
	if r.missing_key_staff_active:
		stress_delta += 1.5
	r.stress_delta = stress_delta


# ── 私有：生成原因摘要 ────────────────────────────────────
static func _build_summary(r: SettlementResult) -> void:
	var pos_mods := r.modifiers.filter(func(m): return m.is_positive and m.value > 0.001)
	var neg_mods := r.modifiers.filter(func(m): return not m.is_positive and m.value < -0.001)

	pos_mods.sort_custom(func(a, b): return a.value > b.value)
	neg_mods.sort_custom(func(a, b): return a.value < b.value)

	r.top_positive = []
	for m in pos_mods.slice(0, 3):
		r.top_positive.append("%s (+%.4f)" % [m.label, m.value])

	r.top_negative = []

	# 未成交原因优先显示
	if r.lost_inventory > 0:
		r.top_negative.append("库存不足：损失%d单" % r.lost_inventory)
	if r.lost_capacity > 0:
		r.top_negative.append("容量不足：损失%d单" % r.lost_capacity)
	for m in neg_mods.slice(0, maxi(0, 3 - r.top_negative.size())):
		r.top_negative.append("%s (%.4f)" % [m.label, m.value])


# ── 工具函数 ──────────────────────────────────────────────
static func _count_overlap(a: Array, b: Array) -> int:
	var count := 0
	for x in a:
		if x in b:
			count += 1
	return count
