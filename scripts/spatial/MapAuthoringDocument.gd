class_name MapAuthoringDocument
extends RefCounted

var road_graph: RoadGraph = RoadGraph.new()
var blocks: Array[BlockData] = []
var storefronts: Array[StorefrontData] = []


static func from_static_data() -> MapAuthoringDocument:
	var document := MapAuthoringDocument.new()
	var source_graph := GameData.get_road_graph()
	for raw_node in source_graph.nodes.values():
		var source_node := raw_node as RoadNode
		if source_node == null:
			continue
		var node := RoadNode.new()
		node.id = source_node.id
		node.position = source_node.position
		document.road_graph.add_node(node)
	for source_segment in source_graph.segments:
		var segment := RoadSegment.new()
		segment.id = source_segment.id
		segment.from_node_id = source_segment.from_node_id
		segment.to_node_id = source_segment.to_node_id
		segment.accessibility = source_segment.accessibility
		segment.exposure = source_segment.exposure
		document.road_graph.add_segment(segment)
	for source_block in GameData.get_blocks():
		document.blocks.append(source_block.duplicate() as BlockData)
	for source_storefront in GameData.get_storefronts():
		document.storefronts.append(source_storefront.duplicate() as StorefrontData)
	return document


func add_road_node(node_id: String, position: Vector2) -> bool:
	var node := RoadNode.new()
	node.id = node_id
	node.position = position
	return road_graph.add_node(node)


func move_road_node(node_id: String, position: Vector2) -> bool:
	var node: RoadNode = road_graph.nodes.get(node_id, null)
	if node == null:
		return false
	node.position = position
	return true


func add_road_segment(segment_id: String, from_node_id: String, to_node_id: String, accessibility: float = 1.0, exposure: float = 1.0) -> bool:
	if _has_road_segment(segment_id):
		return false
	var segment := RoadSegment.new()
	segment.id = segment_id
	segment.from_node_id = from_node_id
	segment.to_node_id = to_node_id
	segment.accessibility = accessibility
	segment.exposure = exposure
	return road_graph.add_segment(segment)


func assign_block_road_entry(block_id: String, node_id: String) -> bool:
	if not road_graph.nodes.has(node_id):
		return false
	for block in blocks:
		if block.id == block_id:
			block.road_entry_node_id = node_id
			return true
	return false


