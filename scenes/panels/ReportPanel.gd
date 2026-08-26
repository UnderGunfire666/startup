extends PanelContainer

@onready var label: RichTextLabel = $MarginContainer/RichTextLabel


func _ready() -> void:
	_show_empty_message("\u6682\u65e0\u7ed3\u7b97\u8bb0\u5f55\u3002\u8425\u4e1a\u4e00\u4e2a\u65f6\u6bb5\u540e\uff0c\u6b64\u5904\u4f1a\u663e\u793a\u5ba2\u6d41\u3001\u6392\u961f\u3001\u5e93\u5b58\u4e0e\u635f\u76ca\u7684\u5177\u4f53\u539f\u56e0\u3002")


func display(results: Array) -> void:
	var product_results: Array[SettlementResult] = []
	var overhead_results: Array[SettlementResult] = []
	for item in results:
		if not (item is SettlementResult):
			continue
		if item.is_store_overhead:
			overhead_results.append(item)
		else:
			product_results.append(item)
	if product_results.is_empty() and overhead_results.is_empty():
		_show_empty_message("\u672c\u65f6\u6bb5\u6ca1\u6709\u53ef\u5c55\u793a\u7684\u7ed3\u7b97\u8bb0\u5f55\u3002")
		return

	var blocks: Array[String] = []
	var awareness_summary := _format_awareness_summary()
	if not awareness_summary.is_empty():
		blocks.append(awareness_summary)
	for result in product_results:
		blocks.append(_format_product(result))
	for result in overhead_results:
		blocks.append(_format_overhead(result))
	label.text = "\n[color=gray]------------------------------------------------[/color]\n\n".join(blocks)
	label.scroll_to_line(0)


func _format_awareness_summary() -> String:
	var store := GameManager.get_active_store()
	if store == null or store.last_awareness_update.is_empty():
		return ""
	var snapshot := store.last_awareness_update
	var storefront := GameManager.get_storefront(str(snapshot.get("storefront_id", "")))
	var storefront_name := storefront.name if storefront != null else str(snapshot.get("storefront_id", "unknown storefront"))
	var lines: Array[String] = []
	lines.append("[b]线下知名度 | 第 %d 日 %02d:00[/b]" % [int(snapshot.get("day", 0)), int(snapshot.get("hour", 0))])
	lines.append("门面：%s  |  半径：%.1f  |  道路曝光修正：x%.2f" % [storefront_name, float(snapshot.get("awareness_radius", 0.0)), float(snapshot.get("awareness_exposure_modifier", 1.0))])
	var coverage: Dictionary = snapshot.get("coverage_ratios", {})
	var awareness: Dictionary = snapshot.get("current_awareness", {})
	var exposure_by_block: Dictionary = snapshot.get("exposure_by_block", {})
	var word_of_mouth_by_block: Dictionary = snapshot.get("word_of_mouth_by_block", {})
	if coverage.is_empty():
		lines.append("[color=gray]本时段没有覆盖到有效区块，因此没有获得线下知名度。[/color]")
	else:
		lines.append("[b]当前覆盖与知名度[/b]")
		for raw_block_id in coverage.keys():
			var block_id := str(raw_block_id)
			var block := GameManager.get_block(block_id)
			var block_name := block.name if block != null else block_id
			lines.append("- %s：覆盖 %.0f%%，知名度 %.2f" % [block_name, float(coverage[raw_block_id]) * 100.0, float(awareness.get(block_id, 0.0))])
	var exposure_gain := float(snapshot.get("exposure_base_gain", 0.0))
	var word_of_mouth_gain := float(snapshot.get("word_of_mouth_base_gain", 0.0))
	var total_gain := float(snapshot.get("total_gain", 0.0))
	lines.append("[b]刚完成时段增长[/b]  道路曝光 +%.3f  |  成交口碑 +%.3f  |  实际新增 +%.3f" % [exposure_gain, word_of_mouth_gain, total_gain])
	if total_gain <= 0.0:
		lines.append("[color=gray]没有增长：没有有效覆盖或道路曝光，或覆盖区块已到上限。成交口碑还需要本时段实际成交。[/color]")
	else:
		for raw_block_id in coverage.keys():
			var block_id := str(raw_block_id)
			var block := GameManager.get_block(block_id)
			var block_name := block.name if block != null else block_id
			var exposure_delta := float(exposure_by_block.get(block_id, 0.0))
			var word_of_mouth_delta := float(word_of_mouth_by_block.get(block_id, 0.0))
			if exposure_delta > 0.0 or word_of_mouth_delta > 0.0:
				lines.append("- %s：曝光 +%.3f，口碑 +%.3f" % [block_name, exposure_delta, word_of_mouth_delta])
	var sources: Array = snapshot.get("destination_sources", [])
	if sources.is_empty():
		lines.append("跨区目的性客流：当前没有满足口碑、知名度与距离条件的来源区块。")
	else:
		var source_names: Array[String] = []
		for source in sources:
			var source_block := GameManager.get_block(str(source.get("block_id", "")))
			var source_name := source_block.name if source_block != null else str(source.get("block_id", "unknown"))
			source_names.append("%s %.1f" % [source_name, float(source.get("estimated_visitors", 0.0))])
		lines.append("跨区目的性客流来源：%s" % "、".join(source_names))
	return "\n".join(lines)


