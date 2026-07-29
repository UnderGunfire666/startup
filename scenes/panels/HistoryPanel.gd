extends PanelContainer

@onready var label: RichTextLabel = $MarginContainer/RichTextLabel

func _ready() -> void:
	label.text = "[color=gray]暂无历史记录。经营结算后将在此显示。[/color]"

func refresh(history: Array[Dictionary]) -> void:
	if history.is_empty():
		label.text = "[color=gray]暂无历史记录。经营结算后将在此显示。[/color]"
		return

	var t := "[b]═══ 经营历史（最近记录）═══[/b]\n\n"

	var daily: Dictionary = {}
	for entry in history:
		var key: int = entry.day
		if not daily.has(key):
			daily[key] = {revenue=0.0, cost=0.0, profit=0.0,
						  orders=0, rep_delta=0.0, lost_inv=0, lost_cap=0}
		var d: Dictionary = daily[key]
		d.revenue    += entry.revenue
		d.cost       += entry.ingredient_cost + entry.staff_cost \
					 + entry.rent_cost + entry.waste_cost
		d.profit     += entry.profit
		d.orders     += entry.actual_orders
		d.rep_delta  += entry.reputation_delta
		d.lost_inv   += entry.lost_inventory
		d.lost_cap   += entry.lost_capacity
		daily[key] = d

	t += "%-6s %-8s %-8s %-8s %-6s %-6s %-6s\n" \
		 % ["日", "收入", "成本", "利润", "订单", "缺货损", "容量损"]
	t += "─".repeat(55) + "\n"

	var sorted_days: Array = daily.keys()
	sorted_days.sort()
	for d_key in sorted_days:
		var d: Dictionary = daily[d_key]
		var p_color := "green" if d.profit >= 0 else "red"
		t += "第%d天  %.0f  %.0f  [color=%s]%+.0f[/color]  %d  %d  %d\n" \
			 % [d_key, d.revenue, d.cost, p_color, d.profit,
				d.orders, d.lost_inv, d.lost_cap]

	t += "\n[b]── 逐时段记录（最近20条）──[/b]\n"
	var start_idx: int = maxi(0, history.size() - 20)
	var recent: Array = history.slice(start_idx)
	for entry in recent:
		if not entry.is_open:
			t += "D%d·%s [color=gray]不营业[/color]\n" % \
				 [entry.day, SettlementConfig.SLOT_NAMES.get(entry.slot, entry.slot)]
			continue
		var pc := "green" if entry.profit >= 0 else "red"
		t += "D%d·%s  订单%d  收入%.0f  [color=%s]利润%+.0f[/color]  口碑%+.1f\n" \
			 % [entry.day,
				SettlementConfig.SLOT_NAMES.get(entry.slot, entry.slot),
				entry.actual_orders, entry.revenue, pc, entry.profit,
				entry.reputation_delta]

	label.text = t
