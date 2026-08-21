extends Node

var passed := 0
var failed := 0


func _ready() -> void:
	var panel: MapAuthoringPanel = preload("res://scenes/tools/MapAuthoringPanel.tscn").instantiate()
	add_child(panel)
	await get_tree().process_frame
	_assert(panel.document.validate().is_empty(), "authoring tool loads a valid independent document")
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
	var storefront_target := Vector2(52.5, 50.75)
	_assert(panel.map_canvas.move_storefront_to_map("sf_nw_grocery", storefront_target), "authoring canvas moves a storefront and finds a nearby road")
	var moved_storefront := panel.document._get_storefront("sf_nw_grocery")
	_assert(moved_storefront != null and moved_storefront.map_position == storefront_target and not moved_storefront.road_segment_id.is_empty(), "authoring canvas persists storefront position and road association")
	var moved_block := panel.document.blocks[0]
	var original_size := moved_block.map_bounds.size
	var original_cell_count := moved_block.grid_cells.size()
	_assert(panel.map_canvas.move_block_to_map(moved_block.id, Vector2(220, 180)), "authoring canvas moves a block in the independent document")
	_assert(not moved_block.grid_cells.is_empty() and moved_block.grid_cells.size() == original_cell_count and moved_block.map_bounds.size == original_size, "polygon blocks preserve their selected cells and bounds when moved")
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
		_assert(polygon.has_map_point(panel.document.grid_to_world_center(Vector2i(202, 203))) and not polygon.has_map_point(panel.document.grid_to_world_center(Vector2i(203, 204))), "polygon block hit testing follows selected cells instead of its bounding rectangle")
		var road_overlap := panel.document.create_block_from_cells("invalid_road_overlap", "Invalid", "CR001", [Vector2i(205, 200)], "commercial", 1)
		_assert(road_overlap == null, "polygon blocks cannot include road-occupied cells")
	panel._on_validate_pressed()
	_assert(panel.status_label.text.contains("\u901a\u8fc7"), "authoring tool reports successful validation")
	panel._on_export_pressed()
	_assert(not panel.export_text.text.is_empty() and panel.export_text.text.contains("roads"), "authoring tool produces a JSON export preview")
	var export_files := panel.document.export_json_files()
	var files: Dictionary = export_files.get("files", {})
	_assert(bool(export_files.get("success", false)) and files.has("roads.json") and files.has("blocks.json") and files.has("storefronts.json"), "authoring tool prepares all three JSON files before user-selected save")
	print("========== Map Authoring Tool Test: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)
