class_name CityMapCanvas
extends Control
## 地图区块选择：鼠标点选一个或多个 Block。
## Phase 1 只负责选择状态与可视化，不改变调查时间、体力或行动结算。
## SurveyArea 相关API暂时保留，供后续迁移期间兼容旧数据。

signal selected_blocks_changed(block_ids: Array[String])
signal storefront_clicked(storefront_id: String)
signal navigable_cell_clicked(block_id: String, cell: Vector2i)

const MIN_MAP_SCALE := 0.3
const MAX_MAP_SCALE := 5.0
const TARGET_CONTENT_SIZE := Vector2(1100.0, 820.0)
const MIN_CONTENT_MARGIN := 16.0
const STOREFRONT_CLICK_RADIUS_SCREEN_PX: float = 14.0
const STOREFRONT_LABEL_FONT_SIZE := 11
const STOREFRONT_LABEL_PADDING := Vector2(4.0, 2.0)

const BLOCK_TYPE_COLORS: Dictionary = {
	"school": Color(0.3, 0.5, 0.9, 0.5),
	"office": Color(0.6, 0.3, 0.8, 0.5),
	"commercial": Color(0.95, 0.6, 0.2, 0.5),
	"industrial": Color(0.5, 0.5, 0.5, 0.5),
	"residential": Color(0.3, 0.75, 0.4, 0.5),
	"mixed": Color(0.65, 0.4, 0.82, 0.5),
	"tourism": Color(0.95, 0.62, 0.2, 0.5),
	"public_green": Color(0.32, 0.72, 0.38, 0.5),
}

const STOREFRONT_STATE_COLORS: Dictionary = {
	"initial_viewing": Color(1.0, 0.85, 0.2, 1.0),
	"full_diligence": Color(0.2, 0.9, 0.4, 1.0),
}

const BLOCK_SELECTED_COLOR := Color(1.0, 0.9, 0.2, 0.95)
const ROAD_COLOR := Color(0.86, 0.86, 0.9, 0.75)
const ROAD_NODE_COLOR := Color(0.98, 0.8, 0.3, 0.9)

var city_regions: Array[CityRegionData] = []
var blocks: Array[BlockData] = []
var road_graph: RoadGraph = null
var road_cells: Dictionary = {}
var player_homes: Array = []
var survey_areas: Array[SurveyAreaState] = []
var storefronts: Array[StorefrontData] = []
var selected_storefront_id := ""
var selected_block_ids: Array[String] = []
var awareness_overlay_storefront: StorefrontData = null
var awareness_overlay_coverage: Dictionary = {}
var awareness_overlay_values: Dictionary = {}
var map_scale := MIN_MAP_SCALE
var content_bounds := Rect2(Vector2.ZERO, Vector2.ONE)
var _cached_label_layout: Array[Dictionary] = []
var _label_layout_valid := false
var _storefront_entrance_cache: Dictionary = {}
var debug_static_draw_count := 0

var travel_layer: CityMapTravelLayer = null


func _ready() -> void:
	travel_layer = get_node_or_null("TravelLayer") as CityMapTravelLayer
	resized.connect(_on_canvas_resized)
	if travel_layer != null:
		travel_layer.setup(self, road_graph)


func setup(new_city_regions: Array[CityRegionData], new_blocks: Array[BlockData], new_road_graph: RoadGraph = null, new_player_homes: Array = []) -> void:
	city_regions = new_city_regions
	blocks = new_blocks
	road_graph = new_road_graph
	road_cells = MapGridGeometry.build_road_cells(road_graph)
	player_homes = new_player_homes
	_update_canvas_size()
	_invalidate_static_layout_cache()
	if travel_layer != null:
		travel_layer.setup(self, road_graph)
	queue_redraw()


func refresh_survey_areas(new_survey_areas: Array[SurveyAreaState]) -> void:
	survey_areas = new_survey_areas
	queue_redraw()


