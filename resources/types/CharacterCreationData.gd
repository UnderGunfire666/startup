class_name CharacterCreationData
extends RefCounted

const DIFFICULTIES: Array[Dictionary] = [
	{
		"id": "easy",
		"name": "试营业",
		"starting_cash": 150000.0,
		"description": "资金较充足，允许多做调研，也能承受一次较大的前期失误。"
	},
	{
		"id": "normal",
		"name": "自主创业",
		"starting_cash": 100000.0,
		"description": "标准创业条件，需要认真权衡调研、门面、品类与备货投入。"
	},
	{
		"id": "hard",
		"name": "资金紧张",
		"starting_cash": 70000.0,
		"description": "每一笔开销都需要取舍，适合熟悉经营循环后挑战。"
	},
	{
		"id": "challenge",
		"name": "背水一战",
		"starting_cash": 50000.0,
		"description": "仅适合低投入起步路线；重大失误可能让开业计划停滞。"
	},
]

const AGE_BRACKETS: Array[Dictionary] = [
	{
		"id": "young",
		"name": "初入社会（20—27岁）",
		"ages": [20, 21, 22, 23, 24, 25, 26, 27],
		"trait_points": 2,
		"max_energy": 100.0,
		"daily_energy_recovery_rate": 1.0,
	},
	{
		"id": "growth",
		"name": "积累期（28—37岁）",
		"ages": [28, 29, 30, 31, 32, 33, 34, 35, 36, 37],
		"trait_points": 4,
		"max_energy": 90.0,
		"daily_energy_recovery_rate": 0.95,
	},
	{
		"id": "mature",
		"name": "成熟期（38—47岁）",
		"ages": [38, 39, 40, 41, 42, 43, 44, 45, 46, 47],
		"trait_points": 6,
		"max_energy": 80.0,
		"daily_energy_recovery_rate": 0.90,
	},
	{
		"id": "transition",
		"name": "转型期（48—58岁）",
		"ages": [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58],
		"trait_points": 8,
		"max_energy": 70.0,
		"daily_energy_recovery_rate": 0.85,
	},
]

const TRAIT_TYPE_ORDER: Array[String] = [
	"body",
	"insight",
	"temperament",
	"social",
]

const TRAIT_TYPE_NAMES := {
	"body": "身体素质",
	"insight": "市场洞察",
	"temperament": "经营心态",
	"social": "商务社交",
}

static func get_difficulty(difficulty_id: String) -> Dictionary:
	for difficulty in DIFFICULTIES:
		if difficulty.id == difficulty_id:
			return difficulty
	return DIFFICULTIES[1] if not DIFFICULTIES.is_empty() else {}


static func get_age_bracket(age: int) -> Dictionary:
	for bracket in AGE_BRACKETS:
		if age in bracket.ages:
			return bracket
	return AGE_BRACKETS[0]


static func get_all_ages() -> Array[int]:
	var result: Array[int] = []
	for bracket in AGE_BRACKETS:
		for age in bracket.ages:
			result.append(age)
	return result


static func get_traits() -> Array[TraitData]:
	var traits: Array[TraitData] = []

	traits.append(_make_trait(
		"energetic",
		"精力充沛",
		"身体素质",
		"body",
		4,
		true,
		"最大精力 +15；后续行动系统接入后，疲惫惩罚降低。",
		{"max_energy_add": 15.0, "fatigue_threshold_add": 1.0}
	))

	traits.append(_make_trait(
		"lethargic",
		"萎靡不振",
		"身体素质",
		"body",
		-4,
		false,
		"最大精力 -15；后续行动系统接入后，更早进入疲惫状态。",
		{"max_energy_add": -15.0, "fatigue_threshold_add": -1.0}
	))

	traits.append(_make_trait(
		"market_instinct",
		"市场嗅觉",
		"市场洞察",
		"insight",
		4,
		true,
		"后续区域调研与门面考察将更早获得关键市场信息。",
		{"research_info_bonus": 1.0}
	))

	traits.append(_make_trait(
		"information_isolated",
		"信息闭塞",
		"市场洞察",
		"insight",
		-4,
		false,
		"后续调研中部分信息获取更慢，或需要额外投入。",
		{"research_info_bonus": -1.0}
	))

	traits.append(_make_trait(
		"stress_resistant",
		"抗压达人",
		"经营心态",
		"temperament",
		3,
		true,
		"经营亏损、缺货、容量不足带来的压力增幅降低。",
		{"stress_gain_mult": 0.80}
	))

	traits.append(_make_trait(
		"anxious",
		"焦虑易感",
		"经营心态",
		"temperament",
		-3,
		false,
		"经营问题带来的压力增幅提高。",
		{"stress_gain_mult": 1.25}
	))

	traits.append(_make_trait(
		"negotiator",
		"谈判老手",
		"商务社交",
		"social",
		5,
		true,
		"后续供应商、房东与员工相关谈判将获得优势。",
		{"negotiation_bonus": 1.0}
	))

	traits.append(_make_trait(
		"socially_awkward",
		"不善交际",
		"商务社交",
		"social",
		-5,
		false,
		"后续谈判和招聘类行动更容易付出额外成本。",
		{"negotiation_bonus": -1.0}
	))

	return traits


static func get_trait(trait_id: String) -> TraitData:
	for trait_data in get_traits():
		if trait_data.id == trait_id:
			return trait_data
	return null


static func get_traits_by_type(trait_type: String) -> Array[TraitData]:
	var result: Array[TraitData] = []
	for trait_data in get_traits():
		if trait_data.trait_type == trait_type:
			result.append(trait_data)
	return result


## 预设人物是“已完成的自定义角色方案”，不会获得隐藏资源加成。
## 每个预设的年龄点数 - 已选特质成本 = 0。
static func get_presets() -> Array[Dictionary]:
	return [
		{
			"id": "steady_shopkeeper",
			"name": "稳健小店主",
			"gender": "female",
			"age": 37,
			"trait_ids": [
				"energetic",
				"stress_resistant",
				"socially_awkward",
			],
			"description": "精力和抗压能力较好，社交谈判较弱；适合持续坐镇、稳步经营。"
		},
		{
			"id": "site_selector",
			"name": "精明选址者",
			"gender": "male",
			"age": 47,
			"trait_ids": [
				"lethargic",
				"market_instinct",
				"negotiator",
				"anxious",
			],
			"description": "信息与谈判能力突出，但精力和压力管理是明显短板。"
		},
		{
			"id": "night_market_adventurer",
			"name": "夜市冒险家",
			"gender": "male",
			"age": 37,
			"trait_ids": [
				"energetic",
				"information_isolated",
				"stress_resistant",
				"socially_awkward",
			],
			"description": "耐力和抗压较强，但市场情报与商务协作能力偏弱。"
		},
	]


static func _make_trait(
		id: String,
		display_name: String,
		_type_name: String,
		trait_type: String,
		point_cost: int,
		is_positive: bool,
		description: String,
		effects: Dictionary
) -> TraitData:
	var trait_data := TraitData.new()
	trait_data.id = id
	trait_data.display_name = display_name
	trait_data.trait_type = trait_type
	trait_data.point_cost = point_cost
	trait_data.is_positive = is_positive
	trait_data.description = description
	trait_data.effects = effects
	return trait_data
