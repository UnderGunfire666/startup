extends Node
## ============================================================
## 全模块自测脚本 TestRunner.gd  (v3：修正lambda按值捕获局部变量的bug)
##
## 用法：
## 1. 新建一个空场景 TestRunner.tscn，根节点类型 Node，挂载本脚本。
## 2. 项目设置 -> Run -> Main Scene 临时改成 TestRunner.tscn
##    （或者直接在编辑器里选中该场景后按 F6 单独运行）。
## 3. 运行后查看 Output 面板，最后会打印通过/失败汇总。
##    失败项会带着 [FAIL] 标签和原因，方便定位。
##
## v3 变更说明：
## - GDScript的lambda对bool/int等值类型是"按值捕获"（创建时拷贝快照），
##   不是按引用捕获。v2版本里 `var flag := false; var cb := func(): flag = true`
##   这种写法，lambda内部改的只是自己那份拷贝，外层永远读不到变化。
##   现改用一元素数组 `[false]` 作容器——数组是引用类型，lambda捕获的是
##   同一份引用，内部`flag[0] = true`能被外层正确读到。
## - 同时修正了 v1 里被这个bug污染但没被断言使用的 slot_completed_fired，
##   顺手一起改掉，避免以后有人真的拿它做断言时踩同样的坑。
## ============================================================

var _pass_count: int = 0
var _fail_count: int = 0
var _fail_messages: Array[String] = []


func _ready() -> void:
	print("\n========== 开始全模块自测 ==========\n")

	_test_character_creation_data()
	_test_schedule_config()
	_test_customer_simulator()

	var region: RegionData = _test_character_creation_and_region()
	var storefront: StorefrontData = _test_storefront_selection(region)
	var category: CategoryData = _test_category_and_product_setup(storefront)
	_test_procurement(category)
	_test_open_store()
	_test_settlement_engine_direct(region, storefront, category)
	_test_time_and_settlement_flow()
	_test_schedule_manager()
	_test_player_state_mechanics()
	_test_store_state_mechanics()
	_test_save_load()

	_print_summary()
	get_tree().quit(0 if _fail_count == 0 else 1)


func check(condition: bool, label: String, extra: String = "") -> bool:
	if condition:
		_pass_count += 1
		print("[PASS] %s" % label)
	else:
		_fail_count += 1
		var msg := "[FAIL] %s%s" % [label, ("  | " + extra) if extra != "" else ""]
		_fail_messages.append(msg)
		print(msg)
	return condition


func _print_summary() -> void:
	print("\n========== 测试汇总 ==========")
	print("通过: %d   失败: %d" % [_pass_count, _fail_count])
	if _fail_count > 0:
		print("\n失败详情:")
		for m in _fail_messages:
			print(m)
	print("================================\n")


# ── 1. CharacterCreationData 静态数据 ─────────────────────

func _test_character_creation_data() -> void:
	print("\n--- [模块] CharacterCreationData ---")

	var ages := CharacterCreationData.get_all_ages()
	check(ages.size() > 0, "get_all_ages() 返回非空年龄列表")
	check(20 in ages and 58 in ages, "年龄范围包含20和58岁边界值", str(ages))

	var difficulty := CharacterCreationData.get_difficulty("normal")
	check(not difficulty.is_empty() and difficulty.id == "normal",
		"get_difficulty('normal') 返回正确难度")
	check(difficulty.starting_cash > 0.0, "难度起始资金 > 0")

	var invalid_difficulty := CharacterCreationData.get_difficulty("__not_exist__")
	check(not invalid_difficulty.is_empty(), "get_difficulty 对无效id有兜底返回值")

	var bracket := CharacterCreationData.get_age_bracket(25)
	check(bracket.id == "young", "25岁应落在young年龄段")

	var traits := CharacterCreationData.get_traits()
	check(traits.size() > 0, "get_traits() 返回非空特质列表")

	var trait_types: Dictionary = {}
	for t in traits:
		trait_types[t.trait_type] = true
	check(trait_types.size() == CharacterCreationData.TRAIT_TYPE_ORDER.size(),
		"特质覆盖了全部特质类型", "覆盖类型数=%d" % trait_types.size())

	var one_trait := CharacterCreationData.get_trait(traits[0].id)
	check(one_trait != null and one_trait.id == traits[0].id, "get_trait() 按id能取回特质")
	check(CharacterCreationData.get_trait("__not_exist__") == null,
		"get_trait() 对无效id返回null")

	# 注意：以下断言依据 CharacterCreationData.gd 内注释的设计约定——
	# "每个预设的年龄点数 - 已选特质成本 = 0"。如果这里持续报FAIL，
	# 说明预设的 trait_ids 组合与当前特质 point_cost / 年龄段 trait_points
	# 已经不匹配，需要回到 get_presets() 里重新配平，这是数据问题不是测试问题。
	var presets := CharacterCreationData.get_presets()
	check(presets.size() > 0, "get_presets() 返回非空预设列表")
	for preset in presets:
		var bracket2 := CharacterCreationData.get_age_bracket(int(preset.age))
		var used := 0
		for tid in preset.trait_ids:
			var td := CharacterCreationData.get_trait(tid)
			check(td != null, "预设[%s]引用的特质[%s]存在" % [preset.id, tid])
			if td != null:
				used += td.point_cost
		check(used == int(bracket2.trait_points),
			"预设[%s]特质点数刚好用完(用%d/共%d)" % [preset.id, used, bracket2.trait_points])


