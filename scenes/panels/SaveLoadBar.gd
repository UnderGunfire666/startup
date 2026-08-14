extends HBoxContainer
## 顶部存档操作栏：提供保存/读取/新开局三个入口。
## 读取和新开局都会重建整个 store_state，因此通过 data_changed 信号
## 通知 Main 刷新全部面板，避免各面板显示与实际状态脱节。

signal data_changed

@onready var save_button: Button = $SaveButton
@onready var load_button: Button = $LoadButton
@onready var new_game_button: Button = $NewGameButton
@onready var status_label: Label = $StatusLabel
@onready var confirm_dialog: ConfirmationDialog = $NewGameConfirmDialog
@onready var time_label: Label = $TimeLabel
@onready var pause_button: Button = $PauseButton
@onready var speed1_button: Button = $Speed1Button
@onready var speed2_button: Button = $Speed2Button
@onready var speed5_button: Button = $Speed5Button
@onready var current_action_label: Label = $CurrentActionLabel
@onready var stop_action_button: Button = $StopActionButton

func _ready() -> void:
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	confirm_dialog.confirmed.connect(_on_new_game_confirmed)
	pause_button.pressed.connect(func() -> void: TimeManager.set_speed(TimeManager.Speed.PAUSED))
	speed1_button.pressed.connect(func() -> void: TimeManager.set_speed(TimeManager.Speed.X1))
	speed2_button.pressed.connect(func() -> void: TimeManager.set_speed(TimeManager.Speed.X2))
	speed5_button.pressed.connect(func() -> void: TimeManager.set_speed(TimeManager.Speed.X5))
	stop_action_button.pressed.connect(_on_stop_current_action_pressed)
	TimeManager.clock_updated.connect(_on_clock_updated)
	ScheduleManager.schedule_changed.connect(_refresh_action_controls)
	load_button.disabled = not SaveManager.has_save()
	_refresh_time_controls()
	_refresh_action_controls()


func _on_clock_updated(hour: int, minute: int, second: int, period_label: String) -> void:
	time_label.text = "第 %d 天｜%02d:%02d:%02d｜%s" % [TimeManager.current_day, hour, minute, second, period_label]
	_refresh_time_controls()
	_refresh_action_controls()


func _refresh_time_controls() -> void:
	var enabled := GameManager.player_state.is_character_created
	pause_button.disabled = not enabled
	speed1_button.disabled = not enabled
	speed2_button.disabled = not enabled
	speed5_button.disabled = not enabled
	pause_button.button_pressed = TimeManager.speed == TimeManager.Speed.PAUSED
	speed1_button.button_pressed = TimeManager.speed == TimeManager.Speed.X1
	speed2_button.button_pressed = TimeManager.speed == TimeManager.Speed.X2
	speed5_button.button_pressed = TimeManager.speed == TimeManager.Speed.X5


func _refresh_action_controls() -> void:
	var state := ScheduleManager.current_action
	var is_active := state != null and state.is_active
	current_action_label.visible = is_active
	stop_action_button.visible = is_active
	stop_action_button.disabled = not is_active
	if not is_active:
		return
	var action := ScheduleActionData.get_action(state.action_id)
	var action_name := action.name if action != null else state.action_id
	current_action_label.text = "进行中：%s" % action_name


func _on_stop_current_action_pressed() -> void:
	var state := ScheduleManager.current_action
	if state == null or not state.is_active:
		return
	var action := ScheduleActionData.get_action(state.action_id)
	var action_name := action.name if action != null else state.action_id
	ScheduleManager.stop_current_action()
	status_label.text = "已结束「%s」" % action_name
	_refresh_action_controls()

func _on_save_pressed() -> void:
	if SaveManager.save_game():
		status_label.text = "✅ 已保存进度"
		load_button.disabled = false
	else:
		status_label.text = "⚠ 保存失败，请检查磁盘权限"

func _on_load_pressed() -> void:
	if SaveManager.load_game():
		status_label.text = "✅ 已读取存档"
		data_changed.emit()
	else:
		status_label.text = "⚠ 读取失败：无存档或存档已损坏"

func _on_new_game_pressed() -> void:
	confirm_dialog.popup_centered()

func _on_new_game_confirmed() -> void:
	GameManager.start_new_game()
	status_label.text = "🆕 已开始新的一局"
	data_changed.emit()
