class_name InteriorCanvas
extends Control

signal cell_pressed(cell: Vector2i)
signal placement_drag_started(instance_id: String)
signal placement_drag_previewed(instance_id: String, cell: Vector2i)
signal placement_drop_requested(instance_id: String, cell: Vector2i)

const CELL_SIZE := 64.0
var grid_size := Vector2i(5, 5)
var layout_geometry: StorefrontLayoutGeometry = null
var available_cells: Dictionary = {}
var entrance_cells: Array[Vector2i] = []
var equipment_names: Dictionary = {}
var placements: Array[StoreFurniturePlacement] = []
var selected_instance_id := ""
var dragging_instance_id := ""
var drag_start_position := Vector2.ZERO
var drag_preview_cell := Vector2i.ZERO
var drag_preview_valid := false
var drag_has_moved := false
var equipment_atlas: Texture2D = preload("res://assets/layout/equipment_atlas.png")

func setup(size: Vector2i, layout: Array[StoreFurniturePlacement], geometry: StorefrontLayoutGeometry = null, current_entrance_cells: Array[Vector2i] = [], current_equipment_names: Dictionary = {}) -> void:
	layout_geometry = geometry
	grid_size = geometry.get_display_grid_size() if geometry != null else size
	placements = layout
	available_cells = geometry.get_display_available_cells() if geometry != null else {}
	entrance_cells = _map_entrance_cells(current_entrance_cells)
	equipment_names = current_equipment_names
	custom_minimum_size = Vector2(grid_size) * CELL_SIZE + Vector2(32, 32)
	queue_redraw()

func set_selected(instance_id: String) -> void:
	selected_instance_id = instance_id
	queue_redraw()

func set_drag_preview_valid(is_valid: bool) -> void:
	drag_preview_valid = is_valid
	queue_redraw()

func get_cell_at_position(position: Vector2) -> Vector2i:
	return Vector2i(floori((position.x - 16.0) / CELL_SIZE), floori((position.y - 16.0) / CELL_SIZE))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := get_cell_at_position(event.position)
		if _is_inside(cell):
			var placement := _find_placement_at(cell)
			if placement != null:
				dragging_instance_id = placement.instance_id
				drag_start_position = event.position
				drag_preview_cell = _get_display_rect(placement).cell
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
			drag_preview_cell = get_cell_at_position(event.position)
			placement_drag_previewed.emit(dragging_instance_id, drag_preview_cell)
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not dragging_instance_id.is_empty():
		var dragged_instance_id := dragging_instance_id
		var drop_cell := get_cell_at_position(event.position)
		dragging_instance_id = ""
		if drag_has_moved:
			placement_drop_requested.emit(dragged_instance_id, drop_cell)
		else:
			cell_pressed.emit(drop_cell)
		queue_redraw()
		accept_event()

func _is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y and (available_cells.is_empty() or available_cells.has(cell))

func _find_placement_at(cell: Vector2i) -> StoreFurniturePlacement:
	for placement in placements:
		var display_rect := _get_display_rect(placement)
		if Rect2i(display_rect.cell, display_rect.size).has_point(cell):
			return placement
	return null

func _draw() -> void:
	draw_rect(Rect2(Vector2(16, 16), Vector2(grid_size) * CELL_SIZE), Color("#16232b"), true)
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			var rect := Rect2(Vector2(16, 16) + Vector2(cell) * CELL_SIZE, Vector2.ONE * CELL_SIZE)
			if _is_inside(cell):
				draw_rect(rect, Color("#314650"), false, 1.0)
			else:
				draw_rect(rect, Color("#0d171d"), true)
	_draw_entrance_markers()
	for placement in placements:
		if placement.instance_id == dragging_instance_id and drag_has_moved:
			continue
		var display_rect := _get_display_rect(placement)
		var min_cell: Vector2i = display_rect.cell
		var actual_size: Vector2i = display_rect.size
		var rect := Rect2(Vector2(16, 16) + Vector2(min_cell) * CELL_SIZE + Vector2(4, 4), Vector2(actual_size) * CELL_SIZE - Vector2(8, 8))
		var color := Color("#d7824b") if placement.instance_id == selected_instance_id else Color("#4f9d9a")
		draw_rect(rect, color, true)
		_draw_equipment_sprite(rect, placement.equipment_id)
		draw_rect(rect, Color("#e8f1ed"), false, 2.0)
		_draw_equipment_name(rect, placement.equipment_id)
	if not dragging_instance_id.is_empty() and drag_has_moved:
		var dragged := _find_placement_by_id(dragging_instance_id)
		if dragged != null:
			var display_rect := _get_display_rect(dragged)
			var actual_size: Vector2i = display_rect.size
			var preview_rect := Rect2(Vector2(16, 16) + Vector2(drag_preview_cell) * CELL_SIZE + Vector2(4, 4), Vector2(actual_size) * CELL_SIZE - Vector2(8, 8))
			var preview_color := Color("#63c6a6", 0.55) if drag_preview_valid else Color("#e06c75", 0.55)
			draw_rect(preview_rect, preview_color, true)
			draw_rect(preview_rect, Color("#e8f1ed", 0.8), false, 2.0)


