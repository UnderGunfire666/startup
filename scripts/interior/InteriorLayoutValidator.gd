class_name InteriorLayoutValidator
extends RefCounted


static func is_valid_placement(
		candidate: StoreFurniturePlacement,
		proposed_cell: Vector2i,
		grid_size: Vector2i,
		placements: Array[StoreFurniturePlacement],
		footprints: Dictionary,
		available_cells: Dictionary = {},
		reserved_cells: Array[Vector2i] = []
	) -> bool:
	var candidate_cells := _footprint_cells(candidate, proposed_cell, footprints)
	for cell in candidate_cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y or (not available_cells.is_empty() and not available_cells.has(cell)) or cell in reserved_cells:
			return false
	for other in placements:
		if other == candidate:
			continue
		var other_cells := _footprint_cells(other, other.cell, footprints)
		for cell in candidate_cells:
			if cell in other_cells:
				return false
	return true


static func _footprint_cells(
		placement: StoreFurniturePlacement,
		cell: Vector2i,
		footprints: Dictionary
	) -> Array[Vector2i]:
	var size: Vector2i = footprints.get(placement.equipment_id, Vector2i.ONE)
	var rotated_size := size if placement.rotation % 2 == 0 else Vector2i(size.y, size.x)
	var cells: Array[Vector2i] = []
	for y in range(rotated_size.y):
		for x in range(rotated_size.x):
			cells.append(cell + Vector2i(x, y))
	return cells
