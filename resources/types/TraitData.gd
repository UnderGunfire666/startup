class_name TraitData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""

## body / insight / temperament / social
@export var trait_type: String = ""

## 正数：消耗特质点；负数：返还特质点。
@export var point_cost: int = 0

## 仅用于 UI 表现和筛选，实际结算以 point_cost 为准。
@export var is_positive: bool = false

## 统一效果表，后续由 PlayerState.get_trait_modifier() 读取。
## 示例：{"max_energy_add": 15.0, "stress_gain_mult": 0.85}
@export var effects: Dictionary = {}
