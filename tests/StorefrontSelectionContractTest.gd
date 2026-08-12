extends Node

var passed: int = 0
var failed: int = 0

func _ready() -> void:
	print("========== Storefront Selection 契约测试开始 ==========")

	_test_selection_requires_full_diligence()
	_test_selection_records_active_store()
	_test_selection_respects_storefront_occupation()

	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [passed, failed])
	if failed == 0:
		print("🎉 Storefront Selection 契约全部通过")
	else:
		print("⚠ Storefront Selection 契约存在失败")


func _new_character_and_store(store_name: String) -> Store:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()

	var character_result: Dictionary = GameManager.create_character({
		"player_name": "Storefront Selection 测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_assert_true(bool(character_result.get("success", false)), "创建角色应成功")
	if not bool(character_result.get("success", false)):
		return null

	var store_result: Dictionary = GameManager.create_new_store(store_name)
	_assert_true(bool(store_result.get("success", false)), "创建Store应成功")
	if not bool(store_result.get("success", false)):
		return null

	var region_result: Dictionary = GameManager.select_region("A001")
	_assert_true(bool(region_result.get("success", false)), "选择A001区域应成功")
	if not bool(region_result.get("success", false)):
		return null

	return GameManager.get_active_store()


func _test_selection_requires_full_diligence() -> void:
	print("\n── 1. 选址必须经过完整尽调 ──")
	var store := _new_character_and_store("选址契约首店")
	if store == null:
		return

	var initial_result: Dictionary = GameManager.select_storefront("S004")
	_assert_true(not bool(initial_result.get("success", false)),
		"未发现/未尽调门面不得直接选定")

	var initial_viewing_result: Dictionary = GameManager.advance_storefront_diligence(
		"S004", "initial_viewing"
	)
	_assert_true(bool(initial_viewing_result.get("success", false)),
		"S004进入initial_viewing应成功")

	var viewed_result: Dictionary = GameManager.select_storefront("S004")
	_assert_true(not bool(viewed_result.get("success", false)),
		"仅initial_viewing仍不得选定门面")
	_assert_true(str(viewed_result.get("reason", "")).contains("完整尽调"),
		"仅初步看铺时应明确提示先完成完整尽调")

	var full_result: Dictionary = GameManager.advance_storefront_diligence(
		"S004", "full_diligence"
	)
	_assert_true(bool(full_result.get("success", false)),
		"S004完成full_diligence应成功")

	var selected_result: Dictionary = GameManager.select_storefront("S004")
	_assert_true(bool(selected_result.get("success", false)),
		"full_diligence后应允许选定S004")


func _test_selection_records_active_store() -> void:
	print("\n── 2. 选址必须写入当前激活Store ──")
	var store := _new_character_and_store("选址契约当前店")
	if store == null:
		return

	GameManager.advance_storefront_diligence("S004", "initial_viewing")
	GameManager.advance_storefront_diligence("S004", "full_diligence")
	var result: Dictionary = GameManager.select_storefront("S004")

	_assert_true(bool(result.get("success", false)), "当前Store选定S004应成功")
	_assert_true(store.selected_storefront_id == "S004",
		"选定门面后应写入当前Store.selected_storefront_id")
	_assert_true(GameManager.store_state == store,
		"选址完成后store_state仍应指向当前激活Store")


func _test_selection_respects_storefront_occupation() -> void:
	print("\n── 3. 多Store不得占用同一门面 ──")
	var first_store := _new_character_and_store("选址契约首店")
	if first_store == null:
		return

	GameManager.advance_storefront_diligence("S004", "initial_viewing")
	GameManager.advance_storefront_diligence("S004", "full_diligence")
	var first_selection: Dictionary = GameManager.select_storefront("S004")
	_assert_true(bool(first_selection.get("success", false)), "首店选定S004应成功")

	var second_result: Dictionary = GameManager.create_new_store("选址契约分店")
	_assert_true(bool(second_result.get("success", false)), "创建第二个Store应成功")
	if not bool(second_result.get("success", false)):
		return

	var second_region: Dictionary = GameManager.select_region("A001")
	_assert_true(bool(second_region.get("success", false)), "第二店选择A001应成功")

	var occupied_result: Dictionary = GameManager.select_storefront("S004")
	_assert_true(not bool(occupied_result.get("success", false)),
		"第二Store不得选定已被首店占用的S004")
	_assert_true(str(occupied_result.get("reason", "")).contains("占用"),
		"重复选址失败原因应明确指出门面已被占用")
	_assert_true(first_store.selected_storefront_id == "S004",
		"拒绝第二Store选址后首店的S004选择不得被污染")


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("✅ " + message)
	else:
		failed += 1
		print("❌ " + message)
