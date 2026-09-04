extends Node
## UI 状态契约测试。
##
## 验证 UI 对“无角色 / 有角色无企划 / 有企划”的状态映射，
## 防止 UI 再次把 PlayerState 与 Store 混为一谈。

var _pass_count: int = 0
var _fail_count: int = 0
var _operation_panel: PanelContainer
var _procurement_panel: PanelContainer
var _save_load_bar: HBoxContainer
var _event_popup: EventPopup


func _ready() -> void:
	print("========== UI 状态契约测试开始 ==========")
	_mount_panels()
	await get_tree().process_frame
	_test_no_character()
	_test_event_popup_exclusivity()
	_test_character_without_store()
	_test_store_created()
	_test_customer_feed_uses_fixed_pool()
	_test_decision_box()
	_test_interrupt_box()
	_test_second_store_switch()
	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("🎉 UI 状态契约全部通过")
	else:
		print("⚠ UI 状态契约存在失败")
	get_tree().quit(1 if _fail_count > 0 else 0)


func _mount_panels() -> void:
	_operation_panel = preload("res://scenes/panels/OperationPanel.tscn").instantiate()
	_procurement_panel = preload("res://scenes/panels/ProcurementPanel.tscn").instantiate()
	_save_load_bar = preload("res://scenes/panels/SaveLoadBar.tscn").instantiate()
	_event_popup = preload("res://scenes/panels/EventPopup.tscn").instantiate()
	add_child(_operation_panel)
	add_child(_procurement_panel)
	add_child(_save_load_bar)
	add_child(_event_popup)


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("✅ %s" % label)
	else:
		_fail_count += 1
		print("❌ %s" % label)


func _test_no_character() -> void:
	print("\n── 1. 无角色 ──")
	GameManager.start_new_game()
	_operation_panel.refresh_display()
	_procurement_panel.refresh()

	var operation_status: Label = _operation_panel.get_node("VBox/OpenStatusLabel")
	var procurement_status: Label = _procurement_panel.get_node("MarginContainer/VBox/StatusLabel")
	var pause_button: Button = _save_load_bar.get_node("PauseButton")
	_check(pause_button.disabled, "无角色时顶栏时间控制应禁用")
	_check(operation_status.text == "⚠ 请先创建角色", "OperationPanel应提示先创建角色")
	_check(procurement_status.text == "请先创建角色。", "ProcurementPanel应提示先创建角色")


func _test_event_popup_exclusivity() -> void:
	print("\n── 事件弹窗层级 ──")
	_check(_event_popup.exclusive, "全局事件弹窗应为独占窗口，不能被底层时间控件覆盖")


