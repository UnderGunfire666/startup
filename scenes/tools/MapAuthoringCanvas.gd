@tool
class_name MapAuthoringCanvas
extends Control

signal node_moved(node_id: String)
signal storefront_moved(storefront_id: String)
signal storefront_selected(storefront_id: String)
signal block_moved(block_id: String)
signal grid_road_requested(from_cell: Vector2i, to_cell: Vector2i)
signal grid_cells_selected(cells: Array[Vector2i])
signal grid_block_selected(block_id: String)
signal road_node_selected(node_id: String)
signal road_segment_selected(segment_id: String)
signal selection_cleared
signal edit_rejected(message: String)
signal additional_element_selected(element_id: String, is_storefront: bool)

const MAP_SCALE := 0.3
const NODE_RADIUS := 7.0
const GRID_SCREEN_SIZE := 16.0
enum EditMode { SELECT, ROAD, BLOCK }

var document: MapAuthoringDocument
var _dragging_node_id := ""
var _dragging_storefront_id := ""
var _dragging_block_id := ""
var edit_mode: EditMode = EditMode.SELECT
var _grid_drag_start := Vector2i.ZERO
var _road_drag_current := Vector2i.ZERO
var _grid_dragging := false
var grid_screen_size: float = GRID_SCREEN_SIZE
var selected_grid_cells: Array[Vector2i] = []
var validation_errors: Array[String] = []
var selected_storefront_id := ""
var selected_storefront_ids: Array[String] = []
var selected_block_ids: Array[String] = []

func set_selected_storefront(storefront_id: String) -> void:
	selected_storefront_id = storefront_id
	selected_storefront_ids = [storefront_id] if not storefront_id.is_empty() else []
	queue_redraw()

func set_validation_errors(errors: Array[String]) -> void:
	validation_errors = errors.duplicate()
	queue_redraw()

func set_selected_grid_cells(cells: Array[Vector2i]) -> void:
	selected_grid_cells = cells.duplicate()
	queue_redraw()


func set_zoom(new_zoom: float) -> void:
	grid_screen_size = clampf(GRID_SCREEN_SIZE * new_zoom, 6.0, 48.0)
	refresh_canvas()


func set_edit_mode(new_mode: EditMode) -> void:
	_cancel_active_block_drag()
	edit_mode = new_mode
	_grid_dragging = false
	_dragging_node_id = ""
	_dragging_storefront_id = ""
	_dragging_block_id = ""
	queue_redraw()


func setup(new_document: MapAuthoringDocument) -> void:
	document = new_document
	refresh_canvas()


func refresh_canvas() -> void:
	_update_canvas_size()
	queue_redraw()


func move_node_to_map(node_id: String, map_position: Vector2) -> bool:
	if document == null or not document.move_road_node(node_id, map_position):
		return false
	node_moved.emit(node_id)
	queue_redraw()
	return true


func move_storefront_to_map(storefront_id: String, map_position: Vector2) -> bool:
	if document == null or not document.move_storefront(storefront_id, map_position):
		edit_rejected.emit("门面必须位于区块内，已恢复原位置。")
		return false
	storefront_moved.emit(storefront_id)
	queue_redraw()
	return true


func move_block_to_map(block_id: String, map_position: Vector2) -> bool:
	if document == null or not document.move_block(block_id, map_position):
		edit_rejected.emit("区块不能覆盖道路且必须紧贴道路，已恢复原位置。")
		return false
	block_moved.emit(block_id)
	queue_redraw()
	return true


