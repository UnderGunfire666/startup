class_name InteriorCanvas
extends Control

signal cell_pressed(cell: Vector2i)
signal placement_drag_started(instance_id: String)
signal placement_drag_previewed(instance_id: String, cell: Vector2i)
signal placement_drop_requested(instance_id: String, cell: Vector2i)

const CELL_SIZE := 64.0
var grid_size := Vector2i(5, 5)
var available_cells: Dictionary = {}
var placements: Array[StoreFurniturePlacement] = []
var selected_instance_id := ""
var dragging_instance_id := ""
var drag_start_position := Vector2.ZERO
var drag_preview_cell := Vector2i.ZERO
var drag_preview_valid := false
var drag_has_moved := false

func setup(size: Vector2i, layout: Array[StoreFurniturePlacement], usable_cells: Dictionary = {}) -> void:
	grid_size = size
	placements = layout
	available_cells = usable_cells
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
		if cell in placement.get_footprint_cells(get_footprint_size(placement.equipment_id)):
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
	for placement in placements:
		if placement.instance_id == dragging_instance_id and drag_has_moved:
			continue
		var size := get_footprint_size(placement.equipment_id)
		var min_cell := placement.cell
		var actual_size := size if placement.rotation % 2 == 0 else Vector2i(size.y, size.x)
		var rect := Rect2(Vector2(16, 16) + Vector2(min_cell) * CELL_SIZE + Vector2(4, 4), Vector2(actual_size) * CELL_SIZE - Vector2(8, 8))
		var color := Color("#d7824b") if placement.instance_id == selected_instance_id else Color("#4f9d9a")
		draw_rect(rect, color, true)
		draw_rect(rect, Color("#e8f1ed"), false, 2.0)
	if not dragging_instance_id.is_empty() and drag_has_moved:
		var dragged := _find_placement_by_id(dragging_instance_id)
		if dragged != null:
			var size := get_footprint_size(dragged.equipment_id)
			var actual_size := size if dragged.rotation % 2 == 0 else Vector2i(size.y, size.x)
			var preview_rect := Rect2(Vector2(16, 16) + Vector2(drag_preview_cell) * CELL_SIZE + Vector2(4, 4), Vector2(actual_size) * CELL_SIZE - Vector2(8, 8))
			var preview_color := Color("#63c6a6", 0.55) if drag_preview_valid else Color("#e06c75", 0.55)
			draw_rect(preview_rect, preview_color, true)
			draw_rect(preview_rect, Color("#e8f1ed", 0.8), false, 2.0)

func _find_placement_by_id(instance_id: String) -> StoreFurniturePlacement:
	for placement in placements:
		if placement.instance_id == instance_id:
			return placement
	return null

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
