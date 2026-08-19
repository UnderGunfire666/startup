extends Node

var passed := 0
var failed := 0


func _ready() -> void:
	var parser := JSON.new()
	_assert(parser.parse(FileAccess.get_file_as_string("res://data/concept_city_grid_map.json")) == OK and parser.data is Dictionary, "reference map JSON parses")
	if not parser.data is Dictionary:
		get_tree().quit(1)
		return
	var source: Dictionary = parser.data
	var imported: Dictionary = MapAuthoringDocument.from_exported_map_data(source)
	_assert(bool(imported.get("success", false)), "reference map JSON passes map validation")
	var document: MapAuthoringDocument = imported.get("document", null)
	if document == null:
		get_tree().quit(1)
		return
	_assert(document.road_graph.segments.size() >= 10, "reference map contains a multi-level road network")
	_assert(document.blocks.size() >= 15, "reference map contains the coloured district layout")
	_assert(document.storefronts.size() >= 10, "reference map contains storefront footprints")
	_assert(_has_block_type(document, "residential") and _has_block_type(document, "commercial") and _has_block_type(document, "office"), "reference map contains the main colour categories")
	_assert(_has_block_type(document, "industrial") and _has_block_type(document, "mixed") and _has_block_type(document, "tourism") and _has_block_type(document, "public_green"), "reference map contains every supplied colour category")
	print("========== Reference City Map Test: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _has_block_type(document: MapAuthoringDocument, block_type: String) -> bool:
	for block in document.blocks:
		if block.block_type == block_type:
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)
