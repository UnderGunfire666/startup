class_name CustomerSimulator
extends RefCounted

var next_arrival_at: float = 0.0
var slot_duration_seconds: float
var arrival_rate_per_second: float
var conversion_rate: float
var slot_capacity: int
var inventory_limit: int
var unit_price: float
var unit_ingredient_cost: float
var unit_utility_cost: float

var visitors_so_far: int = 0
var converted_count: int = 0
var actual_orders: int = 0
var rejected_capacity_count: int = 0
var rejected_inventory_count: int = 0
var revenue: float = 0.0
var ingredient_cost: float = 0.0
var utility_cost: float = 0.0

signal customer_event(purchased: bool, reason: String)

func setup(visitors_target: int, slot_seconds: float, conv_rate: float,
		capacity: int, inv_limit: int, price: float,
		ing_cost: float, util_cost: float) -> void:
	slot_duration_seconds = slot_seconds
	arrival_rate_per_second = float(visitors_target) / maxf(slot_seconds, 1.0)
	conversion_rate = conv_rate
	slot_capacity = capacity
	inventory_limit = inv_limit
	unit_price = price
	unit_ingredient_cost = ing_cost
	unit_utility_cost = util_cost
	_schedule_next_arrival(0.0)

func _schedule_next_arrival(from_time: float) -> void:
	if arrival_rate_per_second <= 0.0:
		next_arrival_at = INF
		return
	var u := randf()
	next_arrival_at = from_time + (-log(1.0 - u) / arrival_rate_per_second)

## elapsed_seconds：距本时段开始的累计秒数
func advance(elapsed_seconds: float) -> void:
	while next_arrival_at <= elapsed_seconds and next_arrival_at <= slot_duration_seconds:
		_process_one_arrival()
		_schedule_next_arrival(next_arrival_at)

func _process_one_arrival() -> void:
	visitors_so_far += 1
	if randf() >= conversion_rate:
		customer_event.emit(false, "看了看没下单")
		return

	converted_count += 1
	if actual_orders >= slot_capacity:
		rejected_capacity_count += 1
		customer_event.emit(false, "排队太长放弃了")
		return
	if actual_orders >= inventory_limit:
		rejected_inventory_count += 1
		customer_event.emit(false, "商品卖光了")
		return

	actual_orders += 1
	revenue += unit_price
	ingredient_cost += unit_ingredient_cost
	utility_cost += unit_utility_cost
	customer_event.emit(true, "")
