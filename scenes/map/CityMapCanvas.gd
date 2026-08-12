class_name CityMapCanvas
extends Control
## v4变更：新增门面渲染与点击检测。未被发现(not_viewed)的门面完全不显示，
## 也不可点；initial_viewing/full_diligence两种状态用不同颜色标记，
## 点击可选中并交给CityMapPanel处理后续的行动触发。

signal survey_drag_finished(city_region_id: String, center: Vector2, radius: float)
signal survey_drag_rejected(reason: String)
signal survey_area_clicked(survey_area_id: String)
signal storefront_clicked(storefront_id: String)

const MAP_SCALE: float = 0.3
const MIN_DRAG_RADIUS: float = 5.0
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

var city_regions: Array[CityRegionData] = []
var blocks: Array[BlockData] = []
var survey_areas: Array[SurveyAreaState] = []
var storefronts: Array[StorefrontData] = []

var _is_dragging: bool = false
var _drag_start_map_pos: Vector2 = Vector2.ZERO
var _drag_current_map_pos: Vector2 = Vector2.ZERO


func setup(new_city_regions: Array[CityRegionData], new_blocks: Array[BlockData]) -> void:
	city_regions = new_city_regions
	blocks = new_blocks
	_update_canvas_size()
	queue_redraw()


func refresh_survey_areas(new_survey_areas: Array[SurveyAreaState]) -> void:
	survey_areas = new_survey_areas
	queue_redraw()


func refresh_storefronts(new_storefronts: Array[StorefrontData]) -> void:
	storefronts = new_storefronts
	queue_redraw()


func _update_canvas_size() -> void:
	var max_x := 0.0
	var max_y := 0.0
	for region in city_regions:
		max_x = maxf(max_x, region.map_bounds.position.x + region.map_bounds.size.x)
		max_y = maxf(max_y, region.map_bounds.position.y + region.map_bounds.size.y)

	custom_minimum_size = Vector2(max_x, max_y) * MAP_SCALE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				## 优先检查是否点在一个可见门面上——门面点击优先级高于
				## 调查区框选/点击，因为门面标记通常很小，容易被拖拽误判。
				var clicked_storefront := _find_storefront_at_screen(mouse_event.position)
				if clicked_storefront != null:
					storefront_clicked.emit(clicked_storefront.id)
					return

				_is_dragging = true
				_drag_start_map_pos = _screen_to_map(mouse_event.position)
				_drag_current_map_pos = _drag_start_map_pos
				queue_redraw()
			else:
				if _is_dragging:
					_finish_drag()
				_is_dragging = false
				queue_redraw()

	elif event is InputEventMouseMotion and _is_dragging:
		var motion_event: InputEventMouseMotion = event
		_drag_current_map_pos = _screen_to_map(motion_event.position)
		queue_redraw()


func _find_storefront_at_screen(screen_pos: Vector2) -> StorefrontData:
	for sf in storefronts:
		var diligence := GameManager.get_storefront_diligence(sf.id)
		if diligence == "not_viewed":
			continue
		var sf_screen := _map_to_screen(sf.map_position)
		if sf_screen.distance_to(screen_pos) <= STOREFRONT_CLICK_RADIUS_SCREEN_PX:
			return sf
	return null


func _compute_drag_circle() -> Dictionary:
	var center := (_drag_start_map_pos + _drag_current_map_pos) / 2.0
	var radius := _drag_start_map_pos.distance_to(_drag_current_map_pos) / 2.0
	return {"center": center, "radius": radius}


func _finish_drag() -> void:
	var drag_info := _compute_drag_circle()
	var radius: float = drag_info.radius
	var center: Vector2 = drag_info.center

	if radius < MIN_DRAG_RADIUS:
		var clicked_area := _find_survey_area_at(_drag_start_map_pos)
		if clicked_area != null:
			survey_area_clicked.emit(clicked_area.id)
		else:
			survey_drag_rejected.emit("拖拽距离太小，未生成调查区")
		return

	var city_region := _find_city_region_at(center)
	if city_region == null:
		survey_drag_rejected.emit("圆心不在任何已知城市区域范围内，请在色块内拖拽")
		return

	survey_drag_finished.emit(city_region.id, center, radius)


func _find_city_region_at(map_pos: Vector2) -> CityRegionData:
	for region in city_regions:
		if region.map_bounds.has_point(map_pos):
			return region
	return null


func _find_survey_area_at(map_pos: Vector2) -> SurveyAreaState:
	for area in survey_areas:
		if area.center_position.distance_to(map_pos) <= area.radius:
			return area
	return null


func _screen_to_map(screen_pos: Vector2) -> Vector2:
	return screen_pos / MAP_SCALE


func _map_to_screen(map_pos: Vector2) -> Vector2:
	return map_pos * MAP_SCALE


func _draw() -> void:
	_draw_city_regions()
	_draw_blocks()
	_draw_survey_areas()
	_draw_storefronts()
	if _is_dragging:
		_draw_drag_preview()


func _draw_city_regions() -> void:
	for region in city_regions:
		var rect := Rect2(
			_map_to_screen(region.map_bounds.position),
			region.map_bounds.size * MAP_SCALE
		)
		draw_rect(rect, Color(1, 1, 1, 0.05), true)
		draw_rect(rect, Color(1, 1, 1, 0.6), false, 2.0)
		draw_string(
			ThemeDB.fallback_font, rect.position + Vector2(6, 16),
			"%s（%s）" % [region.name, region.region_type],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13
		)


func _draw_blocks() -> void:
	for block in blocks:
		var rect := Rect2(
			_map_to_screen(block.map_bounds.position),
			block.map_bounds.size * MAP_SCALE
		)
		var color: Color = BLOCK_TYPE_COLORS.get(block.block_type, Color(1, 1, 1, 0.3))
		draw_rect(rect, color, true)
		draw_rect(rect, Color(0, 0, 0, 0.4), false, 1.0)
		draw_string(
			ThemeDB.fallback_font, rect.position + Vector2(4, 14),
			"%s(%d级)" % [block.name, block.tier],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10
		)


func _draw_survey_areas() -> void:
	for area in survey_areas:
		var screen_center := _map_to_screen(area.center_position)
		var screen_radius := area.radius * MAP_SCALE
		draw_arc(screen_center, screen_radius, 0.0, TAU, 48, Color(0.2, 0.8, 1.0, 0.9), 2.0)
		draw_string(
			ThemeDB.fallback_font, screen_center + Vector2(-20, -screen_radius - 6),
			area.name, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.2, 0.8, 1.0)
		)


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


func _draw_drag_preview() -> void:
	var drag_info := _compute_drag_circle()
	var screen_center := _map_to_screen(drag_info.center)
	var screen_radius: float = drag_info.radius * MAP_SCALE

	draw_arc(screen_center, screen_radius, 0.0, TAU, 48, Color(1.0, 0.9, 0.2, 0.9), 2.0)

	var start_screen := _map_to_screen(_drag_start_map_pos)
	var end_screen := _map_to_screen(_drag_current_map_pos)
	draw_line(start_screen, end_screen, Color(1.0, 0.9, 0.2, 0.6), 1.5)
	draw_circle(start_screen, 4.0, Color(1.0, 0.9, 0.2, 1.0))
	draw_circle(end_screen, 4.0, Color(1.0, 0.9, 0.2, 1.0))
