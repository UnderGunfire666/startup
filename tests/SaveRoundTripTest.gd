extends Node
## 多店存档往返回归测试。
## 验证 PlayerState、Store×N、active_store_id 与 TimeManager 在 Save/Load 后保持一致。

var _pass_count: int = 0
var _fail_count: int = 0
var _store1_id: String = ""
var _store2_id: String = ""


func _ready() -> void:
	print("========== Save Round-trip 测试开始 ==========")
	SaveManager.delete_save()
	GameManager.start_new_game()
	TimeManager.reset()
	ScheduleManager.reset_for_new_game()

	_test_build_state()
	_test_save_and_load()
	_cleanup()

	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("🎉 Save Round-trip 全部通过")
	else:
		print("⚠ Save Round-trip 存在 %d 项失败" % _fail_count)


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("✅ %s" % label)
	else:
		_fail_count += 1
		print("❌ %s" % label)


func _test_build_state() -> void:
	print("\n── 1. 构造多店存档状态 ──")

	var character_result: Dictionary = GameManager.create_character({
		"player_name": "存档回归测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": ["energetic"],
	})
	_check(bool(character_result.get("success", false)), "创建测试角色应成功")

	GameManager.player_state.cash = 87654.0
	GameManager.player_state.stress = 23.5
	GameManager.player_state.block_research_progress["block_w_school"] = {
		"population": 37.5,
		"groups": 62.5,
	}
	GameManager.player_state.brand_awareness_by_block["block_w_school"] = 14.75
	GameManager.player_state.set_storefront_intel("S004", {"visited": true, "menu_reviewed": false, "order_records": [], "traffic_observations": []})
	GameManager.player_state.focused_city_region_id = "CR001"
	GameManager.player_state.supervising_store_id = ""

	var first_result: Dictionary = GameManager.create_new_store("存档首店")
	_store1_id = str(first_result.get("store_id", ""))
	_check(bool(first_result.get("success", false)) and not _store1_id.is_empty(),
		"创建首店应成功并获得ID")

	var store1: Store = GameManager.get_store(_store1_id)
	_check(store1 != null, "首店实例应存在")
	if store1 != null:
		store1.selected_storefront_id = "S004"
		store1.signed_storefront_id = "S004"
		store1.is_open = true
		store1.pre_open_stage = Store.PreOpenStage.OPEN_FOR_BUSINESS
		store1.reputation = 72.5
		store1.ingredient_stock["soybean"] = 11.0
		store1.ingredient_avg_cost["soybean"] = 8.5
		store1.daily_history.append({
			"day": 1,
			"slot": "10:00",
			"group_summary": {"student": {"visitors": 12, "intended_orders": 7, "actual_orders": 5}},
			"lost_no_menu": 2,
			"lost_price_rejection": 1,
			"lost_external_competition": 3,
			"lost_self_cannibalization": 4,
		})

	var second_result: Dictionary = GameManager.create_new_store("存档分店")
	_store2_id = str(second_result.get("store_id", ""))
	_check(bool(second_result.get("success", false)) and not _store2_id.is_empty(),
		"创建分店应成功并获得ID")
	_check(_store1_id != _store2_id, "两家Store ID应不同")

	var store2: Store = GameManager.get_store(_store2_id)
	_check(store2 != null, "分店实例应存在")
	if store2 != null:
		store2.selected_storefront_id = "S001"
		store2.is_open = true
		store2.pre_open_stage = Store.PreOpenStage.OPEN_FOR_BUSINESS
		store2.reputation = 61.0
		store2.ingredient_stock["soybean"] = 23.0
		store2.ingredient_avg_cost["soybean"] = 9.25

	GameManager.player_state.region_intel_levels["CR001"] = 3
	GameManager.player_state.region_intel_progress["CR001"] = 12.5

	TimeManager.total_game_seconds = TimeManager.DAY_START_SECONDS + 7200.0
	TimeManager.current_day = 1
	_check(is_equal_approx(TimeManager.total_game_seconds, TimeManager.DAY_START_SECONDS + 7200.0),
		"Save state uses the explicit 10:00 game timestamp")
	GameManager.switch_active_store(_store1_id)

	_check(GameManager.active_store_id == _store1_id, "保存前应激活首店")
	_check(GameManager.store_state != null and GameManager.store_state.id == _store1_id,
		"保存前store_state应指向首店")
	_check(TimeManager.current_day == 1, "保存前当前日应为第1天")
	_check(TimeManager.get_current_hour_int() == 10, "保存前当前时间应为10:00")


