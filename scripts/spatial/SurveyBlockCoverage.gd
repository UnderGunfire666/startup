class_name SurveyBlockCoverage
extends RefCounted
## 调查区对单个固定区块的几何命中记录。
## 只保存"这个圆覆盖了这个区块多少"，不再保存任何了解度/进度——
## 了解度现在唯一存储在StoreState.block_understanding[block_id]。

var block_id: String = ""
var coverage_ratio: float = 0.0
var distance_weight: float = 0.0
var combined_weight: float = 0.0


func recalculate_combined_weight() -> void:
	coverage_ratio = clampf(coverage_ratio, 0.0, 1.0)
	distance_weight = clampf(distance_weight, 0.0, 1.0)
	combined_weight = coverage_ratio * distance_weight


func to_save_dict() -> Dictionary:
	return {
		"block_id": block_id,
		"coverage_ratio": coverage_ratio,
		"distance_weight": distance_weight,
		"combined_weight": combined_weight,
	}


static func from_save_dict(data: Dictionary) -> SurveyBlockCoverage:
	var coverage := SurveyBlockCoverage.new()
	coverage.block_id = str(data.get("block_id", ""))
	coverage.coverage_ratio = clampf(float(data.get("coverage_ratio", 0.0)), 0.0, 1.0)
	coverage.distance_weight = clampf(float(data.get("distance_weight", 0.0)), 0.0, 1.0)
	coverage.recalculate_combined_weight()
	return coverage
