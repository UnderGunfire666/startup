class_name SettlementEngine
extends RefCounted
## 纯计算类：根据商圈快照/门面/品类/商品/玩家与店铺状态，计算单小时结算参数。
##
## 结算入口为 calculate_params_from_trade_area()，基于 TradeAreaSnapshot 计算客流。
## 旧的基于 RegionData 的 calculate_params() 已废弃并移除。
##
## 字段映射说明：
## - product.suggested_price不存在，改用真实字段product.suggested_margin_rate
##   （建议毛利率）配合product.get_actual_margin_rate()计算价格偏离修正。
## - category.staff_cost_per_hour / visitor_multiplier / capacity_multiplier
##   均不存在于CategoryData，容量改用真实字段base_service_speed +
##   SettlementConfig.SERVICE_SPEED_MOD；人力成本按原模型固定为0.0
##   （CategoryData本身不建模人力成本字段）。
## - storefront.daily_rent不存在，改用真实字段monthly_rent_wan +
##   get_monthly_rent_yuan()方法折算到每小时。
## - SettlementResult.slot真实类型是String（"%02d:00"格式），不是int，
##   修正了int→String的赋值错误。



static func calculate_params_from_trade_area(
		trade_area: TradeAreaSnapshot,
		storefront: StorefrontData,
		category: CategoryData,
		product: ProductData,
		store_state: Store,
		player_state: PlayerState,
		hour: int,
		open_hour_ranges: Array[Vector2i],
		has_key_staff: bool
) -> Dictionary:
	var is_open := _is_category_open(hour, open_hour_ranges)
	var owner_supervising := player_state.supervising_store_id == store_state.id

	var visitors := 0
	var conversion_rate := 0.0
	var slot_capacity := 0

	if is_open:
		var base_visitors := _calc_base_visitors_from_trade_area(trade_area, storefront, category)
		var price_mod := _calc_price_mod(product)
		var reputation_mod := _calc_reputation_mod(store_state.reputation)
		var staff_mod := _calc_staff_mod(has_key_staff)
		var owner_mod := 0.03 if owner_supervising else 0.0
		var trait_mods := _calc_trait_mods(player_state, category, product)

		conversion_rate = clampf(
			0.10
			+ price_mod
			+ reputation_mod
			+ staff_mod
			+ owner_mod
			+ trait_mods,
			0.0, 0.9
		)

		visitors = int(float(base_visitors) * (1.0 + trait_mods))
		slot_capacity = _calc_slot_capacity(storefront, category, has_key_staff)

	var rent_cost := _calc_rent_cost(storefront)
	var utility_cost := _calc_utility_cost(product, store_state, is_open)
	var staff_cost := _calc_staff_cost()

	return {
		"is_open": is_open,
		"visitors": visitors,
		"conversion_rate": conversion_rate,
		"slot_capacity": slot_capacity,
		"rent_cost": rent_cost,
		"utility_cost": utility_cost,
		"staff_cost": staff_cost,
		"owner_supervising": owner_supervising,
		"trade_area": trade_area,
		"storefront": storefront,
		"category": category,
		"product": product,
		"hour": hour,
	}


static func finalize_from_simulation(
		params: Dictionary,
		hour: int,
		day: int,
		category: CategoryData,
		product: ProductData,
		inventory_limit: int,
		sim: CustomerSimulator
) -> SettlementResult:
	var r := SettlementResult.new()
	r.day = day
	r.slot = "%02d:00" % hour
	r.is_open = params.get("is_open", false)
	r.category_id = category.id
	r.category_name = category.name
	r.product_id = product.id
	r.product_name = product.name

	if not r.is_open or sim == null:
		r.rent_cost = params.get("rent_cost", 0.0)
		r.utility_cost = params.get("utility_cost", 0.0)
		r.staff_cost = params.get("staff_cost", 0.0)
		r.profit = -(r.rent_cost + r.utility_cost + r.staff_cost)
		r.reputation_delta = 0.0
		r.stress_delta = 0.0
		return r

	r.actual_orders = sim.actual_orders
	r.revenue = sim.revenue
	r.ingredient_cost = sim.ingredient_cost
	r.waste_cost = _calc_waste_cost(sim.unit_ingredient_cost, inventory_limit, sim.actual_orders)
	r.rent_cost = params.get("rent_cost", 0.0)
	r.utility_cost = params.get("utility_cost", 0.0)
	r.staff_cost = params.get("staff_cost", 0.0)

	r.profit = r.revenue - r.ingredient_cost - r.waste_cost - r.rent_cost - r.utility_cost - r.staff_cost

	var rep_gain := _calc_reputation_gain(r.actual_orders, inventory_limit)
	var rep_loss := _calc_reputation_loss_from_stockout(r.actual_orders, inventory_limit)
	r.reputation_delta = clampf(rep_gain - rep_loss, -5.0, 5.0)

	r.missing_key_staff_active = params.get("missing_key_staff", false)
	var owner_supervising: bool = params.get("owner_supervising", false)
	r.stress_delta = _calc_stress_delta(r, owner_supervising)

	r.lost_inventory = maxi(0, inventory_limit - r.actual_orders)
	r.lost_capacity = 0

	return r


