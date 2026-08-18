class_name MapDataValidator
extends RefCounted

static func validate(graph: RoadGraph, blocks: Array[BlockData], storefronts: Array[StorefrontData]) -> Array[String]:
	var errors := graph.validate()
	var segment_ids: Dictionary = {}
	var block_ids: Dictionary = {}
	var storefront_ids: Dictionary = {}
	for segment in graph.segments:
		if segment_ids.has(segment.id):
			errors.append("duplicate road segment id %s" % segment.id)
		segment_ids[segment.id] = true
	for block in blocks:
		if block_ids.has(block.id):
			errors.append("duplicate block id %s" % block.id)
		block_ids[block.id] = true
		if block.road_entry_node_id.is_empty() or not graph.nodes.has(block.road_entry_node_id):
			errors.append("block %s has no valid road entry" % block.id)
	for storefront in storefronts:
		if storefront_ids.has(storefront.id):
			errors.append("duplicate storefront id %s" % storefront.id)
		storefront_ids[storefront.id] = true
		if storefront.road_segment_id.is_empty() or not segment_ids.has(storefront.road_segment_id):
			errors.append("storefront %s has no valid road segment" % storefront.id)
		var inside_block := false
		for block in blocks:
			if block.city_region_id == storefront.city_region_id and block.has_map_point(storefront.map_position):
				inside_block = true
				break
		if not inside_block:
			errors.append("storefront %s is not inside a block" % storefront.id)
	return errors


static func build_report(graph: RoadGraph, blocks: Array[BlockData], storefronts: Array[StorefrontData]) -> Dictionary:
	var errors := validate(graph, blocks, storefronts)
	return {
		"node_count": graph.nodes.size(),
		"segment_count": graph.segments.size(),
		"block_count": blocks.size(),
		"storefront_count": storefronts.size(),
		"errors": errors,
		"is_valid": errors.is_empty(),
	}