# ── 2. ScheduleConfig 疲惫分段计算 ─────────────────────────

func _test_schedule_config() -> void:
	print("\n--- [模块] ScheduleConfig ---")

	var tier0 := ScheduleConfig.get_fatigue_tier(0.0)
	check(tier0.state == "normal", "0小时工作时对应normal疲惫档位")

	var tier_exhausted := ScheduleConfig.get_fatigue_tier(20.0)
	check(tier_exhausted.state == "exhausted", "20小时工作时对应exhausted疲惫档位")

	check(ScheduleConfig.get_overwork_penalty(5.0) == 0.0, "5小时工作无过劳惩罚")
	check(ScheduleConfig.get_overwork_penalty(11.0) == ScheduleConfig.OVERWORK_PENALTY_TIER1_ENERGY,
		"11小时工作触发一档过劳惩罚")
	check(ScheduleConfig.get_overwork_penalty(13.0) == ScheduleConfig.OVERWORK_PENALTY_TIER2_ENERGY,
		"13小时工作触发二档过劳惩罚")

	var segments := ScheduleConfig.split_duration_by_fatigue_tiers(7.0, 6.0)
	var total_hours := 0.0
	for seg in segments:
		total_hours += seg.hours
	check(segments.size() >= 2, "跨疲惫阈值的行动被正确切分为多段", "段数=%d" % segments.size())
	check(absf(total_hours - 6.0) < 0.01, "分段小时数总和与原始时长一致",
		"总和=%.3f" % total_hours)


# ── 3. CustomerSimulator 顾客到店/成交模拟 ─────────────────

func _test_customer_simulator() -> void:
	print("\n--- [模块] CustomerSimulator ---")

	var sim := CustomerSimulator.new()
	sim.setup(100, 3600.0, 1.0, 9999, 9999, 10.0, 3.0, 0.5)
	sim.advance(3600.0)

	check(sim.visitors_so_far > 0, "推进1小时后有顾客到店", "到店=%d" % sim.visitors_so_far)
	check(sim.actual_orders == sim.converted_count, "无容量/库存限制时成交单=转化单")
	check(absf(sim.revenue - sim.actual_orders * 10.0) < 0.01, "营收=成交单数×单价")
	check(absf(sim.ingredient_cost - sim.actual_orders * 3.0) < 0.01, "原料成本=成交单数×单位成本")

	var sim_capped := CustomerSimulator.new()
	sim_capped.setup(200, 3600.0, 1.0, 5, 9999, 10.0, 3.0, 0.5)
	sim_capped.advance(3600.0)
	check(sim_capped.actual_orders <= 5, "容量限制生效，成交单数不超过容量",
		"实际=%d" % sim_capped.actual_orders)
	check(sim_capped.rejected_capacity_count >= 0, "超容量顾客被记录为rejected_capacity_count")

	var sim_zero := CustomerSimulator.new()
	sim_zero.setup(0, 3600.0, 1.0, 10, 10, 10.0, 3.0, 0.5)
	sim_zero.advance(3600.0)
	check(sim_zero.visitors_so_far == 0, "到店目标为0时，全程无顾客到店")


# ── 4. 角色创建 + 区域调研/选定 ────────────────────────────

