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
		store_is_business_open: bool,
		staffing_power: float
) -> Dictionary:
	var is_open := store_is_business_open and staffing_power > 0.0
	var owner_supervising := player_state.supervising_store_id == store_state.id
	var base_visitors := _calc_base_visitors_from_trade_area(trade_area, storefront, category)
	var price_mod := _calc_price_mod(product)
	var reputation_mod := _calc_reputation_mod(store_state.reputation)
	var owner_mod := 0.03 if owner_supervising else 0.0
	var trait_mods := _calc_trait_mods(player_state, category, product)

	var visitors := 0
	var conversion_rate := 0.0

	if is_open:
		conversion_rate = clampf(
			0.10
			+ price_mod
			+ reputation_mod
			+ owner_mod
			+ trait_mods,
			0.0, 0.9
		)

		visitors = int(float(base_visitors) * (1.0 + trait_mods))

	var group_profiles := _make_group_order_profiles(
		trade_area, storefront, category, product, hour, conversion_rate, trait_mods
	)
	if is_open and not group_profiles.is_empty():
		visitors = 0
		for profile in group_profiles.values():
			visitors += int(profile.get("visitors", 0))

	return {
		"is_open": is_open,
		"visitors": visitors,
		"conversion_rate": conversion_rate,
		## Fixed rent, equipment power and wages are settled once per store by
		## GameManager. Product records carry only order-dependent costs.
		"rent_cost": 0.0,
		"utility_cost": 0.0,
		"staff_cost": 0.0,
		"owner_supervising": owner_supervising,
		"trade_area": trade_area,
		"storefront": storefront,
		"category": category,
		"product": product,
		"hour": hour,
		"staffing_power": staffing_power,
		"business_open": store_is_business_open,
		"base_visitors": base_visitors,
		"price_modifier": price_mod,
		"reputation_modifier": reputation_mod,
		"owner_modifier": owner_mod,
		"trait_modifier": trait_mods,
		"group_profiles": group_profiles,
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
	var trade_area: TradeAreaSnapshot = params.get("trade_area", null)
	var storefront: StorefrontData = params.get("storefront", null)
	var slot_foot_traffic := trade_area.total_effective_audience if trade_area != null else 0.0
	r.slot_foot_traffic = slot_foot_traffic
	var capture_multiplier := maxf(0.0, storefront.capture_modifier) if storefront != null else 0.0
	r.reachable_traffic = slot_foot_traffic * storefront.flow_share * capture_multiplier if storefront != null else 0.0
	r.entry_rate = category.base_entry_rate
	r.natural_visitors = int(params.get("natural_visitors", r.visitors))
	r.destination_visitors = int(params.get("destination_visitors", 0))
	r.market_pool_remaining_supply = int(params.get("market_pool_remaining_supply", 0))
	r.market_pool_share = float(params.get("market_pool_share", 0.0))
	r.conversion_rate = float(params.get("conversion_rate", 0.0))
	r.inventory_limit = inventory_limit
	r.base_visitors = int(params.get("base_visitors", 0))
	r.business_open = bool(params.get("business_open", false))
	r.staffing_power = float(params.get("staffing_power", 0.0))
	r.unit_price = product.average_price
	r.price_modifier = float(params.get("price_modifier", 0.0))
	r.reputation_modifier = float(params.get("reputation_modifier", 0.0))
	r.owner_modifier = float(params.get("owner_modifier", 0.0))
	r.trait_modifier = float(params.get("trait_modifier", 0.0))
	r.modifiers = [
		{"label": "\u5b9a\u4ef7", "value": r.price_modifier},
		{"label": "\u53e3\u7891", "value": r.reputation_modifier},
		{"label": "\u5e97\u4e3b\u7763\u5bfc", "value": r.owner_modifier},
		{"label": "\u7279\u8d28", "value": r.trait_modifier},
	]

	var layout_capture_multiplier := float(params.get("layout_capture_multiplier", 1.0))
	if not is_equal_approx(layout_capture_multiplier, 1.0):
		r.modifiers.append({"label": "layout_signboard", "value": layout_capture_multiplier - 1.0})

	if not r.is_open or sim == null:
		r.rent_cost = 0.0
		r.utility_cost = 0.0
		r.staff_cost = 0.0
		r.profit = -(r.rent_cost + r.utility_cost + r.staff_cost)
		if not r.business_open:
			r.not_open_reason = "\u95e8\u5e97\u5f53\u524d\u5904\u4e8e\u5173\u95e8\u72b6\u6001"
		elif r.staffing_power <= 0.0:
			r.not_open_reason = "\u5f53\u524d\u65f6\u6bb5\u6ca1\u6709\u53ef\u7528\u7684\u6280\u80fd\u4eba\u624b"
		else:
			r.not_open_reason = "\u5f53\u524d\u5546\u54c1\u672a\u6ee1\u8db3\u8425\u4e1a\u6761\u4ef6"
		r.reputation_delta = 0.0
		r.stress_delta = 0.0
		return r

	r.actual_orders = sim.actual_orders
	r.group_summary = sim.group_summary.duplicate(true)
	r.lost_price_rejection = sim.rejected_price_count
	r.lost_self_cannibalization = int(params.get("lost_self_cannibalization", 0))
	r.average_queue_wait_seconds = sim.total_wait_seconds / float(sim.actual_orders) if sim.actual_orders > 0 else 0.0
	r.max_queue_wait_seconds = sim.max_wait_seconds
	r.queue_patience_seconds = sim.max_queue_wait_seconds
	r.service_time_seconds = sim.service_time_seconds
	r.visitors = sim.visitors_so_far
	r.theoretical_orders = sim.converted_count
	r.lost_no_entry = maxi(0, int(r.reachable_traffic) - r.visitors)
	r.lost_no_conversion = maxi(0, r.visitors - sim.converted_count)
	r.lost_capacity = sim.rejected_capacity_count
	r.lost_inventory = sim.rejected_inventory_count
	r.revenue = sim.revenue
	r.ingredient_cost = sim.ingredient_cost
	r.utility_cost = sim.utility_cost
	r.waste_cost = 0.0
	r.rent_cost = 0.0
	r.staff_cost = 0.0

	r.profit = r.revenue - r.ingredient_cost - r.rent_cost - r.utility_cost - r.staff_cost

	var rep_gain := _calc_reputation_gain(r.actual_orders, inventory_limit)
	var rep_loss := _calc_reputation_loss_from_stockout(r.actual_orders, inventory_limit)
	r.reputation_delta = clampf(rep_gain - rep_loss, -5.0, 5.0)

	var owner_supervising: bool = params.get("owner_supervising", false)
	r.stress_delta = _calc_stress_delta(r, owner_supervising)
	if r.price_modifier > 0.0:
		r.top_positive.append("\u5b9a\u4ef7\u4e0e\u5efa\u8bae\u6bdb\u5229\u66f4\u5339\u914d")
	elif r.price_modifier < 0.0:
		r.top_negative.append("\u5b9a\u4ef7\u504f\u79bb\u5efa\u8bae\u6bdb\u5229\uff0c\u538b\u4f4e\u8f6c\u5316")
	if r.reputation_modifier > 0.0:
		r.top_positive.append("\u53e3\u7891\u63d0\u5347\u4e86\u8f6c\u5316\u610f\u613f")
	if sim.rejected_capacity_count > 0:
		r.top_negative.append("\u6392\u961f\u7b49\u5f85\u8d85\u8fc7\u987e\u5ba2\u5fcd\u8010\u65f6\u95f4")
	if sim.rejected_inventory_count > 0:
		r.top_negative.append("\u539f\u6750\u6599\u4e0d\u8db3\u5bfc\u81f4\u65e0\u6cd5\u4e0b\u5355")

	return r


# ── 内部辅助函数 ────────────────────────────────────────────

static func _calc_base_visitors_from_trade_area(
		trade_area: TradeAreaSnapshot,
		storefront: StorefrontData,
		category: CategoryData
) -> int:
	var base := trade_area.total_effective_audience if trade_area != null else 100.0
	var reachable := base * storefront.flow_share * maxf(0.0, storefront.capture_modifier)
	var visitors := reachable * category.base_entry_rate
	return maxi(1, int(visitors))


static func _make_group_order_profiles(trade_area: TradeAreaSnapshot, storefront: StorefrontData, category: CategoryData, product: ProductData, hour: int, base_conversion: float, trait_mod: float) -> Dictionary:
	var profiles := {}
	if trade_area == null or storefront == null or category == null or product == null:
		return profiles
	var preference := CustomerPreferenceConfig.get_profile(category, product)
	var market := _get_weighted_market_profile(trade_area)
	var capture := storefront.flow_share * maxf(0.0, storefront.capture_modifier) * category.base_entry_rate
	for group_id in SpatialConfig.POPULATION_GROUPS:
		var audience := float(trade_area.reachable_groups.get(group_id, 0.0)) * capture
		var affinity := CustomerPreferenceConfig.get_group_affinity(preference, group_id)
		var time_affinity := CustomerPreferenceConfig.get_time_affinity(preference, hour)
		var spend_affinity := CustomerPreferenceConfig.get_spending_affinity(str(preference.get("spending_tier", "medium")), str(market.get("tier", "medium")))
		var price_penalty := (1.0 - float(market.get("price_sensitivity", 0.5))) * 0.03
		var quality_bonus := float(market.get("quality_preference", 0.5)) * float(preference.get("quality_bias", 0.0)) * 0.08
		var conversion := clampf(base_conversion * affinity * time_affinity * spend_affinity + price_penalty + quality_bonus, 0.0, 0.95)
		profiles[group_id] = {
			"visitors": maxi(0, int(round(audience * affinity * time_affinity * (1.0 + trait_mod)))),
			"conversion_rate": conversion,
			"price_rejection_rate": clampf((1.0 - spend_affinity) * (0.35 + float(market.get("price_sensitivity", 0.5)) * 0.45), 0.0, 0.6),
		}
	if trade_area.external_traffic > 0.0:
		profiles["external"] = {"visitors": maxi(0, int(round(trade_area.external_traffic * capture))), "conversion_rate": base_conversion}
	return profiles


static func _get_weighted_market_profile(trade_area: TradeAreaSnapshot) -> Dictionary:
	var total := 0.0
	var sensitivity := 0.0
	var quality := 0.0
	var tiers := {"low": 0.0, "medium": 0.0, "high": 0.0}
	if trade_area != null:
		for contribution in trade_area.block_contributions:
			var weight := maxf(0.0, float(contribution.get("contribution", 0.0)))
			var spending: Dictionary = contribution.get("spending_profile", {})
			total += weight
			sensitivity += weight * float(spending.get("price_sensitivity", 0.5))
			quality += weight * float(spending.get("quality_preference", 0.5))
			var tier := str(spending.get("spend_potential_tier", "medium"))
			tiers[tier] = float(tiers.get(tier, 0.0)) + weight
	if total <= 0.0001:
		return {"price_sensitivity": 0.5, "quality_preference": 0.5, "tier": "medium"}
	var chosen_tier := "medium"
	for tier in tiers:
		if float(tiers[tier]) > float(tiers[chosen_tier]):
			chosen_tier = tier
	return {"price_sensitivity": sensitivity / total, "quality_preference": quality / total, "tier": chosen_tier}

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


## 当前CharacterCreationData里的特质系统只影响精力/疲惫/调研/压力/谈判这些
## 全局属性（TraitData.effects是一个Dictionary，没有effect_type/effect_target
## 这种"按品类/商品生效"的字段），目前不存在任何"对特定品类/商品加成"的特质。
## 这里先返回0.0占位，等特质系统真的扩展出这类效果时再实现具体逻辑。
static func _calc_trait_mods(player_state: PlayerState, category: CategoryData, product: ProductData) -> float:
	return 0.0


## 用真实字段重建：monthly_rent_wan换算到每小时。取代原来编造的daily_rent字段。
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
	if owner_supervising:
		stress += 2.0
	return stress
