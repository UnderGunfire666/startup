class_name CategoryServiceSimulator
extends RefCounted

## One arrival stream and queue per store/category/hour. Product ledgers keep
## existing SettlementResult and history consumers compatible.
var category_id := ""
var slot_duration_seconds := 3600.0
var arrival_rate_per_second := 0.0
var next_arrival_at := INF
var next_service_available_at := 0.0
var max_queue_wait_seconds := 0.0
var group_profiles: Dictionary = {}
var product_options: Array[Dictionary] = []
var product_ledgers: Dictionary = {}
var group_summary: Dictionary = {}
var lost_no_menu := 0
var lost_price_rejection := 0
var lost_capacity := 0
var lost_inventory := 0
var _legacy_shared_state: Dictionary = {"next_service_available_at": 0.0}

signal customer_event(product_id: String, product_name: String, purchased: bool, reason: String, event_time_seconds: float)

func _init(category_id_value: String = "") -> void:
	category_id = category_id_value

func setup(category_id_value: String, visitors_target: int, group_profiles_value: Dictionary, options: Array[Dictionary], queue_wait_seconds: float) -> void:
	category_id = category_id_value
	group_profiles = group_profiles_value.duplicate(true)
	product_options = options
	max_queue_wait_seconds = maxf(0.0, queue_wait_seconds)
	arrival_rate_per_second = float(maxi(0, visitors_target)) / slot_duration_seconds
	for group_id in group_profiles:
		group_summary[group_id] = {"visitors": 0, "intended_orders": 0, "actual_orders": 0, "lost_capacity": 0, "lost_inventory": 0, "lost_no_conversion": 0, "lost_price_rejection": 0, "lost_no_menu": 0}
	for option in product_options:
		var product: ProductData = option.get("product", null)
		if product == null: continue
		var ledger := CustomerSimulator.new()
		ledger.setup(0, slot_duration_seconds, 0.0, float(option.get("service_seconds", 60.0)), max_queue_wait_seconds, int(option.get("inventory_limit", 0)), product.average_price, float(option.get("unit_ingredient_cost", 0.0)), float(option.get("unit_utility_cost", 0.0)))
		product_ledgers[product.id] = ledger
	_schedule_next_arrival(0.0)

## Transitional compatibility for callers still being migrated from product
## simulators. New callers use process_next_arrival_if_due directly.
func get_shared_state() -> Dictionary:
	return _legacy_shared_state

func sync_from_state(state: Dictionary) -> void:
	next_service_available_at = float(state.get("next_service_available_at", next_service_available_at))
	_legacy_shared_state["next_service_available_at"] = next_service_available_at

func _schedule_next_arrival(from_time: float) -> void:
	if arrival_rate_per_second <= 0.0:
		next_arrival_at = INF
		return
	next_arrival_at = from_time + (-log(1.0 - randf()) / arrival_rate_per_second)

func process_next_arrival_if_due(elapsed_seconds: float) -> bool:
	if next_arrival_at > elapsed_seconds or next_arrival_at > slot_duration_seconds: return false
	_process_one_arrival()
	_schedule_next_arrival(next_arrival_at)
	return true

func _process_one_arrival() -> void:
	var group_id := _pick_group_id()
	var summary: Dictionary = group_summary.get(group_id, {})
	if not summary.is_empty(): summary["visitors"] = int(summary.get("visitors", 0)) + 1
	var option := _pick_product_option(group_id)
	if option.is_empty():
		lost_no_menu += 1
		if not summary.is_empty(): summary["lost_no_menu"] = int(summary.get("lost_no_menu", 0)) + 1
		customer_event.emit("", "", false, CustomerSimulator.get_event_reason("no_matching_menu"), next_arrival_at)
		return
	var product: ProductData = option.get("product", null)
	var ledger: CustomerSimulator = product_ledgers.get(product.id, null)
	if product == null or ledger == null: return
	var profile: Dictionary = option.get("profile", {})
	var price_rejection := float(profile.get("price_rejection_rate_by_group", {}).get(group_id, 0.0))
	if price_rejection > 0.0 and randf() < price_rejection:
		lost_price_rejection += 1
		ledger.rejected_price_count += 1
		if not summary.is_empty(): summary["lost_price_rejection"] = int(summary.get("lost_price_rejection", 0)) + 1
		customer_event.emit(product.id, product.name, false, CustomerSimulator.get_event_reason("price_rejected"), next_arrival_at)
		return
	if randf() >= float(group_profiles.get(group_id, {}).get("conversion_rate", 0.0)):
		if not summary.is_empty(): summary["lost_no_conversion"] = int(summary.get("lost_no_conversion", 0)) + 1
		customer_event.emit(product.id, product.name, false, CustomerSimulator.get_event_reason("no_conversion"), next_arrival_at)
		return
	if not summary.is_empty(): summary["intended_orders"] = int(summary.get("intended_orders", 0)) + 1
	var service_start := maxf(next_arrival_at, next_service_available_at)
	var wait := service_start - next_arrival_at
	if wait > max_queue_wait_seconds:
		lost_capacity += 1
		ledger.rejected_capacity_count += 1
		if not summary.is_empty(): summary["lost_capacity"] = int(summary.get("lost_capacity", 0)) + 1
		customer_event.emit(product.id, product.name, false, CustomerSimulator.get_event_reason("queue_too_long"), next_arrival_at)
		return
	var reserve: Callable = option.get("reserve_ingredients", Callable())
	if not reserve.is_valid() or not bool(reserve.call()):
		lost_inventory += 1
		ledger.rejected_inventory_count += 1
		if not summary.is_empty(): summary["lost_inventory"] = int(summary.get("lost_inventory", 0)) + 1
		customer_event.emit(product.id, product.name, false, CustomerSimulator.get_event_reason("out_of_ingredients"), next_arrival_at)
		return
	var service_seconds := float(option.get("service_seconds", 60.0))
	next_service_available_at = service_start + service_seconds
	ledger.visitors_so_far += 1
	ledger.converted_count += 1
	ledger.actual_orders += 1
	ledger.total_wait_seconds += wait
	ledger.max_wait_seconds = maxf(ledger.max_wait_seconds, wait)
	ledger.revenue += product.average_price
	ledger.ingredient_cost += float(option.get("unit_ingredient_cost", 0.0))
	ledger.utility_cost += float(option.get("unit_utility_cost", 0.0))
	if not summary.is_empty(): summary["actual_orders"] = int(summary.get("actual_orders", 0)) + 1
	customer_event.emit(product.id, product.name, true, "", next_service_available_at)

func _pick_group_id() -> String:
	var total := 0.0
	for value in group_profiles.values(): total += maxf(0.0, float(value.get("visitors", 0)))
	if total <= 0.0: return str(group_profiles.keys()[0]) if not group_profiles.is_empty() else ""
	var roll := randf() * total
	for group_id in group_profiles:
		roll -= maxf(0.0, float(group_profiles[group_id].get("visitors", 0)))
		if roll <= 0.0: return str(group_id)
	return str(group_profiles.keys()[0])

func _pick_product_option(group_id: String) -> Dictionary:
	var total := 0.0
	var weights: Array[float] = []
	for option in product_options:
		var profile: Dictionary = option.get("profile", {})
		var weight := maxf(0.0, float(profile.get("weight_by_group", {}).get(group_id, 0.0)))
		weights.append(weight)
		total += weight
	if total <= 0.0001: return {}
	var roll := randf() * total
	for index in product_options.size():
		roll -= weights[index]
		if roll <= 0.0: return product_options[index]
	return product_options.back()
