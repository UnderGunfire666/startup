extends PanelContainer

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
@onready var current_action_box: VBoxContainer = $MarginContainer/RootVBox/CurrentActionBox
@onready var current_action_progress_label: Label = $MarginContainer/RootVBox/CurrentActionBox/ProgressLabel
@onready var stop_action_button: Button = $MarginContainer/RootVBox/CurrentActionBox/StopButton
@onready var action_list: VBoxContainer = $MarginContainer/RootVBox/ActionScroll/ActionList

var _last_hour: int = 0
var _last_minute: int = 0
var _last_second: int = 0
var _last_period_label: String = ""
var _schedule_ui_dirty := false
const EXCLUDED_FROM_LIST: Array[String] = ["region_research"]

func _ready() -> void:
	_seed_clock_cache()
	pause_button.toggled.connect(func(pressed: bool):
		if pressed: TimeManager.set_speed(TimeManager.Speed.PAUSED))
	speed1_button.toggled.connect(func(pressed: bool):
		if pressed: TimeManager.set_speed(TimeManager.Speed.X1))
	speed2_button.toggled.connect(func(pressed: bool):
		if pressed: TimeManager.set_speed(TimeManager.Speed.X2))
	speed5_button.toggled.connect(func(pressed: bool):
		if pressed: TimeManager.set_speed(TimeManager.Speed.X5))
	stop_action_button.pressed.connect(_on_stop_pressed)
	TimeManager.clock_updated.connect(_on_clock_updated)
	ScheduleManager.schedule_changed.connect(_on_schedule_state_changed)
	ScheduleManager.map_block_selection_changed.connect(func(_block_ids: Array[String]) -> void: _on_schedule_state_changed())
	ScheduleManager.action_interrupt.connect(_on_action_interrupt)
	ScheduleManager.day_schedule_ended.connect(_on_day_schedule_ended)
	visibility_changed.connect(_on_visibility_changed)
	_refresh_all()


func _on_schedule_state_changed() -> void:
	_schedule_ui_dirty = true
	if is_visible_in_tree():
		_refresh_all()
		_schedule_ui_dirty = false


func _on_visibility_changed() -> void:
	if is_visible_in_tree() and _schedule_ui_dirty:
		_refresh_all()
		_schedule_ui_dirty = false

func _seed_clock_cache() -> void:
	var hour_float := TimeManager.get_hour_of_day()
	_last_hour = int(hour_float) % 24
	_last_minute = int((hour_float - int(hour_float)) * 60.0)
	_last_second = 0
	_last_period_label = ""

func _update_day_hour_label() -> void:
	day_hour_label.text = "第 %d 天 ｜ %02d:%02d:%02d ｜ %s" % [TimeManager.current_day, _last_hour, _last_minute, _last_second, _last_period_label]

func refresh() -> void:
	_refresh_all()

func _refresh_all() -> void:
	_refresh_status()
	_refresh_current_action_box()
	_build_action_list()

func _refresh_current_action_box() -> void:
	var state := ScheduleManager.current_action
	if state == null or not state.is_active:
		current_action_box.visible = false
		return
	var action := ScheduleActionData.get_action(state.action_id)
	current_action_box.visible = true
	var elapsed: float = (TimeManager.total_game_seconds - state.start_game_seconds) / 3600.0
	var target_text := _describe_target(action, state.target_id, state.target_ids)
	current_action_progress_label.text = "进行中：%s%s（已进行 %.2f / %d 小时）" % [action.name if action != null else state.action_id, target_text, elapsed, action.duration_hours]
	stop_action_button.disabled = false
	stop_action_button.text = "⏹ 取消（尚未产生任何收益）" if elapsed < 0.01 else "⏹ 提前停止"

func _on_stop_pressed() -> void:
	ScheduleManager.stop_current_action()
	_refresh_all()

func _describe_target(action: ActionDefinition, target_id: String, target_ids: Array[String]) -> String:
	if action == null:
		return ""
	if action.action_effect_type == "region_research":
		if target_ids.is_empty():
			return ""
		var block_names: Array[String] = []
		for block_id in target_ids:
			var block := GameManager.get_block(block_id)
			if block != null:
				block_names.append(block.name)
		return "（目标区块：%s）" % "、".join(block_names)
	if action.action_effect_type == "move_to_block":
		var block := GameManager.get_block(target_id)
		return "（目标区块：%s）" % (block.name if block != null else target_id)
	if target_id == "":
		return ""
	return ""

