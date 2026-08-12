extends Node

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("── Phase 4 持续区块调查契约测试 ──")
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var character_result: Dictionary = GameManager.create_character({
		"player_name": "Phase 4 测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_expect(bool(character_result.get("success", false)), "创建角色应成功")

	_test_research_window()
	_test_area_controls_hourly_progress()
	_test_continuous_progress_and_energy()
	_test_completed_block_rejects_new_action()

	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _expect(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("✅ %s" % description)
	else:
		_failed += 1
		print("❌ %s" % description)

func _test_research_window() -> void:
	var check := ScheduleManager.can_schedule_action(
		"region_research",
		8,
		"",
		["cc_primary_school_1"]
	)
	_expect(bool(check.get("can", false)), "区域调查在08:00应允许开始")
	_expect(int(check.get("duration_hours", 0)) == 16, "持续调查的行动窗口应延伸到24:00，而非固定2小时")

	var late_check := ScheduleManager.can_schedule_action(
		"region_research",
		23,
		"",
		["cc_primary_school_1"]
	)
	_expect(bool(late_check.get("can", false)), "23:00仍可开始区域调查")
	_expect(int(late_check.get("duration_hours", 0)) == 1, "23:00开始时调查窗口只剩1小时")

	var night_check := ScheduleManager.can_schedule_action(
		"region_research",
		4,
		"",
		["cc_primary_school_1"]
	)
	_expect(not bool(night_check.get("can", false)), "深夜04:00不得开始区域调查")

func _test_area_controls_hourly_progress() -> void:
	var small_block := GameManager.get_block("cc_primary_school_1")
	var large_block := GameManager.get_block("cc_university_3")
	var small_gain := ScheduleManager._get_region_research_hourly_gain(small_block)
	var large_gain := ScheduleManager._get_region_research_hourly_gain(large_block)
	_expect(small_gain > large_gain, "面积更大的区块每小时了解度增长应更慢")
	_expect(is_equal_approx(small_gain, 50.0), "面积90区块按2小时工作量每小时应增加50了解度")

func _test_continuous_progress_and_energy() -> void:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var character_result: Dictionary = GameManager.create_character({
		"player_name": "持续调查测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_expect(bool(character_result.get("success", false)), "持续调查测试角色创建应成功")
	if not bool(character_result.get("success", false)):
		return

	GameManager.player_state.block_understanding["cc_primary_school_1"] = 0.0
	GameManager.player_state.energy = GameManager.player_state.max_energy
	var energy_before: float = GameManager.player_state.energy
	TimeManager.total_game_seconds = TimeManager.DAY_START_SECONDS

	var start_result := ScheduleManager.start_action_now(
		"region_research",
		"",
		["cc_primary_school_1"]
	)
	_expect(bool(start_result.get("can", false)), "持续区域调查应能启动")
	if not bool(start_result.get("can", false)):
		return

	TimeManager.total_game_seconds += 3600.0
	ScheduleManager._advance_continuous_region_research_to_elapsed()
	_expect(is_equal_approx(GameManager.get_block_understanding("cc_primary_school_1"), 50.0), "调查1小时后应获得50点了解度")
	_expect(is_equal_approx(energy_before - GameManager.player_state.energy, 8.0), "调查1小时应消耗8点精力")
	_expect(ScheduleManager.current_action != null and ScheduleManager.current_action.is_active, "区块未完全了解时调查应继续")

	TimeManager.total_game_seconds += 3600.0
	ScheduleManager._advance_continuous_region_research_to_elapsed()
	_expect(is_equal_approx(GameManager.get_block_understanding("cc_primary_school_1"), 100.0), "调查达到所需工作量后应完全了解区块")
	_expect(ScheduleManager.current_action == null, "区块完全了解后持续调查应自动结束")

func _test_completed_block_rejects_new_action() -> void:
	GameManager.player_state.block_understanding["cc_primary_school_1"] = 100.0
	var check := ScheduleManager.can_schedule_action(
		"region_research",
		8,
		"",
		["cc_primary_school_1"]
	)
	_expect(not bool(check.get("can", false)), "已经完全了解的区块不得重新开始调查")
	_expect(str(check.get("reason_code", "")) == "block_already_understood", "完全了解区块应返回block_already_understood")
