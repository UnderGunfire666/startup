extends PanelContainer
## "日程"标签：提前规划一整天的行动。改为逐小时列表展示，而不是双小时格子。

@onready var day_label: Label = $MarginContainer/RootVBox/DayLabel
@onready var status_label: Label = $MarginContainer/RootVBox/StatusLabel
@onready var start_hour_option: OptionButton = \
	$MarginContainer/RootVBox/AddRow/StartHourOption
@onready var action_list: VBoxContainer = \
	$MarginContainer/RootVBox/ActionScroll/ActionList
@onready var hour_list: VBoxContainer = \
	$MarginContainer/RootVBox/HourScroll/HourList

var _last_displayed_hour: int = -1


func _ready() -> void:
	TimeManager.clock_updated.connect(_on_clock_updated)
	ScheduleManager.schedule_changed.connect(_refresh_all)

	_build_start_hour_options()
	_refresh_all()


func refresh() -> void:
	_refresh_all()


func _on_clock_updated(hour: int, _m: int, _s: int, _l: String) -> void:
	_refresh_day_label()
	## 24格视图没必要跟着时钟每帧重绘，小时数变化时再刷新一次即可，
	## 这样能达到跟旧的"每小时一次hour_executed"相同的刷新频率。
	if hour != _last_displayed_hour:
		_last_displayed_hour = hour
		_refresh_hour_list()


func _refresh_all() -> void:
	_refresh_day_label()
	_build_action_list()
	_refresh_hour_list()


func _refresh_day_label() -> void:
	day_label.text = "第 %d 天的日程安排" % TimeManager.current_day


func _build_start_hour_options() -> void:
	start_hour_option.clear()
	for h in range(24):
		start_hour_option.add_item("%02d:00" % h)
		start_hour_option.set_item_metadata(h, h)
	start_hour_option.item_selected.connect(func(_i): _build_action_list())


func _get_selected_start_hour() -> int:
	if start_hour_option.selected < 0:
		return 0
	return int(start_hour_option.get_item_metadata(start_hour_option.selected))


func _build_action_list() -> void:
	for child in action_list.get_children():
		child.queue_free()

	var start_hour := _get_selected_start_hour()

	for action in ScheduleActionData.get_actions():
		var check := ScheduleManager.can_schedule_action(action.id, start_hour)

		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s（%d小时）" % [action.name, action.duration_hours]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var region_option: OptionButton = null
		if action.action_effect_type == "region_research":
			region_option = OptionButton.new()
			region_option.custom_minimum_size = Vector2(120, 0)
			for r in GameManager.all_regions:
				region_option.add_item(r.name)
				region_option.set_item_metadata(region_option.item_count - 1, r.id)
			row.add_child(region_option)

		var add_btn := Button.new()
		if check.can:
			add_btn.text = "加入 %02d:00" % start_hour
		else:
			add_btn.text = "不可用"
			add_btn.disabled = true
			add_btn.tooltip_text = check.reason

		add_btn.pressed.connect(func():
			var target_id := ""
			if region_option != null and region_option.selected >= 0:
				target_id = str(region_option.get_item_metadata(region_option.selected))
			var result := ScheduleManager.add_action_to_schedule(action.id, start_hour, target_id)
			if result.can:
				status_label.text = "✅ 已加入排程"
			else:
				status_label.text = "⚠ %s" % result.reason
			_refresh_all()
		)
		row.add_child(add_btn)
		action_list.add_child(row)


## 24行列表，每行代表一个小时。依次检查：正在进行中的行动 > 排程队列里
## 还没开始的计划 > 今天已经结束的记录，三者覆盖范围可能重叠
## （比如提前排的计划到点后转成了current_action），按"当前状态优先"取第一个匹配的。
func _refresh_hour_list() -> void:
	for child in hour_list.get_children():
		child.queue_free()

	for hour in range(24):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var hour_label := Label.new()
		hour_label.custom_minimum_size = Vector2(60, 0)
		hour_label.text = "%02d:00" % hour
		row.add_child(hour_label)

		var content_label := Label.new()
		content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_label.text = _describe_hour(hour)
		row.add_child(content_label)

		hour_list.add_child(row)


func _describe_hour(hour: int) -> String:
	var current := ScheduleManager.current_action
	if current != null and current.is_active:
		var start_h := int(current.start_game_seconds / 3600.0) % 24
		var action := ScheduleActionData.get_action(current.action_id)
		var end_h := start_h + (action.duration_hours if action != null else 0)
		if hour >= start_h and hour < end_h:
			return _format_entry_text("▶", action, current.target_id, start_h, end_h, -1.0, -1)

	var pending := ScheduleManager.today_schedule.get_entry_for_hour(hour)
	if pending != null:
		var action := ScheduleActionData.get_action(pending.action_id)
		return _format_entry_text("⏳", action, pending.target_id,
			pending.start_hour, pending.get_end_hour(), -1.0, pending.duration_hours)

	for e in ScheduleManager.completed_entries_today:
		if hour >= e.start_hour and hour < e.get_end_hour():
			var action := ScheduleActionData.get_action(e.action_id)
			var icon := "✅" if e.status == "completed" else "⚠"
			return _format_entry_text(icon, action, e.target_id,
				e.start_hour, e.get_end_hour(), e.hours_completed, e.duration_hours)

	return "（空）"


## hours_completed为-1表示"不适用"（还没结束/还不知道实际完成量），
## duration_hours为-1表示"进行中，还不确定要显示的计划时长"（正在执行的current_action已经在别处传了真实值，这里不会用到-1分支）。
func _format_entry_text(
		icon: String, action: ActionDefinition, target_id: String,
		start_h: int, end_h: int, hours_completed: float, duration_hours: int
) -> String:
	var name := action.name if action != null else "未知行动"
	var target_text := ""
	if target_id != "":
		var region := GameManager.get_region(target_id)
		if region != null:
			target_text = "｜目标：%s" % region.name

	if hours_completed >= 0.0:
		return "%s %s（%d-%d时，已完成%.2f/%d小时）%s" % [
			icon, name, start_h, end_h, hours_completed, duration_hours, target_text
		]
	elif duration_hours >= 0:
		return "%s %s（%d-%d时，计划%d小时）%s" % [
			icon, name, start_h, end_h, duration_hours, target_text
		]
	else:
		return "%s %s（%d-%d时，进行中）%s" % [icon, name, start_h, end_h, target_text]
