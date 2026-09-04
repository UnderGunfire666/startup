extends Node

var passed := 0
var failed := 0


func _ready() -> void:
	var panel: MapAuthoringPanel = preload("res://scenes/tools/MapAuthoringPanel.tscn").instantiate()
	add_child(panel)
	await get_tree().process_frame
	var initial_errors := panel.document.validate()
	if not initial_errors.is_empty():
		print("Map authoring validation errors: %s" % [initial_errors])
	_assert(initial_errors.is_empty(), "authoring tool loads a valid independent document")
	panel.node_id_input.text = "tool_node"
	panel.node_x_input.text = "60"
	panel.node_y_input.text = "60"
	panel._on_add_node_pressed()
	_assert(panel.document.road_graph.nodes.has("tool_node"), "authoring tool adds a node through its UI command")
	_assert(panel.document.add_road_segment("delete_test_segment", "tool_node", "n_10_08"), "test road can be attached to a node before deletion")
	panel.node_id_input.text = "tool_node"
	panel._on_delete_node_pressed()
	_assert(not panel.document.road_graph.nodes.has("tool_node") and not panel.document._has_road_segment("delete_test_segment"), "delete-node button removes its attached road segments")
	panel.node_id_input.text = "tool_node"
	panel._on_add_node_pressed()
	_assert(panel.map_canvas.move_node_to_map("tool_node", Vector2(90, 90)), "authoring canvas moves a road node in the independent document")
	var moved_node: RoadNode = panel.document.road_graph.nodes.get("tool_node", null)
	_assert(moved_node != null and moved_node.position == panel.document.snap_world_to_grid_intersection(Vector2(90, 90)), "authoring canvas snaps dragged road nodes to grid intersections")
	var moved_storefront := panel.document._get_storefront("sf_nw_grocery")
	var original_storefront_position := moved_storefront.map_position
	var original_storefront_cells := moved_storefront.grid_cells.duplicate()
	var original_storefront_segment := moved_storefront.road_segment_id
	var invalid_storefront_target := Vector2(52.5, 50.75)
	_assert(not panel.map_canvas.move_storefront_to_map("sf_nw_grocery", invalid_storefront_target), "authoring canvas rejects a storefront move that disconnects its entrance")
	_assert(moved_storefront.map_position == original_storefront_position and moved_storefront.grid_cells == original_storefront_cells and moved_storefront.road_segment_id == original_storefront_segment, "rejected storefront movement restores position, cells, and road association")
	var moved_block := panel.document.blocks[0]
	var original_size := moved_block.map_bounds.size
	var original_cell_count := moved_block.grid_cells.size()
	var original_block_cell := moved_block.grid_cells[0]
	var original_internal_road := moved_block.internal_road_cells[0]
	var moved_home: Dictionary = panel.document._get_player_home("home_old_community")
	var original_home_cell: Vector2i = moved_home.get("grid_cells", [Vector2i.ZERO])[0]
	var original_home_entrance: Vector2i = moved_home.get("entrance_cell", Vector2i.ZERO)
	_assert(panel.map_canvas.move_block_to_map(moved_block.id, Vector2(220, 180)), "authoring canvas moves a block in the independent document")
	_assert(not moved_block.grid_cells.is_empty() and moved_block.grid_cells.size() == original_cell_count and moved_block.map_bounds.size == original_size, "polygon blocks preserve their selected cells and bounds when moved")
	var block_cell_offset := moved_block.grid_cells[0] - original_block_cell
	_assert(moved_block.internal_road_cells[0] == original_internal_road + block_cell_offset, "moving a block keeps its internal-road cells aligned")
	_assert((moved_home.get("grid_cells", []) as Array)[0] == original_home_cell + block_cell_offset and moved_home.get("entrance_cell", Vector2i.ZERO) == original_home_entrance + block_cell_offset, "moving a block keeps its home cells and entrance aligned")
	panel.map_canvas.set_zoom(2.0)
	_assert(is_equal_approx(panel.map_canvas.grid_screen_size, 32.0), "authoring canvas supports grid zoom")
	_assert(panel.document.add_grid_road("grid_test_road", Vector2i(200, 200), Vector2i(210, 200), "secondary"), "grid editor creates a road from two clicked grid nodes")
	_assert(not panel.document.road_cells.is_empty(), "grid road occupies editable map cells")
	_assert(panel.document.set_road_class("grid_test_road", "arterial") and panel.document.get_road_class("grid_test_road") == "arterial", "selected road class can be changed and retained")
	var reuse_document := MapAuthoringDocument.new()
	_assert(reuse_document.add_grid_road("reuse_first", Vector2i(0, 0), Vector2i(4, 0), "local"), "grid road creates its initial endpoints")
	_assert(reuse_document.add_grid_road("reuse_branch", Vector2i(0, 0), Vector2i(0, 4), "local") and reuse_document.road_graph.nodes.size() == 3, "new road from an existing node reuses that node instead of duplicating it")
	var extension_document := MapAuthoringDocument.new()
	_assert(extension_document.add_grid_road("extend_first", Vector2i(0, 0), Vector2i(4, 0), "local"), "extension test creates an initial road")
	_assert(extension_document.add_grid_road("extend_unused", Vector2i(4, 0), Vector2i(8, 0), "local") and extension_document.road_graph.nodes.size() == 2 and extension_document.road_graph.segments.size() == 1, "straight extension moves the endpoint without creating a third node or segment")
	_assert(not extension_document.add_grid_road("covered_duplicate", Vector2i(0, 0), Vector2i(8, 0), "local") and extension_document.road_graph.nodes.size() == 2 and extension_document.road_graph.segments.size() == 1, "fully covered road path does not create duplicate nodes or segments")
	var polygon_cells: Array[Vector2i] = [Vector2i(202, 203), Vector2i(203, 203), Vector2i(202, 204)]
	var polygon := panel.document.create_block_from_cells("grid_polygon", "Grid Polygon", "CR001", polygon_cells, "commercial", 2)
	_assert(polygon != null and polygon.grid_cells.size() == 3, "grid editor creates a non-rectangular polygon block from selected cells")
	if polygon != null:
		polygon.internal_road_cells = [Vector2i(202, 203)]
		_assert(polygon.has_map_point(panel.document.grid_to_world_center(Vector2i(202, 203))) and not polygon.has_map_point(panel.document.grid_to_world_center(Vector2i(203, 204))), "polygon block hit testing follows selected cells instead of its bounding rectangle")
		var road_overlap := panel.document.create_block_from_cells("invalid_road_overlap", "Invalid", "CR001", [Vector2i(205, 200)], "commercial", 1)
		_assert(road_overlap == null, "polygon blocks cannot include road-occupied cells")
	var edited_errors := panel.document.validate()
	if not edited_errors.is_empty():
		print("Map authoring edited-document errors: %s" % [edited_errors])
	panel._on_validate_pressed()
	_assert(panel.status_label.text.contains("\u901a\u8fc7"), "authoring tool reports successful validation")
	panel._on_export_pressed()
	_assert(not panel.export_text.text.is_empty() and panel.export_text.text.contains("roads"), "authoring tool produces a JSON export preview")
	var export_files := panel.document.export_json_files()
	var files: Dictionary = export_files.get("files", {})
	_assert(bool(export_files.get("success", false)) and files.has("roads.json") and files.has("blocks.json") and files.has("storefronts.json") and files.has("player_homes.json"), "authoring tool prepares all four JSON files before user-selected save")
	_test_canvas_selection_interactions(panel)
	_test_storefront_competition_radius_round_trip(panel)
	_test_four_file_round_trip(panel)
	_test_player_home_editing(panel)
	_test_internal_road_atomic_rejection(panel)
	_test_export_directory(panel)
	_test_document_lifecycle_commands(panel)
	panel.queue_free()
	await get_tree().process_frame
	print("========== Map Authoring Tool Test: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)


func _click_canvas(canvas: MapAuthoringCanvas, screen_position: Vector2, pressed: bool, button_index: MouseButton = MOUSE_BUTTON_LEFT, ctrl_pressed: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.position = screen_position
	event.ctrl_pressed = ctrl_pressed
	canvas._gui_input(event)


func _drag_canvas(canvas: MapAuthoringCanvas, from_screen_position: Vector2, to_screen_position: Vector2) -> void:
	_click_canvas(canvas, from_screen_position, true)
	var motion := InputEventMouseMotion.new()
	motion.position = to_screen_position
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(motion)
	_click_canvas(canvas, to_screen_position, false)


func _test_canvas_selection_interactions(panel: MapAuthoringPanel) -> void:
	var canvas := panel.map_canvas
	var storefront := panel.document._get_storefront("sf_nw_grocery")
	_assert(storefront != null, "selection test has a storefront target")
	if storefront == null:
		return
	var storefront_screen := storefront.map_position / MapAuthoringDocument.GRID_CELL_SIZE * canvas.grid_screen_size
	_click_canvas(canvas, storefront_screen, true)
	_click_canvas(canvas, storefront_screen, false)
	_assert(panel.selected_storefront_id == storefront.id and canvas.selected_storefront_ids.size() == 1 and canvas.selected_storefront_ids[0] == storefront.id, "clicking a storefront updates the panel and typed canvas highlight selection")
	_drag_canvas(canvas, storefront_screen, storefront_screen)
	_assert(canvas._dragging_storefront_id.is_empty(), "storefront drag interaction completes without leaving canvas drag state")
	var second: StorefrontData = null
	for candidate in panel.document.storefronts:
		if candidate.id != storefront.id:
			second = candidate
			break
	if second != null:
		var second_screen := second.map_position / MapAuthoringDocument.GRID_CELL_SIZE * canvas.grid_screen_size
		_click_canvas(canvas, second_screen, true, MOUSE_BUTTON_LEFT, true)
		_click_canvas(canvas, second_screen, false, MOUSE_BUTTON_LEFT, true)
		_assert(canvas.selected_storefront_ids.has(storefront.id) and canvas.selected_storefront_ids.has(second.id), "Ctrl-click adds a second storefront selection")
	_click_canvas(canvas, storefront_screen, true, MOUSE_BUTTON_RIGHT)
	_assert(canvas.selected_storefront_id.is_empty() and canvas.selected_storefront_ids.is_empty() and panel.selected_storefront_id.is_empty(), "right-click clears storefront selection in canvas and panel")
	var block := panel.document.blocks[0]
	var block_screen := block.center_position / MapAuthoringDocument.GRID_CELL_SIZE * canvas.grid_screen_size
	_click_canvas(canvas, block_screen, true)
	_click_canvas(canvas, block_screen, false)
	_assert(canvas.selected_block_ids.has(block.id) and panel.selected_block_id == block.id, "clicking a block updates block selection")
	if not panel.document.player_homes.is_empty():
		var home: Dictionary = panel.document.player_homes[0]
		var home_cell: Vector2i = (home.get("grid_cells", []) as Array)[0]
		var home_screen := (Vector2(home_cell) + Vector2(0.5, 0.5)) * canvas.grid_screen_size
		_click_canvas(canvas, home_screen, true)
		_assert(panel.selected_home_id == str(home.get("id", "")) and panel.selected_block_id.is_empty() and panel.selected_storefront_id.is_empty() and canvas.selected_block_ids.is_empty() and canvas.selected_storefront_ids.is_empty(), "home selection is mutually exclusive with block and storefront selection")
		_click_canvas(canvas, home_screen, false)
	var original_block_center := block.center_position
	_click_canvas(canvas, block_screen, true)
	var preview_motion := InputEventMouseMotion.new()
	preview_motion.position = block_screen + Vector2(canvas.grid_screen_size, 0.0)
	preview_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(preview_motion)
	_click_canvas(canvas, block_screen, true, MOUSE_BUTTON_RIGHT)
	_assert(canvas._dragging_block_id.is_empty() and block.center_position == original_block_center, "right-click cancels an active block drag")


func _test_storefront_competition_radius_round_trip(panel: MapAuthoringPanel) -> void:
	var storefront := panel.document._get_storefront("sf_nw_grocery")
	_assert(storefront != null, "competition-radius test has a storefront target")
	if storefront == null:
		return
	panel._on_storefront_selected(storefront.id)
	panel.storefront_awareness_radius_input.text = "45"
	panel.storefront_competition_radius_input.text = "70"
	panel.storefront_awareness_exposure_input.text = "1.25"
	panel._on_update_storefront_pressed()
	_assert(is_equal_approx(storefront.awareness_radius, 45.0) and is_equal_approx(storefront.competition_radius, 70.0) and is_equal_approx(storefront.awareness_exposure_modifier, 1.25), "storefront editor saves separate awareness, competition, and exposure values")
	var exported := panel.document.export_map_data()
	var restored_result := MapAuthoringDocument.from_exported_map_data(exported)
	var restored: MapAuthoringDocument = restored_result.get("document", null)
	var restored_storefront := restored._get_storefront(storefront.id) if restored != null else null
	_assert(bool(restored_result.get("success", false)) and restored_storefront != null and is_equal_approx(restored_storefront.competition_radius, 70.0), "competition radius survives map export and import")
	var legacy_export: Dictionary = exported.duplicate(true)
	var legacy_storefronts: Array = legacy_export.get("storefronts", [])
	for legacy_entry in legacy_storefronts:
		if legacy_entry is Dictionary and str(legacy_entry.get("id", "")) == storefront.id:
			legacy_entry.erase("competition_radius")
			break
	var legacy_result := MapAuthoringDocument.from_exported_map_data(legacy_export)
	var legacy_document: MapAuthoringDocument = legacy_result.get("document", null)
	var legacy_storefront := legacy_document._get_storefront(storefront.id) if legacy_document != null else null
	_assert(bool(legacy_result.get("success", false)) and legacy_storefront != null and is_equal_approx(legacy_storefront.competition_radius, legacy_storefront.awareness_radius), "legacy storefront maps default competition radius to awareness radius")


func _test_four_file_round_trip(_panel: MapAuthoringPanel) -> void:
	var formal_map := MapAuthoringDocument.from_static_data()
	var first := formal_map.export_json_files()
	var restored := MapAuthoringDocument.from_json_file_contents(first.get("files", {}))
	var restored_document: MapAuthoringDocument = restored.get("document", null)
	var second := restored_document.export_json_files() if restored_document != null else {}
	_assert(bool(first.get("success", false)) and bool(restored.get("success", false)) and bool(second.get("success", false)), "four exported map JSON files reload through the canonical validator")
	_assert(first.get("files", {}) == second.get("files", {}), "four-file export is byte-stable after reload and preserves every serialized field")


func _test_player_home_editing(panel: MapAuthoringPanel) -> void:
	var previous_document := panel.document
	var document := MapAuthoringDocument.new()
	var block := BlockData.new()
	block.id = "home_contract_block"
	block.name = "Home Contract Block"
	block.city_region_id = "TEST"
	for x in range(4):
		for y in range(6):
			block.grid_cells.append(Vector2i(x, y))
	for y in range(6):
		block.internal_road_cells.append(Vector2i(0, y))
	block.rebuild_bounds_from_grid_cells()
	document.blocks.append(block)
	panel.document = document
	panel.map_canvas.setup(document)
	var candidate: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2)]
	var candidate_move_direction := Vector2i.DOWN
	var created := document.create_player_home("contract_home", "Contract Home", candidate)
	_assert(not created.is_empty(), "authoring document creates a connected multi-cell home with an automatic entrance")
	if created.is_empty():
		panel.document = previous_document
		panel.map_canvas.setup(previous_document)
		return
	var home := document._get_player_home("contract_home")
	var original := (home.get("grid_cells", []) as Array).duplicate()
	_assert(not document.move_player_home("contract_home", Vector2(-1000, -1000)) and home.get("grid_cells", []) == original, "invalid home movement rolls back atomically")
	var target := document._grid_cells_center(home.get("grid_cells", [])) + Vector2(candidate_move_direction) * MapAuthoringDocument.GRID_CELL_SIZE
	var moved_successfully: bool = panel.map_canvas.move_player_home_to_map("contract_home", target) and home.get("grid_cells", []) != original
	_assert(moved_successfully, "authoring canvas commits a valid independent home drag and recalculates its entrance")
	candidate.assign(home.get("grid_cells", []))
	var entrance: Vector2i = home.get("entrance_cell", Vector2i(-1, -1))
	var keep_cell: Vector2i = candidate[0] if candidate[0].distance_squared_to(entrance) == 1 else candidate[1]
	var remove_cell: Vector2i = candidate[1] if keep_cell == candidate[0] else candidate[0]
	_assert(document.remove_cells_from_player_home("contract_home", [remove_cell]) and (home.get("grid_cells", []) as Array).size() == 1, "home footprint can be reduced while preserving a valid entrance")
	var remaining := (home.get("grid_cells", []) as Array).duplicate()
	_assert(not document.remove_cells_from_player_home("contract_home", remaining) and home.get("grid_cells", []) == remaining, "home reduction rejects deleting the complete footprint without mutation")
	_assert(document.remove_player_home("contract_home"), "home can be deleted after move and resize validation")
	panel.document = previous_document
	panel.map_canvas.setup(previous_document)


