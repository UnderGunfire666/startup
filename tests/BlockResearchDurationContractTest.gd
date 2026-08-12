extends Node

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("── Phase 3 区块调查时间契约测试 ──")
	_test_baseline_area()
	_test_larger_block_takes_longer()
	_test_multiple_blocks_use_largest_workload()
	_test_small_block_has_minimum_duration()
	print("========== 测试结束：%d 通过 / %d 失败 ==========" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _make_block(area: float) -> BlockData:
	var block := BlockData.new()
	block.id = "TEST_BLOCK_%d" % int(area)
	block.name = "测试区块"
	block.city_region_id = "CR001"
	block.area = area
	return block

func _expect(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("✅ %s" % description)
	else:
		_failed += 1
		print("❌ %s" % description)

func _test_baseline_area() -> void:
	var duration := BlockConfig.get_research_duration_hours(2, [_make_block(100.0)])
	_expect(duration == 2, "面积100的基准区块应保持2小时基础调查时长")

func _test_larger_block_takes_longer() -> void:
	var small_duration := BlockConfig.get_research_duration_hours(2, [_make_block(100.0)])
	var large_duration := BlockConfig.get_research_duration_hours(2, [_make_block(400.0)])
	_expect(large_duration > small_duration, "面积更大的区块应需要更长调查时间")
	_expect(large_duration == 4, "面积400的区块按当前公式应需要4小时")

func _test_multiple_blocks_use_largest_workload() -> void:
	var duration := BlockConfig.get_research_duration_hours(2, [
		_make_block(100.0),
		_make_block(400.0),
	])
	_expect(duration == 4, "多区块同时调查时应按最大区块调查工作量确定总时长")

func _test_small_block_has_minimum_duration() -> void:
	var duration := BlockConfig.get_research_duration_hours(2, [_make_block(25.0)])
	_expect(duration == 1, "很小的区块调查时长不得低于1小时")
