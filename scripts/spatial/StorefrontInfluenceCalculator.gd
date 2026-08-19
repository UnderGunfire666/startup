class_name StorefrontInfluenceCalculator
extends RefCounted

## Computes the part of a Block reached by a storefront's offline awareness
## circle. A grid cell counts when the circle intersects any part of that cell.

static func get_block_coverage_ratio(storefront: StorefrontData, block: BlockData) -> float:
	if storefront == null or block == null or block.grid_cells.is_empty() or storefront.awareness_radius <= 0.0:
		return 0.0
	var covered_count := 0
	for cell in block.grid_cells:
		if _circle_intersects_grid_cell(storefront.map_position, storefront.awareness_radius, cell):
			covered_count += 1
	return float(covered_count) / float(block.grid_cells.size())


static func get_covered_block_ratios(storefront: StorefrontData, blocks: Array[BlockData]) -> Dictionary:
	var ratios: Dictionary = {}
	for block in blocks:
		var ratio := get_block_coverage_ratio(storefront, block)
		if ratio > 0.0:
			ratios[block.id] = ratio
	return ratios


static func _circle_intersects_grid_cell(center: Vector2, radius: float, cell: Vector2i) -> bool:
	var cell_min := Vector2(cell) * MapAuthoringDocument.GRID_CELL_SIZE
	var cell_max := cell_min + Vector2.ONE * MapAuthoringDocument.GRID_CELL_SIZE
	var nearest := Vector2(
		clampf(center.x, cell_min.x, cell_max.x),
		clampf(center.y, cell_min.y, cell_max.y)
	)
	return nearest.distance_squared_to(center) <= radius * radius
