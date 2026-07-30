class_name StoreState
extends RefCounted

var cash: float = SettlementConfig.INITIAL_CASH
var inventory_units: int = SettlementConfig.INITIAL_INVENTORY
var inventory_capacity: int = 200
var reputation: float = SettlementConfig.INITIAL_REPUTATION
var stress: float = SettlementConfig.INITIAL_STRESS
var current_day: int = 1
var current_slot_index: int = 0

var selected_region_id: String = ""
var selected_storefront_id: String = ""
var owner_present: bool = false

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

func get_current_slot() -> String:
	return SettlementConfig.SLOT_ORDER[current_slot_index]

func advance_slot() -> void:
	current_slot_index += 1
	if current_slot_index >= SettlementConfig.SLOT_ORDER.size():
		current_slot_index = 0
		current_day += 1

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
	cash = SettlementConfig.INITIAL_CASH
	inventory_units = SettlementConfig.INITIAL_INVENTORY
	reputation = SettlementConfig.INITIAL_REPUTATION
	stress = SettlementConfig.INITIAL_STRESS
	current_day = 1
	current_slot_index = 0
	category_slots.clear()
	total_revenue = 0.0
	total_cost = 0.0
	total_orders = 0
	total_lost_inventory = 0
	total_lost_capacity = 0
	missing_key_staff_penalty_count = 0
	daily_history.clear()
	ingredient_stock.clear()
	ingredient_stock.clear()
	ingredient_avg_cost.clear()

func apply_settlement(result: SettlementResult) -> void:
	cash += result.profit
	reputation = clampf(reputation + result.reputation_delta, 0.0, 100.0)
	stress = clampf(stress + result.stress_delta, 0.0, 100.0)
	total_revenue += result.revenue
	total_cost += result.ingredient_cost + result.staff_cost + result.rent_cost + result.waste_cost
	total_orders += result.actual_orders
	total_lost_inventory += result.lost_inventory
	total_lost_capacity += result.lost_capacity
	if result.missing_key_staff_active:
		missing_key_staff_penalty_count += 1
	daily_history.append({
		"day": result.day, "slot": result.slot, "is_open": result.is_open,
		"revenue": result.revenue, "ingredient_cost": result.ingredient_cost,
		"staff_cost": result.staff_cost, "rent_cost": result.rent_cost,
		"waste_cost": result.waste_cost, "profit": result.profit,
		"actual_orders": result.actual_orders,
		"reputation_delta": result.reputation_delta,
		"lost_inventory": result.lost_inventory,
		"lost_capacity": result.lost_capacity,
	})

# ── 存档序列化 ──────────────────────────────────────────
func to_save_dict() -> Dictionary:
	var slots_data: Array = []
	for slot in category_slots:
		slots_data.append(slot.to_dict())
	return {
		"version": 2,
		"cash": cash, "inventory_units": inventory_units,
		"inventory_capacity": inventory_capacity,
		"reputation": reputation, "stress": stress,
		"current_day": current_day, "current_slot_index": current_slot_index,
		"selected_region_id": selected_region_id,
		"selected_storefront_id": selected_storefront_id,
		"owner_present": owner_present,
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

static func from_save_dict(data: Dictionary) -> StoreState:
	var s := StoreState.new()
	s.cash = data.get("cash", SettlementConfig.INITIAL_CASH)
	s.inventory_units = data.get("inventory_units", SettlementConfig.INITIAL_INVENTORY)
	s.inventory_capacity = data.get("inventory_capacity", 200)
	s.reputation = data.get("reputation", SettlementConfig.INITIAL_REPUTATION)
	s.stress = data.get("stress", SettlementConfig.INITIAL_STRESS)
	s.current_day = data.get("current_day", 1)
	s.current_slot_index = data.get("current_slot_index", 0)
	s.selected_region_id = data.get("selected_region_id", "")
	s.selected_storefront_id = data.get("selected_storefront_id", "")
	s.owner_present = data.get("owner_present", false)
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
