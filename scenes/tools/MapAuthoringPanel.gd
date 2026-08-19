@tool
class_name MapAuthoringPanel
extends Control

const REFERENCE_MAP_PATH := "res://data/concept_city_grid_map.json"

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
var storefront_id_input: LineEdit
var storefront_name_input: LineEdit
var storefront_rent_input: LineEdit
var storefront_area_input: LineEdit
var storefront_footprint_input: LineEdit
var block_merge_target_input: LineEdit
var storefront_merge_target_input: LineEdit
var storefront_capacity_input: LineEdit
var storefront_awareness_radius_input: LineEdit
var storefront_awareness_exposure_input: LineEdit
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
var block_accessibility_input: LineEdit
var block_development_input: LineEdit
var block_price_input: LineEdit
var block_quality_input: LineEdit
var block_time_input: LineEdit
var block_competition_option: OptionButton
var block_rent_pressure_option: OptionButton
var block_tags_input: LineEdit
var selection_offset_x_input: LineEdit
var selection_offset_y_input: LineEdit
var selected_grid_cells: Array[Vector2i] = []
var selected_block_id := ""
var selected_storefront_id := ""
var block_editor_row: Control
var block_simulation_row: Control
var block_link_row: Control
var storefront_link_row: Control
var storefront_editor_row: Control


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
	controls_scroll.custom_minimum_size = Vector2(480, 0)
	controls_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	controls_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(controls_scroll)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(460, 0)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	map_canvas.storefront_selected.connect(_on_storefront_selected)
	map_canvas.additional_element_selected.connect(_on_additional_element_selected)
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
	var selection_tools_row := HFlowContainer.new()
	selection_offset_x_input = _make_input("dx")
	selection_offset_y_input = _make_input("dy")
	selection_offset_x_input.text = "1"
	selection_offset_y_input.text = "0"
	var move_selection_button := Button.new()
	move_selection_button.text = "\u79fb\u52a8\u6846\u9009"
	move_selection_button.pressed.connect(_on_move_selected_cells_pressed)
	var copy_selection_button := Button.new()
	copy_selection_button.text = "\u590d\u5236\u6846\u9009"
	copy_selection_button.pressed.connect(_on_copy_selected_cells_pressed)
	var delete_selection_button := Button.new()
	delete_selection_button.text = "\u5220\u9664\u6846\u9009\u7f51\u683c"
	delete_selection_button.pressed.connect(_on_delete_selected_cells_pressed)
	for control in [_make_labeled_field("\u6c34\u5e73\u504f\u79fb", selection_offset_x_input), _make_labeled_field("\u5782\u76f4\u504f\u79fb", selection_offset_y_input), move_selection_button, copy_selection_button, delete_selection_button]:
		selection_tools_row.add_child(control)
	root.add_child(selection_tools_row)
	block_editor_row = HFlowContainer.new()
	block_id_input = _make_input("block_id")
	block_name_input = _make_input("名称")
	block_region_input = _make_input("city_region_id")
	block_type_option = OptionButton.new()
	for block_type in ["residential", "school", "office", "commercial", "industrial", "mixed", "tourism", "public_green"]:
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
	for control in [_make_labeled_field("\u533a\u5757 ID", block_id_input), _make_labeled_field("\u533a\u5757\u540d\u79f0", block_name_input), _make_labeled_field("\u57ce\u5e02\u533a\u57df ID", block_region_input), _make_labeled_field("\u533a\u5757\u7c7b\u578b", block_type_option), _make_labeled_field("\u533a\u5757\u7b49\u7ea7", block_tier_option), create_block_button, update_block_button, append_cells_button, delete_block_button]:
		block_editor_row.add_child(control)
	root.add_child(block_editor_row)
	block_editor_row.visible = false
	block_simulation_row = HFlowContainer.new()
	block_accessibility_input = _make_input("\u53ef\u8fbe\u6027 0-1")
	block_development_input = _make_input("\u53d1\u5c55\u5ea6")
	block_price_input = _make_input("\u4ef7\u683c\u654f\u611f 0-1")
	block_quality_input = _make_input("\u54c1\u8d28\u504f\u597d 0-1")
	block_time_input = _make_input("\u65f6\u6bb5:0.8,1,1.2,0.6")
	block_time_input.custom_minimum_size = Vector2(150, 0)
	block_competition_option = OptionButton.new()
	block_rent_pressure_option = OptionButton.new()
	for value in ["low", "medium", "high"]:
		block_competition_option.add_item(value)
		block_rent_pressure_option.add_item(value)
	block_tags_input = _make_input("tags,comma,separated")
	block_tags_input.custom_minimum_size = Vector2(160, 0)
	var update_simulation_button := Button.new()
	update_simulation_button.text = "\u66f4\u65b0\u533a\u5757\u7ecf\u8425\u5c5e\u6027"
	update_simulation_button.pressed.connect(_on_update_block_simulation_pressed)
	for control in [_make_labeled_field("\u53ef\u8fbe\u6027", block_accessibility_input), _make_labeled_field("\u53d1\u5c55\u5ea6", block_development_input), _make_labeled_field("\u4ef7\u683c\u654f\u611f\u5ea6", block_price_input), _make_labeled_field("\u54c1\u8d28\u504f\u597d", block_quality_input), _make_labeled_field("\u65f6\u6bb5\u7cfb\u6570", block_time_input), _make_labeled_field("\u7ade\u4e89\u7b49\u7ea7", block_competition_option), _make_labeled_field("\u79df\u91d1\u538b\u529b", block_rent_pressure_option), _make_labeled_field("\u6807\u7b7e", block_tags_input), update_simulation_button]:
		block_simulation_row.add_child(control)
	root.add_child(block_simulation_row)
	block_simulation_row.visible = false

	root.add_child(_make_separator())
	root.add_child(_make_section_label("\u9053\u8def\u8282\u70b9"))
	var node_row := HFlowContainer.new()
	node_id_input = _make_input("node_id")
	node_x_input = _make_input("x")
	node_y_input = _make_input("y")
	node_row.add_child(_make_labeled_field("\u8282\u70b9 ID", node_id_input))
	node_row.add_child(_make_labeled_field("X \u5750\u6807", node_x_input))
	node_row.add_child(_make_labeled_field("Y \u5750\u6807", node_y_input))
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
	segment_row.add_child(_make_labeled_field("\u8def\u6bb5 ID", segment_id_input))
	segment_row.add_child(_make_labeled_field("\u8d77\u70b9\u8282\u70b9", segment_from_option))
	segment_row.add_child(_make_labeled_field("\u7ec8\u70b9\u8282\u70b9", segment_to_option))
	segment_row.add_child(_make_labeled_field("\u53ef\u8fbe\u6027", segment_accessibility_input))
	segment_row.add_child(_make_labeled_field("\u66dd\u5149\u5ea6", segment_exposure_input))
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
	block_link_row = HFlowContainer.new()
	block_option = OptionButton.new()
	block_entry_option = OptionButton.new()
	block_link_row.add_child(block_option)
	block_link_row.add_child(block_entry_option)
	var assign_block_button := Button.new()
	assign_block_button.text = "\u8bbe\u7f6e\u533a\u5757\u5165\u53e3"
	assign_block_button.pressed.connect(_on_assign_block_entry_pressed)
	block_link_row.add_child(assign_block_button)
	block_merge_target_input = _make_input("\u8981\u5408\u5e76\u7684\u533a\u5757 ID")
	block_link_row.add_child(block_merge_target_input)
	var merge_block_button := Button.new()
	merge_block_button.text = "\u5408\u5e76\u76f8\u90bb\u533a\u5757"
	merge_block_button.pressed.connect(_on_merge_blocks_pressed)
	block_link_row.add_child(merge_block_button)
	root.add_child(block_link_row)
	block_link_row.visible = false
	storefront_link_row = HFlowContainer.new()
	storefront_option = OptionButton.new()
	storefront_link_row.add_child(storefront_option)
	var assign_storefront_button := Button.new()
	assign_storefront_button.text = "\u5173\u8054\u6700\u8fd1\u9053\u8def"
	assign_storefront_button.pressed.connect(_on_assign_storefront_pressed)
	storefront_link_row.add_child(assign_storefront_button)
	var append_storefront_cells_button := Button.new()
	append_storefront_cells_button.text = "\u5c06\u6846\u9009\u7f51\u683c\u52a0\u5165\u9009\u4e2d\u95e8\u9762"
	append_storefront_cells_button.pressed.connect(_on_append_cells_to_storefront_pressed)
	storefront_link_row.add_child(append_storefront_cells_button)
	storefront_merge_target_input = _make_input("\u8981\u5408\u5e76\u7684\u95e8\u9762 ID")
	storefront_link_row.add_child(storefront_merge_target_input)
	var merge_storefront_button := Button.new()
	merge_storefront_button.text = "\u5408\u5e76\u76f8\u90bb\u95e8\u9762"
	merge_storefront_button.pressed.connect(_on_merge_storefronts_pressed)
	storefront_link_row.add_child(merge_storefront_button)
	root.add_child(storefront_link_row)
	storefront_link_row.visible = false
	storefront_editor_row = HFlowContainer.new()
	storefront_id_input = _make_input("storefront_id")
	storefront_name_input = _make_input("\u95e8\u9762\u540d\u79f0")
	storefront_rent_input = _make_input("\u6708\u79df(\u4e07)")
	storefront_area_input = _make_input("\u9762\u79ef")
	storefront_footprint_input = _make_input("12.25")
	storefront_capacity_input = _make_input("\u6bcf\u5c0f\u65f6\u5bb9\u91cf")
	storefront_awareness_radius_input = _make_input("35")
	storefront_awareness_exposure_input = _make_input("1.0")
	var create_storefront_button := Button.new()
	create_storefront_button.text = "\u7528\u6846\u9009\u7f51\u683c\u521b\u5efa\u95e8\u9762"
	create_storefront_button.pressed.connect(_on_create_storefront_pressed)
	var update_storefront_button := Button.new()
	update_storefront_button.text = "\u66f4\u65b0\u9009\u4e2d\u95e8\u9762"
	update_storefront_button.pressed.connect(_on_update_storefront_pressed)
	var delete_storefront_button := Button.new()
	delete_storefront_button.text = "\u5220\u9664\u9009\u4e2d\u95e8\u9762"
	delete_storefront_button.pressed.connect(_on_delete_storefront_pressed)
	for control in [_make_labeled_field("\u95e8\u9762 ID", storefront_id_input), _make_labeled_field("\u95e8\u9762\u540d\u79f0", storefront_name_input), _make_labeled_field("\u6708\u79df\uff08\u4e07\u5143）", storefront_rent_input), _make_labeled_field("\u53ef\u7528\u9762\u79ef\uff08\u33a1）", storefront_area_input), _make_labeled_field("\u5360\u5730\u9762\u79ef\uff08\u33a1）", storefront_footprint_input), _make_labeled_field("\u7ebf\u4e0b\u5f71\u54cd\u534a\u5f84\uff08\u7c73）", storefront_awareness_radius_input), _make_labeled_field("\u77e5\u540d\u5ea6\u66dd\u5149\u4fee\u6b63", storefront_awareness_exposure_input), create_storefront_button, update_storefront_button, delete_storefront_button]:
		storefront_editor_row.add_child(control)
	root.add_child(storefront_editor_row)
	storefront_editor_row.visible = false

	root.add_child(_make_separator())
	var action_row := HFlowContainer.new()
	var new_map_button := Button.new()
	new_map_button.text = "\u65b0\u5efa\u7a7a\u767d\u5730\u56fe"
	new_map_button.pressed.connect(_on_new_blank_map_pressed)
	action_row.add_child(new_map_button)
	var reference_map_button := Button.new()
	reference_map_button.text = "\u8f7d\u5165\u5f69\u8272\u57ce\u533a\u793a\u4f8b"
	reference_map_button.pressed.connect(_on_load_reference_map_pressed)
	action_row.add_child(reference_map_button)
	var validate_button := Button.new()
	validate_button.text = "\u6821\u9a8c\u5730\u56fe"
	validate_button.pressed.connect(_on_validate_pressed)
	action_row.add_child(validate_button)
	var export_button := Button.new()
	export_button.text = "\u751f\u6210\u5bfc\u51fa\u9884\u89c8"
	export_button.pressed.connect(_on_export_pressed)
	action_row.add_child(export_button)
	var import_button := Button.new()
	import_button.text = "\u5bfc\u5165\u9884\u89c8 JSON"
	import_button.pressed.connect(_on_import_preview_pressed)
	action_row.add_child(import_button)
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