# ── 内部辅助函数 ────────────────────────────────────────────

static func _is_category_open(hour: int, open_hour_ranges: Array[Vector2i]) -> bool:
	for range_vec in open_hour_ranges:
		var start := range_vec.x
		var end := range_vec.y
		if start <= end:
			if hour >= start and hour < end:
				return true
		else:
			if hour >= start or hour < end:
				return true
	return false




static func _calc_base_visitors_from_trade_area(
		trade_area: TradeAreaSnapshot,
		storefront: StorefrontData,
		category: CategoryData
) -> int:
	var base := trade_area.total_effective_audience if trade_area != null else 100.0
	var reachable := base * storefront.flow_share
	var visitors := reachable * category.base_entry_rate
	return maxi(1, int(visitors))

static func _calc_waste_cost(unit_ingredient_cost: float, inventory: int, sold: int) -> float:
	var threshold := int(sold * SettlementConfig.WASTE_THRESHOLD_RATIO)
	if inventory <= threshold:
		return 0.0
	var excess := inventory - threshold
	return excess * unit_ingredient_cost * SettlementConfig.WASTE_COST_RATIO_OF_INGREDIENT



static func _is_weekend_day(day: int) -> bool:
	return (day % 7) in SettlementConfig.WEEKEND_DAY_REMAINDERS


## 用真实字段重建：product.get_actual_margin_rate()对比product.suggested_margin_rate，
## 毛利率偏离建议值越大，到店意愿修正越负。取代原来编造的"suggested_price"模型。
static func _calc_price_mod(product: ProductData) -> float:
	var actual_margin := product.get_actual_margin_rate(product.average_price)
	var deviation := actual_margin - product.suggested_margin_rate
	return clampf(-deviation * 0.5, -0.08, 0.05)


static func _calc_reputation_mod(reputation: float) -> float:
	return reputation / 200.0


static func _calc_staff_mod(has_key_staff: bool) -> float:
	if has_key_staff:
		return 0.03
	return -0.05


## 当前CharacterCreationData里的特质系统只影响精力/疲惫/调研/压力/谈判这些
## 全局属性（TraitData.effects是一个Dictionary，没有effect_type/effect_target
## 这种"按品类/商品生效"的字段），目前不存在任何"对特定品类/商品加成"的特质。
## 这里先返回0.0占位，等特质系统真的扩展出这类效果时再实现具体逻辑。
static func _calc_trait_mods(player_state: PlayerState, category: CategoryData, product: ProductData) -> float:
	return 0.0


## 用真实字段重建：hourly_capacity_base × 服务速度系数，缺关键员工时按
## missing_key_staff_capacity_penalty打折。取代原来编造的capacity_multiplier。
static func _calc_slot_capacity(storefront: StorefrontData, category: CategoryData, has_key_staff: bool) -> int:
	var cap := float(storefront.hourly_capacity_base)
	cap *= SettlementConfig.SERVICE_SPEED_MOD.get(category.base_service_speed, 1.0)
	if category.key_staff_type != "none" and not has_key_staff:
		cap *= (1.0 - category.missing_key_staff_capacity_penalty)
	return maxi(1, int(cap))


## 用真实字段重建：monthly_rent_wan换算到每小时。取代原来编造的daily_rent字段。
static func _calc_rent_cost(storefront: StorefrontData) -> float:
	return storefront.get_monthly_rent_yuan() / 30.0 / 24.0


static func _calc_utility_cost(
		product: ProductData,
		store_state: Store,
		is_open: bool
) -> float:
	if not is_open:
		return 0.0
	var unit_cost := product.utility_cost_per_unit
	var total_units := 0
	for slot in store_state.category_slots:
		for pc in slot.product_configs:
			if pc.product_id == product.id:
				total_units += pc.inventory_units
	return float(total_units) * unit_cost


## CategoryData本身不建模人力成本字段（真实项目里人力成本不在这一层结算），
## 固定返回0.0，与你项目原有模型保持一致。
static func _calc_staff_cost() -> float:
	return 0.0


static func _calc_reputation_gain(actual_orders: int, inventory_limit: int) -> float:
	if inventory_limit <= 0:
		return 0.0
	var fill_rate := float(actual_orders) / float(inventory_limit)
	if fill_rate >= 1.0:
		return 0.8
	elif fill_rate >= 0.8:
		return 0.4
	elif fill_rate >= 0.5:
		return 0.1
	return 0.0


static func _calc_reputation_loss_from_stockout(actual_orders: int, inventory_limit: int) -> float:
	if inventory_limit <= 0:
		return 0.0
	if actual_orders >= inventory_limit:
		return 0.0
	var lost := float(inventory_limit - actual_orders) / float(inventory_limit)
	if lost > 0.5:
		return 0.6
	elif lost > 0.2:
		return 0.3
	return 0.1


static func _calc_stress_delta(r: SettlementResult, owner_supervising: bool) -> float:
	var stress := 0.0
	if r.profit < 0.0:
		stress += 1.0
	if r.actual_orders == 0 and r.is_open:
		stress += 1.0
	if r.missing_key_staff_active:
		stress += 1.0
	if owner_supervising:
		stress += 2.0
	return stress