func get_entrance_marker_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in entrance_cells:
		if cell.y == grid_size.y - 1 and _is_inside(cell):
			result.append(cell)
	return result


func get_equipment_display_name(equipment_id: String) -> String:
	return str(equipment_names.get(equipment_id, equipment_id))


func _draw_entrance_markers() -> void:
	for cell in get_entrance_marker_cells():
		var rect := Rect2(Vector2(16, 16) + Vector2(cell) * CELL_SIZE, Vector2.ONE * CELL_SIZE)
		var start := rect.position + Vector2(2.0, CELL_SIZE - 3.0)
		var end := rect.position + Vector2(CELL_SIZE - 2.0, CELL_SIZE - 3.0)
		draw_line(start, end, Color("#f6cf65"), 6.0, true)


func _draw_equipment_name(rect: Rect2, equipment_id: String) -> void:
	var text := get_equipment_display_name(equipment_id)
	if text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var font_size := _get_equipment_name_font_size(font, text, rect.size.x - 10.0)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_height := maxf(float(font_size) + 8.0, 20.0)
	var label_rect := Rect2(rect.position.x + 2.0, rect.end.y - label_height - 2.0, rect.size.x - 4.0, label_height)
	draw_rect(label_rect, Color(0.04, 0.08, 0.1, 0.78), true)
	var baseline := label_rect.get_center().y + text_size.y * 0.35
	draw_string(font, Vector2(label_rect.position.x + 3.0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, label_rect.size.x - 6.0, font_size, Color.WHITE)


func _draw_equipment_sprite(rect: Rect2, equipment_id: String) -> void:
	if equipment_atlas == null:
		return
	var source := LayoutSpriteCatalog.get_equipment_region(equipment_atlas.get_size(), equipment_id)
	if source.size == Vector2.ZERO:
		return
	var target := LayoutSpriteCatalog.fit_source_in_rect(source.size, rect, 5.0)
	draw_texture_rect_region(equipment_atlas, target, source)


func _get_equipment_name_font_size(font: Font, text: String, max_width: float) -> int:
	for font_size in range(18, 7, -1):
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			return font_size
	return 8

func _find_placement_by_id(instance_id: String) -> StoreFurniturePlacement:
	for placement in placements:
		if placement.instance_id == instance_id:
			return placement
	return null


func _get_display_rect(placement: StoreFurniturePlacement) -> Dictionary:
	var footprint := get_footprint_size(placement.equipment_id)
	if layout_geometry != null:
		return layout_geometry.get_display_placement_rect(placement.cell, footprint, placement.rotation)
	var size := footprint if placement.rotation % 2 == 0 else Vector2i(footprint.y, footprint.x)
	return {"cell": placement.cell, "size": size, "rotation": placement.rotation}


func _map_entrance_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	if layout_geometry == null:
		return cells
	var result: Array[Vector2i] = []
	for cell in cells:
		result.append(layout_geometry.physical_to_display_cell(cell))
	return result

func get_footprint_size(equipment_id: String) -> Vector2i:
	var area := 1.0
	for definition in GameManager.all_equipment:
		if definition.id == equipment_id:
			area = definition.area
			break
	if area <= 1.3:
		return Vector2i(1, 1)
	if area <= 2.5:
		return Vector2i(2, 1)
	return Vector2i(2, 2)