func _make_labeled_field(label_text: String, control: Control) -> VBoxContainer:
	var field := VBoxContainer.new()
	field.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	field.add_child(label)
	field.add_child(control)
	return field


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
	map_canvas.set_validation_errors(errors)
	_set_status("\u5730\u56fe\u6821\u9a8c\u901a\u8fc7\u3002" if errors.is_empty() else "\u5730\u56fe\u6821\u9a8c\u5931\u8d25\uff1a\n" + "\n".join(errors))


func _on_new_blank_map_pressed() -> void:
	document = MapAuthoringDocument.new()
	map_canvas.setup(document)
	selected_grid_cells.clear()
	selected_block_id = ""
	selected_storefront_id = ""
	_refresh_options()
	_set_status("\u5df2\u521b\u5efa\u7a7a\u767d\u5730\u56fe\uff1b\u753b\u5e03\u56db\u8fb9\u4fdd\u7559 5 \u4e2a\u7f51\u683c\u7684\u7f16\u8f91\u7a7a\u95f4\u3002")


func _on_load_reference_map_pressed() -> void:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(REFERENCE_MAP_PATH)) != OK or not parser.data is Dictionary:
		_set_status("\u65e0\u6cd5\u8bfb\u53d6\u5f69\u8272\u57ce\u533a\u793a\u4f8b JSON\u3002")
		return
	var result: Dictionary = MapAuthoringDocument.from_exported_map_data(parser.data)
	if not bool(result.get("success", false)):
		_set_status("\u793a\u4f8b\u5730\u56fe\u6821\u9a8c\u5931\u8d25\uff1a\n" + "\n".join(result.get("errors", [])))
		return
	document = result.get("document", document)
	map_canvas.setup(document)
	selected_grid_cells.clear()
	selected_block_id = ""
	selected_storefront_id = ""
	_refresh_options()
	_set_status("\u5df2\u4ece concept_city_grid_map.json \u8f7d\u5165\u5f69\u8272\u57ce\u533a\u793a\u4f8b\u3002")


