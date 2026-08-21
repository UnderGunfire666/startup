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
## inventory_units/inventory_capacity(库存实际记在StoreProductConfig)、
## selected_region_id(旧RegionData体系，选址现完全依赖StorefrontData.city_region_id)。
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

var selected_storefront_id: String = ""
var signed_storefront_id: String = ""
var is_open: bool = false
var is_business_open: bool = false
var business_hour_ranges: Array[Vector2i] = [Vector2i(9, 21)]

var reputation: float = SettlementConfig.INITIAL_REPUTATION
var awareness_by_block: Dictionary = {}

var category_slots: Array[StoreCategorySlot] = []
var equipment: Array[StoreEquipment] = []
var furniture_layout: Array[StoreFurniturePlacement] = []
var facade_layout: Array[StoreFacadePlacement] = []
var facade_layout_initialized: bool = false
var layout_grid_version: int = 2
var employees: Array[StoreEmployee] = []

var ingredient_stock: Dictionary = {}
var ingredient_avg_cost: Dictionary = {}

var total_revenue: float = 0.0
var total_cost: float = 0.0
var total_orders: int = 0
var total_lost_inventory: int = 0
var total_lost_capacity: int = 0
var daily_history: Array[Dictionary] = []
var purchase_history: Array[Dictionary] = []


func get_used_area() -> float:
	return 0.0


func get_available_area(storefront: StorefrontData) -> float:
	if storefront == null:
		return 0.0
	return storefront.area - get_used_area()

func get_equipment_count(equipment_id: String) -> int:
	var count := 0
	for item in equipment:
		if item.equipment_id == equipment_id:
			count += 1
	return count

func has_equipment(equipment_id: String) -> bool:
	return get_equipment_count(equipment_id) > 0

func get_employee(candidate_id: String) -> StoreEmployee:
	for employee in employees:
		if employee.candidate_id == candidate_id:
			return employee
	return null

func has_employee_with_skill(skill: String, hour: int = -1) -> bool:
	for employee in employees:
		if employee.has_skill(skill) and (hour < 0 or employee.is_scheduled_at_hour(hour)):
			return true
	return false

func get_equipment_used_area(data: Array[EquipmentData]) -> float:
	var total := 0.0
	for item in equipment:
		for definition in data:
			if definition.id == item.equipment_id:
				total += definition.area
				break
	return total


func has_category(category_id: String) -> bool:
	for slot in category_slots:
		if slot.category_id == category_id:
			return true
	return false

func is_planned_open_at_hour(hour: int) -> bool:
	for hour_range in business_hour_ranges:
		if hour >= hour_range.x and hour < hour_range.y:
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


func get_max_produceable_by_ingredients(product: ProductData, consumption_multiplier: float = 1.0) -> int:
	if product.recipe.is_empty():
		return 999999
	var max_units: float = INF
	for r in product.recipe:
		var qty_per_unit: float = r.quantity * maxf(1.0, consumption_multiplier)
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


func consume_ingredients(
		product: ProductData,
		units_sold: int,
		consumption_multiplier: float = 1.0
) -> Dictionary:
	var preparation_waste: Dictionary = {}
	if units_sold <= 0:
		return preparation_waste
	for r in product.recipe:
		var current: float = get_ingredient_stock(r.ingredient_id)
		var normal_used: float = r.quantity * units_sold
		var actual_used: float = normal_used * maxf(1.0, consumption_multiplier)
		ingredient_stock[r.ingredient_id] = maxf(0.0, current - actual_used)
		var waste := maxf(0.0, actual_used - normal_used)
		if waste > 0.0:
			preparation_waste[r.ingredient_id] = waste
	return preparation_waste


func try_reserve_product_ingredients(
		product: ProductData,
		units: int = 1,
		consumption_multiplier: float = 1.0
) -> bool:
	if units <= 0 or product.recipe.is_empty():
		return true
	var multiplier := maxf(1.0, consumption_multiplier)
	## 先检查完整配方，确认全部满足后才扣除，避免半扣库存。
	for recipe_item in product.recipe:
		var ingredient_id: String = str(recipe_item.get("ingredient_id", ""))
		var required: float = float(recipe_item.get("quantity", 0.0)) * units * multiplier
		if get_ingredient_stock(ingredient_id) + 0.0001 < required:
			return false
	for recipe_item in product.recipe:
		var ingredient_id: String = str(recipe_item.get("ingredient_id", ""))
		var required: float = float(recipe_item.get("quantity", 0.0)) * units * multiplier
		ingredient_stock[ingredient_id] = maxf(0.0, get_ingredient_stock(ingredient_id) - required)
	return true


