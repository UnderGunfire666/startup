extends Node
## 多店重构回归测试 —— 场景运行版。
##
## 用法：
##   1. 新建一个空场景（Ctrl+N），添加一个Node节点作为根节点。
##   2. 把这个脚本挂到那个Node上。
##   3. 保存场景为 res://tests/TestRunner.tscn。
##   4. 打开这个场景后按 F6（"运行当前场景"），不需要改项目的主场景。
##
## 这样运行时Autoload（GameManager/TimeManager/ScheduleManager/SaveManager）
## 会被正常加载，因为F6是"真正运行游戏"，只是临时把这个场景当成入口。
##
## 覆盖范围与上一版完全相同：Store/PlayerState数据层、门面占用校验、
## SettlementEngine结算公式、多店同时结算循环、空间系统、存档读写。

var _pass_count := 0
var _fail_count := 0


func _ready() -> void:
	print("========== 多店重构回归测试开始 ==========")

	_test_group_b_null_safety_before_character()
	_test_group_a_store_data_layer()
	_test_group_c_storefront_occupancy()
	_test_group_d_settlement_engine()
	_test_group_e_multi_store_simulation()
	_test_group_f_spatial_system()
	_test_group_g_save_load()

	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_pass_count, _fail_count])

	if _fail_count == 0:
		print("🎉 全部通过")
	else:
		print("⚠ 有 %d 项失败，请检查上面标❌的行" % _fail_count)

	## 跑完不自动退出，方便你在编辑器输出面板里慢慢看结果。
	## 想自动关闭窗口的话，取消下面这行的注释：
	# get_tree().quit(1 if _fail_count > 0 else 0)


# ── 通用断言辅助 ──────────────────────────────────────────

func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("✅ %s" % label)
	else:
		_fail_count += 1
		print("❌ %s" % label)


func _check_approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	_check(absf(actual - expected) <= tolerance,
		"%s（实际=%.4f，期望≈%.4f±%.4f）" % [label, actual, expected, tolerance])


# ── B组预检：角色创建前的空值防护（必须在A组之前跑） ──

func _test_group_b_null_safety_before_character() -> void:
	print("\n── B. 角色创建前的空值防护 ──")

	GameManager.start_new_game()

	_check(GameManager.store_state == null, "创建角色前 store_state 应为 null")
	_check(GameManager.get_ingredients_in_use().is_empty(),
		"get_ingredients_in_use() 在无店铺时应返回空数组而不崩溃")

	var readiness := GameManager.get_open_readiness()
	_check(readiness.can_open == false, "get_open_readiness() 在无店铺时 can_open 应为 false")

	var open_result := GameManager.open_store()
	_check(open_result.success == false, "open_store() 在无店铺时应失败而不崩溃")

	var purchase_result := GameManager.purchase_ingredients({"flour": 1.0})
	_check(purchase_result.success == false, "purchase_ingredients() 在无店铺时应失败而不崩溃")


# ── A组：Store/PlayerState 数据层 ──

var _store1_id: String = ""
var _store2_id: String = ""