func _on_export_pressed() -> void:
	var exported := document.export_map_data()
	if not bool(exported.get("success", false)):
		_set_status("\u5bfc\u51fa\u5931\u8d25\uff1a\n" + "\n".join(exported.get("errors", [])))
		return
	export_text.text = JSON.stringify(exported, "\t")
	_set_status("\u5df2\u751f\u6210\u5bfc\u51fa\u9884\u89c8\uff1b\u8bf7\u590d\u6838\u540e\u518d\u5199\u5165\u6570\u636e\u6587\u4ef6\u3002")


func _on_import_preview_pressed() -> void:
	var parser := JSON.new()
	if parser.parse(export_text.text) != OK or not parser.data is Dictionary:
		_set_status("\u5bfc\u5165\u5931\u8d25\uff1a\u8bf7\u5728\u9884\u89c8\u6846\u7c98\u8d34\u5b8c\u6574\u7684\u5730\u56fe JSON\u3002")
		return
	var result: Dictionary = MapAuthoringDocument.from_exported_map_data(parser.data)
	var errors: Array = result.get("errors", [])
	if not bool(result.get("success", false)):
		_set_status("\u5bfc\u5165\u9884\u89c8\u672a\u901a\u8fc7\uff1a\n" + "\n".join(errors))
		return
	document = result.get("document", document)
	map_canvas.setup(document)
	_refresh_options()
	_set_status("\u5bfc\u5165\u5e76\u6821\u9a8c\u901a\u8fc7\u3002")


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


