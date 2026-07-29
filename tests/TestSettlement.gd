extends Node
## 可重复运行的结算测试。挂载到任意场景节点，_ready() 时自动运行并打印结果。
## 不依赖 GameManager 单例，直接从 GameData 构造测试对象，保证脱机可测。

func _ready() -> void:
	run_all_tests()

func run_all_tests() -> void:
	var passed := 0
	var failed := 0

	var tests: Array[Callable] = [
		_test_orders_not_exceed_inventory,
		_test_orders_not_exceed_capacity,
		_test_cash_calculation,
		_test_missing_key_staff_penalty,
		_test_closed_slot_no_revenue,
		_test_deterministic_output,
		_test_scenario_a_noon_positive,
		_test_scenario_c_worse_than_a,
		_test_scenario_e_has_penalty,
		_test_scenario_f_inventory_limit,
	]

	for t in tests:
		var result: String = t.call()
		if result == "OK":
			passed += 1
			print("  PASS: ", t.get_method())
		else:
			failed += 1
			print("  FAIL: ", t.get_method(), " -> ", result)

	print("\n结果：%d passed / %d failed" % [passed, passed + failed])


# ── 工具：按 id 查找 ──────────────────────────────────────
static func _find_by_id(arr: Array, id: String) -> Object:
	for x in arr:
		if x.id == id:
			return x
	return null

static func _make_store_state(
		has_staff: bool, strategy: String, inventory: int
) -> StoreState:
	var s := StoreState.new()
	s.has_key_staff   = has_staff
	s.strategy        = strategy
	s.inventory_units = inventory
	s.reputation      = 50.0
	s.stress          = 20.0
	return s

static func _calc(
		region_id: String, sf_id: String, cat_id: String, prod_id: String,
		has_staff: bool, strategy: String, inventory: int, slot: String,
		debug_cat: bool = false
) -> SettlementResult:
	var all_r := GameData.get_regions()
	var all_s := GameData.get_storefronts()
	var all_c := GameData.get_categories()
	var all_p := GameData.get_products()
	var state := _make_store_state(has_staff, strategy, inventory)
	return SettlementEngine.calculate(
		_find_by_id(all_r, region_id),
		_find_by_id(all_s, sf_id),
		_find_by_id(all_c, cat_id),
		_find_by_id(all_p, prod_id),
		state, slot, 1, debug_cat
	)


# ── 测试用例 ──────────────────────────────────────────────

func _test_orders_not_exceed_inventory() -> String:
	var r := _calc("A001", "S003", "fast_food", "P005", true, "standard", 5, "noon")
	if r.actual_orders > 5:
		return "订单(%d)超过库存(5)" % r.actual_orders
	return "OK"

func _test_orders_not_exceed_capacity() -> String:
	var r := _calc("A001", "S003", "fast_food", "P005", true, "standard", 9999, "noon")
	if r.actual_orders > r.slot_capacity:
		return "订单(%d)超过容量(%d)" % [r.actual_orders, r.slot_capacity]
	return "OK"

func _test_cash_calculation() -> String:
	var state := _make_store_state(true, "standard", 100)
	state.cash = 100000.0
	var all_r := GameData.get_regions()
	var all_s := GameData.get_storefronts()
	var all_c := GameData.get_categories()
	var all_p := GameData.get_products()
	var r := SettlementEngine.calculate(
		_find_by_id(all_r, "A001"), _find_by_id(all_s, "S003"),
		_find_by_id(all_c, "fast_food"), _find_by_id(all_p, "P005"),
		state, "noon", 1
	)
	var expected_profit: float = r.revenue - r.ingredient_cost \
		- r.staff_cost - r.rent_cost - r.waste_cost
	if absf(r.profit - expected_profit) > 0.01:
		return "利润计算错误: %.2f != %.2f" % [r.profit, expected_profit]
	return "OK"

func _test_missing_key_staff_penalty() -> String:
	var with_staff := _calc("A001", "S003", "fast_food", "P005", true, "standard", 100, "noon")
	var without_staff := _calc("A001", "S003", "fast_food", "P005", false, "standard", 100, "noon")
	if without_staff.conversion_rate >= with_staff.conversion_rate:
		return "缺厨师未产生成交率惩罚: %.3f >= %.3f" \
			% [without_staff.conversion_rate, with_staff.conversion_rate]
	if not without_staff.missing_key_staff_active:
		return "missing_key_staff_active 未标记"
	return "OK"

func _test_closed_slot_no_revenue() -> String:
	var r := _calc("A002", "S001", "breakfast", "P001", false, "standard", 100, "night")
	if r.is_open:
		return "早餐类晚夜时段不应营业"
	if r.revenue != 0.0:
		return "不营业时段收入应为0，实为%.2f" % r.revenue
	return "OK"

func _test_deterministic_output() -> String:
	var r1 := _calc("A001", "S003", "fast_food", "P005", true, "standard", 100, "noon")
	var r2 := _calc("A001", "S003", "fast_food", "P005", true, "standard", 100, "noon")
	if r1.actual_orders != r2.actual_orders or absf(r1.profit - r2.profit) > 0.01:
		return "相同输入结果不稳定"
	return "OK"

func _test_scenario_a_noon_positive() -> String:
	var dawn := _calc("A001", "S003", "fast_food", "P005", true, "standard", 100, "dawn")
	var noon := _calc("A001", "S003", "fast_food", "P005", true, "standard", 100, "noon")
	if dawn.is_open:
		return "场景A：快餐清晨不应营业（standard策略）"
	if noon.profit <= 0:
		return "场景A：午间利润应为正，实为%.0f" % noon.profit
	return "OK"

func _test_scenario_c_worse_than_a() -> String:
	var a := _calc("A001", "S003", "fast_food", "P005", true, "standard", 100, "noon")
	var c := _calc("A001", "S003", "beverage_dessert", "P008", false, "standard", 100, "noon", true)
	if not c.is_open:
		return "OK"
	if c.actual_orders >= a.actual_orders:
		return "场景C订单(%d)应少于场景A(%d)" % [c.actual_orders, a.actual_orders]
	return "OK"

func _test_scenario_e_has_penalty() -> String:
	var with_chef := _calc("A001", "S003", "fast_food", "P005", true, "standard", 100, "noon")
	var without_chef := _calc("A001", "S003", "fast_food", "P005", false, "standard", 100, "noon")
	if without_chef.actual_orders > with_chef.actual_orders:
		return "无厨师订单(%d)不应多于有厨师(%d)" \
			% [without_chef.actual_orders, with_chef.actual_orders]
	return "OK"

func _test_scenario_f_inventory_limit() -> String:
	var r := _calc("A001", "S003", "fast_food", "P005", true, "standard", 5, "noon")
	if r.actual_orders > 5:
		return "库存限制失效：订单%d > 5" % r.actual_orders
	if r.lost_inventory == 0 and r.theoretical_orders > 5:
		return "库存不足时 lost_inventory 应>0"
	return "OK"
