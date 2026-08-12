class_name TradeAreaSnapshot
extends RefCounted
## 建议位置：res://scripts/spatial/TradeAreaSnapshot.gd
##
## 门面在某个业态、某个小时下的商圈计算结果。
## 这是运行时快照，不建议写入常规存档——它应该在需要时（预览/结算）
## 由TradeAreaCalculator重新计算，避免存档里保存一份很快过期的派生数据。

var storefront_id: String = ""
var category_id: String = ""
var product_id: String = ""
var hour: int = 0
var period: String = ""

## 每个贡献区块的明细，供UI"这家店的客流主要来自哪"展示，
## 每条包含：block_id, distance, distance_decay, accessibility_mod,
## business_match, competition_mod, group_supply(Dictionary), contribution(float)
var block_contributions: Array[Dictionary] = []

## 五类人群的最终有效可触达量（已应用距离/可达性/业态匹配/竞争修正）
var reachable_groups: Dictionary = {}

## 商业吸引力产生的外来客流，同样已应用修正，但不计入reachable_groups
var external_traffic: float = 0.0

## 参与计算的区块按combined用途加权后的平均竞争修正，仅供UI展示，
## 不用于二次计算（真实竞争修正已经乘进每个区块的贡献里）。
var average_competition_modifier: float = 1.0

## 最终客流基数：reachable_groups总和 + external_traffic
var total_effective_audience: float = 0.0


func get_group_audience(group_id: String) -> float:
	return float(reachable_groups.get(group_id, 0.0))


func to_debug_dict() -> Dictionary:
	return {
		"storefront_id": storefront_id,
		"category_id": category_id,
		"product_id": product_id,
		"hour": hour,
		"period": period,
		"block_contributions": block_contributions,
		"reachable_groups": reachable_groups,
		"external_traffic": external_traffic,
		"average_competition_modifier": average_competition_modifier,
		"total_effective_audience": total_effective_audience,
	}
