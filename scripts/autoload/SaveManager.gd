extends Node
## Autoload单例，负责游戏存档的写入与读取。

const SAVE_PATH := "user://savegame.json"

func save_game() -> bool:
	var data := {
		"player_state": GameManager.player_state.to_save_dict(),
		"store_state": GameManager.store_state.to_save_dict(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: 无法打开存档文件用于写入")
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		push_warning("SaveManager: 存档文件不存在")
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: 存档解析失败")
		return false

	var player_data: Dictionary = parsed.get("player_state", {})
	var store_data: Dictionary = parsed.get("store_state", {})

	GameManager.player_state = PlayerState.from_save_dict(player_data)
	GameManager.store_state = StoreState.from_save_dict(store_data)
	GameManager._sync_data_objects()
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
