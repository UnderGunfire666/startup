extends PanelContainer
## 日程面板：排程行动、显示当日12个双小时格、展示执行状态。
## 时间流逝仍由 TimeManager 的暂停/1x/2x/5x 控制（与营业面板共享同一状态），
## 这里只是额外提供一份便于随时操作的入口，方便玩家不用切到"营业"标签。

const HOUR_CELL_LABELS: Array[String] = [
	"00:00-02:00", "02:00-04:00", "04:00-06:00", "06:00-08:00",
	"08:00-10:00", "10:00-12:00", "12:00-14:00", "14:00-16:00",
	"16:00-18:00", "18:00-20:00", "20:00-22:00", "22:00-24:00",
]

@onready var day_hour_label: Label = $MarginContainer/RootVBox/StatusBox/DayHourLabel
@onready var current_action_label: Label = $MarginContainer/RootVBox/StatusBox/CurrentActionLabel
@onready var energy_label: Label = $MarginContainer/RootVBox/StatusBox/EnergyLabel
@onready var fatigue_label: Label = $MarginContainer/RootVBox/StatusBox/FatigueLabel
@onready var store_status_label: Label = $MarginContainer/RootVBox/StatusBox/StoreStatusLabel
@onready var warning_label: Label = $MarginContainer/RootVBox/WarningLabel

@onready var pause_button: Button = $MarginContainer/RootVBox/SpeedRow/PauseButton
@onready var speed1_button: Button = $MarginContainer/RootVBox/SpeedRow/Speed1Button
@onready var speed2_button: Button = $MarginContainer/RootVBox/SpeedRow/Speed2Button
@onready var speed5_button: Button = $MarginContainer/RootVBox/SpeedRow/Speed5Button

@onready var action_list: VBoxContainer = \
	$MarginContainer/RootVBox/SplitBox/LeftPanel/ActionScroll/ActionList
@onready var start_hour_option: OptionButton = \
	$MarginContainer/RootVBox/SplitBox/RightPanel/AddRow/StartHourOption
@onready var add_button: Button = \
	$MarginContainer/RootVBox/SplitBox/RightPanel/AddRow/AddButton
@onready var add_status_label: Label = \
	$MarginContainer/RootVBox/SplitBox/RightPanel/AddStatusLabel
@onready var grid_container: GridContainer = \
	$MarginContainer/RootVBox/SplitBox/RightPanel/GridScroll/ScheduleGrid

var _selected_action_id: String = ""


func _ready() -> void:
	pause_button.toggled.connect(func(pressed: bool):
		if pressed: TimeManager.set_speed(TimeManager.Speed.PAUSED))
	speed1_button.toggled.connect(func(pressed: bool):
		if pressed: TimeManager.set_speed(TimeManager.Speed.X1))
	speed2_button.toggled.connect(func(pressed: bool):
		if pressed: TimeManager.set_speed(TimeManager.Speed.X2))
	speed5_button.toggled.connect(func(pressed: bool):
		if pressed: TimeManager.set_speed(TimeManager.Speed.X5))

	add_button.pressed.connect(_on_add_pressed)

	TimeManager.clock_updated.connect(_on_clock_updated)
	ScheduleManager.hour_executed.connect(_on_hour_executed)
	ScheduleManager.schedule_changed.connect(_refresh_grid)
	ScheduleManager.action_interrupt.connect(_on_action_interrupt)
	ScheduleManager.day_schedule_ended.connect(_on_day_schedule_ended)

	_build_start_hour_options()
	_build_action_list()
	_refresh_grid()
	_refresh_status()


func refresh() -> void:
	_build_action_list()
	_refresh_grid()
	_refresh_status()


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

		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)

		var title := Label.new()
		title.text = "%s（%d小时）" % [action.name, action.duration_hours]
		title.add_theme_font_size_override("font_size", 15)
		row.add_child(title)

		var desc := Label.new()
		if action.energy_recovery_per_hour > 0.0:
			desc.text = "每小时恢复精力 +%.0f｜不计入工作时长" % action.energy_recovery_per_hour
		else:
			desc.text = "每小时消耗精力 %.0f｜预计总消耗 %.0f（未计疲惫倍率）" % [
				action.base_energy_cost_per_hour,
				action.base_energy_cost_per_hour * action.duration_hours,
			]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(desc)

		var select_btn := Button.new()
		if check.can:
			select_btn.text = "从 %02d:00 开始安排" % start_hour
			select_btn.disabled = false
		else:
			select_btn.text = "不可安排：%s" % check.reason
			select_btn.disabled = true

		select_btn.pressed.connect(func():
			_selected_action_id = action.id
			_on_add_pressed()
		)
		row.add_child(select_btn)
		row.add_child(HSeparator.new())
		action_list.add_child(row)


