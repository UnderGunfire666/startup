class_name MapAuthoringDocument
extends RefCounted

var road_graph: RoadGraph = RoadGraph.new()
var blocks: Array[BlockData] = []
var storefronts: Array[StorefrontData] = []
var player_homes: Array[Dictionary] = []
var _block_move_snapshots: Dictionary = {}
const GRID_CELL_SIZE: float = 3.5
const STOREFRONT_AREA_PER_GRID_CELL: float = GRID_CELL_SIZE * GRID_CELL_SIZE
const STOREFRONT_MAX_USABLE_AREA_RATIO: float = 0.85
const STOREFRONT_AWARENESS_BASE_CELLS: float = 10.0
const STOREFRONT_AWARENESS_PER_EXTRA_CELL: float = 2.0
const ROAD_CLASS_DATA := MapGridGeometry.ROAD_CLASS_DATA
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
		segment.road_class = source_segment.road_class
		document.road_graph.add_segment(segment)
		var from_node: RoadNode = source_graph.nodes.get(segment.from_node_id, null)
		var to_node: RoadNode = source_graph.nodes.get(segment.to_node_id, null)
		if from_node != null and to_node != null:
			var road_class: String = segment.road_class if ROAD_CLASS_DATA.has(segment.road_class) else "local"
			document._paint_road_segment(from_node.position, to_node.position, int(ROAD_CLASS_DATA[road_class].width), road_class, segment.id)
	for source_block in GameData.get_blocks():
		var block := source_block.duplicate() as BlockData
		document.blocks.append(block)
	for source_storefront in GameData.get_storefronts():
		document.storefronts.append(source_storefront.duplicate() as StorefrontData)
	for source_home in GameData.get_player_homes():
		document.player_homes.append(source_home.duplicate(true))
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


func create_player_home(home_id: String, home_name: String, cells: Array[Vector2i]) -> Dictionary:
	if home_id.is_empty() or home_name.strip_edges().is_empty() or cells.is_empty() or _get_player_home(home_id) != null or not _cells_are_connected(cells):
		return {}
	var block := _find_block_containing_cells(cells, "")
	if block == null or not _home_cells_valid(cells, home_id):
		return {}
	var home := {"id": home_id, "name": home_name.strip_edges(), "block_id": block.id, "grid_cells": cells.duplicate(), "entrance_cell": Vector2i(-1, -1), "map_position": _grid_cells_center(cells)}
	if not _refresh_home_entrance(home):
		return {}
	player_homes.append(home)
	return home


func remove_player_home(home_id: String) -> bool:
	for index in range(player_homes.size() - 1, -1, -1):
		if str(player_homes[index].get("id", "")) == home_id:
			player_homes.remove_at(index)
			return true
	return false


func add_cells_to_player_home(home_id: String, cells: Array[Vector2i]) -> bool:
	var home := _get_player_home(home_id)
	if home.is_empty() or cells.is_empty(): return false
	var existing_cells: Array[Vector2i] = home.get("grid_cells", [])
	var combined: Array[Vector2i] = existing_cells.duplicate()
	for cell in cells:
		if not combined.has(cell): combined.append(cell)
	if combined.size() == existing_cells.size() or not _cells_are_connected(combined) or not _home_cells_valid(combined, home_id): return false
	var block := _find_block_containing_cells(combined, "")
	if block == null: return false
	home["grid_cells"] = combined; home["block_id"] = block.id; home["map_position"] = _grid_cells_center(combined)
	return _refresh_home_entrance(home)


func set_internal_road_cells(block_id: String, cells: Array[Vector2i]) -> bool:
	var block := _get_block(block_id)
	if block == null or cells.is_empty() or not _cells_are_connected(cells): return false
	for cell in cells:
		if not block.grid_cells.has(cell) or _cell_belongs_to_storefront(cell, "") or _cell_belongs_to_home(cell, ""):
			return false
	var previous := block.internal_road_cells
	block.internal_road_cells = cells.duplicate()
	for home in player_homes:
		if str(home.get("block_id", "")) == block_id and not _refresh_home_entrance(home):
			block.internal_road_cells = previous
			return false
	if not MapDataValidator.validate(road_graph, blocks, storefronts).is_empty():
		block.internal_road_cells = previous
		for home in player_homes:
			if str(home.get("block_id", "")) == block_id: _refresh_home_entrance(home)
		return false
	return true


