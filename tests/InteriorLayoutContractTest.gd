extends Node

var _passed := 0
var _failed := 0

func _ready() -> void:
	_test_rotation_footprint()
	_test_drag_placement_validation()
	_test_store_layout_round_trip()
	_test_canvas_entrance_and_equipment_labels()
	_test_operational_layout_effects()
	print("========== 室内布局测试：%d 通过 / %d 失败 ==========" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _expect(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("✅ %s" % description)
	else:
		_failed += 1
		print("❌ %s" % description)

func _test_rotation_footprint() -> void:
	var placement := StoreFurniturePlacement.new()
	placement.instance_id = "equipment_test"
	placement.equipment_id = "griddle"
	placement.cell = Vector2i(2, 1)
	var normal_cells := placement.get_footprint_cells(Vector2i(2, 1))
	placement.rotation = 1
	var rotated_cells := placement.get_footprint_cells(Vector2i(2, 1))
	_expect(normal_cells.size() == 2, "设备默认占用格数量正确")
	_expect(rotated_cells == [Vector2i(2, 1), Vector2i(2, 2)], "设备旋转后占用方向正确")

func _test_store_layout_round_trip() -> void:
	var store := Store.new()
	var placement := StoreFurniturePlacement.new()
	placement.instance_id = "equipment_1"
	placement.equipment_id = "steamer"
	placement.cell = Vector2i(3, 4)
	placement.rotation = 2
	store.furniture_layout.append(placement)
	var restored := Store.from_save_dict(store.to_save_dict())
	_expect(restored.furniture_layout.size() == 1, "室内布局存档往返保留项目")
	var restored_item := restored.furniture_layout[0]
	_expect(restored_item.instance_id == "equipment_1", "室内布局往返保留设备实例 ID")
	_expect(restored_item.cell == Vector2i(3, 4) and restored_item.rotation == 2, "室内布局往返保留位置和旋转")

func _test_drag_placement_validation() -> void:
	var moving := StoreFurniturePlacement.new()
	moving.instance_id = "moving"
	moving.equipment_id = "counter"
	moving.cell = Vector2i(0, 0)
	var occupied := StoreFurniturePlacement.new()
	occupied.instance_id = "occupied"
	occupied.equipment_id = "counter"
	occupied.cell = Vector2i(2, 0)
	var placements: Array[StoreFurniturePlacement] = [moving, occupied]
	var footprints := {"counter": Vector2i(2, 1)}
	var grid_size := Vector2i(5, 3)
	_expect(
		InteriorLayoutValidator.is_valid_placement(moving, Vector2i(0, 1), grid_size, placements, footprints),
		"拖拽到空闲网格可放置"
	)
	_expect(
		not InteriorLayoutValidator.is_valid_placement(moving, Vector2i(2, 0), grid_size, placements, footprints),
		"拖拽到已占用网格被拒绝"
	)
	_expect(
		not InteriorLayoutValidator.is_valid_placement(moving, Vector2i(4, 1), grid_size, placements, footprints),
		"拖拽越界被拒绝"
	)
	moving.rotation = 1
	_expect(
		not InteriorLayoutValidator.is_valid_placement(moving, Vector2i(4, 2), grid_size, placements, footprints),
		"旋转后拖拽越界被拒绝"
	)
	moving.rotation = 0
	moving.cell = Vector2i(0, 1)
	var store := Store.new()
	store.furniture_layout.append(moving)
	var restored := Store.from_save_dict(store.to_save_dict())
	_expect(
		restored.furniture_layout[0].cell == Vector2i(0, 1),
		"拖拽落位后的存档往返保留位置"
	)


func _test_canvas_entrance_and_equipment_labels() -> void:
	var canvas := InteriorCanvas.new()
	canvas.size = Vector2(400.0, 300.0)
	add_child(canvas)
	var entrance_cells: Array[Vector2i] = [Vector2i(2, 3), Vector2i(3, 3)]
	canvas.setup(Vector2i(6, 4), [], null, entrance_cells, {"steamer": "商用蒸箱"})
	_expect(canvas.get_entrance_marker_cells() == entrance_cells, "南侧入口映射为室内 2D 下边连续门槛")
	_expect(canvas.get_equipment_display_name("steamer") == "商用蒸箱", "室内 2D 可按设备 ID 解析完整中文名称")
	var east_storefront := StorefrontData.new()
	east_storefront.grid_cells = [Vector2i(0, 0), Vector2i(1, 0)]
	east_storefront.frontage_side = "east"
	var east_geometry := StorefrontLayoutGeometry.from_storefront(east_storefront)
	var east_entrance: Array[Vector2i] = [Vector2i(13, 2), Vector2i(13, 3)]
	canvas.setup(east_geometry.grid_size, [], east_geometry, east_entrance, {})
	_expect(canvas.grid_size == east_geometry.get_display_grid_size() and canvas.get_entrance_marker_cells() == [Vector2i(4, 13), Vector2i(3, 13)], "东向门面 2D 使用显示网格并将入口绘制在下边")
	canvas.setup(Vector2i(6, 4), [], null, [], {"steamer": "商用蒸箱"})
	_expect(canvas.get_entrance_marker_cells().is_empty(), "删除入口后室内 2D 不再绘制门槛")
	canvas.queue_free()


func _test_operational_layout_effects() -> void:
	var store := Store.new()
	var owned := StoreEquipment.new()
	owned.instance_id = "owned_steamer"
	owned.equipment_id = "steamer"
	store.equipment.append(owned)
	_expect(not StoreLayoutEffects.has_placed_equipment(store, "steamer"), "未摆放设备不视为营业可用")
	var furniture := StoreFurniturePlacement.new()
	furniture.instance_id = "owned_steamer"
	furniture.equipment_id = "steamer"
	store.furniture_layout.append(furniture)
	_expect(StoreLayoutEffects.has_placed_equipment(store, "steamer"), "已摆放设备视为营业可用")
	var signboard := StoreFacadePlacement.new()
	signboard.type = "signboard"
	store.facade_layout.append(signboard)
	var first_window := StoreFacadePlacement.new()
	first_window.type = "window"
	store.facade_layout.append(first_window)
	var second_window := StoreFacadePlacement.new()
	second_window.type = "window"
	store.facade_layout.append(second_window)
	_expect(is_equal_approx(StoreLayoutEffects.get_capture_multiplier(store), 1.10), "招牌提供固定进店截获加成")
	_expect(is_equal_approx(StoreLayoutEffects.get_awareness_multiplier(store), 1.08 * 1.08), "两扇橱窗提供可叠加的知名度加成")
	var candidate := StoreFurniturePlacement.new()
	candidate.equipment_id = "steamer"
	_expect(not InteriorLayoutValidator.is_valid_placement(candidate, Vector2i(1, 3), Vector2i(5, 4), [], {"steamer": Vector2i.ONE}, {}, [Vector2i(1, 3), Vector2i(2, 3)]), "入口净空格拒绝家具摆放")
