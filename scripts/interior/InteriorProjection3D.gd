class_name InteriorProjection3D
extends RefCounted

const CELL_WORLD_SIZE := 0.5
const EQUIPMENT_HEIGHT := 0.62


static func get_rotated_footprint(footprint: Vector2i, rotation: int) -> Vector2i:
	return footprint if posmod(rotation, 2) == 0 else Vector2i(footprint.y, footprint.x)


static func get_world_size(footprint: Vector2i, rotation: int) -> Vector3:
	var rotated := get_rotated_footprint(footprint, rotation)
	return Vector3(float(rotated.x) * CELL_WORLD_SIZE, EQUIPMENT_HEIGHT, float(rotated.y) * CELL_WORLD_SIZE)


static func get_world_position(cell: Vector2i, footprint: Vector2i, rotation: int, grid_size: Vector2i) -> Vector3:
	var rotated := get_rotated_footprint(footprint, rotation)
	var x := (float(cell.x) + float(rotated.x) * 0.5 - float(grid_size.x) * 0.5) * CELL_WORLD_SIZE
	var z := (float(cell.y) + float(rotated.y) * 0.5 - float(grid_size.y) * 0.5) * CELL_WORLD_SIZE
	return Vector3(x, EQUIPMENT_HEIGHT * 0.5, z)


static func world_point_to_cell(world_point: Vector3, grid_size: Vector2i) -> Vector2i:
	return Vector2i(
		floori(world_point.x / CELL_WORLD_SIZE + float(grid_size.x) * 0.5),
		floori(world_point.z / CELL_WORLD_SIZE + float(grid_size.y) * 0.5)
	)


static func get_entrance_center_x(facade_layout: Array[StoreFacadePlacement], interior_grid_width: int) -> float:
	for placement in facade_layout:
		if placement.type == "entrance":
			var facade_size := FacadeLayoutValidator.get_footprint_size(placement.type)
			var normalized_center := (float(placement.cell.x) + float(facade_size.x) * 0.5) / float(FacadeLayoutValidator.GRID_SIZE.x)
			return clampf(normalized_center * float(interior_grid_width), 0.0, float(interior_grid_width))
	return float(interior_grid_width) * 0.5
