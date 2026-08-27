extends Node

enum Speed { PAUSED = 0, X1 = 1, X2 = 2, X5 = 5 }

const GAME_SECONDS_PER_REAL_SECOND_AT_X1: float = 120.0
const DAY_SECONDS: float = 86400.0
const DAY_START_SECONDS: float = 8.0 * 3600.0
const DAYS_PER_WEEK: int = 7
const WEEKDAY_COUNT: int = 5
const WEEKDAY_NAMES: Array[String] = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]


signal clock_updated(hour: int, minute: int, second: int, period_label: String)
signal customer_event(product_name: String, purchased: bool, reason: String, event_game_seconds: float)
signal slot_completed(day: int, slot: String, results: Array)
signal day_completed(day: int, summary: Dictionary)
signal hour_advanced(day: int, hour: int)

var speed: int = Speed.PAUSED
var current_day: int = 1
var total_game_seconds: float = 0.0

var _simulation_active: bool = false
var _last_emitted_hour: int = -1
var _last_emitted_day: int = -1
var _connected_simulation_ids: Dictionary = {}


func _process(delta: float) -> void:
	if speed == Speed.PAUSED:
		return
	if not GameManager.player_state.is_character_created:
		return
	_advance(delta * GAME_SECONDS_PER_REAL_SECOND_AT_X1 * float(speed))


func set_speed(new_speed: int) -> void:
	speed = new_speed
	_emit_clock()


func reset() -> void:
	speed = Speed.PAUSED
	current_day = 1
	total_game_seconds = DAY_START_SECONDS
	_simulation_active = false
	_connected_simulation_ids.clear()
	_last_emitted_hour = get_current_hour_int()
	_last_emitted_day = current_day
	_emit_clock()


func get_hour_of_day() -> float:
	return fposmod(total_game_seconds, DAY_SECONDS) / 3600.0


func get_current_hour_int() -> int:
	return int(get_hour_of_day())


## current_day remains an absolute, save-compatible game day. Week rules are
## derived from it instead of introducing another persisted calendar value.
func get_day_of_week(day: int = -1) -> int:
	var resolved_day := current_day if day < 1 else day
	return posmod(resolved_day - 1, DAYS_PER_WEEK) + 1


func is_weekday(day: int = -1) -> bool:
	return get_day_of_week(day) <= WEEKDAY_COUNT


func is_weekend(day: int = -1) -> bool:
	return not is_weekday(day)


func get_weekday_name(day: int = -1) -> String:
	return WEEKDAY_NAMES[get_day_of_week(day) - 1]


func is_store_actually_operating() -> bool:
	var store: Store = GameManager.store_state
	if store == null or not store.is_open or not store.is_business_open:
		return false
	return true


func _advance(game_delta: float) -> void:
	var guard := 0
	while game_delta > 0.0001 and guard < 10000:
		guard += 1
		var day_start: float = floor(total_game_seconds / DAY_SECONDS) * DAY_SECONDS
		var hour_now: float = (total_game_seconds - day_start) / 3600.0
		var next_hour: float = floor(hour_now) + 1.0
		var boundary_abs: float = day_start + next_hour * 3600.0
		var step: float = minf(game_delta, boundary_abs - total_game_seconds)
		step = maxf(step, 0.0)

		if not _simulation_active:
			GameManager.begin_slot_simulation()
			_attach_customer_event_forwarding()
			_simulation_active = true

		var seconds_into_hour: float = total_game_seconds - (day_start + floor(hour_now) * 3600.0) + step
		GameManager.advance_slot_simulation(seconds_into_hour)

		total_game_seconds += step
		game_delta -= step

		ScheduleManager.tick()
		## 行动完成或被手动停止会暂停时间；本帧剩余的模拟步进也必须随之停止，
		## 否则可能在同一帧内误启动下一项行动。
		if speed == Speed.PAUSED:
			break

		_after_time_advance()

		if step <= 0.0001:
			break


func _after_time_advance() -> void:
	var target_hour: float = get_hour_of_day()
	var target_day: int = 1 + int(total_game_seconds / DAY_SECONDS)
	var hour_int: int = int(target_hour)

	if hour_int != _last_emitted_hour or target_day != _last_emitted_day:
		var finished_hour := _last_emitted_hour
		var finished_day := _last_emitted_day if _last_emitted_day > 0 else target_day

		var results := GameManager.finalize_slot_simulation(finished_hour, finished_day)
		_simulation_active = false
		_connected_simulation_ids.clear()
		slot_completed.emit(finished_day, "%02d:00" % maxi(finished_hour, 0), results)

		if target_day != current_day:
			var closed_day := current_day
			current_day = target_day
			var summary := GameManager.get_day_summary_all_stores(closed_day)
			day_completed.emit(closed_day, summary)

		_last_emitted_hour = hour_int
		_last_emitted_day = target_day
		hour_advanced.emit(current_day, hour_int)

	_emit_clock()


func refresh_current_store_staffing(store: Store) -> void:
	if not _simulation_active or store == null:
		return
	GameManager.refresh_active_store_staffing(store)
	_attach_customer_event_forwarding()


func _attach_customer_event_forwarding() -> void:
	var hour_start_seconds: float = floor(total_game_seconds / 3600.0) * 3600.0
	for entry in GameManager.active_simulations:
		var category_service: CategoryServiceSimulator = entry.get("service", null)
		if category_service != null:
			var service_id := category_service.get_instance_id()
			if _connected_simulation_ids.has(service_id):
				continue
			_connected_simulation_ids[service_id] = true
			category_service.customer_event.connect(func(_product_id: String, product_name: String, purchased: bool, reason: String, event_time_seconds: float) -> void:
				customer_event.emit(product_name if not product_name.is_empty() else "\u5546\u54c1", purchased, reason, hour_start_seconds + event_time_seconds))
			continue
		var sim: CustomerSimulator = entry.get("sim", null)
		if sim == null:
			continue
		var sim_id := sim.get_instance_id()
		if _connected_simulation_ids.has(sim_id):
			continue
		_connected_simulation_ids[sim_id] = true
		var product: ProductData = entry.get("product", null)
		var product_name := product.name if product != null else "\u5546\u54c1"
		sim.customer_event.connect(func(purchased: bool, reason: String, event_time_seconds: float) -> void:
			customer_event.emit(product_name, purchased, reason, hour_start_seconds + event_time_seconds))


func _emit_clock() -> void:
	var seconds_in_day: float = fposmod(total_game_seconds, DAY_SECONDS)
	var total_seconds: int = int(seconds_in_day)
	var h := (total_seconds / 3600) % 24
	var m := (total_seconds / 60) % 60
	var s := total_seconds % 60
	clock_updated.emit(h, m, s, _period_label(h))


func _period_label(hour: int) -> String:
	if hour >= 0 and hour < 5: return "深夜"
	elif hour >= 5 and hour < 9: return "清晨"
	elif hour >= 9 and hour < 12: return "上午"
	elif hour >= 12 and hour < 14: return "午间"
	elif hour >= 14 and hour < 18: return "下午"
	else: return "晚夜"


func to_save_dict() -> Dictionary:
	return {"speed": speed, "current_day": current_day, "total_game_seconds": total_game_seconds}


func apply_save_dict(data: Dictionary) -> void:
	speed = Speed.PAUSED
	current_day = int(data.get("current_day", 1))
	total_game_seconds = float(data.get("total_game_seconds", DAY_START_SECONDS))
	_simulation_active = false
	_last_emitted_hour = get_current_hour_int()
	_last_emitted_day = current_day
	_emit_clock()
