class_name MovementConfig
## Phase 6：玩家跨区块移动的全局配置。
## 第一版不建立道路/寻路系统，直接使用 Block.center_position 的直线距离。

const DISTANCE_UNITS_PER_HOUR: float = 100.0
const MIN_TRAVEL_HOURS: float = 0.0

static func get_travel_hours(from_block: BlockData, to_block: BlockData) -> float:
	if from_block == null or to_block == null:
		return -1.0
	if from_block.id == to_block.id:
		return 0.0

	var distance := from_block.center_position.distance_to(to_block.center_position)
	if distance <= 0.0:
		return MIN_TRAVEL_HOURS
	return maxf(MIN_TRAVEL_HOURS, distance / DISTANCE_UNITS_PER_HOUR)
