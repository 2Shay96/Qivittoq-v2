extends RefCounted
## Procedural meshes for the camp: fractured rocks, logs and driftwood, the walrus, the lapstrake
## færing and its oars, and the tent's canvas with its folds.
## Godot treats clockwise triangles as front faces. Rather than wind every strip by hand, each
## builder records a point inside the shape for every vertex and _finish() turns each triangle
## to face away from it.


static func _finish(verts: PackedVector3Array, idx: PackedInt32Array, inside: PackedVector3Array,
		colors := PackedColorArray(), uvs := PackedVector2Array()) -> ArrayMesh:
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var n := (c - a).cross(b - a)
		var mid := (a + b + c) / 3.0
		var ref := (inside[idx[t]] + inside[idx[t + 1]] + inside[idx[t + 2]]) / 3.0
		if n.dot(mid - ref) < 0.0:
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var fn := (verts[idx[t + 2]] - a).cross(verts[idx[t + 1]] - a)
		for k in range(3):
			normals[idx[t + k]] += fn
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _grid(idx: PackedInt32Array, start: int, cols: int, rows: int) -> void:
	# Two triangles for every cell of a cols x rows block of vertices laid out row by row.
	for j in range(rows - 1):
		for i in range(cols - 1):
			var v := start + j * cols + i
			idx.append_array([v, v + 1, v + cols + 1, v, v + cols + 1, v + cols])


static func icosphere(subdiv: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := PackedVector3Array([Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0),
		Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in range(verts.size()):
		verts[i] = verts[i].normalized()
	var faces := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4,
		11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11,
		6, 2, 10, 8, 6, 7, 9, 8, 1])
	for s in range(subdiv):
		var cache := {}
		var next := PackedInt32Array()
		for f in range(0, faces.size(), 3):
			var m := []
			for e in [[faces[f], faces[f + 1]], [faces[f + 1], faces[f + 2]], [faces[f + 2], faces[f]]]:
				var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				if not cache.has(key):
					verts.append(((verts[e[0]] + verts[e[1]]) * 0.5).normalized())
					cache[key] = verts.size() - 1
				m.append(cache[key])
			next.append_array([faces[f], m[0], m[2], faces[f + 1], m[1], m[0], faces[f + 2], m[2], m[1],
				m[0], m[1], m[2]])
		faces = next
	return [verts, faces]


# --- Rocks ------------------------------------------------------------------------

static func rock(seed: int, proportions: Vector3) -> ArrayMesh:
	# A boulder: a lumpy sphere sheared off by a handful of fracture planes, so it has the flat
	# broken faces and rounded edges of frost-split rock.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ico := icosphere(3)
	var verts: PackedVector3Array = ico[0]
	var idx: PackedInt32Array = ico[1]
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 1.1
	n.fractal_octaves = 3
	var planes := []
	for k in range(rng.randi_range(8, 12)):
		var d := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 1.0), rng.randf_range(-1.0, 1.0))
		planes.append([d.normalized(), rng.randf_range(0.5, 0.8)])
	var inside := PackedVector3Array()
	inside.resize(verts.size())
	for i in range(verts.size()):
		var v := verts[i]
		var p := v * (1.0 + 0.17 * n.get_noise_3dv(v * 1.3))
		for pl in planes:
			var dir: Vector3 = pl[0]
			var over := p.dot(dir) - float(pl[1])
			if over > 0.0:
				p -= dir * over * 0.97
		p += v * 0.03 * n.get_noise_3dv(v * 6.0 + Vector3(9.0, 9.0, 9.0))
		verts[i] = p * proportions
	return _finish(verts, idx, inside)


# --- Wood --------------------------------------------------------------------------

