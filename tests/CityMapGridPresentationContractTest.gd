extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	_test_player_animation_uses_separate_layer()
	var document := MapAuthoringDocument.new()
	_expect(document.add_grid_road("arterial", Vector2i(0, 0), Vector2i(14, 0), "arterial"), "grid presentation creates an arterial road")
	var block_cells: Array[Vector2i] = [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(2, 4), Vector2i(2, 5)]
	var block := document.create_block_from_cells("irregular", "Irregular", "TEST", block_cells, "commercial", 2)
	_expect(block != null, "grid presentation creates an irregular road-adjacent block")
	if block == null:
		_finish()
		return
	var storefront_cells: Array[Vector2i] = [Vector2i(2, 4), Vector2i(2, 5)]
	var storefront := document.create_storefront_from_cells("shape_store", "Shape Store", "TEST", storefront_cells)
	_expect(storefront != null and storefront.grid_cells.size() == 2, "grid presentation creates a multi-cell storefront")
	var canvas := CityMapCanvas.new()
	canvas.setup([], document.blocks, document.road_graph)
	canvas.refresh_storefronts(document.storefronts)
	_expect(canvas.road_cells == MapGridGeometry.build_road_cells(document.road_graph), "game map uses the shared editor road-cell geometry")
	_expect(canvas.road_cells == document.road_cells, "game map road cells exactly match the editor document")
	var arterial_cells := 0
	for cell in canvas.road_cells:
		var data: Dictionary = canvas.road_cells[cell]
		if str(data.get("class", "")) == "arterial":
			arterial_cells += 1
	_expect(arterial_cells > 14, "arterial road occupies a wider grid footprint than its center path")
	var overlaps := false
	for cell in block.grid_cells:
		overlaps = overlaps or canvas.road_cells.has(cell)
	for cell in storefront.grid_cells:
		overlaps = overlaps or canvas.road_cells.has(cell)
	_expect(not overlaps, "game-map road cells do not overlap block or storefront footprint cells")
	var clicked_storefront := {"id": ""}
	canvas.storefront_clicked.connect(func(storefront_id: String): clicked_storefront["id"] = storefront_id)
	_click(canvas, canvas._map_to_screen((Vector2(storefront_cells[1]) + Vector2(0.5, 0.5)) * MapGridGeometry.CELL_SIZE))
	_expect(str(clicked_storefront.get("id", "")) == "shape_store", "clicking any storefront footprint cell emits the storefront event")
	_click(canvas, canvas._map_to_screen((Vector2(3.5, 3.5)) * MapGridGeometry.CELL_SIZE))
	_expect(canvas.selected_block_ids.has("irregular"), "clicking a non-storefront irregular block cell selects its block")
	var labels := canvas.get_storefront_label_layout()
	_expect(labels.size() == 1 and str(labels[0].get("storefront_id", "")) == "shape_store" and not str(labels[0].get("label", "")).is_empty(), "grid storefronts retain their visible label layout")
	canvas.free()
	_finish()


func _test_player_animation_uses_separate_layer() -> void:
	var panel := preload("res://scenes/map/CityMapPanel.tscn").instantiate()
	var canvas: CityMapCanvas = panel.get_node("HBoxContainer/MapScrollContainer/MapCanvas")
	var travel_layer: CityMapTravelLayer = canvas.get_node("TravelLayer")
	_expect(travel_layer != null and travel_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "player animation uses an input-transparent layer separate from the static map")
	panel.free()


func _click(canvas: CityMapCanvas, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	canvas._gui_input(event)


func _expect(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		print("FAIL: " + label)


func _finish() -> void:
	print("========== City Map Grid Presentation Test: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
