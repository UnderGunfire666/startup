class_name CurrentActionState
extends RefCounted
## 代表"此刻玩家正在做的这一件事"，不占用任何日历格子。
## 结算时用start_game_seconds算出连续时长，不依赖整点边界。

var action_id: String = ""
## 单目标兼容入口：Store、门面等现有行动继续使用。
var target_id: String = ""
## 多目标入口：Phase 2 的区块调研使用多个 Block ID。
var target_ids: Array[String] = []
var start_game_seconds: float = 0.0
var work_hours_before: float = 0.0   # 开始这个行动前，当天已经工作的小时数（用于疲惫分段结算）
var is_active: bool = false
var source_entry: ScheduledActionEntry = null   # 若是从"日程"计划队列自动接续的，记录来源；纯单步触发则为null
