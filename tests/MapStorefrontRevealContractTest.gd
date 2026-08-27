extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	GameManager.start_new_game()
	_expect(not GameManager.all_storefronts.is_empty(), "运行时地图包含门面")
	_expect(GameManager.reveal_all_storefronts().is_empty(), "全门面不再需要揭示操作")
	var storefront: StorefrontData = GameManager.all_storefronts[0]
	var before := StorefrontIntelPresenter.describe_storefront(storefront, GameManager.player_state)
	var again := StorefrontIntelPresenter.describe_storefront(storefront, GameManager.player_state)
	_expect(before == again and not bool(before.get("visited", false)), "未到访的表面信息在同局内稳定")
	GameManager.player_state.set_current_block(storefront.block_id)
	var visit := GameManager.visit_storefront(storefront.id)
	_expect(bool(visit.get("success", false)), "到访可核验单间门面")
	var after := StorefrontIntelPresenter.describe_storefront(storefront, GameManager.player_state)
	_expect(bool(after.get("visited", false)), "到访后的展示切换为真实物理信息")
	var restored := PlayerState.from_save_dict(GameManager.player_state.to_save_dict())
	_expect(bool(restored.get_storefront_intel(storefront.id).get("visited", false)), "到访情报可存档恢复")
	_finish()

func _expect(condition: bool, message: String) -> void:
	if condition: passed += 1; print("PASS: " + message)
	else: failed += 1; print("FAIL: " + message)

func _finish() -> void:
	print("========== Storefront Intel Test: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