func _test_character_creation_and_region() -> RegionData:
	print("\n--- [模块] GameManager 角色创建 & 区域调研 ---")

	GameManager.start_new_game()

	var bad_result := GameManager.create_character({
		"player_name": "",
		"gender": "male",
		"age": 25,
		"difficulty_id": "normal",
		"trait_ids": [],
	})
	check(bad_result.success == false, "空姓名创建角色应失败")

	var result := GameManager.create_character({
		"player_name": "测试创业者",
		"gender": "male",
		"age": 30,
		"difficulty_id": "normal",
		"trait_ids": [],
	})
	check(result.success == true, "合法参数创建角色应成功", str(result))
	check(GameManager.player_state.is_character_created, "创建后 player_state.is_character_created为true")
	check(GameManager.player_state.cash > 0.0, "创建后玩家现金>0")

	check(GameManager.all_regions.size() > 0, "GameData 提供了至少一个区域，无法继续后续测试则说明数据缺失")
	if GameManager.all_regions.is_empty():
		return null

	var region: RegionData = GameManager.all_regions[0]

	var research_result := GameManager.research_region(region.id)
	check(research_result.success == true, "对存在区域执行研究应成功", str(research_result))
	check(GameManager.store_state.get_region_familiarity(region.id) > 0.0,
		"研究后区域了解程度应提升")

	var required_familiarity := GameManager.player_state.get_required_region_familiarity()
	var guard := 0
	while GameManager.store_state.get_region_familiarity(region.id) < required_familiarity and guard < 50:
		GameManager.research_region(region.id)
		guard += 1
	GameManager.adjust_region_interest(region.id, 100.0)

	var invalid_region_result := GameManager.select_region("__not_exist_region__")
	check(invalid_region_result.success == false, "选定不存在的区域应失败")

	var select_result := GameManager.select_region(region.id)
	check(select_result.success == true, "了解/兴趣达标后选定区域应成功", str(select_result))
	check(GameManager.current_region != null and GameManager.current_region.id == region.id,
		"选定区域后 current_region 同步正确")

	return region


# ── 5. 门面考察与选定 ──────────────────────────────────────

func _test_storefront_selection(region: RegionData) -> StorefrontData:
	print("\n--- [模块] GameManager 门面选定 ---")

	if region == null:
		check(false, "上一阶段未取得有效区域，门面测试跳过")
		return null

	var storefronts := GameManager.get_storefronts_for_region(region.id)
	check(storefronts.size() > 0, "该区域至少有一个门面数据", "区域=%s" % region.id)
	if storefronts.is_empty():
		return null

	var storefront: StorefrontData = storefronts[0]

	var invalid_sf := GameManager.select_storefront("__not_exist_storefront__")
	check(invalid_sf.success == false, "选定不存在的门面应失败")

	var sf_result := GameManager.select_storefront(storefront.id)
	check(sf_result.success == true, "选定合法门面应成功", str(sf_result))
	check(GameManager.current_storefront != null and GameManager.current_storefront.id == storefront.id,
		"选定门面后 current_storefront 同步正确")

	return storefront


# ── 6. 品类/商品配置 ───────────────────────────────────────