func _test_save_and_load() -> void:
	print("\n── 2. Save → 清空运行态 → Load ──")

	var save_result: bool = SaveManager.save_game()
	_check(save_result, "save_game() 应成功")
	_check(SaveManager.has_save(), "保存后应存在存档文件")

	GameManager.player_state = PlayerState.new()
	GameManager.stores = []
	GameManager.active_store_id = ""
	TimeManager.reset()
	ScheduleManager.reset_for_new_game()

	_check(GameManager.stores.is_empty(), "模拟清空后运行态应没有Store")
	_check(GameManager.active_store_id.is_empty(), "模拟清空后active_store_id应为空")

	var load_result: bool = SaveManager.load_game()
	_check(load_result, "load_game() 应成功")

	_check(GameManager.player_state.is_character_created, "加载后角色创建状态应恢复")
	_check(GameManager.player_state.player_name == "存档回归测试者", "加载后玩家姓名应恢复")
	_check(is_equal_approx(GameManager.player_state.cash, 87654.0), "加载后玩家现金应恢复")
	_check(is_equal_approx(GameManager.player_state.stress, 23.5), "加载后玩家压力应恢复")
	_check(is_equal_approx(GameManager.player_state.get_block_research_progress("block_w_school", "population"), 37.5),
		"加载后区块了解度应恢复")
	_check(is_equal_approx(GameManager.player_state.get_block_research_progress("block_w_school", "groups"), 62.5),
		"Independent group research progress restores")
	_check(is_equal_approx(float(GameManager.player_state.brand_awareness_by_block.get("block_w_school", 0.0)), 14.75),
		"Brand awareness restores")
	_check(bool(GameManager.player_state.get_storefront_intel("S004").get("visited", false)),
		"加载后门面尽调状态应恢复")
	_check(GameManager.player_state.region_intel_levels.get("CR001", 0) == 3,
		"加载后区域知识等级应恢复")
	_check(is_equal_approx(float(GameManager.player_state.region_intel_progress.get("CR001", 0.0)), 12.5),
		"加载后区域知识进度应恢复")

	_check(GameManager.stores.size() == 2, "加载后应恢复2个Store")
	_check(GameManager.active_store_id == _store1_id, "加载后active_store_id应恢复为首店")
	_check(GameManager.store_state != null and GameManager.store_state.id == _store1_id,
		"加载后store_state应指向首店")

	var loaded_store1: Store = GameManager.get_store(_store1_id)
	var loaded_store2: Store = GameManager.get_store(_store2_id)
	_check(loaded_store1 != null and loaded_store2 != null, "加载后两家Store实例都应存在")

	if loaded_store1 != null and loaded_store2 != null:
		_check(loaded_store1.name == "存档首店", "首店名称应恢复")
		_check(loaded_store2.name == "存档分店", "分店名称应恢复")
		_check(loaded_store1.selected_storefront_id == "S004", "首店门面应恢复")
		_check(loaded_store2.selected_storefront_id == "S001", "分店门面应恢复")
		_check(loaded_store1.is_open and loaded_store2.is_open, "两家店营业状态应恢复")
		_check(loaded_store1.pre_open_stage == Store.PreOpenStage.OPEN_FOR_BUSINESS
			and loaded_store2.pre_open_stage == Store.PreOpenStage.OPEN_FOR_BUSINESS,
			"两家店营业阶段应恢复为OPEN_FOR_BUSINESS")
		_check(is_equal_approx(loaded_store1.reputation, 72.5), "首店口碑应恢复")
		_check(is_equal_approx(loaded_store2.reputation, 61.0), "分店口碑应恢复")
		_check(is_equal_approx(loaded_store1.get_ingredient_stock("soybean"), 11.0), "首店库存应恢复")
		_check(is_equal_approx(loaded_store2.get_ingredient_stock("soybean"), 23.0), "分店库存应恢复")
		_check(is_equal_approx(loaded_store1.get_ingredient_avg_cost("soybean"), 8.5), "首店原料均价应恢复")
		_check(is_equal_approx(loaded_store2.get_ingredient_avg_cost("soybean"), 9.25), "分店原料均价应恢复")
		_check(is_equal_approx(loaded_store1.get_ingredient_stock("soybean"), 11.0) and
			is_equal_approx(loaded_store2.get_ingredient_stock("soybean"), 23.0),
			"加载后两家Store库存仍应保持隔离")

	_check(TimeManager.current_day == 1, "加载后当前日应恢复为第1天")
	_check(TimeManager.get_current_hour_int() == 10, "加载后当前时间应恢复为10:00")


	if loaded_store1 != null:
		var saved_slot: Dictionary = loaded_store1.daily_history[0] if not loaded_store1.daily_history.is_empty() else {}
		var saved_student: Dictionary = saved_slot.get("group_summary", {}).get("student", {})
		_check(int(saved_student.get("actual_orders", 0)) == 5
			and int(saved_slot.get("lost_no_menu", 0)) == 2
			and int(saved_slot.get("lost_price_rejection", 0)) == 1
			and int(saved_slot.get("lost_external_competition", 0)) == 3
			and int(saved_slot.get("lost_self_cannibalization", 0)) == 4,
			"Group order summary and loss breakdown restore")
	_check(is_equal_approx(TimeManager.total_game_seconds, TimeManager.DAY_START_SECONDS + 7200.0),
		"Total game seconds restore")

func _cleanup() -> void:
	SaveManager.delete_save()
	GameManager.start_new_game()
	TimeManager.reset()
	ScheduleManager.reset_for_new_game()