func assign_storefront_nearest_road(storefront_id: String) -> bool:
	var storefront := _get_storefront(storefront_id)
	if storefront == null or road_graph.segments.is_empty():
		return false
	var nearest_segment_id := ""
	var nearest_distance := INF
	for segment in road_graph.segments:
		var from_node: RoadNode = road_graph.nodes.get(segment.from_node_id, null)
		var to_node: RoadNode = road_graph.nodes.get(segment.to_node_id, null)
		if from_node == null or to_node == null:
			continue
		var distance := _distance_to_segment(storefront.map_position, from_node.position, to_node.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_segment_id = segment.id
	if nearest_segment_id.is_empty():
		return false
	storefront.road_segment_id = nearest_segment_id
	return true


func move_storefront(storefront_id: String, position: Vector2) -> bool:
	var storefront := _get_storefront(storefront_id)
	if storefront == null:
		return false
	storefront.map_position = position
	return assign_storefront_nearest_road(storefront_id)


func move_block(block_id: String, center_position: Vector2) -> bool:
	for block in blocks:
		if block.id != block_id:
			continue
		var offset := center_position - block.center_position
		block.center_position = center_position
		block.map_bounds.position += offset
		return true
	return false


func validate() -> Array[String]:
	return MapDataValidator.validate(road_graph, blocks, storefronts)


func export_roads_data() -> Dictionary:
	var errors := validate()
	if not errors.is_empty():
		return {"success": false, "errors": errors, "roads": []}
	return {"success": true, "errors": [], "roads": _serialize_roads()}


func export_map_data() -> Dictionary:
	var errors := validate()
	if not errors.is_empty():
		return {"success": false, "errors": errors, "roads": [], "blocks": [], "storefronts": []}
	var serialized_blocks: Array[Dictionary] = []
	for block in blocks:
		serialized_blocks.append({
			"id": block.id, "name": block.name, "city_region_id": block.city_region_id,
			"road_entry_node_id": block.road_entry_node_id,
			"map_bounds": {"x": block.map_bounds.position.x, "y": block.map_bounds.position.y, "w": block.map_bounds.size.x, "h": block.map_bounds.size.y},
			"center_position": {"x": block.center_position.x, "y": block.center_position.y},
			"block_type": block.block_type, "tier": block.tier, "area": block.area,
			"development_factor": block.development_factor, "accessibility": block.accessibility,
			"active_time_profile": block.active_time_profile.duplicate(true),
			"group_supply_weights": block.group_supply_weights.duplicate(true),
			"spending_profile": block.spending_profile.duplicate(true),
			"business_demand_tags": block.business_demand_tags.duplicate(),
			"competition_profile": block.competition_profile.duplicate(true),
			"tags": block.tags.duplicate(), "notes": block.notes,
		})
	var serialized_storefronts: Array[Dictionary] = []
	for storefront in storefronts:
		serialized_storefronts.append({
			"id": storefront.id, "name": storefront.name, "region_id": storefront.region_id,
			"city_region_id": storefront.city_region_id,
			"road_segment_id": storefront.road_segment_id,
			"map_position": {"x": storefront.map_position.x, "y": storefront.map_position.y},
			"capture_modifier": storefront.capture_modifier,
			"accessibility_modifier": storefront.accessibility_modifier,
			"monthly_rent_wan": storefront.monthly_rent_wan, "area": storefront.area,
			"decoration_level": storefront.decoration_level, "storefront_flow": storefront.storefront_flow,
			"flow_share": storefront.flow_share,
			"supported_categories": storefront.supported_categories.duplicate(),
			"equipment_condition": storefront.equipment_condition,
			"hourly_capacity_base": storefront.hourly_capacity_base, "notes": storefront.notes,
		})
	return {
		"success": true, "errors": [], "roads": _serialize_roads(),
		"blocks": serialized_blocks, "storefronts": serialized_storefronts,
	}


func export_json_files() -> Dictionary:
	var exported := export_map_data()
	if not bool(exported.get("success", false)):
		return {"success": false, "errors": exported.get("errors", []), "files": {}}
	return {
		"success": true, "errors": [],
		"files": {
			"roads.json": JSON.stringify(exported.get("roads", []), "\t"),
			"blocks.json": JSON.stringify(exported.get("blocks", []), "\t"),
			"storefronts.json": JSON.stringify(exported.get("storefronts", []), "\t"),
		},
	}


func _serialize_roads() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var node_ids: Array[String] = []
	for node_id in road_graph.nodes.keys():
		node_ids.append(str(node_id))
	node_ids.sort()
	for node_id in node_ids:
		var node: RoadNode = road_graph.nodes.get(node_id, null)
		if node == null:
			continue
		entries.append({
			"kind": "node", "id": node.id,
			"position": {"x": node.position.x, "y": node.position.y},
		})
	for segment in road_graph.segments:
		entries.append({
			"kind": "segment", "id": segment.id,
			"from_node_id": segment.from_node_id, "to_node_id": segment.to_node_id,
			"accessibility": segment.accessibility, "exposure": segment.exposure,
		})
	return entries


func _has_road_segment(segment_id: String) -> bool:
	for segment in road_graph.segments:
		if segment.id == segment_id:
			return true
	return false


func _get_storefront(storefront_id: String) -> StorefrontData:
	for storefront in storefronts:
		if storefront.id == storefront_id:
			return storefront
	return null


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var direction := to - from
	if is_zero_approx(direction.length_squared()):
		return point.distance_to(from)
	var ratio := clampf((point - from).dot(direction) / direction.length_squared(), 0.0, 1.0)
	return point.distance_to(from + direction * ratio)