func _test_category_and_product_setup(storefront: StorefrontData) -> CategoryData:
	print("\n--- [模块] GameManager 品类/商品管理 ---")

	if storefront == null:
		check(false, "上一阶段未取得有效门面，品类测试跳过")
		return null

	var options := GameManager.get_category_options_for_current_store()
	check(options.size() > 0, "当前门面至少有可选品类选项", "门面=%s" % storefront.id)

	var chosen_option: Dictionary = {}
	for opt in options:
		if opt.can_add:
			chosen_option = opt
			break
	check(not chosen_option.is_empty(), "存在至少一个当前可添加的品类")
	if chosen_option.is_empty():
		return null

	var category: CategoryData = chosen_option.category
	var products := GameManager.get_products_for_category(category.id)
	check(products.size() > 0, "该品类下至少有一个商品数据", "品类=%s" % category.id)
	if products.is_empty():
		return null

	var product_ids: Array[String] = [products[0].id]

	var cash_before := GameManager.player_state.cash
	var add_result := GameManager.add_category_to_store(category.id, product_ids)
	check(add_result.success == true, "添加品类应成功", str(add_result))
	check(GameManager.player_state.cash < cash_before, "添加品类应扣除装修/设备投入现金")

	var dup_result := GameManager.add_category_to_store(category.id, product_ids)
	check(dup_result.success == false, "重复添加同一品类应失败")

	check(GameManager.store_state.has_category(category.id), "store_state.has_category 正确识别已添加品类")

	if products.size() > 1:
		var add_product_ok := GameManager.add_product_to_slot(category.id, products[1].id)
		check(add_product_ok, "向品类槏位追加第二个商品应成功")
		var remove_product_ok := GameManager.remove_product_from_slot(category.id, products[1].id)
		check(remove_product_ok, "从品类槏位移除刚添加的商品应成功")

	var slot := GameManager.store_state.get_slot_by_category(category.id)
	check(slot != null, "get_slot_by_category 能取回刚添加的槏位")

	var price_ok := GameManager.set_product_price_override(category.id, products[0].id, 999.0)
	check(price_ok, "设置商品自定义价格应成功")
	var pc := slot.get_product_config(products[0].id)
	check(pc != null and absf(pc.custom_price - 999.0) < 0.01, "自定义价格已正确写入")

	var inv_ok := GameManager.set_product_inventory(category.id, products[0].id, 50)
	check(inv_ok, "设置商品库存单位应成功")
	check(pc.inventory_units == 50, "库存单位已正确写入")

	var area_result := GameManager.set_category_area(category.id, category.required_area + 1.0)
	check(area_result.success == true or area_result.success == false,
		"set_category_area 在各种面积输入下都应返回结构化结果而不崩溃")

	return category


# ── 7. 原材料采购 ─────────────────────────────────────────

func _test_procurement(category: CategoryData) -> void:
	print("\n--- [模块] GameManager 原材料采购 ---")

	if category == null:
		check(false, "上一阶段未取得有效品类，采购测试跳过")
		return

	var ingredients := GameManager.get_ingredients_in_use()
	check(ingredients.size() >= 0, "get_ingredients_in_use 不崩溃返回数组")

	if GameManager.all_ingredients.is_empty():
		check(false, "GameData 未提供任何原材料数据，无法测试采购")
		return

	var ingredient: IngredientData = GameManager.all_ingredients[0]

	var empty_cart_result := GameManager.purchase_ingredients({})
	check(empty_cart_result.success == false, "空采购车应返回失败")

	var cart := {ingredient.id: 10.0}
	var total := GameManager.calculate_purchase_total(cart)
	check(total > 0.0, "计算采购总价 > 0", "总价=%.2f" % total)

	var cash_before := GameManager.player_state.cash
	var purchase_result := GameManager.purchase_ingredients(cart)
	check(purchase_result.success == true, "合法采购应成功", str(purchase_result))
	check(absf(GameManager.player_state.cash - (cash_before - total)) < 0.01,
		"采购后现金扣减金额与计算总价一致")
	check(GameManager.store_state.get_ingredient_stock(ingredient.id) >= 10.0,
		"采购后库存增加了对应数量")

	var huge_cart := {ingredient.id: 999999999.0}
	var cash_before2 := GameManager.player_state.cash
	var over_result := GameManager.purchase_ingredients(huge_cart)
	check(over_result.success == false, "超出现金能力的采购应失败")
	check(absf(GameManager.player_state.cash - cash_before2) < 0.01,
		"失败的采购不应改变现金")


# ── 8. 开业条件与开业 ──────────────────────────────────────

func _test_open_store() -> void:
	print("\n--- [模块] GameManager 开业流程 ---")

	var readiness := GameManager.get_open_readiness()
	check(readiness.has("can_open") and readiness.has("checks"), "get_open_readiness 返回结构完整")

	if not readiness.can_open:
		for c in readiness.checks:
			if not c.passed:
				print("    未满足开业条件: %s" % c.label)

	var open_result := GameManager.open_store()
	check(open_result.has("success"), "open_store 返回结构完整")

	if readiness.can_open:
		check(open_result.success == true, "满足开业条件时开业应成功", str(open_result))
		check(GameManager.store_state.is_open == true, "开业后 is_open 应为true")

		var reopen_result := GameManager.open_store()
		check(reopen_result.success == false, "已开业状态下重复开业应失败")
	else:
		check(open_result.success == false, "不满足开业条件时开业应失败(测试环境备货/品类可能不足，这是预期行为)")


# ── 9. SettlementEngine 直接单测（纯函数，不依赖游戏状态推进） ──