func _update_canvas_size() -> void:
	if document == null:
		return
	var max_position := Vector2(640, 480)
	for block in document.blocks:
		max_position.x = maxf(max_position.x, block.map_bounds.end.x)
		max_position.y = maxf(max_position.y, block.map_bounds.end.y)
	for raw_node in document.road_graph.nodes.values():
		var node := raw_node as RoadNode
		if node != null:
			max_position.x = maxf(max_position.x, node.position.x)
			max_position.y = maxf(max_position.y, node.position.y)
	for cell in document.road_cells:
		max_position.x = maxf(max_position.x, (float(cell.x) + 1.0) * MapAuthoringDocument.GRID_CELL_SIZE)
		max_position.y = maxf(max_position.y, (float(cell.y) + 1.0) * MapAuthoringDocument.GRID_CELL_SIZE)
	# Keep a clear five-cell editing margin after the furthest authored element.
	custom_minimum_size = (max_position / MapAuthoringDocument.GRID_CELL_SIZE + Vector2(5, 5)) * grid_screen_size


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
			_cancel_active_block_drag()
			selected_storefront_ids.clear()
			selected_block_ids.clear()
			selection_cleared.emit()
			return
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if edit_mode != EditMode.SELECT:
			if mouse_button.pressed:
				_grid_drag_start = _screen_to_grid_intersection(mouse_button.position) if edit_mode == EditMode.ROAD else _screen_to_grid(mouse_button.position)
				_road_drag_current = _grid_drag_start
				_grid_dragging = true
			else:
				if _grid_dragging:
					var end_cell := _screen_to_grid_intersection(mouse_button.position) if edit_mode == EditMode.ROAD else _screen_to_grid(mouse_button.position)
					if edit_mode == EditMode.ROAD:
						grid_road_requested.emit(_grid_drag_start, end_cell)
					else:
						grid_cells_selected.emit(_rectangle_cells(_grid_drag_start, end_cell))
				_grid_dragging = false
				queue_redraw()
			return
		if mouse_button.pressed:
			_dragging_node_id = _find_node_at_screen(mouse_button.position)
			if not _dragging_node_id.is_empty():
				road_node_selected.emit(_dragging_node_id)
			if _dragging_node_id.is_empty():
				_dragging_storefront_id = _find_storefront_at_screen(mouse_button.position)
				if not _dragging_storefront_id.is_empty():
					if mouse_button.ctrl_pressed:
						if not selected_storefront_ids.has(_dragging_storefront_id):
							selected_storefront_ids.append(_dragging_storefront_id)
						additional_element_selected.emit(_dragging_storefront_id, true)
					else:
						selected_storefront_id = _dragging_storefront_id
						selected_storefront_ids = [_dragging_storefront_id]
						selected_block_ids.clear()
						storefront_selected.emit(_dragging_storefront_id)
			if _dragging_node_id.is_empty() and _dragging_storefront_id.is_empty():
				var segment_id := _find_segment_at_screen(mouse_button.position)
				if not segment_id.is_empty():
					road_segment_selected.emit(segment_id)
				elif _dragging_block_id.is_empty():
					var empty_cells: Array[Vector2i] = []
					grid_cells_selected.emit(empty_cells)
			if _dragging_node_id.is_empty() and _dragging_storefront_id.is_empty():
				_dragging_block_id = _find_block_at_screen(mouse_button.position)
				if not _dragging_block_id.is_empty():
					document.begin_block_move(_dragging_block_id)
					if mouse_button.ctrl_pressed:
						if not selected_block_ids.has(_dragging_block_id):
							selected_block_ids.append(_dragging_block_id)
						additional_element_selected.emit(_dragging_block_id, false)
					else:
						selected_block_ids = [_dragging_block_id]
						selected_storefront_ids.clear()
						grid_block_selected.emit(_dragging_block_id)
		else:
			_dragging_node_id = ""
			_dragging_storefront_id = ""
			if not _dragging_block_id.is_empty():
				var moved_block_id := _dragging_block_id
				_dragging_block_id = ""
				if document.finish_block_move(moved_block_id):
					block_moved.emit(moved_block_id)
				else:
					edit_rejected.emit("区块不能覆盖道路且必须紧贴道路，已恢复原位置。")
				queue_redraw()
	elif event is InputEventMouseMotion and not _dragging_node_id.is_empty() and (((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
		var motion := event as InputEventMouseMotion
		move_node_to_map(_dragging_node_id, _screen_to_world(motion.position))
	elif event is InputEventMouseMotion and not _dragging_storefront_id.is_empty() and (((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
		var motion := event as InputEventMouseMotion
		move_storefront_to_map(_dragging_storefront_id, _screen_to_world(motion.position))
	elif event is InputEventMouseMotion and not _dragging_block_id.is_empty() and (((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
		var motion := event as InputEventMouseMotion
		if document.move_block_preview(_dragging_block_id, _screen_to_world(motion.position)):
			queue_redraw()
	elif event is InputEventMouseMotion and _grid_dragging:
		if edit_mode == EditMode.ROAD:
			_road_drag_current = _screen_to_grid_intersection((event as InputEventMouseMotion).position)
		queue_redraw()


func _screen_to_grid(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / grid_screen_size), floori(position.y / grid_screen_size))


func _screen_to_grid_intersection(position: Vector2) -> Vector2i:
	return Vector2i(roundi(position.x / grid_screen_size), roundi(position.y / grid_screen_size))


func _cancel_active_block_drag() -> void:
	if document != null and not _dragging_block_id.is_empty():
		document.cancel_block_move(_dragging_block_id)
	_dragging_block_id = ""


func _screen_to_world(position: Vector2) -> Vector2:
	return position / grid_screen_size * MapAuthoringDocument.GRID_CELL_SIZE


func _rectangle_cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			result.append(Vector2i(x, y))
	return result


func _find_node_at_screen(screen_position: Vector2) -> String:
	if document == null:
		return ""
	for raw_node in document.road_graph.nodes.values():
		var node := raw_node as RoadNode
		if node != null and _world_to_grid_screen(node.position).distance_to(screen_position) <= NODE_RADIUS:
			return node.id
	return ""


func _find_storefront_at_screen(screen_position: Vector2) -> String:
	if document == null:
		return ""
	for storefront in document.storefronts:
		for cell in storefront.grid_cells:
			var cell_rect := Rect2(Vector2(cell) * grid_screen_size, Vector2.ONE * grid_screen_size)
			if cell_rect.has_point(screen_position):
				return storefront.id
		if _world_to_grid_screen(storefront.map_position).distance_to(screen_position) <= NODE_RADIUS:
			return storefront.id
	return ""


func _find_segment_at_screen(screen_position: Vector2) -> String:
	if document == null:
		return ""
	for segment in document.road_graph.segments:
		var from_node: RoadNode = document.road_graph.nodes.get(segment.from_node_id, null)
		var to_node: RoadNode = document.road_graph.nodes.get(segment.to_node_id, null)
		if from_node == null or to_node == null:
			continue
		if _distance_to_screen_segment(screen_position, _world_to_grid_screen(from_node.position), _world_to_grid_screen(to_node.position)) <= 8.0:
			return segment.id
	return ""


func _distance_to_screen_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var direction := to - from
	if is_zero_approx(direction.length_squared()):
		return point.distance_to(from)
	var ratio := clampf((point - from).dot(direction) / direction.length_squared(), 0.0, 1.0)
	return point.distance_to(from + direction * ratio)


func _find_block_at_screen(screen_position: Vector2) -> String:
	if document == null:
		return ""
	var map_position := _screen_to_world(screen_position)
	for index in range(document.blocks.size() - 1, -1, -1):
		var block := document.blocks[index]
		if block.has_map_point(map_position):
			return block.id
	return ""


func _draw() -> void:
	if document == null:
		return
	var grid_size := get_rect().size
	var grid_x := 0.0
	while grid_x <= grid_size.x:
		draw_line(Vector2(grid_x, 0), Vector2(grid_x, grid_size.y), Color(0.2, 0.23, 0.28, 0.35), 1.0)
		grid_x += grid_screen_size
	var grid_y := 0.0
	while grid_y <= grid_size.y:
		draw_line(Vector2(0, grid_y), Vector2(grid_size.x, grid_y), Color(0.2, 0.23, 0.28, 0.35), 1.0)
		grid_y += grid_screen_size
	for cell in document.road_cells:
		var road_rect := Rect2(Vector2(cell) * grid_screen_size, Vector2.ONE * grid_screen_size)
		var road_data: Dictionary = document.road_cells[cell]
		draw_rect(road_rect, _get_road_color(str(road_data.get("class", "local"))), true)
	for block in document.blocks:
		if block.grid_cells.is_empty():
			var rect := Rect2(block.map_bounds.position / MapAuthoringDocument.GRID_CELL_SIZE * grid_screen_size, block.map_bounds.size / MapAuthoringDocument.GRID_CELL_SIZE * grid_screen_size)
			draw_rect(rect, Color(0.25, 0.45, 0.55, 0.18), true)
			draw_rect(rect, Color(0.7, 0.8, 0.9, 0.45), false, 1.0)
		else:
			var block_color := _get_block_color(block.block_type)
			for cell in block.grid_cells:
				var cell_rect := Rect2(Vector2(cell) * grid_screen_size, Vector2.ONE * grid_screen_size)
				draw_rect(cell_rect, block_color, true)
				draw_rect(cell_rect, block_color.lightened(0.25), false, 1.0)
				if selected_block_ids.has(block.id):
					draw_rect(cell_rect.grow(1.0), Color(1.0, 0.85, 0.2, 1.0), false, 2.0)
			var tier_position := block.center_position / MapAuthoringDocument.GRID_CELL_SIZE * grid_screen_size
			draw_string(ThemeDB.fallback_font, tier_position, str(block.tier), HORIZONTAL_ALIGNMENT_CENTER, 18, 14)
	for segment in document.road_graph.segments:
		var from_node: RoadNode = document.road_graph.nodes.get(segment.from_node_id, null)
		var to_node: RoadNode = document.road_graph.nodes.get(segment.to_node_id, null)
		if from_node == null or to_node == null:
			continue
		draw_line(_world_to_grid_screen(from_node.position), _world_to_grid_screen(to_node.position), Color(0.9, 0.9, 0.95, 0.85), 1.0, true)
	for raw_node in document.road_graph.nodes.values():
		var node := raw_node as RoadNode
		if node == null:
			continue
		var screen_position := _world_to_grid_screen(node.position)
		draw_circle(screen_position, NODE_RADIUS, Color(1.0, 0.72, 0.25, 1.0))
		draw_string(ThemeDB.fallback_font, screen_position + Vector2(9, 4), node.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	for storefront in document.storefronts:
		if storefront.id == selected_storefront_id and storefront.awareness_radius > 0.0:
			var awareness_radius_screen: float = storefront.awareness_radius / MapAuthoringDocument.GRID_CELL_SIZE * grid_screen_size
			draw_arc(_world_to_grid_screen(storefront.map_position), awareness_radius_screen, 0.0, TAU, 64, Color(1.0, 0.8, 0.2, 0.72), 1.5, true)
		for cell in storefront.grid_cells:
			var storefront_cell_rect := Rect2(Vector2(cell) * grid_screen_size, Vector2.ONE * grid_screen_size)
			draw_rect(storefront_cell_rect, Color(0.2, 0.95, 0.55, 0.42), true)
			draw_rect(storefront_cell_rect, Color(0.65, 1.0, 0.78, 0.9), false, 1.0)
			if selected_storefront_ids.has(storefront.id):
				draw_rect(storefront_cell_rect.grow(1.0), Color(1.0, 0.85, 0.2, 1.0), false, 2.0)
		var storefront_position := _world_to_grid_screen(storefront.map_position)
		draw_circle(storefront_position, 5.0, Color(0.25, 0.95, 0.55, 1.0))
		draw_circle(storefront_position, 5.0, Color(0.05, 0.1, 0.05, 0.9), false, 1.0)
	_draw_validation_overlays()
	if _grid_dragging and edit_mode == EditMode.BLOCK:
		var preview := _rectangle_cells(_grid_drag_start, _screen_to_grid(get_local_mouse_position()))
		for cell in preview:
			draw_rect(Rect2(Vector2(cell) * grid_screen_size, Vector2.ONE * grid_screen_size), Color(0.95, 0.8, 0.25, 0.3), true)
	if _grid_dragging and edit_mode == EditMode.ROAD:
		var road_start := Vector2(_grid_drag_start) * grid_screen_size
		var road_end := Vector2(_road_drag_current) * grid_screen_size
		draw_line(road_start, road_end, Color(1.0, 0.78, 0.2, 0.95), 3.0, true)
		draw_circle(road_start, 5.0, Color(1.0, 0.7, 0.15, 1.0))
		draw_circle(road_end, 4.0, Color(1.0, 0.9, 0.45, 0.95))
	for cell in selected_grid_cells:
		draw_rect(Rect2(Vector2(cell) * grid_screen_size, Vector2.ONE * grid_screen_size), Color(0.2, 0.85, 1.0, 0.45), true)
	_draw_legend()


func _draw_validation_overlays() -> void:
	for error in validation_errors:
		var words := error.split(" ")
		if words.size() < 2:
			continue
		var item_id := words[1]
		for block in document.blocks:
			if block.id == item_id:
				var block_color := _validation_color(error)
				for cell in block.grid_cells:
					draw_rect(Rect2(Vector2(cell) * grid_screen_size, Vector2.ONE * grid_screen_size), block_color, false, 2.0)
				draw_string(ThemeDB.fallback_font, _world_to_grid_screen(block.center_position) + Vector2(3, -4), _validation_label(error), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, block_color)
		for storefront in document.storefronts:
			if storefront.id == item_id:
				var storefront_color := _validation_color(error)
				for cell in storefront.grid_cells:
					draw_rect(Rect2(Vector2(cell) * grid_screen_size, Vector2.ONE * grid_screen_size), storefront_color, false, 2.0)
				draw_string(ThemeDB.fallback_font, _world_to_grid_screen(storefront.map_position) + Vector2(5, -7), _validation_label(error), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, storefront_color)


func _validation_color(error: String) -> Color:
	if error.contains("overlap"):
		return Color(1.0, 0.2, 0.2, 0.95)
	if error.contains("adjacent") or error.contains("inside"):
		return Color(1.0, 0.72, 0.12, 0.95)
	return Color(1.0, 0.2, 0.75, 0.95)


func _validation_label(error: String) -> String:
	if error.contains("overlap"):
		return "\u91cd\u53e0"
	if error.contains("adjacent"):
		return "\u672a\u8d34\u8def"
	if error.contains("inside"):
		return "\u8d8a\u754c"
	return "\u65e0\u6548"


func _get_block_color(block_type: String) -> Color:
	match block_type:
		"school": return Color(0.35, 0.55, 0.95, 0.7)
		"office": return Color(0.75, 0.45, 0.95, 0.7)
		"commercial": return Color(0.95, 0.55, 0.25, 0.7)
		"industrial": return Color(0.65, 0.65, 0.35, 0.7)
		"mixed": return Color(0.65, 0.4, 0.82, 0.7)
		"tourism": return Color(0.95, 0.62, 0.2, 0.7)
		"public_green": return Color(0.32, 0.72, 0.38, 0.7)
		_: return Color(0.3, 0.75, 0.5, 0.7)


func _get_road_color(road_class: String) -> Color:
	match road_class:
		"alley": return Color(0.26, 0.28, 0.31, 1.0)
		"secondary": return Color(0.42, 0.44, 0.48, 1.0)
		"arterial": return Color(0.58, 0.6, 0.64, 1.0)
		_: return Color(0.34, 0.36, 0.4, 1.0)


func _draw_legend() -> void:
	var origin := Vector2(8, 18)
	draw_string(ThemeDB.fallback_font, origin, "道路：小巷 / 支路 / 次干路 / 主干路", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(ThemeDB.fallback_font, origin + Vector2(0, 16), "区块：蓝色学校、紫色办公、橙色商业、绿色住宅；数字为等级", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)


func _world_to_grid_screen(position: Vector2) -> Vector2:
	return position / MapAuthoringDocument.GRID_CELL_SIZE * grid_screen_size
