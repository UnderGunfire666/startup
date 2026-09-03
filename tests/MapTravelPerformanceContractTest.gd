extends Node

const FRAME_COUNT := 1800
const FRAMES_PER_BATCH := 60
const DESTINATION_STOREFRONT_ID := "sf_industrial_canteen"
const TEST_SEED := 424242

var passed := 0
var failed := 0
var _map_panel: Control
var _map_canvas: CityMapCanvas
var _travel_layer: CityMapTravelLayer


func _ready() -> void:
	print("========== Map Travel Performance Contract Test ==========")
	await _mount_map_and_start_travel()
	await _test_thirty_second_equivalent_rendering()
	_test_clock_signal_throttle()
	_test_speed_equivalence()
	_cleanup()
	print("========== Map Travel Performance: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _mount_map_and_start_travel() -> void:
	seed(TEST_SEED)
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var created := GameManager.create_character({
		"player_name": "Performance Tester", "gender": "female", "age": 28,
		"difficulty_id": "normal", "preset_id": "", "home_id": "home_old_community", "trait_ids": [],
	})
	_expect(bool(created.get("success", false)), "performance character creation succeeds")
	_map_panel = preload("res://scenes/map/CityMapPanel.tscn").instantiate()
	add_child(_map_panel)
	_map_canvas = _map_panel.get_node("HBoxContainer/MapScrollContainer/MapCanvas") as CityMapCanvas
	_travel_layer = _map_canvas.get_node("TravelLayer") as CityMapTravelLayer
	await get_tree().process_frame
	await get_tree().process_frame
	var grid := GameManager.get_navigation_grid()
	var entrance: Dictionary = grid.storefront_entrances.get(DESTINATION_STOREFRONT_ID, {})
	var started := ScheduleManager.start_travel_to_cell(
		str(entrance.get("block_id", "")),
		entrance.get("cell", Vector2i(-1, -1)),
		MovementConfig.WALK,
		DESTINATION_STOREFRONT_ID
	)
	_expect(bool(started.get("can", false)), "long grid travel starts for performance sampling")
	TimeManager.set_speed(TimeManager.Speed.PAUSED)
	_travel_layer.refresh_from_state()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_thirty_second_equivalent_rendering() -> void:
	_map_canvas.reset_debug_draw_count()
	_travel_layer.reset_debug_counters(true)
	GameManager.get_navigation_grid()
	GameManager.reset_debug_navigation_grid_build_count()
	var node_count_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var batch_microseconds: Array[float] = []
	for batch in range(FRAME_COUNT / FRAMES_PER_BATCH):
		var started_usec := Time.get_ticks_usec()
		for frame in range(FRAMES_PER_BATCH):
			_travel_layer._process(1.0 / 60.0)
			var points := _travel_layer._get_cached_route_points(ScheduleManager.current_action)
			_travel_layer._interpolate_cached_route(float(batch * FRAMES_PER_BATCH + frame) / float(FRAME_COUNT - 1))
			if points.is_empty():
				break
		await get_tree().process_frame
		batch_microseconds.append(float(Time.get_ticks_usec() - started_usec))
	var node_count_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var first_average := _average(batch_microseconds.slice(0, 5))
	var last_average := _average(batch_microseconds.slice(batch_microseconds.size() - 5))
	print("30-second-equivalent metrics: static_draws=%d dynamic_draws=%d route_cache_builds=%d navigation_builds=%d nodes=%d->%d first_5_batches_us=%.1f last_5_batches_us=%.1f" % [
		_map_canvas.debug_static_draw_count,
		_travel_layer.debug_draw_count,
		_travel_layer.debug_route_cache_build_count,
		GameManager.debug_navigation_grid_build_count,
		node_count_before,
		node_count_after,
		first_average,
		last_average,
	])
	_expect(_travel_layer.debug_process_frame_count >= FRAME_COUNT, "dynamic layer processes every sampled movement frame")
	_expect(_travel_layer.debug_draw_count > 0, "dynamic layer redraws while travel is active")
	_expect(_map_canvas.debug_static_draw_count == 0, "static map does not redraw during movement-only frames")
	_expect(_travel_layer.debug_route_cache_build_count == 1, "movement route drawing data is built once")
	_expect(GameManager.debug_navigation_grid_build_count == 0, "movement frames do not rebuild the cached navigation grid")
	_expect(node_count_after <= node_count_before, "movement sampling does not grow the scene node count")


func _test_clock_signal_throttle() -> void:
	TimeManager.reset_debug_clock_emit_count()
	for index in range(1000):
		TimeManager._emit_clock(false)
	_expect(TimeManager.debug_clock_emit_count == 0, "ordinary clock notifications are throttled within 100ms")
	TimeManager._emit_clock(true)
	_expect(TimeManager.debug_clock_emit_count == 1, "forced clock notification bypasses throttling")


func _test_speed_equivalence() -> void:
	var snapshots: Dictionary = {}
	for speed in [TimeManager.Speed.X1, TimeManager.Speed.X2, TimeManager.Speed.X5]:
		snapshots[speed] = _run_travel_at_speed(speed)
	var baseline: Dictionary = snapshots[TimeManager.Speed.X1]
	for speed in [TimeManager.Speed.X2, TimeManager.Speed.X5]:
		var candidate: Dictionary = snapshots[speed]
		_expect(candidate.get("midpoint", Vector2.ZERO).is_equal_approx(baseline.get("midpoint", Vector2.ZERO)), "%dx speed has the same visual midpoint at the same game time" % speed)
		_expect(candidate.get("final_cell", Vector2i.ZERO) == baseline.get("final_cell", Vector2i.ZERO), "%dx speed reaches the same final map cell" % speed)
		_expect(is_equal_approx(float(candidate.get("elapsed", 0.0)), float(baseline.get("elapsed", 0.0))), "%dx speed advances the same authoritative game time" % speed)
		_expect(is_equal_approx(float(candidate.get("cash", 0.0)), float(baseline.get("cash", 0.0))), "%dx speed settles the same travel fare" % speed)
		_expect(is_equal_approx(float(candidate.get("energy", 0.0)), float(baseline.get("energy", 0.0))), "%dx speed settles the same movement energy" % speed)
		_expect(candidate.get("economy", {}) == baseline.get("economy", {}), "%dx speed preserves NPC order and economy totals" % speed)


func _run_travel_at_speed(speed: int) -> Dictionary:
	seed(TEST_SEED)
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var created := GameManager.create_character({
		"player_name": "Speed Tester", "gender": "female", "age": 28,
		"difficulty_id": "normal", "preset_id": "", "home_id": "home_old_community", "trait_ids": [],
	})
	if not bool(created.get("success", false)):
		return {}
	var entrance: Dictionary = GameManager.get_navigation_grid().storefront_entrances.get(DESTINATION_STOREFRONT_ID, {})
	var started := ScheduleManager.start_travel_to_cell(str(entrance.get("block_id", "")), entrance.get("cell", Vector2i(-1, -1)), MovementConfig.WALK, DESTINATION_STOREFRONT_ID)
	if not bool(started.get("can", false)):
		return {}
	TimeManager.set_speed(speed)
	_travel_layer.refresh_from_state()
	_travel_layer.reset_debug_counters(true)
	var action := ScheduleManager.current_action
	var start_seconds := TimeManager.total_game_seconds
	var duration_seconds := float(started.get("duration_hours", 0.0)) * 3600.0
	TimeManager._process(duration_seconds * 0.5 / (TimeManager.GAME_SECONDS_PER_REAL_SECOND_AT_X1 * float(speed)))
	var ratio := clampf((TimeManager.total_game_seconds - action.start_game_seconds) / maxf(1.0, action.duration_hours * 3600.0), 0.0, 1.0)
	_travel_layer._get_cached_route_points(action)
	var midpoint := _travel_layer._interpolate_cached_route(ratio)
	TimeManager._process((duration_seconds * 0.5 + 0.01) / (TimeManager.GAME_SECONDS_PER_REAL_SECOND_AT_X1 * float(speed)))
	return {
		"midpoint": midpoint,
		"final_cell": GameManager.player_state.current_map_cell,
		"elapsed": TimeManager.total_game_seconds - start_seconds,
		"cash": GameManager.player_state.cash,
		"energy": GameManager.player_state.energy,
		"economy": _npc_economy_snapshot(),
	}


func _npc_economy_snapshot() -> Dictionary:
	var result := {"orders": 0, "revenue": 0.0, "cost": 0.0, "inventory": 0, "operating_cash": 0.0}
	for store in GameManager.npc_stores:
		result.orders += store.total_orders
		result.revenue += store.total_revenue
		result.cost += store.total_cost
		result.inventory += store.get_total_inventory_across_slots()
		result.operating_cash += store.operating_cash
	return result


func _average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


func _cleanup() -> void:
	TimeManager.set_speed(TimeManager.Speed.PAUSED)
	ScheduleManager.reset_for_new_game()
	if is_instance_valid(_map_panel):
		_map_panel.queue_free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		print("FAIL: " + label)
