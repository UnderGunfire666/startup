extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	_test_in_memory_graph()
	_test_loaded_road_data()
	_test_map_reference_validation()
	_test_runtime_map_links()
	_test_static_map_links()
	_test_map_authoring_report()
	_test_map_canvas_road_preview()
	_test_map_authoring_document()
	_test_road_based_movement_duration()
	print("========== Road Graph Test: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func _test_in_memory_graph() -> void:
	var graph := RoadGraph.new()
	var node_a := RoadNode.new()
	node_a.id = "a"
	node_a.position = Vector2(0, 0)
	var node_b := RoadNode.new()
	node_b.id = "b"
	node_b.position = Vector2(3, 0)
	var node_c := RoadNode.new()
	node_c.id = "c"
	node_c.position = Vector2(3, 4)
	_assert(graph.add_node(node_a), "road node is accepted once")
	_assert(graph.add_node(node_b), "second road node is accepted")
	_assert(graph.add_node(node_c), "third road node is accepted")
	_assert(not graph.add_node(RoadNode.new()), "invalid road node is rejected")
	var segment_ab := RoadSegment.new()
	segment_ab.id = "ab"
	segment_ab.from_node_id = "a"
	segment_ab.to_node_id = "b"
	var segment_bc := RoadSegment.new()
	segment_bc.id = "bc"
	segment_bc.from_node_id = "b"
	segment_bc.to_node_id = "c"
	_assert(graph.add_segment(segment_ab), "first valid segment is accepted")
	_assert(graph.add_segment(segment_bc), "second valid segment is accepted")
	_assert(is_equal_approx(graph.get_shortest_distance("a", "c"), 7.0), "shortest road distance follows connected segments")
	_assert(is_inf(graph.get_shortest_distance("a", "missing")), "missing road endpoint has no path")
	_assert(graph.validate().is_empty(), "valid road graph passes validation")

func _test_loaded_road_data() -> void:
	var graph := GameData.get_road_graph()
	_assert(graph.nodes.size() == 16 and graph.segments.size() == 14, "road data loads all configured nodes and segments")
	_assert(is_equal_approx(graph.get_shortest_distance("road_cc_1", "road_cc_3"), 666.6604), "loaded road graph computes its configured shortest path")
	_assert(graph.validate().is_empty(), "loaded road data passes graph validation")

func _test_map_reference_validation() -> void:
	var graph := RoadGraph.new()
	var a := RoadNode.new()
	a.id = "a"
	var b := RoadNode.new()
	b.id = "b"
	b.position = Vector2(1, 0)
	graph.add_node(a)
	graph.add_node(b)
	var segment := RoadSegment.new()
	segment.id = "ab"
	segment.from_node_id = "a"
	segment.to_node_id = "b"
	graph.add_segment(segment)
	var block := BlockData.new()
	block.id = "block_ok"
	block.road_entry_node_id = "a"
	var storefront := StorefrontData.new()
	storefront.id = "storefront_ok"
	storefront.road_segment_id = "ab"
	var blocks: Array[BlockData] = [block]
	var storefronts: Array[StorefrontData] = [storefront]
	_assert(MapDataValidator.validate(graph, blocks, storefronts).is_empty(), "valid block and storefront road references pass validation")
	block.road_entry_node_id = "missing"
	storefront.road_segment_id = "missing"
	var errors := MapDataValidator.validate(graph, blocks, storefronts)
	_assert(errors.size() == 2, "validator reports both missing block entry and storefront segment")

func _test_runtime_map_links() -> void:
	var errors := MapDataValidator.validate(GameManager.road_graph, GameManager.all_blocks, GameManager.all_storefronts)
	_assert(errors.is_empty(), "runtime map road links validate for all current blocks and storefronts")

func _test_static_map_links() -> void:
	_assert(MapDataValidator.validate(GameData.get_road_graph(), GameData.get_blocks(), GameData.get_storefronts()).is_empty(), "all current static map road links validate without runtime fallback")


func _test_map_authoring_report() -> void:
	var graph := GameData.get_road_graph()
	var blocks := GameData.get_blocks()
	var storefronts := GameData.get_storefronts()
	var report := MapDataValidator.build_report(graph, blocks, storefronts)
	_assert(bool(report.get("is_valid", false)), "map authoring report marks the configured data as valid")
	_assert(int(report.get("node_count", 0)) == graph.nodes.size() and int(report.get("storefront_count", 0)) == storefronts.size(), "map authoring report exposes editable-data counts")
	var source_segment: RoadSegment = graph.segments[0]
	var duplicate_segment := RoadSegment.new()
	duplicate_segment.id = source_segment.id
	duplicate_segment.from_node_id = source_segment.from_node_id
	duplicate_segment.to_node_id = source_segment.to_node_id
	graph.segments.append(duplicate_segment)
	_assert(not bool(MapDataValidator.build_report(graph, blocks, storefronts).get("is_valid", true)), "map authoring report detects duplicate road segment IDs")


func _test_map_canvas_road_preview() -> void:
	var canvas := CityMapCanvas.new()
	canvas.setup(GameManager.all_city_regions, GameManager.all_blocks, GameManager.road_graph)
	_assert(canvas.road_graph == GameManager.road_graph, "map canvas receives the runtime road graph for visual preview")
	_assert(canvas.road_graph.segments.size() == GameManager.road_graph.segments.size(), "map canvas preview retains every configured road segment")


func _test_map_authoring_document() -> void:
	var document := MapAuthoringDocument.from_static_data()
	_assert(document.validate().is_empty(), "authoring document starts as a valid independent map copy")
	_assert(document.add_road_node("authoring_node", Vector2(20, 20)), "authoring document can add a road node")
	_assert(document.move_road_node("authoring_node", Vector2(30, 20)), "authoring document can move a road node")
	_assert(document.add_road_segment("authoring_segment", "authoring_node", "road_cc_1"), "authoring document can add a road segment")
	_assert(not document.add_road_segment("authoring_segment", "authoring_node", "road_cc_1"), "authoring document rejects duplicate road segment IDs")
	_assert(document.assign_block_road_entry("cc_primary_school_1", "authoring_node"), "authoring document can update a block road entry")
	_assert(document.assign_storefront_nearest_road("S006"), "authoring document can assign a storefront to its nearest road")
	_assert(GameData.get_blocks()[0].road_entry_node_id != "authoring_node", "authoring document does not mutate the static map data")
	var export_data := document.export_roads_data()
	var exported_roads: Array = export_data.get("roads", [])
	_assert(bool(export_data.get("success", false)) and exported_roads.size() == document.road_graph.nodes.size() + document.road_graph.segments.size(), "valid authoring document exports roads in the static-data format")
	var map_export := document.export_map_data()
	var exported_blocks: Array = map_export.get("blocks", [])
	var exported_storefronts: Array = map_export.get("storefronts", [])
	_assert(bool(map_export.get("success", false)) and exported_blocks.size() == document.blocks.size() and exported_storefronts.size() == document.storefronts.size(), "valid authoring document exports roads blocks and storefronts together")
	document.blocks[0].road_entry_node_id = "missing_authoring_node"
	_assert(not bool(document.export_roads_data().get("success", true)), "invalid authoring document cannot export road data")

func _test_road_based_movement_duration() -> void:
	var from_block := BlockData.new()
	from_block.id = "from"
	from_block.center_position = Vector2(0, 0)
	from_block.road_entry_node_id = "a"
	var to_block := BlockData.new()
	to_block.id = "to"
	to_block.center_position = Vector2(10, 0)
	to_block.road_entry_node_id = "c"
	var graph := RoadGraph.new()
	var positions: Dictionary = {"a": Vector2(0, 0), "b": Vector2(0, 10), "c": Vector2(10, 10)}
	for id in ["a", "b", "c"]:
		var node := RoadNode.new()
		node.id = str(id)
		node.position = positions[id] as Vector2
		graph.add_node(node)
	for edge in [["ab", "a", "b"], ["bc", "b", "c"]]:
		var segment := RoadSegment.new()
		segment.id = str(edge[0])
		segment.from_node_id = str(edge[1])
		segment.to_node_id = str(edge[2])
		graph.add_segment(segment)
	_assert(is_equal_approx(MovementConfig.get_travel_hours(from_block, to_block, graph), 0.2), "movement uses road shortest path instead of straight-line distance")

func _assert(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)