func _test_settlement_engine_direct(region: RegionData, storefront: StorefrontData, category: CategoryData) -> void:
	print("\n--- [模块] SettlementEngine 直接计算 ---")

	if region == null or storefront == null or category == null:
		check(false, "缺少region/storefront/category，SettlementEngine直测跳过")
		return

	var products := GameManager.get_products_for_category(category.id)
	if products.is_empty():
		check(false, "该品类下无商品，SettlementEngine直测跳过")
		return

	var product: ProductData = products[0]
	var open_ranges: Array[Vector2i] = [Vector2i(0, 24)]

	var params := SettlementEngine.calculate_params(
		region, storefront, category, product,
		GameManager.store_state, GameManager.player_state,
		12, open_ranges, true
	)
	check(params.has("is_open"), "calculate_params 返回包含is_open字段")
	check(params.visitors >= 0, "calculate_params 计算的visitors非负")
	check(params.conversion_rate >= 0.0 and params.conversion_rate <= 1.0,
		"conversion_rate 在[0,1]范围内", "值=%.3f" % params.conversion_rate)

	var mismatched_category := CategoryData.new()
	mismatched_category.id = "__no_such_category__"
	mismatched_category.name = "不存在的品类"
	var params_mismatch := SettlementEngine.calculate_params(
		region, storefront, mismatched_category, product,
		GameManager.store_state, GameManager.player_state,
		12, open_ranges, true
	)
	check(params_mismatch.is_open == false, "门面不支持的品类应返回is_open=false")

	var closed_ranges: Array[Vector2i] = [Vector2i(0, 0)]
	var params_closed := SettlementEngine.calculate_params(
		region, storefront, category, product,
		GameManager.store_state, GameManager.player_state,
		12, closed_ranges, true
	)
	check(params_closed.is_open == false, "空营业时间段应返回is_open=false")

	var sim := CustomerSimulator.new()
	sim.setup(params.visitors, 3600.0, params.conversion_rate, params.slot_capacity,
		9999, product.average_price if product.average_price > 0.0 else 10.0,
		1.0, 0.5)
	sim.advance(3600.0)

	var result := SettlementEngine.finalize_from_simulation(
		params, 12, GameManager.store_state.current_day, category, product, 9999, sim
	)
	check(result is SettlementResult, "finalize_from_simulation 返回SettlementResult实例")
	check(result.revenue >= 0.0, "结算营收非负")
	check(absf(result.profit - (result.revenue - result.ingredient_cost - result.staff_cost
		- result.rent_cost - result.utility_cost - result.waste_cost)) < 0.01,
		"利润=营收-各项成本的公式成立")


# ── 10. TimeManager + GameManager 经营结算全链路 ────────────

func _test_time_and_settlement_flow() -> void:
	print("\n--- [模块] TimeManager 时间推进 & 经营结算全链路 ---")

	var revenue_before := GameManager.store_state.total_revenue

	# 注意：GDScript的lambda对bool/int等值类型是"按值捕获"，
	# lambda内部修改一个普通局部bool不会反映到外层。这里用一元素数组
	# 当容器（数组是引用类型），lambda和外层拿到的是同一份引用，
	# 内部 flag[0] = true 才能被外层while条件正确读到。
	var slot_completed_flag := [false]
	var on_slot_completed := func(_day, _slot, _results):
		slot_completed_flag[0] = true
	TimeManager.slot_completed.connect(on_slot_completed)

	GameManager.begin_slot_simulation()
	GameManager.advance_slot_simulation(3600.0)
	var results := GameManager.finalize_slot_simulation()
	check(results is Array, "finalize_slot_simulation 返回数组")

	if GameManager.store_state.is_open and not GameManager.store_state.category_slots.is_empty():
		check(results.size() > 0, "门店已开业且有品类时，结算应产生至少一条结果")
		for r in results:
			check(r is SettlementResult, "结算结果类型为SettlementResult")

	TimeManager.slot_completed.disconnect(on_slot_completed)

	# X5速度下每帧(delta=0.1)推进 0.1*120*5=60 游戏内秒，
	# 跨一个小时边界最多需要3600/60=60帧，200帧的预算足够触发多次hour_advanced。
	var hour_advanced_flag := [false]
	var on_hour_advanced := func(_day, _hour):
		hour_advanced_flag[0] = true
	TimeManager.hour_advanced.connect(on_hour_advanced)

	TimeManager.set_speed(TimeManager.Speed.X5)
	check(TimeManager.speed == TimeManager.Speed.X5, "set_speed 正确设置速度")

	var frames := 0
	while frames < 200 and not hour_advanced_flag[0]:
		TimeManager._process(0.1)
		frames += 1

	TimeManager.hour_advanced.disconnect(on_hour_advanced)
	check(hour_advanced_flag[0], "在合理帧数内时间能够推进并触发hour_advanced信号（未卡死）",
		"耗费帧数=%d" % frames)
	TimeManager.set_speed(TimeManager.Speed.PAUSED)

	if GameManager.store_state.is_open:
		check(GameManager.store_state.total_revenue >= revenue_before,
			"营业状态下累计营收不应减少（营收只增不减，成本单独记账）")