func toggle_internal_road_cells(block_id: String, cells: Array[Vector2i]) -> bool:
	var block := _get_block(block_id)
	if block == null or cells.is_empty(): return false
	var updated: Array[Vector2i] = block.internal_road_cells.duplicate()
	for cell in cells:
		if updated.has(cell): updated.erase(cell)
		else: updated.append(cell)
	return set_internal_road_cells(block_id, updated)


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
	var segment := _get_road_segment(segment_id)
	if segment != null:
		segment.road_class = road_class
	_paint_road_segment(grid_to_world_intersection(from_cell), grid_to_world_intersection(to_cell), int(data.width), road_class, segment_id)
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
	var from := grid_to_world_intersection(from_cell)
	var to := grid_to_world_intersection(to_cell)
	var direction := to - from
	var squared_length := direction.length_squared()
	var checked_cell_count := 0
	for cell in path:
		var center := (Vector2(cell) + Vector2(0.5, 0.5)) * GRID_CELL_SIZE
		var progress := (center - from).dot(direction)
		if progress <= 0.0 or progress >= squared_length:
			continue
		checked_cell_count += 1
		if not road_cells.has(cell):
			return false
	return checked_cell_count > 0


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
	var segment := _get_road_segment(segment_id)
	if segment != null:
		segment.road_class = road_class
	_rebuild_road_cells()
	return true


func grid_to_world_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * GRID_CELL_SIZE


func grid_to_world_intersection(point: Vector2i) -> Vector2:
	return Vector2(point) * GRID_CELL_SIZE


static func get_default_storefront_awareness_radius(cell_count: int) -> float:
	var occupied_cell_count := maxi(1, cell_count)
	var radius_in_cells := STOREFRONT_AWARENESS_BASE_CELLS + float(occupied_cell_count - 1) * STOREFRONT_AWARENESS_PER_EXTRA_CELL
	return radius_in_cells * GRID_CELL_SIZE


static func get_required_storefront_cell_count(footprint_area: float) -> int:
	return maxi(1, roundi(footprint_area / STOREFRONT_AREA_PER_GRID_CELL))


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


func remove_cells_from_block(block_id: String, cells: Array[Vector2i]) -> bool:
	var block := _get_block(block_id)
	if block == null or cells.is_empty():
		return false
	var remaining: Array[Vector2i] = []
	for cell in block.grid_cells:
		if not cells.has(cell):
			remaining.append(cell)
	if remaining.is_empty() or remaining.size() == block.grid_cells.size() or not _cells_are_connected(remaining) or not _cells_touch_road(remaining):
		return false
	for storefront in storefronts:
		if storefront.block_id == block_id:
			for storefront_cell in storefront.grid_cells:
				if not remaining.has(storefront_cell):
					return false
	block.grid_cells = remaining
	block.area = float(remaining.size()) * GRID_CELL_SIZE * GRID_CELL_SIZE
	block.rebuild_bounds_from_grid_cells()
	return true


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
	storefront.footprint_area = float(cells.size()) * STOREFRONT_AREA_PER_GRID_CELL
	storefront.area = storefront.footprint_area * STOREFRONT_MAX_USABLE_AREA_RATIO
	storefront.grid_cells = cells.duplicate()
	storefront.map_position = _grid_cells_center(cells)
	storefront.awareness_radius = get_default_storefront_awareness_radius(cells.size())
	storefront.competition_radius = storefront.awareness_radius
	_set_storefront_block(storefront, block)
	storefronts.append(storefront)
	assign_storefront_nearest_road(storefront.id)
	return storefront


func add_cells_to_storefront(storefront_id: String, cells: Array[Vector2i]) -> bool:
	var storefront := _get_storefront(storefront_id)
	if storefront == null or cells.is_empty():
		return false
	_ensure_storefront_grid_cells()
	var previous_cell_count := storefront.grid_cells.size()
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
	storefront.footprint_area = float(combined.size()) * STOREFRONT_AREA_PER_GRID_CELL
	storefront.area = minf(storefront.area, storefront.footprint_area * STOREFRONT_MAX_USABLE_AREA_RATIO)
	if storefront.awareness_radius_manual_override:
		storefront.awareness_radius += float(combined.size() - previous_cell_count) * STOREFRONT_AWARENESS_PER_EXTRA_CELL * GRID_CELL_SIZE
	else:
		storefront.awareness_radius = get_default_storefront_awareness_radius(combined.size())
	_set_storefront_block(storefront, block)
	assign_storefront_nearest_road(storefront.id)
	return true