func _build_action_list() -> void:
	for child in action_list.get_children():
		child.queue_free()
	var busy := ScheduleManager.current_action != null and ScheduleManager.current_action.is_active
	for action in ScheduleActionData.get_actions():
		if action.action_effect_type in EXCLUDED_FROM_LIST:
			continue
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 10)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := Label.new()
		var action_name := action.name
		if action.action_effect_type == "move_to_block":
			var selected_target_id := ScheduleManager.get_selected_move_target_id()
			var selected_target := GameManager.get_block(selected_target_id)
			if selected_target != null:
				action_name += " → %s" % selected_target.name
			else:
				action_name += "（请先在地图选择区块）"
		elif action.action_effect_type == "landlord_negotiation":
			var selected_storefront := GameManager.get_storefront(GameManager.store_state.selected_storefront_id) if GameManager.store_state != null else null
			action_name += " → %s" % selected_storefront.name if selected_storefront != null else "（请先选定空门面）"
		title.text = "%s（%d小时）" % [action_name, action.duration_hours]
		title.add_theme_font_size_override("font_size", 15)
		info.add_child(title)
		var desc := Label.new()
		if action.energy_recovery_per_hour > 0.0:
			desc.text = "每小时恢复精力 +%.0f｜不计入工作时长" % action.energy_recovery_per_hour
		else:
			desc.text = "每小时消耗精力 %.0f｜%s" % [action.base_energy_cost_per_hour, "做多久算多久，随时可停" if action.effect_scaling == "proportional" else "必须做满全部时长才生效，中途停止视为放弃"]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)
		top_row.add_child(info)
		var start_btn := Button.new()
		start_btn.custom_minimum_size = Vector2(110, 0)
		if action.action_effect_type == "move_to_block" and ScheduleManager.get_selected_move_target_id().is_empty():
			start_btn.text = "请先选区块"
			start_btn.disabled = true
			start_btn.tooltip_text = "请在地图面板勾选要前往的区块"
		elif busy:
			start_btn.text = "有行动进行中"
			start_btn.disabled = true
		else:
			var check := ScheduleManager.can_schedule_action(action.id, int(TimeManager.get_hour_of_day()))
			if check.can:
				start_btn.text = "▶ 开始"
				start_btn.disabled = false
			else:
				start_btn.text = "不可用"
				start_btn.disabled = true
				start_btn.tooltip_text = check.reason
			start_btn.pressed.connect(func() -> void:
				var result := ScheduleManager.start_action_now(action.id, "")
				if not result.can:
					warning_label.visible = true
					warning_label.text = "⚠ %s" % result.reason
				_refresh_all()
			)
		top_row.add_child(start_btn)
		row.add_child(top_row)
		action_list.add_child(row)
		action_list.add_child(HSeparator.new())

func _refresh_status() -> void:
	_update_day_hour_label()
	_update_energy_label()
	_update_fatigue_label()
	_update_store_status_label()
	_update_current_action_label()

func _on_clock_updated(hour: int, minute: int, second: int, period_label: String) -> void:
	_last_hour = hour
	_last_minute = minute
	_last_second = second
	_last_period_label = period_label
	if not is_visible_in_tree():
		return
	_update_day_hour_label()
	_update_store_status_label()
	_update_current_action_label()
	_refresh_current_action_box()

func _update_current_action_label() -> void:
	var state := ScheduleManager.current_action
	if state != null and state.is_active:
		var action := ScheduleActionData.get_action(state.action_id)
		current_action_label.text = "当前行动：%s（进行中）" % [action.name if action != null else state.action_id]
		return
	if not ScheduleManager.completed_entries_today.is_empty():
		var last: ScheduledActionEntry = ScheduleManager.completed_entries_today.back()
		var action := ScheduleActionData.get_action(last.action_id)
		var action_name := action.name if action != null else last.action_id
		var status_text: String = {"completed": "已完成", "failed": "已中止：%s" % last.failure_reason}.get(last.status, last.status)
		current_action_label.text = "刚执行：%s（%s，进行了 %.2f 小时）" % [action_name, status_text, last.hours_completed]
		return
	current_action_label.text = "当前行动：空闲，可以选择下一个行动"

func _update_energy_label() -> void:
	var player := GameManager.player_state
	if player.energy_debt > 0.0:
		energy_label.text = "精力：0 / %.0f（透支 %.0f）" % [player.max_energy, player.energy_debt]
	elif player.energy < 0.1:
		var research_check := ScheduleManager.get_region_research_start_energy_check()
		var suffix := "（不足以开始调查）" if not bool(research_check.get("can", false)) else ""
		energy_label.text = "精力：%.3f / %.1f%s" % [player.energy, player.max_energy, suffix]
	else:
		energy_label.text = "精力：%.1f / %.1f" % [player.energy, player.max_energy]

func _update_fatigue_label() -> void:
	var player := GameManager.player_state
	fatigue_label.text = "疲惫：%s（今日已工作 %.0f 小时）" % [ScheduleConfig.FATIGUE_STATE_NAMES.get(player.fatigue_state, player.fatigue_state), player.work_hours_today]

func _update_store_status_label() -> void:
	var store := GameManager.store_state
	if not GameManager.player_state.is_character_created:
		store_status_label.text = "店铺状态：尚未创建角色"
	elif store == null:
		store_status_label.text = "店铺状态：尚未创建开店企划"
	elif not store.is_open:
		store_status_label.text = "店铺状态：尚未开业"
	elif TimeManager.is_store_actually_operating():
		store_status_label.text = "店铺状态：营业中"
	else:
		store_status_label.text = "店铺状态：非营业时段"

func _on_action_interrupt(_reason_code: String, message: String) -> void:
	warning_label.text = "⚠ %s" % message
	warning_label.visible = true

func _on_day_schedule_ended(finished_day: int) -> void:
	warning_label.text = "第 %d 天已结束，请为新的一天选择行动" % finished_day
	warning_label.visible = true
	_refresh_all()
