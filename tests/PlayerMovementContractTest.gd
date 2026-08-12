extends Node

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("── Phase 6 玩家移动契约测试 ──")
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()

	var character_result: Dictionary = GameManager.create_character({
		"player_name": "玩家移动测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_expect(bool(character_result.get("success", false)), "创建角色应成功")
	if not bool(character_result.get("success", false)):
		_finish()
		return

	_test_move_action_exists()
	_test_same_block_move_is_zero()
	_test_cross_block_move_has_duration()
	_test_move_does_not_teleport()
	_test_research_requires_current_block()
	_finish()

func _expect(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("✅ %s" % description)
	else:
		_failed += 1
		print("❌ %s" % description)

func _find_test_block_pair() -> Array[BlockData]:
	var first := GameManager.get_block("cc_primary_school_1")
	var second := GameManager.get_block("cc_university_3")
	if first != null and second != null and first.id != second.id:
		return [first, second]
	return []

func _test_move_action_exists() -> void:
	var action := ScheduleActionData.get_action("move_to_block")
	_expect(action != null, "move_to_block行动定义应存在")
	if action == null:
		return
	_expect(action.action_effect_type == "move_to_block", "move_to_block效果类型应正确")
	_expect(action.base_energy_cost_per_hour == 0.0, "移动当前阶段不应额外消耗精力")

func _test_same_block_move_is_zero() -> void:
	var blocks := _find_test_block_pair()
	if blocks.is_empty():
		_expect(false, "测试区块应存在")
		return

	GameManager.player_state.current_block_id = blocks[0].id
	var check := ScheduleManager.can_schedule_action(
		"move_to_block",
		8,
		blocks[0].id,
		[]
	)
	_expect(bool(check.get("can", false)), "移动到当前区块应允许")
	_expect(is_equal_approx(float(check.get("duration_hours", -1.0)), 0.0), "移动到当前区块耗时应为0")

func _test_cross_block_move_has_duration() -> void:
	var blocks := _find_test_block_pair()
	if blocks.is_empty():
		_expect(false, "测试区块应存在")
		return

	GameManager.player_state.current_block_id = blocks[0].id
	var check := ScheduleManager.can_schedule_action(
		"move_to_block",
		8,
		blocks[1].id,
		[]
	)
	_expect(bool(check.get("can", false)), "跨区块移动应允许")
	_expect(float(check.get("duration_hours", 0.0)) > 0.0, "跨区块移动应消耗时间")

func _test_move_does_not_teleport() -> void:
	var blocks := _find_test_block_pair()
	if blocks.is_empty():
		_expect(false, "测试区块应存在")
		return

	GameManager.player_state.current_block_id = blocks[0].id
	TimeManager.total_game_seconds = TimeManager.DAY_START_SECONDS
	var check := ScheduleManager.can_schedule_action("move_to_block", 8, blocks[1].id)
	_expect(bool(check.get("can", false)), "跨区块移动应能通过前置校验")
	if not bool(check.get("can", false)):
		return

	var expected_duration := float(check.get("duration_hours", 0.0))
	var start_result := ScheduleManager.start_action_now("move_to_block", blocks[1].id)
	_expect(bool(start_result.get("can", false)), "跨区块移动应能开始")
	if not bool(start_result.get("can", false)):
		return

	_expect(GameManager.player_state.current_block_id == blocks[0].id, "移动开始后玩家不能立即传送到目标区块")

	if expected_duration > 0.0:
		TimeManager.total_game_seconds += expected_duration * 3600.0
		ScheduleManager.tick()

	_expect(GameManager.player_state.current_block_id == blocks[1].id, "移动完成后玩家应位于目标区块")
	_expect(ScheduleManager.current_action == null, "移动完成后当前行动应结束")

func _test_research_requires_current_block() -> void:
	var blocks := _find_test_block_pair()
	if blocks.is_empty():
		_expect(false, "测试区块应存在")
		return

	GameManager.player_state.block_understanding[blocks[0].id] = 0.0
	GameManager.player_state.current_block_id = blocks[1].id
	var check := ScheduleManager.can_schedule_action(
		"region_research",
		8,
		"",
		[blocks[0].id]
	)
	_expect(not bool(check.get("can", false)), "不在目标区块时不得直接开始调查")
	_expect(str(check.get("reason_code", "")) == "player_not_at_target_block", "位置不符应返回player_not_at_target_block")

func _finish() -> void:
	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