func _test_character_without_store() -> void:
	print("\n── 2. 有角色、无企划 ──")
	var result: Dictionary = GameManager.create_character({
		"player_name": "UI状态测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_check(bool(result.get("success", false)), "创建角色应成功")
	_operation_panel.refresh_display()
	_procurement_panel.refresh()

	var operation_status: Label = _operation_panel.get_node("VBox/OpenStatusLabel")
	var top_speed: Button = _save_load_bar.get_node("Speed1Button")
	var procurement_status: Label = _procurement_panel.get_node("MarginContainer/VBox/StatusLabel")
	_check(operation_status.text == "尚未创建开店企划，请前往「我的店铺」创建", "OperationPanel应提示创建开店企划")
	_check(not top_speed.disabled, "有角色无企划时顶栏时间控制仍应可用")
	_check(procurement_status.text == "请先在「我的店铺」创建开店企划。", "ProcurementPanel应提示创建开店企划")

	var start_result := ScheduleManager.start_action_now("rest_short")
	_check(bool(start_result.get("can", false)), "测试行动应能开始")
	var stop_button: Button = _save_load_bar.get_node("StopActionButton")
	_check(stop_button.visible, "任意行动进行时顶栏应显示结束行动按钮")
	stop_button.emit_signal("pressed")
	_check(ScheduleManager.current_action == null, "点击顶栏结束行动后当前行动应结束")


func _test_store_created() -> void:
	print("\n── 3. 有当前企划 ──")
	var result: Dictionary = GameManager.create_new_store("UI状态首店")
	_check(bool(result.get("success", false)), "创建企划应成功")
	_operation_panel.refresh_display()
	_procurement_panel.refresh()

	var operation_status: Label = _operation_panel.get_node("VBox/OpenStatusLabel")
	var procurement_status: Label = _procurement_panel.get_node("MarginContainer/VBox/StatusLabel")
	_check(not operation_status.text.contains("尚未创建开店企划"), "OperationPanel不应继续显示无企划状态")
	_check(procurement_status.text != "请先在「我的店铺」创建开店企划。", "ProcurementPanel不应继续显示无企划状态")


func _test_customer_feed_uses_fixed_pool() -> void:
	print("\n── 固定容量经营动态 ──")
	var customer_feed: VBoxContainer = _operation_panel.get_node("VBox/CustomerFeedScroll/CustomerFeed")
	for index in range(30):
		_operation_panel._on_customer_event("测试商品%d" % index, true, "", TimeManager.total_game_seconds + index)
	_check(customer_feed.get_child_count() == 20, "经营动态预创建固定数量的文本节点")
	_check(_operation_panel._feed_entries.size() == 20, "经营动态数据缓冲只保留最近20条")
	_check(_operation_panel._feed_entries[0].contains("测试商品10") and _operation_panel._feed_entries.back().contains("测试商品29"), "固定缓冲按原顺序保留最近事件")


func _test_decision_box() -> void:
	print("\n── 4. 营业事件决策 ──")
	_check(_operation_panel.decision_box != null, "OperationPanel应创建事件决策容器")
	EventManager.reset_for_new_game()
	var definition: GameEventDefinition = EventManager.definitions.get("store_activity_partnership")
	var store: Store = GameManager.store_state
	var event: ActiveGameEvent = EventManager._activate(definition, store.id, store.id)
	_check(_operation_panel.decision_box.get_child_count() == 1 + event.options.size(), "营业事件应按定义显示说明与全部决策按钮")
	var option_buttons: Dictionary = {}
	for option in event.options:
		var option_id := str(option.get("id", ""))
		var option_label := str(option.get("label", option_id))
		for child in _operation_panel.decision_box.get_children():
			if child is Button and (child as Button).text.begins_with(option_label):
				option_buttons[option_id] = child as Button
				break
	_check(option_buttons.size() == event.options.size(), "营业事件每个定义选项均应有对应按钮")
	var accept_button: Button = option_buttons.get("accept", null)
	_check(accept_button != null and not accept_button.disabled, "营业事件应提供可用的接受按钮")
	for locked_id in ["terms", "written"]:
		var locked_button: Button = option_buttons.get(locked_id, null)
		var locked_option: Dictionary = {}
		for option in event.options:
			if str(option.get("id", "")) == locked_id:
				locked_option = option
				break
		_check(locked_button != null and locked_button.disabled, "%s 特性选项应保持显示但不可用" % locked_id)
		_check(locked_button != null and locked_button.tooltip_text == str(locked_option.get("locked_reason", "")), "%s 特性选项应显示锁定原因" % locked_id)
	if accept_button != null:
		accept_button.emit_signal("pressed")
	_check(EventManager.pending_decisions.is_empty(), "点击决策按钮后待处理事件应被移除")
	_check(EventManager.get_modifier_total(GameEventDefinition.Scope.STORE, store.id, "natural_visitors_multiplier_add") == 0.15, "接受活动应立即应用客流加成")
	_check(EventManager.event_history.has(event), "已处理决策应进入事件历史")


func _test_interrupt_box() -> void:
	print("\n── 5. 营业紧急事件 ──")
	EventManager.reset_for_new_game()
	var definition: GameEventDefinition = EventManager.definitions.get("store_equipment_failure")
	var store: Store = GameManager.store_state
	EventManager._activate(definition, store.id, store.id)
	_check(_operation_panel.interrupt_box.get_child_count() == 2, "营业紧急事件应显示说明与确认按钮")
	var acknowledge_button: Button = null
	for child in _operation_panel.interrupt_box.get_children():
		if child is Button:
			acknowledge_button = child as Button
			break
	_check(acknowledge_button != null, "营业紧急事件应提供确认按钮")
	if acknowledge_button != null:
		acknowledge_button.emit_signal("pressed")
	_check(EventManager.pending_interrupts.is_empty(), "确认紧急事件后待处理队列应清空")


func _test_second_store_switch() -> void:
	print("\n── 6. 多Store切换 ──")
	var first_id: String = GameManager.active_store_id
	var result: Dictionary = GameManager.create_new_store("UI状态分店")
	var second_id: String = str(result.get("store_id", ""))
	_check(bool(result.get("success", false)), "创建第二个企划应成功")
	_check(second_id != "" and second_id != first_id, "第二个企划应拥有不同ID")
	_operation_panel.refresh_display()
	_procurement_panel.refresh()

	_check(GameManager.store_state != null and GameManager.store_state.id == second_id, "UI测试结束时store_state应指向第二企划")
