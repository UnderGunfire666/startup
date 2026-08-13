extends Node

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	print("========== Map Action Target Contract Test ==========")
	_test_map_selection_drives_movement_and_initial_location()
	_test_map_research_establishes_initial_location()
	_test_sequential_research_establishes_initial_location()
	print("========== Test finished: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _new_character() -> bool:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	TimeManager.reset()
	var result: Dictionary = GameManager.create_character({
		"player_name": "Map Action Target Tester",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_assert_true(bool(result.get("success", false)), "character creation succeeds")
	return bool(result.get("success", false))


func _test_map_selection_drives_movement_and_initial_location() -> void:
	if not _new_character():
		return
	var first := GameManager.get_block("cc_primary_school_1")
	var second := GameManager.get_block("cc_university_3")
	_assert_true(first != null and second != null, "movement test blocks exist")
	if first == null or second == null:
		return

	ScheduleManager.set_selected_map_block_ids([first.id])
	var first_check := ScheduleManager.can_schedule_action("move_to_block", 8)
	_assert_true(bool(first_check.get("can", false)), "map-selected block is a valid move target")
	var first_move := ScheduleManager.start_action_now("move_to_block")
	_assert_true(bool(first_move.get("can", false)), "movement starts without an explicit target argument")
	_assert_true(GameManager.player_state.current_block_id == first.id,
		"first map-directed movement establishes the selected initial location")

	ScheduleManager.set_selected_map_block_ids([second.id])
	var second_move := ScheduleManager.start_action_now("move_to_block")
	_assert_true(bool(second_move.get("can", false)), "new map selection updates the move destination")
	_assert_true(ScheduleManager.current_action != null and ScheduleManager.current_action.target_id == second.id,
		"movement action stores the selected map block as its target")
	var travel_hours := MovementConfig.get_travel_hours(first, second)
	TimeManager.total_game_seconds += travel_hours * 3600.0
	ScheduleManager.tick()
	_assert_true(GameManager.player_state.current_block_id == second.id,
		"cross-block movement reaches the map-selected destination")


func _test_map_research_establishes_initial_location() -> void:
	if not _new_character():
		return
	var block := GameManager.get_block("cc_primary_school_1")
	_assert_true(block != null, "research test block exists")
	if block == null:
		return
	GameManager.player_state.block_understanding.erase(block.id)
	var result := ScheduleManager.start_action_now("region_research", "", [block.id])
	_assert_true(bool(result.get("can", false)), "research starts from the first selected map block")
	_assert_true(GameManager.player_state.current_block_id == block.id,
		"first map-directed research establishes the selected initial location")
	ScheduleManager.stop_current_action()


func _test_sequential_research_establishes_initial_location() -> void:
	if not _new_character():
		return
	var block := GameManager.get_block("cc_primary_school_1")
	_assert_true(block != null, "sequential research test block exists")
	if block == null:
		return
	GameManager.player_state.block_understanding.erase(block.id)
	var sequence := RegionResearchSequence.new()
	var result := sequence.start([block.id])
	_assert_true(bool(result.get("can", false)), "sequential research starts from a selected initial block")
	_assert_true(GameManager.player_state.current_block_id == block.id,
		"sequential research establishes the selected initial location")
	sequence.cancel()


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)
