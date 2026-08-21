class_name StoreFurniturePlacement
extends RefCounted

var instance_id: String = ""
var equipment_id: String = ""
var cell: Vector2i = Vector2i.ZERO
var rotation: int = 0

func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"equipment_id": equipment_id,
		"cell": [cell.x, cell.y],
		"rotation": rotation,
	}

static func from_dict(data: Dictionary) -> StoreFurniturePlacement:
	var placement := StoreFurniturePlacement.new()
	placement.instance_id = str(data.get("instance_id", ""))
	placement.equipment_id = str(data.get("equipment_id", ""))
	var raw_cell: Array = data.get("cell", [0, 0])
	if raw_cell.size() >= 2:
		placement.cell = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	placement.rotation = posmod(int(data.get("rotation", 0)), 4)
	return placement

func get_footprint_cells(size: Vector2i) -> Array[Vector2i]:
	var rotated_size := size if rotation % 2 == 0 else Vector2i(size.y, size.x)
	var cells: Array[Vector2i] = []
	for y in range(rotated_size.y):
		for x in range(rotated_size.x):
			cells.append(cell + Vector2i(x, y))
	return cells
