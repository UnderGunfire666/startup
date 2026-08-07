extends Node
## 日程行动系统 + 自由营业时间段系统 的回归测试脚本。
##
## 运行方式（三选一）：
##   1. 命令行：godot --headless --path <项目根目录> --script res://tests/test_schedule_system.gd
##   2. Godot编辑器：把这个文件放进 res://tests/ 目录，编辑器里右键 "运行"
##      （需要项目已经打开，Autoload 才会被正确加载）
##   3. 临时把这个脚本挂到场景里的一个 Node 上，用 _ready() 代替 _init() 调用同样的逻辑
##
## 注意：这不是用 GUT 之类的测试框架写的，是纯手写的 assert + 打印摘要，
## 因为项目里没有安装测试插件。跑完看终端输出的 PASS/FAIL 摘要即可。

var pass_count := 0
var fail_count := 0
var fail_messages: Array[String] = []


func _ready() -> void:
	print("========== 开始运行日程/时间系统回归测试 ==========\n")

	_setup_fixture()

	_test_schedule_conflict_same_hour()
	_test_schedule_conflict_crosses_midnight()
	_test_deep_inspection_outside_allowed_hours()
	_test_store_not_open_blocks_actions()
	_test_closing_review_requires_settlement_today()
	_test_fatigue_tiers()
	_test_energy_debt_and_recovery()
	_test_open_hour_ranges()
	_test_store_supervision_operating_hour_check()
	_test_hourly_execution_lifecycle()
	_test_day_rollover_and_overwork_penalty()

	_print_summary()

## 保证 category_slots 至少有一条可用的测试记录，不依赖任何其他测试留下的状态。
## 每个需要用到 category_slots[0] 的测试都应该在自己开头调用这个函数。
func _ensure_test_category_slot() -> StoreCategorySlot:
	if GameManager.store_state.category_slots.is_empty():
		var slot := StoreCategorySlot.new()
		slot.category_id = "test_category"
		slot.open_hour_ranges = [Vector2i(8, 22)]
		GameManager.store_state.category_slots.append(slot)
	return GameManager.store_state.category_slots[0]

## ── 测试固件：走一遍"创建角色→调研→选门面→选品类→开业"的真实流程 ──
func _setup_fixture() -> void:
	var create_result := GameManager.create_character({
		"player_name": "测试员",
		"gender": "male",
		"age": 28,
		"difficulty_id": "normal",
		"trait_ids": [],
	})
	if not create_result.success:
		push_error("测试固件搭建失败：create_character -> %s" % create_result.reason)
		return

	var region: RegionData = GameManager.all_regions[0]
	var required_familiarity := GameManager.player_state.get_required_region_familiarity()
	var required_interest := GameManager.player_state.get_required_region_interest()

	## 反复调研直到熟悉度达标——走真实行动流程（真实消耗现金+按默认增量累加），
	## 不直接改字段，这样固件本身也顺带验证了"调研累积熟悉度"这条链路没坏。
	## 加个次数上限防止万一现金耗尽/研究成本异常导致的死循环。
	var research_attempts := 0
	while GameManager.store_state.get_region_familiarity(region.id) < required_familiarity \
			and research_attempts < 50:
		var research_result := GameManager.research_region(region.id)
		if not research_result.success:
			push_error("测试固件搭建失败：research_region -> %s（已尝试%d次）" % [
				research_result.reason, research_attempts
			])
			return
		research_attempts += 1

	## 兴趣度目前没有对应的玩家行动，adjust_region_interest是预留接口，
	## 测试直接调用它把兴趣度堆到达标线即可，不影响上面熟悉度链路的真实性。
	GameManager.adjust_region_interest(region.id, required_interest)

	var select_region_result := GameManager.select_region(region.id)
	if not select_region_result.success:
		push_error("测试固件搭建失败：select_region -> %s" % select_region_result.reason)
		return

	var storefronts := GameManager.get_storefronts_for_region(region.id)
	var storefront: StorefrontData = null
	for sf in storefronts:
		if not sf.supported_categories.is_empty():
			storefront = sf
			break
	if storefront == null and not storefronts.is_empty():
		storefront = storefronts[0]
	if storefront == null:
		push_error("测试固件搭建失败：区域「%s」下没有任何可用门面" % region.name)
		return

	var select_sf_result := GameManager.select_storefront(storefront.id)
	if not select_sf_result.success:
		push_error("测试固件搭建失败：select_storefront -> %s（门面=%s）" % [
			select_sf_result.reason, storefront.name
		])
		return

	var category_id: String = storefront.supported_categories[0]
	var products := GameManager.get_products_for_category(category_id)
	var product_ids: Array[String] = [products[0].id]

	var cat := GameManager.get_category(category_id)
	var add_result := GameManager.add_category_to_store(
		category_id, product_ids, false, cat.suggested_open_hour_ranges.duplicate())
	if not add_result.success:
		push_error("测试固件搭建失败：add_category_to_store -> %s（门面=%s，品类=%s）" % [
			add_result.reason, storefront.name, category_id
		])
		return

	GameManager.open_store()

