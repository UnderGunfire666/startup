class_name InteriorLayoutPanel
extends Control

signal closed

const FACADE_TYPES := ["signboard", "entrance", "window"]
const FACADE_TYPE_NAMES := {
	"signboard": "招牌",
	"entrance": "入口",
	"window": "橱窗",
}

@onready var title_label: Label = $Margin/VBox/Header/Title
@onready var status_label: Label = $Margin/VBox/Header/Status
@onready var layout_tabs: TabContainer = $Margin/VBox/LayoutTabs
@onready var equipment_list: VBoxContainer = $Margin/VBox/LayoutTabs/Interior/Body/Sidebar/EquipmentScroll/EquipmentList
@onready var canvas: InteriorCanvas = $Margin/VBox/LayoutTabs/Interior/Body/CanvasScroll/InteriorCanvas
@onready var rotate_button: Button = $Margin/VBox/LayoutTabs/Interior/Body/Sidebar/Actions/RotateButton
@onready var delete_button: Button = $Margin/VBox/LayoutTabs/Interior/Body/Sidebar/Actions/DeleteButton
@onready var interior_3d_canvas: Interior3DCanvas = $Margin/VBox/LayoutTabs/Interior3D/Body/Interior3DCanvas
@onready var interior_3d_equipment_list: VBoxContainer = $Margin/VBox/LayoutTabs/Interior3D/Body/Sidebar/EquipmentScroll/EquipmentList
@onready var interior_3d_rotate_button: Button = $Margin/VBox/LayoutTabs/Interior3D/Body/Sidebar/Actions/RotateButton
@onready var interior_3d_delete_button: Button = $Margin/VBox/LayoutTabs/Interior3D/Body/Sidebar/Actions/DeleteButton
@onready var facade_canvas: FacadeCanvas = $Margin/VBox/LayoutTabs/Facade/Body/CanvasScroll/FacadeCanvas
@onready var facade_component_list: VBoxContainer = $Margin/VBox/LayoutTabs/Facade/Body/Sidebar/ComponentList
@onready var facade_delete_button: Button = $Margin/VBox/LayoutTabs/Facade/Body/Sidebar/DeleteButton
@onready var facade_3d_canvas: Facade3DCanvas = $Margin/VBox/LayoutTabs/Facade3D/Body/Facade3DCanvas
@onready var facade_3d_component_list: VBoxContainer = $Margin/VBox/LayoutTabs/Facade3D/Body/Sidebar/ComponentList
@onready var facade_3d_delete_button: Button = $Margin/VBox/LayoutTabs/Facade3D/Body/Sidebar/DeleteButton

var current_storefront_id := ""
var current_store: Store = null
var is_read_only := false
var is_facade_only := false
var selected_equipment_instance_id := ""
var selected_placement_instance_id := ""
var selected_facade_type := ""
var selected_facade_placement: StoreFacadePlacement = null
var grid_size := Vector2i(5, 5)
var facade_grid_size := FacadeLayoutValidator.GRID_SIZE
var layout_geometry: StorefrontLayoutGeometry = null


