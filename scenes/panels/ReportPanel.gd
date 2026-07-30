extends PanelContainer

@onready var label: RichTextLabel = $MarginContainer/RichTextLabel

func _ready() -> void:
	_show_empty_message(
		"尚无结算记录。请在经营控制面板点击「推进到下一时段并结算」。"
	)

func display(results: Array) -> void:
	if results.is_empty():
		_show_empty_message("本时段没有可展示的结算记录。")
		return

	var text := ""
	for i in range(results.size()):
		var result = results[i]
		if result is SettlementResult:
			text += _format_single_result(result)

		if i < results.size() - 1:
			text += "\n[color=gray]────────────────────[/color]\n\n"

	label.text = text if not text.is_empty() else \
		"[color=gray]本时段没有有效的结算记录。[/color]"
	label.scroll_to_line(0)

func _show_empty_message(message: String) -> void:
	label.text = "[color=gray]%s[/color]" % message
	label.scroll_to_line(0)

func _format_single_result(result: SettlementResult) -> String:
	var text := ""
	var slot_name: String = SettlementConfig.SLOT_NAMES.get(result.slot, result.slot)
	var category_label := "「%s」 " % result.category_name \
		if result.category_name != "" else ""

	if not result.is_open:
		text += "[color=orange]⛔ 第%d天 · %s%s — 本时段不营业[/color]\n" % [
			result.day,
			category_label,
			slot_name
		]
		text += result.not_open_reason + "\n"
		return text

	text += "[b]═══ 第%d天 · %s%s 结算报告 ═══[/b]\n\n" % [
		result.day,
		category_label,
		slot_name
	]

	text += "[b]【客流漏斗】[/b]\n"
	text += "区域时段基础人流：%.0f 人/小时\n" % result.slot_foot_traffic
	text += "可触达人流：%.0f 人\n" % result.reachable_traffic
	text += "到店率：%.2f%%  → 进店 %d 人\n" % [
		result.entry_rate * 100.0,
		result.visitors
	]
	text += "成交率：%.2f%%  → 理论订单 %d 单\n" % [
		result.conversion_rate * 100.0,
		result.theoretical_orders
	]
	text += "接待上限：%d 单 / 原材料可售上限：%d 单\n" % [
		result.slot_capacity,
		result.inventory_limit
	]
	text += "[b]实际订单：%d 单[/b]\n\n" % result.actual_orders

	text += "[b]【未成交原因】[/b]\n"
	text += "未进店：%d 人 | 进店未下单：%d 人\n" % [
		result.lost_no_entry,
		result.lost_no_conversion
	]
	if result.lost_capacity > 0:
		text += "[color=orange]容量不足损失：%d 单[/color]\n" % result.lost_capacity
	if result.lost_inventory > 0:
		text += "[color=red]原材料不足损失：%d 单[/color]\n" % result.lost_inventory
	text += "\n"

	text += "[b]【时段财务】[/b]\n"
	text += "营业收入：+%.0f 元\n" % result.revenue
	text += "食材成本：-%.0f 元\n" % result.ingredient_cost
	text += "员工成本：-%.0f 元\n" % result.staff_cost
	text += "租金分摊：-%.0f 元\n" % result.rent_cost
	text += "库存损耗：-%.0f 元\n" % result.waste_cost

	var profit_color := "green" if result.profit >= 0.0 else "red"
	text += "[color=%s][b]时段利润：%+.0f 元[/b][/color]\n\n" % [
		profit_color,
		result.profit
	]

	text += "[b]【状态变化】[/b]\n"
	var reputation_color := "green" if result.reputation_delta >= 0.0 else "red"
	text += "口碑：[color=%s]%+.1f[/color]  压力：%+.1f\n\n" % [
		reputation_color,
		result.reputation_delta,
		result.stress_delta
	]

	if not result.top_positive.is_empty():
		text += "[b]✅ 主要正面因素：[/b]\n"
		for reason in result.top_positive:
			text += "· %s\n" % reason
		text += "\n"

	if not result.top_negative.is_empty():
		text += "[b]⚠ 主要负面因素：[/b]\n"
		for reason in result.top_negative:
			text += "· %s\n" % reason

	return text