func refresh_storefronts(new_storefronts: Array[StorefrontData]) -> void:
	storefronts = new_storefronts
	_update_canvas_size()
	_invalidate_static_layout_cache()
	queue_redraw()


func refresh_storefront_layout() -> void:
	_storefront_entrance_cache.clear()
	queue_redraw()


func refresh_player_layer() -> void:
	if travel_layer != null:
		travel_layer.refresh_from_state()
		travel_layer.queue_redraw()


func set_selected_storefront(storefront_id: String) -> void:
	if selected_storefront_id == storefront_id:
		return
	selected_storefront_id = storefront_id
	queue_redraw()


## The overlay is intentionally display-only: its coverage uses the same circular
## calculation as settlement, while awareness values remain owned by Store.
func set_awareness_overlay(storefront: StorefrontData, awareness_by_block: Dictionary) -> void:
	awareness_overlay_storefront = storefront
	awareness_overlay_values = awareness_by_block.duplicate(true)
	awareness_overlay_coverage = StorefrontInfluenceCalculator.get_covered_block_ratios(storefront, blocks) if storefront != null else {}
	queue_redraw()


func clear_awareness_overlay() -> void:
	awareness_overlay_storefront = null
	awareness_overlay_coverage.clear()
	awareness_overlay_values.clear()
	queue_redraw()


func clear_block_selection() -> void:
	if selected_block_ids.is_empty():
		return
	selected_block_ids.clear()
	selected_blocks_changed.emit(selected_block_ids.duplicate())
	queue_redraw()


func set_block_selected(block_id: String, selected: bool) -> bool:
	var block := _find_block_by_id(block_id)
	if block == null:
		return false

	var was_selected := selected_block_ids.has(block_id)
	if selected and not was_selected:
		selected_block_ids.append(block_id)
	elif not selected and was_selected:
		selected_block_ids.erase(block_id)
	else:
		return true

	selected_blocks_changed.emit(selected_block_ids.duplicate())
	queue_redraw()
	return true


func toggle_block_selection(block_id: String) -> bool:
	return set_block_selected(block_id, not selected_block_ids.has(block_id))


func get_selected_blocks() -> Array[BlockData]:
	var result: Array[BlockData] = []
	for block_id in selected_block_ids:
		var block := _find_block_by_id(block_id)
		if block != null:
			result.append(block)
	return result


func _find_block_by_id(block_id: String) -> BlockData:
	for block in blocks:
		if block.id == block_id:
			return block
	return null


func _update_canvas_size() -> void:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for block in blocks:
		if block.grid_cells.is_empty():
			min_x = minf(min_x, block.map_bounds.position.x)
			min_y = minf(min_y, block.map_bounds.position.y)
			max_x = maxf(max_x, block.map_bounds.end.x)
			max_y = maxf(max_y, block.map_bounds.end.y)
		else:
			for cell in block.grid_cells:
				var cell_position := Vector2(cell) * MapGridGeometry.CELL_SIZE
				min_x = minf(min_x, cell_position.x)
				min_y = minf(min_y, cell_position.y)
				max_x = maxf(max_x, cell_position.x + MapGridGeometry.CELL_SIZE)
				max_y = maxf(max_y, cell_position.y + MapGridGeometry.CELL_SIZE)
	for cell in road_cells:
		var road_position := Vector2(cell) * MapGridGeometry.CELL_SIZE
		min_x = minf(min_x, road_position.x)
		min_y = minf(min_y, road_position.y)
		max_x = maxf(max_x, road_position.x + MapGridGeometry.CELL_SIZE)
		max_y = maxf(max_y, road_position.y + MapGridGeometry.CELL_SIZE)
	if road_graph != null:
		for raw_node in road_graph.nodes.values():
			if raw_node is RoadNode:
				var node := raw_node as RoadNode
				min_x = minf(min_x, node.position.x)
				min_y = minf(min_y, node.position.y)
				max_x = maxf(max_x, node.position.x)
				max_y = maxf(max_y, node.position.y)
	for storefront in storefronts:
		if storefront.grid_cells.is_empty():
			min_x = minf(min_x, storefront.map_position.x)
			min_y = minf(min_y, storefront.map_position.y)
			max_x = maxf(max_x, storefront.map_position.x)
			max_y = maxf(max_y, storefront.map_position.y)
		else:
			for cell in storefront.grid_cells:
				var cell_position := Vector2(cell) * MapGridGeometry.CELL_SIZE
				min_x = minf(min_x, cell_position.x)
				min_y = minf(min_y, cell_position.y)
				max_x = maxf(max_x, cell_position.x + MapGridGeometry.CELL_SIZE)
				max_y = maxf(max_y, cell_position.y + MapGridGeometry.CELL_SIZE)
	if is_inf(min_x) or is_inf(min_y):
		min_x = 0.0
		min_y = 0.0
		max_x = 1.0
		max_y = 1.0
	content_bounds = Rect2(
		Vector2(min_x, min_y),
		Vector2(maxf(1.0, max_x - min_x), maxf(1.0, max_y - min_y))
	)
	var target_scale := minf(TARGET_CONTENT_SIZE.x / content_bounds.size.x, TARGET_CONTENT_SIZE.y / content_bounds.size.y)
	map_scale = clampf(target_scale, MIN_MAP_SCALE, MAX_MAP_SCALE)
	custom_minimum_size = content_bounds.size * map_scale + Vector2.ONE * (MIN_CONTENT_MARGIN * 2.0)


