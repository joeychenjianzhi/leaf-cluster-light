extends RefCounted
## MIT License. Copyright (c) 2026 Leaf Cluster Light contributors.
## Input is Y-up, in mesh-local units. Each vertex has one organ/group ID.

static func normals(points: PackedVector3Array, previous: PackedVector3Array, groups: PackedInt32Array, mode: String) -> PackedVector3Array:
	var boxes: Array[AABB] = []
	var bounds = AABB(points[0], Vector3.ZERO)
	for i in points.size():
		var group = groups[i]
		if group == boxes.size(): boxes.append(AABB(points[i], Vector3.ZERO))
		else: boxes[group] = boxes[group].expand(points[i])
		bounds = bounds.expand(points[i])
	var extent = bounds.size.max(Vector3.ONE * .000001)
	var width = extent[extent.max_axis_index()] * .15
	var centers = PackedVector3Array()
	# Aggregate dense neighborhoods so very large crowns do not need an N*N matrix.
	var cells = {}
	for box in boxes:
		var center = box.get_center()
		centers.append(center)
		var cell = Vector3i((center / width).floor())
		cells[cell] = cells.get(cell, Vector4.ZERO) + Vector4(center.x, center.y, center.z, 1)
	var field = PackedVector3Array()
	for center in centers:
		var sum = Vector3.ZERO
		var mass = 0.0
		if centers.size() <= 512:
			for other in centers:
				var weight = exp(-center.distance_squared_to(other) / (2 * width * width))
				sum += weight * other
				mass += weight
		else:
			var cell = Vector3i((center / width).floor())
			for x in range(-3, 4):
				for y in range(-3, 4):
					for z in range(-3, 4):
						var bucket: Vector4 = cells.get(cell + Vector3i(x,y,z), Vector4.ZERO)
						if bucket.w == 0: continue
						var other = Vector3(bucket.x,bucket.y,bucket.z) / bucket.w
						var weight = bucket.w * exp(-center.distance_squared_to(other) / (2 * width * width))
						sum += weight * other
						mass += weight
		field.append((center - sum / mass) / width + .6 * (center - bounds.get_center()) / extent + Vector3.UP * .38)
	var result = PackedVector3Array()
	result.resize(points.size())
	for i in points.size():
		var group = groups[i]
		var normal = field[group] + .15 * (points[i] - centers[group]).normalized()
		if mode == "blade":
			# Keep both surfaces of a broad leaf distinct and retain a little camber.
			var sign_y = -1.0 if previous[i].y < 0.0 else 1.0
			normal = (normal + Vector3.UP * .38) * sign_y + .22 * previous[i]
		elif mode == "inward": normal = -normal
		result[i] = normal.normalized() if normal.length_squared() > 1e-12 else Vector3.UP
	return result

## Adapter for organ-tagged meshes. UV=(pivot.x,pivot.z), UV2=(pivot.y,phase).
## Intended for offline baking; the game's fallback generators use it once per form.
static func tagged_blades(source: ArrayMesh) -> ArrayMesh:
	if source.has_meta("leaf_cluster_light"): return source
	var output = ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays = source.surface_get_arrays(surface)
		var ids = {}
		var groups = PackedInt32Array()
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var faces: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var geometric = PackedVector3Array()
		geometric.resize(points.size())
		for k in range(0, faces.size() if not faces.is_empty() else points.size(), 3):
			var a = k if faces.is_empty() else faces[k]
			var b = k+1 if faces.is_empty() else faces[k+1]
			var c = k+2 if faces.is_empty() else faces[k+2]
			var face = (points[c]-points[a]).cross(points[b]-points[a])
			for index in [a,b,c]: geometric[index] += face
		var oriented: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL].duplicate()
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var uv: Vector2 = arrays[Mesh.ARRAY_TEX_UV][i]
			var uv2: Vector2 = arrays[Mesh.ARRAY_TEX_UV2][i]
			var key = Vector4(uv.x, uv.y, uv2.x, uv2.y)
			if not ids.has(key): ids[key] = ids.size()
			groups.append(ids[key])
			if geometric[i].dot(oriented[i]) < 0.0: oriented[i] = -oriented[i]
		arrays[Mesh.ARRAY_NORMAL] = normals(points, oriented, groups, "blade")
		output.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
		output.surface_set_material(surface, source.surface_get_material(surface))
	for key in source.get_meta_list(): output.set_meta(key, source.get_meta(key))
	output.set_meta("leaf_cluster_light", 1)
	return output
