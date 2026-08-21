class_name FacadeProjection3D
extends RefCounted

## Converts the 2D elevation grid into a front-facing 3D wall coordinate system.
const CELL_WORLD_SIZE := 0.5
const WALL_DEPTH := 0.3
const COMPONENT_DEPTH := 0.18


static func get_world_size(type: String) -> Vector3:
	var footprint := FacadeLayoutValidator.get_footprint_size(type)
	return Vector3(float(footprint.x) * CELL_WORLD_SIZE, float(footprint.y) * CELL_WORLD_SIZE, COMPONENT_DEPTH)


static func get_world_position(type: String, cell: Vector2i, grid_size: Vector2i = FacadeLayoutValidator.GRID_SIZE) -> Vector3:
	var footprint := FacadeLayoutValidator.get_footprint_size(type)
	var x := (float(cell.x) + float(footprint.x) * 0.5 - float(grid_size.x) * 0.5) * CELL_WORLD_SIZE
	var y := (float(grid_size.y) - float(cell.y) - float(footprint.y) * 0.5) * CELL_WORLD_SIZE
	return Vector3(x, y, WALL_DEPTH * 0.5 + COMPONENT_DEPTH * 0.5 + 0.02)


static func world_point_to_cell(world_point: Vector3, grid_size: Vector2i = FacadeLayoutValidator.GRID_SIZE) -> Vector2i:
	var x := floori(world_point.x / CELL_WORLD_SIZE + float(grid_size.x) * 0.5)
	var y := floori(float(grid_size.y) - world_point.y / CELL_WORLD_SIZE)
	return Vector2i(x, y)


static func get_type_color(type: String) -> Color:
	match type:
		"signboard":
			return Color("#d6a64a")
		"entrance":
			return Color("#4f9d9a")
		"window":
			return Color("#7089c9")
	return Color.WHITE