func update_storefront_properties(storefront_id: String, storefront_name: String, monthly_rent_wan: float, area: float, hourly_capacity: int, notes: String, awareness_radius: float = -1.0, awareness_exposure_modifier: float = -1.0, footprint_area: float = -1.0, competition_radius: float = -1.0) -> bool:
	var storefront := _get_storefront(storefront_id)
	var resolved_footprint: float = storefront.footprint_area if storefront != null and footprint_area < 0.0 else footprint_area
	if storefront == null or storefront_name.strip_edges().is_empty() or monthly_rent_wan < 0.0 or area <= 0.0 or hourly_capacity <= 0 or awareness_radius < -1.0 or awareness_exposure_modifier < -1.0 or competition_radius < -1.0 or resolved_footprint < STOREFRONT_AREA_PER_GRID_CELL or not is_equal_approx(resolved_footprint / STOREFRONT_AREA_PER_GRID_CELL, roundf(resolved_footprint / STOREFRONT_AREA_PER_GRID_CELL)) or area > resolved_footprint * STOREFRONT_MAX_USABLE_AREA_RATIO:
		return false
	storefront.name = storefront_name.strip_edges()
	storefront.monthly_rent_wan = monthly_rent_wan
	storefront.area = area
	storefront.footprint_area = resolved_footprint
	storefront.notes = notes.strip_edges()
	_normalize_storefront_grid_cells_for_area()
	if awareness_radius >= 0.0:
		storefront.awareness_radius = awareness_radius
		storefront.awareness_radius_manual_override = not is_equal_approx(awareness_radius, get_default_storefront_awareness_radius(storefront.grid_cells.size()))
	if awareness_exposure_modifier >= 0.0:
		storefront.awareness_exposure_modifier = awareness_exposure_modifier
	if competition_radius >= 0.0:
		storefront.competition_radius = competition_radius
	return true


func merge_blocks(primary_id: String, secondary_id: String) -> bool:
	var primary := _get_block(primary_id)
	var secondary := _get_block(secondary_id)
	if primary == null or secondary == null or primary == secondary or primary.city_region_id != secondary.city_region_id or not _cells_touch_block(primary.grid_cells, secondary.grid_cells):
		return false
	for cell in secondary.grid_cells:
		if not primary.grid_cells.has(cell):
			primary.grid_cells.append(cell)
	primary.name = primary.name + " + " + secondary.name
	primary.tier = maxi(primary.tier, secondary.tier)
	primary.block_type = primary.block_type if primary.block_type == secondary.block_type else "mixed"
	primary.area = float(primary.grid_cells.size()) * GRID_CELL_SIZE * GRID_CELL_SIZE
	primary.rebuild_bounds_from_grid_cells()
	for storefront in storefronts:
		if storefront.block_id == secondary.id:
			_set_storefront_block(storefront, primary)
	blocks.erase(secondary)
	return true


func merge_storefronts(primary_id: String, secondary_id: String) -> bool:
	var primary := _get_storefront(primary_id)
	var secondary := _get_storefront(secondary_id)
	if primary == null or secondary == null or primary == secondary or primary.block_id != secondary.block_id or not _cells_touch_block(primary.grid_cells, secondary.grid_cells):
		return false
	for cell in secondary.grid_cells:
		if not primary.grid_cells.has(cell):
			primary.grid_cells.append(cell)
	primary.name = primary.name + " + " + secondary.name
	primary.monthly_rent_wan += secondary.monthly_rent_wan
	primary.footprint_area = float(primary.grid_cells.size()) * STOREFRONT_AREA_PER_GRID_CELL
	primary.area = minf(primary.area + secondary.area, primary.footprint_area * STOREFRONT_MAX_USABLE_AREA_RATIO)
	primary.capture_modifier = (primary.capture_modifier + secondary.capture_modifier) * 0.5
	primary.accessibility_modifier = (primary.accessibility_modifier + secondary.accessibility_modifier) * 0.5
	for category_id in secondary.supported_categories:
		if not primary.supported_categories.has(category_id):
			primary.supported_categories.append(category_id)
	primary.map_position = _grid_cells_center(primary.grid_cells)
	primary.awareness_radius = get_default_storefront_awareness_radius(primary.grid_cells.size())
	primary.awareness_radius_manual_override = false
	storefronts.erase(secondary)
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