func _ready() -> void:
	visible = false
	layout_tabs.set_tab_title(0, "室内")
	layout_tabs.set_tab_title(1, "室内 3D")
	layout_tabs.set_tab_title(2, "门面")
	layout_tabs.set_tab_title(3, "门面 3D")
	$Margin/VBox/Header/CloseButton.pressed.connect(_on_close_pressed)
	rotate_button.pressed.connect(_on_rotate_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	interior_3d_rotate_button.pressed.connect(_on_rotate_pressed)
	interior_3d_delete_button.pressed.connect(_on_delete_pressed)
	facade_delete_button.pressed.connect(_on_facade_delete_pressed)
	facade_3d_delete_button.pressed.connect(_on_facade_delete_pressed)
	layout_tabs.tab_changed.connect(_on_layout_tab_changed)
	canvas.cell_pressed.connect(_on_canvas_cell_pressed)
	canvas.placement_drag_started.connect(_on_placement_drag_started)
	canvas.placement_drag_previewed.connect(_on_placement_drag_previewed)
	canvas.placement_drop_requested.connect(_on_placement_drop_requested)
	interior_3d_canvas.cell_pressed.connect(_on_canvas_cell_pressed)
	interior_3d_canvas.placement_drag_started.connect(_on_placement_drag_started)
	interior_3d_canvas.placement_drag_previewed.connect(_on_placement_drag_previewed)
	interior_3d_canvas.placement_drop_requested.connect(_on_placement_drop_requested)
	facade_canvas.cell_pressed.connect(_on_facade_cell_pressed)
	facade_canvas.placement_drag_started.connect(_on_facade_drag_started)
	facade_canvas.placement_drag_previewed.connect(_on_facade_drag_previewed)
	facade_canvas.placement_drop_requested.connect(_on_facade_drop_requested)
	facade_3d_canvas.cell_pressed.connect(_on_facade_cell_pressed)
	facade_3d_canvas.placement_drag_started.connect(_on_facade_drag_started)
	facade_3d_canvas.placement_drag_previewed.connect(_on_facade_drag_previewed)
	facade_3d_canvas.placement_drop_requested.connect(_on_facade_drop_requested)


func open_for_storefront(storefront_id: String, store: Store = null, read_only: bool = false, facade_only: bool = false) -> void:
	current_store = store if store != null else (Store.new() if facade_only else GameManager.store_state)
	is_read_only = read_only
	is_facade_only = facade_only
	var storefront := GameManager.get_storefront(storefront_id)
	if current_store == null or storefront == null:
		return
	current_storefront_id = storefront_id
	layout_geometry = StorefrontLayoutGeometry.from_storefront(storefront)
	grid_size = layout_geometry.grid_size
	facade_grid_size = layout_geometry.get_facade_grid_size()
	if not is_read_only and not is_facade_only:
		_migrate_legacy_layout_grid(storefront)
		_initialize_default_facade_entrance(storefront)
	if is_facade_only:
		var entrance := StoreFacadePlacement.new()
		entrance.type = "entrance"
		entrance.cell = layout_geometry.get_default_entrance_cell(storefront.default_entrance_offset)
		current_store.facade_layout.clear()
		current_store.facade_layout.append(entrance)
	title_label.text = "%s · %s" % [storefront.name, "店铺布局预览" if is_read_only else "店铺编辑"]
	selected_equipment_instance_id = ""
	selected_placement_instance_id = ""
	selected_facade_type = ""
	selected_facade_placement = null
	for tab in range(layout_tabs.get_tab_count()):
		layout_tabs.set_tab_hidden(tab, is_facade_only and tab != 2)
	layout_tabs.current_tab = 2 if is_facade_only else 0
	_refresh_equipment_list()
	_refresh_canvas()
	_refresh_facade_components()
	_refresh_facade_canvas()
	status_label.text = "这是正在营业店铺的只读布局。" if is_read_only else "选择设备后点击网格放置"
	visible = true
	move_to_front()


func _get_grid_size(area: float) -> Vector2i:
	var cells := maxi(9, ceili(area / 12.25))
	var width := clampi(ceili(sqrt(float(cells) * 1.35)), 3, 10)
	var height := clampi(ceili(float(cells) / float(width)), 3, 10)
	return Vector2i(width, height)


func _initialize_default_facade_entrance(storefront: StorefrontData) -> void:
	if current_store.facade_layout_initialized:
		return
	var entrance := StoreFacadePlacement.new()
	entrance.type = "entrance"
	entrance.cell = layout_geometry.get_default_entrance_cell(storefront.default_entrance_offset)
	current_store.facade_layout.append(entrance)
	current_store.facade_layout_initialized = true


func _migrate_legacy_layout_grid(storefront: StorefrontData) -> void:
	if current_store.layout_grid_version >= 2:
		return
	var old_grid := _get_grid_size(storefront.area)
	for placement in current_store.furniture_layout:
		placement.cell = Vector2i(
			clampi(roundi(float(placement.cell.x) / maxf(1.0, float(old_grid.x - 1)) * float(grid_size.x - 1)), 0, grid_size.x - 1),
			clampi(roundi(float(placement.cell.y) / maxf(1.0, float(old_grid.y - 1)) * float(grid_size.y - 1)), 0, grid_size.y - 1)
		)
	for placement in current_store.facade_layout:
		placement.cell = Vector2i(
			clampi(roundi(float(placement.cell.x) / 11.0 * float(facade_grid_size.x - 1)), 0, facade_grid_size.x - 1),
			clampi(roundi(float(placement.cell.y) / 4.0 * float(facade_grid_size.y - 1)), 0, facade_grid_size.y - 1)
		)
	current_store.layout_grid_version = 2


func _refresh_equipment_list() -> void:
	for child in equipment_list.get_children():
		child.queue_free()
	for child in interior_3d_equipment_list.get_children():
		child.queue_free()
	var placed_ids: Dictionary = {}
	for placement in current_store.furniture_layout:
		placed_ids[placement.instance_id] = true
	var count := 0
	for item in current_store.equipment:
		var definition := GameManager.get_equipment(item.equipment_id)
		if definition == null:
			continue
		_add_equipment_button(equipment_list, item.instance_id, definition.name, placed_ids.has(item.instance_id))
		_add_equipment_button(interior_3d_equipment_list, item.instance_id, definition.name, placed_ids.has(item.instance_id))
		count += 1
	if count == 0:
		var empty_label := Label.new()
		empty_label.text = "暂无已购设备"
		equipment_list.add_child(empty_label)
		var interior_3d_empty_label := Label.new()
		interior_3d_empty_label.text = "暂无已购设备"
		interior_3d_equipment_list.add_child(interior_3d_empty_label)


func _add_equipment_button(list: VBoxContainer, instance_id: String, equipment_name: String, is_placed: bool) -> void:
	var button := Button.new()
	button.text = ("✓ " if is_placed else "○ ") + equipment_name
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = is_read_only
	button.tooltip_text = "选择后点击室内网格放置"
	button.pressed.connect(func(): _select_equipment(instance_id))
	list.add_child(button)


func _select_equipment(instance_id: String) -> void:
	selected_equipment_instance_id = instance_id
	selected_placement_instance_id = ""
	status_label.text = "已选择设备，点击网格放置"
	_refresh_canvas()


func _refresh_canvas() -> void:
	canvas.setup(grid_size, current_store.furniture_layout, layout_geometry, _get_interior_entrance_cells(), _get_equipment_names())
	canvas.set_selected(selected_placement_instance_id)
	rotate_button.disabled = is_read_only or selected_placement_instance_id.is_empty()
	delete_button.disabled = is_read_only or selected_placement_instance_id.is_empty()
	_refresh_interior_3d_canvas()


func _refresh_interior_3d_canvas() -> void:
	interior_3d_canvas.setup(grid_size, current_store.furniture_layout, _get_footprint_sizes(), current_store.facade_layout, layout_geometry)
	interior_3d_canvas.set_selected(selected_placement_instance_id)
	interior_3d_rotate_button.disabled = is_read_only or selected_placement_instance_id.is_empty()
	interior_3d_delete_button.disabled = is_read_only or selected_placement_instance_id.is_empty()


func _get_interior_entrance_cells() -> Array[Vector2i]:
	if layout_geometry == null:
		return []
	for placement in current_store.facade_layout:
		if placement.type == "entrance":
			return layout_geometry.get_interior_entrance_cells(placement)
	return []


func _get_equipment_names() -> Dictionary:
	var names: Dictionary = {}
	for definition in GameManager.all_equipment:
		names[definition.id] = definition.name
	return names


func _on_canvas_cell_pressed(cell: Vector2i) -> void:
	if is_read_only:
		return
	var existing := _find_placement_at(cell)
	if existing != null:
		if not selected_placement_instance_id.is_empty() and existing.instance_id != selected_placement_instance_id:
			status_label.text = "该位置已被其他设备占用"
			return
		selected_placement_instance_id = existing.instance_id
		selected_equipment_instance_id = ""
		status_label.text = "已选中设备，可旋转、移除或拖动"
		_refresh_canvas()
		return
	if not selected_placement_instance_id.is_empty():
		var selected_placement := _find_placement(selected_placement_instance_id)
		if selected_placement != null:
			var old_cell := selected_placement.cell
			selected_placement.cell = _display_to_physical_anchor(selected_placement, cell)
			if not _is_valid_placement(selected_placement):
				selected_placement.cell = old_cell
				status_label.text = "位置越界或与其他设备重叠"
				_refresh_canvas()
				return
			status_label.text = "已移动设备"
			_commit_layout()
			return
	if selected_equipment_instance_id.is_empty():
		status_label.text = "请先从左侧选择设备"
		return
	var equipment := _find_equipment(selected_equipment_instance_id)
	if equipment == null:
		return
	var placement := _find_placement(selected_equipment_instance_id)
	var created := placement == null
	if placement == null:
		placement = StoreFurniturePlacement.new()
		placement.instance_id = selected_equipment_instance_id
		placement.equipment_id = equipment.equipment_id
		current_store.furniture_layout.append(placement)
	placement.cell = _display_to_physical_anchor(placement, cell)
	if not _is_valid_placement(placement):
		if created:
			current_store.furniture_layout.erase(placement)
		status_label.text = "位置越界或与其他设备重叠"
		_refresh_canvas()
		return
	selected_placement_instance_id = placement.instance_id
	selected_equipment_instance_id = ""
	status_label.text = "已放置设备"
	_commit_layout()


func _find_placement_at(cell: Vector2i) -> StoreFurniturePlacement:
	for placement in current_store.furniture_layout:
		var display_rect := _get_display_rect(placement)
		if Rect2i(display_rect.cell, display_rect.size).has_point(cell):
			return placement
	return null


func _find_placement(instance_id: String) -> StoreFurniturePlacement:
	for placement in current_store.furniture_layout:
		if placement.instance_id == instance_id:
			return placement
	return null


func _find_equipment(instance_id: String) -> StoreEquipment:
	for item in current_store.equipment:
		if item.instance_id == instance_id:
			return item
	return null


func _is_valid_placement(candidate: StoreFurniturePlacement) -> bool:
	return _is_valid_placement_at(candidate, candidate.cell)


func _is_valid_placement_at(candidate: StoreFurniturePlacement, cell: Vector2i) -> bool:
	return InteriorLayoutValidator.is_valid_placement(candidate, cell, grid_size, current_store.furniture_layout, _get_footprint_sizes(), layout_geometry.available_cells if layout_geometry != null else {}, _get_interior_entrance_cells())


func _display_to_physical_anchor(placement: StoreFurniturePlacement, display_cell: Vector2i) -> Vector2i:
	if layout_geometry == null:
		return display_cell
	return layout_geometry.display_to_physical_placement_cell(display_cell, canvas.get_footprint_size(placement.equipment_id), placement.rotation)


func _get_display_rect(placement: StoreFurniturePlacement) -> Dictionary:
	var footprint := canvas.get_footprint_size(placement.equipment_id)
	if layout_geometry != null:
		return layout_geometry.get_display_placement_rect(placement.cell, footprint, placement.rotation)
	var size := footprint if placement.rotation % 2 == 0 else Vector2i(footprint.y, footprint.x)
	return {"cell": placement.cell, "size": size}


func _get_footprint_sizes() -> Dictionary:
	var footprints: Dictionary = {}
	for placement in current_store.furniture_layout:
		footprints[placement.equipment_id] = canvas.get_footprint_size(placement.equipment_id)
	return footprints


func _on_placement_drag_started(instance_id: String) -> void:
	if is_read_only:
		return
	selected_placement_instance_id = instance_id
	selected_equipment_instance_id = ""
	status_label.text = "拖动设备到目标网格"
	_refresh_canvas()


func _on_placement_drag_previewed(instance_id: String, cell: Vector2i) -> void:
	var placement := _find_placement(instance_id)
	if placement != null:
		var is_valid := _is_valid_placement_at(placement, _display_to_physical_anchor(placement, cell))
		canvas.set_drag_preview_valid(is_valid)
		interior_3d_canvas.set_drag_preview_valid(is_valid)


func _on_placement_drop_requested(instance_id: String, cell: Vector2i) -> void:
	if is_read_only:
		return
	var placement := _find_placement(instance_id)
	if placement == null:
		return
	var physical_cell := _display_to_physical_anchor(placement, cell)
	if not _is_valid_placement_at(placement, physical_cell):
		status_label.text = "位置越界或与其他设备重叠"
		_refresh_canvas()
		return
	placement.cell = physical_cell
	selected_placement_instance_id = instance_id
	status_label.text = "已移动设备"
	_commit_layout()


func _on_rotate_pressed() -> void:
	if is_read_only:
		return
	var placement := _find_placement(selected_placement_instance_id)
	if placement == null:
		return
	var old_rotation := placement.rotation
	placement.rotation = posmod(placement.rotation + 1, 4)
	if not _is_valid_placement(placement):
		placement.rotation = old_rotation
		status_label.text = "旋转后会越界或重叠"
		return
	status_label.text = "已旋转设备"
	_commit_layout()


func _on_delete_pressed() -> void:
	if is_read_only:
		return
	var placement := _find_placement(selected_placement_instance_id)
	if placement == null:
		return
	current_store.furniture_layout.erase(placement)
	selected_placement_instance_id = ""
	status_label.text = "已移除设备"
	_commit_layout()


func _refresh_facade_components() -> void:
	for child in facade_component_list.get_children():
		child.queue_free()
	for child in facade_3d_component_list.get_children():
		child.queue_free()
	for type in FACADE_TYPES:
		var count := _get_facade_type_count(type)
		var maximum := int(FacadeLayoutValidator.MAX_COUNTS[type])
		_add_facade_component_button(facade_component_list, type, count, maximum)
		_add_facade_component_button(facade_3d_component_list, type, count, maximum)


func _add_facade_component_button(list: VBoxContainer, type: String, count: int, maximum: int) -> void:
	var button := Button.new()
	button.text = "%s（%d/%d）" % [str(FACADE_TYPE_NAMES[type]), count, maximum]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = is_read_only or count >= maximum
	button.pressed.connect(func(): _select_facade_type(type))
	list.add_child(button)


func _select_facade_type(type: String) -> void:
	selected_facade_type = type
	selected_facade_placement = null
	status_label.text = "已选择%s，点击门面网格放置" % str(FACADE_TYPE_NAMES[type])
	_refresh_facade_canvas()


func _refresh_facade_canvas() -> void:
	facade_canvas.setup(current_store.facade_layout, facade_grid_size)
	facade_canvas.set_selected(selected_facade_placement)
	facade_3d_canvas.setup(current_store.facade_layout, facade_grid_size, layout_geometry)
	facade_3d_canvas.set_selected(selected_facade_placement)
	facade_delete_button.disabled = is_read_only or selected_facade_placement == null
	facade_3d_delete_button.disabled = is_read_only or selected_facade_placement == null


func _get_facade_type_count(type: String) -> int:
	var count := 0
	for placement in current_store.facade_layout:
		if placement.type == type:
			count += 1
	return count


func _find_facade_placement_at(cell: Vector2i) -> StoreFacadePlacement:
	for placement in current_store.facade_layout:
		if cell in FacadeLayoutValidator.get_footprint_cells(placement.type, placement.cell):
			return placement
	return null


func _on_facade_cell_pressed(cell: Vector2i) -> void:
	if is_read_only:
		return
	var existing := _find_facade_placement_at(cell)
	if existing != null:
		selected_facade_placement = existing
		selected_facade_type = ""
		status_label.text = "已选中%s，可移除或拖动" % str(FACADE_TYPE_NAMES[existing.type])
		_refresh_facade_canvas()
		return
	if selected_facade_placement != null:
		var old_cell := selected_facade_placement.cell
		selected_facade_placement.cell = cell
		if not FacadeLayoutValidator.is_valid_placement(selected_facade_placement, cell, current_store.facade_layout, facade_grid_size):
			selected_facade_placement.cell = old_cell
			status_label.text = "位置越界或与其他组件重叠"
			_refresh_facade_canvas()
			return
		status_label.text = "已移动%s" % str(FACADE_TYPE_NAMES[selected_facade_placement.type])
		_commit_layout()
		return
	if selected_facade_type.is_empty():
		status_label.text = "请先从右侧选择门面组件"
		return
	if not FacadeLayoutValidator.can_add_type(selected_facade_type, current_store.facade_layout):
		status_label.text = "%s数量已达上限" % str(FACADE_TYPE_NAMES[selected_facade_type])
		_refresh_facade_components()
		return
	var placement := StoreFacadePlacement.new()
	placement.type = selected_facade_type
	placement.cell = cell
	if not FacadeLayoutValidator.is_valid_placement(placement, cell, current_store.facade_layout, facade_grid_size):
		status_label.text = "位置越界或与其他组件重叠"
		_refresh_facade_canvas()
		return
	current_store.facade_layout.append(placement)
	selected_facade_placement = placement
	selected_facade_type = ""
	status_label.text = "已放置%s" % str(FACADE_TYPE_NAMES[placement.type])
	_commit_layout()


func _on_facade_drag_started(placement: StoreFacadePlacement) -> void:
	if is_read_only:
		return
	selected_facade_placement = placement
	selected_facade_type = ""
	status_label.text = "拖动%s到目标网格" % str(FACADE_TYPE_NAMES[placement.type])
	_refresh_facade_canvas()


func _on_facade_drag_previewed(placement: StoreFacadePlacement, cell: Vector2i) -> void:
	var is_valid := FacadeLayoutValidator.is_valid_placement(placement, cell, current_store.facade_layout, facade_grid_size)
	facade_canvas.set_drag_preview_valid(is_valid)
	facade_3d_canvas.set_drag_preview_valid(is_valid)


func _on_facade_drop_requested(placement: StoreFacadePlacement, cell: Vector2i) -> void:
	if is_read_only:
		return
	if not FacadeLayoutValidator.is_valid_placement(placement, cell, current_store.facade_layout, facade_grid_size):
		status_label.text = "位置越界或与其他组件重叠"
		_refresh_facade_canvas()
		return
	placement.cell = cell
	selected_facade_placement = placement
	status_label.text = "已移动%s" % str(FACADE_TYPE_NAMES[placement.type])
	_commit_layout()


func _on_facade_delete_pressed() -> void:
	if is_read_only:
		return
	if selected_facade_placement == null:
		return
	var removed_type := selected_facade_placement.type
	current_store.facade_layout.erase(selected_facade_placement)
	selected_facade_placement = null
	status_label.text = "已移除%s" % str(FACADE_TYPE_NAMES[removed_type])
	_commit_layout()


func _on_layout_tab_changed(tab: int) -> void:
	if not visible:
		return
	status_label.text = "选择设备后点击网格放置" if tab == 0 else "选择门面组件后点击网格放置"


func _commit_layout() -> void:
	if is_read_only:
		return
	_refresh_equipment_list()
	_refresh_canvas()
	_refresh_facade_components()
	_refresh_facade_canvas()
	GameManager.store_plan_updated.emit(current_store.id)


func _on_close_pressed() -> void:
	visible = false
	closed.emit()
