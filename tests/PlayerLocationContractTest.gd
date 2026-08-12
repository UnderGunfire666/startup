extends Node

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("── Phase 5 玩家位置契约测试 ──")
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()

	var character_result: Dictionary = GameManager.create_character({
		"player_name": "玩家位置测试者",
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

	_expect(GameManager.player_state.current_block_id.is_empty(), "新角色初始位置应为空，不能凭空指定区块")

	var valid_block_id := "cc_primary_school_1"
	var set_valid := GameManager.player_state.set_current_block(valid_block_id)
	_expect(set_valid, "设置有效区块位置应成功")
	_expect(GameManager.player_state.current_block_id == valid_block_id, "玩家当前位置应保存为指定Block ID")

	var set_invalid := GameManager.player_state.set_current_block("__invalid_block__")
	_expect(not set_invalid, "设置不存在的区块位置应失败")
	_expect(GameManager.player_state.current_block_id == valid_block_id, "设置无效区块后当前位置不得被污染")

	var save_data: Dictionary = GameManager.player_state.to_save_dict()
	_expect(str(save_data.get("current_block_id", "")) == valid_block_id, "玩家当前位置应写入存档数据")

	var restored := PlayerState.from_save_dict(save_data)
	_expect(restored.current_block_id == valid_block_id, "从存档恢复后应保留玩家当前位置")

	var clear_result := GameManager.player_state.set_current_block("")
	_expect(clear_result, "清空玩家当前位置应成功")
	_expect(GameManager.player_state.current_block_id.is_empty(), "清空后当前位置应为空")

	_finish()

func _expect(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("✅ %s" % description)
	else:
		_failed += 1
		print("❌ %s" % description)

func _finish() -> void:
	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