func update_block_simulation_properties(block_id: String, accessibility: float, development_factor: float, price_sensitivity: float, quality_preference: float, time_profile: Dictionary, competition_level: String, rent_pressure: String, tags: Array[String]) -> bool:
	var block := _get_block(block_id)
	if block == null or accessibility < 0.0 or accessibility > 1.0 or development_factor < 0.0 or price_sensitivity < 0.0 or price_sensitivity > 1.0 or quality_preference < 0.0 or quality_preference > 1.0:
		return false
	block.accessibility = accessibility
	block.development_factor = development_factor
	block.spending_profile["price_sensitivity"] = price_sensitivity
	block.spending_profile["quality_preference"] = quality_preference
	block.active_time_profile = time_profile.duplicate()
	block.competition_profile["competition_level"] = competition_level
	block.competition_profile["rent_pressure"] = rent_pressure
	block.tags = tags.duplicate()
	return true


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
	if not MapDataValidator.validate(road_graph, blocks, storefronts).is_empty():
		storefront.map_position = original_position
		storefront.grid_cells = original_cells
		storefront.road_segment_id = original_segment
		storefront.block_id = original_block_id
		storefront.block_local_position = original_local_position
		return false
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
				"grid_cells": storefront.grid_cells.duplicate(),
			})
	var home_state: Array[Dictionary] = []
	for home in player_homes:
		if str(home.get("block_id", "")) == block_id:
			home_state.append({
				"home": home,
				"grid_cells": (home.get("grid_cells", []) as Array).duplicate(),
				"entrance_cell": home.get("entrance_cell", Vector2i(-1, -1)),
				"map_position": home.get("map_position", Vector2.ZERO),
			})
	_block_move_snapshots[block_id] = {
		"cells": block.grid_cells.duplicate(),
		"internal_road_cells": block.internal_road_cells.duplicate(),
		"bounds": block.map_bounds,
		"center": block.center_position,
		"storefronts": storefront_state,
		"homes": home_state,
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
		var restored_internal_roads: Array[Vector2i] = []
		for raw_cell in snapshot.get("internal_road_cells", []):
			if raw_cell is Vector2i:
				restored_internal_roads.append(raw_cell)
		block.internal_road_cells = restored_internal_roads
		block.map_bounds = snapshot.get("bounds", Rect2())
		block.center_position = snapshot.get("center", Vector2.ZERO)
		for state in snapshot.get("storefronts", []):
			var storefront: StorefrontData = state.get("storefront", null)
			if storefront != null:
				storefront.map_position = state.get("map_position", Vector2.ZERO)
				storefront.block_local_position = state.get("local_position", Vector2.ZERO)
				storefront.grid_cells.assign(state.get("grid_cells", []))
		for state in snapshot.get("homes", []):
			var home: Dictionary = state.get("home", {})
			if not home.is_empty():
				home["grid_cells"] = (state.get("grid_cells", []) as Array).duplicate()
				home["entrance_cell"] = state.get("entrance_cell", Vector2i(-1, -1))
				home["map_position"] = state.get("map_position", Vector2.ZERO)
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
			_translate_block_contents(block, cell_offset)
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
			_translate_block_contents(block, offset)
			block.rebuild_bounds_from_grid_cells()
			return


func _translate_block_contents(block: BlockData, cell_offset: Vector2i) -> void:
	if block == null or cell_offset == Vector2i.ZERO:
		return
	for index in range(block.internal_road_cells.size()):
		block.internal_road_cells[index] += cell_offset
	for home in player_homes:
		if str(home.get("block_id", "")) != block.id:
			continue
		var cells: Array[Vector2i] = []
		for raw_cell in home.get("grid_cells", []):
			if raw_cell is Vector2i:
				cells.append(raw_cell + cell_offset)
		home["grid_cells"] = cells
		var entrance: Vector2i = home.get("entrance_cell", Vector2i(-1, -1))
		if entrance != Vector2i(-1, -1):
			home["entrance_cell"] = entrance + cell_offset
		if not cells.is_empty():
			home["map_position"] = _grid_cells_center(cells)


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
		if not city_region_id.is_empty() and block.city_region_id != city_region_id:
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
		if road_cells.has(cell) or _cell_belongs_to_other_storefront(cell, ignored_storefront_id) or _cell_belongs_to_home(cell, ""):
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


func _get_player_home(home_id: String) -> Dictionary:
	for home in player_homes:
		if str(home.get("id", "")) == home_id:
			return home
	return {}


func _cell_belongs_to_storefront(cell: Vector2i, ignored_id: String) -> bool:
	for storefront in storefronts:
		if storefront.id != ignored_id and storefront.grid_cells.has(cell): return true
	return false


func _cell_belongs_to_home(cell: Vector2i, ignored_id: String) -> bool:
	for home in player_homes:
		if str(home.get("id", "")) != ignored_id and (home.get("grid_cells", []) as Array).has(cell): return true
	return false


func _home_cells_valid(cells: Array[Vector2i], ignored_id: String) -> bool:
	for cell in cells:
		if road_cells.has(cell) or _cell_belongs_to_storefront(cell, "") or _cell_belongs_to_home(cell, ignored_id): return false
	return true


func _refresh_home_entrance(home: Dictionary) -> bool:
	var block := _get_block(str(home.get("block_id", "")))
	if block == null: return false
	var candidates: Array[Vector2i] = []
	for road_cell in block.internal_road_cells:
		for home_cell in home.get("grid_cells", []):
			if absi(road_cell.x - home_cell.x) + absi(road_cell.y - home_cell.y) == 1:
				candidates.append(road_cell)
				break
	if candidates.is_empty(): return false
	candidates.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	home["entrance_cell"] = candidates[0]
	return true


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
		elif storefront.grid_cells.size() != get_required_storefront_cell_count(storefront.footprint_area):
			errors.append("storefront %s occupied-cell count does not match its area" % storefront.id)
		elif not _cells_are_connected(storefront.grid_cells):
			errors.append("storefront %s has disconnected grid cells" % storefront.id)
		elif not _storefront_cells_valid(storefront.grid_cells, storefront.id):
			errors.append("storefront %s overlaps a road or another storefront" % storefront.id)
		elif _find_block_containing_cells(storefront.grid_cells, storefront.city_region_id) == null:
			errors.append("storefront %s is not fully inside one block" % storefront.id)
	for home in player_homes:
		var cells: Array[Vector2i] = home.get("grid_cells", [])
		if cells.is_empty() or not _cells_are_connected(cells) or not _home_cells_valid(cells, str(home.get("id", ""))) or _find_block_containing_cells(cells, "") == null or not _refresh_home_entrance(home):
			errors.append("home %s has invalid occupied cells or entrance" % str(home.get("id", "")))
	return errors


func export_roads_data() -> Dictionary:
	var errors := validate()
	if not errors.is_empty():
		return {"success": false, "errors": errors, "roads": []}
	return {"success": true, "errors": [], "roads": _serialize_roads()}


func export_map_data() -> Dictionary:
	var errors := validate()
	if not errors.is_empty():
		return {"success": false, "errors": errors, "roads": [], "blocks": [], "storefronts": [], "player_homes": []}
	var serialized_blocks: Array[Dictionary] = []
	for block in blocks:
		serialized_blocks.append({
			"id": block.id, "name": block.name, "city_region_id": block.city_region_id,
			"road_entry_node_id": block.road_entry_node_id,
			"map_bounds": {"x": block.map_bounds.position.x, "y": block.map_bounds.position.y, "w": block.map_bounds.size.x, "h": block.map_bounds.size.y},
			"center_position": {"x": block.center_position.x, "y": block.center_position.y},
			"grid_cell_size": block.grid_cell_size,
			"grid_cells": _serialize_grid_cells(block.grid_cells),
			"internal_road_cells": _serialize_grid_cells(block.internal_road_cells),
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
			"frontage_side": storefront.frontage_side,
			"default_entrance_offset": storefront.default_entrance_offset,
			"map_position": {"x": storefront.map_position.x, "y": storefront.map_position.y},
			"block_id": storefront.block_id,
			"block_local_position": {"x": storefront.block_local_position.x, "y": storefront.block_local_position.y},
			"grid_cells": _serialize_grid_cells(storefront.grid_cells),
			"capture_modifier": storefront.capture_modifier,
			"accessibility_modifier": storefront.accessibility_modifier,
			"awareness_radius": storefront.awareness_radius,
			"awareness_radius_manual_override": storefront.awareness_radius_manual_override,
			"competition_radius": storefront.competition_radius,
			"awareness_exposure_modifier": storefront.awareness_exposure_modifier,
			"monthly_rent_wan": storefront.monthly_rent_wan, "area": storefront.area, "footprint_area": storefront.footprint_area,
			"decoration_level": storefront.decoration_level, "storefront_flow": storefront.storefront_flow,
			"flow_share": storefront.flow_share,
			"supported_categories": storefront.supported_categories.duplicate(),
			"equipment_condition": storefront.equipment_condition,
			"is_occupied": storefront.is_occupied,
			"occupant_name": storefront.occupant_name,
		})
	var serialized_homes: Array[Dictionary] = []
	for home in player_homes:
		var entrance: Vector2i = home.get("entrance_cell", Vector2i(-1, -1))
		serialized_homes.append({"id": str(home.get("id", "")), "name": str(home.get("name", "")), "block_id": str(home.get("block_id", "")), "grid_cells": _serialize_grid_cells(home.get("grid_cells", [])), "entrance_cell": {"x": entrance.x, "y": entrance.y}})
	return {
		"success": true, "errors": [], "roads": _serialize_roads(),
		"blocks": serialized_blocks, "storefronts": serialized_storefronts, "player_homes": serialized_homes,
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
			"player_homes.json": JSON.stringify(exported.get("player_homes", []), "\t"),
		},
	}