func _get_draw_offset() -> Vector2:
	var rendered_size := content_bounds.size * map_scale
	var available_size := size
	if available_size.x < rendered_size.x + MIN_CONTENT_MARGIN * 2.0:
		available_size.x = custom_minimum_size.x
	if available_size.y < rendered_size.y + MIN_CONTENT_MARGIN * 2.0:
		available_size.y = custom_minimum_size.y
	return Vector2(
		maxf(MIN_CONTENT_MARGIN, (available_size.x - rendered_size.x) * 0.5),
		maxf(MIN_CONTENT_MARGIN, (available_size.y - rendered_size.y) * 0.5)
	)


func _on_canvas_resized() -> void:
	_label_layout_valid = false
	queue_redraw()
	if travel_layer != null:
		travel_layer.queue_redraw()


func _invalidate_static_layout_cache() -> void:
	_label_layout_valid = false
	_cached_label_layout.clear()
	_storefront_entrance_cache.clear()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return

	var mouse_event: InputEventMouseButton = event
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	## 门面点击优先，避免点击已发现门面时同时改变区块选择。
	var clicked_storefront := _find_storefront_at_screen(mouse_event.position)
	if clicked_storefront != null:
		storefront_clicked.emit(clicked_storefront.id)
		return
	var clicked_cell := _find_internal_road_cell_at_screen(mouse_event.position)
	if not clicked_cell.is_empty():
		navigable_cell_clicked.emit(str(clicked_cell.get("block_id", "")), clicked_cell.get("cell", Vector2i(-1, -1)))
		return

	var clicked_block := _find_block_at_screen(mouse_event.position)
	if clicked_block == null:
		return

	toggle_block_selection(clicked_block.id)


func _find_storefront_at_screen(screen_pos: Vector2) -> StorefrontData:
	var map_pos := _screen_to_map(screen_pos)
	for sf in storefronts:
		for cell in sf.grid_cells:
			if Rect2(Vector2(cell) * MapGridGeometry.CELL_SIZE, Vector2.ONE * MapGridGeometry.CELL_SIZE).has_point(map_pos):
				return sf
		var sf_screen := _map_to_screen(sf.map_position)
		if sf_screen.distance_to(screen_pos) <= STOREFRONT_CLICK_RADIUS_SCREEN_PX:
			return sf
	return null


func _find_block_at_screen(screen_pos: Vector2) -> BlockData:
	var map_pos := _screen_to_map(screen_pos)
	## 从后往前检查，若未来存在边界重叠时优先使用最后配置的区块。
	for index in range(blocks.size() - 1, -1, -1):
		var block := blocks[index]
		if block.has_map_point(map_pos):
			return block
	return null


