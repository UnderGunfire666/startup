class_name Interior3DCanvas
extends SubViewportContainer

signal cell_pressed(cell: Vector2i)
signal placement_drag_started(instance_id: String)
signal placement_drag_previewed(instance_id: String, cell: Vector2i)
signal placement_drop_requested(instance_id: String, cell: Vector2i)

const CAMERA_YAW_LIMIT := PI
const CAMERA_ORTHOGONAL_SIZE_MIN := 5.0
const CAMERA_ORTHOGONAL_SIZE_MAX := 22.0

var grid_size := Vector2i(5, 5)
var placements: Array[StoreFurniturePlacement] = []
var footprints: Dictionary = {}
var facade_layout: Array[StoreFacadePlacement] = []
var layout_geometry: StorefrontLayoutGeometry = null
var selected_instance_id := ""
var dragging_instance_id := ""
var drag_start_position := Vector2.ZERO
var drag_preview_cell := Vector2i.ZERO
var drag_preview_valid := false
var drag_has_moved := false
var camera_yaw := 0.0
var camera_orthogonal_size := 9.0
var orbiting := false

var _viewport: SubViewport
var _world_root: Node3D
var _static_root: Node3D
var _equipment_root: Node3D
var _preview_root: Node3D
var _camera: Camera3D


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	add_child(_viewport)
	_world_root = Node3D.new()
	_viewport.add_child(_world_root)
	_create_world()
	_rebuild_scene()


func setup(size: Vector2i, layout: Array[StoreFurniturePlacement], footprint_sizes: Dictionary, current_facade_layout: Array[StoreFacadePlacement], geometry: StorefrontLayoutGeometry = null) -> void:
	grid_size = size
	placements = layout
	footprints = footprint_sizes
	facade_layout = current_facade_layout
	layout_geometry = geometry
	camera_orthogonal_size = clampf(maxf(float(grid_size.x), float(grid_size.y)) * 1.45, CAMERA_ORTHOGONAL_SIZE_MIN, CAMERA_ORTHOGONAL_SIZE_MAX)
	if is_instance_valid(_static_root):
		_rebuild_scene()


func set_selected(instance_id: String) -> void:
	selected_instance_id = instance_id
	if is_instance_valid(_equipment_root):
		_rebuild_scene()


func set_drag_preview_valid(is_valid: bool) -> void:
	drag_preview_valid = is_valid
	if is_instance_valid(_preview_root):
		_rebuild_preview()


func is_using_orthographic_camera() -> bool:
	return _camera != null and _camera.projection == Camera3D.PROJECTION_ORTHOGONAL


func allows_vertical_camera_rotation() -> bool:
	return false


func _create_world() -> void:
	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color("#101a22")
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color("#d8e4ed")
	environment_resource.ambient_light_energy = 0.7
	environment.environment = environment_resource
	_world_root.add_child(environment)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	key_light.light_energy = 1.15
	_world_root.add_child(key_light)
	_static_root = Node3D.new()
	_world_root.add_child(_static_root)
	_equipment_root = Node3D.new()
	_world_root.add_child(_equipment_root)
	_preview_root = Node3D.new()
	_world_root.add_child(_preview_root)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_world_root.add_child(_camera)
	_update_camera()


func _rebuild_scene() -> void:
	for root in [_static_root, _equipment_root]:
		for child in root.get_children():
			child.queue_free()
	_create_static_geometry()
	for placement in placements:
		if placement.instance_id == dragging_instance_id and drag_has_moved:
			continue
		_draw_equipment(_equipment_root, placement, placement.cell, false, true)
	_rebuild_preview()
	_update_camera()


