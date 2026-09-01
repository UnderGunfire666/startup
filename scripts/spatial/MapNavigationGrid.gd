class_name MapNavigationGrid
extends RefCounted

## Navigation uses authored internal lanes and external road surfaces. Block
## footprints remain closed except for their explicit internal-road cells.
const CARDINALS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var walkable_cells: Dictionary = {}
var internal_cells: Dictionary = {}
var storefront_entrances: Dictionary = {} # storefront id -> {cell, side, block_id}
var home_entrances: Dictionary = {} # home id -> {cell, entrance_cell, block_id}
var cell_blocks: Dictionary = {} # cell -> block id

static func build(road_graph: RoadGraph, blocks: Array[BlockData], storefronts: Array[StorefrontData], homes: Array = []) -> MapNavigationGrid:
	var grid := MapNavigationGrid.new()
	var storefront_cells: Dictionary = {}
	for storefront in storefronts:
		for cell in storefront.grid_cells:
			storefront_cells[cell] = true
	for block in blocks:
		for cell in block.grid_cells:
			grid.cell_blocks[cell] = block.id
		for cell in block.internal_road_cells:
			if storefront_cells.has(cell):
				continue
			grid.walkable_cells[cell] = true
			grid.internal_cells[cell] = true
	# Navigation uses the authored road surface, rather than only its centre
	# line, so a block lane can meet the road width at its boundary.
	for cell in MapGridGeometry.build_road_cells(road_graph):
		if not grid.cell_blocks.has(cell):
			grid.walkable_cells[cell] = true
	for storefront in storefronts:
		var entrance := get_storefront_entrance(storefront, storefront_cells)
		if entrance.is_empty():
			continue
		grid.storefront_entrances[storefront.id] = entrance
		grid.walkable_cells[entrance.cell] = true
	for home in homes:
		var home_id := str(home.get("id", ""))
		var entrance_cell: Vector2i = home.get("entrance_cell", Vector2i(-1, -1))
		var home_cells: Array = home.get("grid_cells", [])
		var home_cell := Vector2i(-1, -1)
		for raw_cell in home_cells:
			var cell: Vector2i = raw_cell
			if CARDINALS.any(func(direction: Vector2i): return cell + direction == entrance_cell):
				home_cell = cell
				break
		if home_id.is_empty() or home_cell == Vector2i(-1, -1) or not grid.internal_cells.has(entrance_cell):
			continue
		grid.home_entrances[home_id] = {"cell": home_cell, "entrance_cell": entrance_cell, "block_id": str(home.get("block_id", ""))}
		grid.walkable_cells[home_cell] = true
	return grid


static func get_storefront_entrance(storefront: StorefrontData, occupied_storefront_cells: Dictionary = {}) -> Dictionary:
	if storefront == null or storefront.grid_cells.is_empty():
		return {}
	var geometry := StorefrontLayoutGeometry.from_storefront(storefront)
	var offset := storefront.default_entrance_offset
	# A signed storefront's configured facade entrance is authoritative.
	for store in GameManager.stores:
		if store.signed_storefront_id != storefront.id:
			continue
		for placement in store.facade_layout:
			if placement.type == "entrance":
				offset = placement.cell.x
				break
	var facade_cell := geometry.get_default_entrance_cell(offset)
	var entrance_width := StorefrontLayoutGeometry.ENTRANCE_WIDTH_CELLS
	var min_cell := storefront.grid_cells[0]
	var max_cell := storefront.grid_cells[0]
	for occupied in storefront.grid_cells:
		min_cell = Vector2i(mini(min_cell.x, occupied.x), mini(min_cell.y, occupied.y))
		max_cell = Vector2i(maxi(max_cell.x, occupied.x), maxi(max_cell.y, occupied.y))
	var facade_start := geometry.frontage_start + facade_cell.x
	var along := floori((facade_start + entrance_width * 0.5) / StorefrontLayoutGeometry.CELLS_PER_CITY_CELL)
	var cell: Vector2i
	match storefront.frontage_side:
		"north": cell = Vector2i(clampi(min_cell.x + along, min_cell.x, max_cell.x), min_cell.y)
		"east": cell = Vector2i(max_cell.x, clampi(min_cell.y + along, min_cell.y, max_cell.y))
		"west": cell = Vector2i(min_cell.x, clampi(min_cell.y + along, min_cell.y, max_cell.y))
		_: cell = Vector2i(clampi(min_cell.x + along, min_cell.x, max_cell.x), max_cell.y)
	var outward := _side_offset(storefront.frontage_side)
	if not storefront.grid_cells.has(cell) or storefront.grid_cells.has(cell + outward) or occupied_storefront_cells.has(cell + outward):
		# Irregular footprints can have a gap at the nominal facade coordinate,
		# or extend one cell beyond it. Pick the nearest facade cell that exits
		# directly into public space instead of manufacturing a blocked entrance.
		var best := Vector2i(-1, -1)
		var best_distance := 999999
		for candidate in storefront.grid_cells:
			if storefront.grid_cells.has(candidate + outward) or occupied_storefront_cells.has(candidate + outward):
				continue
			var distance := absi(candidate.x - cell.x) + absi(candidate.y - cell.y)
			if distance < best_distance or (distance == best_distance and (candidate.y < best.y or (candidate.y == best.y and candidate.x < best.x))):
				best = candidate
				best_distance = distance
		if best != Vector2i(-1, -1):
			cell = best
		elif not storefront.grid_cells.has(cell):
			cell = storefront.grid_cells[0]
	return {
		"cell": cell,
		"side": storefront.frontage_side,
		"block_id": storefront.block_id,
		"facade_offset": facade_cell.x,
		"facade_start": facade_start,
		"entrance_width": entrance_width,
	}


func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in CARDINALS:
		var other := cell + direction
		if not walkable_cells.has(other):
			continue
		if _allows_edge(cell, other, direction) and _allows_edge(other, cell, -direction):
			result.append(other)
	return result


func _allows_edge(from: Vector2i, _to: Vector2i, direction: Vector2i) -> bool:
	for entrance in home_entrances.values():
		if entrance.cell == from:
			return from + direction == entrance.entrance_cell
	for entrance in storefront_entrances.values():
		if entrance.cell != from:
			continue
		return direction == _side_offset(str(entrance.side))
	return true


func shortest_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not walkable_cells.has(from) or not walkable_cells.has(to):
		return result
	var queue: Array[Vector2i] = [from]
	var queue_index := 0
	var previous: Dictionary = {from: from}
	while queue_index < queue.size():
		var current: Vector2i = queue[queue_index]
		queue_index += 1
		if current == to:
			break
		for next in get_neighbors(current):
			if not previous.has(next):
				previous[next] = current
				queue.append(next)
	if not previous.has(to):
		return result
	var current := to
	while current != from:
		result.push_front(current)
		current = previous[current]
	result.push_front(from)
	return result


static func _side_offset(side: String) -> Vector2i:
	match side:
		"north": return Vector2i.UP
		"east": return Vector2i.RIGHT
		"west": return Vector2i.LEFT
		_: return Vector2i.DOWN
