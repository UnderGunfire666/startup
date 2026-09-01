class_name CityMapTravelLayer
extends Control

var map_canvas = null
var road_graph: RoadGraph = null

var _observed_action_id := -1
var _cached_action_id: int = 0
var _cached_route_points: Array[Vector2] = []
var _cached_route_cumulative: Array[float] = []
var _cached_route_total := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_sync_processing)
	ScheduleManager.schedule_changed.connect(refresh_from_state)
	set_process(false)


func setup(owner_canvas, new_road_graph: RoadGraph) -> void:
	map_canvas = owner_canvas
	road_graph = new_road_graph
	_observed_action_id = -1
	_clear_route_cache()
	refresh_from_state()


func refresh_from_state() -> void:
	var action := ScheduleManager.current_action
	var action_id := action.get_instance_id() if action != null and action.is_active else 0
	if action_id == _observed_action_id:
		return
	_observed_action_id = action_id
	if action == null or not action.is_active or action.action_id not in ["move_to_block", "move_to_map_cell"]:
		_clear_route_cache()
	_sync_processing()
	queue_redraw()


func _sync_processing() -> void:
	var action := ScheduleManager.current_action
	var animating := action != null and action.is_active and action.action_id in ["move_to_block", "move_to_map_cell", "region_research"]
	set_process(animating and is_visible_in_tree())
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if map_canvas == null:
		return
	var player := GameManager.player_state
	if not player.is_character_created:
		return
	var position := player.current_map_position
	var action := ScheduleManager.current_action
	if action != null and action.is_active and action.action_id == "region_research":
		var walk_cells: Array = action.context.get("research_walk_cells", [])
		if not walk_cells.is_empty():
			var elapsed_hours := maxf(0.0, (TimeManager.total_game_seconds - action.start_game_seconds) / 3600.0)
			var walk_index := clampi(floori(elapsed_hours / 0.25), 0, walk_cells.size() - 1)
			var raw_cell: Dictionary = walk_cells[walk_index]
			position = (Vector2(float(raw_cell.get("x", 0)), float(raw_cell.get("y", 0))) + Vector2(0.5, 0.5)) * MapGridGeometry.CELL_SIZE
	elif action != null and action.is_active and action.action_id in ["move_to_block", "move_to_map_cell"]:
		var points := _get_cached_route_points(action)
		if points.size() >= 2:
			for index in range(1, points.size()):
				draw_line(map_canvas._map_to_screen(points[index - 1]), map_canvas._map_to_screen(points[index]), Color(0.2, 0.9, 1.0, 0.9), 3.0, true)
			var ratio := clampf((TimeManager.total_game_seconds - action.start_game_seconds) / maxf(1.0, action.duration_hours * 3600.0), 0.0, 1.0)
			position = _interpolate_cached_route(ratio)
	var screen_position: Vector2 = map_canvas._map_to_screen(position)
	draw_circle(screen_position, 6.5, Color(1.0, 0.25, 0.35, 1.0))
	draw_circle(screen_position, 6.5, Color(0.15, 0.02, 0.05, 0.95), false, 1.5)


func _get_cached_route_points(action: CurrentActionState) -> Array[Vector2]:
	var action_id := action.get_instance_id()
	if action_id == _cached_action_id:
		return _cached_route_points
	_clear_route_cache()
	_cached_action_id = action_id
	var quote: Dictionary = action.context.get("travel_quote", {})
	if action.action_id == "move_to_map_cell":
		for raw_cell in quote.get("route_cells", []):
			if raw_cell is Dictionary:
				_cached_route_points.append((Vector2(float(raw_cell.get("x", 0)), float(raw_cell.get("y", 0))) + Vector2(0.5, 0.5)) * MapGridGeometry.CELL_SIZE)
	else:
		for node_id in quote.get("route_node_ids", []):
			var node: RoadNode = road_graph.nodes.get(str(node_id), null) if road_graph != null else null
			if node != null:
				_cached_route_points.append(node.position)
	_cached_route_cumulative.append(0.0)
	for index in range(1, _cached_route_points.size()):
		_cached_route_total += _cached_route_points[index - 1].distance_to(_cached_route_points[index])
		_cached_route_cumulative.append(_cached_route_total)
	return _cached_route_points


func _interpolate_cached_route(ratio: float) -> Vector2:
	if _cached_route_points.is_empty():
		return Vector2.ZERO
	if _cached_route_points.size() == 1 or _cached_route_total <= 0.0001:
		return _cached_route_points[0]
	var distance := clampf(ratio, 0.0, 1.0) * _cached_route_total
	var low := 1
	var high := _cached_route_cumulative.size() - 1
	while low < high:
		var middle := floori(float(low + high) * 0.5)
		if _cached_route_cumulative[middle] < distance:
			low = middle + 1
		else:
			high = middle
	var segment := low
	var start_distance := _cached_route_cumulative[segment - 1]
	var segment_length := _cached_route_cumulative[segment] - start_distance
	return _cached_route_points[segment - 1].lerp(_cached_route_points[segment], (distance - start_distance) / maxf(segment_length, 0.0001))


func _clear_route_cache() -> void:
	_cached_action_id = 0
	_cached_route_points.clear()
	_cached_route_cumulative.clear()
	_cached_route_total = 0.0
