class_name LayoutSpriteCatalog
extends RefCounted

## Shared atlas slicing and aspect-preserving fitting for the layout editors.
const EQUIPMENT_COLUMNS := 5
const EQUIPMENT_ROWS := 6
const EQUIPMENT_IDS := ["steamer", "griddle", "fryer", "rice_cooker", "warming_station", "noodle_boiler", "hotpot_table", "cold_display", "commercial_stove", "wok", "bbq_grill", "exhaust", "spice_station", "oven", "grill", "cup_sealer", "ice_maker", "proofer", "ice_cream_machine", "coffee_machine", "coffee_grinder", "dessert_steamer", "sugar_stove", "refrigerator", "freezer", "dry_storage_shelf"]
const FACADE_TYPES := {"signboard": 0, "entrance": 1, "window": 2}
const EQUIPMENT_ATLAS_PATH := "res://assets/layout/equipment_atlas.png"
const FACADE_ATLAS_PATH := "res://assets/layout/facade_atlas.png"

static var _equipment_3d_texture_cache: Dictionary = {}
static var _facade_3d_texture_cache: Dictionary = {}


static func get_equipment_region(atlas_size: Vector2, equipment_id: String) -> Rect2:
	var index := EQUIPMENT_IDS.find(equipment_id)
	if index < 0 or atlas_size.x <= 0.0 or atlas_size.y <= 0.0:
		return Rect2()
	var cell_size := Vector2(atlas_size.x / EQUIPMENT_COLUMNS, atlas_size.y / EQUIPMENT_ROWS)
	return Rect2(Vector2(float(index % EQUIPMENT_COLUMNS), float(index / EQUIPMENT_COLUMNS)) * cell_size, cell_size)


static func get_facade_region(atlas_size: Vector2, type: String) -> Rect2:
	if not FACADE_TYPES.has(type) or atlas_size.x <= 0.0 or atlas_size.y <= 0.0:
		return Rect2()
	var width := atlas_size.x / 3.0
	return Rect2(Vector2(float(FACADE_TYPES[type]) * width, 0.0), Vector2(width, atlas_size.y))


static func fit_source_in_rect(source_size: Vector2, target_rect: Rect2, padding: float = 0.0) -> Rect2:
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return Rect2()
	var safe_rect := target_rect.grow(-minf(padding, minf(target_rect.size.x, target_rect.size.y) * 0.5))
	if safe_rect.size.x <= 0.0 or safe_rect.size.y <= 0.0:
		return Rect2()
	var scale := minf(safe_rect.size.x / source_size.x, safe_rect.size.y / source_size.y)
	var fitted_size := source_size * scale
	return Rect2(safe_rect.get_center() - fitted_size * 0.5, fitted_size)


static func get_equipment_3d_texture(atlas: Texture2D, equipment_id: String) -> ImageTexture:
	if atlas == null or not EQUIPMENT_IDS.has(equipment_id):
		return null
	if _equipment_3d_texture_cache.has(equipment_id):
		return _equipment_3d_texture_cache[equipment_id]
	var index := EQUIPMENT_IDS.find(equipment_id)
	var pixel_region := _get_grid_pixel_region(atlas.get_size(), EQUIPMENT_COLUMNS, EQUIPMENT_ROWS, index % EQUIPMENT_COLUMNS, index / EQUIPMENT_COLUMNS)
	var texture := _crop_texture(atlas, pixel_region)
	if texture != null:
		_equipment_3d_texture_cache[equipment_id] = texture
	return texture


static func get_facade_3d_texture(atlas: Texture2D, type: String) -> ImageTexture:
	if atlas == null or not FACADE_TYPES.has(type):
		return null
	if _facade_3d_texture_cache.has(type):
		return _facade_3d_texture_cache[type]
	var pixel_region := _get_grid_pixel_region(atlas.get_size(), 3, 1, int(FACADE_TYPES[type]), 0)
	var texture := _crop_texture(atlas, pixel_region)
	if texture != null:
		_facade_3d_texture_cache[type] = texture
	return texture


static func _get_grid_pixel_region(atlas_size: Vector2, columns: int, rows: int, column: int, row: int) -> Rect2i:
	var start_x := floori(float(column) * atlas_size.x / float(columns))
	var end_x := floori(float(column + 1) * atlas_size.x / float(columns))
	var start_y := floori(float(row) * atlas_size.y / float(rows))
	var end_y := floori(float(row + 1) * atlas_size.y / float(rows))
	return Rect2i(start_x, start_y, end_x - start_x, end_y - start_y)


static func _crop_texture(atlas: Texture2D, pixel_region: Rect2i) -> ImageTexture:
	if pixel_region.size.x <= 0 or pixel_region.size.y <= 0:
		return null
	var image := atlas.get_image()
	if image == null or not Rect2i(Vector2i.ZERO, image.get_size()).encloses(pixel_region):
		return null
	var cropped := image.get_region(pixel_region)
	if cropped == null or cropped.is_empty():
		return null
	return ImageTexture.create_from_image(cropped)
