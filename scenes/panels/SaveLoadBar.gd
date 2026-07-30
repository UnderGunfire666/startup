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

func _ready() -> void:
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	confirm_dialog.confirmed.connect(_on_new_game_confirmed)
	load_button.disabled = not SaveManager.has_save()

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