static func log_mesh(length: float, radius: float, seed: int, bend := 0.04, char_center := -1.0,
		tint := Color(1, 1, 1)) -> ArrayMesh:
	# A log or a stick of driftwood along local X, gently bent, knotted and tapering, with cut
	# ends. COLOR.a rises toward `char_center` (0 to 1 along the log) for the fire's charring.
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 1.0
	var rings := 14
	var seg := 10
	var verts := PackedVector3Array()
	var inside := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var phase := float(seed % 97) * 0.37
	var centers := []
	var radii := []
	for r in range(rings + 1):
		var t := float(r) / rings
		var c := Vector3((t - 0.5) * length, sin(t * PI) * bend * length,
			sin(t * PI * 1.6 + phase) * bend * 0.6 * length)
		centers.append(c)
		radii.append(radius * (1.0 + 0.14 * n.get_noise_1d(t * 9.0)) * (1.0 - 0.18 * t))
		for s in range(seg + 1):
			var a := float(s) / seg * TAU
			var bump := 1.0 + 0.07 * n.get_noise_2d(t * 25.0, float(s) * 2.0)
			verts.append(c + Vector3(0.0, cos(a), sin(a)) * radii[r] * bump)
			inside.append(c)
			uvs.append(Vector2(t * length, float(s) / seg * TAU * radius))
			var ch := 0.0 if char_center < 0.0 else clampf(1.0 - absf(t - char_center) * 2.0, 0.0, 1.0)
			colors.append(Color(tint.r, tint.g, tint.b, ch))
	_grid(idx, 0, seg + 1, rings + 1)
	for end in [0, rings]:
		var c: Vector3 = centers[end]
		var axis := Vector3(-1.0 if end == 0 else 1.0, 0.0, 0.0)
		var start := verts.size()
		verts.append(c)
		inside.append(c - axis * radius)
		uvs.append(Vector2(0.0, 0.0))
		colors.append(Color(tint.r * 1.15, tint.g * 1.1, tint.b, colors[0].a if end == 0 else colors[colors.size() - 2].a))
		for s in range(seg):
			var a := float(s) / seg * TAU
			verts.append(c + Vector3(0.0, cos(a), sin(a)) * float(radii[end]))
			inside.append(c - axis * radius)
			uvs.append(Vector2(cos(a), sin(a)) * radius)
			colors.append(colors[start])
		for s in range(seg):
			idx.append_array([start, start + 1 + s, start + 1 + (s + 1) % seg])
	return _finish(verts, idx, inside, colors, uvs)


static func blubber(seed: int) -> ArrayMesh:
	# A slab of blubber cut from the walrus: pale fat, with the dark hide still on one face.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ico := icosphere(2)
	var verts: PackedVector3Array = ico[0]
	var inside := PackedVector3Array()
	inside.resize(verts.size())
	var colors := PackedColorArray()
	for i in range(verts.size()):
		var v := verts[i]
		var p := Vector3(signf(v.x) * pow(absf(v.x), 0.5), signf(v.y) * pow(absf(v.y), 0.6),
			signf(v.z) * pow(absf(v.z), 0.5))
		verts[i] = p * Vector3(0.13, 0.055, 0.09) * rng.randf_range(0.95, 1.05)
		colors.append(Color(0.2, 0.17, 0.15, 0.0) if v.y > 0.55 else Color(0.62, 0.56, 0.45, 1.0))
	return _finish(verts, ico[1], inside, colors)


# --- The walrus ---------------------------------------------------------------------

const _W_WIDTH := [[0.0, 0.1], [0.08, 0.28], [0.2, 0.5], [0.4, 0.68], [0.58, 0.74], [0.72, 0.64],
	[0.82, 0.48], [0.9, 0.37], [0.96, 0.3], [1.0, 0.08]]
const _W_HEIGHT := [[0.0, 0.07], [0.08, 0.19], [0.2, 0.36], [0.4, 0.5], [0.58, 0.55], [0.72, 0.48],
	[0.82, 0.36], [0.9, 0.29], [0.96, 0.24], [1.0, 0.06]]
const SKIN := Color(0.27, 0.23, 0.21, 0.0)
const RAW := Color(0.3, 0.05, 0.045, 1.0)
const FAT := Color(0.72, 0.66, 0.55, 0.6)


static func _profile(table: Array, u: float) -> float:
	for k in range(table.size() - 1):
		var a: Array = table[k]
		var b: Array = table[k + 1]
		if u <= b[0]:
			var f := smoothstep(0.0, 1.0, (u - a[0]) / (b[0] - a[0]))
			return lerpf(a[1], b[1], f)
	return table[-1][1]


