class_name CustomerSimulator
extends RefCounted

var next_arrival_at: float = 0.0
var slot_duration_seconds: float
var arrival_rate_per_second: float
var conversion_rate: float
var inventory_limit: int
var service_time_seconds: float
var max_queue_wait_seconds: float
var next_service_available_at: float = 0.0
var unit_price: float
var unit_ingredient_cost: float
var unit_utility_cost: float
var inventory_reserver: Callable = Callable()
var visitors_so_far: int = 0
var converted_count: int = 0
var actual_orders: int = 0
var rejected_capacity_count: int = 0
var rejected_inventory_count: int = 0
var rejected_queue_wait_count: int = 0
var rejected_slot_end_count: int = 0
var total_wait_seconds: float = 0.0
var max_wait_seconds: float = 0.0
var revenue: float = 0.0
var ingredient_cost: float = 0.0
var utility_cost: float = 0.0

signal customer_event(purchased: bool, reason: String, event_time_seconds: float)

func setup(visitors_target: int, slot_seconds: float, conv_rate: float, service_seconds: float, max_wait_seconds_value: float, inv_limit: int, price: float, ing_cost: float, util_cost: float, reserver: Callable = Callable()) -> void:
	slot_duration_seconds = slot_seconds
	arrival_rate_per_second = float(visitors_target) / maxf(slot_seconds, 1.0)
	conversion_rate = conv_rate
	service_time_seconds = maxf(1.0, service_seconds)
	max_queue_wait_seconds = maxf(0.0, max_wait_seconds_value)
	inventory_limit = inv_limit
	unit_price = price
	unit_ingredient_cost = ing_cost
	unit_utility_cost = util_cost
	inventory_reserver = reserver
	_schedule_next_arrival(0.0)

func _schedule_next_arrival(from_time: float) -> void:
	if arrival_rate_per_second <= 0.0:
		next_arrival_at = INF
		return
	var u := randf()
	next_arrival_at = from_time + (-log(1.0 - u) / arrival_rate_per_second)

func advance(elapsed_seconds: float) -> void:
	while process_next_arrival_if_due(elapsed_seconds):
		pass

func process_next_arrival_if_due(elapsed_seconds: float) -> bool:
	if next_arrival_at > elapsed_seconds or next_arrival_at > slot_duration_seconds:
		return false
	_process_one_arrival()
	_schedule_next_arrival(next_arrival_at)
	return true

func process_arrival_at(arrival_at: float) -> void:
	next_arrival_at = clampf(arrival_at, 0.0, slot_duration_seconds)
	_process_one_arrival()

func _process_one_arrival() -> void:
	visitors_so_far += 1
	if randf() >= conversion_rate:
		customer_event.emit(false, "\u770b\u4e86\u770b\u6ca1\u4e0b\u5355", next_arrival_at)
		return
	converted_count += 1
	var service_start := maxf(next_arrival_at, next_service_available_at)
	var wait_seconds := service_start - next_arrival_at
	var service_finish := service_start + service_time_seconds
	if wait_seconds > max_queue_wait_seconds:
		rejected_capacity_count += 1
		rejected_queue_wait_count += 1
		customer_event.emit(false, "\u6392\u961f\u592a\u957f\u653e\u5f03\u4e86", next_arrival_at)
		return
	if inventory_reserver.is_valid():
		if not bool(inventory_reserver.call()):
			rejected_inventory_count += 1
			customer_event.emit(false, "\u539f\u6750\u6599\u4e0d\u8db3", next_arrival_at)
			return
	elif actual_orders >= inventory_limit:
		rejected_inventory_count += 1
		customer_event.emit(false, "\u539f\u6750\u6599\u4e0d\u8db3", next_arrival_at)
		return
	next_service_available_at = service_finish
	total_wait_seconds += wait_seconds
	max_wait_seconds = maxf(max_wait_seconds, wait_seconds)
	actual_orders += 1
	revenue += unit_price
	ingredient_cost += unit_ingredient_cost
	utility_cost += unit_utility_cost
	customer_event.emit(true, "", service_finish)

func get_debug_summary() -> Dictionary:
	return {"accepted": actual_orders, "rejected_queue_wait": rejected_queue_wait_count, "rejected_slot_end": rejected_slot_end_count, "rejected_inventory": rejected_inventory_count, "average_wait_seconds": total_wait_seconds / float(actual_orders) if actual_orders > 0 else 0.0, "max_wait_seconds": max_wait_seconds, "service_time_seconds": service_time_seconds, "next_service_available_at": next_service_available_at}
