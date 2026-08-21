class_name StoreFacadePlacement
extends RefCounted

## A single component placed on the store's front elevation grid.
var type: String = ""
var cell: Vector2i = Vector2i.ZERO


func to_dict() -> Dictionary:
	return {
		"type": type,
		"cell": [cell.x, cell.y],
	}


static func from_dict(data: Dictionary) -> StoreFacadePlacement:
	var placement := StoreFacadePlacement.new()
	placement.type = str(data.get("type", ""))
	var raw_cell: Array = data.get("cell", [0, 0])
	if raw_cell.size() >= 2:
		placement.cell = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	return placement
