extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var character := GameManager.create_character({"player_name":"Selection Test", "gender":"female", "age":28, "difficulty_id":"normal", "preset_id":"", "trait_ids":[]})
	_expect(bool(character.get("success", false)), "创建角色")
	var created := GameManager.create_new_store("Selection Test Store")
	_expect(bool(created.get("success", false)), "创建筹备店铺")
	var empty: StorefrontData = null
	var occupied: StorefrontData = null
	for storefront in GameManager.all_storefronts:
		if storefront.is_occupied and occupied == null: occupied = storefront
		if not storefront.is_occupied and empty == null: empty = storefront
	_expect(empty != null and occupied != null, "地图同时拥有空门面和营业门面")
	if empty != null:
		_expect(not bool(GameManager.get_storefront_intel(empty.id).get("visited", false)), "选址前不要求门面已到访")
		var selected := GameManager.select_storefront(empty.id)
		_expect(bool(selected.get("success", false)), "空门面无需深度勘验即可选为企划")
		_expect(GameManager.get_active_store().selected_storefront_id == empty.id, "选址写入当前店铺")
	if occupied != null:
		var rejected := GameManager.select_storefront(occupied.id)
		_expect(not bool(rejected.get("success", false)), "真实已开店门面仍不能选址")
	_finish()

func _expect(condition: bool, message: String) -> void:
	if condition: passed += 1; print("PASS: " + message)
	else: failed += 1; print("FAIL: " + message)

func _finish() -> void:
	print("========== Storefront Selection Test: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
