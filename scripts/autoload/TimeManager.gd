extends Node

enum Speed { PAUSED = 0, X1 = 1, X2 = 2, X5 = 5 }

const GAME_SECONDS_PER_REAL_SECOND_AT_X1: float = 120.0
const DAY_START_HOUR: int = 6

signal clock_updated(hour: int, minute: int, second: int, period_label: String)
signal customer_event(product_name: String, purchased: bool, reason: String)
signal slot_completed(day: int, slot: String, results: Array)
signal day_completed(day: int, summary: Dictionary)

var speed: int = Speed.PAUSED
var slot_elapsed_seconds: float = 0.0
var _simulation_active: bool = false

func _process(delta: float) -> void:
	if speed == Speed.PAUSED or not GameManager.store_state.is_open:
		return
	if not _simulation_active:
		_start_slot()
	_advance(delta * GAME_SECONDS_PER_REAL_SECOND_AT_X1 * float(speed))

func set_speed(new_speed: int) -> void:
	speed = new_speed
	if speed != Speed.PAUSED and GameManager.store_state.is_open and not _simulation_active:
		_start_slot()

func _start_slot() -> void:
	GameManager.begin_slot_simulation()
	for entry in GameManager.active_simulations:
		if entry.sim != null:
			entry.sim.customer_event.connect(
				func(purchased, reason): customer_event.emit(entry.product.name, purchased, reason))
	_simulation_active = true

func _current_slot_length_seconds() -> float:
	var slot := GameManager.store_state.get_current_slot()
	return float(SettlementConfig.SLOT_HOURS.get(slot, 1)) * 3600.0

func _advance(game_delta: float) -> void:
	var slot_len := _current_slot_length_seconds()
	slot_elapsed_seconds += game_delta
	GameManager.advance_slot_simulation(slot_elapsed_seconds)
	_emit_clock()

	if slot_elapsed_seconds >= slot_len:
		var overflow := slot_elapsed_seconds - slot_len
		_finish_slot()
		slot_elapsed_seconds = 0.0
		_simulation_active = false
		if overflow > 0.0 and GameManager.store_state.is_open:
			_start_slot()
			_advance(overflow)

func _finish_slot() -> void:
	var day := GameManager.store_state.current_day
	var slot := GameManager.store_state.get_current_slot()
	var was_last := GameManager.store_state.is_last_slot_of_day()

	var results := GameManager.finalize_slot_simulation()
	GameManager.advance_time_only()
	slot_completed.emit(day, slot, results)

	if was_last:
		var summary := GameManager.store_state.get_day_summary(day)
		day_completed.emit(day, summary)

func _emit_clock() -> void:
	var elapsed_in_day := _seconds_before_current_slot() + slot_elapsed_seconds
	var total_seconds: int = int(elapsed_in_day) + DAY_START_HOUR * 3600
	var h := (total_seconds / 3600) % 24
	var m := (total_seconds / 60) % 60
	var s := total_seconds % 60
	clock_updated.emit(h, m, s, _period_label(h))

func _seconds_before_current_slot() -> float:
	var total := 0.0
	for slot_name in SettlementConfig.SLOT_ORDER:
		if slot_name == GameManager.store_state.get_current_slot():
			break
		total += float(SettlementConfig.SLOT_HOURS.get(slot_name, 0)) * 3600.0
	return total

func _period_label(hour: int) -> String:
	if hour >= 5 and hour < 8: return "清晨"
	elif hour >= 8 and hour < 11: return "上午"
	elif hour >= 11 and hour < 13: return "中午"
	elif hour >= 13 and hour < 17: return "午后"
	elif hour >= 17 and hour < 19: return "傍晚"
	elif hour >= 19 and hour < 23: return "夜晚"
	else: return "深夜"
