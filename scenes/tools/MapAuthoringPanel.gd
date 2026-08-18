@tool
class_name MapAuthoringPanel
extends Control

var document: MapAuthoringDocument
var status_label: Label
var node_id_input: LineEdit
var node_x_input: LineEdit
var node_y_input: LineEdit
var segment_id_input: LineEdit
var segment_from_option: OptionButton
var segment_to_option: OptionButton
var segment_accessibility_input: LineEdit
var segment_exposure_input: LineEdit
var block_option: OptionButton
var block_entry_option: OptionButton
var storefront_option: OptionButton
var export_text: TextEdit
var map_canvas: MapAuthoringCanvas
var save_dialog: FileDialog
var pending_export_files: Dictionary = {}
var road_class_option: OptionButton
var block_id_input: LineEdit
var block_name_input: LineEdit
var block_region_input: LineEdit
var block_type_option: OptionButton
var block_tier_option: OptionButton
var selected_grid_cells: Array[Vector2i] = []
var selected_block_id := ""


func _ready() -> void:
	document = MapAuthoringDocument.from_static_data()
	_build_interface()
	_refresh_options()
	_set_status("\u5df2\u8f7d\u5165\u72ec\u7acb\u5730\u56fe\u7f16\u8f91\u6587\u6863\u3002")


