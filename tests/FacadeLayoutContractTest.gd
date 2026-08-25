extends Node

var _passed := 0
var _failed := 0


func _ready() -> void:
	_test_footprints_and_bounds()
	_test_overlap_and_limits()
	_test_drag_validation()
	_test_3d_projection()
	_test_3d_canvas_initialization()
	_test_texture_decals()
	_test_store_layout_round_trip()
	_test_legacy_store_compatibility()
	print("========== 门面布局测试：%d 通过 / %d 失败 ==========" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("✓ %s" % description)
	else:
		_failed += 1
		print("✗ %s" % description)


func _placement(type: String, cell: Vector2i) -> StoreFacadePlacement:
	var placement := StoreFacadePlacement.new()
	placement.type = type
	placement.cell = cell
	return placement


func _test_footprints_and_bounds() -> void:
	_expect(FacadeLayoutValidator.get_footprint_size("signboard") == Vector2i(4, 1), "招牌占用 4×1 网格")
	_expect(FacadeLayoutValidator.get_footprint_size("entrance") == Vector2i(2, 3), "入口占用 2×3 网格")
	_expect(FacadeLayoutValidator.get_footprint_size("window") == Vector2i(3, 3), "橱窗占用 3×3 网格")
	var signboard := _placement("signboard", Vector2i(8, 0))
	_expect(FacadeLayoutValidator.is_valid_placement(signboard, signboard.cell, []), "贴近右边界的招牌可放置")
	_expect(not FacadeLayoutValidator.is_valid_placement(signboard, Vector2i(9, 0), []), "越出右边界的招牌被拒绝")
	var entrance := _placement("entrance", Vector2i(0, 3))
	_expect(not FacadeLayoutValidator.is_valid_placement(entrance, entrance.cell, []), "越出下边界的入口被拒绝")


func _test_overlap_and_limits() -> void:
	var signboard := _placement("signboard", Vector2i(0, 0))
	var entrance := _placement("entrance", Vector2i(0, 1))
	var placements: Array[StoreFacadePlacement] = [signboard, entrance]
	_expect(not FacadeLayoutValidator.is_valid_placement(_placement("window", Vector2i(1, 1)), Vector2i(1, 1), placements), "重叠组件被拒绝")
	_expect(FacadeLayoutValidator.can_add_type("window", placements), "可添加第一个橱窗")
	placements.append(_placement("window", Vector2i(3, 1)))
	placements.append(_placement("window", Vector2i(6, 1)))
	_expect(not FacadeLayoutValidator.can_add_type("window", placements), "第三个橱窗被数量限制拒绝")
	_expect(not FacadeLayoutValidator.can_add_type("signboard", placements), "第二个招牌被数量限制拒绝")
	_expect(not FacadeLayoutValidator.can_add_type("entrance", placements), "第二个入口被数量限制拒绝")


func _test_drag_validation() -> void:
	var signboard := _placement("signboard", Vector2i(0, 0))
	var entrance := _placement("entrance", Vector2i(5, 1))
	var placements: Array[StoreFacadePlacement] = [signboard, entrance]
	_expect(FacadeLayoutValidator.is_valid_placement(signboard, Vector2i(0, 4), placements), "拖拽招牌到空白位置可提交")
	_expect(not FacadeLayoutValidator.is_valid_placement(signboard, Vector2i(4, 1), placements), "拖拽到入口重叠区域被拒绝")
	_expect(not FacadeLayoutValidator.is_valid_placement(signboard, Vector2i(10, 4), placements), "拖拽越界被拒绝且应保持原位置")


func _test_3d_projection() -> void:
	_expect(FacadeProjection3D.get_world_position("signboard", Vector2i(0, 0)) == Vector3(-2.0, 2.25, 0.26), "左上招牌投影到墙面正确位置")
	_expect(FacadeProjection3D.get_world_position("window", Vector2i(9, 2)) == Vector3(2.25, 0.75, 0.26), "右下区域橱窗投影到墙面正确位置")
	_expect(FacadeProjection3D.get_world_size("entrance") == Vector3(1.0, 1.5, FacadeProjection3D.COMPONENT_DEPTH), "入口投影尺寸与 0.25㎡格一致")
	_expect(FacadeProjection3D.world_point_to_cell(Vector3(-2.95, 2.45, 0.2)) == Vector2i(0, 0), "墙面左上命中点可反算为网格坐标")
	_expect(FacadeProjection3D.world_point_to_cell(Vector3(2.95, 0.05, 0.2)) == Vector2i(11, 4), "墙面右下命中点可反算为网格坐标")
	var entrance := _placement("entrance", Vector2i(5, 1))
	var placements: Array[StoreFacadePlacement] = [entrance]
	var dragged := _placement("window", Vector2i(0, 0))
	_expect(not FacadeLayoutValidator.is_valid_placement(dragged, FacadeProjection3D.world_point_to_cell(Vector3(0.0, 2.5, 0.2)), placements), "3D 命中位置仍复用重叠校验")


func _test_3d_canvas_initialization() -> void:
	var canvas := Facade3DCanvas.new()
	canvas.size = Vector2(800.0, 500.0)
	add_child(canvas)
	canvas.setup([_placement("signboard", Vector2i(4, 0))])
	_expect(canvas.get_child_count() == 1 and canvas.get_child(0) is SubViewport, "3D 门面画布可创建独立 SubViewport")
	_expect(canvas.is_using_orthographic_camera() and not canvas.allows_vertical_camera_rotation(), "门面 3D 使用正交相机且只允许水平旋转")
	canvas.queue_free()


func _test_texture_decals() -> void:
	var source := LayoutSpriteCatalog.get_facade_region(Vector2(1869.0, 842.0), "window")
	var fitted := LayoutSpriteCatalog.fit_source_in_rect(source.size, Rect2(Vector2.ZERO, Vector2(1.5, 1.5)), 0.04)
	var atlas := load(LayoutSpriteCatalog.FACADE_ATLAS_PATH) as Texture2D
	var cropped := LayoutSpriteCatalog.get_facade_3d_texture(atlas, "window")
	_expect(source == Rect2(Vector2(1246.0, 0.0), Vector2(623.0, 842.0)), "门面图集可按组件类型裁切到正确单元")
	_expect(LayoutSpriteCatalog.get_facade_region(Vector2(1869.0, 842.0), "unknown") == Rect2(), "未知门面组件不生成纹理区域并回退到色块")
	_expect(cropped != null and cropped.get_size() == Vector2(623.0, 842.0) and cropped.get_size() != atlas.get_size() and LayoutSpriteCatalog.get_facade_3d_texture(atlas, "window") == cropped, "门面 3D 纹理是复用缓存的独立图集单元")
	_expect(fitted.size.x <= 1.42 and fitted.size.y <= 1.42 and is_equal_approx(fitted.size.x / fitted.size.y, source.size.x / source.size.y), "门面贴花等比限制在组件正面安全范围内")
	var canvas := Facade3DCanvas.new()
	add_child(canvas)
	var body := canvas._add_box(canvas._component_root, Vector3(1.5, 1.5, 0.18), Vector3.ZERO, Color.WHITE)
	canvas._add_component_front_decal(body, Vector3(1.5, 1.5, 0.18), "window")
	var body_material := body.material_override as StandardMaterial3D
	var decal := body.get_node_or_null("FrontDecal") as MeshInstance3D
	var decal_material := decal.material_override as StandardMaterial3D if decal != null else null
	_expect(body_material != null and body_material.albedo_texture == null and decal_material != null and decal_material.albedo_texture is ImageTexture and not decal_material.texture_repeat, "门面盒体保持纯色，正面只使用独立且不重复的贴花")
	var face_names := ["TopDecal", "FrontDecal", "BackSurface", "LeftSurface", "RightSurface"]
	var all_faces_exist := true
	for face_name in face_names:
		all_faces_exist = all_faces_exist and body.get_node_or_null(face_name) is MeshInstance3D
	_expect(all_faces_exist and body.get_node_or_null("BottomSurface") == null, "门面组件创建五个可见面且不创建底面")
	var top_material := (body.get_node_or_null("TopDecal") as MeshInstance3D).material_override as StandardMaterial3D
	var back_material := (body.get_node_or_null("BackSurface") as MeshInstance3D).material_override as StandardMaterial3D
	var right := body.get_node_or_null("RightSurface") as MeshInstance3D
	var right_mesh := right.mesh as PlaneMesh if right != null else null
	_expect(top_material.albedo_texture is ImageTexture and back_material.albedo_texture == null and right_mesh.size == Vector2(0.18, 1.5), "门面顶/正面使用贴图，三侧保持主色并贴合盒体")
	var unknown_body := canvas._add_box(canvas._component_root, Vector3.ONE, Vector3.ZERO, Color.WHITE)
	canvas._add_component_front_decal(unknown_body, Vector3.ONE, "unknown")
	_expect(unknown_body.get_child_count() == 0, "未知门面组件不创建五面贴图装饰")
	canvas.queue_free()


func _test_store_layout_round_trip() -> void:
	var store := Store.new()
	var furniture := StoreFurniturePlacement.new()
	furniture.instance_id = "equipment_1"
	furniture.equipment_id = "steamer"
	furniture.cell = Vector2i(2, 1)
	store.furniture_layout.append(furniture)
	store.facade_layout.append(_placement("signboard", Vector2i(4, 0)))
	store.facade_layout.append(_placement("entrance", Vector2i(5, 2)))
	var restored := Store.from_save_dict(store.to_save_dict())
	_expect(restored.furniture_layout.size() == 1 and restored.furniture_layout[0].cell == Vector2i(2, 1), "室内家具布局与门面布局可共同存档")
	_expect(restored.facade_layout.size() == 2, "门面布局存档往返保留所有组件")
	_expect(restored.facade_layout[0].type == "signboard" and restored.facade_layout[0].cell == Vector2i(4, 0), "门面组件类型与位置可往返保存")


func _test_legacy_store_compatibility() -> void:
	var legacy_data := Store.new().to_save_dict()
	legacy_data.erase("facade_layout")
	var restored := Store.from_save_dict(legacy_data)
	_expect(restored.facade_layout.is_empty(), "不含门面布局字段的旧存档兼容加载")
