extends Node
## Autoload单例，负责游戏存档的写入与读取。
## v2变更：store_state单例改为stores数组+active_store_id，
## 存档结构相应调整。不做旧格式兼容（已确认不需要存档迁移）。

const SAVE_PATH := "user://savegame.json"

func save_game() -> bool:
	var store_data: Array = []
	for store in GameManager.stores:
		store_data.append(store.to_save_dict())

	var data := {
		"player_state": GameManager.player_state.to_save_dict(),
		"stores": store_data,
		"active_store_id": GameManager.active_store_id,
		"time_manager": TimeManager.to_save_dict(),
		"event_manager": EventManager.to_save_dict(),
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
	var stores_raw: Array = parsed.get("stores", [])
	var time_data: Dictionary = parsed.get("time_manager", {})
	var event_data: Dictionary = parsed.get("event_manager", {})

	GameManager.player_state = PlayerState.from_save_dict(player_data)

	var loaded_stores: Array[Store] = []
	for raw_store in stores_raw:
		if raw_store is Dictionary:
			loaded_stores.append(Store.from_save_dict(raw_store))
	GameManager.stores = loaded_stores
	GameManager.active_store_id = str(parsed.get("active_store_id", ""))
	## 容错旧存档或异常存档：激活店铺ID无效时，自动选择第一家已载入店铺。
	if GameManager.get_active_store() == null and not GameManager.stores.is_empty():
		GameManager.active_store_id = GameManager.stores[0].id
	GameManager.active_simulations.clear()
	## 日程系统当前不写入存档；读档后清除运行时行动，避免旧会话的行动继续影响时间推进。
	ScheduleManager.reset_for_new_game()

	TimeManager.apply_save_dict(time_data)
	EventManager.apply_save_dict(event_data)
	GameManager._sync_data_objects()
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
