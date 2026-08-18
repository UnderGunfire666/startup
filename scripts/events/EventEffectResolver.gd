class_name EventEffectResolver
extends RefCounted

static func apply(event: ActiveGameEvent) -> void:
	for effect in event.effects:
		var effect_type := str(effect.get("type", ""))
		match effect_type:
			"player_energy_add":
				GameManager.player_state.energy = clampf(
					GameManager.player_state.energy + float(effect.get("amount", 0.0)),
					0.0, GameManager.player_state.max_energy)
			"player_stress_add":
				GameManager.player_state.stress = clampf(
					GameManager.player_state.stress + float(effect.get("amount", 0.0)), 0.0, 100.0)
			"block_understanding_add":
				var amount := float(effect.get("amount", 0.0))
				if amount > 0.0 and not event.target_id.is_empty():
					GameManager.advance_block_understanding(event.target_id, amount)
					var block := GameManager.get_block(event.target_id)
					if block != null:
						GameManager.recalculate_region_intel(block.city_region_id)
			"temporary_modifier":
				EventManager.add_temporary_modifier(
					int(effect.get("scope", event.scope)), event.target_id,
					str(effect.get("key", "")), float(effect.get("value", 0.0)),
					float(effect.get("duration_hours", 0.0)))