func _create_static_geometry() -> void:
	if layout_geometry != null:
		for cell in layout_geometry.get_available_cell_array():
			var floor_position := InteriorProjection3D.get_world_position(cell, Vector2i.ONE, 0, grid_size)
			floor_position.y = -0.07
			_add_box(_static_root, Vector3(InteriorProjection3D.CELL_WORLD_SIZE, 0.14, InteriorProjection3D.CELL_WORLD_SIZE), floor_position, Color("#263842"))
	else:
		var floor_size := Vector3(float(grid_size.x) * InteriorProjection3D.CELL_WORLD_SIZE, 0.14, float(grid_size.y) * InteriorProjection3D.CELL_WORLD_SIZE)
		_add_box(_static_root, floor_size, Vector3(0.0, -0.07, 0.0), Color("#263842"))
	var grid_color := Color(0.65, 0.78, 0.84, 0.32)
	for x in range(grid_size.x + 1):
		_add_box(_static_root, Vector3(0.018, 0.02, float(grid_size.y) * InteriorProjection3D.CELL_WORLD_SIZE), Vector3((float(x) - float(grid_size.x) * 0.5) * InteriorProjection3D.CELL_WORLD_SIZE, 0.015, 0.0), grid_color, true)
	for z in range(grid_size.y + 1):
		_add_box(_static_root, Vector3(float(grid_size.x) * InteriorProjection3D.CELL_WORLD_SIZE, 0.02, 0.018), Vector3(0.0, 0.015, (float(z) - float(grid_size.y) * 0.5) * InteriorProjection3D.CELL_WORLD_SIZE), grid_color, true)
	var wall_color := Color("#435762")
	var half_x := float(grid_size.x) * InteriorProjection3D.CELL_WORLD_SIZE * 0.5
	var half_z := float(grid_size.y) * InteriorProjection3D.CELL_WORLD_SIZE * 0.5
	_add_box(_static_root, Vector3(0.16, 2.4, float(grid_size.y) * InteriorProjection3D.CELL_WORLD_SIZE), Vector3(-half_x, 1.2, 0.0), wall_color)
	_add_box(_static_root, Vector3(0.16, 2.4, float(grid_size.y) * InteriorProjection3D.CELL_WORLD_SIZE), Vector3(half_x, 1.2, 0.0), wall_color)
	_add_box(_static_root, Vector3(float(grid_size.x) * InteriorProjection3D.CELL_WORLD_SIZE, 2.4, 0.16), Vector3(0.0, 1.2, half_z), wall_color)
	var entrance: StoreFacadePlacement = null
	for placement in facade_layout:
		if placement.type == "entrance":
			entrance = placement
			break
	if entrance == null:
		return
	var entrance_center := InteriorProjection3D.get_entrance_center_x(facade_layout, grid_size.x) * InteriorProjection3D.CELL_WORLD_SIZE - half_x
	if layout_geometry != null:
		var entrance_cells := layout_geometry.get_interior_entrance_cells(entrance)
		if not entrance_cells.is_empty():
			var x_total := 0.0
			for entrance_cell in entrance_cells:
				x_total += (float(entrance_cell.x) + 0.5) * InteriorProjection3D.CELL_WORLD_SIZE - half_x
			entrance_center = x_total / float(entrance_cells.size())
	var opening_width := minf(float(StorefrontLayoutGeometry.ENTRANCE_WIDTH_CELLS) * InteriorProjection3D.CELL_WORLD_SIZE, maxf(InteriorProjection3D.CELL_WORLD_SIZE, float(grid_size.x) * InteriorProjection3D.CELL_WORLD_SIZE - 0.5))
	var left_width := maxf(0.0, entrance_center - opening_width * 0.5 + half_x)
	var right_width := maxf(0.0, half_x - (entrance_center + opening_width * 0.5))
	if left_width > 0.0:
		_add_box(_static_root, Vector3(left_width, 2.4, 0.16), Vector3(-half_x + left_width * 0.5, 1.2, -half_z), wall_color)
	if right_width > 0.0:
		_add_box(_static_root, Vector3(right_width, 2.4, 0.16), Vector3(half_x - right_width * 0.5, 1.2, -half_z), wall_color)
	_add_box(_static_root, Vector3(opening_width, 0.05, 0.28), Vector3(entrance_center, 0.025, -half_z), Color("#63c6a6"), true)


