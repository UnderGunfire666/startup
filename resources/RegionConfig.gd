class_name RegionConfig

## 每小时"区域调研"行动带来的了解程度增量（不是一次性总量）。
## 区域调研行动时长2小时，跑满全程总共获得20%（2×10%），
## 中途只做1小时就只拿10%，符合"做多久拿多久"的设计。
const FAMILIARITY_GAIN_PER_HOUR: float = 10.0

## 默认门槛：多数角色需要达到这个了解/兴趣程度才能选定区域开店。
## 特质会在这个基础上做加减修正，见 PlayerState.get_required_region_familiarity()。
const DEFAULT_OPEN_FAMILIARITY_THRESHOLD: float = 40.0
const DEFAULT_OPEN_INTEREST_THRESHOLD: float = 0.0
