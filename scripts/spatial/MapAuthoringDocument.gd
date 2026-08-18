class_name MapAuthoringDocument
extends RefCounted

var road_graph: RoadGraph = RoadGraph.new()
var blocks: Array[BlockData] = []
var storefronts: Array[StorefrontData] = []
var _block_move_snapshots: Dictionary = {}
const GRID_CELL_SIZE: float = 3.5
const ROAD_CLASS_DATA := {
	"alley": {"width": 1, "accessibility": 0.55, "exposure": 0.45},
	"local": {"width": 2, "accessibility": 0.75, "exposure": 0.65},
	"secondary": {"width": 4, "accessibility": 0.9, "exposure": 0.9},
	"arterial": {"width": 6, "accessibility": 1.0, "exposure": 1.15},
}
const ROAD_CLASS_LABELS := {"alley": "小巷", "local": "支路", "secondary": "次干路", "arterial": "主干路"}
var road_cells: Dictionary = {}


static func from_static_data() -> MapAuthoringDocument:
	var document := MapAuthoringDocument.new()
	var source_graph := GameData.get_road_graph()
	for raw_node in source_graph.nodes.values():
		var source_node := raw_node as RoadNode
		if source_node == null:
			continue
		var node := RoadNode.new()
		node.id = source_node.id
		node.position = source_node.position
		document.road_graph.add_node(node)
	for source_segment in source_graph.segments:
		var segment := RoadSegment.new()
		segment.id = source_segment.id
		segment.from_node_id = source_segment.from_node_id
		segment.to_node_id = source_segment.to_node_id
		segment.accessibility = source_segment.accessibility
		segment.exposure = source_segment.exposure
		document.road_graph.add_segment(segment)
		var from_node: RoadNode = source_graph.nodes.get(segment.from_node_id, null)
		var to_node: RoadNode = source_graph.nodes.get(segment.to_node_id, null)
		if from_node != null and to_node != null:
			for cell in document._raster_line(
				Vector2i(floori(from_node.position.x / GRID_CELL_SIZE), floori(from_node.position.y / GRID_CELL_SIZE)),
				Vector2i(floori(to_node.position.x / GRID_CELL_SIZE), floori(to_node.position.y / GRID_CELL_SIZE))):
				document._paint_road_width(cell, 2, "local", segment.id)
	for source_block in GameData.get_blocks():
		var block := source_block.duplicate() as BlockData
		document.blocks.append(block)
	for source_storefront in GameData.get_storefronts():
		document.storefronts.append(source_storefront.duplicate() as StorefrontData)
	document._ensure_storefront_grid_cells()
	document._ensure_storefront_block_assignments()
	return document


func add_road_node(node_id: String, position: Vector2) -> bool:
	var node := RoadNode.new()
	node.id = node_id
	node.position = snap_world_to_grid_intersection(position)
	return road_graph.add_node(node)


func remove_road_node(node_id: String) -> bool:
	if not road_graph.nodes.has(node_id):
		return false
	for index in range(road_graph.segments.size() - 1, -1, -1):
		var segment := road_graph.segments[index]
		if segment.from_node_id == node_id or segment.to_node_id == node_id:
			remove_road_segment(segment.id)
	road_graph.nodes.erase(node_id)
	return true


func remove_road_segment(segment_id: String) -> bool:
	for index in range(road_graph.segments.size() - 1, -1, -1):
		if road_graph.segments[index].id == segment_id:
			road_graph.segments.remove_at(index)
			var occupied_cells := road_cells.keys()
			for cell in occupied_cells:
				if str(road_cells[cell].get("segment_id", "")) == segment_id:
					road_cells.erase(cell)
			return true
	return false


func remove_block(block_id: String) -> bool:
	for index in range(blocks.size() - 1, -1, -1):
		if blocks[index].id == block_id:
			blocks.remove_at(index)
			return true
	return false


func remove_storefront(storefront_id: String) -> bool:
	for index in range(storefronts.size() - 1, -1, -1):
		if storefronts[index].id == storefront_id:
			storefronts.remove_at(index)
			return true
	return false


