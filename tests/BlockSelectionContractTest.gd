extends Node

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("── Block 调查契约测试 ──")
	_test_click_selects_block()
	_test_click_again_deselects_block()
	_test_multiple_blocks_can_be_selected()
	_test_clear_selection()
	_test_region_research_uses_selected_blocks()
	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _make_canvas() -> CityMapCanvas:
	var canvas := CityMapCanvas.new()
	var first := BlockData.new()
	first.id = "TEST_B001"
	first.name = "测试区块1"
	first.city_region_id = "CR001"
	first.map_bounds = Rect2(0, 0, 100, 100)

	var second := BlockData.new()
	second.id = "TEST_B002"
	second.name = "测试区块2"
	second.city_region_id = "CR001"
	second.map_bounds = Rect2(100, 0, 100, 100)

	var blocks: Array[BlockData] = [first, second]
	canvas.setup([], blocks)
	return canvas


func _click(canvas: CityMapCanvas, screen_position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = screen_position
	canvas._gui_input(event)


func _expect(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("✅ %s" % description)
	else:
		_failed += 1
		print("❌ %s" % description)


func _test_click_selects_block() -> void:
	var canvas := _make_canvas()
	_click(canvas, Vector2(15, 15))
	_expect(canvas.selected_block_ids == ["TEST_B001"], "鼠标点击区块后应选中该区块")
	canvas.free()


func _test_click_again_deselects_block() -> void:
	var canvas := _make_canvas()
	_click(canvas, Vector2(15, 15))
	_click(canvas, Vector2(15, 15))
	_expect(canvas.selected_block_ids.is_empty(), "再次点击已选区块应取消选择")
	canvas.free()


func _test_multiple_blocks_can_be_selected() -> void:
	var canvas := _make_canvas()
	_click(canvas, Vector2(15, 15))
	_click(canvas, Vector2(45, 15))
	_expect(canvas.selected_block_ids == ["TEST_B001", "TEST_B002"], "鼠标点击不同区块后应允许同时选择多个区块")
	_click(canvas, Vector2(45, 15))
	_expect(canvas.selected_block_ids == ["TEST_B001"], "再次点击第二个区块应只取消第二个区块")
	canvas.free()


func _test_clear_selection() -> void:
	var canvas := _make_canvas()
	canvas.set_block_selected("TEST_B001", true)
	canvas.set_block_selected("TEST_B002", true)
	canvas.clear_block_selection()
	_expect(canvas.selected_block_ids.is_empty(), "清空选择后不应保留任何区块")
	canvas.free()


func _test_region_research_uses_selected_blocks() -> void:
	GameManager.start_new_game()
	var create_result := GameManager.create_character({
		"player_name": "Block 调查测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_expect(bool(create_result.get("success", false)), "创建角色应成功")
	if not bool(create_result.get("success", false)):
		return

	if GameManager.all_blocks.size() < 2:
		_expect(false, "测试需要至少两个真实Block")
		return

	var first: BlockData = GameManager.all_blocks[0]
	var second: BlockData = GameManager.all_blocks[1]
	GameManager.player_state.block_understanding.erase(first.id)
	GameManager.player_state.block_understanding.erase(second.id)

	var block_ids: Array[String] = [first.id, second.id]
	var start_result := ScheduleManager.start_action_now("region_research", "", block_ids)
	_expect(bool(start_result.get("can", false)), "区域调研应接受选中的Block ID列表")
	if not bool(start_result.get("can", false)):
		return

	_expect(
		ScheduleManager.current_action != null and ScheduleManager.current_action.target_ids == block_ids,
		"当前调研行动应直接保存选中的Block ID列表"
	)

	ScheduleManager._finalize_current_action(1.0)
	var first_understanding := GameManager.get_block_understanding(first.id)
	var second_understanding := GameManager.get_block_understanding(second.id)
	_expect(first_understanding > 0.0, "第一个选中Block应获得调查进度")
	_expect(second_understanding > 0.0, "第二个选中Block应获得调查进度")
	_expect(GameManager.player_state.survey_areas.is_empty(), "本次Block调查不应创建SurveyArea")
