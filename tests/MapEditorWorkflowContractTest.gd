extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	_test_diagonal_road_coverage()
	var document := MapAuthoringDocument.new()
	_assert(document.add_grid_road("road", Vector2i(5, 5), Vector2i(15, 5), "alley"), "road can be authored")
	var cells: Array[Vector2i] = [Vector2i(7, 6), Vector2i(8, 6), Vector2i(7, 7), Vector2i(8, 7)]
	var block := document.create_block_from_cells("block", "Block", "CR001", cells, "commercial", 2)
	_assert(block != null, "block can be authored beside a road")
	var profile := {"morning": 0.8, "noon": 1.3, "evening": 1.1, "night": 0.4}
	var tags: Array[String] = ["office", "lunch"]
	_assert(document.update_block_simulation_properties("block", 0.9, 1.2, 0.35, 0.8, profile, "high", "high", tags), "block simulation properties can be edited")
	_assert(is_equal_approx(block.accessibility, 0.9) and block.competition_profile.get("competition_level", "") == "high" and block.active_time_profile.get("noon", 0.0) == 1.3, "block property panel data updates the simulation source")
	var storefront_cells: Array[Vector2i] = [Vector2i(7, 6)]
	var storefront := document.create_storefront_from_cells("storefront", "Storefront", "CR001", storefront_cells)
	_assert(storefront != null, "storefront can be authored inside a block")
	_assert(document.update_storefront_properties("storefront", "Updated", 1.2, 24, 32, "test"), "storefront business properties can be edited")
	var exported := document.export_map_data()
	var imported: Dictionary = MapAuthoringDocument.from_exported_map_data(exported)
	_assert(bool(imported.get("success", false)), "exported map passes import preview validation")
	var imported_document: MapAuthoringDocument = imported.get("document", null)
	var imported_storefront: StorefrontData = imported_document._get_storefront("storefront") if imported_document != null else null
	_assert(imported_storefront != null and imported_storefront.monthly_rent_wan == 1.2 and imported_storefront.area == 24 and imported_storefront.hourly_capacity_base == 32, "storefront data survives export and import")
	print("========== Map Editor Workflow Test: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _test_diagonal_road_coverage() -> void:
	var document := MapAuthoringDocument.new()
	_assert(document.add_grid_road("diagonal", Vector2i(0, 0), Vector2i(4, 2), "alley"), "diagonal road can be authored")
	_assert(document.road_cells.has(Vector2i(1, 0)) and document.road_cells.has(Vector2i(3, 1)), "diagonal road occupies every crossed grid cell")
	_assert(document.road_cells.has(Vector2i(1, 1)), "diagonal road occupies a cell touched at an interior grid corner")
	_assert(not document.road_cells.has(Vector2i(4, 2)), "diagonal road does not paint cells beyond its endpoint")
	var straight_document := MapAuthoringDocument.new()
	_assert(straight_document.add_grid_road("straight", Vector2i(0, 0), Vector2i(4, 0), "local"), "wide straight road can be authored")
	_assert(not straight_document.road_cells.has(Vector2i(4, 0)) and not straight_document.road_cells.has(Vector2i(4, -1)), "wide straight road has no endpoint overrun")

func _assert(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)
