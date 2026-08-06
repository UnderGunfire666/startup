class_name SettlementConfig

# ── 时段等价小时数 ──────────────────────────────────────
const SLOT_HOURS: Dictionary = {
	"midnight": 5,
	"dawn":     4,
	"noon":     2,
	"night":    6
}

const SLOT_NAMES: Dictionary = {
	"midnight": "深夜",
	"dawn":     "清晨",
	"noon":     "午间",
	"night":    "晚夜"
}

const SLOT_ORDER: Array = ["midnight", "dawn", "noon", "night"]

# ── 到店率范围（原0.15上限过低，调整为更真实区间） ──────────
const ENTRY_RATE_MIN: float = 0.02
const ENTRY_RATE_MAX: float = 0.40

# ── 区域人流真实感：周末与每日随机波动 ────────────────────
## day 从1开始计数，7天一周；day % 7 == 6 或 0 视为周末（周六/周日）
const WEEKEND_DAY_REMAINDERS: Array = [6, 0]

## 每日人流随机浮动区间（同一天同一区域同一时段的人流会在此范围内波动）
const TRAFFIC_FLUCTUATION_MIN: float = 0.80
const TRAFFIC_FLUCTUATION_MAX: float = 1.25

# ── 客群匹配权重 ─────────────────────────────────────────
# 每个主客群命中加权值；次客群命中×0.5；完全不匹配总扣减
const GROUP_MATCH_PRIMARY_WEIGHT: float  = 0.006
const GROUP_MATCH_SECONDARY_WEIGHT: float = 0.003
const GROUP_NO_MATCH_PENALTY: float      = -0.012

# ── 时段匹配 ─────────────────────────────────────────────
const SLOT_MATCH_BONUS: float    = 0.010
const SLOT_MISMATCH_PENALTY: float = -0.008

# ── 消费能力匹配 ─────────────────────────────────────────
# key = "price_tier_spending_power"
const SPENDING_POWER_MOD: Dictionary = {
	"low_low":      0.006,
	"low_medium":   0.002,
	"low_high":    -0.015,
	"medium_low":  -0.006,
	"medium_medium": 0.005,
	"medium_high": -0.008,
	"high_low":    -0.022,
	"high_medium": -0.008,
	"high_high":    0.010
}

# ── 装修修正 ─────────────────────────────────────────────
const DECORATION_MOD: Dictionary = {
	"poor":   -0.005,
	"normal":  0.000,
	"good":    0.006
}

# ── 差异化修正（到店率） ──────────────────────────────────
const DIFFERENTIATION_ENTRY_MOD: Dictionary = {
	"normal":        0.000,
	"special":       0.005,
	"strong_special": 0.010
}

# ── 口碑对到店率的最大影响（reputation=100时+max，=0时-max） ──
const REPUTATION_MAX_ENTRY_MOD: float = 0.015

# ── 竞争惩罚 ─────────────────────────────────────────────
const COMPETITION_PENALTY: Dictionary = {
	"low":    0.005,
	"medium": 0.010,
	"high":   0.018
}
# 差异化抵消竞争惩罚的量
const COMPETITION_DIFF_OFFSET: Dictionary = {
	"normal":        0.000,
	"special":       0.004,
	"strong_special": 0.009
}

# ── 停留性对非偏好品类的额外惩罚（仅用于特定品类×区域组合） ──
# 停留性low + 品类preferred_dwell_required=true 时施加
const DWELL_MISMATCH_PENALTY: float = -0.008

# ── 成交率 ───────────────────────────────────────────────
const BASE_CONVERSION_RATE: float = 0.85
const CONVERSION_RATE_MIN: float  = 0.05
const CONVERSION_RATE_MAX: float  = 0.98

# ── 设备状态对容量的影响 ──────────────────────────────────
const EQUIPMENT_CAPACITY_MOD: Dictionary = {
	"poor":   0.75,
	"normal": 1.00,
	"good":   1.20
}

# ── 服务速度对容量的影响 ──────────────────────────────────
const SERVICE_SPEED_MOD: Dictionary = {
	"high":   1.00,
	"medium": 0.75,
	"slow":   0.50
}

# ── 营业策略修正 ──────────────────────────────────────────
const STRATEGY_EXTEND_ENTRY_PENALTY: float     = -0.005  # 非默认时段到店率惩罚
const STRATEGY_EXTEND_COST_MULTIPLIER: float   =  1.20   # 员工成本倍率
const STRATEGY_SHORTEN_COST_MULTIPLIER: float  =  0.80

# ── 损耗配置 ─────────────────────────────────────────────
const WASTE_THRESHOLD_RATIO: float  = 1.20   # 库存 > 销量×1.20 才计损耗
const WASTE_COST_RATIO_OF_INGREDIENT: float = 0.10  # 超量部分×食材成本×10%

# ── 压力阈值与成交率惩罚 ──────────────────────────────────
const STRESS_HIGH_THRESHOLD: float    = 70.0
const STRESS_CONVERSION_PENALTY: float = 0.05

const MARGIN_DEVIATION_ENTRY_COEFFICIENT: float = 0.08  # 毛利率偏离1个百分点对到店率的影响系数
const MARGIN_DEVIATION_MAX_PENALTY: float = 0.05        # 定价过高的到店率惩罚上限
const MARGIN_DEVIATION_MAX_BONUS: float = 0.03          # 定价亲民的到店率加成上限（通常小于惩罚，避免"越便宜越好"无限套利）

# ── 口碑变化参数 ──────────────────────────────────────────
const REPUTATION_PER_SLOT_MAX_CHANGE: float = 3.0   # 单时段最大变化
const REPUTATION_GOOD_THRESHOLD: float      = 0.80  # 订单完成率≥80%算良好
const REPUTATION_BAD_THRESHOLD: float       = 0.40

# ── 压力变化参数 ──────────────────────────────────────────
const STRESS_LOSS_PER_SLOT: float     = 3.0    # 亏损时压力上升
const STRESS_OVERLOAD_PER_SLOT: float = 4.0    # 容量超载时上升
const STRESS_REST_PER_DAY: float      = 5.0    # 每日结算时自然下降

# ── 门面品类适配强制校验（正常游戏模式） ─────────────────────
const ENFORCE_CATEGORY_RESTRICTION: bool = true  # 调试模式可覆盖

# ── 初始门店状态 ──────────────────────────────────────────
const INITIAL_CASH: float      = 100000.0
const INITIAL_REPUTATION: float = 50.0
const INITIAL_STRESS: float     = 20.0
const INITIAL_INVENTORY: int    = 100

# ── 门面基础水电（与面积相关，每时段仅结算一次） ─────────────
const BASE_UTILITY_COST_PER_AREA_PER_SLOT: float = 0.8  # 元/㎡/时段
