extends Node
## 首店垂直切片 + 双店隔离回归测试。
##
## 目标：从“有角色但无企划”开始，完整验证：
## 角色 → 创建企划 → 调查区 → 区域调研 → 发现门面 → 深度勘验
## → 选定门面 → 配置品类 → 备货 → 开业 → 营业结算 → 第二家店。
##
## 运行方式：打开 res://tests/VerticalSliceTest.tscn 后按 F6。
## 该测试只使用当前项目已经存在的公开业务 API；时间推进使用
## TimeManager._advance() 作为测试用的确定性时钟推进入口，不修改正式游戏入口。

var _pass_count: int = 0
var _fail_count: int = 0

var _store1_id: String = ""
var _store2_id: String = ""


func _ready() -> void:
	print("========== 首店垂直切片测试开始 ==========")

	_test_new_game_and_first_store()
	_test_spatial_research_and_diligence()
	_test_first_store_open_and_settlement()
	_test_second_store_and_isolation()

	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("🎉 垂直切片通过：角色→首店→空间调研→开业→结算→第二店")
	else:
		print("⚠ 有 %d 项失败，请先修复后再继续扩玩法" % _fail_count)

	GameManager.start_new_game()
	TimeManager.reset()
	ScheduleManager.reset_for_new_game()


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("✅ %s" % label)
	else:
		_fail_count += 1
		print("❌ %s" % label)


func _test_new_game_and_first_store() -> void:
	print("\n── 1. 角色与首个开店企划 ──")

	GameManager.start_new_game()
	TimeManager.reset()
	ScheduleManager.reset_for_new_game()

	_check(GameManager.player_state.is_character_created == false,
		"新游戏开始时应没有角色")
	_check(GameManager.stores.is_empty(),
		"新游戏开始时不应存在任何Store")

	var character_result: Dictionary = GameManager.create_character({
		"player_name": "垂直切片测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": ["energetic"],
	})
	_check(bool(character_result.get("success", false)),
		"create_character() 应成功：%s" % str(character_result.get("reason", "")))
	_check(GameManager.player_state.is_character_created,
		"角色创建后 player_state.is_character_created 应为 true")
	_check(GameManager.stores.is_empty(),
		"角色创建后仍不应自动创建Store（玩家与企划必须分离）")
	_check(GameManager.active_store_id.is_empty(),
		"角色创建后 active_store_id 应为空")
	_check(GameManager.store_state == null,
		"角色创建后无企划时 store_state 应为 null")

	var store_result: Dictionary = GameManager.create_new_store("垂直切片首店")
	_check(bool(store_result.get("success", false)),
		"create_new_store() 应成功：%s" % str(store_result.get("reason", "")))

	_store1_id = str(store_result.get("store_id", ""))
	_check(not _store1_id.is_empty(), "首个Store应获得唯一ID")
	_check(GameManager.stores.size() == 1, "创建首个企划后玩家名下应有1个Store")
	_check(GameManager.active_store_id == _store1_id, "新建企划后应自动激活该Store")
	_check(GameManager.store_state != null and GameManager.store_state.id == _store1_id,
		"store_state 兼容入口应指向当前激活Store")

	var region_result: Dictionary = GameManager.select_region("A001")
	_check(bool(region_result.get("success", false)),
		"首店选择A001应成功：%s" % str(region_result.get("reason", "")))


