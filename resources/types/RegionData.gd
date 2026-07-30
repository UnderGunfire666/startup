class_name RegionData
extends Resource

## ── 核心标识 ────────────────────────────────────────
@export var id: String = ""
@export var name: String = ""

## ── 人口与消费属性 ──────────────────────────────────
@export var radiation_population: int = 0
@export var population_density: String = "medium"
@export var primary_groups: Array[String] = []
@export var secondary_groups: Array[String] = []
@export var spending_power: String = "medium"
@export var dwell_time: String = "medium"

## ── 交通与竞争 ──────────────────────────────────────
@export var traffic_sources: Array[String] = []
@export var competition_level: String = "medium"
@export var rent_baseline: String = "medium"

## ── 客流与周末表现 ──────────────────────────────────
## key 为 SettlementConfig.SLOT_ORDER 里的时段字符串
## 例如 {"morning": 800, "noon": 1500, "afternoon": 600, "evening": 1200, "night": 300}
@export var hourly_foot_traffic_by_slot: Dictionary = {}

## 周末客流倍率，例如 1.3 表示周末客流是工作日的1.3倍
@export var weekend_modifier: float = 1.0

## ── 展示说明 ────────────────────────────────────────
@export var notes: String = ""

## ── 调研付费（展示层专用，GameData 目前未赋值，保留默认即可） ──
@export var research_cost: float = 800.0
