extends StaticBody3D
## Eske's tent: a room of canvas over a ridge pole, big enough to sit up in and look around. The
## door faces west, toward the fire and the sea, and is kept laced shut, so from inside the world
## is only what comes through the cloth: the fire's glow, the wind, and whatever else is out
## there. The glow on the canvas is the only fire meter from inside.

const Meshes := preload("res://scripts/meshes.gd")
const Materials := preload("res://scripts/materials.gd")
const LENGTH := 3.6
const HALF_WIDTH := 1.45
const RIDGE := 2.0

var main
var occupied := false

var _candle_light: OmniLight3D
var _candle_flame: MeshInstance3D
var _glow: OmniLight3D
var _t := 0.0


func _ready() -> void:
	var canvas := MeshInstance3D.new()
	canvas.mesh = Meshes.tent_canvas(LENGTH, HALF_WIDTH, RIDGE)
	canvas.material_override = Materials.get_mat("canvas")
	add_child(canvas)
	var door := MeshInstance3D.new()
	door.mesh = Meshes.tent_door(LENGTH, HALF_WIDTH, RIDGE)
	door.material_override = Materials.get_mat("canvas")
	add_child(door)

	# The ridge pole, and at each end a pair of poles crossed above it.
	_pole(Vector3(-LENGTH * 0.5 - 0.14, RIDGE + 0.03, 0.0), Vector3(LENGTH * 0.5 + 0.14, RIDGE + 0.03, 0.0), 0.045)
	for end in [-1.0, 1.0]:
		var x: float = end * (LENGTH * 0.5 + 0.04)
		for side in [-1.0, 1.0]:
			_pole(Vector3(x, -0.08, side * (HALF_WIDTH + 0.05)), Vector3(x, RIDGE + 0.3, -side * 0.2), 0.038)
		var peg := Vector3(x + end * 1.0, 0.0, 0.0)
		_line(Vector3(x, RIDGE + 0.15, 0.0), peg)
		_peg(peg)
	# Guy lines out from the sides, and the hem pegged down all along.
	for side in [-1.0, 1.0]:
		for px in [-0.95, 0.95]:
			var on_panel := Vector3(px, 0.55, side * HALF_WIDTH * (1.0 - 0.55 / RIDGE))
			var peg := Vector3(px * 1.1, 0.0, side * (HALF_WIDTH + 1.0))
			_line(on_panel, peg)
			_peg(peg)
		for k in range(4):
			_peg(Vector3(-LENGTH * 0.5 + 0.2 + k * (LENGTH - 0.4) / 3.0, 0.0, side * (HALF_WIDTH + 0.08)))

	_build_inside()

	# Light from the fire, coming through the canvas of the door: a meter of its own.
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.5, 0.22)
	_glow.omni_range = 3.2
	_glow.position = Vector3(-LENGTH * 0.5 + 0.25, 0.8, 0.0)
	add_child(_glow)

	# No blowing snow indoors.
	var clear := FogVolume.new()
	clear.size = Vector3(LENGTH, RIDGE, HALF_WIDTH * 2.0)
	clear.position.y = RIDGE * 0.5
	var fm := FogMaterial.new()
	fm.density = -2.0
	clear.material = fm
	add_child(clear)

	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var l := LENGTH * 0.5
	shape.points = PackedVector3Array([Vector3(-l, 0, -HALF_WIDTH), Vector3(l, 0, -HALF_WIDTH),
		Vector3(l, 0, HALF_WIDTH), Vector3(-l, 0, HALF_WIDTH), Vector3(-l, RIDGE, 0), Vector3(l, RIDGE, 0)])
	cs.shape = shape
	add_child(cs)


