extends Node

enum Speed { PAUSED = 0, X1 = 1, X2 = 2, X5 = 5 }

const GAME_SECONDS_PER_REAL_SECOND_AT_X1: float = 120.0
const DAY_SECONDS: float = 86400.0
const DAY_START_SECONDS: float = 8.0 * 3600.0


signal clock_updated(hour: int, minute: int, second: int, period_label: String)
signal customer_event(product_name: String, purchased: bool, reason: String)
signal slot_completed(day: int, slot: String, results: Array)
signal day_completed(day: int, summary: Dictionary)
signal hour_advanced(day: int, hour: int)

var speed: int = Speed.PAUSED
var current_day: int = 1
var total_game_seconds: float = 0.0

var _simulation_active: bool = false
var _last_emitted_hour: int = -1
var _last_emitted_day: int = -1


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
	_last_emitted_hour = get_current_hour_int()
	_last_emitted_day = current_day
	_emit_clock()


func get_hour_of_day() -> float:
	return fposmod(total_game_seconds, DAY_SECONDS) / 3600.0


func get_current_hour_int() -> int:
	return int(get_hour_of_day())


func is_store_actually_operating() -> bool:
	var store: Store = GameManager.store_state
	if store == null or not store.is_open:
		return false
	var hour := get_current_hour_int()
	for cat_slot in store.category_slots:
		if cat_slot.is_open_at_hour(hour):
			return true
	return false


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
			for entry in GameManager.active_simulations:
				if entry.sim != null:
					entry.sim.customer_event.connect(
						func(purchased, reason): customer_event.emit(entry.product.name, purchased, reason))
			_simulation_active = true

		var seconds_into_hour: float = total_game_seconds - (day_start + floor(hour_now) * 3600.0) + step
		GameManager.advance_slot_simulation(seconds_into_hour)

		total_game_seconds += step
		game_delta -= step

		ScheduleManager.tick()

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

		var results := GameManager.finalize_slot_simulation()
		_simulation_active = false
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
