extends PanelContainer

@onready var status_label: RichTextLabel = $MarginContainer/VBox/StatusScroll/StatusLabel


func refresh() -> void:
	var player := GameManager.player_state
	if not player.is_character_created:
		status_label.text = "[color=gray]尚未创建角色。[/color]"
		return

	var difficulty: Dictionary = CharacterCreationData.get_difficulty(player.difficulty_id)
	var gender := "女" if player.gender == "female" else "男"
	var preset := player.selected_preset_id if not player.selected_preset_id.is_empty() else "自定义角色"
	var location := "尚未定位"
	var block := GameManager.get_block(player.current_block_id)
	if block != null:
		location = block.name
	var supervising := "未坐镇"
	if not player.supervising_store_id.is_empty():
		var store := GameManager.get_store(player.supervising_store_id)
		supervising = store.name if store != null else player.supervising_store_id

	var trait_lines: Array[String] = []
	for trait_id in player.selected_trait_ids:
		var trait_data := CharacterCreationData.get_trait(trait_id)
		if trait_data != null:
			trait_lines.append("• %s（%s）\n  %s" % [trait_data.display_name, CharacterCreationData.TRAIT_TYPE_NAMES.get(trait_data.trait_type, trait_data.trait_type), trait_data.description])
	if trait_lines.is_empty():
		trait_lines.append("未选择特质")

	var skills := "无"
	if not player.work_skills.is_empty():
		skills = "、".join(player.work_skills)
	var debt_text := "无" if player.energy_debt <= 0.0 else "%.1f" % player.energy_debt
	status_label.text = "[b]身份[/b]\n姓名：%s\n性别：%s\n年龄：%d\n难度：%s\n预设：%s\n\n[b]特质[/b]\n%s\n\n[b]状态资源[/b]\n现金：¥%.0f\n压力：%.1f\n精力：%.1f / %.1f\n精力透支：%s\n每日精力恢复：%.0f%%\n疲劳状态：%s\n今日工时：%.1f 小时\n\n[b]位置与能力[/b]\n当前位置：%s\n当前坐镇：%s\n工作技能：%s\n技能等级：%.1f" % [
		player.player_name, gender, player.age, str(difficulty.get("name", player.difficulty_id)), preset,
		"\n".join(trait_lines), player.cash, player.stress, player.energy, player.max_energy, debt_text,
		player.daily_energy_recovery_rate * 100.0, player.fatigue_state, player.work_hours_today,
		location, supervising, skills, player.work_skill_level,
	]