func _test_group_a_store_data_layer() -> void:
	print("\n── A. Store/PlayerState 数据层 ──")

	var create_result := GameManager.create_character({
		"player_name": "测试创业者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": ["energetic"],
	})
	_check(create_result.get("success", false), "create_character() 应成功：%s" % create_result.get("reason", ""))

	_check(GameManager.stores.size() == 1, "创建角色后应自动provision恰好1家店")
	_check(GameManager.active_store_id != "", "active_store_id 应指向刚创建的店")
	_check(GameManager.store_state != null, "store_state 兼容属性应能正确解析出激活店")
	_check(GameManager.player_state.cash == 100000.0, "normal难度初始资金应为100000")

	_store1_id = GameManager.active_store_id

	var r1 := GameManager.select_region("A001")
	_check(r1.get("success", false), "店铺1选区域A001应成功：%s" % r1.get("reason", ""))

	var r2 := GameManager.select_storefront("S003")
	_check(r2.get("success", false), "店铺1选门面S003应成功：%s" % r2.get("reason", ""))

	var r3 := GameManager.add_category_to_store("breakfast", ["P001"])
	_check(r3.get("success", false), "店铺1添加breakfast品类应成功：%s" % r3.get("reason", ""))

	var r4 := GameManager.purchase_ingredients({"soybean": 5.0, "flour": 5.0, "oil": 2.0})
	_check(r4.get("success", false), "店铺1采购原料应成功：%s" % r4.get("reason", ""))

	var readiness1 := GameManager.get_open_readiness()
	_check(readiness1.can_open, "店铺1完成选址+品类+备货后应满足开业条件")

	var open1 := GameManager.open_store()
	_check(open1.get("success", false), "店铺1开业应成功：%s" % open1.get("reason", ""))
	_check(GameManager.get_open_stores().size() == 1, "此时应有且仅有1家店在营业")

	var new_store_result := GameManager.create_new_store("测试分店")
	_check(new_store_result.get("success", false), "create_new_store() 应成功：%s" % new_store_result.get("reason", ""))
	_check(GameManager.stores.size() == 2, "此时玩家名下应有2家店")

	_store2_id = new_store_result.get("store_id", "")
	_check(_store2_id != "" and _store2_id != _store1_id, "店铺2的id应与店铺1不同")
	_check(GameManager.active_store_id == _store2_id, "create_new_store() 后active_store_id应指向新店")

	var store1_check := GameManager.get_store(_store1_id)
	_check(store1_check != null and store1_check.is_open,
		"切换到店铺2之后，店铺1的is_open状态不应被影响")
	_check(store1_check.category_slots.size() == 1,
		"切换到店铺2之后，店铺1的品类配置不应被清空或串改")


# ── C组：门面占用校验（决定②） ──

func _test_group_c_storefront_occupancy() -> void:
	print("\n── C. 门面占用校验 ──")

	var r1 := GameManager.select_region("A001")
	_check(r1.get("success", false), "店铺2选区域A001应成功：%s" % r1.get("reason", ""))

	var occupied_result := GameManager.select_storefront("S003")
	_check(occupied_result.get("success", false) == false,
		"店铺2尝试选已被店铺1占用的S003应失败")
	_check(GameManager.is_storefront_occupied("S003", _store2_id),
		"is_storefront_occupied(S003, 排除店铺2) 应返回true（因为店铺1占着）")
	_check(GameManager.is_storefront_occupied("S003", _store1_id) == false,
		"is_storefront_occupied(S003, 排除店铺1) 应返回false（店铺1自己不算占用自己）")

	var r2 := GameManager.select_region("A002")
	_check(r2.get("success", false), "店铺2改选区域A002应成功：%s" % r2.get("reason", ""))

	var r3 := GameManager.select_storefront("S001")
	_check(r3.get("success", false), "店铺2选门面S001（未被占用）应成功：%s" % r3.get("reason", ""))

	var r4 := GameManager.add_category_to_store("breakfast", ["P001"])
	_check(r4.get("success", false), "店铺2添加breakfast品类应成功：%s" % r4.get("reason", ""))

	var r5 := GameManager.purchase_ingredients({"soybean": 5.0, "flour": 5.0, "oil": 2.0})
	_check(r5.get("success", false), "店铺2采购原料应成功（应计入店铺2独立库存，不影响店铺1）：%s" % r5.get("reason", ""))

	var open2 := GameManager.open_store()
	_check(open2.get("success", false), "店铺2开业应成功：%s" % open2.get("reason", ""))
	_check(GameManager.get_open_stores().size() == 2, "此时应有2家店同时在营业")

	var store1 := GameManager.get_store(_store1_id)
	var store2 := GameManager.get_store(_store2_id)
	_check(store1.get_ingredient_stock("soybean") > 0.0 and store2.get_ingredient_stock("soybean") > 0.0,
		"两家店都应各自有soybean库存")

	store1.set_ingredient_stock("soybean", 999.0)
	_check(store2.get_ingredient_stock("soybean") != 999.0,
		"修改店铺1的库存不应影响店铺2（验证库存数据是独立对象，不是共享引用）")


