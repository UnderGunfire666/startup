extends PanelContainer

@onready var label: RichTextLabel = $MarginContainer/RichTextLabel

func _ready() -> void:
	label.text = "[color=gray]尚无结算记录。请在经营控制面板点击「推进到下一时段并结算」，或使用调试面板应用验收场景。[/color]"

func display(result: SettlementResult) -> void:
	if result == null:
		label.text = "[color=gray]尚无结算记录。请点击「推进到下一时段并结算」。[/color]"
		return

	var t: String = ""
	var slot_name: String = SettlementConfig.SLOT_NAMES.get(result.slot, result.slot)

	if not result.is_open:
		t += "[color=orange]⛔ 第%d天 · %s — 本时段不营业[/color]\n" \
			 % [result.day, slot_name]
		t += result.not_open_reason + "\n"
		label.text = t
		return

	t += "[b]═══ 第%d天 · %s 结算报告 ═══[/b]\n\n" % [result.day, slot_name]

	t += "[b]【客流漏斗】[/b]\n"
	t += "  区域时段基础人流：%.0f 人/小时\n" % result.slot_foot_traffic
	t += "  可触达人流：%.0f 人\n" % result.reachable_traffic
	t += "  到店率：%.2f%%  → 进店 %d 人\n" \
		 % [result.entry_rate * 100.0, result.visitors]
	t += "  成交率：%.2f%%  → 理论订单 %d 单\n" \
		 % [result.conversion_rate * 100.0, result.theoretical_orders]
	t += "  接待上限：%d 单 / 库存上限：%d 单\n" \
		 % [result.slot_capacity, result.inventory_limit]
	t += "  [b]实际订单：%d 单[/b]\n\n" % result.actual_orders

	t += "[b]【未成交原因】[/b]\n"
	t += "  未进店：%d 人  |  进店未下单：%d 人\n" \
		 % [result.lost_no_entry, result.lost_no_conversion]
	if result.lost_capacity > 0:
		t += "  [color=orange]容量不足损失：%d 单[/color]\n" % result.lost_capacity
	if result.lost_inventory > 0:
		t += "  [color=red]库存不足损失：%d 单[/color]\n" % result.lost_inventory
	t += "\n"

	t += "[b]【时段财务】[/b]\n"
	t += "  营业收入：+%.0f 元\n" % result.revenue
	t += "  食材成本：-%.0f 元\n" % result.ingredient_cost
	t += "  员工成本：-%.0f 元\n" % result.staff_cost
	t += "  租金分摊：-%.0f 元\n" % result.rent_cost
	t += "  库存损耗：-%.0f 元\n" % result.waste_cost
	var profit_color: String = "green" if result.profit >= 0 else "red"
	t += "  [color=%s][b]时段利润：%+.0f 元[/b][/color]\n\n" \
		 % [profit_color, result.profit]

	t += "[b]【状态变化】[/b]\n"
	var rep_color: String = "green" if result.reputation_delta >= 0 else "red"
	t += "  口碑：[color=%s]%+.1f[/color]  " % [rep_color, result.reputation_delta]
	t += "  压力：+%.1f\n\n" % result.stress_delta

	if result.top_positive.size() > 0:
		t += "[b]✅ 主要正面因素：[/b]\n"
		for s in result.top_positive:
			t += "  · " + s + "\n"
		t += "\n"
	if result.top_negative.size() > 0:
		t += "[b]⚠️ 主要负面因素：[/b]\n"
		for s in result.top_negative:
			t += "  · " + s + "\n"

	label.text = t
