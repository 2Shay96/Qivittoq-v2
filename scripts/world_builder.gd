extends RefCounted
## Builds the bay at Norðrseta: the land out past the horizon, the sea, the rocks, the snow the
## wind has banked against them, the cairn, the færing and, kilometers off, the mountains and the
## edge of the ice cap. North is -Z, east is +X, and the sea lies to the west. The wind comes down
## off the ice cap in the east and streams out to sea.

const FuelItem := preload("res://scripts/fuel_item.gd")
const Carcass := preload("res://scripts/carcass.gd")
const Meshes := preload("res://scripts/meshes.gd")
const Materials := preload("res://scripts/materials.gd")

const HOLLOW := Vector2(36.0, -26.0)
const CAIRN_Z := -70.0
const TENT := Vector2(2.6, 0.0)
const WIND := Vector2(-0.989, 0.149)  # the way the snow blows
# The terrain grid: 1 m squares near the camp, wider and wider out to the horizon.
const FINE_X := Vector2(-75.0, 50.0)
const FINE_Z := Vector2(-80.0, 45.0)
const EXTENT_X := Vector2(-450.0, 6500.0)
const EXTENT_Z := Vector2(-6500.0, 6500.0)
const CHUNK := 48
# Collision: a 2 m heightmap a kilometer across, which is further than the cold lets anyone walk.
const COLLIDE_SIZE := 513
const COLLIDE_STEP := 2.0
const COLLIDE_CENTER := Vector2(290.0, 0.0)
const ROCK_SHAPES := [Vector3(1.25, 0.72, 1.0), Vector3(1.0, 0.9, 0.85), Vector3(1.45, 0.6, 1.1),
	Vector3(0.9, 1.1, 0.9), Vector3(1.2, 0.8, 1.3), Vector3(1.0, 0.62, 0.95), Vector3(1.5, 0.85, 1.0),
	Vector3(1.1, 1.0, 1.2)]

var noise := FastNoiseLite.new()
var hills := FastNoiseLite.new()
var drifts := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var rocks: Array = []
var faering_pos := Vector3.ZERO
var carcasses: Array = []
var _banks := {}
var _camp_h := 0.0
var _rock_meshes: Array = []
var _rock_points: Array = []


func _init() -> void:
	noise.seed = 1424
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	hills.seed = 77
	hills.frequency = 0.0022
	hills.fractal_octaves = 4
	drifts.seed = 9
	drifts.frequency = 0.08
	drifts.fractal_octaves = 2
	rng.seed = 1424
	_camp_h = _raw_height(0.0, 0.0)
	_plan_rocks()


func shore_x(z: float) -> float:
	# The coastline wanders a little, and a headland pushes west in the north.
	# shaders/common.gdshaderinc has the same curve.
	return -30.0 + 5.0 * sin(z * 0.021) + 3.0 * sin(z * 0.053 + 1.3) \
		- 16.0 * exp(-pow((z - CAIRN_Z) / 22.0, 2.0))


func _raw_height(x: float, z: float) -> float:
	var d := x - shore_x(z)
	var h: float
	if d < 0.0:
		h = maxf(d * 0.15, -40.0)
	else:
		h = 0.7 * (1.0 - exp(-d * 0.08)) + clampf(d - 22.0, 0.0, 400.0) * 0.07 \
			+ 160.0 * (1.0 - exp(-maxf(0.0, d - 70.0) / 700.0))
	h += noise.get_noise_2d(x, z) * (0.35 + clampf(d * 0.012, 0.0, 2.0))
	if d > 100.0:
		h += hills.get_noise_2d(x, z) * 70.0 * clampf((d - 100.0) / 500.0, 0.0, 1.0)
	# The hollow where Eske hid: a dip in the slope above the bay.
	h -= 1.3 * exp(-(pow(x - HOLLOW.x, 2.0) + pow(z - HOLLOW.y, 2.0)) / 30.0)
	# Drifts the wind has sculpted: long low ridges lying along it.
	if d > 5.0 and x * x + z * z < 640000.0:
		var s := drifts.get_noise_2d(x * 0.3, z * 1.4)
		h += (0.45 - absf(s)) * 0.32 * smoothstep(5.0, 15.0, d)
	return h


func height_at(x: float, z: float) -> float:
	var h := _raw_height(x, z)
	var r := sqrt(x * x + z * z)
	if r < 11.0:  # the camp, trodden flat
		h = lerpf(h, _camp_h, 1.0 - smoothstep(5.0, 11.0, r))
	return h + _bank(x, z)


func ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


func hollow_point() -> Vector3:
	return ground(HOLLOW.x, HOLLOW.y)


# --- Snow banked by the wind ------------------------------------------------------

func _add_bank(cx: float, cz: float, height: float, rx: float, rz: float) -> void:
	var b := [cx, cz, height, 1.0 / (rx * rx), 1.0 / (rz * rz)]
	var reach := 2.6 * maxf(rx, rz)
	for i in range(floori((cx - reach) / 16.0), floori((cx + reach) / 16.0) + 1):
		for j in range(floori((cz - reach) / 16.0), floori((cz + reach) / 16.0) + 1):
			var key := Vector2i(i, j)
			if not _banks.has(key):
				_banks[key] = []
			_banks[key].append(b)


func _bank(x: float, z: float) -> float:
	var key := Vector2i(floori(x / 16.0), floori(z / 16.0))
	if not _banks.has(key):
		return 0.0
	# Nothing drifts inside the tent.
	if absf(x - TENT.x) < 1.85 and absf(z - TENT.y) < 1.5:
		return 0.0
	var h := 0.0
	for b in _banks[key]:
		var dx: float = x - b[0]
		var dz: float = z - b[1]
		h += b[2] * exp(-(dx * dx * b[3] + dz * dz * b[4]))
	return h


func _plan_rocks() -> void:
	# Boulders along the shore, a ring of them around the hollow, big outcrops inland.
	for k in range(90):
		var z := rng.randf_range(-220.0, 220.0)
		var x := shore_x(z) + rng.randf_range(-3.0, 45.0)
		if Vector2(x, z).length() < 12.0:
			continue
		var size := rng.randf_range(0.35, 2.3)
		rocks.append({"pos": Vector2(x, z), "size": size, "sink": 0.3, "variant": k % 8,
			"yaw": rng.randf() * TAU, "shore": x - shore_x(z) < 6.0})
	for k in range(16):
		var a := k / 16.0 * TAU
		if cos(a) < -0.5:
			continue  # leave the west side open, looking out over the bay
		var r := rng.randf_range(4.0, 6.0)
		rocks.append({"pos": HOLLOW + Vector2(cos(a), sin(a)) * r, "size": rng.randf_range(1.2, 2.6),
			"sink": 0.3, "variant": k % 8, "yaw": rng.randf() * TAU, "shore": false})
	for k in range(10):
		var z := CAIRN_Z + rng.randf_range(-22.0, 22.0)
		rocks.append({"pos": Vector2(shore_x(z) + rng.randf_range(-1.0, 8.0), z), "size": rng.randf_range(1.0, 2.8),
			"sink": 0.35, "variant": k % 8, "yaw": rng.randf() * TAU, "shore": true})
	for k in range(45):
		var x := rng.randf_range(60.0, 420.0)
		var z := rng.randf_range(-400.0, 400.0)
		rocks.append({"pos": Vector2(x, z), "size": rng.randf_range(3.0, 8.0), "sink": 0.45,
			"variant": k % 8, "yaw": rng.randf() * TAU, "shore": false})
	for r in rocks:
		var p: Vector2 = r["pos"]
		var s: float = r["size"]
		if s < 0.8 or p.length() > 320.0:
			continue
		var up := -WIND
		_add_bank(p.x + up.x * s * 0.6, p.y + up.y * s * 0.6, 0.3 * s, 0.5 * s, 0.9 * s)
		_add_bank(p.x + WIND.x * s * 1.7, p.y + WIND.y * s * 1.7, 0.18 * s, 1.8 * s, 0.55 * s)
	# Snow piled against the windward (east) end of the tent and along its sides.
	_add_bank(TENT.x + 2.15, TENT.y, 0.6, 0.45, 1.6)
	_add_bank(TENT.x + 0.4, TENT.y - 1.68, 0.14, 1.6, 0.25)
	_add_bank(TENT.x + 0.4, TENT.y + 1.68, 0.14, 1.6, 0.25)


# --- Terrain -------------------------------------------------------------------------

func _spacing(e: float) -> float:
	if e < 100.0:
		return 1.0 + e / 33.0
	return minf(4.0 + (e - 100.0) * 0.12, 320.0)