func _build_interface() -> void:
	var workspace := HBoxContainer.new()
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.add_theme_constant_override("separation", 12)
	add_child(workspace)
	var controls_scroll := ScrollContainer.new()
	controls_scroll.custom_minimum_size = Vector2(390, 0)
	controls_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	controls_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(controls_scroll)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(370, 0)
	root.add_theme_constant_override("separation", 8)
	controls_scroll.add_child(root)

	var title := Label.new()
	title.text = "\u5730\u56fe\u5236\u4f5c\u5de5\u5177\uff08\u5f00\u53d1\u7528\uff09"
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	var map_scroll := ScrollContainer.new()
	map_scroll.custom_minimum_size = Vector2(820, 0)
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_canvas = MapAuthoringCanvas.new()
	map_canvas.setup(document)
	map_canvas.node_moved.connect(_on_canvas_node_moved)
	map_canvas.storefront_moved.connect(_on_canvas_storefront_moved)
	map_canvas.block_moved.connect(_on_canvas_block_moved)
	map_canvas.grid_road_requested.connect(_on_grid_road_requested)
	map_canvas.grid_cells_selected.connect(_on_grid_cells_selected)
	map_canvas.grid_block_selected.connect(_on_grid_block_selected)
	map_canvas.road_node_selected.connect(_on_road_node_selected)
	map_canvas.road_segment_selected.connect(_on_road_segment_selected)
	map_canvas.selection_cleared.connect(_on_selection_cleared)
	map_canvas.edit_rejected.connect(_set_status)
	map_scroll.add_child(map_canvas)
	workspace.add_child(map_scroll)
	var mode_row := HFlowContainer.new()
	for item in [["选择", MapAuthoringCanvas.EditMode.SELECT], ["绘制道路", MapAuthoringCanvas.EditMode.ROAD], ["框选区块", MapAuthoringCanvas.EditMode.BLOCK]]:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(map_canvas.set_edit_mode.bind(item[1]))
		mode_row.add_child(button)
	road_class_option = OptionButton.new()
	for road_class in MapAuthoringDocument.ROAD_CLASS_DATA.keys():
		road_class_option.add_item(str(MapAuthoringDocument.ROAD_CLASS_LABELS.get(road_class, road_class)))
		road_class_option.set_item_metadata(road_class_option.item_count - 1, road_class)
	mode_row.add_child(road_class_option)
	var zoom_label := Label.new()
	zoom_label.text = "缩放"
	mode_row.add_child(zoom_label)
	var zoom_slider := HSlider.new()
	zoom_slider.min_value = 0.5
	zoom_slider.max_value = 3.0
	zoom_slider.step = 0.1
	zoom_slider.value = 1.0
	zoom_slider.custom_minimum_size = Vector2(160, 0)
	zoom_slider.value_changed.connect(map_canvas.set_zoom)
	mode_row.add_child(zoom_slider)
	root.add_child(mode_row)
	var block_create_row := HFlowContainer.new()
	block_id_input = _make_input("block_id")
	block_name_input = _make_input("名称")
	block_region_input = _make_input("city_region_id")
	block_type_option = OptionButton.new()
	for block_type in ["residential", "school", "office", "commercial", "industrial"]:
		block_type_option.add_item(block_type)
	block_tier_option = OptionButton.new()
	for tier in range(1, 4):
		block_tier_option.add_item(str(tier))
	var create_block_button := Button.new()
	create_block_button.text = "用已框选网格创建区块"
	create_block_button.pressed.connect(_on_create_grid_block_pressed)
	var update_block_button := Button.new()
	update_block_button.text = "更新选中区块属性"
	update_block_button.pressed.connect(_on_update_grid_block_pressed)
	var append_cells_button := Button.new()
	append_cells_button.text = "加入选中区块"
	append_cells_button.pressed.connect(_on_append_cells_to_block_pressed)
	var delete_block_button := Button.new()
	delete_block_button.text = "删除选中区块"
	delete_block_button.pressed.connect(_on_delete_selected_block_pressed)
	for control in [block_id_input, block_name_input, block_region_input, block_type_option, block_tier_option, create_block_button, update_block_button, append_cells_button, delete_block_button]:
		block_create_row.add_child(control)
	root.add_child(block_create_row)

	root.add_child(_make_separator())
	root.add_child(_make_section_label("\u9053\u8def\u8282\u70b9"))
	var node_row := HFlowContainer.new()
	node_id_input = _make_input("node_id")
	node_x_input = _make_input("x")
	node_y_input = _make_input("y")
	node_row.add_child(node_id_input)
	node_row.add_child(node_x_input)
	node_row.add_child(node_y_input)
	var add_node_button := Button.new()
	add_node_button.text = "\u6dfb\u52a0\u8282\u70b9"
	add_node_button.pressed.connect(_on_add_node_pressed)
	node_row.add_child(add_node_button)
	var delete_node_button := Button.new()
	delete_node_button.text = "删除节点"
	delete_node_button.pressed.connect(_on_delete_node_pressed)
	node_row.add_child(delete_node_button)
	root.add_child(node_row)

	root.add_child(_make_section_label("\u9053\u8def\u8def\u6bb5"))
	var segment_row := HFlowContainer.new()
	segment_id_input = _make_input("segment_id")
	segment_from_option = OptionButton.new()
	segment_to_option = OptionButton.new()
	segment_accessibility_input = _make_input("\u53ef\u8fbe\u6027")
	segment_accessibility_input.text = "1.0"
	segment_exposure_input = _make_input("\u66dd\u5149")
	segment_exposure_input.text = "1.0"
	segment_row.add_child(segment_id_input)
	segment_row.add_child(segment_from_option)
	segment_row.add_child(segment_to_option)
	segment_row.add_child(segment_accessibility_input)
	segment_row.add_child(segment_exposure_input)
	var add_segment_button := Button.new()
	add_segment_button.text = "\u6dfb\u52a0\u8def\u6bb5"
	add_segment_button.pressed.connect(_on_add_segment_pressed)
	segment_row.add_child(add_segment_button)
	var delete_segment_button := Button.new()
	delete_segment_button.text = "删除路段"
	delete_segment_button.pressed.connect(_on_delete_segment_pressed)
	segment_row.add_child(delete_segment_button)
	var update_segment_button := Button.new()
	update_segment_button.text = "更新道路等级"
	update_segment_button.pressed.connect(_on_update_segment_class_pressed)
	segment_row.add_child(update_segment_button)
	root.add_child(segment_row)

	root.add_child(_make_section_label("\u533a\u5757\u4e0e\u95e8\u9762\u5173\u8054"))
	var link_row := HFlowContainer.new()
	block_option = OptionButton.new()
	block_entry_option = OptionButton.new()
	link_row.add_child(block_option)
	link_row.add_child(block_entry_option)
	var assign_block_button := Button.new()
	assign_block_button.text = "\u8bbe\u7f6e\u533a\u5757\u5165\u53e3"
	assign_block_button.pressed.connect(_on_assign_block_entry_pressed)
	link_row.add_child(assign_block_button)
	storefront_option = OptionButton.new()
	link_row.add_child(storefront_option)
	var assign_storefront_button := Button.new()
	assign_storefront_button.text = "\u5173\u8054\u6700\u8fd1\u9053\u8def"
	assign_storefront_button.pressed.connect(_on_assign_storefront_pressed)
	link_row.add_child(assign_storefront_button)
	var append_storefront_cells_button := Button.new()
	append_storefront_cells_button.text = "\u5c06\u6846\u9009\u7f51\u683c\u52a0\u5165\u9009\u4e2d\u95e8\u9762"
	append_storefront_cells_button.pressed.connect(_on_append_cells_to_storefront_pressed)
	link_row.add_child(append_storefront_cells_button)
	root.add_child(link_row)

	root.add_child(_make_separator())
	var action_row := HFlowContainer.new()
	var validate_button := Button.new()
	validate_button.text = "\u6821\u9a8c\u5730\u56fe"
	validate_button.pressed.connect(_on_validate_pressed)
	action_row.add_child(validate_button)
	var export_button := Button.new()
	export_button.text = "\u751f\u6210\u5bfc\u51fa\u9884\u89c8"
	export_button.pressed.connect(_on_export_pressed)
	action_row.add_child(export_button)
	var save_button := Button.new()
	save_button.text = "\u4fdd\u5b58\u5bfc\u51fa\u6587\u4ef6"
	save_button.pressed.connect(_on_save_pressed)
	action_row.add_child(save_button)
	root.add_child(action_row)

	export_text = TextEdit.new()
	export_text.custom_minimum_size = Vector2(0, 260)
	export_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	export_text.editable = false
	root.add_child(export_text)

	save_dialog = FileDialog.new()
	save_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	save_dialog.dir_selected.connect(_on_export_directory_selected)
	add_child(save_dialog)


