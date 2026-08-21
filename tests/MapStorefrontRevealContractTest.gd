extends Node

var passed := 0
var failed := 0


func _ready() -> void:
	GameManager.start_new_game()
	var storefronts := GameManager.all_storefronts
	_expect(not storefronts.is_empty(), "运行时地图包含门面")
	if storefronts.is_empty():
		_finish()
		return
	var fully_reviewed: StorefrontData = storefronts[0]
	GameManager.advance_storefront_diligence(fully_reviewed.id, "initial_viewing")
	GameManager.advance_storefront_diligence(fully_reviewed.id, "full_diligence")
	var revealed := GameManager.reveal_all_storefronts()
	_expect(revealed.size() == storefronts.size() - 1, "显示全部门面只显示此前未发现的门面")
	_expect(GameManager.get_storefront_diligence(fully_reviewed.id) == "full_diligence", "显示全部门面不会降级完整尽调状态")
	var all_visible := true
	for storefront in storefronts:
		all_visible = all_visible and GameManager.get_storefront_diligence(storefront.id) != "not_viewed"
	_expect(all_visible, "显示全部门面后不保留未发现状态")
	_expect(GameManager.reveal_all_storefronts().is_empty(), "重复显示全部门面不产生重复变更")
	var restored := PlayerState.from_save_dict(GameManager.player_state.to_save_dict())
	_expect(restored.get_storefront_diligence(fully_reviewed.id) == "full_diligence", "显示全部门面后的尽调状态可存档恢复")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)


func _finish() -> void:
	print("========== Map Storefront Reveal Test: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