static func walrus(seed: int) -> ArrayMesh:
	# A dead walrus lying on its belly, head toward +X. The hunters have hacked the tusks out of
	# the upper jaw and begun to flense the back, then left it.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 2.0
	var length := 3.2
	var rings := 44
	var seg := 28
	var verts := PackedVector3Array()
	var inside := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var cut_u := rng.randf_range(0.36, 0.48)
	for r in range(rings + 1):
		var u := float(r) / rings
		var w: float = _profile(_W_WIDTH, u)
		var h: float = _profile(_W_HEIGHT, u)
		var belly := h * 0.42
		var c := Vector3((u - 0.5) * length, belly + 0.01 - 0.05 * smoothstep(0.85, 1.0, u), 0.0)
		for s in range(seg + 1):
			var a := float(s) / seg * TAU
			var sn := sin(a)
			var folds := 1.0 + 0.04 * sin(u * 70.0 + sn) * smoothstep(0.6, 0.85, u) + 0.04 * n.get_noise_2d(u * 9.0, a)
			var p := c + Vector3(0.0, (sn * h if sn > 0.0 else sn * belly), cos(a) * w) * folds
			var col := SKIN
			# Where the hunters cut into the back: blubber at the edge, raw meat inside.
			var cut := (1.0 - smoothstep(0.08, 0.15, absf(u - cut_u) + n.get_noise_2d(u * 4.0, a * 2.0) * 0.04)) \
				* smoothstep(0.55, 0.85, sn)
			p.y -= 0.09 * smoothstep(0.4, 1.0, cut)
			if cut > 0.55:
				col = RAW
			elif cut > 0.2:
				col = FAT
			# Where the tusks were: two bloody sockets under the upper lip.
			if u > 0.9 and sn < -0.2:
				var tusk := 1.0 - smoothstep(0.1, 0.32, absf(absf(cos(a)) - 0.45) + (1.0 - u) * 1.5)
				if tusk > 0.3:
					col = RAW
					p -= (p - c) * 0.12 * tusk
			verts.append(p)
			inside.append(c)
			colors.append(col)
	_grid(idx, 0, seg + 1, rings + 1)
	for end in [0, rings]:
		var start := verts.size()
		var c := Vector3(((float(end) / rings) - 0.5) * length, 0.12, 0.0)
		verts.append(c + Vector3(-0.04 if end == 0 else 0.04, 0.0, 0.0))
		inside.append(c - Vector3(-0.2 if end == 0 else 0.2, 0.0, 0.0))
		colors.append(SKIN)
		var row: int = end * (seg + 1)
		for s in range(seg):
			idx.append_array([start, row + s, row + s + 1])
	# Flippers: two broad fore flippers spread on the ground, and the hind pair trailing behind.
	for spec in [[0.6, 1.0, -0.6], [0.6, -1.0, 0.6], [0.0, 1.0, 2.6], [0.0, -1.0, -2.6]]:
		_flipper(verts, inside, colors, idx, (spec[0] - 0.5) * length, spec[1], spec[2],
			_profile(_W_WIDTH, spec[0]))
	return _finish(verts, idx, inside, colors)


static func _flipper(verts: PackedVector3Array, inside: PackedVector3Array, colors: PackedColorArray,
		idx: PackedInt32Array, x: float, side: float, yaw: float, half_width: float) -> void:
	var ico := icosphere(2)
	var base := verts.size()
	var root := Vector3(x, 0.08, side * half_width * 0.85)
	var basis := Basis(Vector3.UP, yaw)
	for v in ico[0]:
		var p := Vector3(v.x * 0.34 + 0.24, v.y * 0.045, v.z * 0.17 * (0.6 + 0.4 * (v.x * 0.5 + 0.5)))
		verts.append(root + basis * p)
		inside.append(root + basis * Vector3(0.24, 0.0, 0.0))
		colors.append(SKIN)
	for i in ico[1]:
		idx.append(base + i)


# --- The færing -------------------------------------------------------------------

