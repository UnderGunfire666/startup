extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var created := GameManager.create_character({"player_name":"Grid Tester", "gender":"female", "age":28, "difficulty_id":"normal", "preset_id":"", "home_id":"home_old_community", "trait_ids":[]})
	_expect(bool(created.get("success", false)), "character creation succeeds")
	var grid := GameManager.get_navigation_grid()
	_expect(MapDataValidator.validate(GameManager.road_graph, GameManager.all_blocks, GameManager.all_storefronts).is_empty(), "authored map validates")
	for block in GameManager.all_blocks:
		_expect(not block.internal_road_cells.is_empty(), "%s has explicit internal roads" % block.id)
		for cell in block.internal_road_cells:
			_expect(grid.internal_cells.has(cell), "%s road is navigable" % block.id)
	_expect(not grid.walkable_cells.has(Vector2i(17, 15)), "ordinary block cells are not legacy walkable fallback")
	_expect(grid.walkable_cells.has(GameManager.player_state.current_map_cell), "home is normalized onto a navigable cell")
	var legacy := BlockData.new()
	legacy.id = "legacy_without_lanes"
	legacy.road_entry_node_id = "n_10_08"
	legacy.grid_cells = [Vector2i(11, 9)]
	var legacy_blocks: Array[BlockData] = [legacy]
	var legacy_errors := MapDataValidator.validate(GameManager.road_graph, legacy_blocks, [])
	_expect(legacy_errors.has("block legacy_without_lanes has no internal roads"), "missing internal roads are rejected by validation")
	_finish()

func _expect(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		print("FAIL: " + label)

func _finish() -> void:
	print("Player movement: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
