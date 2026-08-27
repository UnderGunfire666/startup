class_name DiscoveryPanel
extends PanelContainer

@onready var label: RichTextLabel = $MarginContainer/RichTextLabel


func _ready() -> void:
	BlockDiscoveryManager.discovery_recorded.connect(_on_discovery_recorded)
	refresh()


func refresh() -> void:
	var history := GameManager.player_state.discovery_history
	if history.is_empty():
		label.text = "[color=gray]暂无发现。前往地图并持续调查区块，人口、人群、时段与商业环境会逐步记录在这里。[/color]"
		return

	var latest_by_key: Dictionary = {}
	for index in range(history.size() - 1, -1, -1):
		var record: Dictionary = history[index]
		var key := "%s:%s" % [record.get("block_id", ""), record.get("discovery_id", "")]
		if not latest_by_key.has(key):
			latest_by_key[key] = record

	var lines: Array[String] = ["[b]当前结论[/b]"]
	var cards: Array = latest_by_key.values()
	cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("game_seconds", 0.0)) > float(b.get("game_seconds", 0.0)))
	for record in cards:
		lines.append("[b]%s · %s[/b]  [color=gray]第%d天 %s %02d:%02d[/color]\n%s" % [
			str(record.get("block_name", "未知区块")), str(record.get("category", "发现")),
			int(record.get("day", 0)), str(record.get("weekday", "")), int(record.get("hour", 0)), _get_record_minute(record), str(record.get("message", "")),
		])

	lines.append("\n[b]发现时间线[/b]")
	for index in range(history.size() - 1, -1, -1):
		var record: Dictionary = history[index]
		var tier_text := "偶发线索" if bool(record.get("occasional", false)) else "了解度第%d档" % int(record.get("tier", 0))
		lines.append("[color=gray]第%d天 %s %02d:%02d · %s[/color] [b]%s[/b]\n%s" % [
			int(record.get("day", 0)), str(record.get("weekday", "")), int(record.get("hour", 0)), _get_record_minute(record), tier_text,
			str(record.get("block_name", "未知区块")), str(record.get("message", "")),
		])
	label.text = "\n[color=gray]────────────────────────────────[/color]\n".join(lines)
	label.scroll_to_line(0)


func _on_discovery_recorded(_record: Dictionary) -> void:
	refresh()


func _get_record_minute(record: Dictionary) -> int:
	## Legacy records did not persist minutes and therefore render as :00.
	return int(record.get("minute", 0))
