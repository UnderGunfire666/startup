class_name SpatialMigrationConfig
## 旧空间系统 → 新空间系统的迁移专用配置。
## 只在存档迁移时使用，不参与正常游戏逻辑判定。

## 每完成一次不兼容的存档结构变更就+1，配合StoreState.spatial_system_version判断是否需要迁移。
const CURRENT_SPATIAL_VERSION: int = 1

## 旧RegionData.id → 新CityRegionData.id。
## 这张表需要你根据实际regions.json/city_regions.json的内容手动维护，
## 目前示例对应之前给出的storefronts.json迁移方案(A001→CR001, A002→CR002)。
const LEGACY_REGION_TO_CITY_REGION: Dictionary = {
	"A001": "CR001",
	"A002": "CR002",
}

## 迁移生成的默认调查区半径，需要能覆盖该城市区域的大部分区块。
const MIGRATED_SURVEY_RADIUS: float = 900.0


static func get_city_region_id_for_legacy_region(region_id: String) -> String:
	return str(LEGACY_REGION_TO_CITY_REGION.get(region_id, ""))