func get_preparation_waste_for_orders(
		product: ProductData,
		units: int,
		consumption_multiplier: float
) -> Dictionary:
	var waste: Dictionary = {}
	if units <= 0:
		return waste
	var multiplier := maxf(1.0, consumption_multiplier)
	for recipe_item in product.recipe:
		var ingredient_id: String = str(recipe_item.get("ingredient_id", ""))
		var amount: float = float(recipe_item.get("quantity", 0.0)) * units * (multiplier - 1.0)
		if amount > 0.0:
			waste[ingredient_id] = amount
	return waste


func apply_ingredient_spoilage(ratios_by_ingredient: Dictionary) -> Dictionary:
	var spoiled: Dictionary = {}
	for ingredient_id in ingredient_stock.keys():
		var safe_ratio := clampf(float(ratios_by_ingredient.get(str(ingredient_id), 0.0)), 0.0, 1.0)
		if safe_ratio <= 0.0:
			continue
		var current := get_ingredient_stock(str(ingredient_id))
		var amount := current * safe_ratio
		if amount <= 0.0:
			continue
		ingredient_stock[ingredient_id] = maxf(0.0, current - amount)
		spoiled[ingredient_id] = amount
	return spoiled


func reset_to_defaults() -> void:
	reputation = SettlementConfig.INITIAL_REPUTATION
	category_slots.clear()
	equipment.clear()
	furniture_layout.clear()
	facade_layout.clear()
	facade_layout_initialized = false
	employees.clear()
	total_revenue = 0.0
	total_cost = 0.0
	total_orders = 0
	total_lost_inventory = 0
	total_lost_capacity = 0
	daily_history.clear()
	ingredient_stock.clear()
	ingredient_avg_cost.clear()


## 结算后应用店铺层面的变化：口碑、累计统计、历史记录。
## 财务（cash）与压力（stress）在PlayerState.apply_settlement()处理。
func apply_settlement(result: SettlementResult) -> void:
	reputation = clampf(reputation + result.reputation_delta, 0.0, 100.0)
	total_revenue += result.revenue
	total_cost += result.ingredient_cost + result.staff_cost + result.rent_cost + result.utility_cost
	total_orders += result.actual_orders
	total_lost_inventory += result.lost_inventory
	total_lost_capacity += result.lost_capacity
	daily_history.append({
		"day": result.day, "slot": result.slot, "is_open": result.is_open,
		"is_store_overhead": result.is_store_overhead,
		"revenue": result.revenue, "ingredient_cost": result.ingredient_cost,
		"staff_cost": result.staff_cost, "rent_cost": result.rent_cost,
		"utility_cost": result.utility_cost,
		"waste_cost": 0.0, "profit": result.profit,
		"preparation_waste_ingredients": result.preparation_waste_ingredients.duplicate(),
		"spoilage_ingredients": result.spoilage_ingredients.duplicate(),
		"actual_orders": result.actual_orders,
		"reputation_delta": result.reputation_delta,
		"stress_delta": result.stress_delta,
		"lost_inventory": result.lost_inventory,
		"lost_capacity": result.lost_capacity,
		"lost_no_entry": result.lost_no_entry,
		"lost_no_conversion": result.lost_no_conversion,
		"visitors": result.visitors,
		"theoretical_orders": result.theoretical_orders,
		"conversion_rate": result.conversion_rate,
		"average_queue_wait_seconds": result.average_queue_wait_seconds,
		"max_queue_wait_seconds": result.max_queue_wait_seconds,
		"service_time_seconds": result.service_time_seconds,
		"staffing_power": result.staffing_power,
		"slot_capacity": result.slot_capacity,
		"inventory_limit": result.inventory_limit,
		"not_open_reason": result.not_open_reason,
	})


