extends Node

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	print("========== Store Opening Stage Contract Test ==========")
	_test_opening_stage_transition()
	print("========== Test finished: %d passed / %d failed ==========" % [passed, failed])
	if failed > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_opening_stage_transition() -> void:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()

	var character_result: Dictionary = GameManager.create_character({
		"player_name": "Opening Stage Contract Tester",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_assert_true(bool(character_result.get("success", false)), "character creation succeeds")

	var store_result: Dictionary = GameManager.create_new_store("Opening Stage Contract Store")
	_assert_true(bool(store_result.get("success", false)), "store creation succeeds")
	var store := GameManager.get_active_store()
	if store == null:
		_assert_true(false, "active store exists")
		return

	var storefront: StorefrontData = _find_empty_storefront()
	_assert_true(storefront != null, "an empty storefront is available")
	if storefront == null:
		return
	var storefront_result: Dictionary = GameManager.select_storefront(storefront.id)
	_assert_true(bool(storefront_result.get("success", false)), "storefront selection succeeds")
	_assert_true(store.pre_open_stage == Store.PreOpenStage.STORE_SETUP,
		"storefront selection enters STORE_SETUP")

	var premature_open_result: Dictionary = GameManager.open_store()
	_assert_true(not bool(premature_open_result.get("success", false)),
		"opening fails before configuration and stocking are ready")
	_assert_true(store.pre_open_stage == Store.PreOpenStage.STORE_SETUP,
		"failed opening keeps STORE_SETUP")

	var offer_set := GameManager.set_pending_lease_offer(
		store.id, storefront.id, 1.0, 0, 0.0, "opening_stage_contract"
	)
	_assert_true(offer_set, "lease offer is recorded")
	var signing_result: Dictionary = GameManager.sign_selected_storefront()
	_assert_true(bool(signing_result.get("success", false)), "selected storefront is signed")

	var category_result: Dictionary = GameManager.add_category_to_store("breakfast", ["P001"])
	_assert_true(bool(category_result.get("success", false)), "category setup succeeds")
	var purchase_result: Dictionary = GameManager.purchase_ingredients({
		"soybean": 5.0,
		"flour": 5.0,
		"oil": 2.0,
	})
	_assert_true(bool(purchase_result.get("success", false)), "ingredient purchase succeeds")
	for equipment_id in ["steamer", "griddle"]:
		var equipment_result: Dictionary = GameManager.purchase_equipment(equipment_id)
		_assert_true(bool(equipment_result.get("success", false)), "%s purchase succeeds" % equipment_id)

	var geometry := StorefrontLayoutGeometry.from_storefront(storefront)
	var entrance := StoreFacadePlacement.new()
	entrance.type = "entrance"
	entrance.cell = geometry.get_default_entrance_cell(storefront.default_entrance_offset)
	store.facade_layout = [entrance]
	store.facade_layout_initialized = true
	_assert_true(_place_owned_equipment(store, geometry, entrance),
		"required equipment is placed without blocking the entrance")

	store.pre_open_stage = Store.PreOpenStage.STOREFRONT_SELECTION
	var wrong_stage_open_result: Dictionary = GameManager.open_store()
	_assert_true(not bool(wrong_stage_open_result.get("success", false)),
		"opening rejects ready fields when pre_open_stage is not STORE_SETUP")
	_assert_true(store.pre_open_stage == Store.PreOpenStage.STOREFRONT_SELECTION,
		"rejected wrong-stage opening does not repair or advance pre_open_stage")
	store.pre_open_stage = Store.PreOpenStage.STORE_SETUP

	store.facade_layout.clear()
	var missing_entrance_result: Dictionary = GameManager.open_store()
	_assert_true(not bool(missing_entrance_result.get("success", false)),
		"opening fails after the facade entrance is removed")
	_assert_true(store.pre_open_stage == Store.PreOpenStage.STORE_SETUP,
		"missing entrance failure keeps STORE_SETUP")
	store.facade_layout.append(entrance)

	var open_result: Dictionary = GameManager.open_store()
	_assert_true(bool(open_result.get("success", false)), "opening succeeds when ready")
	_assert_true(store.is_open, "opening sets is_open")
	_assert_true(store.pre_open_stage == Store.PreOpenStage.OPEN_FOR_BUSINESS,
		"successful opening enters OPEN_FOR_BUSINESS")
	var restored_store := Store.from_save_dict(store.to_save_dict())
	_assert_true(restored_store.pre_open_stage == Store.PreOpenStage.OPEN_FOR_BUSINESS,
		"save data restores OPEN_FOR_BUSINESS without field-derived stage inference")

	var repeated_open_result: Dictionary = GameManager.open_store()
	_assert_true(not bool(repeated_open_result.get("success", false)), "already-open store cannot open again")
	_assert_true(store.pre_open_stage == Store.PreOpenStage.OPEN_FOR_BUSINESS,
		"rejected repeated opening keeps OPEN_FOR_BUSINESS")


func _find_empty_storefront() -> StorefrontData:
	for storefront in GameManager.all_storefronts:
		if not storefront.is_occupied:
			return storefront
	return null


func _place_owned_equipment(
		store: Store,
		geometry: StorefrontLayoutGeometry,
		entrance: StoreFacadePlacement
) -> bool:
	var blocked: Dictionary = {}
	for cell in geometry.get_interior_entrance_cells(entrance):
		blocked[cell] = true
	for equipment in store.equipment:
		var definition := GameManager.get_equipment(equipment.equipment_id)
		if definition == null:
			return false
		var footprint := Vector2i.ONE
		if definition.area > 2.5:
			footprint = Vector2i(2, 2)
		elif definition.area > 1.3:
			footprint = Vector2i(2, 1)
		var origin := _find_free_origin(geometry, footprint, blocked)
		if origin.x < 0:
			return false
		var placement := StoreFurniturePlacement.new()
		placement.instance_id = equipment.instance_id
		placement.equipment_id = equipment.equipment_id
		placement.cell = origin
		store.furniture_layout.append(placement)
		for cell in placement.get_footprint_cells(footprint):
			blocked[cell] = true
	return true


func _find_free_origin(
		geometry: StorefrontLayoutGeometry,
		footprint: Vector2i,
		blocked: Dictionary
) -> Vector2i:
	for y in range(geometry.grid_size.y):
		for x in range(geometry.grid_size.x):
			var origin := Vector2i(x, y)
			var valid := true
			for offset_y in range(footprint.y):
				for offset_x in range(footprint.x):
					var cell := origin + Vector2i(offset_x, offset_y)
					if not geometry.is_available(cell) or blocked.has(cell):
						valid = false
						break
				if not valid:
					break
			if valid:
				return origin
	return Vector2i(-1, -1)


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)
