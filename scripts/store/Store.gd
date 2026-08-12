class_name Store
extends RefCounted
## 多店重构阶段1：原StoreState精简重命名而来。一个Store实例=玩家名下的
## 一家具体店铺，GameManager.stores可以同时持有多个实例。
##
## 迁移出去(→PlayerState)：region_intel_levels/region_intel_progress/
## block_understanding/storefront_diligence/survey_areas/
## focused_city_region_id/owner_present(→supervising_store_id)。
##
## 清理的死字段：current_day(与TimeManager.current_day重复)、
## inventory_units/inventory_capacity(库存实际记在StoreProductConfig)。
##
## 新增：id、name，用于多店场景下的身份标识。

enum PreOpenStage {
	CHARACTER_CREATION,
	REGION_RESEARCH,
	STOREFRONT_SELECTION,
	STORE_SETUP,
	OPEN_FOR_BUSINESS
}

var id: String = ""
var name: String = ""

var pre_open_stage: PreOpenStage = PreOpenStage.CHARACTER_CREATION

var selected_region_id: String = ""
var selected_storefront_id: String = ""
var signed_storefront_id: String = ""
var is_open: bool = false

var reputation: float = SettlementConfig.INITIAL_REPUTATION

var category_slots: Array[StoreCategorySlot] = []

var ingredient_stock: Dictionary = {}
var ingredient_avg_cost: Dictionary = {}

var total_revenue: float = 0.0
var total_cost: float = 0.0
var total_orders: int = 0
var total_lost_inventory: int = 0
var total_lost_capacity: int = 0
var missing_key_staff_penalty_count: int = 0
var daily_history: Array[Dictionary] = []


func get_used_area() -> float:
	var total := 0.0
	for slot in category_slots:
		total += slot.allocated_area
	return total


func get_available_area(storefront: StorefrontData) -> float:
	if storefront == null:
		return 0.0
	return storefront.area - get_used_area()


func has_category(category_id: String) -> bool:
	for slot in category_slots:
		if slot.category_id == category_id:
			return true
	return false


func get_slot_by_category(category_id: String) -> StoreCategorySlot:
	for slot in category_slots:
		if slot.category_id == category_id:
			return slot
	return null


func get_total_inventory_across_slots() -> int:
	var total := 0
	for slot in category_slots:
		total += slot.get_total_inventory()
	return total


func get_ingredient_stock(ingredient_id: String) -> float:
	return ingredient_stock.get(ingredient_id, 0.0)


func set_ingredient_stock(ingredient_id: String, amount: float) -> void:
	ingredient_stock[ingredient_id] = maxf(0.0, amount)


func get_max_produceable_by_ingredients(product: ProductData) -> int:
	if product.recipe.is_empty():
		return 999999
	var max_units: float = INF
	for r in product.recipe:
		var qty_per_unit: float = r.quantity
		if qty_per_unit <= 0.0:
			continue
		var available: float = get_ingredient_stock(r.ingredient_id)
		max_units = minf(max_units, floorf(available / qty_per_unit))
	return int(max_units) if max_units != INF else 999999


func get_ingredient_avg_cost(ingredient_id: String) -> float:
	return float(ingredient_avg_cost.get(ingredient_id, 0.0))


func add_ingredient_stock(
		ingredient_id: String,
		amount: float,
		purchase_unit_price: float
) -> void:
	if amount <= 0.0:
		return

	var old_stock := get_ingredient_stock(ingredient_id)
	var old_avg_cost := get_ingredient_avg_cost(ingredient_id)
	var new_stock := old_stock + amount

	var new_avg_cost := purchase_unit_price
	if new_stock > 0.0:
		new_avg_cost = (
			old_stock * old_avg_cost
			+ amount * purchase_unit_price
		) / new_stock

	ingredient_stock[ingredient_id] = new_stock
	ingredient_avg_cost[ingredient_id] = new_avg_cost


func consume_ingredients(product: ProductData, units_sold: int) -> void:
	if units_sold <= 0:
		return
	for r in product.recipe:
		var current: float = get_ingredient_stock(r.ingredient_id)
		ingredient_stock[r.ingredient_id] = maxf(0.0, current - r.quantity * units_sold)


func reset_to_defaults() -> void:
	reputation = SettlementConfig.INITIAL_REPUTATION
	category_slots.clear()
	total_revenue = 0.0
	total_cost = 0.0
	total_orders = 0
	total_lost_inventory = 0
	total_lost_capacity = 0
	missing_key_staff_penalty_count = 0
	daily_history.clear()
	ingredient_stock.clear()
	ingredient_avg_cost.clear()


