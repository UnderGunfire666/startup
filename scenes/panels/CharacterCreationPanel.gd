extends PanelContainer

signal character_created

@onready var difficulty_option: OptionButton = $MarginContainer/RootVBox/SplitBox/LeftPanel/DifficultyRow/DifficultyOption
@onready var name_input: LineEdit = $MarginContainer/RootVBox/SplitBox/LeftPanel/NameRow/NameInput
@onready var male_button: CheckButton = $MarginContainer/RootVBox/SplitBox/LeftPanel/GenderRow/MaleButton
@onready var female_button: CheckButton = $MarginContainer/RootVBox/SplitBox/LeftPanel/GenderRow/FemaleButton
@onready var age_option: OptionButton = $MarginContainer/RootVBox/SplitBox/LeftPanel/AgeRow/AgeOption
@onready var home_option: OptionButton = $MarginContainer/RootVBox/SplitBox/LeftPanel/HomeRow/HomeOption
@onready var preset_list: VBoxContainer = $MarginContainer/RootVBox/SplitBox/LeftPanel/PresetScroll/PresetList

@onready var point_summary_label: RichTextLabel = $MarginContainer/RootVBox/SplitBox/RightPanel/PointSummaryLabel
@onready var trait_list: VBoxContainer = $MarginContainer/RootVBox/SplitBox/RightPanel/TraitScroll/TraitList

@onready var confirm_button: Button = $MarginContainer/RootVBox/ConfirmButton
@onready var status_label: Label = $MarginContainer/RootVBox/StatusLabel

var _gender_group := ButtonGroup.new()
var _trait_options: Dictionary = {}
var _selected_preset_id: String = ""

## 标记玩家是否已经明确做出选择：使用预设，或开始自定义编辑。
## 初始为 false 时禁止确认创建。
var _has_selection: bool = false


func _ready() -> void:
	male_button.button_group = _gender_group
	female_button.button_group = _gender_group

	name_input.text_changed.connect(func(_text: String) -> void:
		_mark_custom_edit()
	)

	male_button.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_mark_custom_edit()
	)

	female_button.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_mark_custom_edit()
	)

	difficulty_option.item_selected.connect(func(_index: int) -> void:
		_refresh_summary()
	)

	age_option.item_selected.connect(func(_index: int) -> void:
		_mark_custom_edit()
	)
	home_option.item_selected.connect(func(_index: int) -> void: _mark_custom_edit())

	confirm_button.pressed.connect(_on_confirm_pressed)

	_build_difficulty_options()
	_build_age_options()
	_build_home_options()
	_build_trait_options()
	refresh()


func refresh() -> void:
	status_label.text = ""
	_build_preset_cards()

	var player := GameManager.player_state
	if player.is_character_created:
		_apply_player_to_form(player)
		_has_selection = true
	else:
		_apply_default_form()
		_has_selection = false

	_refresh_summary()


func _build_difficulty_options() -> void:
	difficulty_option.clear()

	for difficulty in CharacterCreationData.DIFFICULTIES:
		difficulty_option.add_item(
			"%s｜初始资金 ¥%.0f" % [
				difficulty.name,
				float(difficulty.starting_cash),
			]
		)
		difficulty_option.set_item_metadata(
			difficulty_option.item_count - 1,
			difficulty.id
		)

	difficulty_option.select(1)


func _build_age_options() -> void:
	age_option.clear()

	for age in CharacterCreationData.get_all_ages():
		age_option.add_item("%d岁" % age)
		age_option.set_item_metadata(age_option.item_count - 1, age)

	_select_age(28)


func _build_home_options() -> void:
	home_option.clear()
	for home in GameManager.all_player_homes:
		var block := GameManager.get_block(str(home.get("block_id", "")))
		home_option.add_item("%s（%s）" % [str(home.get("name", "")), block.name if block != null else str(home.get("block_id", ""))])
		home_option.set_item_metadata(home_option.item_count - 1, str(home.get("id", "")))
	if home_option.item_count > 0:
		home_option.select(0)