func _draw_equipment(parent: Node3D, placement: StoreFurniturePlacement, cell: Vector2i, preview: bool, valid: bool) -> void:
	var footprint := _get_footprint(placement.equipment_id)
	var instance := _add_box(parent, Vector3(float(footprint.x) * InteriorProjection3D.CELL_WORLD_SIZE, InteriorProjection3D.EQUIPMENT_HEIGHT, float(footprint.y) * InteriorProjection3D.CELL_WORLD_SIZE), InteriorProjection3D.get_world_position(cell, footprint, placement.rotation, grid_size), Color("#63c6a6", 0.55) if preview and valid else Color("#e06c75", 0.55) if preview else Color("#d7824b") if placement.instance_id == selected_instance_id else Color("#4f9d9a"), preview)
	instance.rotation.y = float(posmod(placement.rotation, 4)) * PI * 0.5


func _rebuild_preview() -> void:
	for child in _preview_root.get_children():
		child.queue_free()
	if not dragging_instance_id.is_empty() and drag_has_moved:
		var placement := _find_placement(dragging_instance_id)
		if placement != null:
			_draw_equipment(_preview_root, placement, drag_preview_cell, true, drag_preview_valid)


func _add_box(parent: Node3D, box_size: Vector3, position: Vector3, color: Color, transparent: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	instance.mesh = mesh
	instance.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _update_camera() -> void:
	if _camera == null:
		return
	var camera_distance := maxf(float(grid_size.x), float(grid_size.y)) * 2.2 + 4.0
	var target := Vector3(0.0, 0.0, 0.0)
	_camera.position = target + Vector3(sin(camera_yaw) * camera_distance, camera_distance * 0.9, cos(camera_yaw) * camera_distance)
	_camera.size = camera_orthogonal_size
	_camera.look_at(target, Vector3.UP)


func _get_floor_cell(position: Vector2) -> Vector2i:
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(_camera.project_ray_origin(position), _camera.project_ray_normal(position))
	if hit == null:
		return Vector2i(-999, -999)
	return InteriorProjection3D.world_point_to_cell(hit as Vector3, grid_size)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		orbiting = event.pressed
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_orthogonal_size = clampf(camera_orthogonal_size - 0.7, CAMERA_ORTHOGONAL_SIZE_MIN, CAMERA_ORTHOGONAL_SIZE_MAX)
		_update_camera()
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_orthogonal_size = clampf(camera_orthogonal_size + 0.7, CAMERA_ORTHOGONAL_SIZE_MIN, CAMERA_ORTHOGONAL_SIZE_MAX)
		_update_camera()
		accept_event()
		return
	if event is InputEventMouseMotion and orbiting:
		camera_yaw = clampf(camera_yaw - event.relative.x * 0.01, -CAMERA_YAW_LIMIT, CAMERA_YAW_LIMIT)
		_update_camera()
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := _get_floor_cell(event.position)
		if _is_inside(cell):
			var placement := _find_placement_at(cell)
			if placement != null:
				dragging_instance_id = placement.instance_id
				drag_start_position = event.position
				drag_preview_cell = placement.cell
				drag_preview_valid = true
				drag_has_moved = false
				placement_drag_started.emit(placement.instance_id)
			else:
				cell_pressed.emit(cell)
			accept_event()
	elif event is InputEventMouseMotion and not dragging_instance_id.is_empty():
		if event.position.distance_to(drag_start_position) >= 4.0:
			drag_has_moved = true
		if drag_has_moved:
			drag_preview_cell = _get_floor_cell(event.position)
			placement_drag_previewed.emit(dragging_instance_id, drag_preview_cell)
			_rebuild_scene()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not dragging_instance_id.is_empty():
		var dropped_instance_id := dragging_instance_id
		var drop_cell := _get_floor_cell(event.position)
		dragging_instance_id = ""
		if drag_has_moved:
			placement_drop_requested.emit(dropped_instance_id, drop_cell)
		else:
			cell_pressed.emit(drop_cell)
		_rebuild_scene()
		accept_event()


func _get_footprint(equipment_id: String) -> Vector2i:
	return footprints.get(equipment_id, Vector2i.ONE)


func _find_placement(instance_id: String) -> StoreFurniturePlacement:
	for placement in placements:
		if placement.instance_id == instance_id:
			return placement
	return null


func _find_placement_at(cell: Vector2i) -> StoreFurniturePlacement:
	for placement in placements:
		if cell in placement.get_footprint_cells(_get_footprint(placement.equipment_id)):
			return placement
	return null


func _is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y and (layout_geometry == null or layout_geometry.is_available(cell))