func _on_additional_element_selected(element_id: String, is_storefront: bool) -> void:
	var target_input := storefront_merge_target_input if is_storefront else block_merge_target_input
	var ids: PackedStringArray = target_input.text.split(",", false)
	if not ids.has(element_id):
		ids.append(element_id)
	target_input.text = ",".join(ids)
	_set_status("\u5df2\u6dfb\u52a0\u5408\u5e76\u9009\u62e9\uff1a" + str(ids.size() + 1))


func _on_storefront_selected(storefront_id: String) -> void:
	_set_editor_visibility(false, true)
	for storefront in document.storefronts:
		if storefront.id != storefront_id:
			continue
		selected_storefront_id = storefront_id
		storefront_id_input.text = storefront.id
		storefront_name_input.text = storefront.name
		storefront_rent_input.text = str(storefront.monthly_rent_wan)
		storefront_area_input.text = str(storefront.area)
		storefront_footprint_input.text = str(storefront.footprint_area)
		storefront_awareness_radius_input.text = str(storefront.awareness_radius)
		storefront_awareness_exposure_input.text = str(storefront.awareness_exposure_modifier)
		for index in range(storefront_option.item_count):
			if str(storefront_option.get_item_metadata(index)) == storefront_id:
				storefront_option.select(index)
				break
		map_canvas.set_selected_storefront(storefront_id)
		_set_status("\u95e8\u9762 %s\uff1a\u6240\u5c5e\u533a\u5757 %s\uff0c\u5360\u7528 %d \u683c\uff0c\u4e34\u8857 %s" % [storefront.name, storefront.block_id, storefront.grid_cells.size(), storefront.road_segment_id])
		return


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
	storefront_awareness_radius_input.text = str(MapAuthoringDocument.get_default_storefront_awareness_radius(selected_grid_cells.size()))
	_set_status("已选择 %d 个非道路网格。" % selected_grid_cells.size())


