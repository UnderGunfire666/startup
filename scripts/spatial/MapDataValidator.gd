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
		if block.internal_road_cells.is_empty():
			errors.append("block %s has no internal roads" % block.id)
		for cell in block.internal_road_cells:
			if not block.grid_cells.has(cell):
				errors.append("block %s internal road lies outside its cells" % block.id)
	var external_center_cells := MapGridGeometry.build_road_center_cells(graph)
	for block in blocks:
		for cell in block.grid_cells:
			if external_center_cells.has(cell):
				errors.append("block %s overlaps an external road centre line" % block.id)
				break
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
		for block in blocks:
			if block.id == storefront.block_id:
				for cell in storefront.grid_cells:
					if block.internal_road_cells.has(cell):
						errors.append("storefront %s overlaps an internal road" % storefront.id)
						break
	var navigation := MapNavigationGrid.build(graph, blocks, storefronts)
	var external_cells := MapGridGeometry.build_road_cells(graph)
	for block in blocks:
		var has_external_connection := false
		for lane in block.internal_road_cells:
			for direction in MapNavigationGrid.CARDINALS:
				var neighbor := lane + direction
				if external_cells.has(neighbor) and not navigation.cell_blocks.has(neighbor):
					has_external_connection = true
					break
			if has_external_connection:
				break
		if not has_external_connection:
			errors.append("block %s internal roads do not meet an external road" % block.id)
	for storefront in storefronts:
		var entrance: Dictionary = navigation.storefront_entrances.get(storefront.id, {})
		if entrance.is_empty():
			errors.append("storefront %s has no navigable entrance" % storefront.id)
			continue
		var can_reach_external := false
		for road_cell in external_cells:
			if navigation.cell_blocks.has(road_cell):
				continue
			if not navigation.shortest_path(entrance.cell, road_cell).is_empty():
				can_reach_external = true
				break
		if not can_reach_external:
			errors.append("storefront %s entrance is unreachable" % storefront.id)
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
