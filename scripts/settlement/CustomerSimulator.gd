class_name CustomerSimulator
extends RefCounted

const CUSTOMER_EVENT_REASON_VARIANTS := {
	"no_matching_menu": [
		"顾客看完菜单，在想找的那一类前停住了脚步",
		"顾客翻来覆去看了两遍菜单，最后还是没找到能点的那一项",
	],
	"price_rejected": [
		"顾客看了眼价格，把想说的话咽了回去",
		"顾客算了算手里的预算，朝你抱歉地笑了笑",
	],
	"no_conversion": [
		"顾客犹豫片刻，还是把位置让给了下一位",
		"顾客在柜台前停了一会儿，最终带着“下次再来”转身离开",
	],
	"queue_too_long": [
		"队伍迟迟没动，顾客看了看时间后离开了",
		"等待的目光从后场移向门口，顾客终究没能继续等下去",
	],
	"out_of_ingredients": [
		"做到这一步才发现原料已经见底，只能向顾客致歉",
		"备料盒里最后一点存货也用完了，这一单只能遗憾作罢",
	],
}

static func get_event_reason(reason_id: String) -> String:
	var variants: Array = CUSTOMER_EVENT_REASON_VARIANTS.get(reason_id, [])
	return str(variants.pick_random()) if not variants.is_empty() else reason_id

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
var rejected_price_count: int = 0
var rejected_queue_wait_count: int = 0
var rejected_slot_end_count: int = 0
var total_wait_seconds: float = 0.0
var max_wait_seconds: float = 0.0
var revenue: float = 0.0
var ingredient_cost: float = 0.0
var utility_cost: float = 0.0
var group_profiles: Dictionary = {}
var group_summary: Dictionary = {}
## Product simulators in the same category may share this queue state.
var shared_service_state: Dictionary = {}

signal customer_event(purchased: bool, reason: String, event_time_seconds: float)

func setup(visitors_target: int, slot_seconds: float, conv_rate: float, service_seconds: float, max_wait_seconds_value: float, inv_limit: int, price: float, ing_cost: float, util_cost: float, reserver: Callable = Callable(), group_profiles_value: Dictionary = {}, shared_service_state_value: Dictionary = {}) -> void:
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
	group_profiles = group_profiles_value.duplicate(true)
	group_summary.clear()
	for group_id in group_profiles:
		group_summary[group_id] = {"visitors": 0, "intended_orders": 0, "actual_orders": 0, "lost_capacity": 0, "lost_inventory": 0, "lost_no_conversion": 0, "lost_price_rejection": 0}
	shared_service_state = shared_service_state_value
	if shared_service_state.is_empty():
		shared_service_state = {"next_service_available_at": 0.0}
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
	var group_id := _pick_group_id()
	var summary: Dictionary = group_summary.get(group_id, {})
	visitors_so_far += 1
	if not summary.is_empty():
		summary["visitors"] = int(summary.get("visitors", 0)) + 1
	var group_conversion := float(group_profiles.get(group_id, {}).get("conversion_rate", conversion_rate))
	var price_rejection := float(group_profiles.get(group_id, {}).get("price_rejection_rate", 0.0))
	if price_rejection > 0.0 and randf() < price_rejection:
		rejected_price_count += 1
		if not summary.is_empty():
			summary["lost_price_rejection"] = int(summary.get("lost_price_rejection", 0)) + 1
		customer_event.emit(false, get_event_reason("price_rejected"), next_arrival_at)
		return
	if randf() >= group_conversion:
		if not summary.is_empty():
			summary["lost_no_conversion"] = int(summary.get("lost_no_conversion", 0)) + 1
		customer_event.emit(false, get_event_reason("no_conversion"), next_arrival_at)
		return
	converted_count += 1
	if not summary.is_empty():
		summary["intended_orders"] = int(summary.get("intended_orders", 0)) + 1
	var shared_next := float(shared_service_state.get("next_service_available_at", next_service_available_at))
	var service_start := maxf(next_arrival_at, shared_next)
	var wait_seconds := service_start - next_arrival_at
	var service_finish := service_start + service_time_seconds
	if wait_seconds > max_queue_wait_seconds:
		rejected_capacity_count += 1
		rejected_queue_wait_count += 1
		if not summary.is_empty():
			summary["lost_capacity"] = int(summary.get("lost_capacity", 0)) + 1
		customer_event.emit(false, get_event_reason("queue_too_long"), next_arrival_at)
		return
	if inventory_reserver.is_valid():
		if not bool(inventory_reserver.call()):
			rejected_inventory_count += 1
			if not summary.is_empty():
				summary["lost_inventory"] = int(summary.get("lost_inventory", 0)) + 1
			customer_event.emit(false, get_event_reason("out_of_ingredients"), next_arrival_at)
			return
	elif actual_orders >= inventory_limit:
		rejected_inventory_count += 1
		if not summary.is_empty():
			summary["lost_inventory"] = int(summary.get("lost_inventory", 0)) + 1
		customer_event.emit(false, get_event_reason("out_of_ingredients"), next_arrival_at)
		return
	next_service_available_at = service_finish
	shared_service_state["next_service_available_at"] = service_finish
	total_wait_seconds += wait_seconds
	max_wait_seconds = maxf(max_wait_seconds, wait_seconds)
	actual_orders += 1
	if not summary.is_empty():
		summary["actual_orders"] = int(summary.get("actual_orders", 0)) + 1
	revenue += unit_price
	ingredient_cost += unit_ingredient_cost
	utility_cost += unit_utility_cost
	customer_event.emit(true, "", service_finish)


func _pick_group_id() -> String:
	if group_profiles.is_empty():
		return ""
	var total := 0.0
	for profile in group_profiles.values():
		total += maxf(0.0, float(profile.get("visitors", 0)))
	if total <= 0.0:
		return str(group_profiles.keys()[0])
	var pick := randf() * total
	for group_id in group_profiles:
		pick -= maxf(0.0, float(group_profiles[group_id].get("visitors", 0)))
		if pick <= 0.0:
			return str(group_id)
	return str(group_profiles.keys()[0])

func get_debug_summary() -> Dictionary:
	return {"accepted": actual_orders, "rejected_queue_wait": rejected_queue_wait_count, "rejected_slot_end": rejected_slot_end_count, "rejected_inventory": rejected_inventory_count, "average_wait_seconds": total_wait_seconds / float(actual_orders) if actual_orders > 0 else 0.0, "max_wait_seconds": max_wait_seconds, "service_time_seconds": service_time_seconds, "next_service_available_at": next_service_available_at}
