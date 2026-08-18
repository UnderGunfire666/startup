extends Node

var passed := 0
var failed := 0


func _ready() -> void:
	var document := MapAuthoringDocument.new()
	_assert(document.add_grid_road("test_alley", Vector2i(0, 0), Vector2i(12, 0), "alley"), "test road is created")
	var block_cells: Array[Vector2i] = [Vector2i(2, 1), Vector2i(3, 1)]
	var block := document.create_block_from_cells("test_block", "Test Block", "TEST_REGION", block_cells, "commercial", 1)
	_assert(block != null, "test block can be placed beside a road")
	if block == null:
		_finish()
		return

	var storefront := StorefrontData.new()
	storefront.id = "test_storefront"
	storefront.city_region_id = "TEST_REGION"
	storefront.map_position = document.grid_to_world_center(Vector2i(2, 1))
	document.storefronts.append(storefront)
	document.assign_storefront_nearest_road(storefront.id)
	_assert(document._storefront_is_inside_any_block(storefront), "test storefront starts inside its block")

	var original_position: Vector2 = storefront.map_position
	var original_local_position: Vector2 = storefront.map_position - block.center_position
	# Moving one cell away from the road requires the document to snap the block back.
	# The storefront must receive that same final snap offset, not just the preview offset.
	var requested_center: Vector2 = block.center_position + Vector2(0.0, MapAuthoringDocument.GRID_CELL_SIZE)
	_assert(document.move_block(block.id, requested_center), "block move near a road is accepted and snapped")
	_assert(document._storefront_is_inside_any_block(storefront), "storefront remains inside its block after a snapped block move")
	_assert((storefront.map_position - block.center_position).is_equal_approx(original_local_position), "storefront keeps its local position when its block snaps")
	_assert(storefront.map_position.is_equal_approx(original_position), "snap back restores the storefront to the matching map position")
	_assert(document.begin_block_move(block.id), "block drag captures an editable preview state")
	_assert(document.move_block_preview(block.id, requested_center), "block can be previewed away from its legal final position")
	_assert(not storefront.map_position.is_equal_approx(original_position), "storefront follows the block during drag preview")
	document.cancel_block_move(block.id)
	_assert(storefront.map_position.is_equal_approx(original_position), "cancelling a block drag restores the storefront and block together")

	var invalid_target := document.grid_to_world_center(Vector2i(10, 5))
	_assert(not document.move_storefront(storefront.id, invalid_target), "storefront cannot be moved outside every block")
	_assert(storefront.map_position.is_equal_approx(original_position), "illegal storefront move restores its previous map position")

	var exported: Dictionary = document.export_map_data()
	var exported_storefronts: Array = exported.get("storefronts", [])
	var storefront_entry: Dictionary = exported_storefronts[0] if not exported_storefronts.is_empty() else {}
	_assert(storefront_entry.has("block_id"), "storefront export records its containing block id")
	_assert(storefront_entry.has("block_local_position"), "storefront export records its position relative to the containing block")
	_finish()


func _assert(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)


func _finish() -> void:
	print("========== Map Block / Storefront Contract Test: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