static func from_exported_map_data(data: Dictionary) -> Dictionary:
	var document := MapAuthoringDocument.new()
	for entry in data.get("roads", []):
		if not entry is Dictionary:
			continue
		if str(entry.get("kind", "")) == "node":
			document.add_road_node(str(entry.get("id", "")), Vector2(float(entry.get("position", {}).get("x", 0.0)), float(entry.get("position", {}).get("y", 0.0))))
	for entry in data.get("roads", []):
		if not entry is Dictionary or str(entry.get("kind", "")) != "segment":
			continue
		document.add_road_segment(str(entry.get("id", "")), str(entry.get("from_node_id", "")), str(entry.get("to_node_id", "")), float(entry.get("accessibility", 1.0)), float(entry.get("exposure", 1.0)))
		var segment := document._get_road_segment(str(entry.get("id", "")))
		if segment != null:
			segment.road_class = str(entry.get("road_class", "local"))
	document._rebuild_road_cells()
	for entry in data.get("blocks", []):
		if not entry is Dictionary:
			continue
		var cells := document._deserialize_grid_cells(entry.get("grid_cells", []))
		var block := BlockData.new()
		block.id = str(entry.get("id", "")); block.name = str(entry.get("name", "")); block.city_region_id = str(entry.get("city_region_id", "")); block.road_entry_node_id = str(entry.get("road_entry_node_id", "")); block.block_type = str(entry.get("block_type", "residential")); block.tier = int(entry.get("tier", 1)); block.grid_cell_size = float(entry.get("grid_cell_size", GRID_CELL_SIZE)); block.grid_cells = cells; block.internal_road_cells = document._deserialize_grid_cells(entry.get("internal_road_cells", [])); block.area = float(entry.get("area", cells.size() * GRID_CELL_SIZE * GRID_CELL_SIZE)); block.rebuild_bounds_from_grid_cells(); document.blocks.append(block)
	for entry in data.get("storefronts", []):
		if not entry is Dictionary:
			continue
		var storefront := StorefrontData.new()
		storefront.id = str(entry.get("id", "")); storefront.name = str(entry.get("name", "")); storefront.city_region_id = str(entry.get("city_region_id", "")); storefront.region_id = str(entry.get("region_id", "")); storefront.road_segment_id = str(entry.get("road_segment_id", "")); storefront.frontage_side = str(entry.get("frontage_side", "south")); storefront.default_entrance_offset = int(entry.get("default_entrance_offset", -1)); storefront.block_id = str(entry.get("block_id", "")); storefront.monthly_rent_wan = float(entry.get("monthly_rent_wan", 1.0)); storefront.is_occupied = bool(entry.get("is_occupied", false)); storefront.occupant_name = str(entry.get("occupant_name", "")); storefront.grid_cells = document._deserialize_grid_cells(entry.get("grid_cells", [])); storefront.footprint_area = float(entry.get("footprint_area", float(maxi(1, storefront.grid_cells.size())) * STOREFRONT_AREA_PER_GRID_CELL)); storefront.area = minf(float(entry.get("area", storefront.footprint_area * STOREFRONT_MAX_USABLE_AREA_RATIO)), storefront.footprint_area * STOREFRONT_MAX_USABLE_AREA_RATIO); storefront.awareness_radius_manual_override = bool(entry.get("awareness_radius_manual_override", false)); storefront.awareness_radius = maxf(0.0, float(entry.get("awareness_radius", get_default_storefront_awareness_radius(storefront.grid_cells.size())))) if storefront.awareness_radius_manual_override else get_default_storefront_awareness_radius(storefront.grid_cells.size()); storefront.competition_radius = maxf(0.0, float(entry.get("competition_radius", storefront.awareness_radius))); storefront.awareness_exposure_modifier = maxf(0.0, float(entry.get("awareness_exposure_modifier", 1.0))); storefront.map_position = document._grid_cells_center(storefront.grid_cells) if not storefront.grid_cells.is_empty() else Vector2.ZERO; document.storefronts.append(storefront)
	for entry in data.get("player_homes", []):
		if not entry is Dictionary: continue
		var cells := document._deserialize_grid_cells(entry.get("grid_cells", []))
		var raw_entrance: Dictionary = entry.get("entrance_cell", {})
		document.player_homes.append({"id": str(entry.get("id", "")), "name": str(entry.get("name", "")), "block_id": str(entry.get("block_id", "")), "grid_cells": cells, "entrance_cell": Vector2i(int(raw_entrance.get("x", -1)), int(raw_entrance.get("y", -1))), "map_position": document._grid_cells_center(cells)})
	if bool(data.get("reflow_for_road_width", false)):
		document._reflow_imported_map_for_road_width()
	document._normalize_storefront_grid_cells_for_area()
	document._ensure_storefront_block_assignments()
	var errors := document.validate()
	return {"success": errors.is_empty(), "errors": errors, "document": document}


