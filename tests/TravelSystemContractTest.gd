extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var created := GameManager.create_character({"player_name":"Travel Tester", "gender":"female", "age":28, "difficulty_id":"normal", "preset_id":"", "home_id":"home_old_community", "trait_ids":[]})
	_expect(bool(created.get("success", false)), "custom character selects a home")
	_expect(GameManager.player_state.home_id == "home_old_community" and GameManager.player_state.current_location_kind == "home", "home is the initial position")
	_expect(GameManager.player_state.owned_vehicles.is_empty(), "custom character starts without vehicles")
	var target := GameManager.get_block("block_w_school")
	_expect(target != null, "travel target exists")
	if target != null:
		var walk := ScheduleManager.get_travel_quote(target.id, MovementConfig.WALK)
		var transit := ScheduleManager.get_travel_quote(target.id, MovementConfig.TRANSIT)
		var bicycle := ScheduleManager.get_travel_quote(target.id, MovementConfig.BICYCLE)
		_expect(bool(walk.get("can", false)) and float(walk.get("energy_cost", 0.0)) > 0.0, "walking quote uses road distance and energy")
		_expect(bool(transit.get("can", false)) and float(transit.get("cost", 0.0)) > 0.0, "transit costs by distance")
		_expect(not bool(bicycle.get("can", true)), "bicycle requires ownership")
		var cash_before := GameManager.player_state.cash
		var energy_before := GameManager.player_state.energy
		var started := ScheduleManager.start_travel(target.id, MovementConfig.TRANSIT)
		_expect(bool(started.get("can", false)) and GameManager.player_state.cash < cash_before, "travel charges fare at departure")
		var duration := float(started.get("duration_hours", 0.0))
		TimeManager.total_game_seconds += duration * 3600.0
		ScheduleManager.tick()
		_expect(GameManager.player_state.current_block_id == target.id and GameManager.player_state.energy < energy_before, "travel completes at target and consumes energy")
	print("Travel system: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func _expect(condition: bool, label: String) -> void:
	if condition: passed += 1; print("PASS: " + label)
	else: failed += 1; print("FAIL: " + label)