func _assert(condition: bool, description: String) -> void:
	if condition:
		pass_count += 1
		print("✅ PASS: %s" % description)
	else:
		fail_count += 1
		fail_messages.append(description)
		print("❌ FAIL: %s" % description)


func _print_summary() -> void:
	print("\n========== 测试结果 ==========")
	print("通过：%d ｜ 失败：%d" % [pass_count, fail_count])
	if fail_count > 0:
		print("失败项：")
		for m in fail_messages:
			print("  - %s" % m)


## ── ① 排程冲突 ────────────────────────────────────────────
func _test_schedule_conflict_same_hour() -> void:
	ScheduleManager.reset_for_new_game()

	var r1 := ScheduleManager.add_action_to_schedule("rest_short", 6)
	_assert(r1.can, "①-1 空排程下，6点安排「短暂休息」应该成功")

	var r2 := ScheduleManager.can_schedule_action("rest_short", 6)
	_assert(not r2.can and r2.reason_code == "time_conflict",
		"①-2 同一小时再排另一个行动应该被拒绝，reason_code=time_conflict")

	ScheduleManager.today_schedule.clear()


func _test_schedule_conflict_crosses_midnight() -> void:
	ScheduleManager.reset_for_new_game()

	var check := ScheduleManager.can_schedule_action("sleep", 20)
	_assert(not check.can, "①-3 20点开始的6小时睡眠会跨过24点，应该被拒绝")

	var ok_check := ScheduleManager.can_schedule_action("sleep", 18)
	_assert(ok_check.can, "①-4 18点开始的6小时睡眠正好到24点，应该允许")

	ScheduleManager.today_schedule.clear()


## ── ② 行动允许时间 ────────────────────────────────────────
func _test_deep_inspection_outside_allowed_hours() -> void:
	ScheduleManager.today_schedule.clear()
	GameManager.store_state.inspected_storefront_ids.append("dummy_inspected")

	var too_late := ScheduleManager.can_schedule_action("deep_inspection", 20)
	_assert(not too_late.can and too_late.reason_code == "outside_allowed_hours",
		"②-1 深度勘验不能排在晚夜（20点），reason_code=outside_allowed_hours")

	var ok := ScheduleManager.can_schedule_action("deep_inspection", 10)
	_assert(ok.can, "②-2 深度勘验排在10点（09-18范围内）应该允许")

	GameManager.store_state.inspected_storefront_ids.clear()
	ScheduleManager.today_schedule.clear()


