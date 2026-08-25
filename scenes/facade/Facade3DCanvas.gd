class_name Facade3DCanvas
extends SubViewportContainer

signal cell_pressed(cell: Vector2i)
signal placement_drag_started(placement: StoreFacadePlacement)
signal placement_drag_previewed(placement: StoreFacadePlacement, cell: Vector2i)
signal placement_drop_requested(placement: StoreFacadePlacement, cell: Vector2i)

const CAMERA_MIN_DISTANCE := 9.0
const CAMERA_MAX_DISTANCE := 24.0
const CAMERA_YAW_LIMIT := 1.15
const CAMERA_ORTHOGONAL_SIZE_MIN := 7.0
const CAMERA_ORTHOGONAL_SIZE_MAX := 18.0
const CAMERA_FIXED_HEIGHT := 2.5

var placements: Array[StoreFacadePlacement] = []
var grid_size := FacadeLayoutValidator.GRID_SIZE
var layout_geometry: StorefrontLayoutGeometry = null
var selected_placement: StoreFacadePlacement = null
var dragging_placement: StoreFacadePlacement = null
var drag_start_position := Vector2.ZERO
var drag_preview_cell := Vector2i.ZERO
var drag_preview_valid := false
var drag_has_moved := false
var camera_yaw := 0.0
var camera_orthogonal_size := 11.0
var orbiting := false

var _viewport: SubViewport
var _world_root: Node3D
var _static_root: Node3D
var _component_root: Node3D
var _preview_root: Node3D
var _camera: Camera3D


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	add_child(_viewport)
	_world_root = Node3D.new()
	_viewport.add_child(_world_root)
	_create_world()
	_rebuild_scene()


func setup(layout: Array[StoreFacadePlacement], size: Vector2i = FacadeLayoutValidator.GRID_SIZE, geometry: StorefrontLayoutGeometry = null) -> void:
	placements = layout
	layout_geometry = geometry
	grid_size = geometry.get_facade_grid_size() if geometry != null else size
	if is_instance_valid(_component_root):
		_rebuild_scene()