func _reflow_imported_map_for_road_width() -> void:
	# Legacy hand-authored examples reserved one grid cell for every road. The
	# current editor correctly gives each road class its configured width, so
	# trim those old overlaps and relocate storefronts into legal block cells.
	for block in blocks:
		var legal_cells: Array[Vector2i] = []
		for cell in block.grid_cells:
			if not road_cells.has(cell):
				legal_cells.append(cell)
		if not legal_cells.is_empty():
			block.grid_cells = legal_cells
			block.area = float(legal_cells.size()) * GRID_CELL_SIZE * GRID_CELL_SIZE
			block.rebuild_bounds_from_grid_cells()
	var occupied_storefront_cells: Dictionary = {}
	for storefront in storefronts:
		var block := _get_block(storefront.block_id)
		var is_legal := block != null and not storefront.grid_cells.is_empty()
		if is_legal:
			for cell in storefront.grid_cells:
				if road_cells.has(cell) or not block.grid_cells.has(cell) or occupied_storefront_cells.has(cell):
					is_legal = false
					break
		if not is_legal and block != null:
			for cell in block.grid_cells:
				if not occupied_storefront_cells.has(cell):
					storefront.grid_cells = [cell]
					storefront.map_position = grid_to_world_center(cell)
					is_legal = true
					break
		if is_legal:
			for cell in storefront.grid_cells:
				occupied_storefront_cells[cell] = true