func _build_trait_options() -> void:
	for child in trait_list.get_children():
		child.queue_free()

	_trait_options.clear()

	for trait_type in CharacterCreationData.TRAIT_TYPE_ORDER:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 4)
		trait_list.add_child(section)

		var title := Label.new()
		title.text = "【%s】" % CharacterCreationData.TRAIT_TYPE_NAMES[trait_type]
		title.add_theme_font_size_override("font_size", 16)
		section.add_child(title)

		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_item("不选择该类型特质")
		option.set_item_metadata(0, "")

		for trait_data in CharacterCreationData.get_traits_by_type(trait_type):
			var point_text := "消耗 %d 点" % trait_data.point_cost
			if trait_data.point_cost < 0:
				point_text = "获得 %d 点" % abs(trait_data.point_cost)

			var prefix := "正向" if trait_data.is_positive else "负向"
			option.add_item(
				"[%s] %s（%s）" % [
					prefix,
					trait_data.display_name,
					point_text,
				]
			)
			option.set_item_metadata(option.item_count - 1, trait_data.id)

		option.item_selected.connect(func(_index: int) -> void:
			_mark_custom_edit()
		)

		section.add_child(option)

		var description := Label.new()
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.text = "同类特质互斥；选择负向特质会返还特质点。"
		section.add_child(description)

		section.add_child(HSeparator.new())
		_trait_options[trait_type] = option


func _build_preset_cards() -> void:
	for child in preset_list.get_children():
		child.queue_free()

	for preset in CharacterCreationData.get_presets():
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 4)
		preset_list.add_child(card)

		var title := Label.new()
		title.text = preset.name
		title.add_theme_font_size_override("font_size", 16)
		card.add_child(title)

		var description := Label.new()
		description.text = preset.description
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(description)

		var traits_text: Array[String] = []
		for trait_id in preset.trait_ids:
			var trait_data := CharacterCreationData.get_trait(trait_id)
			if trait_data != null:
				traits_text.append(trait_data.display_name)

		var info := Label.new()
		info.text = "%d岁｜%s" % [
			int(preset.age),
			"、".join(traits_text),
		]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(info)

		var button := Button.new()
		button.text = "使用此预设"
		button.pressed.connect(func() -> void:
			_apply_preset(preset)
		)
		card.add_child(button)

		card.add_child(HSeparator.new())


func _apply_default_form() -> void:
	name_input.text = ""
	male_button.button_pressed = true
	_select_age(28)
	_select_difficulty("normal")
	_selected_preset_id = ""
	if home_option.item_count > 0:
		home_option.select(0)

	for option in _trait_options.values():
		option.select(0)


func _apply_player_to_form(player: PlayerState) -> void:
	name_input.text = player.player_name
	_selected_preset_id = player.selected_preset_id

	if player.gender == "female":
		female_button.button_pressed = true
	else:
		male_button.button_pressed = true

	_select_age(player.age)
	_select_difficulty(player.difficulty_id)
	_select_home(player.home_id)
	_apply_trait_ids(player.selected_trait_ids)


func _apply_preset(preset: Dictionary) -> void:
	name_input.text = preset.name
	_selected_preset_id = preset.id
	_select_home(str(preset.get("home_id", "")))
	_has_selection = true

	if preset.gender == "female":
		female_button.button_pressed = true
	else:
		male_button.button_pressed = true

	_select_age(int(preset.age))
	_apply_trait_ids(preset.trait_ids)
	_refresh_summary()


## 用户手动改动任意自定义字段时调用：视为进入自定义模式，
## 但不清空预设——如果用户只是在预设基础上微调，仍视为已完成选择。
func _mark_custom_edit() -> void:
	_has_selection = true
	_refresh_summary()