func _find_internal_road_cell_at_screen(screen_pos: Vector2) -> Dictionary:
	var cell := Vector2i(floori(_screen_to_map(screen_pos).x / MapGridGeometry.CELL_SIZE), floori(_screen_to_map(screen_pos).y / MapGridGeometry.CELL_SIZE))
	for block in blocks:
		if block.internal_road_cells.has(cell): return {"block_id": block.id, "cell": cell}
	return {}


func _screen_to_map(screen_pos: Vector2) -> Vector2:
	return (screen_pos - _get_draw_offset()) / map_scale + content_bounds.position


func _map_to_screen(map_pos: Vector2) -> Vector2:
	return _get_draw_offset() + (map_pos - content_bounds.position) * map_scale


func _draw() -> void:
	debug_static_draw_count += 1
	_draw_city_regions()
	_draw_roads()
	_draw_blocks()
	_draw_awareness_overlay()
	_draw_survey_areas()
	_draw_storefronts()
	_draw_player_homes()


func reset_debug_draw_count() -> void:
	debug_static_draw_count = 0


func _draw_player_homes() -> void:
	for home in player_homes:
		var home_position := _map_to_screen(home.get("map_position", Vector2.ZERO))
		draw_rect(Rect2(home_position - Vector2(4, 4), Vector2(8, 8)), Color(0.35, 0.75, 1.0, 0.95), true)
		draw_rect(Rect2(home_position - Vector2(4, 4), Vector2(8, 8)), Color(0.05, 0.12, 0.2, 0.9), false, 1.0)


func _draw_city_regions() -> void:
	for region in city_regions:
		var visible_bounds := region.map_bounds.intersection(content_bounds)
		if not visible_bounds.has_area():
			continue
		var rect := Rect2(
			_map_to_screen(visible_bounds.position),
			visible_bounds.size * map_scale
		)
		draw_rect(rect, Color(1, 1, 1, 0.05), true)
		draw_rect(rect, Color(1, 1, 1, 0.6), false, 2.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, 16), region.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)


func _draw_roads() -> void:
	for cell in road_cells:
		var road_data: Dictionary = road_cells[cell]
		draw_rect(_map_cell_rect(cell), MapGridGeometry.get_road_color(str(road_data.get("class", "local"))), true)
	if road_graph == null:
		return
	for node in road_graph.nodes.values():
		if node is RoadNode:
			draw_circle(_map_to_screen((node as RoadNode).position), 2.5, ROAD_NODE_COLOR)


func _draw_blocks() -> void:
	for block in blocks:
		var color: Color = BLOCK_TYPE_COLORS.get(block.block_type, Color(1, 1, 1, 0.3))
		if block.grid_cells.is_empty():
			_draw_block_rect(block, color)
		else:
			for cell in block.grid_cells:
				var cell_rect := _map_cell_rect(cell)
				draw_rect(cell_rect, color, true)
				draw_rect(cell_rect, Color(0, 0, 0, 0.4), false, 1.0)
				if selected_block_ids.has(block.id):
					draw_rect(cell_rect.grow(1.0), BLOCK_SELECTED_COLOR, false, 2.0)
					draw_rect(cell_rect.grow(-1.0), Color(1.0, 0.9, 0.2, 0.12), true)

		draw_string(
			ThemeDB.fallback_font, _map_to_screen(block.center_position) + Vector2(4, 14),
			"%s(%d级)" % [block.name, block.tier],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10
		)
		for cell in block.internal_road_cells:
			var internal_rect := _map_cell_rect(cell)
			draw_rect(internal_rect, Color(0.73, 0.70, 0.56, 0.96), true)
			draw_rect(internal_rect, Color(0.15, 0.14, 0.10, 0.8), false, 1.0)


