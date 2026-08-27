extends Node

var _passed := 0
var _failed := 0
const BLOCK_ID := "block_w_school"


func _ready() -> void:
	_test_sync_is_default_and_even()
	_test_population_completion_does_not_block_research()
	_test_zero_energy_rejects_research_without_time_change()
	_test_minimum_frame_energy_boundary()
	_test_minimum_frame_energy_uses_fatigue_multiplier()
	_test_energy_debt_rejects_research()
	_test_specialist_completion_switches_to_sync()
	_test_only_all_focuses_complete_the_block()
	await _test_map_button_uses_minimum_frame_energy()
	print("========== Independent research contract: %d passed / %d failed ==========" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("✓ %s" % description)
	else:
		_failed += 1
		print("✗ %s" % description)


func _reset_state() -> bool:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var result := GameManager.create_character({
		"player_name": "Research Focus Test", "gender": "female", "age": 28,
		"difficulty_id": "normal", "preset_id": "", "trait_ids": [],
	})
	GameManager.player_state.current_block_id = BLOCK_ID
	GameManager.player_state.energy = GameManager.player_state.max_energy
	TimeManager.total_game_seconds = TimeManager.DAY_START_SECONDS
	return bool(result.get("success", false)) and GameManager.get_block(BLOCK_ID) != null


func _empty_focuses() -> Dictionary:
	var progress := {}
	for focus_id in GameManager.BLOCK_RESEARCH_FOCUSES:
		progress[focus_id] = 0.0
	return progress


func _test_sync_is_default_and_even() -> void:
	_expect(_reset_state(), "test setup succeeds")
	_expect(ScheduleManager.selected_research_focus == ScheduleManager.RESEARCH_FOCUS_ALL, "sync research is the default")
	GameManager.player_state.block_research_progress[BLOCK_ID] = _empty_focuses()
	var applied := ScheduleManager._apply_block_research_work(BLOCK_ID, 60.0, ScheduleManager.RESEARCH_FOCUS_ALL)
	var tracks: Dictionary = GameManager.player_state.block_research_progress[BLOCK_ID]
	var evenly_distributed := is_equal_approx(float(applied.get("used_work", 0.0)), 60.0)
	for focus_id in GameManager.BLOCK_RESEARCH_FOCUSES:
		evenly_distributed = evenly_distributed and is_equal_approx(float(tracks.get(focus_id, 0.0)), 10.0)
	_expect(evenly_distributed, "sync research evenly divides total work among unfinished focuses")


func _test_population_completion_does_not_block_research() -> void:
	_expect(_reset_state(), "population-complete setup succeeds")
	var tracks := _empty_focuses()
	tracks["population"] = 100.0
	GameManager.player_state.block_research_progress[BLOCK_ID] = tracks
	var check := ScheduleManager.can_schedule_action("region_research", 8, "", [BLOCK_ID])
	_expect(bool(check.get("can", false)), "a population-complete block remains researchable")


func _test_zero_energy_rejects_research_without_time_change() -> void:
	_expect(_reset_state(), "zero-energy setup succeeds")
	GameManager.player_state.block_research_progress[BLOCK_ID] = _empty_focuses()
	GameManager.player_state.energy = 0.0
	TimeManager.set_speed(TimeManager.Speed.PAUSED)
	var seconds_before := TimeManager.total_game_seconds
	var check := ScheduleManager.can_schedule_action("region_research", TimeManager.get_current_hour_int(), "", [BLOCK_ID])
	var started := ScheduleManager.start_action_now("region_research", "", [BLOCK_ID])
	_expect(str(check.get("reason_code", "")) == "energy_insufficient" and str(started.get("reason_code", "")) == "energy_insufficient", "zero energy rejects research before an action starts")
	_expect(ScheduleManager.current_action == null and TimeManager.speed == TimeManager.Speed.PAUSED and is_equal_approx(TimeManager.total_game_seconds, seconds_before) and is_equal_approx(GameManager.player_state.energy, 0.0), "zero-energy rejection leaves time, action, and energy unchanged")


func _test_minimum_frame_energy_boundary() -> void:
	_expect(_reset_state(), "minimum-frame-energy setup succeeds")
	GameManager.player_state.block_research_progress[BLOCK_ID] = _empty_focuses()
	var required := ScheduleManager.get_region_research_minimum_start_energy()
	GameManager.player_state.energy = required - 0.00001
	TimeManager.set_speed(TimeManager.Speed.PAUSED)
	var seconds_before := TimeManager.total_game_seconds
	var entries_before := ScheduleManager.completed_entries_today.size()
	var rejected := ScheduleManager.start_action_now("region_research", "", [BLOCK_ID])
	_expect(not bool(rejected.get("can", false)) and str(rejected.get("reason_code", "")) == "energy_insufficient", "energy below one two-second quantum rejects research")
	_expect(ScheduleManager.current_action == null and TimeManager.speed == TimeManager.Speed.PAUSED and is_equal_approx(TimeManager.total_game_seconds, seconds_before) and ScheduleManager.completed_entries_today.size() == entries_before, "sub-quantum rejection does not advance time or mutate action history")

	_expect(_reset_state(), "exact-frame-energy setup succeeds")
	GameManager.player_state.block_research_progress[BLOCK_ID] = _empty_focuses()
	required = ScheduleManager.get_region_research_minimum_start_energy()
	GameManager.player_state.energy = required
	var exact_check := ScheduleManager.can_schedule_action("region_research", TimeManager.get_current_hour_int(), "", [BLOCK_ID])
	_expect(bool(exact_check.get("can", false)), "energy equal to one two-second quantum allows research")

	GameManager.player_state.energy = required + 0.00001
	var above_check := ScheduleManager.can_schedule_action("region_research", TimeManager.get_current_hour_int(), "", [BLOCK_ID])
	_expect(bool(above_check.get("can", false)), "energy above one two-second quantum allows research")


func _test_minimum_frame_energy_uses_fatigue_multiplier() -> void:
	_expect(_reset_state(), "fatigue-energy setup succeeds")
	GameManager.player_state.work_hours_today = 0.0
	var normal_required := ScheduleManager.get_region_research_minimum_start_energy()
	GameManager.player_state.work_hours_today = 9.0
	var tired_required := ScheduleManager.get_region_research_minimum_start_energy()
	GameManager.player_state.work_hours_today = 11.0
	var overworked_required := ScheduleManager.get_region_research_minimum_start_energy()
	GameManager.player_state.work_hours_today = 13.0
	var exhausted_required := ScheduleManager.get_region_research_minimum_start_energy()
	_expect(is_equal_approx(tired_required, normal_required * 1.25) and is_equal_approx(overworked_required, normal_required * 1.6) and is_equal_approx(exhausted_required, normal_required * 2.0), "minimum research energy follows current fatigue multiplier")


func _test_energy_debt_rejects_research() -> void:
	_expect(_reset_state(), "energy-debt setup succeeds")
	GameManager.player_state.block_research_progress[BLOCK_ID] = _empty_focuses()
	GameManager.player_state.energy = ScheduleManager.get_region_research_minimum_start_energy() * 2.0
	GameManager.player_state.energy_debt = 1.0
	var check := ScheduleManager.can_schedule_action("region_research", TimeManager.get_current_hour_int(), "", [BLOCK_ID])
	_expect(not bool(check.get("can", false)) and str(check.get("reason_code", "")) == "energy_insufficient", "energy debt rejects research even when current energy can pay a frame")


func _test_specialist_completion_switches_to_sync() -> void:
	_expect(_reset_state(), "specialist-switch setup succeeds")
	var tracks := _empty_focuses()
	tracks["population"] = 95.0
	GameManager.player_state.block_research_progress[BLOCK_ID] = tracks
	ScheduleManager.set_region_research_focus("population")
	var started := ScheduleManager.start_action_now("region_research", "", [BLOCK_ID])
	_expect(bool(started.get("can", false)), "population specialist research starts")
	if not bool(started.get("can", false)):
		return
	TimeManager.total_game_seconds += 3600.0
	ScheduleManager._advance_continuous_region_research_to_elapsed()
	var updated: Dictionary = GameManager.player_state.block_research_progress[BLOCK_ID]
	_expect(ScheduleManager.current_action != null and ScheduleManager.current_action.is_active and ScheduleManager.current_action.research_focus == ScheduleManager.RESEARCH_FOCUS_ALL, "completed specialist automatically changes to sync without ending the action")
	_expect(float(updated.get("groups", 0.0)) > 0.0, "remaining time advances other focuses after the automatic switch")


func _test_only_all_focuses_complete_the_block() -> void:
	_expect(_reset_state(), "full-completion setup succeeds")
	var tracks := _empty_focuses()
	for focus_id in GameManager.BLOCK_RESEARCH_FOCUSES:
		tracks[focus_id] = 100.0
	GameManager.player_state.block_research_progress[BLOCK_ID] = tracks
	_expect(GameManager.is_block_research_complete(BLOCK_ID), "all six focuses mark a block as complete")
	var check := ScheduleManager.can_schedule_action("region_research", 8, "", [BLOCK_ID])
	_expect(not bool(check.get("can", false)), "fully researched block rejects another research action")
	TimeManager.set_speed(TimeManager.Speed.PAUSED)
	var seconds_before := TimeManager.total_game_seconds
	var energy_before := GameManager.player_state.energy
	var started := ScheduleManager.start_action_now("region_research", "", [BLOCK_ID])
	_expect(not bool(started.get("can", false)) and ScheduleManager.current_action == null and TimeManager.speed == TimeManager.Speed.PAUSED and is_equal_approx(TimeManager.total_game_seconds, seconds_before) and is_equal_approx(GameManager.player_state.energy, energy_before), "rejected research does not start time, create an action, or consume energy")


func _test_map_button_uses_minimum_frame_energy() -> void:
	_expect(_reset_state(), "map-button-energy setup succeeds")
	GameManager.player_state.block_research_progress[BLOCK_ID] = _empty_focuses()
	var panel := preload("res://scenes/map/CityMapPanel.tscn").instantiate()
	add_child(panel)
	await get_tree().process_frame
	panel.map_canvas.set_block_selected(BLOCK_ID, true)
	GameManager.player_state.energy = ScheduleManager.get_region_research_minimum_start_energy() - 0.00001
	panel._refresh_research_controls()
	_expect(panel.start_research_button.disabled and panel.start_research_button.tooltip_text == "精力不足，无法开始调查", "map research button disables when energy cannot pay one frame")
	var seconds_before := TimeManager.total_game_seconds
	panel._on_start_research_pressed()
	_expect(ScheduleManager.current_action == null and is_equal_approx(TimeManager.total_game_seconds, seconds_before), "map click defense cannot start time with sub-frame energy")
	GameManager.player_state.energy = ScheduleManager.get_region_research_minimum_start_energy()
	panel._refresh_research_controls()
	_expect(not panel.start_research_button.disabled, "map research button re-enables after enough energy is restored")

	var minimum_energy := ScheduleManager.get_region_research_minimum_start_energy()
	GameManager.player_state.energy = minimum_energy * 1.5
	panel._on_start_research_pressed()
	_expect(ScheduleManager.current_action != null, "research can start with more than one logical frame of energy")
	var stop_time_before := TimeManager.total_game_seconds
	TimeManager.total_game_seconds += ScheduleManager.REGION_RESEARCH_START_QUANTUM_GAME_SECONDS * 2.0
	ScheduleManager._advance_continuous_region_research_to_elapsed()
	_expect(ScheduleManager.current_action == null and is_zero_approx(GameManager.player_state.energy), "an unaffordable research frame exhausts the unusable remainder without debt")
	_expect(panel.start_research_button.disabled and panel.start_research_button.tooltip_text == "精力不足，无法开始调查", "map research button disables immediately after automatic energy stop")
	panel._on_start_research_pressed()
	_expect(ScheduleManager.current_action == null and is_equal_approx(TimeManager.total_game_seconds, stop_time_before + ScheduleManager.REGION_RESEARCH_START_QUANTUM_GAME_SECONDS * 2.0), "click defense cannot restart time after automatic energy stop")
	panel.queue_free()