## ── ③ 店铺前置条件 ────────────────────────────────────────
func _test_store_not_open_blocks_actions() -> void:
	ScheduleManager.today_schedule.clear()
	var was_open := GameManager.store_state.is_open
	GameManager.store_state.is_open = false

	var procurement_check := ScheduleManager.can_schedule_action("procurement", 8)
	_assert(not procurement_check.can and procurement_check.reason_code == "store_not_open",
		"③-1 未开业时安排「采购备货」应该被拒绝")

	var supervision_check := ScheduleManager.can_schedule_action("store_supervision", 8)
	_assert(not supervision_check.can and supervision_check.reason_code == "store_not_open",
		"③-2 未开业时安排「亲自坐镇」应该被拒绝")

	var review_check := ScheduleManager.can_schedule_action("closing_review", 8)
	_assert(not review_check.can and review_check.reason_code == "store_not_open",
		"③-3 未开业时安排「收档复盘」应该被拒绝")

	GameManager.store_state.is_open = was_open


func _test_closing_review_requires_settlement_today() -> void:
	ScheduleManager.today_schedule.clear()
	var backup_history: Array[Dictionary] = GameManager.store_state.daily_history.duplicate()
	GameManager.store_state.daily_history.clear()

	var check := ScheduleManager.can_schedule_action("closing_review", 20)
	_assert(not check.can and check.reason_code == "no_business_today",
		"③-4 今天还没结算过任何一单时，「收档复盘」应该被拒绝")

	GameManager.store_state.daily_history.append({"day": TimeManager.current_day})
	var check2 := ScheduleManager.can_schedule_action("closing_review", 20)
	_assert(check2.can, "③-5 今天已有结算记录后，「收档复盘」应该允许")

	GameManager.store_state.daily_history = backup_history
	ScheduleManager.today_schedule.clear()


## ── ④ 疲惫倍率 ────────────────────────────────────────────
func _test_fatigue_tiers() -> void:
	var t0 := ScheduleConfig.get_fatigue_tier(0.0)
	_assert(t0.state == "normal", "④-1 已工作0小时应该是normal")

	var t8 := ScheduleConfig.get_fatigue_tier(8.0)
	_assert(t8.state == "tired" and is_equal_approx(t8.energy_mult, 1.25),
		"④-2 已工作8小时后接下来这1小时（第9小时）应该用tired倍率")

	var t7 := ScheduleConfig.get_fatigue_tier(7.0)
	_assert(t7.state == "normal",
		"④-2b 已工作7小时后接下来这1小时（第8小时）应该仍是normal")

	var t9 := ScheduleConfig.get_fatigue_tier(9.0)
	_assert(t9.state == "tired" and is_equal_approx(t9.energy_mult, 1.25),
		"④-3 已工作9小时应该是tired，精力倍率1.25")

	var t11 := ScheduleConfig.get_fatigue_tier(11.0)
	_assert(t11.state == "overworked" and is_equal_approx(t11.energy_mult, 1.60),
		"④-4 已工作11小时应该是overworked，精力倍率1.60")

	var t13 := ScheduleConfig.get_fatigue_tier(13.0)
	_assert(t13.state == "exhausted" and is_equal_approx(t13.energy_mult, 2.00),
		"④-5 已工作13小时应该是exhausted，精力倍率2.00")


func _test_day_rollover_and_overwork_penalty() -> void:
	var player := GameManager.player_state
	player.work_hours_today = 11.0
	var energy_before := player.energy
	player.start_new_day()
	_assert(player.work_hours_today == 0.0, "④-6 跨天后work_hours_today应该归零")
	_assert(player.fatigue_state == "normal", "④-7 跨天后疲惫状态应该重置为normal")
	_assert(player.energy < energy_before or player.energy_debt > 0.0,
		"④-8 前一天工作超过10小时，次日精力应该有过劳遗留惩罚")