func _test_internal_road_atomic_rejection(panel: MapAuthoringPanel) -> void:
	var restored := MapAuthoringDocument.from_exported_map_data(panel.document.export_map_data())
	var document: MapAuthoringDocument = restored.get("document", null)
	var rejected := false
	if document != null:
		for home in document.player_homes:
			var block: BlockData = document._get_block(str(home.get("block_id", "")))
			var entrance: Vector2i = home.get("entrance_cell", Vector2i(-1, -1))
			if block == null or not block.internal_road_cells.has(entrance): continue
			var before := block.internal_road_cells.duplicate()
			var proposed := before.duplicate()
			proposed.erase(entrance)
			if not proposed.is_empty() and not document.set_internal_road_cells(block.id, proposed):
				rejected = block.internal_road_cells == before and home.get("entrance_cell", Vector2i(-1, -1)) == entrance
				break
	_assert(rejected, "removing an internal-road cell required by a home or storefront is rejected with complete rollback")


func _test_export_directory(panel: MapAuthoringPanel) -> void:
	var directory := "user://map_authoring_contract_export"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var exported := panel.document.export_json_files()
	panel.pending_export_files = exported.get("files", {})
	panel._on_export_directory_selected(directory)
	_assert(FileAccess.file_exists(directory.path_join("roads.json")) and FileAccess.file_exists(directory.path_join("blocks.json")) and FileAccess.file_exists(directory.path_join("storefronts.json")) and FileAccess.file_exists(directory.path_join("player_homes.json")), "authoring tool writes all four JSON exports to the selected directory")


