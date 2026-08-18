extends Node

var passed := 0
var failed := 0


func _ready() -> void:
	var document := MapAuthoringDocument.new()
	_assert(document.add_grid_road("test_road", Vector2i(0, 0), Vector2i(12, 0), "alley"), "test road is created")
	var block_cells: Array[Vector2i] = []
	for x in range(1, 7):
		for y in range(1, 5):
			block_cells.append(Vector2i(x, y))
	var block := document.create_block_from_cells("test_block", "Test Block", "TEST_REGION", block_cells, "commercial", 1)
	_assert(block != null, "test block is created beside the road")
	if block == null:
		_finish()
		return

	var first_cells: Array[Vector2i] = [Vector2i(2, 2)]
	var first := document.create_storefront_from_cells("first", "First", "TEST_REGION", first_cells)
	_assert(first != null and first.grid_cells.size() == 1, "a storefront occupies at least one grid cell")
	var overlap_block_cells: Array[Vector2i] = [Vector2i(2, 2)]
	_assert(document.create_block_from_cells("overlap_block", "Overlap", "TEST_REGION", overlap_block_cells, "commercial", 1) == null, "different blocks cannot overlap any grid cell")

	var connected_cells: Array[Vector2i] = [Vector2i(3, 2), Vector2i(3, 3)]
	_assert(document.add_cells_to_storefront("first", connected_cells), "connected selected cells inside the block can be added to a storefront")
	_assert(first != null and first.grid_cells.size() == 3, "storefront records every occupied grid cell")
	var disconnected_cells: Array[Vector2i] = [Vector2i(6, 4)]
	_assert(not document.add_cells_to_storefront("first", disconnected_cells), "disconnected cells cannot be added to a storefront")

	var second_cells: Array[Vector2i] = [Vector2i(4, 2)]
	var second := document.create_storefront_from_cells("second", "Second", "TEST_REGION", second_cells)
	_assert(second != null, "a second non-overlapping storefront can be created")
	var overlap_storefront_cells: Array[Vector2i] = [Vector2i(4, 2)]
	_assert(not document.add_cells_to_storefront("first", overlap_storefront_cells), "storefronts cannot overlap occupied grid cells")

	var outside_cells: Array[Vector2i] = [Vector2i(8, 2)]
	_assert(document.create_storefront_from_cells("outside", "Outside", "TEST_REGION", outside_cells) == null, "a storefront must be fully contained by one block")
	_assert(document.validate().is_empty(), "valid block and storefront footprints pass map validation")
	_finish()


func _assert(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)


func _finish() -> void:
	print("========== Map Storefront Footprint Contract Test: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