static func faering() -> ArrayMesh:
	# A small double-ended Norse boat, clinker built: five strakes a side, each overlapping the
	# one below it, rising to a stem at each end. Length along X.
	var length := 5.4
	var beam := 1.5
	var depth := 0.62
	var strakes := 5
	var lap := 0.02
	var stations := 40
	var verts := PackedVector3Array()
	var inside := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for side in [-1.0, 1.0]:
		for k in range(strakes):
			var tone := 0.85 + 0.3 * fposmod(float(k) * 0.37 + side * 0.11, 1.0)
			var start := verts.size()
			var rows := [0.0, 0.5, 1.0]
			for fr in rows:
				var s: float = (float(k) + fr) / strakes
				for st in range(stations + 1):
					var t := lerpf(-1.0, 1.0, float(st) / stations)
					var p := _hull_point(t, s, side, length, beam, depth)
					var nrm := _hull_normal(t, s, side, length, beam, depth)
					p += nrm * lap * (1.0 - fr)
					verts.append(p)
					inside.append(Vector3(p.x, depth * 1.4, 0.0))
					colors.append(Color(tone, tone * 0.97, tone * 0.94, 0.0))
					uvs.append(Vector2(p.x, s * 2.0 + float(k) * 0.37))
			_grid(idx, start, stations + 1, rows.size())
			if k > 0:
				# The edge of the plank where it laps over the one below.
				var e0 := verts.size()
				for fr in [0.0, 1.0]:
					var s := float(k) / strakes
					for st in range(stations + 1):
						var t := lerpf(-1.0, 1.0, float(st) / stations)
						var p: Vector3 = _hull_point(t, s, side, length, beam, depth) \
							+ _hull_normal(t, s, side, length, beam, depth) * lap * (1.0 - fr)
						verts.append(p)
						inside.append(Vector3(p.x, depth * 3.0, 0.0))
						colors.append(Color(tone * 0.7, tone * 0.68, tone * 0.66, 0.0))
						uvs.append(Vector2(p.x, s))
				_grid(idx, e0, stations + 1, 2)
	# Stems: a curved post at each end rising above the sheer.
	for end in [-1.0, 1.0]:
		var start := verts.size()
		for k in range(10):
			var f := float(k) / 9.0
			var x: float = end * (length * 0.5 + 0.04 + 0.1 * f * f)
			var y := lerpf(0.0, depth * 1.4, f)
			for w in [-0.035, 0.035]:
				for o in [0.0, 0.07]:
					verts.append(Vector3(x + end * o, y, w))
					inside.append(Vector3(x + end * 0.035, y, 0.0))
					colors.append(Color(0.8, 0.78, 0.75, 0.0))
					uvs.append(Vector2(y, o))
		for k in range(9):
			var a := start + k * 4
			idx.append_array([a, a + 4, a + 5, a, a + 5, a + 1])
			idx.append_array([a + 2, a + 6, a + 7, a + 2, a + 7, a + 3])
			idx.append_array([a + 1, a + 5, a + 7, a + 1, a + 7, a + 3])
			idx.append_array([a, a + 4, a + 6, a, a + 6, a + 2])
	# Thwarts: two seats across the boat.
	for tx in [-0.28, 0.3]:
		var y := _hull_point(tx, 0.82, 1.0, length, beam, depth).y
		var w := _hull_point(tx, 0.82, 1.0, length, beam, depth).z
		_box(verts, inside, colors, uvs, idx, Vector3(tx * length * 0.5, y, 0.0), Vector3(0.13, 0.03, w), Color(0.95, 0.93, 0.9))
	return _finish(verts, idx, inside, colors, uvs)


static func _hull_point(t: float, s: float, side: float, length: float, beam: float, depth: float) -> Vector3:
	var w := beam * 0.5 * pow(maxf(0.0, 1.0 - t * t), 0.62)
	var top := depth * (1.0 + 0.55 * pow(t, 4.0))
	var a := s * PI * 0.5
	return Vector3(t * length * 0.5, top * (1.0 - cos(a)) * 0.98 + 0.02 * s, side * w * sin(a))


static func _hull_normal(t: float, s: float, side: float, length: float, beam: float, depth: float) -> Vector3:
	var e := 0.01
	var p0 := _hull_point(t, s - e, side, length, beam, depth)
	var p1 := _hull_point(t, s + e, side, length, beam, depth)
	var tan := p1 - p0
	var nrm := Vector3(0.0, -tan.z * side, tan.y * side)
	if nrm.length() < 0.0001:
		return Vector3(0.0, -1.0, 0.0)
	return nrm.normalized()


static func _box(verts: PackedVector3Array, inside: PackedVector3Array, colors: PackedColorArray,
		uvs: PackedVector2Array, idx: PackedInt32Array, c: Vector3, half: Vector3, col: Color,
		basis := Basis()) -> void:
	var start := verts.size()
	for k in range(8):
		var corner := Vector3(half.x * (1 if k & 1 else -1), half.y * (1 if k & 2 else -1), half.z * (1 if k & 4 else -1))
		verts.append(c + basis * corner)
		inside.append(c)
		colors.append(col)
		uvs.append(Vector2(corner.x + corner.z, corner.y))
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		idx.append_array([start + f[0], start + f[1], start + f[2], start + f[0], start + f[2], start + f[3]])


static func oar(seed: int) -> ArrayMesh:
	# A long oar: a round loom and a narrow blade, along local X.
	var verts := PackedVector3Array()
	var inside := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var seg := 8
	var shaft := 2.6
	for r in range(2):
		var x := -shaft * 0.5 + r * shaft
		for s in range(seg + 1):
			var a := float(s) / seg * TAU
			verts.append(Vector3(x, cos(a) * 0.025, sin(a) * 0.025))
			inside.append(Vector3(x, 0.0, 0.0))
			colors.append(Color(1.0, 0.98, 0.95, 0.0))
			uvs.append(Vector2(x, float(s) / seg * 0.16))
	_grid(idx, 0, seg + 1, 2)
	_box(verts, inside, colors, uvs, idx, Vector3(shaft * 0.5 + 0.38, 0.0, 0.0), Vector3(0.42, 0.012, 0.075),
		Color(0.95, 0.93, 0.9))
	return _finish(verts, idx, inside, colors, uvs)


