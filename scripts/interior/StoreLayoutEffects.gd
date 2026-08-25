class_name StoreLayoutEffects
extends RefCounted

## Pure layout-to-operation rules. Layout remains the sole source of placement truth.
const SIGNBOARD_CAPTURE_MULTIPLIER := 1.10
const WINDOW_AWARENESS_MULTIPLIER := 1.08


static func get_placed_instance_ids(store: Store) -> Dictionary:
	var owned: Dictionary = {}
	if store == null:
		return owned
	for equipment in store.equipment:
		owned[equipment.instance_id] = equipment.equipment_id
	var placed: Dictionary = {}
	for placement in store.furniture_layout:
		if owned.get(placement.instance_id, "") == placement.equipment_id:
			placed[placement.instance_id] = placement.equipment_id
	return placed


static func has_placed_equipment(store: Store, equipment_id: String) -> bool:
	for placed_equipment_id in get_placed_instance_ids(store).values():
		if placed_equipment_id == equipment_id:
			return true
	return false


static func get_entrance_cells(store: Store, geometry: StorefrontLayoutGeometry) -> Array[Vector2i]:
	if store == null or geometry == null:
		return []
	for placement in store.facade_layout:
		if placement.type == "entrance":
			return geometry.get_interior_entrance_cells(placement)
	return []


static func has_entrance(store: Store, geometry: StorefrontLayoutGeometry) -> bool:
	return not get_entrance_cells(store, geometry).is_empty()


static func has_clear_entrance(store: Store, geometry: StorefrontLayoutGeometry, footprints: Dictionary) -> bool:
	var entrance_cells := get_entrance_cells(store, geometry)
	if entrance_cells.is_empty():
		return false
	for placement in store.furniture_layout:
		for occupied_cell in placement.get_footprint_cells(footprints.get(placement.equipment_id, Vector2i.ONE)):
			if occupied_cell in entrance_cells:
				return false
	return true


static func get_capture_multiplier(store: Store) -> float:
	if store == null:
		return 1.0
	for placement in store.facade_layout:
		if placement.type == "signboard":
			return SIGNBOARD_CAPTURE_MULTIPLIER
	return 1.0


static func get_awareness_multiplier(store: Store) -> float:
	if store == null:
		return 1.0
	var windows := 0
	for placement in store.facade_layout:
		if placement.type == "window":
			windows += 1
	return pow(WINDOW_AWARENESS_MULTIPLIER, mini(windows, 2))
