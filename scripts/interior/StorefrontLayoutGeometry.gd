class_name StorefrontLayoutGeometry
extends RefCounted

## One 3.5m city-map cell is exactly 7×7 layout cells at 0.25㎡ per cell.
const CELLS_PER_CITY_CELL := 7
const CELL_AREA_SQM := 0.25
const CELL_WORLD_SIZE := 0.5
const FACADE_HEIGHT_CELLS := 7
const ENTRANCE_WIDTH_CELLS := 2

var grid_size := Vector2i.ONE
var available_cells: Dictionary = {}
var frontage_side := "south"
var frontage_start := 0
var frontage_length := CELLS_PER_CITY_CELL


static func from_storefront(storefront: StorefrontData) -> StorefrontLayoutGeometry:
	var geometry := StorefrontLayoutGeometry.new()
	geometry.frontage_side = storefront.frontage_side
	if geometry.frontage_side.is_empty():
		geometry.frontage_side = "south"
	if storefront.grid_cells.is_empty():
		geometry.available_cells[Vector2i.ZERO] = true
		return geometry
	var min_cell := storefront.grid_cells[0]
	var max_cell := storefront.grid_cells[0]
	for city_cell in storefront.grid_cells:
		min_cell = Vector2i(mini(min_cell.x, city_cell.x), mini(min_cell.y, city_cell.y))
		max_cell = Vector2i(maxi(max_cell.x, city_cell.x), maxi(max_cell.y, city_cell.y))
	geometry.grid_size = (max_cell - min_cell + Vector2i.ONE) * CELLS_PER_CITY_CELL
	for city_cell in storefront.grid_cells:
		var local_origin := (city_cell - min_cell) * CELLS_PER_CITY_CELL
		for y in range(CELLS_PER_CITY_CELL):
			for x in range(CELLS_PER_CITY_CELL):
				geometry.available_cells[local_origin + Vector2i(x, y)] = true
	geometry._resolve_frontage()
	return geometry


func is_available(cell: Vector2i) -> bool:
	return available_cells.has(cell)


func get_available_cell_array() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in available_cells.keys():
		result.append(cell)
	return result


func get_facade_grid_size() -> Vector2i:
	return Vector2i(frontage_length, FACADE_HEIGHT_CELLS)


func get_default_entrance_cell(offset: int) -> Vector2i:
	var x := clampi(offset if offset >= 0 else maxi(0, (frontage_length - ENTRANCE_WIDTH_CELLS) / 2), 0, maxi(0, frontage_length - ENTRANCE_WIDTH_CELLS))
	return Vector2i(x, FACADE_HEIGHT_CELLS - 3)


func get_interior_entrance_cells(facade_entrance: StoreFacadePlacement) -> Array[Vector2i]:
	if facade_entrance == null or facade_entrance.type != "entrance":
		return []
	var offset := facade_entrance.cell.x
	var cells: Array[Vector2i] = []
	for index in range(ENTRANCE_WIDTH_CELLS):
		var along := clampi(offset + index, 0, frontage_length - 1)
		cells.append(_frontage_cell_at(frontage_start + along))
	return cells


func _resolve_frontage() -> void:
	var best_start := 0
	var best_length := 0
	var edge_length := grid_size.x if frontage_side == "north" or frontage_side == "south" else grid_size.y
	var run_start := 0
	var run_length := 0
	for along in range(edge_length):
		if is_available(_frontage_cell_at(along)):
			if run_length == 0:
				run_start = along
			run_length += 1
			if run_length > best_length:
				best_start = run_start
				best_length = run_length
		else:
			run_length = 0
	frontage_start = best_start
	frontage_length = maxi(1, best_length)


func _frontage_cell_at(along: int) -> Vector2i:
	match frontage_side:
		"north":
			return Vector2i(along, 0)
		"east":
			return Vector2i(grid_size.x - 1, along)
		"west":
			return Vector2i(0, along)
	return Vector2i(along, grid_size.y - 1)