func _apply_trait_ids(trait_ids: Array) -> void:
	for option in _trait_options.values():
		option.select(0)

	for trait_id_raw in trait_ids:
		var trait_data := CharacterCreationData.get_trait(str(trait_id_raw))
		if trait_data == null:
			continue

		var option: OptionButton = _trait_options.get(trait_data.trait_type)
		if option == null:
			continue

		for index in range(option.item_count):
			if str(option.get_item_metadata(index)) == trait_data.id:
				option.select(index)
				break


func _get_selected_trait_ids() -> Array[String]:
	var result: Array[String] = []

	for trait_type in CharacterCreationData.TRAIT_TYPE_ORDER:
		var option: OptionButton = _trait_options[trait_type]
		var trait_id := str(option.get_item_metadata(option.selected))
		if not trait_id.is_empty():
			result.append(trait_id)

	return result


func _get_selected_gender() -> String:
	if female_button.button_pressed:
		return "female"
	return "male"


func _get_selected_age() -> int:
	return int(age_option.get_item_metadata(age_option.selected))


func _get_selected_difficulty_id() -> String:
	return str(difficulty_option.get_item_metadata(difficulty_option.selected))


func _select_home(home_id: String) -> void:
	for index in range(home_option.item_count):
		if str(home_option.get_item_metadata(index)) == home_id:
			home_option.select(index)
			return


func _get_selected_home_id() -> String:
	return str(home_option.get_item_metadata(home_option.selected)) if home_option.selected >= 0 else ""


func _refresh_summary() -> void:
	var age := _get_selected_age()
	var bracket := CharacterCreationData.get_age_bracket(age)
	var trait_ids := _get_selected_trait_ids()

	var used_points := 0
	var trait_names: Array[String] = []

	for trait_id in trait_ids:
		var trait_data := CharacterCreationData.get_trait(trait_id)
		if trait_data == null:
			continue

		used_points += trait_data.point_cost
		trait_names.append(trait_data.display_name)

	var remaining_points := int(bracket.trait_points) - used_points
	var max_energy := float(bracket.max_energy)

	for trait_id in trait_ids:
		var trait_data := CharacterCreationData.get_trait(trait_id)
		if trait_data != null:
			max_energy += float(trait_data.effects.get("max_energy_add", 0.0))

	var point_color := "green" if remaining_points >= 0 else "red"
	var traits_text := "无" if trait_names.is_empty() else "、".join(trait_names)

	point_summary_label.text = (
		"[b]特质点余额：[color=%s]%d[/color] / %d[/b]\n"
		+ "最大精力：%.0f｜每日精力恢复：%.0f%%\n"
		+ "已选特质：%s"
	) % [
		point_color,
		remaining_points,
		int(bracket.trait_points),
		max_energy,
		float(bracket.daily_energy_recovery_rate) * 100.0,
		traits_text,
	]

	var name_filled := not name_input.text.strip_edges().is_empty()
	var points_valid := remaining_points >= 0
	var store := GameManager.store_state
	var store_already_open := store != null and store.is_open

	confirm_button.disabled = (
		not _has_selection
		or not name_filled
		or not points_valid
		or store_already_open
	)


func _on_confirm_pressed() -> void:
	var result := GameManager.create_character({
		"player_name": name_input.text,
		"gender": _get_selected_gender(),
		"age": _get_selected_age(),
		"difficulty_id": _get_selected_difficulty_id(),
		"preset_id": _selected_preset_id,
		"home_id": _get_selected_home_id(),
		"trait_ids": _get_selected_trait_ids(),
	})

	if not result.get("success", false):
		status_label.text = "⚠ %s" % result.get("reason", "角色创建失败")
		return

	status_label.text = "✅ %s" % result.get("reason", "角色创建完成")
	character_created.emit()


func _select_age(age: int) -> void:
	for index in range(age_option.item_count):
		if int(age_option.get_item_metadata(index)) == age:
			age_option.select(index)
			return


func _select_difficulty(difficulty_id: String) -> void:
	for index in range(difficulty_option.item_count):
		if str(difficulty_option.get_item_metadata(index)) == difficulty_id:
			difficulty_option.select(index)
			return
