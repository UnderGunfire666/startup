extends Node

var _passed := 0
var _failed := 0


func _ready() -> void:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	GameManager.create_character({
		"player_name": "发现测试", "gender": "female", "age": 28,
		"difficulty_id": "normal", "preset_id": "", "trait_ids": [],
	})
	_test_week_calendar()
	_test_authored_block_profiles()
	_test_progressive_and_persistent_discovery()
	_test_observed_after_school_window()
	_test_occasional_discovery()
	_test_legacy_player_state()
	print("========== 区块发现契约：%d 通过 / %d 失败 ==========" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("✓ %s" % description)
	else:
		_failed += 1
		print("✗ %s" % description)


func _test_week_calendar() -> void:
	_expect(TimeManager.get_day_of_week(1) == 1 and TimeManager.is_weekday(5), "第 1–5 天属于工作日")
	_expect(TimeManager.get_day_of_week(6) == 6 and TimeManager.is_weekend(7), "第 6–7 天属于周末")
	_expect(TimeManager.get_day_of_week(8) == 1, "周历按七天循环且不改变绝对日期")


func _test_authored_block_profiles() -> void:
	_expect(not GameManager.all_blocks.is_empty(), "blocks.json 可被加载为区块列表")
	var all_valid := true
	for block in GameManager.all_blocks:
		var total := 0.0
		for group_id in SpatialConfig.POPULATION_GROUPS:
			total += block.get_group_weight(group_id)
		all_valid = all_valid and SpatialConfig.is_valid_block_type(block.block_type) and is_equal_approx(total, 1.0)
	_expect(all_valid, "每个区块都具有有效且归一化的人群配置")


func _test_progressive_and_persistent_discovery() -> void:
	var block_id := "block_w_school"
	var block := GameManager.get_block(block_id)
	_expect(block != null and block.get_group_weight("student") > 0.0, "真实学校区块存在且拥有学生人群配置")
	if block == null:
		return
	GameManager.player_state.block_understanding[block_id] = 100.0
	TimeManager.current_day = 1
	TimeManager.total_game_seconds = 12.0 * 3600.0
	var records := BlockDiscoveryManager.evaluate_research(block_id, 1.0)
	var known: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	_expect(int(known.get("group_student", 0)) == 4, "人群发现会直接补齐已跨越的四档")
	_expect(not records.is_empty() and GameManager.player_state.discovery_history.size() == records.size(), "每次解锁都写入持久时间线")
	var second := BlockDiscoveryManager.evaluate_research(block_id, 1.0)
	_expect(second.is_empty(), "同一档发现不会重复记录")
	var restored := PlayerState.from_save_dict(GameManager.player_state.to_save_dict())
	_expect(not restored.discovery_history.is_empty() and not restored.block_discovery_progress.is_empty(), "发现记录可随玩家状态保存和恢复")


func _test_observed_after_school_window() -> void:
	var block_id := "block_w_school"
	GameManager.player_state.block_discovery_progress.erase(block_id)
	GameManager.player_state.discovery_history.clear()
	GameManager.player_state.block_understanding[block_id] = 100.0
	TimeManager.current_day = 1
	TimeManager.total_game_seconds = 16.0 * 3600.0
	BlockDiscoveryManager.evaluate_research(block_id, 1.0)
	var before: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	_expect(not before.has("student_after_school"), "17 点前不会发现放学人流")
	TimeManager.total_game_seconds = 17.0 * 3600.0
	BlockDiscoveryManager.evaluate_research(block_id, 1.0)
	var weekday: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	_expect(int(weekday.get("student_after_school", 0)) == 4, "工作日 17–19 点可发现学生放学规律")
	GameManager.player_state.block_discovery_progress.erase(block_id)
	TimeManager.current_day = 6
	TimeManager.total_game_seconds = 17.0 * 3600.0
	BlockDiscoveryManager.evaluate_research(block_id, 1.0)
	var weekend: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	_expect(not weekend.has("student_after_school"), "周末同一时段不会触发工作日放学规律")


func _test_occasional_discovery() -> void:
	var block_id := "block_w_school"
	GameManager.player_state.block_discovery_progress.erase(block_id)
	GameManager.player_state.discovery_history.clear()
	GameManager.player_state.block_understanding[block_id] = 0.0
	TimeManager.current_day = 1
	TimeManager.total_game_seconds = 10.0 * 3600.0
	BlockDiscoveryManager.evaluate_research(block_id, 0.0)
	var known: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	_expect(int(known.get("occasional_local_tip", 0)) == 1, "偶发线索不受了解度门槛限制")
	TimeManager.total_game_seconds += 3600.0
	BlockDiscoveryManager.evaluate_research(block_id, 0.0)
	_expect(GameManager.player_state.discovery_history.size() == 1, "偶发线索永久去重")


func _test_legacy_player_state() -> void:
	var restored := PlayerState.from_save_dict({"player_name": "旧存档", "block_understanding": {"a": 25.0}})
	_expect(restored.discovery_history.is_empty() and restored.block_discovery_progress.is_empty(), "旧存档缺少发现字段时安全初始化为空")