func get_day_summary(day: int) -> Dictionary:
	var s := {
		"revenue": 0.0, "ingredient_cost": 0.0, "staff_cost": 0.0,
		"rent_cost": 0.0, "utility_cost": 0.0,
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
	var equipment_data: Array = []
	for item in equipment:
		equipment_data.append(item.to_dict())
	var employee_data: Array = []
	for employee in employees:
		employee_data.append(employee.to_dict())
	var furniture_data: Array = []
	for placement in furniture_layout:
		furniture_data.append(placement.to_dict())
	var facade_data: Array = []
	for placement in facade_layout:
		facade_data.append(placement.to_dict())
	var business_ranges_data: Array = []
	for hour_range in business_hour_ranges:
		business_ranges_data.append([hour_range.x, hour_range.y])

	return {
		"version": 1,
		"id": id,
		"name": name,
		"pre_open_stage": pre_open_stage,
		"selected_storefront_id": selected_storefront_id,
		"signed_storefront_id": signed_storefront_id,
		"is_open": is_open,
		"is_business_open": is_business_open,
		"business_hour_ranges": business_ranges_data,
		"reputation": reputation,
		"awareness_by_block": awareness_by_block,
		"category_slots": slots_data,
		"equipment": equipment_data,
		"furniture_layout": furniture_data,
		"facade_layout": facade_data,
		"facade_layout_initialized": facade_layout_initialized,
		"layout_grid_version": layout_grid_version,
		"employees": employee_data,
		"total_revenue": total_revenue, "total_cost": total_cost,
		"total_orders": total_orders,
		"total_lost_inventory": total_lost_inventory,
		"total_lost_capacity": total_lost_capacity,
		"daily_history": daily_history,
		"purchase_history": purchase_history,
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

	s.selected_storefront_id = data.get("selected_storefront_id", "")
	s.signed_storefront_id = data.get("signed_storefront_id", "")
	s.is_open = data.get("is_open", false)
	s.is_business_open = data.get("is_business_open", false)
	var business_ranges_raw: Array = data.get("business_hour_ranges", [[9, 21]])
	for raw_range in business_ranges_raw:
		if raw_range is Array and raw_range.size() >= 2:
			s.business_hour_ranges.append(Vector2i(int(raw_range[0]), int(raw_range[1])))
	if s.business_hour_ranges.is_empty():
		s.business_hour_ranges.append(Vector2i(9, 21))
	s.reputation = data.get("reputation", SettlementConfig.INITIAL_REPUTATION)
	s.awareness_by_block = data.get("awareness_by_block", {})

	var slots_raw: Array = data.get("category_slots", [])
	for sd in slots_raw:
		s.category_slots.append(StoreCategorySlot.from_dict(sd))
	var equipment_raw: Array = data.get("equipment", [])
	for item in equipment_raw:
		var equipment_item := StoreEquipment.from_dict(item)
		if equipment_item.instance_id.is_empty():
			equipment_item.instance_id = "legacy_equipment_%d" % s.equipment.size()
		s.equipment.append(equipment_item)
	var furniture_raw: Array = data.get("furniture_layout", [])
	for placement_data in furniture_raw:
		if placement_data is Dictionary:
			s.furniture_layout.append(StoreFurniturePlacement.from_dict(placement_data))
	var facade_raw: Array = data.get("facade_layout", [])
	for placement_data in facade_raw:
		if placement_data is Dictionary:
			var facade_placement := StoreFacadePlacement.from_dict(placement_data)
			if FacadeLayoutValidator.is_known_type(facade_placement.type):
				s.facade_layout.append(facade_placement)
	s.facade_layout_initialized = bool(data.get("facade_layout_initialized", not facade_raw.is_empty()))
	s.layout_grid_version = int(data.get("layout_grid_version", 1))
	var employees_raw: Array = data.get("employees", [])
	for employee_data in employees_raw:
		s.employees.append(StoreEmployee.from_dict(employee_data))

	s.total_revenue = data.get("total_revenue", 0.0)
	s.total_cost = data.get("total_cost", 0.0)
	s.total_orders = data.get("total_orders", 0)
	s.total_lost_inventory = data.get("total_lost_inventory", 0)
	s.total_lost_capacity = data.get("total_lost_capacity", 0)
	s.ingredient_stock = data.get("ingredient_stock", {})
	s.ingredient_avg_cost = data.get("ingredient_avg_cost", {})

	var history_raw: Array = data.get("daily_history", [])
	var history_typed: Array[Dictionary] = []
	for h in history_raw:
		history_typed.append(h)
	s.daily_history = history_typed
	var purchases_raw: Array = data.get("purchase_history", [])
	var purchases_typed: Array[Dictionary] = []
	for purchase in purchases_raw:
		if purchase is Dictionary:
			purchases_typed.append(purchase)
	s.purchase_history = purchases_typed

	return s
