class_name StorefrontSelectionService
extends RefCounted

## Phase 8：把已完成完整尽调的门面落实到指定 Store。
## 业务状态仍写入 Store，玩家层的门面知识仍由 PlayerState 持有。
## GameManager/UI 应通过本服务完成选择，避免直接修改 Store.selected_storefront_id。

static func select_storefront(
	store: Store,
	storefront: StorefrontData,
	all_stores: Array[Store],
	player_state: PlayerState
) -> Dictionary:
	if store == null:
		return {"success": false, "reason_code": "no_store", "reason": "没有激活的开店企划"}
	if storefront == null:
		return {"success": false, "reason_code": "storefront_not_found", "reason": "目标门面不存在"}
	if player_state == null or not player_state.is_character_created:
		return {"success": false, "reason_code": "no_character", "reason": "请先完成人物创建"}

	var diligence_state: String = player_state.get_storefront_diligence(storefront.id)
	if diligence_state != "full_diligence":
		return {
			"success": false,
			"reason_code": "storefront_not_diligent",
			"reason": "请先完成该门面的完整尽调",
		}

	for other_store in all_stores:
		if other_store == store:
			continue
		if other_store.selected_storefront_id == storefront.id or other_store.signed_storefront_id == storefront.id:
			return {
				"success": false,
				"reason_code": "storefront_occupied",
				"reason": "该门面已被其他开店企划占用",
			}

	store.selected_storefront_id = storefront.id
	store.selected_region_id = storefront.region_id
	store.pre_open_stage = Store.PreOpenStage.STOREFRONT_SELECTION

	return {
		"success": true,
		"reason_code": "",
		"reason": "已选定门面「%s」" % storefront.id,
		"store_id": store.id,
		"storefront_id": storefront.id,
	}