func move_road_node(node_id: String, position: Vector2) -> bool:
	var node: RoadNode = road_graph.nodes.get(node_id, null)
	if node == null:
		return false
	node.position = snap_world_to_grid_intersection(position)
	_rebuild_road_cells()
	return true


func snap_world_to_grid_intersection(position: Vector2) -> Vector2:
	return grid_to_world_intersection(Vector2i(roundi(position.x / GRID_CELL_SIZE), roundi(position.y / GRID_CELL_SIZE)))


func add_road_segment(segment_id: String, from_node_id: String, to_node_id: String, accessibility: float = 1.0, exposure: float = 1.0) -> bool:
	if _has_road_segment(segment_id):
		return false
	var segment := RoadSegment.new()
	segment.id = segment_id
	segment.from_node_id = from_node_id
	segment.to_node_id = to_node_id
	segment.accessibility = accessibility
	segment.exposure = exposure
	return road_graph.add_segment(segment)


func add_grid_road(segment_id: String, from_cell: Vector2i, to_cell: Vector2i, road_class: String) -> bool:
	if _has_road_segment(segment_id) or not ROAD_CLASS_DATA.has(road_class):
		return false
	if _is_road_path_already_occupied(from_cell, to_cell):
		return false
	if _extend_straight_road_if_possible(from_cell, to_cell):
		return true
	var from_id := _get_node_id_at_cell(from_cell)
	var to_id := _get_node_id_at_cell(to_cell)
	if from_id.is_empty():
		from_id = segment_id + "_from"
		if not add_road_node(from_id, grid_to_world_intersection(from_cell)):
			return false
	if to_id.is_empty():
		to_id = segment_id + "_to"
		if not add_road_node(to_id, grid_to_world_intersection(to_cell)):
			return false
	if from_id == to_id:
		return false
	if not _can_connect_road_class(from_id, road_class) or not _can_connect_road_class(to_id, road_class):
		return false
	var data: Dictionary = ROAD_CLASS_DATA[road_class]
	if not add_road_segment(segment_id, from_id, to_id, float(data.accessibility), float(data.exposure)):
		return false
	for cell in _raster_line(from_cell, to_cell):
		_paint_road_width(cell, int(data.width), road_class, segment_id)
	return true


func _get_node_id_at_cell(cell: Vector2i) -> String:
	var target := grid_to_world_intersection(cell)
	for raw_node in road_graph.nodes.values():
		var node := raw_node as RoadNode
		if node != null and node.position.is_equal_approx(target):
			return node.id
	return ""


