extends Node

var store_state: StoreState = StoreState.new()
var player_state: PlayerState = PlayerState.new()
var last_settlement_error: String = ""

var all_origins: Array[OriginData] = []

var current_region: RegionData = null
var current_storefront: StorefrontData = null

var all_regions: Array[RegionData] = []
var all_storefronts: Array[StorefrontData] = []
var all_categories: Array[CategoryData] = []
var all_products: Array[ProductData] = []
var all_ingredients: Array[IngredientData] = []

func _ready() -> void:
	all_regions     = GameData.get_regions()
	all_storefronts = GameData.get_storefronts()
	all_categories  = GameData.get_categories()
	all_products    = GameData.get_products()
	all_ingredients = GameData.get_ingredients()
	all_origins = GameData.get_origins()

func get_origin(origin_id: String) -> OriginData:
	for origin in all_origins:
		if origin.id == origin_id:
			return origin
	return null

func get_region(id: String) -> RegionData:
	for r in all_regions:
		if r.id == id: return r
	return null

func get_storefront(id: String) -> StorefrontData:
	for s in all_storefronts:
		if s.id == id: return s
	return null

func get_category(id: String) -> CategoryData:
	for c in all_categories:
		if c.id == id: return c
	return null

func get_product(id: String) -> ProductData:
	for p in all_products:
		if p.id == id: return p
	return null

func get_products_for_category(category_id: String) -> Array[ProductData]:
	var result: Array[ProductData] = []
	for p in all_products:
		if p.category_id == category_id:
			result.append(p)
	return result

func get_ingredient(id: String) -> IngredientData:
	for i in all_ingredients:
		if i.id == id: return i
	return null

func get_ingredients_in_use() -> Array[IngredientData]:
	var used_ids: Dictionary = {}
	for slot in store_state.category_slots:
		for pc in slot.product_configs:
			var product := get_product(pc.product_id)
			if product == null:
				continue
			for r in product.recipe:
				used_ids[r.ingredient_id] = true
	var result: Array[IngredientData] = []
	for id in used_ids.keys():
		var ing := get_ingredient(id)
		if ing != null:
			result.append(ing)
	return result

func get_ingredient_purchase_price(ingredient_id: String) -> float:
	var ingredient := get_ingredient(ingredient_id)
	if ingredient == null:
		return 0.0
	return ingredient.base_purchase_price

func get_product_unit_utility_cost(product: ProductData) -> float:
	return product.utility_cost_per_unit

func select_origin(origin_id: String) -> Dictionary:
	var origin := get_origin(origin_id)
	if origin == null:
		return {"success": false, "reason": "出身不存在"}

	if store_state.is_open:
		return {"success": false, "reason": "门店已开业，不能更换出身"}

	store_state.selected_origin_id = origin.id
	player_state.cash = origin.starting_cash
	player_state.stress = origin.initial_stress
	store_state.reputation = origin.initial_reputation

	store_state.selected_region_id = ""
	store_state.selected_storefront_id = ""
	store_state.signed_storefront_id = ""
	store_state.researched_region_ids.clear()
	store_state.inspected_storefront_ids.clear()
	store_state.category_slots.clear()
	store_state.ingredient_stock.clear()
	store_state.ingredient_avg_cost.clear()
	store_state.is_open = false

	current_region = null
	current_storefront = null

	return {
		"success": true,
		"reason": "已选择出身：「%s」" % origin.name
	}

func research_region(region_id: String) -> Dictionary:
	var region := get_region(region_id)
	if region == null:
		return {"success": false, "reason": "区域不存在"}

	if region_id in store_state.researched_region_ids:
		return {"success": false, "reason": "该区域已调研"}

	var origin := get_origin(store_state.selected_origin_id)
	var discount: float = 0.0
	if origin != null:
		discount = origin.research_discount_rate

	var cost: float = region.research_cost * (1.0 - discount)

	if player_state.cash < cost:
		return {"success": false, "reason": "现金不足，调研需要¥%.0f" % cost}

	player_state.cash -= cost
	store_state.researched_region_ids.append(region_id)

	return {
		"success": true,
		"reason": "已完成对「%s」的调研，花费¥%.0f" % [region.name, cost]
	}


