class_name CityMapCanvas
extends Control
## 地图区块选择：鼠标点选一个或多个 Block。
## Phase 1 只负责选择状态与可视化，不改变调查时间、体力或行动结算。
## SurveyArea 相关API暂时保留，供后续迁移期间兼容旧数据。

signal selected_blocks_changed(block_ids: Array[String])
signal storefront_clicked(storefront_id: String)

const MAP_SCALE: float = 0.3
const STOREFRONT_CLICK_RADIUS_SCREEN_PX: float = 14.0

const BLOCK_TYPE_COLORS: Dictionary = {
	"school": Color(0.3, 0.5, 0.9, 0.5),
	"office": Color(0.6, 0.3, 0.8, 0.5),
	"commercial": Color(0.95, 0.6, 0.2, 0.5),
	"industrial": Color(0.5, 0.5, 0.5, 0.5),
	"residential": Color(0.3, 0.75, 0.4, 0.5),
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
var survey_areas: Array[SurveyAreaState] = []
var storefronts: Array[StorefrontData] = []
var selected_block_ids: Array[String] = []


func setup(new_city_regions: Array[CityRegionData], new_blocks: Array[BlockData], new_road_graph: RoadGraph = null) -> void:
	city_regions = new_city_regions
	blocks = new_blocks
	road_graph = new_road_graph
	_update_canvas_size()
	queue_redraw()


func refresh_survey_areas(new_survey_areas: Array[SurveyAreaState]) -> void:
	survey_areas = new_survey_areas
	queue_redraw()


func refresh_storefronts(new_storefronts: Array[StorefrontData]) -> void:
	storefronts = new_storefronts
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
	var max_x := 0.0
	var max_y := 0.0
	for region in city_regions:
		max_x = maxf(max_x, region.map_bounds.position.x + region.map_bounds.size.x)
		max_y = maxf(max_y, region.map_bounds.position.y + region.map_bounds.size.y)

	custom_minimum_size = Vector2(max_x, max_y) * MAP_SCALE


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

	var clicked_block := _find_block_at_screen(mouse_event.position)
	if clicked_block == null:
		return

	toggle_block_selection(clicked_block.id)


func _find_storefront_at_screen(screen_pos: Vector2) -> StorefrontData:
	for sf in storefronts:
		var diligence := GameManager.get_storefront_diligence(sf.id)
		if diligence == "not_viewed":
			continue
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


func _screen_to_map(screen_pos: Vector2) -> Vector2:
	return screen_pos / MAP_SCALE


func _map_to_screen(map_pos: Vector2) -> Vector2:
	return map_pos * MAP_SCALE


func _draw() -> void:
	_draw_city_regions()
	_draw_roads()
	_draw_blocks()
	_draw_survey_areas()
	_draw_storefronts()


func _draw_city_regions() -> void:
	for region in city_regions:
		var rect := Rect2(
			_map_to_screen(region.map_bounds.position),
			region.map_bounds.size * MAP_SCALE
		)
		draw_rect(rect, Color(1, 1, 1, 0.05), true)
		draw_rect(rect, Color(1, 1, 1, 0.6), false, 2.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, 16), region.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)


func _draw_roads() -> void:
	if road_graph == null:
		return
	for segment in road_graph.segments:
		var from_node: RoadNode = road_graph.nodes.get(segment.from_node_id, null)
		var to_node: RoadNode = road_graph.nodes.get(segment.to_node_id, null)
		if from_node == null or to_node == null:
			continue
		var exposure_alpha := lerpf(0.35, 0.9, clampf(segment.exposure / 1.2, 0.0, 1.0))
		var road_color := Color(ROAD_COLOR.r, ROAD_COLOR.g, ROAD_COLOR.b, exposure_alpha)
		var width := 1.5 + clampf(segment.accessibility, 0.0, 1.0) * 2.0
		draw_line(_map_to_screen(from_node.position), _map_to_screen(to_node.position), road_color, width, true)
	for node in road_graph.nodes.values():
		if node is RoadNode:
			draw_circle(_map_to_screen((node as RoadNode).position), 2.5, ROAD_NODE_COLOR)


func _draw_blocks() -> void:
	for block in blocks:
		var rect := Rect2(
			_map_to_screen(block.map_bounds.position),
			block.map_bounds.size * MAP_SCALE
		)
		var color: Color = BLOCK_TYPE_COLORS.get(block.block_type, Color(1, 1, 1, 0.3))
		draw_rect(rect, color, true)
		draw_rect(rect, Color(0, 0, 0, 0.4), false, 1.0)

		if selected_block_ids.has(block.id):
			draw_rect(rect, BLOCK_SELECTED_COLOR, false, 4.0)
			draw_rect(rect.grow(-3.0), Color(1.0, 0.9, 0.2, 0.12), true)

		draw_string(
			ThemeDB.fallback_font, rect.position + Vector2(4, 14),
			"%s(%d级)" % [block.name, block.tier],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10
		)


func _draw_survey_areas() -> void:
	## 旧调查区仍可视化，直到后续Phase完成迁移；Phase 1不再通过拖拽创建。
	for area in survey_areas:
		var screen_center := _map_to_screen(area.center_position)
		var screen_radius := area.radius * MAP_SCALE
		draw_arc(screen_center, screen_radius, 0.0, TAU, 48, Color(0.2, 0.8, 1.0, 0.35), 1.0)


func _draw_storefronts() -> void:
	## not_viewed的门面完全不画——对应"未被发现前不可见/不可选"的设计。
	for sf in storefronts:
		var diligence := GameManager.get_storefront_diligence(sf.id)
		if diligence == "not_viewed":
			continue

		var color: Color = STOREFRONT_STATE_COLORS.get(diligence, Color.WHITE)
		var screen_pos := _map_to_screen(sf.map_position)
		draw_circle(screen_pos, 6.0, color)
		draw_circle(screen_pos, 6.0, Color(0, 0, 0, 0.6), false, 1.5)
		draw_string(
			ThemeDB.fallback_font, screen_pos + Vector2(8, 4),
			sf.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color
		)
