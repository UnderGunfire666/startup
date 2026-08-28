class_name CityMapCanvas
extends Control
## 地图区块选择：鼠标点选一个或多个 Block。
## Phase 1 只负责选择状态与可视化，不改变调查时间、体力或行动结算。
## SurveyArea 相关API暂时保留，供后续迁移期间兼容旧数据。

signal selected_blocks_changed(block_ids: Array[String])
signal storefront_clicked(storefront_id: String)

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
var player_homes: Array = []
var survey_areas: Array[SurveyAreaState] = []
var storefronts: Array[StorefrontData] = []
var selected_block_ids: Array[String] = []
var awareness_overlay_storefront: StorefrontData = null
var awareness_overlay_coverage: Dictionary = {}
var awareness_overlay_values: Dictionary = {}
var map_scale := MIN_MAP_SCALE
var content_bounds := Rect2(Vector2.ZERO, Vector2.ONE)


func _ready() -> void:
	resized.connect(queue_redraw)


func setup(new_city_regions: Array[CityRegionData], new_blocks: Array[BlockData], new_road_graph: RoadGraph = null, new_player_homes: Array = []) -> void:
	city_regions = new_city_regions
	blocks = new_blocks
	road_graph = new_road_graph
	player_homes = new_player_homes
	_update_canvas_size()
	queue_redraw()


func refresh_survey_areas(new_survey_areas: Array[SurveyAreaState]) -> void:
	survey_areas = new_survey_areas
	queue_redraw()


func refresh_storefronts(new_storefronts: Array[StorefrontData]) -> void:
	storefronts = new_storefronts
	_update_canvas_size()
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
		min_x = minf(min_x, block.map_bounds.position.x)
		min_y = minf(min_y, block.map_bounds.position.y)
		max_x = maxf(max_x, block.map_bounds.end.x)
		max_y = maxf(max_y, block.map_bounds.end.y)
	if road_graph != null:
		for raw_node in road_graph.nodes.values():
			if raw_node is RoadNode:
				var node := raw_node as RoadNode
				min_x = minf(min_x, node.position.x)
				min_y = minf(min_y, node.position.y)
				max_x = maxf(max_x, node.position.x)
				max_y = maxf(max_y, node.position.y)
	for storefront in storefronts:
		min_x = minf(min_x, storefront.map_position.x)
		min_y = minf(min_y, storefront.map_position.y)
		max_x = maxf(max_x, storefront.map_position.x)
		max_y = maxf(max_y, storefront.map_position.y)
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
	return (screen_pos - _get_draw_offset()) / map_scale + content_bounds.position


func _map_to_screen(map_pos: Vector2) -> Vector2:
	return _get_draw_offset() + (map_pos - content_bounds.position) * map_scale


func _draw() -> void:
	_draw_city_regions()
	_draw_roads()
	_draw_blocks()
	_draw_awareness_overlay()
	_draw_survey_areas()
	_draw_storefronts()
	_draw_player_travel()


func _draw_player_travel() -> void:
	var player := GameManager.player_state
	if not player.is_character_created:
		return
	for home in player_homes:
		var home_position := _map_to_screen(home.get("map_position", Vector2.ZERO))
		draw_rect(Rect2(home_position - Vector2(4, 4), Vector2(8, 8)), Color(0.35, 0.75, 1.0, 0.95), true)
		draw_rect(Rect2(home_position - Vector2(4, 4), Vector2(8, 8)), Color(0.05, 0.12, 0.2, 0.9), false, 1.0)
	var position := player.current_map_position
	if ScheduleManager.current_action != null and ScheduleManager.current_action.is_active and ScheduleManager.current_action.action_id == "move_to_block":
		var quote: Dictionary = ScheduleManager.current_action.context.get("travel_quote", {})
		var points: Array[Vector2] = []
		for node_id in quote.get("route_node_ids", []):
			var node: RoadNode = road_graph.nodes.get(str(node_id), null) if road_graph != null else null
			if node != null:
				points.append(node.position)
		if points.size() >= 2:
			for index in range(1, points.size()):
				draw_line(_map_to_screen(points[index - 1]), _map_to_screen(points[index]), Color(0.2, 0.9, 1.0, 0.9), 3.0, true)
			var ratio := clampf((TimeManager.total_game_seconds - ScheduleManager.current_action.start_game_seconds) / maxf(1.0, ScheduleManager.current_action.duration_hours * 3600.0), 0.0, 1.0)
			position = _interpolate_route(points, ratio)
	draw_circle(_map_to_screen(position), 6.5, Color(1.0, 0.25, 0.35, 1.0))
	draw_circle(_map_to_screen(position), 6.5, Color(0.15, 0.02, 0.05, 0.95), false, 1.5)


func _interpolate_route(points: Array[Vector2], ratio: float) -> Vector2:
	if points.is_empty(): return Vector2.ZERO
	var total := 0.0
	for index in range(1, points.size()): total += points[index - 1].distance_to(points[index])
	var remaining := total * ratio
	for index in range(1, points.size()):
		var segment := points[index - 1].distance_to(points[index])
		if remaining <= segment:
			return points[index - 1].lerp(points[index], remaining / maxf(segment, 0.001))
		remaining -= segment
	return points.back()


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
			block.map_bounds.size * map_scale
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
		var rect := Rect2(_map_to_screen(block.map_bounds.position), block.map_bounds.size * map_scale)
		var awareness := clampf(float(awareness_overlay_values.get(block.id, 0.0)) / 100.0, 0.0, 1.0)
		draw_rect(rect, Color(1.0, 0.5 + awareness * 0.35, 0.1, 0.08 + awareness * 0.20), true)
		draw_rect(rect, Color(1.0, 0.84, 0.28, 0.5 + coverage * 0.45), false, 1.5 + coverage * 2.0)
		var info := "覆盖 %.0f%%  |  知名 %.1f" % [coverage * 100.0, awareness * 100.0]
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(4.0, rect.size.y - 5.0), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.93, 0.65, 0.98))


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
		var color := Color.WHITE
		var screen_pos := _map_to_screen(sf.map_position)
		draw_circle(screen_pos, 6.0, color)
		draw_circle(screen_pos, 6.0, Color(0, 0, 0, 0.6), false, 1.5)
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


func get_storefront_label_text(storefront_name: String) -> String:
	return storefront_name if storefront_name.length() <= 4 else storefront_name.left(4) + "…"


func get_storefront_label_layout() -> Array[Dictionary]:
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
	return layout


func _label_rect_overlaps(candidate: Rect2, occupied_rects: Array[Rect2]) -> bool:
	for occupied in occupied_rects:
		if candidate.grow(2.0).intersects(occupied.grow(2.0)):
			return true
	return false
