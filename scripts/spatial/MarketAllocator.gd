class_name MarketAllocator

static func make_pool_key(city_region_id: String, block_id: String, group_id: String, category_id: String, day: int, hour: int) -> String:
	return "%s|%s|%s|%s|%d|%02d" % [city_region_id, block_id, group_id, category_id, day, hour]

static func calculate_participant_weight(participant: Dictionary) -> float:
	if not bool(participant.get("is_operating", false)) or not bool(participant.get("offers_category", false)):
		return 0.0
	var distance := maxf(0.0, float(participant.get("distance", 0.0)))
	var distance_factor := 1.0 / (1.0 + distance / 800.0)
	var accessibility := maxf(0.0, float(participant.get("block_accessibility", 1.0))) * maxf(0.0, float(participant.get("storefront_accessibility", 1.0)))
	var capture := maxf(0.0, float(participant.get("capture_modifier", 1.0)))
	var business_match := maxf(0.0, float(participant.get("business_match", 1.0)))
	var reputation := 0.5 + clampf(float(participant.get("reputation", 0.0)) / 100.0, 0.0, 1.0)
	var awareness := 1.0 + clampf(float(participant.get("awareness", 0.0)) / 100.0, 0.0, 1.0) * 0.25
	return maxf(0.0, distance_factor * accessibility * capture * business_match * reputation * awareness)

static func describe_pool(raw_supply: int, external_competition_ratio: float, participant_weights: Dictionary) -> Dictionary:
	var raw := maxi(0, raw_supply)
	var loss := clampi(int(round(float(raw) * clampf(external_competition_ratio, 0.0, 1.0))), 0, raw)
	var remaining := raw - loss
	var allocation := allocate_finite_pool(remaining, participant_weights)
	var loss_allocation := allocate_finite_pool(loss, participant_weights)
	return {"raw_supply": raw, "external_competition_loss": loss, "remaining_supply": remaining, "allocations": allocation.get("allocations", {}), "external_competition_losses": loss_allocation.get("allocations", {}), "unallocated": allocation.get("unallocated", remaining)}

## Deterministic finite-pool allocation used by the per-block shared market.
static func allocate_finite_pool(pool_visitors: int, participant_weights: Dictionary) -> Dictionary:
	var result := {"allocations": {}, "unallocated": maxi(0, pool_visitors)}
	var total := 0.0
	for store_id in participant_weights:
		total += maxf(0.0, float(participant_weights[store_id]))
	if total <= 0.0001 or pool_visitors <= 0:
		return result
	var keys: Array = participant_weights.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	var assigned := 0
	var remainders: Array[Dictionary] = []
	for store_id in keys:
		var exact := float(pool_visitors) * maxf(0.0, float(participant_weights[store_id])) / total
		var count := maxi(0, int(floor(exact)))
		result.allocations[store_id] = count
		assigned += count
		remainders.append({"store_id": store_id, "fraction": exact - float(count)})
	remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.fraction), float(b.fraction)):
			return float(a.fraction) > float(b.fraction)
		return str(a.store_id) < str(b.store_id)
	)
	for index in mini(pool_visitors - assigned, remainders.size()):
		var store_id: Variant = remainders[index].store_id
		result.allocations[store_id] = int(result.allocations[store_id]) + 1
		assigned += 1
	result.unallocated = pool_visitors - assigned
	return result
static func get_player_market_share(store: Store, storefront: StorefrontData, all_stores: Array[Store], category_id: String = "") -> Dictionary:
	if store == null or storefront == null:
		return {"share": 1.0, "competitor_count": 0}
	var own_weight := _get_weight(store, storefront, category_id)
	var total := 0.0
	var competitors := 0
	for other in all_stores:
		if other == null or not other.is_open:
			continue
		var other_front := GameManager.get_storefront(other.selected_storefront_id)
		if other_front == null or other_front.city_region_id != storefront.city_region_id:
			continue
		if not category_id.is_empty() and not _store_offers_category(other, category_id):
			continue
		total += _get_weight(other, other_front, category_id)
		if other.id != store.id:
			competitors += 1
	if total <= 0.0001:
		return {"share": 1.0, "competitor_count": 0}
	return {"share": clampf(own_weight / total, 0.0, 1.0), "competitor_count": competitors}

static func _get_weight(store: Store, storefront: StorefrontData, category_id: String) -> float:
	var category_fit := 1.0
	if not category_id.is_empty():
		var category := GameManager.get_category(category_id)
		category_fit = category.base_entry_rate if category != null else 0.1
	return maxf(0.05, storefront.flow_share * storefront.capture_modifier * category_fit * (0.5 + store.reputation / 100.0))

static func _store_offers_category(store: Store, category_id: String) -> bool:
	if store == null:
		return false
	for slot in store.category_slots:
		if slot.category_id == category_id and not slot.product_configs.is_empty():
			return true
	return false