func select_region(region_id: String) -> Dictionary:
	if store_state.is_open:
		return {"success": false, "reason": "门店已开业，不能更换区域"}

	if region_id not in store_state.researched_region_ids:
		return {"success": false, "reason": "请先调研该区域"}

	var region := get_region(region_id)
	if region == null:
		return {"success": false, "reason": "区域不存在"}

	store_state.selected_region_id = region_id
	store_state.selected_storefront_id = ""
	store_state.signed_storefront_id = ""
	current_region = region
	current_storefront = null

	return {"success": true, "reason": "已选定区域：「%s」" % region.name}

func get_storefronts_for_region(region_id: String) -> Array[StorefrontData]:
	var result: Array[StorefrontData] = []
	for s in all_storefronts:
		if s.region_id == region_id:
			result.append(s)
	return result


func select_storefront(storefront_id: String) -> Dictionary:
	if store_state.is_open:
		return {"success": false, "reason": "门店已开业，不能更换门面"}

	if store_state.selected_region_id == "":
		return {"success": false, "reason": "请先选定区域"}

	var sf := get_storefront(storefront_id)
	if sf == null:
		return {"success": false, "reason": "门面不存在"}

	if sf.region_id != store_state.selected_region_id:
		return {"success": false, "reason": "该门面不属于当前选定区域"}

	store_state.selected_storefront_id = storefront_id
	store_state.category_slots.clear()
	_sync_data_objects()

	return {"success": true, "reason": "已选定门面：「%s」" % sf.name}

func calculate_purchase_total(cart: Dictionary) -> float:
	var total := 0.0
	for ingredient_id in cart:
		var quantity := float(cart[ingredient_id])
		if quantity <= 0.0:
			continue
		total += get_ingredient_purchase_price(ingredient_id) * quantity
	return total


func purchase_ingredients(cart: Dictionary) -> Dictionary:
	var total_cost := calculate_purchase_total(cart)

	if cart.is_empty():
		return {"success": false, "reason": "未选择任何原材料"}

	if total_cost <= 0.0:
		return {"success": false, "reason": "采购数量必须大于0"}

	if player_state.cash < total_cost:
		return {
			"success": false,
			"reason": "现金不足，需要%.0f元，当前仅有%.0f元"
				% [total_cost, player_state.cash]
		}

	for ingredient_id in cart:
		var quantity := float(cart[ingredient_id])
		if quantity <= 0.0:
			continue

		var ingredient := get_ingredient(ingredient_id)
		if ingredient == null:
			return {"success": false, "reason": "原材料不存在：" + ingredient_id}

		var unit_price := get_ingredient_purchase_price(ingredient_id)
		store_state.add_ingredient_stock(
			ingredient_id,
			quantity,
			unit_price
		)

	player_state.cash -= total_cost

	return {
		"success": true,
		"reason": "采购完成",
		"total_cost": total_cost
	}

func get_product_unit_ingredient_cost(product: ProductData) -> float:
	var total_cost := 0.0

	for recipe_item in product.recipe:
		var ingredient_id: String = recipe_item.get("ingredient_id", "")
		var quantity: float = float(recipe_item.get("quantity", 0.0))
		total_cost += quantity * store_state.get_ingredient_avg_cost(ingredient_id)

	return total_cost

func set_ingredient_stock(ingredient_id: String, amount: float) -> void:
	store_state.set_ingredient_stock(ingredient_id, amount)

func _sync_data_objects() -> void:
	current_region = get_region(store_state.selected_region_id)
	current_storefront = get_storefront(store_state.selected_storefront_id)


# ── 品类添加/管理 ───────────────────────────────────────

func get_category_options_for_current_store() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if current_storefront == null:
		return options
	var available_area := store_state.get_available_area(current_storefront)
	for cat in all_categories:
		var supported: bool = cat.id in current_storefront.supported_categories
		if not supported:
			continue
		var already_added := store_state.has_category(cat.id)
		var fits := cat.required_area <= available_area
		var can_add := supported and not already_added and fits
		var reason := ""
		if already_added:
			reason = "已添加"
		elif not fits:
			reason = "面积不足（需%.0f㎡，剩余%.0f㎡）" % [cat.required_area, available_area]
		options.append({
			"category": cat,
			"already_added": already_added,
			"can_add": can_add,
			"reason": reason,
		})
	return options

