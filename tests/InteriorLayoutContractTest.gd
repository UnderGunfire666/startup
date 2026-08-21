extends Node

var _passed := 0
var _failed := 0

func _ready() -> void:
	_test_rotation_footprint()
	_test_drag_placement_validation()
	_test_store_layout_round_trip()
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
