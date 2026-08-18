@tool
class_name MapAuthoringCanvas
extends Control

signal node_moved(node_id: String)
signal storefront_moved(storefront_id: String)
signal block_moved(block_id: String)

const MAP_SCALE := 0.3
const NODE_RADIUS := 7.0

var document: MapAuthoringDocument
var _dragging_node_id := ""
var _dragging_storefront_id := ""
var _dragging_block_id := ""


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
		return false
	storefront_moved.emit(storefront_id)
	queue_redraw()
	return true


func move_block_to_map(block_id: String, map_position: Vector2) -> bool:
	if document == null or not document.move_block(block_id, map_position):
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
	custom_minimum_size = (max_position + Vector2(80, 80)) * MAP_SCALE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			_dragging_node_id = _find_node_at_screen(mouse_button.position)
			if _dragging_node_id.is_empty():
				_dragging_storefront_id = _find_storefront_at_screen(mouse_button.position)
			if _dragging_node_id.is_empty() and _dragging_storefront_id.is_empty():
				_dragging_block_id = _find_block_at_screen(mouse_button.position)
		else:
			_dragging_node_id = ""
			_dragging_storefront_id = ""
			_dragging_block_id = ""
	elif event is InputEventMouseMotion and not _dragging_node_id.is_empty():
		var motion := event as InputEventMouseMotion
		move_node_to_map(_dragging_node_id, motion.position / MAP_SCALE)
	elif event is InputEventMouseMotion and not _dragging_storefront_id.is_empty():
		var motion := event as InputEventMouseMotion
		move_storefront_to_map(_dragging_storefront_id, motion.position / MAP_SCALE)
	elif event is InputEventMouseMotion and not _dragging_block_id.is_empty():
		var motion := event as InputEventMouseMotion
		move_block_to_map(_dragging_block_id, motion.position / MAP_SCALE)


func _find_node_at_screen(screen_position: Vector2) -> String:
	if document == null:
		return ""
	for raw_node in document.road_graph.nodes.values():
		var node := raw_node as RoadNode
		if node != null and (node.position * MAP_SCALE).distance_to(screen_position) <= NODE_RADIUS:
			return node.id
	return ""


func _find_storefront_at_screen(screen_position: Vector2) -> String:
	if document == null:
		return ""
	for storefront in document.storefronts:
		if (storefront.map_position * MAP_SCALE).distance_to(screen_position) <= NODE_RADIUS:
			return storefront.id
	return ""


func _find_block_at_screen(screen_position: Vector2) -> String:
	if document == null:
		return ""
	var map_position := screen_position / MAP_SCALE
	for index in range(document.blocks.size() - 1, -1, -1):
		var block := document.blocks[index]
		if block.map_bounds.has_point(map_position):
			return block.id
	return ""


func _draw() -> void:
	if document == null:
		return
	for block in document.blocks:
		var rect := Rect2(block.map_bounds.position * MAP_SCALE, block.map_bounds.size * MAP_SCALE)
		draw_rect(rect, Color(0.25, 0.45, 0.55, 0.18), true)
		draw_rect(rect, Color(0.7, 0.8, 0.9, 0.45), false, 1.0)
	for segment in document.road_graph.segments:
		var from_node: RoadNode = document.road_graph.nodes.get(segment.from_node_id, null)
		var to_node: RoadNode = document.road_graph.nodes.get(segment.to_node_id, null)
		if from_node == null or to_node == null:
			continue
		draw_line(from_node.position * MAP_SCALE, to_node.position * MAP_SCALE, Color(0.9, 0.9, 0.95, 0.85), 2.5, true)
	for raw_node in document.road_graph.nodes.values():
		var node := raw_node as RoadNode
		if node == null:
			continue
		var screen_position := node.position * MAP_SCALE
		draw_circle(screen_position, NODE_RADIUS, Color(1.0, 0.72, 0.25, 1.0))
		draw_string(ThemeDB.fallback_font, screen_position + Vector2(9, 4), node.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	for storefront in document.storefronts:
		var storefront_position := storefront.map_position * MAP_SCALE
		draw_circle(storefront_position, 5.0, Color(0.25, 0.95, 0.55, 1.0))
		draw_circle(storefront_position, 5.0, Color(0.05, 0.1, 0.05, 0.9), false, 1.0)