## ── ⑤ 精力透支与恢复 ──────────────────────────────────────
func _test_energy_debt_and_recovery() -> void:
	var p := PlayerState.new()
	p.max_energy = 100.0
	p.energy = 5.0
	p.energy_debt = 0.0

	p.apply_energy_delta(-20.0)
	_assert(is_equal_approx(p.energy, 0.0), "⑤-1 精力扣到负数时应该截到0")
	_assert(is_equal_approx(p.energy_debt, 15.0), "⑤-2 超支部分应该记入energy_debt")

	p.apply_energy_delta(10.0)
	_assert(is_equal_approx(p.energy_debt, 5.0), "⑤-3 恢复精力应该优先偿还透支")
	_assert(is_equal_approx(p.energy, 0.0), "⑤-4 透支没还完之前energy应该还是0")

	p.apply_energy_delta(20.0)
	_assert(is_equal_approx(p.energy_debt, 0.0), "⑤-5 透支还完后energy_debt应该归零")
	_assert(is_equal_approx(p.energy, 15.0), "⑤-6 还清透支后剩余部分应该正常加到energy")


## ── ⑥ 自由营业时间段 ──────────────────────────────────────
func _test_open_hour_ranges() -> void:
	var slot := StoreCategorySlot.new()
	slot.open_hour_ranges = [Vector2i(6, 9), Vector2i(18, 24)]

	_assert(slot.is_open_at_hour(7), "⑥-1 7点应该在[6,9)范围内，判定营业")
	_assert(not slot.is_open_at_hour(9), "⑥-2 9点是区间右端开区间，不应该算营业")
	_assert(not slot.is_open_at_hour(12), "⑥-3 12点在两段之间的空档，不应该营业")
	_assert(slot.is_open_at_hour(23), "⑥-4 23点应该在[18,24)范围内，判定营业")
	_assert(not slot.is_open_at_hour(0), "⑥-5 0点不在任何配置区间内，不应该营业")


func _test_store_supervision_operating_hour_check() -> void:
	var slot := _ensure_test_category_slot()
	ScheduleManager.today_schedule.clear()
	var backup_ranges: Array[Vector2i] = slot.open_hour_ranges.duplicate()
	slot.open_hour_ranges = [Vector2i(9, 12)]

	var check_inside := ScheduleManager.can_schedule_action("store_supervision", 9)
	_assert(check_inside.can, "⑥-6 营业时间[9,12)内排「亲自坐镇」应该允许")

	var check_outside := ScheduleManager.can_schedule_action("store_supervision", 14)
	_assert(not check_outside.can and check_outside.reason_code == "store_not_operating",
		"⑥-7 营业时间之外排「亲自坐镇」应该被拒绝，reason_code=store_not_operating")
	_assert(check_outside.reason.find("下次营业时间") >= 0,
		"⑥-8 拒绝原因里应该包含下次营业时间提示")

	slot.open_hour_ranges = backup_ranges
	ScheduleManager.today_schedule.clear()


