class_name StoreEquipment
extends RefCounted

var instance_id: String = ""
var equipment_id: String = ""
var durability: float = 100.0

func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"equipment_id": equipment_id,
		"durability": durability,
	}

static func from_dict(data: Dictionary) -> StoreEquipment:
	var item := StoreEquipment.new()
	item.instance_id = str(data.get("instance_id", ""))
	item.equipment_id = str(data.get("equipment_id", ""))
	item.durability = float(data.get("durability", 100.0))
	return item
