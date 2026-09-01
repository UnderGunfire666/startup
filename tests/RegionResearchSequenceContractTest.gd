extends Node

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("── Phase 7 区块调查模式契约测试 ──")
	_test_sequential_research_flow()
	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _expect(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("✅ %s" % description)
	else:
		_failed += 1
		print("❌ %s" % description)

func _test_sequential_research_flow() -> void:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var character_result: Dictionary = GameManager.create_character({
		"player_name": "Phase 7 测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_expect(bool(character_result.get("success", false)), "创建角色应成功")
	if not bool(character_result.get("success", false)):
		return

	var first_block := GameManager.get_block("block_w_school")
	var second_block := GameManager.get_block("block_c_commercial")
	_expect(first_block != null, "第一调查区块应存在")
	_expect(second_block != null, "第二调查区块应存在")
	if first_block == null or second_block == null:
		return

	GameManager.player_state.current_block_id = first_block.id
	_set_all_focus_progress(first_block.id, 0.0)
	_set_all_focus_progress(second_block.id, 0.0)
	TimeManager.total_game_seconds = TimeManager.DAY_START_SECONDS

	var sequence := RegionResearchSequence.new()
	var start_result := sequence.start([first_block.id, second_block.id])
	_expect(bool(start_result.get("can", false)), "按顺序调查应能启动")
	_expect(sequence.active, "按顺序调查启动后应保持活动状态")
	_expect(ScheduleManager.current_action != null and ScheduleManager.current_action.action_id == "region_research", "第一目标应先进入调查行动")

	TimeManager.total_game_seconds += 3600.0
	ScheduleManager._advance_continuous_region_research_to_elapsed()
	_expect(not GameManager.is_block_research_complete(first_block.id), "第一目标未完全了解前不应完成")
	_expect(is_equal_approx(GameManager.get_block_research_progress(second_block.id, "population"), 0.0), "第一目标未完成时第二目标进度不得增加")

	_set_all_focus_progress(first_block.id, 100.0)
	ScheduleManager._finalize_current_action(ScheduleManager.current_action.applied_hours)
	_expect(GameManager.is_block_research_complete(first_block.id), "第一目标完成后六项进度均应达到100%")
	_expect(ScheduleManager.current_action != null and ScheduleManager.current_action.action_id == "move_to_map_cell", "第一目标完成后应自动开始网格移动到第二目标")
	_expect(GameManager.player_state.current_block_id == first_block.id, "移动完成前玩家位置不得提前改变")

	var travel_hours := MovementConfig.get_travel_hours(first_block, second_block)
	_expect(travel_hours > 0.0, "两个不同区块之间应存在移动时间")
	var action_travel_hours := ScheduleManager.current_action.duration_hours
	_expect(action_travel_hours > 0.0 and GameManager.get_navigation_grid().walkable_cells.has(GameManager.player_state.current_map_cell), "调查移动从可导航地图格出发")
	TimeManager.total_game_seconds += (action_travel_hours + 0.001) * 3600.0
	ScheduleManager.tick()
	_expect(GameManager.player_state.current_block_id == second_block.id, "移动完成后玩家应到达第二目标区块")
	_expect(ScheduleManager.current_action != null and ScheduleManager.current_action.action_id == "region_research", "到达第二目标后应自动开始第二目标调查")

	_set_all_focus_progress(second_block.id, 100.0)
	ScheduleManager._finalize_current_action(ScheduleManager.current_action.applied_hours)
	_expect(GameManager.is_block_research_complete(second_block.id), "第二目标完成后六项进度均应达到100%")
	_expect(not sequence.active, "所有目标完成后按顺序调查应自动结束")


func _set_all_focus_progress(block_id: String, value: float) -> void:
	var tracks := {}
	for focus_id in GameManager.BLOCK_RESEARCH_FOCUSES:
		tracks[focus_id] = value
	GameManager.player_state.block_research_progress[block_id] = tracks
