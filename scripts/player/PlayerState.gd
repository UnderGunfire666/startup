class_name PlayerState
extends RefCounted

## ── 角色身份 ─────────────────────────────────────────────

var is_character_created: bool = false
var player_name: String = ""
var gender: String = ""
var age: int = 20
var difficulty_id: String = "normal"
var selected_preset_id: String = ""

## ── 角色资源 ─────────────────────────────────────────────

var cash: float = SettlementConfig.INITIAL_CASH
var stress: float = SettlementConfig.INITIAL_STRESS

var max_energy: float = 100.0
var energy: float = 100.0
var daily_energy_recovery_rate: float = 1.0

## 年龄提供的原始点数，以及最终已选择的特质。
var base_trait_points: int = 0
var selected_trait_ids: Array[String] = []


func reset_to_defaults() -> void:
	is_character_created = false
	player_name = ""
	gender = ""
	age = 20
	difficulty_id = "normal"
	selected_preset_id = ""

	cash = SettlementConfig.INITIAL_CASH
	stress = SettlementConfig.INITIAL_STRESS

	max_energy = 100.0
	energy = 100.0
	daily_energy_recovery_rate = 1.0

	base_trait_points = 0
	selected_trait_ids.clear()


func get_used_trait_points() -> int:
	var total := 0
	for trait_id in selected_trait_ids:
		var trait_data := CharacterCreationData.get_trait(trait_id)
		if trait_data != null:
			total += trait_data.point_cost
	return total


func get_remaining_trait_points() -> int:
	return base_trait_points - get_used_trait_points()


func has_trait(trait_id: String) -> bool:
	return trait_id in selected_trait_ids


func get_selected_trait_for_type(trait_type: String) -> String:
	for trait_id in selected_trait_ids:
		var trait_data := CharacterCreationData.get_trait(trait_id)
		if trait_data != null and trait_data.trait_type == trait_type:
			return trait_id
	return ""


## 用于后续接入调研、行动、谈判与经营结算。
## 对数值型 effect 采用“加总”规则；倍率类字段由调用方自行约定默认值。
func get_trait_modifier(effect_key: String, default_value: float = 0.0) -> float:
	var value := default_value
	for trait_id in selected_trait_ids:
		var trait_data := CharacterCreationData.get_trait(trait_id)
		if trait_data == null:
			continue
		if trait_data.effects.has(effect_key):
			value += float(trait_data.effects[effect_key])
	return value


func get_trait_multiplier(effect_key: String, default_value: float = 1.0) -> float:
	var value := default_value
	for trait_id in selected_trait_ids:
		var trait_data := CharacterCreationData.get_trait(trait_id)
		if trait_data == null:
			continue
		if trait_data.effects.has(effect_key):
			value *= float(trait_data.effects[effect_key])
	return value


func apply_character_setup(data: Dictionary) -> void:
	var bracket: Dictionary = CharacterCreationData.get_age_bracket(int(data.age))
	var selected_ids: Array[String] = []

	for trait_id in data.get("trait_ids", []):
		selected_ids.append(str(trait_id))

	is_character_created = true
	player_name = str(data.player_name).strip_edges()
	gender = str(data.gender)
	age = int(data.age)
	difficulty_id = str(data.difficulty_id)
	selected_preset_id = str(data.get("preset_id", ""))

	cash = float(data.starting_cash)
	stress = SettlementConfig.INITIAL_STRESS

	base_trait_points = int(bracket.trait_points)
	selected_trait_ids = selected_ids

	var energy_bonus := get_trait_modifier("max_energy_add", 0.0)
	max_energy = maxf(1.0, float(bracket.max_energy) + energy_bonus)
	energy = max_energy
	daily_energy_recovery_rate = float(bracket.daily_energy_recovery_rate)


## 结算后应用财务与压力变化。
## 口碑变化仍在 StoreState.apply_settlement() 中处理。
func apply_settlement(result: SettlementResult) -> void:
	cash += result.profit

	var stress_multiplier := get_trait_multiplier("stress_gain_mult", 1.0)
	stress = clampf(
		stress + result.stress_delta * stress_multiplier,
		0.0,
		100.0
	)


func to_save_dict() -> Dictionary:
	return {
		"version": 2,
		"is_character_created": is_character_created,
		"player_name": player_name,
		"gender": gender,
		"age": age,
		"difficulty_id": difficulty_id,
		"selected_preset_id": selected_preset_id,

		"cash": cash,
		"stress": stress,

		"max_energy": max_energy,
		"energy": energy,
		"daily_energy_recovery_rate": daily_energy_recovery_rate,

		"base_trait_points": base_trait_points,
		"selected_trait_ids": selected_trait_ids,
	}


static func from_save_dict(data: Dictionary) -> PlayerState:
	var p := PlayerState.new()

	p.is_character_created = data.get("is_character_created", false)
	p.player_name = str(data.get("player_name", ""))
	p.gender = str(data.get("gender", ""))
	p.age = int(data.get("age", 20))
	p.difficulty_id = str(data.get("difficulty_id", "normal"))
	p.selected_preset_id = str(data.get("selected_preset_id", ""))

	p.cash = float(data.get("cash", SettlementConfig.INITIAL_CASH))
	p.stress = float(data.get("stress", SettlementConfig.INITIAL_STRESS))

	p.max_energy = float(data.get("max_energy", 100.0))
	p.energy = float(data.get("energy", p.max_energy))
	p.daily_energy_recovery_rate = float(data.get(
		"daily_energy_recovery_rate",
		1.0
	))

	p.base_trait_points = int(data.get("base_trait_points", 0))

	var raw_trait_ids: Array = data.get("selected_trait_ids", [])
	var typed_trait_ids: Array[String] = []
	for trait_id in raw_trait_ids:
		typed_trait_ids.append(str(trait_id))
	p.selected_trait_ids = typed_trait_ids

	return p