func _test_document_lifecycle_commands(panel: MapAuthoringPanel) -> void:
	panel._on_load_reference_map_pressed()
	_assert(not panel.document.blocks.is_empty() and not panel.document.storefronts.is_empty(), "load-reference command provides an authored document")
	panel._on_export_pressed()
	var preview := panel.export_text.text
	panel.selected_home_id = "stale_home"
	panel.selected_block_id = "stale_block"
	panel.selected_storefront_id = "stale_storefront"
	panel.map_canvas.selected_home_id = "stale_home"
	panel.map_canvas.selected_block_ids = ["stale_block"]
	panel.map_canvas.selected_storefront_ids = ["stale_storefront"]
	panel._on_import_preview_pressed()
	_assert(not preview.is_empty() and panel.status_label.text.contains("通过"), "import-preview command restores a validated exported document")
	_assert(panel.selected_home_id.is_empty() and panel.selected_block_id.is_empty() and panel.selected_storefront_id.is_empty(), "successful import clears stale panel selections")
	_assert(panel.map_canvas.selected_home_id.is_empty() and panel.map_canvas.selected_block_ids.is_empty() and panel.map_canvas.selected_storefront_ids.is_empty(), "successful import clears stale canvas selections")
	panel._on_new_blank_map_pressed()
	_assert(panel.document.blocks.is_empty() and panel.document.storefronts.is_empty() and panel.document.road_graph.nodes.is_empty(), "new-blank-map command resets all editable map content")