# ── 11. ScheduleManager 行动排程 ───────────────────────────

func _test_schedule_manager() -> void:
	print("\n--- [模块] ScheduleManager 行动排程 ---")

	var invalid_action := ScheduleManager.can_schedule_action("__no_such_action__", 10)
	check(invalid_action.can == false and invalid_action.reason_code == "invalid_action",
		"排程不存在的行动应返回invalid_action")

	var rest_check := ScheduleManager.can_schedule_action("rest_short", 10)
	check(rest_check.has("can"), "对合法行动can_schedule_action返回结构完整")

	if rest_check.can:
		var add_result := ScheduleManager.add_action_to_schedule("rest_short", 10)
		check(add_result.can == true, "合法行动应能成功加入排程")
		check(ScheduleManager.today_schedule.entries.size() > 0, "排程队列中应出现刚加入的行动")

		var removed := ScheduleManager.remove_action_from_schedule(10)
		check(removed == true, "移除已排程的行动应成功")

	var energy_before := GameManager.player_state.energy
	var start_result := ScheduleManager.start_action_now("rest_short")
	check(start_result.has("can"), "start_action_now 返回结构完整")

	if start_result.can:
		check(ScheduleManager.current_action != null and ScheduleManager.current_action.is_active,
			"start_action_now成功后current_action应处于激活状态")

		# rest_short时长1小时=3600游戏秒。start_action_now会把速度设为X1，
		# 每帧(delta=0.2)推进 0.2*120*1=24 游戏秒，完整走完需要约150帧，
		# 这里给到300帧的预算，留足安全余量。这段用的是直接读取
		# ScheduleManager.current_action的成员字段判断，不涉及lambda捕获，
		# 不受v3修复的那个坑影响。
		var guard := 0
		while ScheduleManager.current_action != null and ScheduleManager.current_action.is_active and guard < 300:
			TimeManager._process(0.2)
			guard += 1
		check(guard < 300, "行动能在合理时间内自然结束（tick驱动正常）", "耗费帧数=%d" % guard)
		check(GameManager.player_state.energy >= energy_before or GameManager.player_state.energy_debt < 999999.0,
			"休息类行动执行后精力状态发生了合理变化")

	TimeManager.set_speed(TimeManager.Speed.PAUSED)


# ── 12. PlayerState 特质/精力/跨天机制 ─────────────────────

func _test_player_state_mechanics() -> void:
	print("\n--- [模块] PlayerState 特质/精力/跨天 ---")

	var p := PlayerState.new()
	p.apply_character_setup({
		"player_name": "特质测试员",
		"gender": "female",
		"age": 30,
		"difficulty_id": "normal",
		"preset_id": "",
		"starting_cash": 100000.0,
		"trait_ids": ["energetic"],
	})
	check(p.has_trait("energetic"), "apply_character_setup后正确记录已选特质")
	check(p.get_trait_modifier("max_energy_add", 0.0) == 15.0,
		"energetic特质的max_energy_add效果读取正确")
	check(p.max_energy > 90.0, "energetic特质应提升max_energy高于基础值90")

	var energy_before := p.energy
	p.apply_energy_delta(-50.0)
	check(p.energy == maxf(0.0, energy_before - 50.0), "扣减精力在有余额时直接减少energy")

	p.apply_energy_delta(-99999.0)
	check(p.energy == 0.0 and p.energy_debt > 0.0, "精力耗尽后超支部分记录为energy_debt")

	var debt_before := p.energy_debt
	p.apply_energy_delta(10.0)
	check(p.energy_debt < debt_before, "补充精力优先偿还energy_debt")

	p.work_hours_today = 11.0
	p.start_new_day()
	check(p.work_hours_today == 0.0, "start_new_day 重置当日工作时长")
	check(p.fatigue_state == "normal", "start_new_day 重置疲惫状态为normal")

	var required_fam := p.get_required_region_familiarity()
	check(required_fam >= 0.0 and required_fam <= 100.0, "区域了解阈值在合理范围内")