func _axis(lo: float, hi: float, fine_lo: float, fine_hi: float, fine_step := 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var p := fine_lo
	while p - lo > 0.5:
		p = maxf(lo, p - _spacing(fine_lo - p) * fine_step)
		out.append(p)
	out.reverse()
	p = fine_lo
	while p < fine_hi - 0.001:
		out.append(p)
		p += fine_step
	out.append(fine_hi)
	p = fine_hi
	while hi - p > 0.5:
		p = minf(hi, p + _spacing(p - fine_hi) * fine_step)
		out.append(p)
	return out


func build_terrain() -> StaticBody3D:
	var xs := _axis(EXTENT_X.x, EXTENT_X.y, FINE_X.x, FINE_X.y)
	var zs := _axis(EXTENT_Z.x, EXTENT_Z.y, FINE_Z.x, FINE_Z.y)
	var nx := xs.size()
	var nz := zs.size()
	var h := PackedFloat32Array()
	h.resize(nx * nz)
	for j in range(nz):
		for i in range(nx):
			h[j * nx + i] = height_at(xs[i], zs[j])

	var body := StaticBody3D.new()
	body.name = "Terrain"
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	for cj in range(0, nz - 1, CHUNK):
		for ci in range(0, nx - 1, CHUNK):
			var i1 := mini(ci + CHUNK, nx - 1)
			var j1 := mini(cj + CHUNK, nz - 1)
			var cols := i1 - ci + 1
			var verts := PackedVector3Array()
			var normals := PackedVector3Array()
			for j in range(cj, j1 + 1):
				for i in range(ci, i1 + 1):
					verts.append(Vector3(xs[i], h[j * nx + i], zs[j]))
					var il := maxi(i - 1, 0)
					var ir := mini(i + 1, nx - 1)
					var jl := maxi(j - 1, 0)
					var jr := mini(j + 1, nz - 1)
					var dx := (h[j * nx + ir] - h[j * nx + il]) / (xs[ir] - xs[il])
					var dz := (h[jr * nx + i] - h[jl * nx + i]) / (zs[jr] - zs[jl])
					normals.append(Vector3(-dx, 1.0, -dz).normalized())
			var idx := PackedInt32Array()
			Meshes._grid(idx, 0, cols, j1 - cj + 1)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			var near := Vector2(clampf(0.0, xs[ci], xs[i1]), clampf(0.0, zs[cj], zs[j1])).length()
			if near > 220.0:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(mi)

	var map := PackedFloat32Array()
	map.resize(COLLIDE_SIZE * COLLIDE_SIZE)
	var half := (COLLIDE_SIZE - 1) * 0.5
	for j in range(COLLIDE_SIZE):
		var z := COLLIDE_CENTER.y + (j - half) * COLLIDE_STEP
		for i in range(COLLIDE_SIZE):
			var x := COLLIDE_CENTER.x + (i - half) * COLLIDE_STEP
			map[j * COLLIDE_SIZE + i] = height_at(x, z) / COLLIDE_STEP
	var shape := HeightMapShape3D.new()
	shape.map_width = COLLIDE_SIZE
	shape.map_depth = COLLIDE_SIZE
	shape.map_data = map
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(COLLIDE_CENTER.x, 0.0, COLLIDE_CENTER.y)
	cs.scale = Vector3.ONE * COLLIDE_STEP
	body.add_child(cs)
	return body


func build_sea() -> MeshInstance3D:
	# Water out to the horizon, finer near the shore where the swell can be seen.
	var xs := _axis(-9000.0, 40.0, -160.0, -10.0, 4.0)
	var zs := _axis(-9000.0, 9000.0, -260.0, 260.0, 4.0)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for z in zs:
		for x in xs:
			verts.append(Vector3(x, 0.0, z))
			normals.append(Vector3.UP)
	var idx := PackedInt32Array()
	Meshes._grid(idx, 0, xs.size(), zs.size())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-9000.0, -2.0, -9000.0), Vector3(9040.0, 4.0, 18000.0))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sea.gdshader")
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = -0.12
	return mi


# --- The mountains ----------------------------------------------------------------------

func build_mountains() -> Node3D:
	# Three ridgelines, each further, taller and fainter, and the edge of the ice cap beyond.
	# They wrap around the landward side, from north-north-west through east to south-south-west.
	var root := Node3D.new()
	root.name = "Mountains"
	root.add_child(_ridgeline(2200.0, 600.0, 1350.0, -112.0, 108.0, 11, 0.6, 0.66, Color(0.13, 0.14, 0.17)))
	root.add_child(_ridgeline(3500.0, 750.0, 1450.0, -124.0, 118.0, 23, 0.4, 0.62, Color(0.18, 0.19, 0.22)))
	root.add_child(_ridgeline(5000.0, 900.0, 1500.0, -136.0, 130.0, 37, 0.24, 0.58, Color(0.24, 0.25, 0.28)))
	root.add_child(_ridgeline(7300.0, 1050.0, 1200.0, -150.0, 146.0, 51, 0.14, 0.0, Color(0.7, 0.74, 0.8), true))
	return root