# ── D组：SettlementEngine 真实字段结算 ──

func _test_group_d_settlement_engine() -> void:
	print("\n── D. SettlementEngine 结算公式 ──")

	var store1 := GameManager.get_store(_store1_id)
	var region := GameManager.get_region("A001")
	var storefront := GameManager.get_storefront("S003")
	var category := GameManager.get_category("breakfast")
	var product := GameManager.get_product("P001")
	var slot := store1.get_slot_by_category("breakfast")

	_check(region != null and storefront != null and category != null and product != null and slot != null,
		"D组测试所需的基础数据对象都应能正常取到（未出现字段名不存在导致的null）")

	var params_open := SettlementEngine.calculate_params(
		region, storefront, category, product, store1, GameManager.player_state,
		7, slot.open_hour_ranges, false)
	_check(params_open.is_open == true, "hour=7应落在breakfast营业时段内，is_open应为true")
	_check(params_open.visitors >= 0, "visitors不应为负数")
	_check(params_open.conversion_rate >= 0.0 and params_open.conversion_rate <= 0.9,
		"conversion_rate应落在[0, 0.9]范围内")
	_check(params_open.slot_capacity > 0, "营业时段内slot_capacity应大于0")

	var params_closed := SettlementEngine.calculate_params(
		region, storefront, category, product, store1, GameManager.player_state,
		15, slot.open_hour_ranges, false)
	_check(params_closed.is_open == false, "hour=15不在breakfast营业时段内，is_open应为false")

	GameManager.player_state.supervising_store_id = ""
	var params_no_supervise := SettlementEngine.calculate_params(
		region, storefront, category, product, store1, GameManager.player_state,
		7, slot.open_hour_ranges, false)

	GameManager.player_state.supervising_store_id = store1.id
	var params_supervise := SettlementEngine.calculate_params(
		region, storefront, category, product, store1, GameManager.player_state,
		7, slot.open_hour_ranges, false)

	_check_approx(
		params_supervise.conversion_rate - params_no_supervise.conversion_rate,
		0.03, 0.001,
		"坐镇加成应让conversion_rate正好提升0.03（且只在supervising_store_id匹配当前店时生效）"
	)

	GameManager.player_state.supervising_store_id = ""

	_check(params_open.rent_cost > 0.0, "rent_cost应基于monthly_rent_wan算出正数（验证未使用已删除的daily_rent字段）")


# ── E组：多店同时结算循环（阶段2） ──

func _test_group_e_multi_store_simulation() -> void:
	print("\n── E. 多店同时结算循环 ──")

	var store1 := GameManager.get_store(_store1_id)
	var store2 := GameManager.get_store(_store2_id)
	var orders_before_1 := store1.total_orders
	var orders_before_2 := store2.total_orders

	GameManager.begin_slot_simulation()
	_check(not GameManager.active_simulations.is_empty(),
		"两家店都在营业时段内时，active_simulations不应为空")

	var seen_store_ids: Dictionary = {}
	for entry in GameManager.active_simulations:
		seen_store_ids[entry.store_id] = true
	_check(seen_store_ids.has(_store1_id) and seen_store_ids.has(_store2_id),
		"active_simulations里应同时包含店铺1和店铺2的模拟条目（验证多店循环真的遍历了所有营业店铺）")

	GameManager.advance_slot_simulation(3600.0)
	var results := GameManager.finalize_slot_simulation()

	_check(not results.is_empty(), "finalize_slot_simulation() 应返回非空结果数组")
	_check(GameManager.active_simulations.is_empty(),
		"finalize后active_simulations应被清空，不残留上一轮数据")

	_check(store1.total_orders >= orders_before_1, "店铺1的total_orders在结算后不应减少")
	_check(store2.total_orders >= orders_before_2, "店铺2的total_orders在结算后不应减少")
	_check(not store1.daily_history.is_empty(), "店铺1应有daily_history记录（结算结果已正确记到店铺而不是丢失）")
	_check(not store2.daily_history.is_empty(), "店铺2应有daily_history记录")

	var store1_days: Dictionary = {}
	for h in store1.daily_history:
		store1_days[h.get("day", -1)] = true
	var current_day := TimeManager.current_day
	_check(store1_days.has(current_day), "店铺1当天的daily_history应包含TimeManager.current_day这一天")

	var s1_summary := store1.get_day_summary(current_day)
	var s2_summary := store2.get_day_summary(current_day)
	var combined := GameManager.get_day_summary_all_stores(current_day)

	_check_approx(combined.revenue, s1_summary.revenue + s2_summary.revenue, 0.01,
		"get_day_summary_all_stores()的revenue应等于两家店revenue之和")
	_check(combined.actual_orders == s1_summary.actual_orders + s2_summary.actual_orders,
		"get_day_summary_all_stores()的actual_orders应等于两家店actual_orders之和")


