extends PopupPanel
## 晚夜结算后的日结面板：聚合当天全部经营数据 + 当日行动执行情况。
## 点击按钮关闭并进入新的一天。

signal day_confirmed

@onready var rich_text: RichTextLabel = $MarginContainer/VBox/RichTextLabel
@onready var confirm_button: Button = $MarginContainer/VBox/ConfirmButton


func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm_pressed)


func show_summary(day: int, summary: Dictionary) -> void:
	rich_text.text = _format_summary(day, summary)
	popup_centered(Vector2(520, 620))


func _on_confirm_pressed() -> void:
	hide()
	day_confirmed.emit()


func _format_summary(day: int, s: Dictionary) -> String:
	var state := GameManager.store_state
	var player := GameManager.player_state
	var text := "[b]═══ 第%d天 · 日结报告 ═══[/b]\n\n" % day

	text += "[b]【当日财务汇总】[/b]\n"
	text += "营业收入：+%.0f 元\n" % s.revenue
	text += "食材成本：-%.0f 元\n" % s.ingredient_cost
	text += "员工成本：-%.0f 元\n" % s.staff_cost
	text += "租金成本：-%.0f 元\n" % s.rent_cost
	text += "水电成本：-%.0f 元\n" % s.utility_cost
	text += "\u539f\u6599\u635f\u8017\uff1a\u5236\u4f5c\u4e0e\u8fc7\u671f\u635f\u8017\u5df2\u4ece\u5e93\u5b58\u4e2d\u6263\u9664\uff08\u8be6\u60c5\u89c1\u5386\u53f2\u8bb0\u5f55\uff09\n"

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
		s.stress_delta, player.stress
	]

	text += "[b]当前现金：%.0f 元[/b]\n" % player.cash

	if player.cash < 0.0:
		text += "\n[color=red][b]⚠ 现金已为负，门店面临倒闭风险！[/b][/color]\n"
	elif player.stress >= SettlementConfig.STRESS_HIGH_THRESHOLD:
		text += "\n[color=orange]⚠ 压力值偏高，可能影响服务质量[/color]\n"

	text += _format_action_summary(day)
	text += _format_energy_summary(player)

	return text


## 汇总当天已经结束的每个行动（无论是自然跑完、提前停止还是失败），
## 以及店铺营业期间玩家的坐镇覆盖率。
func _format_action_summary(_day: int) -> String:
	var text := "\n[b]【当日行动记录】[/b]\n"

	var day_entries: Array[ScheduledActionEntry] = ScheduleManager.completed_entries_today
	if day_entries.is_empty():
		text += "（今天没有完成任何行动）\n"
	else:
		for e in day_entries:
			var action := ScheduleActionData.get_action(e.action_id)
			var name := action.name if action != null else e.action_id
			var icon := "✅" if e.status == "completed" else "⚠"

			var target_text := ""
			if e.target_id != "":
				var storefront := GameManager.get_storefront(e.target_id)
				if storefront != null:
					target_text = "（目标：%s）" % storefront.name

			text += "%s %s%s：实际进行 %.2f 小时（计划上限 %d 小时）" % [
				icon, name, target_text, e.hours_completed, e.duration_hours,
			]
			if e.status == "failed" and e.failure_reason != "":
				text += " ｜原因：%s" % e.failure_reason
			text += "\n"

	var operating_hours := ScheduleManager.operating_hours_today
	var supervising_hours := ScheduleManager.supervising_hours_today
	if operating_hours > 0:
		var coverage := float(supervising_hours) / float(operating_hours) * 100.0
		text += "\n店铺营业时间共%d小时，其中亲自坐镇%d小时（%.0f%%）\n" % [
			operating_hours, supervising_hours, coverage
		]

	return text


func _format_energy_summary(player: PlayerState) -> String:
	var text := "\n[b]【今日精力/疲惫】[/b]\n"
	text += "疲惫状态：%s ｜ 累计工作 %.2f 小时\n" % [
		ScheduleConfig.FATIGUE_STATE_NAMES.get(player.fatigue_state, player.fatigue_state),
		player.work_hours_today,
	]
	if player.energy_debt > 0.0:
		text += "[color=red]精力透支：%.1f 点[/color]\n" % player.energy_debt
	else:
		text += "精力：%.1f / %.0f\n" % [player.energy, player.max_energy]
	return text
