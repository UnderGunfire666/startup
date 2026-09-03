extends Control

const RUN_SECONDS := 30.0
const EARLY_WINDOW_SECONDS := 5.0
const LATE_WINDOW_START_SECONDS := 20.0
const TARGET_STOREFRONTS: Array[String] = ["sf_industrial_canteen", "sf_nw_grocery"]
const TEST_SEED := 424242

var passed := 0
var failed := 0
var _map_panel: Control
var _operation_panel: Control
var _map_canvas: CityMapCanvas
var _travel_layer: CityMapTravelLayer
var _target_index := 0
var _journey_count := 0


func _ready() -> void:
	print("========== 30-Second Realtime Map Travel Acceptance ==========")
	await _setup_runtime()
	if failed == 0:
		await _run_realtime_acceptance()
	TimeManager.set_speed(TimeManager.Speed.PAUSED)
	print("========== Realtime Acceptance: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _setup_runtime() -> void:
	seed(TEST_SEED)
	GameManager.start_new_game()
	var created := GameManager.create_character({
		"player_name": "Realtime Performance Tester", "gender": "female", "age": 28,
		"difficulty_id": "normal", "preset_id": "", "home_id": "home_old_community", "trait_ids": [],
	})
	_expect(bool(created.get("success", false)), "performance character creation succeeds")
	_expect(_promote_npc_store_to_player_store(), "an operating player store is available during travel")

	_map_panel = preload("res://scenes/map/CityMapPanel.tscn").instantiate()
	_map_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_map_panel)
	_map_canvas = _map_panel.get_node("HBoxContainer/MapScrollContainer/MapCanvas") as CityMapCanvas
	_travel_layer = _map_canvas.get_node("TravelLayer") as CityMapTravelLayer

	_operation_panel = preload("res://scenes/panels/OperationPanel.tscn").instantiate()
	_operation_panel.visible = false
	add_child(_operation_panel)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_start_next_journey(), "the first long-distance journey starts")
	await get_tree().process_frame
	await get_tree().process_frame


func _promote_npc_store_to_player_store() -> bool:
	if GameManager.npc_stores.is_empty():
		return false
	var source: Store = GameManager.npc_stores[0]
	var store := Store.from_save_dict(source.to_save_dict())
	GameManager.npc_stores.remove_at(0)
	store.id = "realtime_performance_store"
	store.name = "Realtime Performance Store"
	store.owner_kind = "player"
	store.is_open = true
	store.is_business_open = true
	store.business_hour_ranges = [Vector2i(0, 24)]
	store.pre_open_stage = Store.PreOpenStage.OPEN_FOR_BUSINESS
	GameManager.stores.append(store)
	GameManager.active_store_id = store.id
	GameManager._sync_data_objects()
	GameManager.set_player_store_presence(store, true)
	return true


func _run_realtime_acceptance() -> void:
	_map_canvas.reset_debug_draw_count()
	_travel_layer.reset_debug_counters(true)
	GameManager.get_navigation_grid()
	GameManager.reset_debug_navigation_grid_build_count()
	TimeManager.reset_debug_clock_emit_count()
	var node_count_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var order_count_before := _total_player_orders()
	var early_frame_ms: Array[float] = []
	var late_frame_ms: Array[float] = []
	var max_draw_calls := 0
	var started_msec := Time.get_ticks_msec()
	var previous_usec := Time.get_ticks_usec()
	var frame_count := 0
	while float(Time.get_ticks_msec() - started_msec) / 1000.0 < RUN_SECONDS:
		await get_tree().process_frame
		var now_usec := Time.get_ticks_usec()
		var frame_ms := float(now_usec - previous_usec) / 1000.0
		previous_usec = now_usec
		var elapsed_seconds := float(Time.get_ticks_msec() - started_msec) / 1000.0
		if elapsed_seconds <= EARLY_WINDOW_SECONDS:
			early_frame_ms.append(frame_ms)
		elif elapsed_seconds >= LATE_WINDOW_START_SECONDS:
			late_frame_ms.append(frame_ms)
		frame_count += 1
		max_draw_calls = maxi(max_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		if ScheduleManager.current_action == null or not ScheduleManager.current_action.is_active:
			_start_next_journey()
		elif TimeManager.speed != TimeManager.Speed.X5:
			TimeManager.set_speed(TimeManager.Speed.X5)

	var node_count_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var order_count_after := _total_player_orders()
	var early_average := _average(early_frame_ms)
	var late_average := _average(late_frame_ms)
	var early_p95 := _percentile(early_frame_ms, 0.95)
	var late_p95 := _percentile(late_frame_ms, 0.95)
	print("realtime metrics: frames=%d journeys=%d early_avg_ms=%.3f late_avg_ms=%.3f early_p95_ms=%.3f late_p95_ms=%.3f static_draws=%d dynamic_draws=%d route_builds=%d navigation_builds=%d nodes=%d->%d clock_emits=%d player_orders=%d->%d max_draw_calls=%d" % [
		frame_count, _journey_count, early_average, late_average, early_p95, late_p95,
		_map_canvas.debug_static_draw_count, _travel_layer.debug_draw_count,
		_travel_layer.debug_route_cache_build_count, GameManager.debug_navigation_grid_build_count,
		node_count_before, node_count_after, TimeManager.debug_clock_emit_count,
		order_count_before, order_count_after, max_draw_calls,
	])
	_expect(frame_count >= 600, "the visible benchmark renders enough real frames")
	_expect(not early_frame_ms.is_empty() and not late_frame_ms.is_empty(), "both early and late frame-time windows are sampled")
	_expect(late_average <= early_average * 1.25 + 1.0, "average frame time does not progressively degrade")
	_expect(late_p95 <= early_p95 * 1.5 + 2.0, "95th-percentile frame time does not progressively degrade")
	_expect(_map_canvas.debug_static_draw_count <= 2, "continuous travel does not repeatedly redraw the static map")
	_expect(_travel_layer.debug_draw_count > 0, "the dynamic travel layer redraws during movement")
	_expect(_travel_layer.debug_route_cache_build_count <= _journey_count + 1, "each journey builds route drawing data at most once")
	_expect(GameManager.debug_navigation_grid_build_count == 0, "continuous travel reuses the navigation grid")
	_expect(node_count_after <= node_count_before, "hidden operation UI and travel do not grow the scene node count")
	_expect(TimeManager.debug_clock_emit_count <= 360, "ordinary clock UI updates remain close to the 10Hz cap")
	_expect(order_count_after > order_count_before, "the player store continues processing orders during travel")


func _start_next_journey() -> bool:
	for offset in range(TARGET_STOREFRONTS.size()):
		var storefront_id := TARGET_STOREFRONTS[(_target_index + offset) % TARGET_STOREFRONTS.size()]
		var entrance: Dictionary = GameManager.get_navigation_grid().storefront_entrances.get(storefront_id, {})
		var result := ScheduleManager.start_travel_to_cell(
			str(entrance.get("block_id", "")),
			entrance.get("cell", Vector2i(-1, -1)),
			MovementConfig.WALK,
			storefront_id
		)
		if bool(result.get("can", false)) and float(result.get("duration_hours", 0.0)) > 0.0:
			_target_index = (_target_index + offset + 1) % TARGET_STOREFRONTS.size()
			_journey_count += 1
			TimeManager.set_speed(TimeManager.Speed.X5)
			return true
	return false


func _total_player_orders() -> int:
	var total := 0
	for store in GameManager.stores:
		total += store.total_orders
	return total


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var index := clampi(int(ceil(float(sorted_values.size()) * ratio)) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]


func _expect(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		print("FAIL: " + label)