func add_category_to_store(category_id: String, product_ids: Array[String],
		has_key_staff: bool = false, strategy: String = "standard") -> Dictionary:
	if current_storefront == null:
		return {"success": false, "reason": "尚未选择门面"}
	var cat := get_category(category_id)
	if cat == null:
		return {"success": false, "reason": "品类不存在"}
	if store_state.has_category(category_id):
		return {"success": false, "reason": "该品类已添加"}
	if product_ids.is_empty():
		return {"success": false, "reason": "请至少选择一个商品"}
	if category_id not in current_storefront.supported_categories:
		return {"success": false, "reason": "门面不支持该品类"}
	var available := store_state.get_available_area(current_storefront)
	if cat.required_area > available:
		return {"success": false, "reason": "面积不足（需%.0f㎡，剩余%.0f㎡）" % [cat.required_area, available]}
	var setup_cost := cat.setup_cost_wan * 10000.0
	if player_state.cash < setup_cost:
		return {"success": false, "reason": "现金不足，开设需要%.0f元装修/设备投入" % setup_cost}

	var slot := StoreCategorySlot.new()
	slot.category_id = category_id
	slot.has_key_staff = has_key_staff
	slot.strategy = strategy
	slot.allocated_area = cat.required_area
	for pid in product_ids:
		var pc := StoreProductConfig.new()
		pc.product_id = pid
		pc.inventory_units = SettlementConfig.INITIAL_INVENTORY
		slot.product_configs.append(pc)
	store_state.category_slots.append(slot)
	player_state.cash -= setup_cost
	return {"success": true, "reason": ""}

func add_product_to_slot(category_id: String, product_id: String) -> bool:
	var slot := store_state.get_slot_by_category(category_id)
	if slot == null or slot.has_product(product_id):
		return false
	var pc := StoreProductConfig.new()
	pc.product_id = product_id
	pc.inventory_units = SettlementConfig.INITIAL_INVENTORY
	slot.product_configs.append(pc)
	return true

func remove_product_from_slot(category_id: String, product_id: String) -> bool:
	var slot := store_state.get_slot_by_category(category_id)
	if slot == null:
		return false
	for i in range(slot.product_configs.size()):
		if slot.product_configs[i].product_id == product_id:
			slot.product_configs.remove_at(i)
			return true
	return false

func remove_category_from_store(category_id: String) -> bool:
	for i in range(store_state.category_slots.size()):
		if store_state.category_slots[i].category_id == category_id:
			store_state.category_slots.remove_at(i)
			return true
	return false

func set_product_price_override(category_id: String, product_id: String, new_price: float) -> bool:
	var slot := store_state.get_slot_by_category(category_id)
	if slot == null:
		return false
	var pc := slot.get_product_config(product_id)
	if pc == null:
		return false
	pc.custom_price = new_price
	return true

func set_product_inventory(category_id: String, product_id: String, new_units: int) -> bool:
	var slot := store_state.get_slot_by_category(category_id)
	if slot == null:
		return false
	var pc := slot.get_product_config(product_id)
	if pc == null:
		return false
	pc.inventory_units = maxi(0, new_units)
	return true

func set_category_strategy(category_id: String, strategy: String) -> bool:
	var slot := store_state.get_slot_by_category(category_id)
	if slot == null:
		return false
	slot.strategy = strategy
	return true

func set_category_key_staff(category_id: String, has_staff: bool) -> bool:
	var slot := store_state.get_slot_by_category(category_id)
	if slot == null:
		return false
	slot.has_key_staff = has_staff
	return true