# ── F组：空间系统（区块了解度 → 门面发现 → 区域情报） ──

func _test_group_f_spatial_system() -> void:
	print("\n── F. 空间系统：区块了解度与门面发现 ──")

	var block_id := "cc_primary_school_1"
	var before_diligence := GameManager.get_storefront_diligence("S004")
	_check(before_diligence == "not_viewed",
		"测试开始前S004应处于not_viewed状态（如果不是，说明F组测试顺序被污染，需要独立跑）")

	var advance_result := GameManager.advance_block_understanding(block_id, 999.0)
	_check(advance_result.get("success", false), "advance_block_understanding() 应成功")
	_check(GameManager.get_block_understanding(block_id) >= 99.0,
		"区块了解度应被clamp到接近100（验证clampf边界正确）")

	var after_diligence := GameManager.get_storefront_diligence("S004")
	_check(after_diligence == "initial_viewing",
		"区块了解度达标后，S004应被自动标记为initial_viewing（验证_discover_storefronts_in_block()正常工作）")

	var deep_result := GameManager.advance_storefront_diligence("S004", "full_diligence")
	_check(deep_result.get("success", false), "完整尽调S004应成功：%s" % deep_result.get("reason", ""))
	_check(GameManager.get_storefront_diligence("S004") == "full_diligence",
		"完整尽调后S004状态应变为full_diligence")

	GameManager.recalculate_region_intel("CR001")
	var progress := GameManager.player_state.get_region_intel_progress("CR001")
	_check(progress > 0.0, "CR001的区域情报进度在提升区块了解度后应大于0")

	var before_switch_understanding := GameManager.get_block_understanding(block_id)
	GameManager.switch_active_store(_store1_id)
	var after_switch_understanding := GameManager.get_block_understanding(block_id)
	_check_approx(before_switch_understanding, after_switch_understanding, 0.001,
		"切换激活店铺不应影响PlayerState层面的区块了解度（验证知识字段已正确迁移出Store）")


# ── G组：存档读写（多店存档格式） ──

func _test_group_g_save_load() -> void:
	print("\n── G. 存档读写 ──")

	var store_count_before := GameManager.stores.size()
	var cash_before := GameManager.player_state.cash
	var active_id_before := GameManager.active_store_id

	var save_ok := SaveManager.save_game()
	_check(save_ok, "save_game() 应成功写入存档")

	GameManager.player_state.cash = -1.0
	GameManager.stores.clear()
	GameManager.active_store_id = ""

	var load_ok := SaveManager.load_game()
	_check(load_ok, "load_game() 应成功读取存档")

	_check(GameManager.stores.size() == store_count_before,
		"读档后店铺数量应恢复为存档前的%d家" % store_count_before)
	_check_approx(GameManager.player_state.cash, cash_before, 0.01,
		"读档后现金应恢复为存档前的数值")
	_check(GameManager.active_store_id == active_id_before,
		"读档后active_store_id应恢复为存档前指向的店铺")

	var restored_store1 := GameManager.get_store(_store1_id)
	_check(restored_store1 != null and restored_store1.is_open,
		"读档后店铺1应存在且仍是营业状态")
	_check(restored_store1.category_slots.size() == 1,
		"读档后店铺1的品类配置应完整还原")
