extends Node
## Autoload单例，负责游戏存档的写入与读取。
## 使用JSON格式而非ResourceSaver，理由：避免自定义Resource潜在的代码执行风险，
## 且JSON对字段增删更宽容，便于跨版本迁移和人工调试。

const SAVE_PATH := "user://savegame.json"

func save_game() -> bool:
	var data := GameManager.store_state.to_save_dict()
	data["debug_ignore_category_restriction"] = GameManager.debug_ignore_category_restriction
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
	GameManager.store_state = StoreState.from_save_dict(parsed)
	GameManager.debug_ignore_category_restriction = parsed.get("debug_ignore_category_restriction", false)
	GameManager._sync_data_objects()
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