func _build_inside() -> void:
	# A ground cloth over the snow, and hides over that.
	var cloth := MeshInstance3D.new()
	var floor_plane := PlaneMesh.new()
	floor_plane.size = Vector2(LENGTH - 0.05, HALF_WIDTH * 1.9)
	cloth.mesh = floor_plane
	cloth.material_override = Materials.get_mat("wool")
	cloth.position.y = 0.015
	add_child(cloth)
	for k in range(2):
		var rug := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(1.9, 1.5)
		plane.subdivide_width = 6
		plane.subdivide_depth = 6
		rug.mesh = plane
		rug.material_override = Materials.get_mat("hide")
		rug.position = Vector3(-0.55 + k * 1.15, 0.025 + k * 0.006, 0.12 - k * 0.3)
		rug.rotation.y = 0.12 - k * 0.2
		add_child(rug)
	# His bedroll along the north wall, a fur thrown over it.
	var roll := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.2
	cyl.bottom_radius = 0.22
	cyl.height = 1.7
	roll.mesh = cyl
	roll.material_override = Materials.get_mat("wool")
	roll.position = Vector3(0.45, 0.2, -0.82)
	roll.rotation = Vector3(0.0, 0.05, PI * 0.5)
	add_child(roll)
	var fur := MeshInstance3D.new()
	var fur_mesh := BoxMesh.new()
	fur_mesh.size = Vector3(0.95, 0.05, 0.62)
	fur.mesh = fur_mesh
	fur.position = Vector3(0.2, 0.42, -0.78)
	fur.rotation = Vector3(0.12, 0.08, 0.0)
	fur.material_override = Materials.get_mat("wool")
	add_child(fur)
	# The sea chest he dragged ashore, in the back corner.
	var chest := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.42, 0.78)
	chest.mesh = box
	chest.material_override = Materials.get_mat("tar")
	chest.position = Vector3(1.38, 0.21, 0.82)
	chest.rotation.y = -0.1
	add_child(chest)
	for bx in [-0.2, 0.2]:
		var band := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.52, 0.44, 0.04)
		band.mesh = bm
		band.material_override = Materials.get_mat("iron")
		band.position = Vector3(0.0, 0.0, bx)
		chest.add_child(band)
	# A coil of rope, and the rune stick he carves the days into.
	var coil := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.12
	torus.outer_radius = 0.2
	coil.mesh = torus
	coil.material_override = Materials.get_mat("rope")
	coil.position = Vector3(1.4, 0.05, -0.2)
	add_child(coil)
	var stick := MeshInstance3D.new()
	stick.mesh = Meshes.log_mesh(0.5, 0.016, 77, 0.01)
	stick.material_override = Materials.get_mat("pole")
	stick.position = Vector3(-0.1, 0.05, 0.32)
	stick.rotation.y = 0.5
	add_child(stick)

	# The candle, a stub of tallow on a flat stone.
	var at := Vector3(-0.35, 0.0, 0.5)
	main.world.place_rock(self, at + Vector3(0.0, 0.02, 0.0), 0.24, 5, 0.3, false, Materials.get_mat("rock_fire"))
	var candle := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022
	cm.bottom_radius = 0.026
	cm.height = 0.1
	candle.mesh = cm
	candle.material_override = Materials.get_mat("tallow")
	candle.position = at + Vector3(0.0, 0.12, 0.0)
	add_child(candle)
	_candle_flame = MeshInstance3D.new()
	var flame := SphereMesh.new()
	flame.radius = 0.009
	flame.height = 0.034
	_candle_flame.mesh = flame
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.82, 0.5)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.7, 0.35)
	glow.emission_energy_multiplier = 4.0
	_candle_flame.material_override = glow
	_candle_flame.position = at + Vector3(0.0, 0.19, 0.0)
	add_child(_candle_flame)
	_candle_light = OmniLight3D.new()
	_candle_light.light_color = Color(1.0, 0.8, 0.58)
	_candle_light.light_energy = 0.55
	_candle_light.omni_range = 3.6
	_candle_light.shadow_enabled = true
	_candle_light.light_size = 0.02
	_candle_light.position = at + Vector3(0.0, 0.26, 0.0)
	add_child(_candle_light)
	set_candle(false)


func _pole(a: Vector3, b: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.log_mesh(a.distance_to(b), radius, int(a.x * 13.0 + b.z * 7.0) & 255, 0.004)
	mi.material_override = Materials.get_mat("pole")
	mi.position = (a + b) * 0.5
	mi.basis = _along(b - a)
	add_child(mi)


func _line(a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.006
	cyl.bottom_radius = 0.006
	cyl.height = a.distance_to(b)
	cyl.radial_segments = 4
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = Materials.get_mat("rope")
	mi.position = (a + b) * 0.5
	var x_basis := _along(b - a)
	mi.basis = Basis(x_basis.y, -x_basis.x, x_basis.z)  # the cylinder runs along its own Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _peg(p: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.008
	cyl.height = 0.25
	cyl.radial_segments = 5
	mi.mesh = cyl
	mi.material_override = Materials.get_mat("pole")
	mi.position = p + Vector3(0.0, 0.06, 0.0)
	mi.rotation.z = 0.25
	add_child(mi)


static func _along(dir: Vector3) -> Basis:
	# A basis whose X axis points along `dir`.
	var x := dir.normalized()
	var up := Vector3.UP if absf(x.y) < 0.95 else Vector3.FORWARD
	var z := x.cross(up).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


func set_candle(on: bool) -> void:
	_candle_light.visible = on
	_candle_flame.visible = on


func set_occupied(inside: bool) -> void:
	occupied = inside


func _process(delta: float) -> void:
	_t += delta
	if _candle_light.visible:
		_candle_light.light_energy = 0.55 + 0.06 * sin(_t * 9.1) + 0.04 * sin(_t * 23.3)
	var fire = main.fire
	var s: float = fire.strength() if fire != null else 0.0
	_glow.visible = occupied and s > 0.0
	_glow.light_energy = (0.04 + 0.28 * s) * (0.85 + 0.15 * sin(_t * 11.0) * sin(_t * 3.7))


func inside_point() -> Vector3:
	# Where Eske sits, near the back, facing the laced door.
	return to_global(Vector3(0.95, 0.0, 0.2))


func outside_point() -> Vector3:
	return to_global(Vector3(-LENGTH * 0.5 - 1.0, 0.1, 0.5))


func get_prompt(_player) -> String:
	return "Crawl into the tent" if main.clock_running() else ""


func interact(player) -> void:
	player.enter_tent(self)
