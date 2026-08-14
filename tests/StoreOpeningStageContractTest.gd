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

	GameManager.advance_storefront_diligence("S004", "initial_viewing")
	GameManager.advance_storefront_diligence("S004", "full_diligence")
	var storefront_result: Dictionary = GameManager.select_storefront("S004")
	_assert_true(bool(storefront_result.get("success", false)), "storefront selection succeeds")
	_assert_true(store.pre_open_stage == Store.PreOpenStage.STORE_SETUP,
		"storefront selection enters STORE_SETUP")

	var premature_open_result: Dictionary = GameManager.open_store()
	_assert_true(not bool(premature_open_result.get("success", false)),
		"opening fails before configuration and stocking are ready")
	_assert_true(store.pre_open_stage == Store.PreOpenStage.STORE_SETUP,
		"failed opening keeps STORE_SETUP")

	var category_result: Dictionary = GameManager.add_category_to_store("breakfast", ["P001"])
	_assert_true(bool(category_result.get("success", false)), "category setup succeeds")
	var purchase_result: Dictionary = GameManager.purchase_ingredients({
		"soybean": 5.0,
		"flour": 5.0,
		"oil": 2.0,
	})
	_assert_true(bool(purchase_result.get("success", false)), "ingredient purchase succeeds")

	store.pre_open_stage = Store.PreOpenStage.STOREFRONT_SELECTION
	var wrong_stage_open_result: Dictionary = GameManager.open_store()
	_assert_true(not bool(wrong_stage_open_result.get("success", false)),
		"opening rejects ready fields when pre_open_stage is not STORE_SETUP")
	_assert_true(store.pre_open_stage == Store.PreOpenStage.STOREFRONT_SELECTION,
		"rejected wrong-stage opening does not repair or advance pre_open_stage")
	store.pre_open_stage = Store.PreOpenStage.STORE_SETUP

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


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)