func _draw_awareness_overlay() -> void:
	if awareness_overlay_storefront == null or awareness_overlay_coverage.is_empty():
		return
	var center := _map_to_screen(awareness_overlay_storefront.map_position)
	var radius := awareness_overlay_storefront.awareness_radius * map_scale
	if radius > 0.0:
		draw_circle(center, radius, Color(1.0, 0.78, 0.18, 0.055), true)
		draw_arc(center, radius, 0.0, TAU, 96, Color(1.0, 0.8, 0.22, 0.9), 2.0, true)
	for block in blocks:
		var coverage := float(awareness_overlay_coverage.get(block.id, 0.0))
		if coverage <= 0.0:
			continue
		var awareness := clampf(float(awareness_overlay_values.get(block.id, 0.0)) / 100.0, 0.0, 1.0)
		for cell in block.grid_cells:
			var cell_rect := _map_cell_rect(cell)
			draw_rect(cell_rect, Color(1.0, 0.5 + awareness * 0.35, 0.1, 0.08 + awareness * 0.20), true)
			draw_rect(cell_rect, Color(1.0, 0.84, 0.28, 0.5 + coverage * 0.45), false, 1.5 + coverage * 2.0)
		var info := "覆盖 %.0f%%  |  知名 %.1f" % [coverage * 100.0, awareness * 100.0]
		draw_string(ThemeDB.fallback_font, _map_to_screen(block.center_position) + Vector2(4.0, 12.0), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.93, 0.65, 0.98))


func _draw_survey_areas() -> void:
	## 旧调查区仍可视化，直到后续Phase完成迁移；Phase 1不再通过拖拽创建。
	for area in survey_areas:
		var screen_center := _map_to_screen(area.center_position)
		var screen_radius := area.radius * map_scale
		draw_arc(screen_center, screen_radius, 0.0, TAU, 48, Color(0.2, 0.8, 1.0, 0.35), 1.0)


func _draw_storefronts() -> void:
	## not_viewed的门面完全不画——对应"未被发现前不可见/不可选"的设计。
	var labels := get_storefront_label_layout()
	for sf in storefronts:
		var color := _get_storefront_color(sf)
		for cell in sf.grid_cells:
			var cell_rect := _map_cell_rect(cell)
			draw_rect(cell_rect, Color(color.r, color.g, color.b, 0.55), true)
			draw_rect(cell_rect, color, false, 1.5)
		_draw_storefront_frontage_edges(sf, color)
		_draw_storefront_entrance_marker(sf)
		if sf.id == selected_storefront_id:
			_draw_storefront_selection_outline(sf)
	for item in labels:
		var rect: Rect2 = item.get("rect", Rect2())
		var label_color: Color = item.get("color", Color.WHITE)
		var label_text := str(item.get("label", ""))
		draw_rect(rect, Color(0.04, 0.08, 0.11, 0.94), true)
		draw_rect(rect, Color(label_color.r, label_color.g, label_color.b, 0.8), false, 1.0)
		draw_string(
			ThemeDB.fallback_font,
			rect.position + STOREFRONT_LABEL_PADDING + Vector2(0.0, STOREFRONT_LABEL_FONT_SIZE),
			label_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			STOREFRONT_LABEL_FONT_SIZE,
			label_color
		)


func _draw_storefront_selection_outline(storefront: StorefrontData) -> void:
	var cells: Dictionary = {}
	for cell in storefront.grid_cells:
		cells[cell] = true
	for cell in storefront.grid_cells:
		var rect := _map_cell_rect(cell)
		if not cells.has(cell + Vector2i.UP):
			draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color(1.0, 0.86, 0.15, 1.0), 3.5, true)
		if not cells.has(cell + Vector2i.DOWN):
			draw_line(Vector2(rect.position.x, rect.end.y), rect.end, Color(1.0, 0.86, 0.15, 1.0), 3.5, true)
		if not cells.has(cell + Vector2i.LEFT):
			draw_line(rect.position, Vector2(rect.position.x, rect.end.y), Color(1.0, 0.86, 0.15, 1.0), 3.5, true)
		if not cells.has(cell + Vector2i.RIGHT):
			draw_line(Vector2(rect.end.x, rect.position.y), rect.end, Color(1.0, 0.86, 0.15, 1.0), 3.5, true)