func _show_empty_message(message: String) -> void:
	label.text = "[color=gray]%s[/color]" % message
	label.scroll_to_line(0)


func _format_product(r: SettlementResult) -> String:
	var title := "[b]\u7b2c %d \u65e5 %s | %s - %s[/b]" % [r.day, r.slot, r.category_name, r.product_name]
	var lines: Array[String] = [title]
	if not r.is_open:
		lines.append("[color=orange]\u672a\u53c2\u4e0e\u8425\u4e1a[/color]  \u539f\u56e0\uff1a%s" % r.not_open_reason)
		lines.append("\u6f5c\u5728\u8fdb\u5e97\u5ba2\u6d41\uff1a%d  |  \u5f53\u524d\u4eba\u624b\u6548\u80fd\uff1a%.2f" % [r.base_visitors, r.staffing_power])
		return "\n".join(lines)

	lines.append("[b]\u5ba2\u6d41\u6f0f\u6597[/b]  \u5546\u5708\u6709\u6548\u5ba2\u6d41 %.0f -> \u53ef\u89e6\u8fbe %.0f -> \u5b9e\u9645\u8fdb\u5e97 %d -> \u60f3\u4e0b\u5355 %d -> \u6210\u4ea4 %d" % [r.slot_foot_traffic, r.reachable_traffic, r.visitors, r.theoretical_orders, r.actual_orders])
	lines.append("\u8f6c\u5316\u7387\uff1a%.1f%%  |  \u672a\u8fdb\u5e97\uff1a%d  |  \u8fdb\u5e97\u540e\u672a\u4e0b\u5355\uff1a%d" % [r.conversion_rate * 100.0, r.lost_no_entry, r.lost_no_conversion])
	lines.append("[b]\u51fa\u9910\u4e0e\u6392\u961f[/b]  \u5355\u4efd\u9884\u8ba1\u51fa\u9910\uff1a%s  |  \u5f53\u524d\u4eba\u624b\u6548\u80fd\uff1a%.2f" % [_format_seconds(r.service_time_seconds), r.staffing_power])
	lines.append("\u6210\u4ea4\u5ba2\u5e73\u5747\u7b49\u5f85\uff1a%s  |  \u6700\u957f\u7b49\u5f85\uff1a%s  |  \u5ba2\u6237\u5fcd\u8010\u4e0a\u9650\uff1a%s  |  \u56e0\u6392\u961f\u653e\u5f03\uff1a%d" % [_format_seconds(r.average_queue_wait_seconds), _format_seconds(r.max_queue_wait_seconds), _format_seconds(r.queue_patience_seconds), r.lost_capacity])
	lines.append("[b]\u5e93\u5b58\u4e0e\u5546\u54c1[/b]  \u552e\u4ef7\uff1a%.2f\u5143  |  \u672c\u65f6\u6bb5\u539f\u6599\u53ef\u505a\uff1a%d \u5355  |  \u539f\u6599\u4e0d\u8db3\u672a\u6210\u4ea4\uff1a%d \u5355" % [r.unit_price, r.inventory_limit, r.lost_inventory])
	lines.append("\u5236\u4f5c\u539f\u6599\u635f\u8017\uff1a%s\uff08\u5f53\u524d\u603b\u6d88\u8017\u4e3a\u914d\u65b9\u7684 %.0f%%\uff09" % [_format_ingredients(r.preparation_waste_ingredients), r.ingredient_consumption_multiplier * 100.0])
	lines.append("[b]\u635f\u76ca[/b]  \u8425\u6536\uff1a%.2f  |  \u539f\u6599\u6210\u672c\uff08\u542b\u5236\u4f5c\u635f\u8017\uff09\uff1a%.2f  |  \u79df\u91d1\uff1a%.2f  |  \u6c34\u7535\uff1a%.2f  |  \u4eba\u5de5\uff1a%.2f  |  [b]\u5229\u6da6\uff1a%.2f[/b]" % [r.revenue, r.ingredient_cost, r.rent_cost, r.utility_cost, r.staff_cost, r.profit])
	lines.append("\u8f6c\u5316\u4fee\u6b63\uff1a\u5b9a\u4ef7 %+.1f%%\uff0c\u53e3\u7891 %+.1f%%\uff0c\u5e97\u4e3b\u7763\u5bfc %+.1f%%\uff0c\u7279\u8d28 %+.1f%%" % [r.price_modifier * 100.0, r.reputation_modifier * 100.0, r.owner_modifier * 100.0, r.trait_modifier * 100.0])
	if not r.top_positive.is_empty():
		lines.append("[color=green]\u6709\u5229\u56e0\u7d20\uff1a%s[/color]" % "\u3001".join(r.top_positive))
	if not r.top_negative.is_empty():
		lines.append("[color=tomato]\u9700\u5173\u6ce8\uff1a%s[/color]" % "\u3001".join(r.top_negative))
	return "\n".join(lines)


