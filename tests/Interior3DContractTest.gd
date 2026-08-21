extends Node

var _passed := 0
var _failed := 0


func _ready() -> void:
	_test_projection()
	_test_storefront_geometry()
	_test_entrance_mapping()
	_test_drag_validation()
	_test_canvas_initialization()
	print("========== 室内 3D 测试：%d 通过 / %d 失败 ==========" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("✓ %s" % description)
	else:
		_failed += 1
		print("✗ %s" % description)


func _test_projection() -> void:
	var grid_size := Vector2i(5, 4)
	_expect(InteriorProjection3D.get_rotated_footprint(Vector2i(2, 1), 1) == Vector2i(1, 2), "室内设备旋转后占格方向正确")
	_expect(InteriorProjection3D.get_world_size(Vector2i(2, 1), 1) == Vector3(0.5, InteriorProjection3D.EQUIPMENT_HEIGHT, 1.0), "室内设备旋转后投影尺寸正确")
	_expect(InteriorProjection3D.get_world_position(Vector2i(1, 1), Vector2i(2, 1), 1, grid_size) == Vector3(-0.5, InteriorProjection3D.EQUIPMENT_HEIGHT * 0.5, 0.0), "室内格坐标可映射到 3D 地面位置")
	_expect(InteriorProjection3D.world_point_to_cell(Vector3(-1.2, 0.0, -0.95), grid_size) == Vector2i(0, 0), "室内左上地面命中点可反算为格坐标")
	_expect(InteriorProjection3D.world_point_to_cell(Vector3(1.2, 0.0, 0.95), grid_size) == Vector2i(4, 3), "室内右下地面命中点可反算为格坐标")


func _test_storefront_geometry() -> void:
	var storefront := StorefrontData.new()
	storefront.id = "sf_nw_grocery"
	storefront.grid_cells = [Vector2i(0, 0), Vector2i(1, 0)]
	storefront.frontage_side = "south"
	var geometry := StorefrontLayoutGeometry.from_storefront(storefront)
	_expect(StorefrontLayoutGeometry.CELLS_PER_CITY_CELL == 7 and is_equal_approx(StorefrontLayoutGeometry.CELL_AREA_SQM, 0.25), "城市地图格精确细分为 7×7 个 0.25㎡格")
	_expect(geometry.grid_size == Vector2i(14, 7) and geometry.available_cells.size() == 98, "社区生鲜铺双地图格生成真实室内轮廓")
	_expect(geometry.get_facade_grid_size() == Vector2i(14, 7), "社区生鲜铺门头宽度与室内临街边界均为 14 格")
	var l_shape := StorefrontData.new()
	l_shape.grid_cells = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	var l_geometry := StorefrontLayoutGeometry.from_storefront(l_shape)
	_expect(l_geometry.is_available(Vector2i(0, 0)) and not l_geometry.is_available(Vector2i(13, 13)), "转角门面的非矩形区域不会成为可摆放空间")


func _test_entrance_mapping() -> void:
	var entrance := StoreFacadePlacement.new()
	entrance.type = "entrance"
	entrance.cell = Vector2i(4, 1)
	var layout: Array[StoreFacadePlacement] = [entrance]
	_expect(is_equal_approx(InteriorProjection3D.get_entrance_center_x(layout, 8), 5.0 / 12.0 * 8.0), "门面入口横向位置按比例映射到室内前墙")
	_expect(is_equal_approx(InteriorProjection3D.get_entrance_center_x([], 7), 3.5), "缺少门面入口时室内入口居中")


func _test_drag_validation() -> void:
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
	_expect(InteriorLayoutValidator.is_valid_placement(moving, Vector2i(0, 2), Vector2i(5, 4), placements, footprints), "室内 3D 可复用有效拖放校验")
	_expect(not InteriorLayoutValidator.is_valid_placement(moving, Vector2i(2, 0), Vector2i(5, 4), placements, footprints), "室内 3D 重叠目标被拒绝")
	_expect(not InteriorLayoutValidator.is_valid_placement(moving, Vector2i(4, 3), Vector2i(5, 4), placements, footprints), "室内 3D 越界目标被拒绝")


func _test_canvas_initialization() -> void:
	var canvas := Interior3DCanvas.new()
	canvas.size = Vector2(700.0, 500.0)
	add_child(canvas)
	canvas.setup(Vector2i(5, 4), [], {}, [])
	_expect(canvas.get_child_count() == 1 and canvas.get_child(0) is SubViewport, "室内 3D 画布可创建独立 SubViewport")
	_expect(canvas.is_using_orthographic_camera() and not canvas.allows_vertical_camera_rotation(), "室内 3D 使用正交相机且只允许水平旋转")
	canvas.queue_free()
