class_name GameEventDefinition
extends RefCounted

enum Scope { PLAYER, BLOCK, CITY_REGION, STOREFRONT, STORE }
enum Interaction { NOTICE, DECISION, INTERRUPT }

var id: String = ""
var scope: int = Scope.PLAYER
var interaction: int = Interaction.NOTICE
## Presentation is independent from interaction: notices do not pause by
## default, decisions do, and urgent events can opt in explicitly.
var pauses_time: bool = false
var urgent: bool = false
var chain_id: String = ""
var node_id: String = ""
var trigger_kind: String = ""
var weight: float = 1.0
var cooldown_hours: float = 0.0
var minimum_understanding: float = 0.0
var allowed_block_types: Array[String] = []
var required_block_tags: Array[String] = []
var allowed_hours: Array[int] = []
var required_action_ids: Array[String] = []
var required_action_effect_types: Array[String] = []
var title: String = ""
var message: String = ""
## Optional prose alternatives for recurring events. The activated instance
## stores the selected text, so its history and save data remain stable.
var message_variants: Array[String] = []
var effects: Array[Dictionary] = []
var options: Array[Dictionary] = []