func set_selected(placement: StoreFacadePlacement) -> void:
	selected_placement = placement
	if is_instance_valid(_component_root):
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
	environment_resource.ambient_light_energy = 0.65
	environment.environment = environment_resource
	_world_root.add_child(environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	key_light.light_energy = 1.25
	_world_root.add_child(key_light)
	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(-4.0, 3.0, 5.0)
	fill_light.light_energy = 3.0
	fill_light.omni_range = 18.0
	_world_root.add_child(fill_light)

	_static_root = Node3D.new()
	_world_root.add_child(_static_root)
	_component_root = Node3D.new()
	_component_root.name = "FacadeComponents"
	_world_root.add_child(_component_root)
	_preview_root = Node3D.new()
	_preview_root.name = "Preview"
	_world_root.add_child(_preview_root)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_world_root.add_child(_camera)
	_update_camera()


func _create_static_geometry() -> void:
	var wall_size := Vector3(float(grid_size.x) * FacadeProjection3D.CELL_WORLD_SIZE, float(grid_size.y) * FacadeProjection3D.CELL_WORLD_SIZE, FacadeProjection3D.WALL_DEPTH)
	var entrance: StoreFacadePlacement = null
	for placement in placements:
		if placement.type == "entrance":
			entrance = placement
			break
	if entrance == null:
		_add_box(_static_root, wall_size, Vector3(0.0, wall_size.y * 0.5, 0.0), Color("#344754"))
	else:
		var opening_width := float(FacadeLayoutValidator.get_footprint_size("entrance").x) * FacadeProjection3D.CELL_WORLD_SIZE
		var opening_center := (float(entrance.cell.x) + 1.0 - float(grid_size.x) * 0.5) * FacadeProjection3D.CELL_WORLD_SIZE
		var left_width := maxf(0.0, opening_center - opening_width * 0.5 + wall_size.x * 0.5)
		var right_width := maxf(0.0, wall_size.x * 0.5 - (opening_center + opening_width * 0.5))
		if left_width > 0.0:
			_add_box(_static_root, Vector3(left_width, wall_size.y, wall_size.z), Vector3(-wall_size.x * 0.5 + left_width * 0.5, wall_size.y * 0.5, 0.0), Color("#344754"))
		if right_width > 0.0:
			_add_box(_static_root, Vector3(right_width, wall_size.y, wall_size.z), Vector3(wall_size.x * 0.5 - right_width * 0.5, wall_size.y * 0.5, 0.0), Color("#344754"))
	_add_box(_static_root, Vector3(float(grid_size.x) * FacadeProjection3D.CELL_WORLD_SIZE + 1.0, 0.18, 2.5), Vector3(0.0, -0.09, 1.2), Color("#25333b"))
	var grid_color := Color(0.66, 0.78, 0.83, 0.34)
	for x in range(grid_size.x + 1):
		var world_x := (float(x) - float(grid_size.x) * 0.5) * FacadeProjection3D.CELL_WORLD_SIZE
		_add_box(_static_root, Vector3(0.025, float(grid_size.y) * FacadeProjection3D.CELL_WORLD_SIZE, 0.025), Vector3(world_x, float(grid_size.y) * FacadeProjection3D.CELL_WORLD_SIZE * 0.5, FacadeProjection3D.WALL_DEPTH * 0.5 + 0.018), grid_color, true)
	for y in range(grid_size.y + 1):
		_add_box(_static_root, Vector3(float(grid_size.x) * FacadeProjection3D.CELL_WORLD_SIZE, 0.025, 0.025), Vector3(0.0, float(y) * FacadeProjection3D.CELL_WORLD_SIZE, FacadeProjection3D.WALL_DEPTH * 0.5 + 0.02), grid_color, true)


func _add_box(parent: Node3D, box_size: Vector3, position: Vector3, color: Color, transparent: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	instance.mesh = mesh
	instance.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.05
	material.roughness = 0.72
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _rebuild_scene() -> void:
	for child in _static_root.get_children():
		child.queue_free()
	_create_static_geometry()
	for child in _component_root.get_children():
		child.queue_free()
	for placement in placements:
		if placement == dragging_placement and drag_has_moved:
			continue
		var color := FacadeProjection3D.get_type_color(placement.type)
		if placement == selected_placement:
			color = color.lightened(0.22)
		var box_size := FacadeProjection3D.get_world_size(placement.type)
		var component := _add_box(_component_root, box_size, FacadeProjection3D.get_world_position(placement.type, placement.cell, grid_size), color)
		_add_component_front_decal(component, box_size, placement.type, color)
	_rebuild_preview()


func _rebuild_preview() -> void:
	for child in _preview_root.get_children():
		child.queue_free()
	if dragging_placement != null and drag_has_moved:
		var preview_color := Color("#63c6a6", 0.56) if drag_preview_valid else Color("#e06c75", 0.56)
		_add_box(_preview_root, FacadeProjection3D.get_world_size(dragging_placement.type), FacadeProjection3D.get_world_position(dragging_placement.type, drag_preview_cell, grid_size), preview_color, true)


func _add_component_front_decal(instance: MeshInstance3D, box_size: Vector3, type: String, side_color: Color = Color("#344754")) -> void:
	var atlas := load(LayoutSpriteCatalog.FACADE_ATLAS_PATH) as Texture2D
	if atlas == null:
		return
	var texture := LayoutSpriteCatalog.get_facade_3d_texture(atlas, type)
	if texture == null:
		return
	LayoutBoxSurfaceDecor.add_five_faces(instance, box_size, texture, side_color)


func _update_camera() -> void:
	if _camera == null:
		return
	var target := Vector3(0.0, float(grid_size.y) * FacadeProjection3D.CELL_WORLD_SIZE * 0.5, 0.0)
	_camera.position = target + Vector3(sin(camera_yaw) * CAMERA_MAX_DISTANCE, CAMERA_FIXED_HEIGHT, cos(camera_yaw) * CAMERA_MAX_DISTANCE)
	_camera.size = camera_orthogonal_size
	_camera.look_at(target, Vector3.UP)


func _get_wall_cell(position: Vector2) -> Vector2i:
	var ray_origin := _camera.project_ray_origin(position)
	var ray_direction := _camera.project_ray_normal(position)
	var plane := Plane(Vector3.FORWARD, FacadeProjection3D.WALL_DEPTH * 0.5 + 0.05)
	var hit: Variant = plane.intersects_ray(ray_origin, ray_direction)
	if hit == null:
		return Vector2i(-999, -999)
	return FacadeProjection3D.world_point_to_cell(hit as Vector3, grid_size)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		orbiting = event.pressed
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_orthogonal_size = clampf(camera_orthogonal_size - 0.8, CAMERA_ORTHOGONAL_SIZE_MIN, CAMERA_ORTHOGONAL_SIZE_MAX)
		_update_camera()
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_orthogonal_size = clampf(camera_orthogonal_size + 0.8, CAMERA_ORTHOGONAL_SIZE_MIN, CAMERA_ORTHOGONAL_SIZE_MAX)
		_update_camera()
		accept_event()
		return
	if event is InputEventMouseMotion and orbiting:
		camera_yaw = clampf(camera_yaw - event.relative.x * 0.01, -CAMERA_YAW_LIMIT, CAMERA_YAW_LIMIT)
		_update_camera()
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := _get_wall_cell(event.position)
		if _is_inside(cell):
			var placement := _find_placement_at(cell)
			if placement != null:
				dragging_placement = placement
				drag_start_position = event.position
				drag_preview_cell = placement.cell
				drag_preview_valid = true
				drag_has_moved = false
				placement_drag_started.emit(placement)
			else:
				cell_pressed.emit(cell)
			accept_event()
	elif event is InputEventMouseMotion and dragging_placement != null:
		if event.position.distance_to(drag_start_position) >= 4.0:
			drag_has_moved = true
		if drag_has_moved:
			drag_preview_cell = _get_wall_cell(event.position)
			placement_drag_previewed.emit(dragging_placement, drag_preview_cell)
			_rebuild_scene()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and dragging_placement != null:
		var dropped_placement := dragging_placement
		var drop_cell := _get_wall_cell(event.position)
		dragging_placement = null
		if drag_has_moved:
			placement_drop_requested.emit(dropped_placement, drop_cell)
		else:
			cell_pressed.emit(drop_cell)
		_rebuild_scene()
		accept_event()


func _is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func _find_placement_at(cell: Vector2i) -> StoreFacadePlacement:
	for placement in placements:
		if cell in FacadeLayoutValidator.get_footprint_cells(placement.type, placement.cell):
			return placement
	return null
