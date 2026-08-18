extends Node

var passed := 0
var failed := 0


func _ready() -> void:
	_test_cardinal_adjacency_for_each_road_width()
	_test_diagonal_contact_is_not_adjacency()
	_test_irregular_block_with_only_bottom_cells_touching()
	_test_block_move_along_a_road()
	print("========== Map Road Adjacency Contract Test: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _test_cardinal_adjacency_for_each_road_width() -> void:
	for road_class in ["alley", "local", "secondary", "arterial"]:
		var document := MapAuthoringDocument.new()
		_assert(document.add_grid_road("road_" + road_class, Vector2i(10, 10), Vector2i(20, 10), road_class), road_class + " road is created")
		var occupied: Array[Vector2i] = _road_cells(document)
		var top_edge := _edge_cell(occupied, Vector2i.UP)
		var bottom_edge := _edge_cell(occupied, Vector2i.DOWN)
		var left_edge := _edge_cell(occupied, Vector2i.LEFT)
		var right_edge := _edge_cell(occupied, Vector2i.RIGHT)
		_assert(_create_single_cell_block(document, "top_" + road_class, top_edge + Vector2i.UP) != null, road_class + " road accepts a block directly above its occupied cells")
		_assert(_create_single_cell_block(document, "bottom_" + road_class, bottom_edge + Vector2i.DOWN) != null, road_class + " road accepts a block directly below its occupied cells")
		_assert(_create_single_cell_block(document, "left_" + road_class, left_edge + Vector2i.LEFT) != null, road_class + " road accepts a block directly left of its occupied cells")
		_assert(_create_single_cell_block(document, "right_" + road_class, right_edge + Vector2i.RIGHT) != null, road_class + " road accepts a block directly right of its occupied cells")


func _test_diagonal_contact_is_not_adjacency() -> void:
	var document := MapAuthoringDocument.new()
	document.add_grid_road("diagonal_road", Vector2i(10, 10), Vector2i(15, 10), "alley")
	var occupied: Array[Vector2i] = _road_cells(document)
	var top_edge := _edge_cell(occupied, Vector2i.UP)
	var right_edge := _edge_cell(occupied, Vector2i.RIGHT)
	var corner := Vector2i(right_edge.x + 1, top_edge.y - 1)
	_assert(_create_single_cell_block(document, "diagonal_only", corner) == null, "corner-only contact is rejected; blocks must share an edge with a road")


func _test_irregular_block_with_only_bottom_cells_touching() -> void:
	var document := MapAuthoringDocument.new()
	document.add_grid_road("bottom_road", Vector2i(10, 10), Vector2i(20, 10), "alley")
	# This reproduces the pictured shape: its bottom row, not its bounding rectangle,
	# is the only part that touches the road.
	var cells: Array[Vector2i] = [
		Vector2i(14, 7), Vector2i(14, 8), Vector2i(14, 9),
		Vector2i(13, 9), Vector2i(15, 9),
	]
	var block := document.create_block_from_cells("bottom_touch_shape", "Bottom Touch Shape", "TEST_REGION", cells, "commercial", 1)
	_assert(block != null, "irregular block is legal when any bottom cell shares an edge with the road")
	if block != null:
		_assert(not document._block_overlaps_road(block), "bottom-touching irregular block does not overlap road cells")
		_assert(document._cells_touch_road(block.grid_cells), "bottom-touching irregular block reports road adjacency")


func _test_block_move_along_a_road() -> void:
	var document := MapAuthoringDocument.new()
	document.add_grid_road("move_road", Vector2i(0, 0), Vector2i(20, 0), "alley")
	var block := _create_single_cell_block(document, "move_block", Vector2i(3, 1))
	_assert(block != null, "movable block starts adjacent to the road")
	if block == null:
		return
	var target := block.center_position + Vector2(6.0 * MapAuthoringDocument.GRID_CELL_SIZE, 0.0)
	_assert(document.move_block(block.id, target), "moving a block parallel to an adjacent road remains legal")
	_assert(document._cells_touch_road(block.grid_cells), "moved block remains road-adjacent after final validation")
	_assert(not document._block_overlaps_road(block), "already-adjacent block is not snapped into the road during final validation")


func _create_single_cell_block(document: MapAuthoringDocument, block_id: String, cell: Vector2i) -> BlockData:
	var cells: Array[Vector2i] = [cell]
	return document.create_block_from_cells(block_id, block_id, "TEST_REGION", cells, "commercial", 1)


func _road_cells(document: MapAuthoringDocument) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for raw_cell in document.road_cells.keys():
		if raw_cell is Vector2i:
			cells.append(raw_cell)
	return cells


func _edge_cell(cells: Array[Vector2i], direction: Vector2i) -> Vector2i:
	var result := cells[0]
	for cell in cells:
		if direction == Vector2i.UP and cell.y < result.y:
			result = cell
		elif direction == Vector2i.DOWN and cell.y > result.y:
			result = cell
		elif direction == Vector2i.LEFT and cell.x < result.x:
			result = cell
		elif direction == Vector2i.RIGHT and cell.x > result.x:
			result = cell
	return result


func _assert(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)
