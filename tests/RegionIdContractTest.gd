extends Node
## CityRegion 归属契约测试。
## 旧RegionData/region_id体系已废弃（GameManager不再持有all_regions/get_region()），
## 门面地理归属现完全以StorefrontData.city_region_id为唯一权威来源。

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("========== CityRegion 归属契约测试开始 ==========")
	_test_static_mapping()
	_test_region_intel_store_mapping()
	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_pass_count, _fail_count])
	if _fail_count == 0:
		print("🎉 CityRegion 归属契约全部通过")
	else:
		print("⚠ CityRegion 归属契约存在失败")
	get_tree().quit(1 if _fail_count > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("✅ %s" % label)
	else:
		_fail_count += 1
		print("❌ %s" % label)

func _test_static_mapping() -> void:
	print("\n── 1. 门面 city_region_id 归属 ──")
	var storefront: StorefrontData = GameManager.get_storefront("sf_nw_grocery")
	var cr001: CityRegionData = GameManager.get_city_region("CR001")
	var cr002: CityRegionData = GameManager.get_city_region("CR002")
	_check(cr001 != null and cr002 != null, "CityRegion CR001/CR002应存在")
	_check(storefront != null and storefront.city_region_id == "CR001", "示例城区门面应属于CityRegion CR001")
	var reserved_regions_have_no_storefronts := true
	for candidate in GameManager.all_storefronts:
		reserved_regions_have_no_storefronts = reserved_regions_have_no_storefronts and candidate.city_region_id != "CR002"
	_check(reserved_regions_have_no_storefronts, "保留的CityRegion CR002尚未错误绑定CR001门面")

func _test_region_intel_store_mapping() -> void:
	print("\n── 2. Store 经营数据反哺 CityRegion 情报 ──")
	GameManager.start_new_game()
	var create_result: Dictionary = GameManager.create_character({
		"player_name": "Region ID 测试者",
		"gender": "female",
		"age": 28,
		"difficulty_id": "normal",
		"preset_id": "",
		"trait_ids": [],
	})
	_check(bool(create_result.get("success", false)), "创建角色应成功")
	if not bool(create_result.get("success", false)):
		return

	var store_result: Dictionary = GameManager.create_new_store("Region ID 首店")
	_check(bool(store_result.get("success", false)), "创建Store应成功")
	var store: Store = GameManager.store_state
	if store == null:
		return

	store.selected_storefront_id = "sf_nw_grocery"
	store.daily_history.append({"day": 1, "slot": "08:00"})

	GameManager.recalculate_region_intel("CR001")
	var cr001_progress: float = GameManager.player_state.region_intel_progress.get("CR001", 0.0)
	var cr002_progress: float = GameManager.player_state.region_intel_progress.get("CR002", 0.0)
	_check(cr001_progress > 0.0, "CR001门面对应的经营天数应计入CR001情报")
	_check(is_zero_approx(cr002_progress), "CR001门面经营天数不得计入CR002情报")