# --- The tent ------------------------------------------------------------------------

static func tent_canvas(length: float, half_width: float, ridge: float) -> ArrayMesh:
	# Woven canvas over a ridge pole: two roof panels sagging between the pole and the pegged
	# hem, and a closed back (east) end. The door at the west end is tent_door(). UVs in meters.
	# COLOR.a: how free the cloth is to move in the wind.
	var verts := PackedVector3Array()
	var inside := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var cols := 30
	var rows := 14
	var centre := Vector3(0.0, ridge * 0.35, 0.0)
	var slant := sqrt(half_width * half_width + ridge * ridge)
	for side in [-1.0, 1.0]:
		var start := verts.size()
		var out := Vector3(0.0, half_width, side * ridge).normalized()
		for j in range(rows + 1):
			var v := float(j) / rows
			for i in range(cols + 1):
				var u := float(i) / cols
				var x := (u - 0.5) * length
				var p := Vector3(x, ridge * (1.0 - v), side * half_width * v)
				# Sag between ridge and hem, more in the middle of the panel than at the ends.
				var sag := sin(PI * v) * (0.04 + 0.035 * sin(PI * u))
				# Folds fanning out from the pole ends and pulled into the pegs along the hem.
				var near_end := exp(-pow((absf(x) - length * 0.5) / 0.35, 2.0))
				var folds := sin(u * 34.0 + v * 9.0 * side) * 0.011 * (1.0 - v) * near_end
				var hem := 0.035 * absf(sin(PI * x / (length / 3.0))) * smoothstep(0.75, 1.0, v)
				p += -out * (sag + folds)
				p.y += hem
				verts.append(p)
				inside.append(centre)
				var free := sin(PI * v) * (0.4 + 0.6 * sin(PI * u))
				colors.append(Color(1, 1, 1, free))
				uvs.append(Vector2(x, v * slant))
		_grid(idx, start, cols + 1, rows + 1)
	# The back end: a triangle of canvas, sagging in a little.
	var start := verts.size()
	var tri_rows := 10
	for j in range(tri_rows + 1):
		var f := float(j) / tri_rows
		var y := ridge * (1.0 - f)
		for i in range(j + 1):
			var g := 0.0 if j == 0 else float(i) / j
			var z := (g * 2.0 - 1.0) * half_width * f
			var sag := 0.05 * f * (1.0 - f) * sin(PI * g)
			verts.append(Vector3(length * 0.5 - sag, y, z))
			inside.append(centre)
			colors.append(Color(1, 1, 1, f * (1.0 - f) * 2.0 * sin(PI * g)))
			uvs.append(Vector2(z, y))
	var row_start := start
	for j in range(tri_rows):
		var next_start := row_start + j + 1
		for i in range(j + 1):
			idx.append_array([row_start + i, next_start + i, next_start + i + 1])
			if i < j:
				idx.append_array([row_start + i, next_start + i + 1, row_start + i + 1])
		row_start = next_start
	return _finish(verts, idx, inside, colors, uvs)


static func tent_door(length: float, half_width: float, ridge: float) -> ArrayMesh:
	# The two door flaps at the west end. They meet and overlap down the middle, laced shut, so
	# the tent is a room of its own.
	var verts := PackedVector3Array()
	var inside := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var x0 := -length * 0.5
	for side in [-1.0, 1.0]:
		var fs := verts.size()
		var rows := 12
		var cols := 8
		for j in range(rows + 1):
			var f := float(j) / rows
			var y := ridge * (1.0 - f)
			var reach := half_width * f
			for i in range(cols + 1):
				var g := float(i) / cols
				# From the hem corner across to just past the middle, where it overlaps the other.
				var z: float = side * lerpf(reach, -0.05 * f, g)
				var bulge := 0.04 * sin(PI * g) * sin(PI * f)
				verts.append(Vector3(x0 - bulge - (0.012 if side > 0.0 else 0.0), y, z))
				inside.append(Vector3(x0 + length * 0.5, ridge * 0.35, 0.0))
				colors.append(Color(0.95, 0.95, 0.95, sin(PI * f) * g))
				uvs.append(Vector2(g * half_width, y))
		_grid(idx, fs, cols + 1, rows + 1)
	return _finish(verts, idx, inside, colors, uvs)
