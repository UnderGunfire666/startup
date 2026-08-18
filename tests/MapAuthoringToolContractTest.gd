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
	_assert(panel.map_canvas.move_node_to_map("tool_node", Vector2(90, 90)), "authoring canvas moves a road node in the independent document")
	var moved_node: RoadNode = panel.document.road_graph.nodes.get("tool_node", null)
	_assert(moved_node != null and moved_node.position == Vector2(90, 90), "authoring canvas stores the dragged node position")
	_assert(panel.map_canvas.move_storefront_to_map("S006", Vector2(700, 260)), "authoring canvas moves a storefront and finds a nearby road")
	var moved_storefront := panel.document._get_storefront("S006")
	_assert(moved_storefront != null and moved_storefront.map_position == Vector2(700, 260) and not moved_storefront.road_segment_id.is_empty(), "authoring canvas persists storefront position and road association")
	var moved_block := panel.document.blocks[0]
	var original_size := moved_block.map_bounds.size
	_assert(panel.map_canvas.move_block_to_map(moved_block.id, Vector2(220, 180)), "authoring canvas moves a block in the independent document")
	_assert(moved_block.center_position == Vector2(220, 180) and moved_block.map_bounds.size == original_size, "authoring canvas moves the block bounds without resizing it")
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
