extends Node

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	print("── Block 鼠标点选契约测试 ──")
	_test_click_selects_block()
	_test_click_again_deselects_block()
	_test_multiple_blocks_can_be_selected()
	_test_clear_selection()
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