func _draw_storefront_frontage_edges(storefront: StorefrontData, color: Color) -> void:
	var direction := _frontage_direction(storefront.frontage_side)
	var cells: Dictionary = {}
	for cell in storefront.grid_cells:
		cells[cell] = true
	for cell in storefront.grid_cells:
		if cells.has(cell + direction):
			continue
		var rect := _map_cell_rect(cell)
		var from := rect.position
		var to := rect.end
		match storefront.frontage_side:
			"north": to = Vector2(rect.end.x, rect.position.y)
			"south": from = Vector2(rect.position.x, rect.end.y)
			"west": to = Vector2(rect.position.x, rect.end.y)
			"east": from = Vector2(rect.end.x, rect.position.y)
		draw_line(from, to, Color(color.r, color.g, color.b, 1.0), 2.0, true)


func _draw_storefront_entrance_marker(storefront: StorefrontData) -> void:
	var entrance: Dictionary = {}
	if _storefront_entrance_cache.has(storefront.id):
		entrance = _storefront_entrance_cache[storefront.id]
	else:
		entrance = MapNavigationGrid.get_storefront_entrance(storefront)
		_storefront_entrance_cache[storefront.id] = entrance
	if entrance.is_empty():
		return
	var cell: Vector2i = entrance.get("cell", Vector2i(-1, -1))
	if cell == Vector2i(-1, -1):
		return
	var offset := int(entrance.get("facade_start", entrance.get("facade_offset", 0)))
	var width := maxi(1, int(entrance.get("entrance_width", StorefrontLayoutGeometry.ENTRANCE_WIDTH_CELLS)))
	var min_cell := storefront.grid_cells[0]
	var max_cell := storefront.grid_cells[0]
	for occupied in storefront.grid_cells:
		min_cell = Vector2i(mini(min_cell.x, occupied.x), mini(min_cell.y, occupied.y))
		max_cell = Vector2i(maxi(max_cell.x, occupied.x), maxi(max_cell.y, occupied.y))
	var first_city_index := floori(float(offset) / StorefrontLayoutGeometry.CELLS_PER_CITY_CELL)
	var last_city_index := floori(float(offset + width - 1) / StorefrontLayoutGeometry.CELLS_PER_CITY_CELL)
	for city_index in range(first_city_index, last_city_index + 1):
		var marker_cell := _frontage_city_cell(str(entrance.get("side", storefront.frontage_side)), city_index, min_cell, max_cell)
		if not storefront.grid_cells.has(marker_cell):
			continue
		var local_start := maxi(0, offset - city_index * StorefrontLayoutGeometry.CELLS_PER_CITY_CELL)
		var local_end := mini(StorefrontLayoutGeometry.CELLS_PER_CITY_CELL, offset + width - city_index * StorefrontLayoutGeometry.CELLS_PER_CITY_CELL)
		_draw_entrance_edge_segment(_map_cell_rect(marker_cell), str(entrance.get("side", storefront.frontage_side)), float(local_start) / StorefrontLayoutGeometry.CELLS_PER_CITY_CELL, float(local_end) / StorefrontLayoutGeometry.CELLS_PER_CITY_CELL)


func _frontage_city_cell(side: String, along: int, min_cell: Vector2i, max_cell: Vector2i) -> Vector2i:
	match side:
		"north": return Vector2i(clampi(min_cell.x + along, min_cell.x, max_cell.x), min_cell.y)
		"east": return Vector2i(max_cell.x, clampi(min_cell.y + along, min_cell.y, max_cell.y))
		"west": return Vector2i(min_cell.x, clampi(min_cell.y + along, min_cell.y, max_cell.y))
		_: return Vector2i(clampi(min_cell.x + along, min_cell.x, max_cell.x), max_cell.y)


