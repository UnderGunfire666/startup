class_name StorefrontIntelPresenter
extends RefCounted

## The same unverified claim is shown until a research or field action changes
## what the player knows.  We never re-roll on opening a panel.
static func describe_storefront(storefront: StorefrontData, player: PlayerState) -> Dictionary:
	var intel := player.get_storefront_intel(storefront.id)
	if bool(intel.get("visited", false)):
		return {
			"visited": true,
			"occupancy": "已开店" if storefront.is_occupied else "空门面",
			"occupant_name": storefront.occupant_name,
			"area": "面积 %.1f㎡" % storefront.area,
			"appearance": "装修：%s｜设备：%s｜临街：%s｜可达性 ×%.2f｜截流 ×%.2f" % [storefront.decoration_level, storefront.equipment_condition, storefront.storefront_flow, storefront.accessibility_modifier, storefront.capture_modifier],
		}
	var rng := _rng(player, storefront.id)
	var areas := ["面积约 15㎡", "面积约 30㎡", "面积约 55㎡", "面积约 80㎡"]
	var appearances := ["装修：普通｜设备：一般｜临街：次要", "装修：较新｜设备：齐全｜临街：主街", "装修：老旧｜设备：待整修｜临街：隐蔽"]
	return {
		"visited": false,
		"occupancy": "已开店" if rng.randf() > 0.48 else "空门面",
		"occupant_name": "",
		"area": areas[rng.randi_range(0, areas.size() - 1)],
		"appearance": appearances[rng.randi_range(0, appearances.size() - 1)],
	}

static func describe_block(block: BlockData, player: PlayerState) -> Array[String]:
	var lines: Array[String] = []
	for focus_id in GameManager.BLOCK_RESEARCH_FOCUSES:
		lines.append(_describe_focus(block, focus_id, player.get_block_research_progress(block.id, focus_id), player))
	return lines

static func _describe_focus(block: BlockData, focus_id: String, progress: float, player: PlayerState) -> String:
	var truth := _truth(block, focus_id)
	if progress >= 100.0:
		return truth
	var rng := _rng(player, block.id + ":" + focus_id)
	var guesses := _guesses(focus_id)
	var guess := guesses[rng.randi_range(0, guesses.size() - 1)]
	if progress >= 75.0:
		return _label(focus_id) + "：" + _coarse_truth(block, focus_id)
	if progress >= 50.0:
		return _label(focus_id) + "：" + _direction_truth(block, focus_id)
	if progress >= 25.0:
		return _label(focus_id) + "：" + guess + "；还需要再跑几趟才能分清细节"
	return _label(focus_id) + "：" + guess

static func _truth(block: BlockData, focus_id: String) -> String:
	match focus_id:
		"population": return "人口：%s，密度与基础活跃程度已核验" % ("规模较大" if block.tier >= 2 else "规模有限")
		"groups": return "客群：主要是%s" % _largest_group(block)
		"time": return "时段：%s最活跃" % _largest_period(block)
		"spending": return "消费：%s" % str(block.spending_profile.get("spend_potential_tier", "medium"))
		"demand": return "需求：%s" % (str(block.business_demand_tags[0]) if not block.business_demand_tags.is_empty() else "暂无明显缺口")
		"competition": return "竞争：%s" % str(block.competition_profile.get("competition_level", "medium"))
	return focus_id

static func _coarse_truth(block: BlockData, focus_id: String) -> String:
	match focus_id:
		"groups": return "%s占得更多" % _largest_group(block)
		"time": return "%s附近更活跃" % _largest_period(block)
		"population": return "人流%s" % ("偏多" if block.tier >= 2 else "不算密")
		_: return _truth(block, focus_id).replace(_label(focus_id) + "：", "")

static func _direction_truth(block: BlockData, focus_id: String) -> String:
	match focus_id:
		"population": return "街面活动%s" % ("更旺" if block.tier >= 2 else "较平")
		"groups": return "某一类固定客群更显眼"
		"time": return "高峰并不均匀"
		"spending": return "价格会影响不少人的选择"
		"demand": return "有些业态显得拥挤，有些仍留着空白"
		"competition": return "同行的招牌比预想中更多"
	return "轮廓开始清楚"

static func _guesses(focus_id: String) -> Array[String]:
	match focus_id:
		"population": return ["人流看着不小", "街上比想象安静", "高低峰很难说"]
		"groups": return ["像是上班族居多", "学生面孔很多", "家庭客流可能更多"]
		"time": return ["早晨或许更忙", "午后似乎有一阵人潮", "晚上可能才热闹"]
		"spending": return ["大家可能更在意价格", "看起来愿意为品质停留", "消费习惯还说不准"]
		"demand": return ["餐饮招牌似乎有空子", "便利服务可能不够", "暂时看不出缺什么"]
		"competition": return ["同行可能不少", "这一行或许还不拥挤", "附近店铺变化很快"]
	return ["尚无可靠判断"]

static func _label(focus_id: String) -> String:
	return str({"population":"人口", "groups":"客群", "time":"时段", "spending":"消费", "demand":"需求", "competition":"竞争"}.get(focus_id, focus_id))

static func _rng(player: PlayerState, key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(player.storefront_intel_seed) + int(hash(key))
	return rng

static func _largest_group(block: BlockData) -> String:
	var best := "student"
	for group_id in SpatialConfig.POPULATION_GROUPS:
		if block.get_group_weight(group_id) > block.get_group_weight(best):
			best = group_id
	return str({"student":"学生", "office_worker":"上班族", "worker":"工人", "family_household":"家庭", "high_spend_household":"高消费家庭"}.get(best, best))

static func _largest_period(block: BlockData) -> String:
	var best := "morning"
	for period in ["noon", "evening", "night"]:
		if block.get_time_activity(period) > block.get_time_activity(best):
			best = period
	return str({"morning":"早晨", "noon":"中午", "evening":"傍晚", "night":"夜间"}.get(best, best))