func _format_overhead(r: SettlementResult) -> String:
	return "[b]\u7b2c %d \u65e5 %s | \u95e8\u5e97\u56fa\u5b9a\u5f00\u652f\u4e0e\u539f\u6599\u8fc7\u671f[/b]\n\u623f\u79df\uff1a%.2f  |  \u57fa\u7840\u6c34\u7535\uff1a%.2f  |  \u5458\u5de5\u5de5\u8d44\uff1a%.2f  |  [b]\u5408\u8ba1\uff1a%.2f[/b]\n\u672c\u65f6\u6bb5\u81ea\u7136\u8fc7\u671f\u539f\u6599\uff1a%s" % [r.day, r.slot, r.rent_cost, r.utility_cost, r.staff_cost, -r.profit, _format_ingredients(r.spoilage_ingredients)]


func _format_ingredients(items: Dictionary) -> String:
	if items.is_empty():
		return "\u65e0"
	var parts: Array[String] = []
	for ingredient_id in items:
		var ingredient := GameManager.get_ingredient(str(ingredient_id))
		var name := ingredient.name if ingredient != null else str(ingredient_id)
		parts.append("%s %.2f" % [name, float(items[ingredient_id])])
	return "\u3001".join(parts)


func _format_seconds(value: float) -> String:
	if value < 60.0:
		return "%.0f\u79d2" % value
	return "%.1f\u5206\u949f" % (value / 60.0)