func _draw_entrance_edge_segment(rect: Rect2, side: String, start_ratio: float, end_ratio: float) -> void:
	var from := rect.position
	var to := rect.end
	match side:
		"north":
			from = Vector2(lerpf(rect.position.x, rect.end.x, start_ratio), rect.position.y)
			to = Vector2(lerpf(rect.position.x, rect.end.x, end_ratio), rect.position.y)
		"south":
			from = Vector2(lerpf(rect.position.x, rect.end.x, start_ratio), rect.end.y)
			to = Vector2(lerpf(rect.position.x, rect.end.x, end_ratio), rect.end.y)
		"west":
			from = Vector2(rect.position.x, lerpf(rect.position.y, rect.end.y, start_ratio))
			to = Vector2(rect.position.x, lerpf(rect.position.y, rect.end.y, end_ratio))
		"east":
			from = Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, start_ratio))
			to = Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, end_ratio))
	draw_line(from, to, Color(0.12, 0.88, 1.0, 1.0), 5.0, true)


func _frontage_direction(frontage_side: String) -> Vector2i:
	match frontage_side:
		"north": return Vector2i.UP
		"west": return Vector2i.LEFT
		"east": return Vector2i.RIGHT
		_: return Vector2i.DOWN


func get_storefront_label_text(storefront_name: String) -> String:
	return storefront_name if storefront_name.length() <= 4 else storefront_name.left(4) + "…"


func get_storefront_label_layout() -> Array[Dictionary]:
	if _label_layout_valid:
		return _cached_label_layout
	var layout: Array[Dictionary] = []
	var occupied_rects: Array[Rect2] = []
	for storefront in storefronts:
		var label := get_storefront_label_text(storefront.name)
		var text_size := ThemeDB.fallback_font.get_string_size(
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			STOREFRONT_LABEL_FONT_SIZE
		)
		var label_size := text_size + STOREFRONT_LABEL_PADDING * 2.0
		var anchor := _map_to_screen(storefront.map_position)
		var candidate_offsets := [
			Vector2(8.0, -label_size.y - 8.0),
			Vector2(8.0, 8.0),
			Vector2(-label_size.x - 8.0, -label_size.y - 8.0),
			Vector2(-label_size.x - 8.0, 8.0),
			Vector2(8.0, -label_size.y - 26.0),
			Vector2(-label_size.x - 8.0, 26.0),
		]
		for offset in candidate_offsets:
			var rect := Rect2(anchor + offset, label_size)
			if _label_rect_overlaps(rect, occupied_rects):
				continue
			occupied_rects.append(rect)
			layout.append({
				"storefront_id": storefront.id,
				"label": label,
				"rect": rect,
				"color": Color.WHITE,
			})
			break
	_cached_label_layout = layout
	_label_layout_valid = true
	return _cached_label_layout


func _map_cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_map_to_screen(Vector2(cell) * MapGridGeometry.CELL_SIZE), Vector2.ONE * MapGridGeometry.CELL_SIZE * map_scale)


func _draw_block_rect(block: BlockData, color: Color) -> void:
	var rect := Rect2(_map_to_screen(block.map_bounds.position), block.map_bounds.size * map_scale)
	draw_rect(rect, color, true)
	draw_rect(rect, Color(0, 0, 0, 0.4), false, 1.0)
	if selected_block_ids.has(block.id):
		draw_rect(rect, BLOCK_SELECTED_COLOR, false, 4.0)


func _get_storefront_color(storefront: StorefrontData) -> Color:
	var state := str(GameManager.player_state.storefront_diligence.get(storefront.id, ""))
	return STOREFRONT_STATE_COLORS.get(state, Color(0.65, 1.0, 0.78, 0.9))


func _label_rect_overlaps(candidate: Rect2, occupied_rects: Array[Rect2]) -> bool:
	for occupied in occupied_rects:
		if candidate.grow(2.0).intersects(occupied.grow(2.0)):
			return true
	return false