func _selection_offset() -> Vector2i:
	return Vector2i(selection_offset_x_input.text.to_int(), selection_offset_y_input.text.to_int())


func _on_move_selected_cells_pressed() -> void:
	if selected_grid_cells.is_empty():
		return
	var moved: Array[Vector2i] = []
	for cell in selected_grid_cells:
		var target := cell + _selection_offset()
		if document.road_cells.has(target):
			_set_status("\u79fb\u52a8\u53d6\u6d88\uff1a\u6846\u9009\u7f51\u683c\u4e0e\u9053\u8def\u91cd\u53e0\u3002")
			return
		moved.append(target)
	selected_grid_cells = moved
	map_canvas.set_selected_grid_cells(selected_grid_cells)


func _on_copy_selected_cells_pressed() -> void:
	if selected_grid_cells.is_empty():
		return
	var additions: Array[Vector2i] = []
	for cell in selected_grid_cells:
		var target := cell + _selection_offset()
		if not document.road_cells.has(target) and not selected_grid_cells.has(target):
			additions.append(target)
	selected_grid_cells.append_array(additions)
	map_canvas.set_selected_grid_cells(selected_grid_cells)


func _on_delete_selected_cells_pressed() -> void:
	if selected_grid_cells.is_empty():
		return
	if not selected_block_id.is_empty():
		document.remove_cells_from_block(selected_block_id, selected_grid_cells)
		map_canvas.refresh_canvas()
	selected_grid_cells.clear()
	map_canvas.set_selected_grid_cells(selected_grid_cells)


func _on_selection_cleared() -> void:
	selected_grid_cells.clear()
	selected_block_id = ""
	selected_storefront_id = ""
	_set_editor_visibility(false, false)
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
	_set_editor_visibility(true, false)
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
		block_accessibility_input.text = str(block.accessibility)
		block_development_input.text = str(block.development_factor)
		block_price_input.text = str(block.spending_profile.get("price_sensitivity", 0.5))
		block_quality_input.text = str(block.spending_profile.get("quality_preference", 0.5))
		block_time_input.text = "%s,%s,%s,%s" % [block.active_time_profile.get("morning", 1.0), block.active_time_profile.get("noon", 1.0), block.active_time_profile.get("evening", 1.0), block.active_time_profile.get("night", 1.0)]
		block_tags_input.text = ",".join(block.tags)
		_select_option_text(block_competition_option, str(block.competition_profile.get("competition_level", "medium")))
		_select_option_text(block_rent_pressure_option, str(block.competition_profile.get("rent_pressure", "medium")))
		_set_status("已选中区块：" + block.id)
		return


func _set_editor_visibility(show_block: bool, show_storefront: bool) -> void:
	block_editor_row.visible = show_block
	block_simulation_row.visible = show_block
	block_link_row.visible = show_block
	storefront_link_row.visible = show_storefront
	storefront_editor_row.visible = show_storefront


