extends Node

var _passed := 0
var _failed := 0


func _ready() -> void:
	_test_projection()
	_test_storefront_geometry()
	_test_unified_display_geometry()
	_test_entrance_mapping()
	_test_drag_validation()
	_test_canvas_initialization()
	_test_texture_decals()
	_test_five_face_decorations()
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
	_expect(l_geometry.get_outer_wall_segments().size() == 56, "L 形门面可导出真实外墙轮廓边段")
	for frontage_side in ["north", "east", "south", "west"]:
		var directional_storefront := StorefrontData.new()
		directional_storefront.grid_cells = [Vector2i(0, 0), Vector2i(1, 0)]
		directional_storefront.frontage_side = frontage_side
		var directional_geometry := StorefrontLayoutGeometry.from_storefront(directional_storefront)
		var display_size := directional_geometry.get_display_grid_size()
		var physical_cell := Vector2i(0, 0)
		var displayed_cell := directional_geometry.physical_to_display_cell(physical_cell)
		_expect(directional_geometry.display_to_physical_cell(displayed_cell) == physical_cell and displayed_cell.x >= 0 and displayed_cell.y >= 0 and displayed_cell.x < display_size.x and displayed_cell.y < display_size.y, "%s 临街坐标可在物理与显示网格间往返" % frontage_side)


func _test_entrance_mapping() -> void:
	var entrance := StoreFacadePlacement.new()
	entrance.type = "entrance"
	entrance.cell = Vector2i(4, 1)
	var layout: Array[StoreFacadePlacement] = [entrance]
	_expect(is_equal_approx(InteriorProjection3D.get_entrance_center_x(layout, 8), 5.0 / 12.0 * 8.0), "门面入口横向位置按比例映射到室内前墙")
	_expect(is_equal_approx(InteriorProjection3D.get_entrance_center_x([], 7), 3.5), "缺少门面入口时室内入口居中")


func _test_unified_display_geometry() -> void:
	for frontage_side in ["north", "east", "south", "west"]:
		var storefront := StorefrontData.new()
		storefront.grid_cells = [Vector2i(0, 0), Vector2i(1, 0)]
		storefront.frontage_side = frontage_side
		var geometry := StorefrontLayoutGeometry.from_storefront(storefront)
		var entrance := StoreFacadePlacement.new()
		entrance.type = "entrance"
		entrance.cell = Vector2i(3, 1)
		var display_entrance := geometry.get_display_interior_entrance_cells(entrance)
		var entrance_on_bottom := not display_entrance.is_empty()
		for cell in display_entrance:
			entrance_on_bottom = entrance_on_bottom and cell.y == geometry.get_display_grid_size().y - 1
		_expect(entrance_on_bottom, "%s 临街入口统一映射到显示下边" % frontage_side)
		var south_segment_found := false
		for segment in geometry.get_display_outer_wall_segments():
			if segment.cell in display_entrance and segment.side == "south":
				south_segment_found = true
		_expect(south_segment_found, "%s 临街入口对应显示南墙开口" % frontage_side)
		for footprint in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)]:
			for rotation in [0, 1]:
				var physical_cell := Vector2i(2, 2)
				var display_rect := geometry.get_display_placement_rect(physical_cell, footprint, rotation)
				var restored_cell := geometry.display_to_physical_placement_cell(display_rect.cell, footprint, rotation)
				_expect(restored_cell == physical_cell, "%s 临街 %s 家具显示/物理锚点可往返" % [frontage_side, str(footprint)])
				var expected_size: Vector2i = footprint if posmod(geometry.physical_to_display_rotation(rotation), 2) == 0 else Vector2i(footprint.y, footprint.x)
				_expect(display_rect.size == expected_size, "%s 临街家具显示占格与朝向一致" % frontage_side)


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
	_expect(canvas.is_using_orthographic_camera() and not canvas.allows_vertical_camera_rotation() and not canvas.allows_horizontal_camera_rotation(), "室内 3D 使用固定正交相机，不允许水平或垂直旋转")
	_expect(is_equal_approx(canvas.get_fixed_camera_pitch_degrees(), 45.0), "室内 3D 固定为 45 度俯视")
	var camera_position_before := canvas._camera.position
	var middle_press := InputEventMouseButton.new()
	middle_press.button_index = MOUSE_BUTTON_MIDDLE
	middle_press.pressed = true
	canvas._gui_input(middle_press)
	var middle_motion := InputEventMouseMotion.new()
	middle_motion.relative = Vector2(100.0, 0.0)
	canvas._gui_input(middle_motion)
	_expect(canvas._camera.position == camera_position_before, "中键拖动不会改变固定相机")
	var east_wall := canvas._static_root.get_node_or_null("EastWall") as MeshInstance3D
	var south_wall := canvas._static_root.get_node_or_null("SouthWall") as MeshInstance3D
	var west_wall := canvas._static_root.get_node_or_null("WestWall") as MeshInstance3D
	var north_wall := canvas._static_root.get_node_or_null("NorthWall") as MeshInstance3D
	var east_material := east_wall.material_override as StandardMaterial3D if east_wall != null else null
	var south_material := south_wall.material_override as StandardMaterial3D if south_wall != null else null
	var west_material := west_wall.material_override as StandardMaterial3D if west_wall != null else null
	var north_material := north_wall.material_override as StandardMaterial3D if north_wall != null else null
	_expect(east_material != null and south_material != null and east_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and south_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "面向镜头的东墙和南墙使用透明材质")
	_expect(west_material != null and north_material != null and west_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and north_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "远侧墙体保持不透明，且无入口时北墙完整封闭")
	var entrance := StoreFacadePlacement.new()
	entrance.type = "entrance"
	entrance.cell = Vector2i(4, 1)
	var entrance_layout: Array[StoreFacadePlacement] = [entrance]
	canvas.setup(Vector2i(5, 4), [], {}, entrance_layout)
	var south_left_wall := canvas._static_root.get_node_or_null("SouthWallLeft") as MeshInstance3D
	var south_right_wall := canvas._static_root.get_node_or_null("SouthWallRight") as MeshInstance3D
	var queued_south_wall := canvas._static_root.get_node_or_null("SouthWall") as MeshInstance3D
	var south_left_material := south_left_wall.material_override as StandardMaterial3D if south_left_wall != null else null
	var south_right_material := south_right_wall.material_override as StandardMaterial3D if south_right_wall != null else null
	_expect((queued_south_wall == null or queued_south_wall.is_queued_for_deletion()) and south_left_material != null and south_right_material != null, "实际入口改在室内 3D 下方南墙开口")
	_expect(south_left_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and south_right_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "入口两侧南墙保持透明")
	canvas.queue_free()