func _test_spatial_research_and_diligence() -> void:
	print("\n── 2. 空间调研→发现门面→深度勘验 ──")

	## S004 位于 CR001 的中央实验小学区块；调查区覆盖该区块。
	var survey_result: Dictionary = GameManager.create_survey_area(
		"CR001", Vector2(125.0, 110.0), 180.0
	)
	_check(bool(survey_result.get("success", false)),
		"创建CR001调查区应成功：%s" % str(survey_result.get("reason", "")))

	var survey_area_id: String = str(survey_result.get("survey_area_id", ""))
	_check(not survey_area_id.is_empty(), "调查区应获得唯一ID")
	_check(GameManager.get_blocks_for_survey_area(survey_area_id).size() > 0,
		"调查区应至少覆盖一个Block")

	var research_result: Dictionary = ScheduleManager.start_action_now(
		"region_research", survey_area_id
	)
	_check(bool(research_result.get("can", false)),
		"8:00开始区域调研应允许执行：%s" % str(research_result.get("reason", "")))
	_check(ScheduleManager.current_action != null,
		"开始区域调研后应存在current_action")

	## region_research 时长为2小时；从8:00推进到10:00，验证行动完成和了解度效果。
	TimeManager._advance(7200.0)

	_check(ScheduleManager.current_action == null,
		"区域调研满2小时后current_action应结束")
	_check(GameManager.get_block_understanding("cc_primary_school_1") > 0.0,
		"区域调研应实际增加覆盖区块的了解度")
	_check(GameManager.get_storefront_diligence("S004") == "initial_viewing",
		"中央实验小学区块达到发现阈值后S004应自动进入initial_viewing")

	var diligence_result: Dictionary = ScheduleManager.start_action_now(
		"deep_inspection", "S004"
	)
	_check(bool(diligence_result.get("can", false)),
		"S004进入initial_viewing后应允许开始深度勘验：%s" % str(diligence_result.get("reason", "")))

	## 深度勘验时长3小时：10:00→13:00。
	TimeManager._advance(10800.0)

	_check(ScheduleManager.current_action == null,
		"深度勘验满3小时后current_action应结束")
	_check(GameManager.get_storefront_diligence("S004") == "full_diligence",
		"深度勘验完成后S004应进入full_diligence")

	var select_storefront_result: Dictionary = GameManager.select_storefront("S004")
	_check(bool(select_storefront_result.get("success", false)),
		"完成深度勘验后应能把S004落实到当前企划：%s" % str(select_storefront_result.get("reason", "")))

	var store1: Store = GameManager.get_store(_store1_id)
	_check(store1 != null and store1.selected_storefront_id == "S004",
		"首店selected_storefront_id应记录S004")


func _test_first_store_open_and_settlement() -> void:
	print("\n── 3. 首店配置→备货→开业→结算 ──")

	var category_result: Dictionary = GameManager.add_category_to_store("breakfast", ["P001"])
	_check(bool(category_result.get("success", false)),
		"首店添加breakfast品类应成功：%s" % str(category_result.get("reason", "")))

	var purchase_result: Dictionary = GameManager.purchase_ingredients({
		"soybean": 5.0,
		"flour": 5.0,
		"oil": 2.0,
	})
	_check(bool(purchase_result.get("success", false)),
		"首店采购原料应成功：%s" % str(purchase_result.get("reason", "")))

	var readiness: Dictionary = GameManager.get_open_readiness()
	_check(bool(readiness.get("can_open", false)),
		"完成选址+品类+备货后首店应满足开业条件")

	var open_result: Dictionary = GameManager.open_store()
	_check(bool(open_result.get("success", false)),
		"首店开业应成功：%s" % str(open_result.get("reason", "")))

	var store1: Store = GameManager.get_store(_store1_id)
	_check(store1 != null and store1.is_open, "首店开业后is_open应为true")
	_check(GameManager.get_open_stores().size() == 1, "首店开业后应有且仅有1家营业店")

	## 深度勘验把时钟推进到了13:00；重置到8:00后测试真实营业时段。
	TimeManager.reset()
	GameManager.begin_slot_simulation()
	_check(GameManager.active_simulations.size() == 1,
		"8:00首店营业时段内应创建1条active_simulations")

	var results: Array = []
	if not GameManager.active_simulations.is_empty():
		GameManager.advance_slot_simulation(3600.0)
		results = GameManager.finalize_slot_simulation()

	_check(not results.is_empty(), "首店营业1小时后应产生结算结果")
	_check(GameManager.active_simulations.is_empty(),
		"首店结算完成后active_simulations应清空")
	_check(store1 != null and not store1.daily_history.is_empty(),
		"首店结算后应写入daily_history")
	_check(store1 != null and store1.total_orders >= 0,
		"首店结算后total_orders应保持合法非负值")


