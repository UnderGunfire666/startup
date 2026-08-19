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
	_assert(is_equal_approx(storefront.awareness_radius, 35.0), "one-cell storefront defaults to a ten-cell awareness radius")
	_assert(MapAuthoringDocument.get_required_storefront_cell_count(12.25) == 1 and MapAuthoringDocument.get_required_storefront_cell_count(24.5) == 2 and MapAuthoringDocument.get_required_storefront_cell_count(36.75) == 3, "storefront footprint maps to the required occupied grid-cell count")
	_assert(is_equal_approx(MapAuthoringDocument.get_default_storefront_awareness_radius(2), 42.0) and is_equal_approx(MapAuthoringDocument.get_default_storefront_awareness_radius(3), 49.0), "each extra storefront cell adds two grid cells to awareness radius")
	storefront.awareness_radius = 2.0
	_assert(is_equal_approx(StorefrontInfluenceCalculator.get_block_coverage_ratio(storefront, block), 0.75), "storefront awareness circle reports partial block coverage by grid cell")
	storefront.awareness_radius = 35.0
	_assert(document.update_storefront_properties("storefront", "Updated", 1.2, 10.0, 32, "test", 35.0, 1.25) and storefront.grid_cells.size() == 1, "storefront usable area updates without changing its footprint")
	var exported := document.export_map_data()
	var imported: Dictionary = MapAuthoringDocument.from_exported_map_data(exported)
	_assert(bool(imported.get("success", false)), "exported map passes import preview validation")
	var imported_document: MapAuthoringDocument = imported.get("document", null)
	var imported_storefront: StorefrontData = imported_document._get_storefront("storefront") if imported_document != null else null
	_assert(imported_storefront != null and imported_storefront.monthly_rent_wan == 1.2 and imported_storefront.area == 10.0 and imported_storefront.footprint_area == 12.25 and imported_storefront.awareness_radius == 35.0 and imported_storefront.awareness_exposure_modifier == 1.25, "storefront business and awareness data survive export and import")
	var legacy_export: Dictionary = exported.duplicate(true)
	var legacy_storefronts: Array = legacy_export.get("storefronts", [])
	if not legacy_storefronts.is_empty():
		var legacy_storefront: Dictionary = legacy_storefronts[0]
		legacy_storefront["awareness_radius"] = 120.0
		legacy_storefront.erase("awareness_radius_manual_override")
	var legacy_imported: Dictionary = MapAuthoringDocument.from_exported_map_data(legacy_export)
	var legacy_document: MapAuthoringDocument = legacy_imported.get("document", null)
	var migrated_storefront: StorefrontData = legacy_document._get_storefront("storefront") if legacy_document != null else null
	_assert(migrated_storefront != null and migrated_storefront.grid_cells.size() == 1 and is_equal_approx(migrated_storefront.awareness_radius, 35.0), "legacy storefront radius and occupied cells are migrated from its footprint")
	var extra_storefront_cells: Array[Vector2i] = [Vector2i(7, 7)]
	_assert(document.add_cells_to_storefront("storefront", extra_storefront_cells) and storefront.footprint_area == 24.5 and is_equal_approx(storefront.awareness_radius, 42.0), "expanding a storefront keeps footprint, occupied cells, and awareness radius aligned")
	var neighboring_storefront_cells: Array[Vector2i] = [Vector2i(8, 6)]
	var neighboring_storefront := document.create_storefront_from_cells("storefront_b", "Second", "CR001", neighboring_storefront_cells)
	_assert(neighboring_storefront != null and document.merge_storefronts("storefront", "storefront_b") and storefront.grid_cells.size() == 3 and is_equal_approx(storefront.monthly_rent_wan, 2.2), "adjacent storefronts merge names, rent, and occupied cells")
	var neighboring_block_cells: Array[Vector2i] = [Vector2i(9, 6)]
	var neighboring_block := document.create_block_from_cells("block_b", "Second Block", "CR001", neighboring_block_cells, "commercial", 1)
	_assert(neighboring_block != null and document.merge_blocks("block", "block_b") and block.grid_cells.size() == 5, "adjacent blocks merge their grid cells")
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