func _ridgeline(radius: float, low: float, high: float, from_deg: float, to_deg: float, seed: int,
		contrast: float, snow_line: float, rock: Color, ice_cap := false) -> MeshInstance3D:
	var peaks := FastNoiseLite.new()
	peaks.seed = seed
	peaks.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	peaks.fractal_octaves = 5
	peaks.frequency = 1.0 / (2600.0 if ice_cap else 1100.0)
	var gullies := FastNoiseLite.new()
	gullies.seed = seed + 1
	gullies.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	gullies.fractal_octaves = 3
	gullies.frequency = 1.0 / 240.0
	var massifs := FastNoiseLite.new()
	massifs.seed = seed + 2
	massifs.frequency = 1.0 / 2600.0
	var cols := int((to_deg - from_deg) / 0.3)
	var rows := 18
	var verts := PackedVector3Array()
	var inside := PackedVector3Array()
	var idx := PackedInt32Array()
	for c in range(cols + 1):
		var f := float(c) / cols
		var th := deg_to_rad(lerpf(from_deg, to_deg, f))
		var dir := Vector3(cos(th), 0.0, sin(th))
		var arc := th * radius
		var n := clampf(peaks.get_noise_1d(arc) * 0.5 + 0.5, 0.0, 1.0)
		var m := smoothstep(-0.4, 0.5, massifs.get_noise_1d(arc))
		# Broad massifs with saddles between them, and a jagged crest along the top.
		var peak := lerpf(low * 0.35, high, m) * (0.72 + 0.28 * n)
		if ice_cap:
			peak = lerpf(low, high, n)
		peak *= smoothstep(0.0, 0.06, f) * smoothstep(1.0, 0.94, f) * 0.85 + 0.15
		var run := peak * (2.6 if ice_cap else 1.7)
		for r in range(rows + 1):
			var g := float(r) / rows
			var rad := radius - run * (1.0 - g)
			var shape := smoothstep(0.0, 1.0, g) if ice_cap else pow(g, 1.45)
			var y := -80.0 + (peak + 80.0) * shape
			if not ice_cap:
				y -= gullies.get_noise_2d(arc, rad) * peak * 0.05 * sin(PI * g)
			verts.append(dir * rad + Vector3.UP * y)
			inside.append(dir * radius * 3.0 + Vector3.UP * y)
		# Behind the crest the ground falls away again, so the skyline is the crest.
		var back := dir * (radius + run * 0.35) + Vector3.UP * (peak * 0.55)
		verts.append(back)
		inside.append(dir * radius * 3.0 + Vector3.UP * back.y)
	Meshes._grid(idx, 0, rows + 2, cols + 1)
	var mesh := Meshes._finish(verts, idx, inside)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mountain.gdshader")
	mat.set_shader_parameter("contrast", contrast)
	mat.set_shader_parameter("snow_line", snow_line)
	mat.set_shader_parameter("rock", rock)
	mat.set_shader_parameter("base_height", 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- Rocks, the cairn and the boat --------------------------------------------------------

func _rock_mesh(variant: int) -> ArrayMesh:
	if _rock_meshes.is_empty():
		for k in range(ROCK_SHAPES.size()):
			var m := Meshes.rock(100 + k, ROCK_SHAPES[k])
			_rock_meshes.append(m)
			var hull: ConvexPolygonShape3D = m.create_convex_shape(true, true)
			_rock_points.append(hull.points)
	return _rock_meshes[variant]


func place_rock(parent: Node, pos: Vector3, size: float, variant: int, yaw: float, solid: bool,
		mat: Material, tilt := Vector3.ZERO) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _rock_mesh(variant)
	mi.material_override = mat
	mi.scale = Vector3.ONE * size * 0.5
	var holder: Node3D
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		var pts := PackedVector3Array()
		for p in _rock_points[variant]:
			pts.append(p * size * 0.5)
		shape.points = pts
		cs.shape = shape
		body.add_child(cs)
		holder = body
	else:
		holder = Node3D.new()
	holder.position = pos
	holder.rotation = Vector3(tilt.x, yaw, tilt.z)
	holder.add_child(mi)
	parent.add_child(holder)
	return holder


func build_props(parent: Node3D) -> void:
	var rock_mat := Materials.get_mat("rock")
	var shore_mat := Materials.get_mat("rock_shore")
	for r in rocks:
		var p: Vector2 = r["pos"]
		var size: float = r["size"]
		var shape: Vector3 = ROCK_SHAPES[r["variant"]]
		var y := height_at(p.x, p.y) + size * 0.5 * shape.y * (1.0 - 2.0 * float(r["sink"]))
		var tilt := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
		place_rock(parent, Vector3(p.x, y, p.y), size, r["variant"], r["yaw"], size > 0.8,
			shore_mat if r["shore"] else rock_mat, tilt)
	_build_cairn(parent)
	_build_faering(parent)
	parent.add_child(build_mountains())


func _build_cairn(parent: Node3D) -> void:
	# Stones stacked by someone, long ago, on the headland.
	var base := ground(shore_x(CAIRN_Z) + 9.0, CAIRN_Z)
	var y := 0.0
	for k in range(7):
		var w := 0.95 - k * 0.11
		var stone := place_rock(parent, base + Vector3(rng.randf_range(-0.05, 0.05), y + w * 0.16, rng.randf_range(-0.05, 0.05)),
			w, k % 8, rng.randf() * TAU, false, Materials.get_mat("rock"))
		stone.scale = Vector3(1.0, 0.55, 1.0)
		y += w * 0.3
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, y, 0.9)
	cs.shape = box
	body.position = base + Vector3(0.0, y * 0.5, 0.0)
	body.add_child(cs)
	parent.add_child(body)


