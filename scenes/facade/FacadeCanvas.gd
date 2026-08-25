class_name FacadeCanvas
extends Control

signal cell_pressed(cell: Vector2i)
signal placement_drag_started(placement: StoreFacadePlacement)
signal placement_drag_previewed(placement: StoreFacadePlacement, cell: Vector2i)
signal placement_drop_requested(placement: StoreFacadePlacement, cell: Vector2i)

const CELL_SIZE := 64.0
const GRID_ORIGIN := Vector2(16.0, 16.0)
const TYPE_COLORS := {
	"signboard": Color("#d6a64a"),
	"entrance": Color("#4f9d9a"),
	"window": Color("#7089c9"),
}
const TYPE_LABELS := {
	"signboard": "招牌",
	"entrance": "入口",
	"window": "橱窗",
}

var placements: Array[StoreFacadePlacement] = []
var grid_size := FacadeLayoutValidator.GRID_SIZE
var selected_placement: StoreFacadePlacement = null
var dragging_placement: StoreFacadePlacement = null
var drag_start_position := Vector2.ZERO
var drag_preview_cell := Vector2i.ZERO
var drag_preview_valid := false
var drag_has_moved := false
var facade_atlas: Texture2D = preload("res://assets/layout/facade_atlas.png")


func setup(layout: Array[StoreFacadePlacement], size: Vector2i = FacadeLayoutValidator.GRID_SIZE) -> void:
	placements = layout
	grid_size = size
	custom_minimum_size = Vector2(grid_size) * CELL_SIZE + Vector2(32.0, 32.0)
	queue_redraw()


func set_selected(placement: StoreFacadePlacement) -> void:
	selected_placement = placement
	queue_redraw()


func set_drag_preview_valid(is_valid: bool) -> void:
	drag_preview_valid = is_valid
	queue_redraw()


func get_cell_at_position(position: Vector2) -> Vector2i:
	return Vector2i(floori((position.x - GRID_ORIGIN.x) / CELL_SIZE), floori((position.y - GRID_ORIGIN.y) / CELL_SIZE))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := get_cell_at_position(event.position)
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
			drag_preview_cell = get_cell_at_position(event.position)
			placement_drag_previewed.emit(dragging_placement, drag_preview_cell)
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and dragging_placement != null:
		var dropped_placement := dragging_placement
		var drop_cell := get_cell_at_position(event.position)
		dragging_placement = null
		if drag_has_moved:
			placement_drop_requested.emit(dropped_placement, drop_cell)
		else:
			cell_pressed.emit(drop_cell)
		queue_redraw()
		accept_event()


func _is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func _find_placement_at(cell: Vector2i) -> StoreFacadePlacement:
	for placement in placements:
		if cell in FacadeLayoutValidator.get_footprint_cells(placement.type, placement.cell):
			return placement
	return null


func _draw() -> void:
	var grid_rect := Rect2(GRID_ORIGIN, Vector2(grid_size) * CELL_SIZE)
	draw_rect(grid_rect, Color("#16232b"), true)
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			draw_rect(Rect2(GRID_ORIGIN + Vector2(x, y) * CELL_SIZE, Vector2.ONE * CELL_SIZE), Color("#314650"), false, 1.0)
	for placement in placements:
		if placement == dragging_placement and drag_has_moved:
			continue
		_draw_placement(placement, placement.cell, false, true)
	if dragging_placement != null and drag_has_moved:
		_draw_placement(dragging_placement, drag_preview_cell, true, drag_preview_valid)


func _draw_placement(placement: StoreFacadePlacement, cell: Vector2i, preview: bool, valid: bool) -> void:
	var size := FacadeLayoutValidator.get_footprint_size(placement.type)
	var rect := Rect2(GRID_ORIGIN + Vector2(cell) * CELL_SIZE + Vector2(4.0, 4.0), Vector2(size) * CELL_SIZE - Vector2(8.0, 8.0))
	var color: Color = Color("#63c6a6", 0.55) if preview and valid else Color("#e06c75", 0.55) if preview else TYPE_COLORS.get(placement.type, Color.WHITE)
	draw_rect(rect, color, true)
	if not preview:
		_draw_component_sprite(rect, placement.type)
	var border := Color("#ffffff", 0.8) if preview else Color("#f6e7b0") if placement == selected_placement else Color("#e8f1ed")
	draw_rect(rect, border, false, 2.0)
	var font := ThemeDB.fallback_font
	var text := str(TYPE_LABELS.get(placement.type, placement.type))
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	var label_rect := Rect2(rect.position.x + 2.0, rect.end.y - 26.0, rect.size.x - 4.0, 24.0)
	draw_rect(label_rect, Color(0.04, 0.08, 0.1, 0.78), true)
	draw_string(font, Vector2(label_rect.get_center().x - text_size.x * 0.5, label_rect.get_center().y + text_size.y * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


func _draw_component_sprite(rect: Rect2, type: String) -> void:
	if facade_atlas == null:
		return
	var source := LayoutSpriteCatalog.get_facade_region(facade_atlas.get_size(), type)
	if source.size == Vector2.ZERO:
		return
	var target := LayoutSpriteCatalog.fit_source_in_rect(source.size, rect, 5.0)
	draw_texture_rect_region(facade_atlas, target, source)
