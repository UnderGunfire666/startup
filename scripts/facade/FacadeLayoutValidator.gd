class_name FacadeLayoutValidator
extends RefCounted

const GRID_SIZE := Vector2i(12, 5)
const MAX_COUNTS := {
	"signboard": 1,
	"entrance": 1,
	"window": 2,
}


static func get_footprint_size(type: String) -> Vector2i:
	match type:
		"signboard":
			return Vector2i(4, 1)
		"entrance":
			return Vector2i(2, 3)
		"window":
			return Vector2i(3, 3)
	return Vector2i.ZERO


static func is_known_type(type: String) -> bool:
	return MAX_COUNTS.has(type)


static func can_add_type(type: String, placements: Array[StoreFacadePlacement], ignored: StoreFacadePlacement = null) -> bool:
	if not is_known_type(type):
		return false
	var count := 0
	for placement in placements:
		if placement != ignored and placement.type == type:
			count += 1
	return count < int(MAX_COUNTS[type])


static func is_valid_placement(candidate: StoreFacadePlacement, proposed_cell: Vector2i, placements: Array[StoreFacadePlacement], grid_size: Vector2i = GRID_SIZE) -> bool:
	if candidate == null or not is_known_type(candidate.type):
		return false
	var candidate_cells := get_footprint_cells(candidate.type, proposed_cell)
	for cell in candidate_cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
			return false
	for other in placements:
		if other == candidate:
			continue
		for cell in candidate_cells:
			if cell in get_footprint_cells(other.type, other.cell):
				return false
	return true


static func get_footprint_cells(type: String, cell: Vector2i) -> Array[Vector2i]:
	var size := get_footprint_size(type)
	var cells: Array[Vector2i] = []
	for y in range(size.y):
		for x in range(size.x):
			cells.append(cell + Vector2i(x, y))
	return cells
