extends Node
## UI 状态契约测试。
##
## 验证 UI 对“无角色 / 有角色无企划 / 有企划”的状态映射，
## 防止 UI 再次把 PlayerState 与 Store 混为一谈。

var _pass_count: int = 0
var _fail_count: int = 0
var _action_panel: PanelContainer
var _operation_panel: PanelContainer
var _procurement_panel: PanelContainer


func _ready() -> void:
	print("========== UI 状态契约测试开始 ==========")
	_mount_panels()
	await get_tree().process_frame
	_test_no_character()
	_test_character_without_store()
	_test_store_created()
	_test_second_store_switch()
	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("🎉 UI 状态契约全部通过")
	else:
		print("⚠ UI 状态契约存在失败")


func _mount_panels() -> void:
	_action_panel = preload("res://scenes/panels/ActionPanel.tscn").instantiate()
	_operation_panel = preload("res://scenes/panels/OperationPanel.tscn").instantiate()
	_procurement_panel = preload("res://scenes/panels/ProcurementPanel.tscn").instantiate()
	add_child(_action_panel)
	add_child(_operation_panel)
	add_child(_procurement_panel)


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
	_action_panel.refresh()
	_operation_panel.refresh_display()
	_procurement_panel.refresh()

	var action_status: Label = _action_panel.get_node("MarginContainer/RootVBox/StatusBox/StoreStatusLabel")
	var operation_status: Label = _operation_panel.get_node("VBox/OpenStatusLabel")
	var procurement_status: Label = _procurement_panel.get_node("MarginContainer/VBox/StatusLabel")
	_check(action_status.text == "店铺状态：尚未创建角色", "ActionPanel应显示尚未创建角色")
	_check(operation_status.text == "⚠ 请先创建角色", "OperationPanel应提示先创建角色")
	_check(procurement_status.text == "请先创建角色。", "ProcurementPanel应提示先创建角色")


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
	_action_panel.refresh()
	_operation_panel.refresh_display()
	_procurement_panel.refresh()

	var action_status: Label = _action_panel.get_node("MarginContainer/RootVBox/StatusBox/StoreStatusLabel")
	var operation_status: Label = _operation_panel.get_node("VBox/OpenStatusLabel")
	var operation_pause: Button = _operation_panel.get_node("VBox/SpeedRow/PauseButton")
	var procurement_status: Label = _procurement_panel.get_node("MarginContainer/VBox/StatusLabel")
	_check(action_status.text == "店铺状态：尚未创建开店企划", "ActionPanel应显示尚未创建开店企划")
	_check(operation_status.text == "尚未创建开店企划，请前往「我的店铺」创建", "OperationPanel应提示创建开店企划")
	_check(not operation_pause.disabled, "有角色无企划时OperationPanel时间控制仍应可用")
	_check(procurement_status.text == "请先在「我的店铺」创建开店企划。", "ProcurementPanel应提示创建开店企划")


func _test_store_created() -> void:
	print("\n── 3. 有当前企划 ──")
	var result: Dictionary = GameManager.create_new_store("UI状态首店")
	_check(bool(result.get("success", false)), "创建企划应成功")
	_action_panel.refresh()
	_operation_panel.refresh_display()
	_procurement_panel.refresh()

	var action_status: Label = _action_panel.get_node("MarginContainer/RootVBox/StatusBox/StoreStatusLabel")
	var operation_status: Label = _operation_panel.get_node("VBox/OpenStatusLabel")
	var procurement_status: Label = _procurement_panel.get_node("MarginContainer/VBox/StatusLabel")
	_check(action_status.text == "店铺状态：尚未开业", "ActionPanel应显示当前企划尚未开业")
	_check(not operation_status.text.contains("尚未创建开店企划"), "OperationPanel不应继续显示无企划状态")
	_check(procurement_status.text != "请先在「我的店铺」创建开店企划。", "ProcurementPanel不应继续显示无企划状态")


func _test_second_store_switch() -> void:
	print("\n── 4. 多Store切换 ──")
	var first_id: String = GameManager.active_store_id
	var result: Dictionary = GameManager.create_new_store("UI状态分店")
	var second_id: String = str(result.get("store_id", ""))
	_check(bool(result.get("success", false)), "创建第二个企划应成功")
	_check(second_id != "" and second_id != first_id, "第二个企划应拥有不同ID")
	_action_panel.refresh()
	_operation_panel.refresh_display()
	_procurement_panel.refresh()

	var action_status: Label = _action_panel.get_node("MarginContainer/RootVBox/StatusBox/StoreStatusLabel")
	_check(action_status.text == "店铺状态：尚未开业", "切到第二企划后ActionPanel应反映当前企划")
	_check(GameManager.store_state != null and GameManager.store_state.id == second_id, "UI测试结束时store_state应指向第二企划")
