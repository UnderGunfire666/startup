extends Node
## 核心状态契约测试。
##
## 目标：验证 PlayerState / Store / active_store 三层状态边界，
## 防止旧单店语义重新回归。

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("========== 核心状态契约测试开始 ==========")
	_test_player_without_store()
	_test_store_creation_and_activation()
	_test_store_isolation()
	_test_active_store_switching()
	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("🎉 核心状态契约全部通过")
	else:
		print("⚠ 核心状态契约存在失败")


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("✅ %s" % label)
	else:
		_fail_count += 1
		print("❌ %s" % label)


func _test_player_without_store() -> void:
	print("\n── 1. PlayerState 与 Store 分离 ──")
	GameManager.start_new_game()
	_check(not GameManager.player_state.is_character_created, "新游戏开始时角色应不存在")
	_check(GameManager.stores.is_empty(), "新游戏开始时Store应为空")
	_check(GameManager.active_store_id == "", "新游戏开始时active_store_id应为空")
	_check(GameManager.store_state == null, "新游戏开始时store_state应为null")

	var create_result: Dictionary = GameManager.create_character({
		"player_name": "状态契约测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_check(bool(create_result.get("success", false)), "创建角色应成功")
	_check(GameManager.player_state.is_character_created, "创建角色后PlayerState应标记为已创建")
	_check(GameManager.stores.is_empty(), "创建角色后不得自动创建Store")
	_check(GameManager.active_store_id == "", "创建角色后active_store_id仍应为空")
	_check(GameManager.store_state == null, "创建角色后无企划时store_state应为null")


func _test_store_creation_and_activation() -> void:
	print("\n── 2. Store 创建与激活 ──")
	var result: Dictionary = GameManager.create_new_store("状态契约首店")
	_check(bool(result.get("success", false)), "创建首个Store应成功")
	var store_id: String = str(result.get("store_id", ""))
	_check(store_id != "", "首个Store应拥有非空ID")
	_check(GameManager.stores.size() == 1, "创建首个Store后应有1个Store")
	_check(GameManager.active_store_id == store_id, "创建Store后应自动激活该Store")
	_check(GameManager.store_state != null, "有激活Store时store_state不应为null")
	_check(GameManager.store_state.id == store_id, "store_state应指向active_store_id对应Store")


func _test_store_isolation() -> void:
	print("\n── 3. Store 数据隔离 ──")
	var first_id: String = GameManager.active_store_id
	var first: Store = GameManager.get_store(first_id)
	var second_result: Dictionary = GameManager.create_new_store("状态契约分店")
	var second_id: String = str(second_result.get("store_id", ""))
	var second: Store = GameManager.get_store(second_id)

	_check(second_id != "" and second_id != first_id, "第二个Store应拥有不同ID")
	_check(GameManager.stores.size() == 2, "创建第二个Store后应有2个Store")
	_check(first != null and second != null, "两个Store实例都应存在")
	_check(first.category_slots.size() == 0, "首店初始品类应为空")
	_check(second.category_slots.size() == 0, "分店初始品类应为空")
	_check(second.get_ingredient_stock("soybean") == 0.0, "分店初始soybean库存应为0")

	first.set_ingredient_stock("soybean", 321.0)
	_check(second.get_ingredient_stock("soybean") != 321.0, "修改首店库存不得影响分店库存")
	_check(first.get_ingredient_stock("soybean") == 321.0, "首店自身库存修改应生效")


func _test_active_store_switching() -> void:
	print("\n── 4. active_store / store_state 切换 ──")
	var ids: Array[String] = []
	for store in GameManager.stores:
		if store != null:
			ids.append(store.id)
	_check(ids.size() == 2, "测试期间应存在2个Store")
	if ids.size() < 2:
		return

	var first_id: String = ids[0]
	var second_id: String = ids[1]
	var first_switch: Dictionary = GameManager.switch_active_store(first_id)
	_check(bool(first_switch.get("success", false)), "切换到首店应成功")
	_check(GameManager.active_store_id == first_id, "切换后active_store_id应为首店")
	_check(GameManager.store_state != null and GameManager.store_state.id == first_id, "切换后store_state应指向首店")

	var second_switch: Dictionary = GameManager.switch_active_store(second_id)
	_check(bool(second_switch.get("success", false)), "切换到分店应成功")
	_check(GameManager.active_store_id == second_id, "切换后active_store_id应为分店")
	_check(GameManager.store_state != null and GameManager.store_state.id == second_id, "切换后store_state应指向分店")