## 结算后应用店铺层面的变化：口碑、累计统计、历史记录。
## 财务（cash）与压力（stress）在PlayerState.apply_settlement()处理。
func apply_settlement(result: SettlementResult) -> void:
	reputation = clampf(reputation + result.reputation_delta, 0.0, 100.0)
	total_revenue += result.revenue
	total_cost += result.ingredient_cost + result.staff_cost + result.rent_cost \
		+ result.utility_cost + result.waste_cost
	total_orders += result.actual_orders
	total_lost_inventory += result.lost_inventory
	total_lost_capacity += result.lost_capacity
	if result.missing_key_staff_active:
		missing_key_staff_penalty_count += 1
	daily_history.append({
		"day": result.day, "slot": result.slot, "is_open": result.is_open,
		"revenue": result.revenue, "ingredient_cost": result.ingredient_cost,
		"staff_cost": result.staff_cost, "rent_cost": result.rent_cost,
		"utility_cost": result.utility_cost,
		"waste_cost": result.waste_cost, "profit": result.profit,
		"actual_orders": result.actual_orders,
		"reputation_delta": result.reputation_delta,
		"stress_delta": result.stress_delta,
		"lost_inventory": result.lost_inventory,
		"lost_capacity": result.lost_capacity,
	})


func get_day_summary(day: int) -> Dictionary:
	var s := {
		"revenue": 0.0, "ingredient_cost": 0.0, "staff_cost": 0.0,
		"rent_cost": 0.0, "utility_cost": 0.0, "waste_cost": 0.0,
		"profit": 0.0, "actual_orders": 0,
		"reputation_delta": 0.0, "stress_delta": 0.0,
		"lost_inventory": 0, "lost_capacity": 0,
	}
	for entry in daily_history:
		if entry.get("day", -1) != day:
			continue
		s.revenue += entry.get("revenue", 0.0)
		s.ingredient_cost += entry.get("ingredient_cost", 0.0)
		s.staff_cost += entry.get("staff_cost", 0.0)
		s.rent_cost += entry.get("rent_cost", 0.0)
		s.utility_cost += entry.get("utility_cost", 0.0)
		s.waste_cost += entry.get("waste_cost", 0.0)
		s.profit += entry.get("profit", 0.0)
		s.actual_orders += entry.get("actual_orders", 0)
		s.reputation_delta += entry.get("reputation_delta", 0.0)
		s.stress_delta += entry.get("stress_delta", 0.0)
		s.lost_inventory += entry.get("lost_inventory", 0)
		s.lost_capacity += entry.get("lost_capacity", 0)
	return s


func to_save_dict() -> Dictionary:
	var slots_data: Array = []
	for slot in category_slots:
		slots_data.append(slot.to_dict())

	return {
		"version": 1,
		"id": id,
		"name": name,
		"pre_open_stage": pre_open_stage,
		"selected_region_id": selected_region_id,
		"selected_storefront_id": selected_storefront_id,
		"signed_storefront_id": signed_storefront_id,
		"is_open": is_open,
		"reputation": reputation,
		"category_slots": slots_data,
		"total_revenue": total_revenue, "total_cost": total_cost,
		"total_orders": total_orders,
		"total_lost_inventory": total_lost_inventory,
		"total_lost_capacity": total_lost_capacity,
		"missing_key_staff_penalty_count": missing_key_staff_penalty_count,
		"daily_history": daily_history,
		"ingredient_stock": ingredient_stock,
		"ingredient_avg_cost": ingredient_avg_cost,
	}


static func from_save_dict(data: Dictionary) -> Store:
	var s := Store.new()
	s.id = data.get("id", "")
	s.name = data.get("name", "")
	s.pre_open_stage = data.get(
		"pre_open_stage",
		PreOpenStage.CHARACTER_CREATION
	) as PreOpenStage

	s.selected_region_id = data.get("selected_region_id", "")
	s.selected_storefront_id = data.get("selected_storefront_id", "")
	s.signed_storefront_id = data.get("signed_storefront_id", "")
	s.is_open = data.get("is_open", false)
	s.reputation = data.get("reputation", SettlementConfig.INITIAL_REPUTATION)

	var slots_raw: Array = data.get("category_slots", [])
	for sd in slots_raw:
		s.category_slots.append(StoreCategorySlot.from_dict(sd))

	s.total_revenue = data.get("total_revenue", 0.0)
	s.total_cost = data.get("total_cost", 0.0)
	s.total_orders = data.get("total_orders", 0)
	s.total_lost_inventory = data.get("total_lost_inventory", 0)
	s.total_lost_capacity = data.get("total_lost_capacity", 0)
	s.missing_key_staff_penalty_count = data.get("missing_key_staff_penalty_count", 0)
	s.ingredient_stock = data.get("ingredient_stock", {})
	s.ingredient_avg_cost = data.get("ingredient_avg_cost", {})

	var history_raw: Array = data.get("daily_history", [])
	var history_typed: Array[Dictionary] = []
	for h in history_raw:
		history_typed.append(h)
	s.daily_history = history_typed

	return s