func _on_add_pressed() -> void:
	if _selected_action_id == "":
		return
	var start_hour := _get_selected_start_hour()
	var result := ScheduleManager.add_action_to_schedule(_selected_action_id, start_hour)
	if result.can:
		add_status_label.text = "✅ 已加入排程"
	else:
		add_status_label.text = "⚠ %s" % result.reason
	_build_action_list()
	_refresh_grid()


func _refresh_grid() -> void:
	for child in grid_container.get_children():
		child.queue_free()

	for cell_index in range(12):
		var cell_start_hour := cell_index * 2
		var cell_end_hour := cell_start_hour + 2

		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.custom_minimum_size = Vector2(140, 70)

		var header := Label.new()
		header.text = HOUR_CELL_LABELS[cell_index]
		header.add_theme_font_size_override("font_size", 12)
		cell.add_child(header)

		var covered_entries: Array[ScheduledActionEntry] = []
		for hour in range(cell_start_hour, cell_end_hour):
			var e := ScheduleManager.today_schedule.get_entry_for_hour(hour)
			if e != null and not covered_entries.has(e):
				covered_entries.append(e)

		if covered_entries.is_empty():
			var empty_label := Label.new()
			empty_label.text = "（空）"
			cell.add_child(empty_label)
		else:
			for e in covered_entries:
				var action := ScheduleActionData.get_action(e.action_id)
				var line := Label.new()
				line.text = "%s %02d-%02d｜%s" % [
					"✅" if e.status == "completed" else ("⚠" if e.status == "failed" else "⏳"),
					e.start_hour, e.get_end_hour(),
					action.name if action != null else e.action_id,
				]
				line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				cell.add_child(line)

				if e.status == "pending":
					var del_btn := Button.new()
					del_btn.text = "删除"
					del_btn.pressed.connect(func():
						ScheduleManager.remove_action_from_schedule(e.start_hour)
						_build_action_list()
					)
					cell.add_child(del_btn)

		var panel := PanelContainer.new()
		panel.add_child(cell)
		grid_container.add_child(panel)


func _refresh_status() -> void:
	var player := GameManager.player_state
	day_hour_label.text = "第 %d 天" % TimeManager.current_day
	_update_energy_label()
	_update_fatigue_label()
	_update_store_status_label()
	current_action_label.text = "当前行动：（未开始推进）"


func _on_clock_updated(hour: int, minute: int, second: int, period_label: String) -> void:
	day_hour_label.text = "第 %d 天 ｜ %02d:%02d:%02d ｜ %s" % [
		TimeManager.current_day, hour, minute, second, period_label
	]
	_update_store_status_label()


func _on_hour_executed(log: HourlyLogEntry) -> void:
	if log.action_id != "":
		current_action_label.text = "当前行动：%s（%s）" % [
			log.action_name,
			{"executing": "进行中", "completed": "已完成",
			 "failed": "已中止：%s" % log.failure_reason}.get(log.action_status, log.action_status)
		]
	else:
		current_action_label.text = "当前行动：空闲"
	_update_energy_label()
	_update_fatigue_label()
	_update_store_status_label()
	_refresh_grid()


func _update_energy_label() -> void:
	var player := GameManager.player_state
	if player.energy_debt > 0.0:
		energy_label.text = "精力：0 / %.0f（透支 %.0f）" % [player.max_energy, player.energy_debt]
	else:
		energy_label.text = "精力：%.0f / %.0f" % [player.energy, player.max_energy]


func _update_fatigue_label() -> void:
	var player := GameManager.player_state
	fatigue_label.text = "疲惫：%s（今日已工作 %.0f 小时）" % [
		ScheduleConfig.FATIGUE_STATE_NAMES.get(player.fatigue_state, player.fatigue_state),
		player.work_hours_today,
	]


func _update_store_status_label() -> void:
	if not GameManager.store_state.is_open:
		store_status_label.text = "店铺状态：尚未开业"
	elif TimeManager.is_store_actually_operating():
		store_status_label.text = "店铺状态：营业中"
	else:
		store_status_label.text = "店铺状态：非营业时段"


func _on_action_interrupt(_reason_code: String, message: String) -> void:
	warning_label.text = "⚠ %s" % message
	warning_label.visible = true


func _on_day_schedule_ended(finished_day: int) -> void:
	warning_label.text = "第 %d 天已结束，请为新的一天安排日程" % finished_day
	warning_label.visible = true
	_build_action_list()
	_refresh_grid()