func _build_faering(parent: Node3D) -> void:
	# A small double-ended boat, hauled up the beach just north-west of camp, oars across it.
	var body := StaticBody3D.new()
	body.name = "Faering"
	var z := -9.0
	body.position = ground(shore_x(z) + 6.0, z) + Vector3(0, 0.02, 0)
	body.rotation = Vector3(0.0, deg_to_rad(-25.0), deg_to_rad(7.0))
	faering_pos = body.position
	var hull := MeshInstance3D.new()
	hull.mesh = Meshes.faering()
	hull.material_override = Materials.get_mat("tar")
	body.add_child(hull)
	for k in range(2):
		var oar := MeshInstance3D.new()
		oar.mesh = Meshes.oar(k)
		oar.material_override = Materials.get_mat("oar")
		oar.position = Vector3(0.15 + k * 0.25, 0.58, -0.1 + k * 0.22)
		oar.rotation = Vector3(0.0, 0.08 - k * 0.15, 0.02)
		body.add_child(oar)
	# Snow lying in the bottom of the boat.
	var drift := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 1.0
	dm.height = 2.0
	drift.mesh = dm
	drift.scale = Vector3(2.1, 0.12, 0.42)
	drift.position = Vector3(0.0, 0.14, 0.0)
	var snow_mat := StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.82, 0.85, 0.9)
	snow_mat.roughness = 0.85
	drift.material_override = snow_mat
	body.add_child(drift)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.4, 0.62, 1.5)
	cs.shape = box
	cs.position.y = 0.31
	body.add_child(cs)
	parent.add_child(body)


# --- Fuel -------------------------------------------------------------------------

func spawn_fuel(parent: Node3D) -> void:
	# Driftwood along the tideline. Day 1 has plenty close by.
	for k in range(38):
		var z := rng.randf_range(-130.0, 130.0)
		if k < 14:
			z = rng.randf_range(-35.0, 35.0)
		var x := shore_x(z) + rng.randf_range(0.8, 6.5)
		var item := FuelItem.new()
		item.kind = "driftwood"
		item.value = 45.0
		item.seed = k
		item.position = ground(x, z) + Vector3(0, 0.07, 0)
		item.rotation.y = rng.randf() * TAU
		parent.add_child(item)

	# Butchered walrus on the beach south of camp. Their blubber burns long.
	for z in [14.0, 23.0, 34.0]:
		var c: StaticBody3D = Carcass.new()
		c.seed = int(z)
		var x: float = shore_x(z) + rng.randf_range(3.0, 6.0)
		c.position = ground(x, z)
		c.rotation.y = rng.randf() * TAU
		parent.add_child(c)
		carcasses.append(c)