func _normalize_storefront_grid_cells_for_area() -> void:
	var occupied_cells: Dictionary = {}
	for storefront in storefronts:
		var block := _get_block(storefront.block_id)
		if block == null:
			continue
		var required_cell_count := get_required_storefront_cell_count(storefront.footprint_area)
		var current_cells: Array[Vector2i] = []
		for cell in storefront.grid_cells:
			if block.grid_cells.has(cell) and not road_cells.has(cell) and not occupied_cells.has(cell) and not current_cells.has(cell):
				current_cells.append(cell)
		if current_cells.size() != required_cell_count or not _cells_are_connected(current_cells):
			current_cells = _find_nearest_available_storefront_cells(block, occupied_cells, required_cell_count, storefront.map_position)
		if current_cells.size() == required_cell_count:
			storefront.grid_cells = current_cells
			storefront.map_position = _grid_cells_center(current_cells)
			if not storefront.awareness_radius_manual_override:
				storefront.awareness_radius = get_default_storefront_awareness_radius(current_cells.size())
			_set_storefront_block(storefront, block)
		for cell in storefront.grid_cells:
			occupied_cells[cell] = true


func _find_nearest_available_storefront_cells(block: BlockData, occupied_cells: Dictionary, required_cell_count: int, preferred_position: Vector2) -> Array[Vector2i]:
	var available_cells: Dictionary = {}
	var start_cell := Vector2i.ZERO
	var has_start := false
	var nearest_distance := INF
	for cell in block.grid_cells:
		if road_cells.has(cell) or occupied_cells.has(cell):
			continue
		available_cells[cell] = true
		var distance := grid_to_world_center(cell).distance_squared_to(preferred_position)
		if not has_start or distance < nearest_distance:
			start_cell = cell
			nearest_distance = distance
			has_start = true
	if not has_start:
		return []
	var result: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start_cell]
	var queued_cells: Dictionary = {start_cell: true}
	var neighbor_offsets: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	while not queue.is_empty() and result.size() < required_cell_count:
		var cell: Vector2i = queue.pop_front()
		result.append(cell)
		for offset in neighbor_offsets:
			var neighbor := cell + offset
			if available_cells.has(neighbor) and not queued_cells.has(neighbor):
				queued_cells[neighbor] = true
				queue.append(neighbor)
	return result if result.size() == required_cell_count else []