func _make_input(placeholder: String) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.custom_minimum_size = Vector2(95, 0)
	return input


func _make_separator() -> HSeparator:
	return HSeparator.new()


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _refresh_options() -> void:
	_refresh_node_option(segment_from_option)
	_refresh_node_option(segment_to_option)
	_refresh_node_option(block_entry_option)
	block_option.clear()
	for block in document.blocks:
		block_option.add_item("%s (%s)" % [block.name, block.id])
		block_option.set_item_metadata(block_option.item_count - 1, block.id)
	storefront_option.clear()
	for storefront in document.storefronts:
		storefront_option.add_item("%s (%s)" % [storefront.name, storefront.id])
		storefront_option.set_item_metadata(storefront_option.item_count - 1, storefront.id)


func _refresh_node_option(option: OptionButton) -> void:
	option.clear()
	var ids: Array[String] = []
	for node_id in document.road_graph.nodes.keys():
		ids.append(str(node_id))
	ids.sort()
	for node_id in ids:
		option.add_item(node_id)
		option.set_item_metadata(option.item_count - 1, node_id)


func _selected_id(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func _on_add_node_pressed() -> void:
	var node_id := node_id_input.text.strip_edges()
	if document.add_road_node(node_id, Vector2(node_x_input.text.to_float(), node_y_input.text.to_float())):
		_refresh_options()
		map_canvas.refresh_canvas()
		_set_status("\u5df2\u6dfb\u52a0\u9053\u8def\u8282\u70b9\uff1a" + node_id)
	else:
		_set_status("\u65e0\u6cd5\u6dfb\u52a0\u8282\u70b9\uff1aID \u4e3a\u7a7a\u6216\u5df2\u5b58\u5728\u3002")


func _on_add_segment_pressed() -> void:
	var segment_id := segment_id_input.text.strip_edges()
	if document.add_road_segment(segment_id, _selected_id(segment_from_option), _selected_id(segment_to_option), segment_accessibility_input.text.to_float(), segment_exposure_input.text.to_float()):
		map_canvas.refresh_canvas()
		_set_status("\u5df2\u6dfb\u52a0\u9053\u8def\u8def\u6bb5\uff1a" + segment_id)
	else:
		_set_status("\u65e0\u6cd5\u6dfb\u52a0\u8def\u6bb5\uff1a\u8bf7\u68c0\u67e5 ID \u4e0e\u8282\u70b9\u3002")


func _on_assign_block_entry_pressed() -> void:
	var block_id := _selected_id(block_option)
	if document.assign_block_road_entry(block_id, _selected_id(block_entry_option)):
		_set_status("\u5df2\u66f4\u65b0\u533a\u5757\u7684\u9053\u8def\u5165\u53e3\u3002")
	else:
		_set_status("\u65e0\u6cd5\u66f4\u65b0\u533a\u5757\u5165\u53e3\u3002")


func _on_assign_storefront_pressed() -> void:
	if document.assign_storefront_nearest_road(_selected_id(storefront_option)):
		_set_status("\u5df2\u4e3a\u95e8\u9762\u5173\u8054\u6700\u8fd1\u9053\u8def\u3002")
	else:
		_set_status("\u65e0\u6cd5\u4e3a\u95e8\u9762\u5173\u8054\u9053\u8def\u3002")


func _on_validate_pressed() -> void:
	var errors := document.validate()
	_set_status("\u5730\u56fe\u6821\u9a8c\u901a\u8fc7\u3002" if errors.is_empty() else "\u5730\u56fe\u6821\u9a8c\u5931\u8d25\uff1a\n" + "\n".join(errors))


func _on_export_pressed() -> void:
	var exported := document.export_map_data()
	if not bool(exported.get("success", false)):
		_set_status("\u5bfc\u51fa\u5931\u8d25\uff1a\n" + "\n".join(exported.get("errors", [])))
		return
	export_text.text = JSON.stringify(exported, "\t")
	_set_status("\u5df2\u751f\u6210\u5bfc\u51fa\u9884\u89c8\uff1b\u8bf7\u590d\u6838\u540e\u518d\u5199\u5165\u6570\u636e\u6587\u4ef6\u3002")


func _on_save_pressed() -> void:
	var exported := document.export_json_files()
	if not bool(exported.get("success", false)):
		_set_status("\u5bfc\u51fa\u5931\u8d25\uff1a\u8bf7\u5148\u4fee\u590d\u5730\u56fe\u6821\u9a8c\u9519\u8bef\u3002")
		return
	pending_export_files = exported.get("files", {})
	save_dialog.popup_centered_ratio(0.7)
	_set_status("\u8bf7\u9009\u62e9\u5bfc\u51fa\u76ee\u5f55\u3002\u540c\u540d JSON \u6587\u4ef6\u5c06\u88ab\u66ff\u6362\u3002")


func _on_export_directory_selected(directory: String) -> void:
	var failed_files: Array[String] = []
	for file_name in pending_export_files.keys():
		var path := directory.path_join(str(file_name))
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			failed_files.append(str(file_name))
			continue
		file.store_string(str(pending_export_files[file_name]))
		file.close()
	if failed_files.is_empty():
		_set_status("\u5df2\u5bfc\u51fa roads.json\u3001blocks.json \u548c storefronts.json\u3002")
	else:
		_set_status("\u4ee5\u4e0b\u6587\u4ef6\u5bfc\u51fa\u5931\u8d25\uff1a" + "\u3001".join(failed_files))


func _on_canvas_node_moved(node_id: String) -> void:
	_set_status("\u5df2\u79fb\u52a8\u9053\u8def\u8282\u70b9\uff1a" + node_id)


func _on_canvas_storefront_moved(storefront_id: String) -> void:
	_set_status("\u5df2\u79fb\u52a8\u95e8\u9762\u5e76\u91cd\u65b0\u5173\u8054\u6700\u8fd1\u9053\u8def\uff1a" + storefront_id)


func _on_canvas_block_moved(block_id: String) -> void:
	_set_status("\u5df2\u79fb\u52a8\u533a\u5757\uff1a" + block_id + "\uff1b\u5982\u6709\u9700\u8981\uff0c\u8bf7\u540c\u65f6\u66f4\u65b0\u5176\u9053\u8def\u5165\u53e3\u3002")


func _set_status(message: String) -> void:
	status_label.text = message


func _on_grid_road_requested(from_cell: Vector2i, to_cell: Vector2i) -> void:
	var segment_id := segment_id_input.text.strip_edges()
	if segment_id.is_empty():
		segment_id = "road_grid_%d" % document.road_graph.segments.size()
	var road_class := str(road_class_option.get_item_metadata(road_class_option.selected))
	if document.add_grid_road(segment_id, from_cell, to_cell, road_class):
		segment_id_input.clear()
		_refresh_options()
		map_canvas.refresh_canvas()
		_set_status("道路已创建：" + segment_id)
	else:
		_set_status("无法创建道路：ID 已存在或道路等级无效。")


func _on_grid_cells_selected(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		selected_grid_cells.clear()
		map_canvas.set_selected_grid_cells(selected_grid_cells)
		_set_status("已取消网格选择。")
		return
	for cell in cells:
		if not document.road_cells.has(cell) and not selected_grid_cells.has(cell):
			selected_grid_cells.append(cell)
	map_canvas.set_selected_grid_cells(selected_grid_cells)
	_set_status("已选择 %d 个非道路网格。" % selected_grid_cells.size())


func _on_selection_cleared() -> void:
	selected_grid_cells.clear()
	selected_block_id = ""
	map_canvas.set_selected_grid_cells(selected_grid_cells)
	_set_status("已取消当前选择。")


func _on_create_grid_block_pressed() -> void:
	var block := document.create_block_from_cells(
		block_id_input.text.strip_edges(), block_name_input.text.strip_edges(), block_region_input.text.strip_edges(),
		selected_grid_cells, block_type_option.get_item_text(block_type_option.selected), block_tier_option.selected + 1)
	if block == null:
		_set_status("无法创建区块：请填写唯一 ID、城市区域，并选择不与道路重叠的网格。")
		return
	selected_grid_cells.clear()
	map_canvas.set_selected_grid_cells(selected_grid_cells)
	_refresh_options()
	map_canvas.refresh_canvas()
	_set_status("多边形区块已创建：" + block.id)


func _on_grid_block_selected(block_id: String) -> void:
	for block in document.blocks:
		if block.id != block_id:
			continue
		selected_block_id = block.id
		block_id_input.text = block.id
		block_name_input.text = block.name
		block_region_input.text = block.city_region_id
		for index in range(block_type_option.item_count):
			if block_type_option.get_item_text(index) == block.block_type:
				block_type_option.select(index)
				break
		block_tier_option.select(clampi(block.tier - 1, 0, 2))
		_set_status("已选中区块：" + block.id)
		return


func _on_update_grid_block_pressed() -> void:
	if selected_block_id.is_empty():
		_set_status("请先在选择模式点击一个区块。")
		return
	if document.update_block_properties(selected_block_id, block_name_input.text.strip_edges(), block_region_input.text.strip_edges(), block_type_option.get_item_text(block_type_option.selected), block_tier_option.selected + 1):
		map_canvas.refresh_canvas()
		_set_status("区块属性已更新：" + selected_block_id)


func _on_append_cells_to_block_pressed() -> void:
	if selected_block_id.is_empty() or not document.add_cells_to_block(selected_block_id, selected_grid_cells):
		_set_status("无法加入网格：请先选中区块，且网格不得包含道路并需与道路相邻。")
		return
	selected_grid_cells.clear()
	map_canvas.set_selected_grid_cells(selected_grid_cells)
	map_canvas.refresh_canvas()
	_set_status("已将网格加入选中区块。")


func _on_append_cells_to_storefront_pressed() -> void:
	var storefront_id := _selected_id(storefront_option)
	if storefront_id.is_empty() or not document.add_cells_to_storefront(storefront_id, selected_grid_cells):
		_set_status("\u65e0\u6cd5\u52a0\u5165\u7f51\u683c\uff1a\u8bf7\u9009\u62e9\u95e8\u9762\uff0c\u5e76\u786e\u4fdd\u7f51\u683c\u5728\u540c\u4e00\u533a\u5757\u5185\u4e14\u4e0e\u73b0\u6709\u95e8\u9762\u8fde\u901a\u3002")
		return
	selected_grid_cells.clear()
	map_canvas.set_selected_grid_cells(selected_grid_cells)
	map_canvas.refresh_canvas()
	_set_status("\u5df2\u5c06\u7f51\u683c\u52a0\u5165\u9009\u4e2d\u95e8\u9762\u3002")


func _on_delete_selected_block_pressed() -> void:
	if document.remove_block(selected_block_id):
		selected_block_id = ""
		_refresh_options()
		map_canvas.refresh_canvas()
		_set_status("区块已删除。")


func _on_delete_node_pressed() -> void:
	if document.remove_road_node(node_id_input.text.strip_edges()):
		_refresh_options()
		map_canvas.refresh_canvas()
		_set_status("节点及关联路段已删除。")


func _on_delete_segment_pressed() -> void:
	if document.remove_road_segment(segment_id_input.text.strip_edges()):
		_refresh_options()
		map_canvas.refresh_canvas()
		_set_status("路段已删除。")


func _on_road_node_selected(node_id: String) -> void:
	node_id_input.text = node_id
	_set_status("已选中道路节点：" + node_id)


func _on_road_segment_selected(segment_id: String) -> void:
	segment_id_input.text = segment_id
	var current_class := document.get_road_class(segment_id)
	for index in range(road_class_option.item_count):
		if str(road_class_option.get_item_metadata(index)) == current_class:
			road_class_option.select(index)
			break
	_set_status("已选中道路路段：" + segment_id)


func _on_update_segment_class_pressed() -> void:
	var road_class := str(road_class_option.get_item_metadata(road_class_option.selected))
	if document.set_road_class(segment_id_input.text.strip_edges(), road_class):
		map_canvas.refresh_canvas()
		_set_status("道路等级已更新。")