func _on_update_block_simulation_pressed() -> void:
	var periods := block_time_input.text.split(",", false)
	if selected_block_id.is_empty() or periods.size() != 4:
		_set_status("\u8bf7\u9009\u4e2d\u533a\u5757\uff0c\u5e76\u586b\u5199 4 \u4e2a\u9017\u53f7\u5206\u9694\u7684\u65f6\u6bb5\u7cfb\u6570\u3002")
		return
	var tags: Array[String] = []
	for tag in block_tags_input.text.split(",", false):
		tags.append(tag.strip_edges())
	var profile := {"morning": periods[0].to_float(), "noon": periods[1].to_float(), "evening": periods[2].to_float(), "night": periods[3].to_float()}
	if document.update_block_simulation_properties(selected_block_id, block_accessibility_input.text.to_float(), block_development_input.text.to_float(), block_price_input.text.to_float(), block_quality_input.text.to_float(), profile, block_competition_option.get_item_text(block_competition_option.selected), block_rent_pressure_option.get_item_text(block_rent_pressure_option.selected), tags):
		_set_status("\u533a\u5757\u7ecf\u8425\u5c5e\u6027\u5df2\u66f4\u65b0\u3002")


func _select_option_text(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if option.get_item_text(index) == value:
			option.select(index)
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
	_on_storefront_selected(storefront_id)
	map_canvas.refresh_canvas()
	_set_status("\u5df2\u5c06\u7f51\u683c\u52a0\u5165\u9009\u4e2d\u95e8\u9762\u3002")


func _on_merge_blocks_pressed() -> void:
	var merged := false
	for target_id in block_merge_target_input.text.split(",", false):
		merged = document.merge_blocks(selected_block_id, target_id.strip_edges()) or merged
	if merged:
		_refresh_options()
		_on_grid_block_selected(selected_block_id)
		map_canvas.refresh_canvas()
		_set_status("\u5df2\u5408\u5e76\u76f8\u90bb\u533a\u5757\u3002")
	else:
		_set_status("\u533a\u5757\u5408\u5e76\u5931\u8d25\uff1a\u9700\u4e3a\u540c\u57ce\u5e02\u533a\u57df\u4e14\u7f51\u683c\u76f8\u90bb\u3002")


func _on_merge_storefronts_pressed() -> void:
	var primary_id := _selected_id(storefront_option)
	var merged := false
	for target_id in storefront_merge_target_input.text.split(",", false):
		merged = document.merge_storefronts(primary_id, target_id.strip_edges()) or merged
	if merged:
		_refresh_options()
		_on_storefront_selected(primary_id)
		map_canvas.refresh_canvas()
		_set_status("\u5df2\u5408\u5e76\u76f8\u90bb\u95e8\u9762\u3002")
	else:
		_set_status("\u95e8\u9762\u5408\u5e76\u5931\u8d25\uff1a\u9700\u4e3a\u540c\u533a\u5757\u4e14\u7f51\u683c\u76f8\u90bb\u3002")


func _on_create_storefront_pressed() -> void:
	var storefront := document.create_storefront_from_cells(storefront_id_input.text.strip_edges(), storefront_name_input.text.strip_edges(), block_region_input.text.strip_edges(), selected_grid_cells)
	if storefront == null:
		_set_status("\u65e0\u6cd5\u521b\u5efa\u95e8\u9762\uff1a\u8bf7\u4f7f\u7528\u540c\u4e00\u533a\u5757\u5185\u7684\u8fde\u901a\u7f51\u683c\u3002")
		return
	document.update_storefront_properties(storefront.id, storefront.name, storefront_rent_input.text.to_float(), maxf(0.1, storefront_area_input.text.to_float()), 20, "", storefront.awareness_radius, maxf(0.0, storefront_awareness_exposure_input.text.to_float()), storefront.footprint_area)
	selected_grid_cells.clear()
	map_canvas.set_selected_grid_cells(selected_grid_cells)
	_refresh_options()
	_on_storefront_selected(storefront.id)
	map_canvas.refresh_canvas()


func _on_update_storefront_pressed() -> void:
	var storefront_id := _selected_id(storefront_option)
	if document.update_storefront_properties(storefront_id, storefront_name_input.text, storefront_rent_input.text.to_float(), maxf(0.1, storefront_area_input.text.to_float()), 20, "", maxf(0.0, storefront_awareness_radius_input.text.to_float()), maxf(0.0, storefront_awareness_exposure_input.text.to_float()), storefront_footprint_input.text.to_float()):
		_refresh_options()
		map_canvas.refresh_canvas()


func _on_delete_storefront_pressed() -> void:
	if document.remove_storefront(_selected_id(storefront_option)):
		_refresh_options()
		map_canvas.refresh_canvas()


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
