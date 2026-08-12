extends Node

var passed: int = 0
var failed: int = 0

func _ready() -> void:
	print("========== Action Target 契约测试开始 ==========")
	GameManager.start_new_game()
	TimeManager.reset_for_new_game()
	ScheduleManager.reset_for_new_game()

	_test_action_target_definitions()
	_test_region_research_is_player_level()
	_test_deep_inspection_requires_initial_viewing()
	_test_store_actions_require_store()
	_test_store_supervision_target_is_store_id()

	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [passed, failed])
	if failed == 0:
		print("🎉 Action Target 契约全部通过")
	else:
		print("⚠ Action Target 契约存在失败")


func _test_action_target_definitions() -> void:
	var region_action := ScheduleActionData.get_action("region_research")
	var deep_action := ScheduleActionData.get_action("deep_inspection")
	var supervision_action := ScheduleActionData.get_action("store_supervision")
	var procurement_action := ScheduleActionData.get_action("procurement")

	_assert_true(region_action != null, "region_research 应存在")
	_assert_true(deep_action != null, "deep_inspection 应存在")
	_assert_true(supervision_action != null, "store_supervision 应存在")
	_assert_true(procurement_action != null, "procurement 应存在")

	if region_action != null:
		_assert_true(region_action.action_effect_type == "region_research", "region_research target 应解释为调查区")
	if deep_action != null:
		_assert_true(deep_action.action_effect_type == "deep_inspection", "deep_inspection target 应解释为门面")
		_assert_true(deep_action.requires_inspected_storefront, "deep_inspection 应要求已初步看铺门面")
	if supervision_action != null:
		_assert_true(supervision_action.action_effect_type == "store_supervision", "store_supervision target 应解释为Store")
	if procurement_action != null:
		_assert_true(procurement_action.requires_open_store, "procurement 应要求营业Store")


func _test_region_research_is_player_level() -> void:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var character_result: Dictionary = GameManager.create_character({
		"player_name": "Action Target 测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_assert_true(bool(character_result.get("success", false)), "创建角色应成功")
	
	var survey_result := GameManager.create_survey_area("A001", Vector2(500, 500), 300.0)
	_assert_true(survey_result.success, "创建调查区应成功")
	if not survey_result.success:
		return

	var survey_area_id: String = survey_result.survey_area_id
	var check := ScheduleManager.can_schedule_action("region_research", 8, survey_area_id)
	_assert_true(check.can, "region_research 不应要求Store")
	_assert_true(GameManager.stores.is_empty(), "region_research 测试期间不应偷偷创建Store")


func _test_deep_inspection_requires_initial_viewing() -> void:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var character_result: Dictionary = GameManager.create_character({
		"player_name": "Deep Inspection 测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_assert_true(bool(character_result.get("success", false)), "深度勘验测试角色创建应成功")

	var not_viewed_check := ScheduleManager.can_schedule_action("deep_inspection", 9, "S004")
	_assert_true(not not_viewed_check.can, "未进入initial_viewing的门面不得开始deep_inspection")
	_assert_true(not_viewed_check.reason_code == "storefront_not_inspected", "未初步看铺应返回storefront_not_inspected")

	GameManager.player_state.storefront_diligence["S004"] = "initial_viewing"
	var viewed_check := ScheduleManager.can_schedule_action("deep_inspection", 9, "S004")
	_assert_true(viewed_check.can, "initial_viewing门面应允许开始deep_inspection")


func _test_store_actions_require_store() -> void:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var character_result: Dictionary = GameManager.create_character({
		"player_name": "Store Target 测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_assert_true(bool(character_result.get("success", false)), "Store行动测试角色创建应成功")

	var procurement_check := ScheduleManager.can_schedule_action("procurement", 9, "missing-store")
	_assert_true(not procurement_check.can, "procurement 无有效Store时不得执行")
	_assert_true(procurement_check.reason_code == "no_store", "procurement 无Store应返回no_store")


func _test_store_supervision_target_is_store_id() -> void:
	var action := ScheduleActionData.get_action("store_supervision")
	_assert_true(action != null, "store_supervision定义应存在")
	if action != null:
		_assert_true(action.requires_open_store, "store_supervision 应要求营业Store")
		_assert_true(action.requires_store_operating_hour, "store_supervision 应要求营业时段")


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("✅ " + message)
	else:
		failed += 1
		print("❌ " + message)
