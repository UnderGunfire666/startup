extends PopupPanel
## 晚夜结算后的日结面板：聚合当天全部时段（含门店整体固定成本）的经营数据。
## 展示财务汇总、订单与损失、口碑压力变化，点击按钮关闭并进入新的一天。

signal day_confirmed

@onready var rich_text: RichTextLabel = $MarginContainer/VBox/RichTextLabel
@onready var confirm_button: Button = $MarginContainer/VBox/ConfirmButton

func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm_pressed)

func show_summary(day: int, summary: Dictionary) -> void:
	rich_text.text = _format_summary(day, summary)
	popup_centered(Vector2(480, 460))

func _on_confirm_pressed() -> void:
	hide()
	day_confirmed.emit()

func _format_summary(day: int, s: Dictionary) -> String:
	var state := GameManager.store_state
	var text := "[b]═══ 第%d天 · 日结报告 ═══[/b]\n\n" % day

	text += "[b]【当日财务汇总】[/b]\n"
	text += "营业收入：+%.0f 元\n" % s.revenue
	text += "食材成本：-%.0f 元\n" % s.ingredient_cost
	text += "员工成本：-%.0f 元\n" % s.staff_cost
	text += "租金成本：-%.0f 元\n" % s.rent_cost
	text += "水电成本：-%.0f 元\n" % s.utility_cost
	text += "库存损耗：-%.0f 元\n" % s.waste_cost

	var profit_color := "green" if s.profit >= 0.0 else "red"
	text += "[color=%s][b]当日利润：%+.0f 元[/b][/color]\n\n" % [profit_color, s.profit]

	text += "[b]【订单与损失】[/b]\n"
	text += "总订单：%d 单 | 缺货损失：%d 单 | 容量损失：%d 单\n\n" % [
		s.actual_orders, s.lost_inventory, s.lost_capacity
	]

	text += "[b]【状态变化】[/b]\n"
	var rep_color := "green" if s.reputation_delta >= 0.0 else "red"
	text += "口碑：[color=%s]%+.1f[/color]  （当前 %.1f / 100）\n" % [
		rep_color, s.reputation_delta, state.reputation
	]
	text += "压力：%+.1f  （当前 %.1f / 100）\n\n" % [
		s.stress_delta, state.stress
	]

	text += "[b]当前现金：%.0f 元[/b]\n" % state.cash

	if state.cash < 0.0:
		text += "\n[color=red][b]⚠ 现金已为负，门店面临倒闭风险！[/b][/color]\n"
	elif state.stress >= SettlementConfig.STRESS_HIGH_THRESHOLD:
		text += "\n[color=orange]⚠ 压力值偏高，可能影响服务质量[/color]\n"

	return text