func _test_second_store_and_isolation() -> void:
	print("\n── 4. 第二家店与多店隔离 ──")

	var second_result: Dictionary = GameManager.create_new_store("垂直切片分店")
	_check(bool(second_result.get("success", false)),
		"创建第二家店应成功：%s" % str(second_result.get("reason", "")))

	_store2_id = str(second_result.get("store_id", ""))
	_check(not _store2_id.is_empty() and _store2_id != _store1_id,
		"第二家店应拥有不同于首店的唯一ID")
	_check(GameManager.stores.size() == 2, "此时玩家名下应有2个Store")
	_check(GameManager.active_store_id == _store2_id, "创建第二家店后active_store_id应切到第二家店")

	var store1: Store = GameManager.get_store(_store1_id)
	var store2: Store = GameManager.get_store(_store2_id)

	_check(store1 != null and store1.is_open, "切到第二家店后首店仍应保持营业")
	_check(store2 != null and not store2.is_open, "新建第二家店初始应为筹备中")
	_check(store2 != null and store2.category_slots.is_empty(), "第二家店不应继承首店品类")
	_check(store2 != null and is_zero_approx(store2.get_ingredient_stock("soybean")),
		"第二家店不应继承首店soybean库存")

	var region_result: Dictionary = GameManager.select_region("A002")
	_check(bool(region_result.get("success", false)),
		"第二店选择A002应成功：%s" % str(region_result.get("reason", "")))

	var storefront_result: Dictionary = GameManager.select_storefront("S001")
	_check(bool(storefront_result.get("success", false)),
		"第二店选择未占用的S001应成功：%s" % str(storefront_result.get("reason", "")))

	var category_result: Dictionary = GameManager.add_category_to_store("breakfast", ["P001"])
	_check(bool(category_result.get("success", false)),
		"第二店添加breakfast品类应成功：%s" % str(category_result.get("reason", "")))

	var purchase_result: Dictionary = GameManager.purchase_ingredients({
		"soybean": 5.0,
		"flour": 5.0,
		"oil": 2.0,
	})
	_check(bool(purchase_result.get("success", false)),
		"第二店采购原料应成功：%s" % str(purchase_result.get("reason", "")))

	var open_result: Dictionary = GameManager.open_store()
	_check(bool(open_result.get("success", false)),
		"第二店开业应成功：%s" % str(open_result.get("reason", "")))
	_check(GameManager.get_open_stores().size() == 2, "第二店开业后应有2家营业店")

	## 验证两家店库存独立。
	if store1 != null and store2 != null:
		var store1_soybean_before: float = store1.get_ingredient_stock("soybean")
		var store2_soybean_before: float = store2.get_ingredient_stock("soybean")
		store1.set_ingredient_stock("soybean", 999.0)
		_check(not is_equal_approx(store2.get_ingredient_stock("soybean"), 999.0),
			"修改首店库存不应影响第二店库存")
		store1.set_ingredient_stock("soybean", store1_soybean_before)
		_check(is_equal_approx(store2.get_ingredient_stock("soybean"), store2_soybean_before),
			"恢复首店库存后第二店库存仍应保持原值")

	## 两家店同时营业时，结算入口必须遍历全部营业店。
	TimeManager.reset()
	GameManager.begin_slot_simulation()

	var seen_store_ids: Dictionary = {}
	for entry in GameManager.active_simulations:
		seen_store_ids[str(entry.get("store_id", ""))] = true

	_check(seen_store_ids.has(_store1_id) and seen_store_ids.has(_store2_id),
		"双店营业时active_simulations应同时包含两家Store")

	GameManager.advance_slot_simulation(3600.0)
	var results: Array = GameManager.finalize_slot_simulation()
	_check(results.size() >= 2, "双店营业1小时后结算结果至少应包含两家Store")
	_check(store1 != null and not store1.daily_history.is_empty(), "首店仍应持续产生自己的daily_history")
	_check(store2 != null and not store2.daily_history.is_empty(), "第二店应产生自己的daily_history")

	var switch_result: Dictionary = GameManager.switch_active_store(_store1_id)
	_check(bool(switch_result.get("success", false)), "切回首店应成功")
	_check(GameManager.active_store_id == _store1_id and GameManager.store_state == store1,
		"切回首店后active_store与store_state应指向首店")
