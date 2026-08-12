class_name SurveyAreaState
extends RefCounted
## 玩家在地图上自由框选的调查范围。
## 只是"批量选择要调查的区块"的工具，不再存储任何了解度进度——
## 进度全部记在StoreState.block_understanding[block_id]上，
## 圆本身可以随时重画、删除，不影响已经调查到的信息。

var id: String = ""
var name: String = ""
var city_region_id: String = ""
var shape_type: String = "radius"
var center_position: Vector2 = Vector2.ZERO
var radius: float = 0.0

var block_coverages: Array[SurveyBlockCoverage] = []

var created_day: int = 1
var last_used_day: int = 0


func is_valid() -> bool:
	return (
		not id.is_empty()
		and not city_region_id.is_empty()
		and shape_type == "radius"
		and radius > 0.0
	)


func get_coverage(block_id: String) -> SurveyBlockCoverage:
	for coverage in block_coverages:
		if coverage.block_id == block_id:
			return coverage
	return null


func to_save_dict() -> Dictionary:
	var coverage_data: Array[Dictionary] = []
	for coverage in block_coverages:
		coverage_data.append(coverage.to_save_dict())

	return {
		"version": 2,
		"id": id,
		"name": name,
		"city_region_id": city_region_id,
		"shape_type": shape_type,
		"center_position": {"x": center_position.x, "y": center_position.y},
		"radius": radius,
		"block_coverages": coverage_data,
		"created_day": created_day,
		"last_used_day": last_used_day,
	}


static func from_save_dict(data: Dictionary) -> SurveyAreaState:
	var area := SurveyAreaState.new()

	area.id = str(data.get("id", ""))
	area.name = str(data.get("name", ""))
	area.city_region_id = str(data.get("city_region_id", ""))
	area.shape_type = str(data.get("shape_type", "radius"))

	var raw_center: Dictionary = data.get("center_position", {})
	area.center_position = Vector2(
		float(raw_center.get("x", 0.0)),
		float(raw_center.get("y", 0.0))
	)

	area.radius = maxf(0.0, float(data.get("radius", 0.0)))
	area.created_day = maxi(1, int(data.get("created_day", 1)))
	area.last_used_day = maxi(0, int(data.get("last_used_day", 0)))

	var raw_coverages: Array = data.get("block_coverages", [])
	for raw_coverage in raw_coverages:
		if raw_coverage is Dictionary:
			area.block_coverages.append(SurveyBlockCoverage.from_save_dict(raw_coverage))

	return area