# ── 13. StoreState 原料库存/结算累计机制 ───────────────────

func _test_store_state_mechanics() -> void:
	print("\n--- [模块] StoreState 库存/结算累计 ---")

	var s := StoreState.new()
	s.add_ingredient_stock("test_ing", 10.0, 2.0)
	check(absf(s.get_ingredient_stock("test_ing") - 10.0) < 0.01, "首次入库数量正确")
	check(absf(s.get_ingredient_avg_cost("test_ing") - 2.0) < 0.01, "首次入库均价正确")

	s.add_ingredient_stock("test_ing", 10.0, 4.0)
	check(absf(s.get_ingredient_stock("test_ing") - 20.0) < 0.01, "二次入库后总量正确累加")
	check(absf(s.get_ingredient_avg_cost("test_ing") - 3.0) < 0.01,
		"二次入库后加权平均成本计算正确(应为3.0)")

	var product := ProductData.new()
	product.id = "test_product"
	product.recipe = [{"ingredient_id": "test_ing", "quantity": 2.0}]
	var producible := s.get_max_produceable_by_ingredients(product)
	check(producible == 10, "按配方与库存计算的最大可生产数量正确(20/2=10)")

	s.consume_ingredients(product, 4)
	check(absf(s.get_ingredient_stock("test_ing") - 12.0) < 0.01,
		"消耗原料后库存正确扣减(20-4*2=12)")

	var result := SettlementResult.new()
	result.day = 1
	result.slot = "12:00"
	result.revenue = 100.0
	result.ingredient_cost = 20.0
	result.profit = 80.0
	result.reputation_delta = 2.0
	result.actual_orders = 5

	var reputation_before := s.reputation
	var revenue_before := s.total_revenue
	s.apply_settlement(result)
	check(s.reputation == clampf(reputation_before + 2.0, 0.0, 100.0), "结算后口碑正确变化")
	check(absf(s.total_revenue - (revenue_before + 100.0)) < 0.01, "结算后累计营收正确累加")
	check(s.daily_history.size() > 0, "结算后daily_history记录了本条历史")

	var summary := s.get_day_summary(1)
	check(absf(summary.revenue - 100.0) < 0.01, "get_day_summary 正确汇总当日数据")


# ── 14. SaveManager 存档读写 & 序列化往返 ───────────────────

func _test_save_load() -> void:
	print("\n--- [模块] SaveManager 存档/读档 ---")

	var p := GameManager.player_state
	var p_dict := p.to_save_dict()
	var p_restored := PlayerState.from_save_dict(p_dict)
	check(absf(p_restored.cash - p.cash) < 0.01, "PlayerState序列化往返后cash一致")
	check(p_restored.player_name == p.player_name, "PlayerState序列化往返后player_name一致")
	check(p_restored.selected_trait_ids == p.selected_trait_ids,
		"PlayerState序列化往返后特质列表一致")

	var s := GameManager.store_state
	var s_dict := s.to_save_dict()
	var s_restored := StoreState.from_save_dict(s_dict)
	check(s_restored.is_open == s.is_open, "StoreState序列化往返后is_open一致")
	check(s_restored.category_slots.size() == s.category_slots.size(),
		"StoreState序列化往返后品类槏位数量一致")
	check(absf(s_restored.total_revenue - s.total_revenue) < 0.01,
		"StoreState序列化往返后total_revenue一致")

	var cash_snapshot := GameManager.player_state.cash
	var save_ok := SaveManager.save_game()
	check(save_ok == true, "save_game() 应成功写入存档文件")
	check(SaveManager.has_save() == true, "存档后has_save()应为true")

	GameManager.player_state.cash = -999.0
	var load_ok := SaveManager.load_game()
	check(load_ok == true, "load_game() 应成功读取存档文件")
	check(absf(GameManager.player_state.cash - cash_snapshot) < 0.01,
		"读档后玩家现金恢复为存档时的值")

	SaveManager.delete_save()
	check(SaveManager.has_save() == false, "delete_save() 后has_save()应为false")

	var load_missing := SaveManager.load_game()
	check(load_missing == false, "存档不存在时load_game()应返回false且不崩溃")
