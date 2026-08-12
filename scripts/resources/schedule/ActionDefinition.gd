class_name ActionDefinition
extends Resource

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var category: String = ""

@export var duration_hours: int = 1
@export var base_energy_cost_per_hour: float = 0.0

## 允许安排的小时区间 [start_hour, end_hour)，均为0-23的整数，end可以是24表示到当天结束。
@export var allowed_hour_range: Vector2i = Vector2i(0, 24)

@export var requires_character_created: bool = true
@export var requires_region_selected: bool = false
@export var requires_open_store: bool = false
@export var requires_store_operating_hour: bool = false   # 动态：当前小时店铺是否真的在营业
@export var requires_today_has_settled: bool = false       # 动态：今天是否已经发生过至少一次结算
@export var requires_selected_category: bool = false
@export var requires_inspected_storefront: bool = false     # deep_inspection 的前置

@export var work_hour_counting: bool = true
@export var interruptible: bool = true

## 恢复类行动（休息/睡眠）：为正数，代表每小时精力恢复量。0表示不是恢复类行动。
@export var energy_recovery_per_hour: float = 0.0

## 供未来系统读取的效果类型标签，ScheduleManager按此分发，不按id写死。
@export var action_effect_type: String = "generic_hook"

## proportional：每小时累加效果；binary：必须做满全部时长才触发一次性效果。
@export var effect_scaling: String = "proportional"