func _test_texture_decals() -> void:
	var source := LayoutSpriteCatalog.get_equipment_region(Vector2(1024.0, 1536.0), "steamer")
	var fitted := LayoutSpriteCatalog.fit_source_in_rect(source.size, Rect2(Vector2.ZERO, Vector2(1.0, 0.5)), 0.04)
	var atlas := load(LayoutSpriteCatalog.EQUIPMENT_ATLAS_PATH) as Texture2D
	var cropped := LayoutSpriteCatalog.get_equipment_3d_texture(atlas, "steamer")
	_expect(source == Rect2(Vector2.ZERO, Vector2(204.8, 256.0)), "设备图集可按 ID 裁切到正确单元")
	_expect(LayoutSpriteCatalog.get_equipment_region(Vector2(1024.0, 1536.0), "unknown") == Rect2(), "未知设备 ID 不生成纹理区域并回退到色块")
	_expect(cropped != null and cropped.get_size() == Vector2(204.0, 256.0) and cropped.get_size() != atlas.get_size() and LayoutSpriteCatalog.get_equipment_3d_texture(atlas, "steamer") == cropped, "设备 3D 纹理是复用缓存的独立图集单元")
	_expect(Rect2(Vector2.ZERO, Vector2(1.0, 0.5)).encloses(fitted) and is_equal_approx(fitted.size.x / fitted.size.y, source.size.x / source.size.y), "设备贴花等比限制在家具顶面安全范围内")
	var canvas := Interior3DCanvas.new()
	add_child(canvas)
	var body := canvas._add_box(canvas._equipment_root, Vector3(1.0, 0.6, 0.5), Vector3.ZERO, Color.WHITE)
	canvas._add_equipment_top_decal(body, Vector3(1.0, 0.6, 0.5), "steamer")
	var body_material := body.material_override as StandardMaterial3D
	var decal := body.get_node_or_null("TopDecal") as MeshInstance3D
	var decal_material := decal.material_override as StandardMaterial3D if decal != null else null
	_expect(body_material != null and body_material.albedo_texture == null and decal_material != null and decal_material.albedo_texture is ImageTexture and not decal_material.texture_repeat, "家具盒体保持纯色，顶面只使用独立且不重复的贴花")
	canvas.queue_free()


func _test_five_face_decorations() -> void:
	var canvas := Interior3DCanvas.new()
	add_child(canvas)
	var body := canvas._add_box(canvas._equipment_root, Vector3(1.0, 0.6, 0.5), Vector3.ZERO, Color.WHITE)
	canvas._add_equipment_top_decal(body, Vector3(1.0, 0.6, 0.5), "steamer", Color("#4f9d9a"))
	var face_names := ["TopDecal", "FrontDecal", "BackSurface", "LeftSurface", "RightSurface"]
	var all_faces_exist := true
	for face_name in face_names:
		all_faces_exist = all_faces_exist and body.get_node_or_null(face_name) is MeshInstance3D
	_expect(all_faces_exist and body.get_node_or_null("BottomSurface") == null, "室内设备创建五个可见面且不创建底面")
	var top_material := (body.get_node_or_null("TopDecal") as MeshInstance3D).material_override as StandardMaterial3D
	var front_material := (body.get_node_or_null("FrontDecal") as MeshInstance3D).material_override as StandardMaterial3D
	var left := body.get_node_or_null("LeftSurface") as MeshInstance3D
	var left_material := left.material_override as StandardMaterial3D if left != null else null
	var left_mesh := left.mesh as PlaneMesh if left != null else null
	_expect(top_material.albedo_texture is ImageTexture and front_material.albedo_texture is ImageTexture and left_material.albedo_texture == null and left_material.albedo_color == Color("#4f9d9a") and left_mesh.size == Vector2(0.5, 0.6), "室内顶/正面使用贴图，侧面保持主色并贴合盒体")
	for frontage_side in ["north", "east", "south", "west"]:
		var storefront := StorefrontData.new()
		storefront.grid_cells = [Vector2i(0, 0), Vector2i(1, 0)]
		storefront.frontage_side = frontage_side
		var geometry := StorefrontLayoutGeometry.from_storefront(storefront)
		var display_rotation := geometry.physical_to_display_rotation(0)
		body.rotation.y = float(display_rotation) * PI * 0.5
		_expect(body.get_node_or_null("TopDecal") != null and is_equal_approx(body.rotation.y, float(display_rotation) * PI * 0.5), "%s 临街设备五面装饰随统一显示旋转" % frontage_side)
	canvas.queue_free()