func set_category_area(category_id: String, new_area: float) -> Dictionary:
	var cat := get_category(category_id)
	var slot := store_state.get_slot_by_category(category_id)
	if cat == null or slot == null or current_storefront == null:
		return {"success": false, "reason": "品类不存在", "clamped_area": 0.0}

	var other_area: float = store_state.get_used_area() - slot.allocated_area
	var max_area: float = current_storefront.area - other_area
	var min_area: float = cat.required_area

	if max_area < min_area:
		return {"success": false, "reason": "门店总面积不足以维持最低需求", "clamped_area": slot.allocated_area}

	var clamped: float = clampf(new_area, min_area, max_area)
	slot.allocated_area = clamped
	return {"success": true, "reason": "", "clamped_area": clamped}

# ── 开业 ────────────────────────────────────────────────

func get_open_readiness() -> Dictionary:
	var checks: Array[Dictionary] = []

	var has_storefront := current_storefront != null
	checks.append({
		"label": "已签约门面",
		"passed": has_storefront,
	})

	var has_category := not store_state.category_slots.is_empty()
	checks.append({
		"label": "已添加至少一个经营品类",
		"passed": has_category,
	})

	var has_inventory := store_state.get_total_inventory_across_slots() > 0
	checks.append({
		"label": "已备货（至少一个商品有库存）",
		"passed": has_inventory,
	})

	var can_open: bool = has_storefront and has_category and has_inventory

	return {
		"can_open": can_open,
		"checks": checks,
	}

func open_store() -> Dictionary:
	if store_state.is_open:
		return {"success": false, "reason": "门店已经开业"}
	var readiness := get_open_readiness()
	if not readiness.can_open:
		return {"success": false, "reason": "开业条件尚未全部满足，请查看开业清单"}
	store_state.is_open = true
	return {"success": true, "reason": "门店已开业！"}

# ── 结算（现在遍历门店内所有品类实例） ──────────────────

func run_settlement() -> Array[SettlementResult]:
	last_settlement_error = ""
	var results: Array[SettlementResult] = []

	if current_region == null or current_storefront == null:
		last_settlement_error = "尚未选择区域或门面"
		push_error("GameManager: " + last_settlement_error)
		return results

	if store_state.category_slots.is_empty():
		last_settlement_error = "尚未添加任何品类"
		push_error("GameManager: " + last_settlement_error)
		return results

	var total_area: float = current_storefront.area
	for slot in store_state.category_slots:
		var category := get_category(slot.category_id)
		if category == null or slot.product_configs.is_empty():
			continue

		var area_share: float = slot.allocated_area / total_area
		var product_count: int = slot.product_configs.size()

		for pc in slot.product_configs:
			var product_template := get_product(pc.product_id)
			if product_template == null:
				continue

			var scaled_storefront: StorefrontData = current_storefront.duplicate()
			scaled_storefront.hourly_capacity_base = int(round(
				current_storefront.hourly_capacity_base * area_share / product_count))
			scaled_storefront.flow_share = current_storefront.flow_share / product_count

			var product_instance: ProductData = product_template.duplicate()
			product_instance.average_price = pc.get_effective_price(product_template)
			product_instance.recipe = product_template.recipe

			var available_units := store_state.get_max_produceable_by_ingredients(product_template)
			var unit_ingredient_cost := get_product_unit_ingredient_cost(product_template)
			var unit_utility_cost := get_product_unit_utility_cost(product_template)

			var result := SettlementEngine.calculate(
				current_region,
				scaled_storefront,
				category,
				product_instance,
				store_state,
				player_state,
				store_state.get_current_slot(),
				store_state.current_day,
				slot.has_key_staff,
				slot.strategy,
				available_units,
				unit_ingredient_cost,
				unit_utility_cost,
				)

			var extra_upkeep: float = (category.extra_rent_wan * 10000.0) \
				/ 30.0 / SettlementConfig.SLOT_ORDER.size() / product_count
			result.rent_cost += extra_upkeep
			result.profit -= extra_upkeep

			store_state.consume_ingredients(product_template, result.actual_orders)
			store_state.apply_settlement(result)
			player_state.apply_settlement(result)
			results.append(result)

	return results

func advance_time_only() -> void:
	store_state.advance_slot()

## 开始全新一局：完全重建门店与玩家状态，不保留任何选择/进度/存档影响。
func start_new_game() -> void:
	store_state = StoreState.new()
	player_state = PlayerState.new()
	current_region = null
	current_storefront = null