func _deserialize_grid_cells(raw_cells: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for raw_cell in raw_cells:
		if raw_cell is Dictionary:
			cells.append(Vector2i(int(raw_cell.get("x", 0)), int(raw_cell.get("y", 0))))
	return cells


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
			"accessibility": segment.accessibility, "exposure": segment.exposure, "road_class": segment.road_class,
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
	# Roads begin and end at grid intersections. Test the line segment against
	# each candidate cell rather than rounding samples along it: rounding skips
	# shallow diagonal cells and adds cells the line never enters.
	var cells: Array[Vector2i] = []
	var line_from := Vector2(from)
	var line_to := Vector2(to)
	var min_x := floori(minf(line_from.x, line_to.x))
	var max_x := ceili(maxf(line_from.x, line_to.x)) - 1
	var min_y := floori(minf(line_from.y, line_to.y))
	var max_y := ceili(maxf(line_from.y, line_to.y)) - 1
	# A horizontal or vertical road lies on a grid line. Use the cell on its
	# positive side as the canonical one, matching the rest of the editor.
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


func _segment_enters_grid_cell(line_from: Vector2, line_to: Vector2, cell: Vector2i) -> bool:
	var direction := line_to - line_from
	var entry_time := 0.0
	var exit_time := 1.0
	for axis in range(2):
		var position := line_from.x if axis == 0 else line_from.y
		var delta := direction.x if axis == 0 else direction.y
		var cell_min := float(cell.x if axis == 0 else cell.y)
		var cell_max := cell_min + 1.0
		if is_zero_approx(delta):
			# Half-open cells ensure a line on a grid boundary has exactly one
			# canonical row or column instead of painting both sides.
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
	# A line crossing a grid corner in its interior belongs to every cell that
	# meets at that corner. Endpoint-only contact is deliberately excluded so a
	# road does not spill past either of its nodes.
	return exit_time >= entry_time and exit_time > 0.0 and entry_time < 1.0


func _paint_road_width(cell: Vector2i, width: int, road_class: String, segment_id: String) -> void:
	var start_offset := -int(width / 2)
	for x in range(cell.x + start_offset, cell.x + start_offset + width):
		for y in range(cell.y + start_offset, cell.y + start_offset + width):
			road_cells[Vector2i(x, y)] = {"class": road_class, "segment_id": segment_id}


func _paint_road_segment(from: Vector2, to: Vector2, width: int, road_class: String, segment_id: String) -> void:
	MapGridGeometry.paint_road_segment(road_cells, from, to, width, road_class, segment_id)


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
	road_cells = MapGridGeometry.build_road_cells(road_graph)


func _has_road_segment(segment_id: String) -> bool:
	for segment in road_graph.segments:
		if segment.id == segment_id:
			return true
	return false


func _get_road_segment(segment_id: String) -> RoadSegment:
	for segment in road_graph.segments:
		if segment.id == segment_id:
			return segment
	return null


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
