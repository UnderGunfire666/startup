extends Node
## TimeManager 时间边界回归测试。
## 重点验证：
## 1. reset() 后第一小时是 08:00→09:00，并以 08:00 作为完成slot。
## 2. 连续小时依次完成 09:00、10:00。
## 3. 23:00→00:00 跨日时完成的是第1天23:00 slot。

var _pass_count: int = 0
var _fail_count: int = 0
var _slot_events: Array[Dictionary] = []
var _day_events: Array[Dictionary] = []


func _ready() -> void:
	TimeManager.slot_completed.connect(_on_slot_completed)
	TimeManager.day_completed.connect(_on_day_completed)

	_test_first_slot()
	_test_hour_sequence()
	_test_day_boundary()

	print("========== TimeManager边界测试结束：%d 通过 / %d 失败 ==========" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("🎉 TimeManager slot边界通过")
	else:
		print("⚠ TimeManager边界测试存在失败")

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


func _prepare_game() -> void:
	GameManager.start_new_game()
	var character_result: Dictionary = GameManager.create_character({
		"player_name": "时间边界测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": ["energetic"],
	})
	_check(bool(character_result.get("success", false)), "边界测试角色创建应成功")
	TimeManager.reset()
	_slot_events.clear()
	_day_events.clear()


func _test_first_slot() -> void:
	print("\n── 第一小时：08:00→09:00 ──")
	_prepare_game()

	_check(TimeManager.current_day == 1, "reset后current_day应为1")
	_check(TimeManager.get_current_hour_int() == 8, "reset后当前小时应为08")

	TimeManager._advance(3600.0)

	_check(TimeManager.get_current_hour_int() == 9, "推进1小时后当前小时应为09")
	_check(_slot_events.size() == 1, "08:00→09:00应恰好完成1个slot")
	if _slot_events.size() == 1:
		_check(int(_slot_events[0].get("day", 0)) == 1, "第一slot应属于第1天")
		_check(str(_slot_events[0].get("slot", "")) == "08:00", "第一slot应标记为08:00，而不是00:00/-1:00")


func _test_hour_sequence() -> void:
	print("\n── 连续小时：09:00→10:00→11:00 ──")
	_prepare_game()

	TimeManager._advance(3600.0)
	TimeManager._advance(3600.0)
	TimeManager._advance(3600.0)

	_check(_slot_events.size() == 3, "连续推进3小时应完成3个slot")
	if _slot_events.size() == 3:
		_check(str(_slot_events[0].get("slot", "")) == "08:00", "第1个slot应为08:00")
		_check(str(_slot_events[1].get("slot", "")) == "09:00", "第2个slot应为09:00")
		_check(str(_slot_events[2].get("slot", "")) == "10:00", "第3个slot应为10:00")


func _test_day_boundary() -> void:
	print("\n── 跨日：23:00→00:00 ──")
	_prepare_game()

	## 15小时：08:00→23:00；再1小时跨到第2天00:00。
	TimeManager._advance(15.0 * 3600.0)
	_slot_events.clear()
	_day_events.clear()

	_check(TimeManager.current_day == 1, "到23:00时仍应是第1天")
	_check(TimeManager.get_current_hour_int() == 23, "到23:00时当前小时应为23")

	TimeManager._advance(3600.0)

	_check(TimeManager.current_day == 2, "23:00→00:00后应进入第2天")
	_check(TimeManager.get_current_hour_int() == 0, "跨日后当前小时应为00")
	_check(_slot_events.size() == 1, "跨日这一小时应恰好完成1个slot")
	if _slot_events.size() == 1:
		_check(int(_slot_events[0].get("day", 0)) == 1, "跨日完成的slot仍属于第1天")
		_check(str(_slot_events[0].get("slot", "")) == "23:00", "跨日完成的slot应标记为23:00")

	_check(_day_events.size() == 1, "跨日应产生1次day_completed")
	if _day_events.size() == 1:
		_check(int(_day_events[0].get("day", 0)) == 1, "day_completed应结算刚结束的第1天")


func _on_slot_completed(day: int, slot: String, _results: Array) -> void:
	_slot_events.append({"day": day, "slot": slot})


func _on_day_completed(day: int, _summary: Dictionary) -> void:
	_day_events.append({"day": day})
