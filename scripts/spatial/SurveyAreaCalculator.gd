class_name SurveyAreaCalculator
## 调查区与区块的几何命中计算。逻辑本身不变，只是不再需要
## 在rebuild_coverages()里保留/拷贝"discovery_state"——
## 因为进度已经不挂在coverage上了，重画圆不会丢失任何已调查信息。

const COVERAGE_SAMPLE_GRID: int = 8
const DISTANCE_WEIGHT_RADIUS_MULTIPLIER: float = 1.5
const MIN_COMBINED_WEIGHT: float = 0.001


static func rebuild_coverages(
	survey_area: SurveyAreaState,
	blocks: Array[BlockData]
) -> void:
	if survey_area == null or survey_area.shape_type != "radius":
		return

	var rebuilt: Array[SurveyBlockCoverage] = []
	for block in blocks:
		if block == null or not block.is_valid():
			continue
		if block.city_region_id != survey_area.city_region_id:
			continue

		var new_coverage := build_coverage(survey_area, block)
		if new_coverage != null:
			rebuilt.append(new_coverage)

	survey_area.block_coverages = rebuilt


static func build_coverage(
	survey_area: SurveyAreaState,
	block: BlockData
) -> SurveyBlockCoverage:
	if survey_area == null or block == null or survey_area.radius <= 0.0:
		return null

	var coverage_ratio := calculate_coverage_ratio(
		survey_area.center_position, survey_area.radius, block.map_bounds
	)
	if coverage_ratio <= 0.0:
		return null

	var distance_weight := calculate_distance_weight(
		survey_area.center_position, survey_area.radius, block.center_position
	)

	var coverage := SurveyBlockCoverage.new()
	coverage.block_id = block.id
	coverage.coverage_ratio = coverage_ratio
	coverage.distance_weight = distance_weight
	coverage.recalculate_combined_weight()

	if coverage.combined_weight < MIN_COMBINED_WEIGHT:
		return null

	return coverage


static func calculate_coverage_ratio(
	center: Vector2, radius: float, block_bounds: Rect2
) -> float:
	if radius <= 0.0 or block_bounds.size.x <= 0.0 or block_bounds.size.y <= 0.0:
		return 0.0

	var circle_bounds := Rect2(
		center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)
	)
	if not circle_bounds.intersects(block_bounds):
		return 0.0

	var inside_count := 0
	var total_count := COVERAGE_SAMPLE_GRID * COVERAGE_SAMPLE_GRID
	var radius_squared := radius * radius

	for x_index in range(COVERAGE_SAMPLE_GRID):
		for y_index in range(COVERAGE_SAMPLE_GRID):
			var local_x := (float(x_index) + 0.5) / float(COVERAGE_SAMPLE_GRID)
			var local_y := (float(y_index) + 0.5) / float(COVERAGE_SAMPLE_GRID)
			var sample_point := Vector2(
				block_bounds.position.x + block_bounds.size.x * local_x,
				block_bounds.position.y + block_bounds.size.y * local_y
			)
			if center.distance_squared_to(sample_point) <= radius_squared:
				inside_count += 1

	return float(inside_count) / float(total_count)


static func calculate_distance_weight(
	survey_center: Vector2, survey_radius: float, block_center: Vector2
) -> float:
	if survey_radius <= 0.0:
		return 0.0

	var effective_radius := survey_radius * DISTANCE_WEIGHT_RADIUS_MULTIPLIER
	var distance := survey_center.distance_to(block_center)

	if distance >= effective_radius:
		return 0.0

	return clampf(1.0 - distance / effective_radius, 0.0, 1.0)


static func get_covered_blocks(
	survey_area: SurveyAreaState, all_blocks: Array[BlockData]
) -> Array[BlockData]:
	var block_by_id: Dictionary = {}
	for block in all_blocks:
		if block != null:
			block_by_id[block.id] = block

	var result: Array[BlockData] = []
	for coverage in survey_area.block_coverages:
		var block: BlockData = block_by_id.get(coverage.block_id, null)
		if block != null:
			result.append(block)
	return result