## ── ⑦ 每小时执行生命周期 ──────────────────────────────────
func _test_hourly_execution_lifecycle() -> void:
	ScheduleManager.today_schedule.clear()
	ScheduleManager.completed_entries_today.clear()
	ScheduleManager.current_action = null
	var player := GameManager.player_state
	player.max_energy = 100.0        # ← 新增这一行
	player.energy = 100.0
	player.energy_debt = 0.0
	player.work_hours_today = 0.0

	## ── 子测试1：短暂休息，自然跑完1小时 ──
	var start_result := ScheduleManager.start_action_now("rest_short")
	_assert(start_result.can, "⑦-1 应该能成功开始「短暂休息」")
	_assert(ScheduleManager.current_action != null and ScheduleManager.current_action.is_active,
		"⑦-1b 开始后current_action应该处于激活状态")

	TimeManager._advance(3600.0)

	_assert(ScheduleManager.current_action == null,
		"⑦-2 短暂休息跑满1小时后应该自动结束，current_action清空")
	_assert(ScheduleManager.completed_entries_today.size() == 1,
		"⑦-3 应该产生一条已完成记录")

	var record1: ScheduledActionEntry = ScheduleManager.completed_entries_today[0]
	_assert(record1.status == "completed", "⑦-4 记录状态应该是completed")
	_assert(is_equal_approx(record1.hours_completed, 1.0),
		"⑦-5 hours_completed应该约等于1.0")
	_assert(player.energy > 99.0,
		"⑦-6 短暂休息应该恢复精力（不超过max_energy封顶）")
	_assert(is_equal_approx(player.work_hours_today, 0.0),
		"⑦-7 短暂休息不计入work_hours_today（work_hour_counting=false）")

	ScheduleManager.completed_entries_today.clear()

	## ── 子测试2：多小时行动中途喊停，检查连续（非整点）时长结算 ──
	var multi_result := ScheduleManager.start_action_now("procurement")
	_assert(multi_result.can, "⑦-8 应该能成功开始「采购备货」")

	TimeManager._advance(1800.0)   # 只推进30分钟
	_assert(ScheduleManager.current_action != null,
		"⑦-9 半小时后行动应该还在进行中（procurement时长2小时）")

	ScheduleManager.stop_current_action()
	_assert(ScheduleManager.current_action == null,
		"⑦-10 提前停止后current_action应该清空")

	var record2: ScheduledActionEntry = ScheduleManager.completed_entries_today.back()
	_assert(is_equal_approx(record2.hours_completed, 0.5),
		"⑦-11 提前停止在30分钟处，hours_completed应该精确约等于0.5（连续时长，不再量化到整点）")

	ScheduleManager.completed_entries_today.clear()

	## ── 子测试3：亲自坐镇，owner_present在开始/结束瞬间就切换，不用等到整点 ──
	var slot := _ensure_test_category_slot()
	var backup_ranges: Array[Vector2i] = slot.open_hour_ranges.duplicate()
	slot.open_hour_ranges = [Vector2i(int(TimeManager.get_hour_of_day()), 24)]

	var supervision_result := ScheduleManager.start_action_now("store_supervision")
	_assert(supervision_result.can, "⑦-13 应该能成功开始「亲自坐镇」")
	_assert(GameManager.store_state.owner_present == true,
		"⑦-14 亲自坐镇开始的瞬间owner_present应该立刻为true，不用等满1小时")

	ScheduleManager.stop_current_action()
	_assert(GameManager.store_state.owner_present == false,
		"⑦-15 亲自坐镇结束后owner_present应该立刻恢复false")

	slot.open_hour_ranges = backup_ranges
	ScheduleManager.completed_entries_today.clear()

	## ── 子测试4：跨疲惫阈值的分段结算 ──
	player.max_energy = 100.0
	player.energy = 100.0
	player.energy_debt = 0.0
	player.work_hours_today = 7.0

	var fatigue_test_result := ScheduleManager.start_action_now("procurement")
	_assert(fatigue_test_result.can, "⑦-16 应该能开始行动测试疲惫分段")

	TimeManager._advance(3600.0 * 2.0)   # procurement时长2小时，跑满

	var record3: ScheduledActionEntry = ScheduleManager.completed_entries_today.back()
	_assert(record3.status == "completed", "⑦-17 跑满后应该是completed")

	## 预期：第1段(cursor 7→8)用normal倍率1.0，第2段(cursor 8→9)用tired倍率1.25
	## procurement每小时基础消耗9.0精力，预期总消耗 = 9*1*1.0 + 9*1*1.25 = 20.25
	var expected_cost := 9.0 * 1.0 * 1.0 + 9.0 * 1.0 * 1.25
	var actual_cost := 100.0 - player.energy
	_assert(is_equal_approx(actual_cost, expected_cost),
		"⑦-18 跨越8小时疲惫阈值时应该分段结算，预期消耗%.2f，实际消耗%.2f" % [
			expected_cost, actual_cost
		])
	_assert(is_equal_approx(player.work_hours_today, 9.0),
		"⑦-19 work_hours_today应该正确累加到9.0（7+2）")
