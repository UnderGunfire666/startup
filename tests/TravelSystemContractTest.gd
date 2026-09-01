extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	_test_navigation_grid_is_cached_and_invalidated()
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var created := GameManager.create_character({"player_name":"Travel Tester", "gender":"female", "age":28, "difficulty_id":"normal", "preset_id":"", "home_id":"home_old_community", "trait_ids":[]})
	_expect(bool(created.get("success", false)), "character creation succeeds")
	var storefront_id := "sf_school_stationery"
	var grid := GameManager.get_navigation_grid()
	var entrance: Dictionary = grid.storefront_entrances.get(storefront_id, {})
	_expect(not entrance.is_empty(), "storefront has a resolved entrance")
	var quote := ScheduleManager.get_travel_quote_to_storefront(storefront_id, MovementConfig.WALK)
	_expect(bool(quote.get("can", false)), "walking route reaches storefront")
	for raw_cell in quote.get("route_cells", []):
		var cell := Vector2i(int(raw_cell.get("x", -1)), int(raw_cell.get("y", -1)))
		_expect(grid.walkable_cells.has(cell), "route never crosses a non-walkable cell")
	var cash_before := GameManager.player_state.cash
	var energy_before := GameManager.player_state.energy
	var started := ScheduleManager.start_travel_to_cell("block_w_school", entrance.get("cell", Vector2i(-1, -1)), MovementConfig.WALK, storefront_id)
	_expect(bool(started.get("can", false)), "grid travel starts")
	TimeManager.total_game_seconds += float(started.get("duration_hours", 0.0)) * 3600.0
	ScheduleManager.tick()
	_expect(GameManager.player_state.current_map_cell == entrance.get("cell", Vector2i(-1, -1)), "grid travel arrives at entrance cell")
	_expect(GameManager.player_state.cash == cash_before and GameManager.player_state.energy < energy_before, "walking consumes energy but no fare")
	_finish()

func _expect(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		print("FAIL: " + label)

func _finish() -> void:
	print("Travel system: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _test_navigation_grid_is_cached_and_invalidated() -> void:
	var first := GameManager.get_navigation_grid()
	var second := GameManager.get_navigation_grid()
	_expect(first == second, "navigation grid is reused between route quotes")
	GameManager.invalidate_navigation_grid()
	var rebuilt := GameManager.get_navigation_grid()
	_expect(rebuilt != first, "navigation grid rebuilds after explicit invalidation")