func _extend_straight_road_if_possible(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var endpoint_id := _get_node_id_at_cell(from_cell)
	if endpoint_id.is_empty():
		return false
	var endpoint: RoadNode = road_graph.nodes.get(endpoint_id, null)
	if endpoint == null:
		return false
	var connected: Array[RoadSegment] = []
	for segment in road_graph.segments:
		if segment.from_node_id == endpoint_id or segment.to_node_id == endpoint_id:
			connected.append(segment)
	if connected.size() != 1:
		return false
	var segment := connected[0]
	var other_id := segment.to_node_id if segment.from_node_id == endpoint_id else segment.from_node_id
	var other: RoadNode = road_graph.nodes.get(other_id, null)
	var new_position := grid_to_world_intersection(to_cell)
	if other == null or new_position.is_equal_approx(endpoint.position):
		return false
	var old_direction := endpoint.position - other.position
	var extension := new_position - endpoint.position
	if absf(old_direction.cross(extension)) > 0.01 or old_direction.dot(extension) <= 0.0:
		return false
	endpoint.position = new_position
	_rebuild_road_cells()
	return true


func _is_road_path_already_occupied(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var path := _raster_line(from_cell, to_cell)
	if path.is_empty():
		return false
	for cell in path:
		if not road_cells.has(cell):
			return false
	return true


func get_road_class(segment_id: String) -> String:
	for cell in road_cells:
		var road_data: Dictionary = road_cells[cell]
		if str(road_data.get("segment_id", "")) == segment_id:
			return str(road_data.get("class", "local"))
	return "local"


func set_road_class(segment_id: String, road_class: String) -> bool:
	if not ROAD_CLASS_DATA.has(road_class) or not _has_road_segment(segment_id):
		return false
	for cell in road_cells:
		var road_data: Dictionary = road_cells[cell]
		if str(road_data.get("segment_id", "")) == segment_id:
			road_data["class"] = road_class
			road_cells[cell] = road_data
	_rebuild_road_cells()
	return true


func grid_to_world_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * GRID_CELL_SIZE


func grid_to_world_intersection(point: Vector2i) -> Vector2:
	return Vector2(point) * GRID_CELL_SIZE


func create_block_from_cells(block_id: String, block_name: String, city_region_id: String, cells: Array[Vector2i], block_type: String, tier: int) -> BlockData:
	if block_id.is_empty() or city_region_id.is_empty() or cells.is_empty() or _has_block(block_id):
		return null
	for cell in cells:
		if road_cells.has(cell) or _cell_belongs_to_other_block(cell, ""):
			return null
	if not _cells_touch_road(cells):
		return null
	var block := BlockData.new()
	block.id = block_id
	block.name = block_name
	block.city_region_id = city_region_id
	block.block_type = block_type
	block.tier = clampi(tier, 1, 3)
	block.grid_cell_size = GRID_CELL_SIZE
	block.grid_cells = cells.duplicate()
	block.area = float(cells.size()) * GRID_CELL_SIZE * GRID_CELL_SIZE
	block.rebuild_bounds_from_grid_cells()
	block.road_entry_node_id = _find_nearest_road_node(block.center_position)
	blocks.append(block)
	return block


func add_cells_to_block(block_id: String, cells: Array[Vector2i]) -> bool:
	for block in blocks:
		if block.id != block_id:
			continue
		for cell in cells:
			if road_cells.has(cell) or _cell_belongs_to_other_block(cell, block_id):
				return false
		if not _cells_touch_block(cells, block.grid_cells) or not _cells_are_connected(cells):
			return false
		for cell in cells:
			if not block.grid_cells.has(cell):
				block.grid_cells.append(cell)
		if not _cells_touch_road(block.grid_cells):
			return false
		block.area = float(block.grid_cells.size()) * GRID_CELL_SIZE * GRID_CELL_SIZE
		block.rebuild_bounds_from_grid_cells()
		return true
	return false


func create_storefront_from_cells(storefront_id: String, storefront_name: String, city_region_id: String, cells: Array[Vector2i]) -> StorefrontData:
	if storefront_id.is_empty() or cells.is_empty() or _get_storefront(storefront_id) != null:
		return null
	if not _cells_are_connected(cells) or not _storefront_cells_valid(cells, ""):
		return null
	var block := _find_block_containing_cells(cells, city_region_id)
	if block == null:
		return null
	var storefront := StorefrontData.new()
	storefront.id = storefront_id
	storefront.name = storefront_name
	storefront.city_region_id = city_region_id
	storefront.grid_cells = cells.duplicate()
	storefront.map_position = _grid_cells_center(cells)
	_set_storefront_block(storefront, block)
	storefronts.append(storefront)
	assign_storefront_nearest_road(storefront.id)
	return storefront


func add_cells_to_storefront(storefront_id: String, cells: Array[Vector2i]) -> bool:
	var storefront := _get_storefront(storefront_id)
	if storefront == null or cells.is_empty():
		return false
	_ensure_storefront_grid_cells()
	var combined: Array[Vector2i] = storefront.grid_cells.duplicate()
	for cell in cells:
		if not combined.has(cell):
			combined.append(cell)
	if combined.size() == storefront.grid_cells.size() or not _cells_touch_block(cells, storefront.grid_cells):
		return false
	if not _cells_are_connected(combined) or not _storefront_cells_valid(combined, storefront.id):
		return false
	var block := _find_block_containing_cells(combined, storefront.city_region_id)
	if block == null:
		return false
	storefront.grid_cells = combined
	storefront.map_position = _grid_cells_center(combined)
	_set_storefront_block(storefront, block)
	assign_storefront_nearest_road(storefront.id)
	return true


func update_block_properties(block_id: String, block_name: String, city_region_id: String, block_type: String, tier: int) -> bool:
	for block in blocks:
		if block.id == block_id:
			block.name = block_name
			block.city_region_id = city_region_id
			block.block_type = block_type
			block.tier = clampi(tier, 1, 3)
			return true
	return false


func assign_block_road_entry(block_id: String, node_id: String) -> bool:
	if not road_graph.nodes.has(node_id):
		return false
	for block in blocks:
		if block.id == block_id:
			block.road_entry_node_id = node_id
			return true
	return false


func assign_storefront_nearest_road(storefront_id: String) -> bool:
	var storefront := _get_storefront(storefront_id)
	if storefront == null or road_graph.segments.is_empty():
		return false
	var nearest_segment_id := ""
	var nearest_distance := INF
	for segment in road_graph.segments:
		var from_node: RoadNode = road_graph.nodes.get(segment.from_node_id, null)
		var to_node: RoadNode = road_graph.nodes.get(segment.to_node_id, null)
		if from_node == null or to_node == null:
			continue
		var distance := _distance_to_segment(storefront.map_position, from_node.position, to_node.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_segment_id = segment.id
	if nearest_segment_id.is_empty():
		return false
	storefront.road_segment_id = nearest_segment_id
	return true


func move_storefront(storefront_id: String, position: Vector2) -> bool:
	var storefront := _get_storefront(storefront_id)
	if storefront == null:
		return false
	_ensure_storefront_grid_cells()
	var original_position := storefront.map_position
	var original_segment := storefront.road_segment_id
	var original_block_id := storefront.block_id
	var original_local_position := storefront.block_local_position
	var original_cells := storefront.grid_cells.duplicate()
	var cell_offset := Vector2i(roundi((position.x - storefront.map_position.x) / GRID_CELL_SIZE), roundi((position.y - storefront.map_position.y) / GRID_CELL_SIZE))
	for index in range(storefront.grid_cells.size()):
		storefront.grid_cells[index] += cell_offset
	storefront.map_position += Vector2(cell_offset) * GRID_CELL_SIZE
	var containing_block := _find_block_containing_cells(storefront.grid_cells, storefront.city_region_id)
	if containing_block == null or not _storefront_cells_valid(storefront.grid_cells, storefront.id):
		storefront.map_position = original_position
		storefront.grid_cells = original_cells
		storefront.road_segment_id = original_segment
		storefront.block_id = original_block_id
		storefront.block_local_position = original_local_position
		return false
	if not assign_storefront_nearest_road(storefront_id) or containing_block == null:
		storefront.map_position = original_position
		storefront.grid_cells = original_cells
		storefront.road_segment_id = original_segment
		storefront.block_id = original_block_id
		storefront.block_local_position = original_local_position
		return false
	_set_storefront_block(storefront, containing_block)
	return true


func move_block(block_id: String, center_position: Vector2) -> bool:
	if not begin_block_move(block_id):
		return false
	if move_block_preview(block_id, center_position) and finish_block_move(block_id):
		return true
	cancel_block_move(block_id)
	return false


func begin_block_move(block_id: String) -> bool:
	var block := _get_block(block_id)
	if block == null:
		return false
	if _block_move_snapshots.has(block_id):
		return true
	_ensure_storefront_block_assignments()
	var storefront_state: Array[Dictionary] = []
	for storefront in storefronts:
		if storefront.block_id == block_id:
			storefront_state.append({
				"storefront": storefront,
				"map_position": storefront.map_position,
				"local_position": storefront.block_local_position,
			})
	_block_move_snapshots[block_id] = {
		"cells": block.grid_cells.duplicate(),
		"bounds": block.map_bounds,
		"center": block.center_position,
		"storefronts": storefront_state,
	}
	return true


func finish_block_move(block_id: String) -> bool:
	if not _block_move_snapshots.has(block_id):
		return false
	if finalize_block_move(block_id):
		_block_move_snapshots.erase(block_id)
		return true
	cancel_block_move(block_id)
	return false


func cancel_block_move(block_id: String) -> void:
	var snapshot: Dictionary = _block_move_snapshots.get(block_id, {})
	var block := _get_block(block_id)
	if block != null and not snapshot.is_empty():
		var restored_cells: Array[Vector2i] = []
		var raw_cells: Array = snapshot.get("cells", [])
		for raw_cell in raw_cells:
			if raw_cell is Vector2i:
				restored_cells.append(raw_cell)
		block.grid_cells = restored_cells
		block.map_bounds = snapshot.get("bounds", Rect2())
		block.center_position = snapshot.get("center", Vector2.ZERO)
		for state in snapshot.get("storefronts", []):
			var storefront: StorefrontData = state.get("storefront", null)
			if storefront != null:
				storefront.map_position = state.get("map_position", Vector2.ZERO)
				storefront.block_local_position = state.get("local_position", Vector2.ZERO)
	_block_move_snapshots.erase(block_id)


func move_block_preview(block_id: String, center_position: Vector2) -> bool:
	for block in blocks:
		if block.id != block_id:
			continue
		var offset := center_position - block.center_position
		if not block.grid_cells.is_empty():
			var cell_offset := Vector2i(roundi(offset.x / block.grid_cell_size), roundi(offset.y / block.grid_cell_size))
			for index in range(block.grid_cells.size()):
				block.grid_cells[index] += cell_offset
			block.rebuild_bounds_from_grid_cells()
		else:
			block.center_position = center_position
			block.map_bounds.position += offset
		_sync_storefronts_for_block(block)
		return true
	return false


func finalize_block_move(block_id: String) -> bool:
	for block in blocks:
		if block.id != block_id:
			continue
		_snap_block_to_road(block)
		_sync_storefronts_for_block(block)
		return not _block_overlaps_road(block) and not _cells_overlap_other_blocks(block.grid_cells, block.id) and _cells_touch_road(block.grid_cells)
	return false


func _snap_block_to_road(block: BlockData) -> void:
	if block == null or block.grid_cells.is_empty():
		return
	# A block that already shares an edge with a road is valid. Do not snap it again:
	# doing so can shift it into the road cells and make a legal placement fail.
	if _cells_touch_road(block.grid_cells):
		return
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var shifted_cells: Array[Vector2i] = []
		for cell in block.grid_cells:
			shifted_cells.append(cell + offset)
		if not _cells_overlap_road(shifted_cells) and _cells_touch_road(shifted_cells):
			block.grid_cells = shifted_cells
			block.rebuild_bounds_from_grid_cells()
			return


func _block_overlaps_road(block: BlockData) -> bool:
	return _cells_overlap_road(block.grid_cells)


func _cells_overlap_road(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if road_cells.has(cell):
			return true
	return false


func _storefront_is_inside_any_block(storefront: StorefrontData) -> bool:
	return _find_block_containing_storefront(storefront) != null


func _find_block_containing_storefront(storefront: StorefrontData) -> BlockData:
	if not storefront.grid_cells.is_empty():
		return _find_block_containing_cells(storefront.grid_cells, storefront.city_region_id)
	for block in blocks:
		if block.city_region_id == storefront.city_region_id and block.has_map_point(storefront.map_position):
			return block
	return null


func _find_block_containing_cells(cells: Array[Vector2i], city_region_id: String) -> BlockData:
	for block in blocks:
		if block.city_region_id != city_region_id:
			continue
		var all_inside := true
		for cell in cells:
			if not block.grid_cells.has(cell):
				all_inside = false
				break
		if all_inside:
			return block
	return null


func _get_block(block_id: String) -> BlockData:
	for block in blocks:
		if block.id == block_id:
			return block
	return null


func _set_storefront_block(storefront: StorefrontData, block: BlockData) -> void:
	storefront.block_id = block.id
	storefront.block_local_position = storefront.map_position - block.center_position


func _ensure_storefront_block_assignments() -> void:
	_ensure_storefront_grid_cells()
	for storefront in storefronts:
		var block := _get_block(storefront.block_id)
		if block != null and block.city_region_id == storefront.city_region_id and _storefront_cells_are_inside_block(storefront, block):
			storefront.block_local_position = storefront.map_position - block.center_position
			continue
		var containing_block := _find_block_containing_storefront(storefront)
		if containing_block != null:
			_set_storefront_block(storefront, containing_block)


func _sync_storefronts_for_block(block: BlockData) -> void:
	for storefront in storefronts:
		if storefront.block_id == block.id:
			var target_position := block.center_position + storefront.block_local_position
			var cell_offset := Vector2i(roundi((target_position.x - storefront.map_position.x) / GRID_CELL_SIZE), roundi((target_position.y - storefront.map_position.y) / GRID_CELL_SIZE))
			for index in range(storefront.grid_cells.size()):
				storefront.grid_cells[index] += cell_offset
			storefront.map_position = target_position


func _storefront_is_inside_block(storefront: StorefrontData, block: BlockData, cells: Array[Vector2i]) -> bool:
	if cells.is_empty(): return block.map_bounds.has_point(storefront.map_position)
	var cell := Vector2i(floori(storefront.map_position.x / block.grid_cell_size), floori(storefront.map_position.y / block.grid_cell_size))
	return cells.has(cell)


func _storefront_cells_are_inside_block(storefront: StorefrontData, block: BlockData) -> bool:
	if storefront.grid_cells.is_empty():
		return block.has_map_point(storefront.map_position)
	for cell in storefront.grid_cells:
		if not block.grid_cells.has(cell):
			return false
	return true


func _ensure_storefront_grid_cells() -> void:
	for storefront in storefronts:
		if storefront.grid_cells.is_empty():
			storefront.grid_cells.append(Vector2i(floori(storefront.map_position.x / GRID_CELL_SIZE), floori(storefront.map_position.y / GRID_CELL_SIZE)))


func _storefront_cells_valid(cells: Array[Vector2i], ignored_storefront_id: String) -> bool:
	if cells.is_empty():
		return false
	for cell in cells:
		if road_cells.has(cell) or _cell_belongs_to_other_storefront(cell, ignored_storefront_id):
			return false
	return true


func _cell_belongs_to_other_storefront(cell: Vector2i, ignored_storefront_id: String) -> bool:
	for storefront in storefronts:
		if storefront.id != ignored_storefront_id and storefront.grid_cells.has(cell):
			return true
	return false


func _cell_belongs_to_other_block(cell: Vector2i, ignored_block_id: String) -> bool:
	for block in blocks:
		if block.id != ignored_block_id and block.grid_cells.has(cell):
			return true
	return false


func _cells_overlap_other_blocks(cells: Array[Vector2i], ignored_block_id: String) -> bool:
	for cell in cells:
		if _cell_belongs_to_other_block(cell, ignored_block_id):
			return true
	return false


func _grid_cells_center(cells: Array[Vector2i]) -> Vector2:
	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell in cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	return Rect2(Vector2(min_cell) * GRID_CELL_SIZE, Vector2(max_cell - min_cell + Vector2i.ONE) * GRID_CELL_SIZE).get_center()


func validate() -> Array[String]:
	_ensure_storefront_grid_cells()
	_ensure_storefront_block_assignments()
	var errors := MapDataValidator.validate(road_graph, blocks, storefronts)
	for block in blocks:
		if block.grid_cells.is_empty():
			continue
		if not _cells_touch_road(block.grid_cells):
			errors.append("block %s is not adjacent to a road" % block.id)
		for cell in block.grid_cells:
			if road_cells.has(cell):
				errors.append("block %s overlaps a road" % block.id)
				break
		if _cells_overlap_other_blocks(block.grid_cells, block.id):
			errors.append("block %s overlaps another block" % block.id)
	for storefront in storefronts:
		if storefront.grid_cells.is_empty():
			errors.append("storefront %s has no occupied grid cells" % storefront.id)
		elif not _cells_are_connected(storefront.grid_cells):
			errors.append("storefront %s has disconnected grid cells" % storefront.id)
		elif not _storefront_cells_valid(storefront.grid_cells, storefront.id):
			errors.append("storefront %s overlaps a road or another storefront" % storefront.id)
		elif _find_block_containing_cells(storefront.grid_cells, storefront.city_region_id) == null:
			errors.append("storefront %s is not fully inside one block" % storefront.id)
	return errors


func export_roads_data() -> Dictionary:
	var errors := validate()
	if not errors.is_empty():
		return {"success": false, "errors": errors, "roads": []}
	return {"success": true, "errors": [], "roads": _serialize_roads()}


func export_map_data() -> Dictionary:
	var errors := validate()
	if not errors.is_empty():
		return {"success": false, "errors": errors, "roads": [], "blocks": [], "storefronts": []}
	var serialized_blocks: Array[Dictionary] = []
	for block in blocks:
		serialized_blocks.append({
			"id": block.id, "name": block.name, "city_region_id": block.city_region_id,
			"road_entry_node_id": block.road_entry_node_id,
			"map_bounds": {"x": block.map_bounds.position.x, "y": block.map_bounds.position.y, "w": block.map_bounds.size.x, "h": block.map_bounds.size.y},
			"center_position": {"x": block.center_position.x, "y": block.center_position.y},
			"grid_cell_size": block.grid_cell_size,
			"grid_cells": _serialize_grid_cells(block.grid_cells),
			"block_type": block.block_type, "tier": block.tier, "area": block.area,
			"development_factor": block.development_factor, "accessibility": block.accessibility,
			"active_time_profile": block.active_time_profile.duplicate(true),
			"group_supply_weights": block.group_supply_weights.duplicate(true),
			"spending_profile": block.spending_profile.duplicate(true),
			"business_demand_tags": block.business_demand_tags.duplicate(),
			"competition_profile": block.competition_profile.duplicate(true),
			"tags": block.tags.duplicate(), "notes": block.notes,
		})
	var serialized_storefronts: Array[Dictionary] = []
	for storefront in storefronts:
		serialized_storefronts.append({
			"id": storefront.id, "name": storefront.name, "region_id": storefront.region_id,
			"city_region_id": storefront.city_region_id,
			"road_segment_id": storefront.road_segment_id,
			"map_position": {"x": storefront.map_position.x, "y": storefront.map_position.y},
			"block_id": storefront.block_id,
			"block_local_position": {"x": storefront.block_local_position.x, "y": storefront.block_local_position.y},
			"grid_cells": _serialize_grid_cells(storefront.grid_cells),
			"capture_modifier": storefront.capture_modifier,
			"accessibility_modifier": storefront.accessibility_modifier,
			"monthly_rent_wan": storefront.monthly_rent_wan, "area": storefront.area,
			"decoration_level": storefront.decoration_level, "storefront_flow": storefront.storefront_flow,
			"flow_share": storefront.flow_share,
			"supported_categories": storefront.supported_categories.duplicate(),
			"equipment_condition": storefront.equipment_condition,
			"hourly_capacity_base": storefront.hourly_capacity_base, "notes": storefront.notes,
		})
	return {
		"success": true, "errors": [], "roads": _serialize_roads(),
		"blocks": serialized_blocks, "storefronts": serialized_storefronts,
	}


func export_json_files() -> Dictionary:
	var exported := export_map_data()
	if not bool(exported.get("success", false)):
		return {"success": false, "errors": exported.get("errors", []), "files": {}}
	return {
		"success": true, "errors": [],
		"files": {
			"roads.json": JSON.stringify(exported.get("roads", []), "\t"),
			"blocks.json": JSON.stringify(exported.get("blocks", []), "\t"),
			"storefronts.json": JSON.stringify(exported.get("storefronts", []), "\t"),
		},
	}


func _serialize_roads() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var node_ids: Array[String] = []
	for node_id in road_graph.nodes.keys():
		node_ids.append(str(node_id))
	node_ids.sort()
	for node_id in node_ids:
		var node: RoadNode = road_graph.nodes.get(node_id, null)
		if node == null:
			continue
		entries.append({
			"kind": "node", "id": node.id,
			"position": {"x": node.position.x, "y": node.position.y},
		})
	for segment in road_graph.segments:
		entries.append({
			"kind": "segment", "id": segment.id,
			"from_node_id": segment.from_node_id, "to_node_id": segment.to_node_id,
			"accessibility": segment.accessibility, "exposure": segment.exposure,
		})
	return entries


func _serialize_grid_cells(cells: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in cells:
		result.append({"x": cell.x, "y": cell.y})
	return result


func _has_block(block_id: String) -> bool:
	for block in blocks:
		if block.id == block_id:
			return true
	return false


func _find_nearest_road_node(position: Vector2) -> String:
	var nearest_id := ""
	var nearest_distance := INF
	for raw_node in road_graph.nodes.values():
		var node := raw_node as RoadNode
		if node != null and node.position.distance_to(position) < nearest_distance:
			nearest_id = node.id
			nearest_distance = node.position.distance_to(position)
	return nearest_id


func _raster_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var delta := to - from
	var steps := maxi(absi(delta.x), absi(delta.y))
	for step in range(steps + 1):
		cells.append(Vector2i(roundi(lerpf(float(from.x), float(to.x), float(step) / float(maxi(1, steps)))), roundi(lerpf(float(from.y), float(to.y), float(step) / float(maxi(1, steps))))))
	return cells


func _paint_road_width(cell: Vector2i, width: int, road_class: String, segment_id: String) -> void:
	var start_offset := -int(width / 2)
	for x in range(cell.x + start_offset, cell.x + start_offset + width):
		for y in range(cell.y + start_offset, cell.y + start_offset + width):
			road_cells[Vector2i(x, y)] = {"class": road_class, "segment_id": segment_id}


func _cells_touch_road(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		for neighbor in [cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN]:
			if road_cells.has(neighbor):
				return true
	return false


func _cells_touch_block(cells: Array[Vector2i], block_cells: Array[Vector2i]) -> bool:
	for cell in cells:
		for neighbor in [cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN]:
			if block_cells.has(neighbor):
				return true
	return false


func _cells_are_connected(cells: Array[Vector2i]) -> bool:
	if cells.is_empty():
		return false
	var visited: Dictionary = {cells[0]: true}
	var pending: Array[Vector2i] = [cells[0]]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for neighbor in [cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN]:
			if cells.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				pending.append(neighbor)
	return visited.size() == cells.size()


func _can_connect_road_class(node_id: String, road_class: String) -> bool:
	var rank: int = ["alley", "local", "secondary", "arterial"].find(road_class)
	for segment in road_graph.segments:
		if segment.from_node_id != node_id and segment.to_node_id != node_id:
			continue
		var other_rank: int = ["alley", "local", "secondary", "arterial"].find(get_road_class(segment.id))
		if other_rank >= 0 and abs(rank - other_rank) > 1:
			return false
	return true


func _rebuild_road_cells() -> void:
	var class_by_segment: Dictionary = {}
	for cell in road_cells:
		var road_data: Dictionary = road_cells[cell]
		class_by_segment[str(road_data.get("segment_id", ""))] = str(road_data.get("class", "local"))
	road_cells.clear()
	for segment in road_graph.segments:
		var from_node: RoadNode = road_graph.nodes.get(segment.from_node_id, null)
		var to_node: RoadNode = road_graph.nodes.get(segment.to_node_id, null)
		if from_node == null or to_node == null:
			continue
		var road_class := str(class_by_segment.get(segment.id, "local"))
		var road_data: Dictionary = ROAD_CLASS_DATA.get(road_class, ROAD_CLASS_DATA["local"])
		for cell in _raster_line(Vector2i(floori(from_node.position.x / GRID_CELL_SIZE), floori(from_node.position.y / GRID_CELL_SIZE)), Vector2i(floori(to_node.position.x / GRID_CELL_SIZE), floori(to_node.position.y / GRID_CELL_SIZE))):
			_paint_road_width(cell, int(road_data.width), road_class, segment.id)


func _has_road_segment(segment_id: String) -> bool:
	for segment in road_graph.segments:
		if segment.id == segment_id:
			return true
	return false


func _get_storefront(storefront_id: String) -> StorefrontData:
	for storefront in storefronts:
		if storefront.id == storefront_id:
			return storefront
	return null


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var direction := to - from
	if is_zero_approx(direction.length_squared()):
		return point.distance_to(from)
	var ratio := clampf((point - from).dot(direction) / direction.length_squared(), 0.0, 1.0)
	return point.distance_to(from + direction * ratio)
