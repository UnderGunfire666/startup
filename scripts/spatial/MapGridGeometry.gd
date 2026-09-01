class_name MapGridGeometry
extends RefCounted

const CELL_SIZE := 3.5
const ROAD_CLASS_DATA := {
	"alley": {"width": 1, "accessibility": 0.55, "exposure": 0.45},
	"local": {"width": 2, "accessibility": 0.75, "exposure": 0.65},
	"secondary": {"width": 4, "accessibility": 0.9, "exposure": 0.9},
	"arterial": {"width": 6, "accessibility": 1.0, "exposure": 1.15},
}

static func build_road_cells(road_graph: RoadGraph) -> Dictionary:
	var cells: Dictionary = {}
	if road_graph == null:
		return cells
	for segment in road_graph.segments:
		var from_node: RoadNode = road_graph.nodes.get(segment.from_node_id, null)
		var to_node: RoadNode = road_graph.nodes.get(segment.to_node_id, null)
		if from_node == null or to_node == null:
			continue
		var road_class := segment.road_class if ROAD_CLASS_DATA.has(segment.road_class) else "local"
		paint_road_segment(cells, from_node.position, to_node.position, int(ROAD_CLASS_DATA[road_class].width), road_class, segment.id)
	return cells


static func build_road_center_cells(road_graph: RoadGraph) -> Dictionary:
	var cells: Dictionary = {}
	if road_graph == null:
		return cells
	for segment in road_graph.segments:
		var from_node: RoadNode = road_graph.nodes.get(segment.from_node_id, null)
		var to_node: RoadNode = road_graph.nodes.get(segment.to_node_id, null)
		if from_node == null or to_node == null:
			continue
		var from_cell := Vector2i(floori(from_node.position.x / CELL_SIZE), floori(from_node.position.y / CELL_SIZE))
		var to_cell := Vector2i(floori(to_node.position.x / CELL_SIZE), floori(to_node.position.y / CELL_SIZE))
		for cell in raster_line(from_cell, to_cell):
			cells[cell] = true
	return cells


static func get_road_color(road_class: String) -> Color:
	match road_class:
		"alley": return Color(0.26, 0.28, 0.31, 1.0)
		"secondary": return Color(0.42, 0.44, 0.48, 1.0)
		"arterial": return Color(0.58, 0.60, 0.64, 1.0)
		_: return Color(0.34, 0.36, 0.40, 1.0)


static func paint_road_segment(cells: Dictionary, from: Vector2, to: Vector2, width: int, road_class: String, segment_id: String) -> void:
	var direction := to - from
	var squared_length := direction.length_squared()
	if squared_length <= 0.0:
		return
	var from_cell := Vector2i(floori(from.x / CELL_SIZE), floori(from.y / CELL_SIZE))
	var to_cell := Vector2i(floori(to.x / CELL_SIZE), floori(to.y / CELL_SIZE))
	for path_cell in raster_line(from_cell, to_cell):
		var start_offset := -int(width / 2)
		for x in range(path_cell.x + start_offset, path_cell.x + start_offset + width):
			for y in range(path_cell.y + start_offset, path_cell.y + start_offset + width):
				var occupied_cell := Vector2i(x, y)
				var center := (Vector2(occupied_cell) + Vector2(0.5, 0.5)) * CELL_SIZE
				var progress := (center - from).dot(direction)
				if progress > 0.0 and progress < squared_length:
					cells[occupied_cell] = {"class": road_class, "segment_id": segment_id}


static func raster_line(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var line_from := Vector2(from_cell)
	var line_to := Vector2(to_cell)
	var min_x := floori(minf(line_from.x, line_to.x))
	var max_x := ceili(maxf(line_from.x, line_to.x)) - 1
	var min_y := floori(minf(line_from.y, line_to.y))
	var max_y := ceili(maxf(line_from.y, line_to.y)) - 1
	if is_equal_approx(line_from.x, line_to.x):
		min_x = floori(line_from.x)
		max_x = min_x
	if is_equal_approx(line_from.y, line_to.y):
		min_y = floori(line_from.y)
		max_y = min_y
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var cell := Vector2i(x, y)
			if _segment_enters_grid_cell(line_from, line_to, cell):
				cells.append(cell)
	return cells


static func _segment_enters_grid_cell(line_from: Vector2, line_to: Vector2, cell: Vector2i) -> bool:
	var direction := line_to - line_from
	var entry_time := 0.0
	var exit_time := 1.0
	for axis in range(2):
		var position := line_from.x if axis == 0 else line_from.y
		var delta := direction.x if axis == 0 else direction.y
		var cell_min := float(cell.x if axis == 0 else cell.y)
		var cell_max := cell_min + 1.0
		if is_zero_approx(delta):
			if position < cell_min or position >= cell_max:
				return false
			continue
		var first_time := (cell_min - position) / delta
		var second_time := (cell_max - position) / delta
		if first_time > second_time:
			var swap_time := first_time
			first_time = second_time
			second_time = swap_time
		entry_time = maxf(entry_time, first_time)
		exit_time = minf(exit_time, second_time)
		if exit_time < entry_time:
			return false
	return exit_time >= entry_time and exit_time > 0.0 and entry_time < 1.0
