extends StaticBody3D
## The fire: the game's only meter. It burns fuel in seconds of burn time. Crossed logs over a bed
## of embers in a ring of stones. Its light is warm, flickers and casts shadows, and the cold
## swallows it within a few meters.

signal died

const Meshes := preload("res://scripts/meshes.gd")
const Materials := preload("res://scripts/materials.gd")
const MAX_FUEL := 180.0  # a full load burns about 3 minutes

var main
var fuel := 40.0
var lit := true
var strikes_needed := 0
var smoky := 0.0

var _light: OmniLight3D
var _flames: GPUParticles3D
var _sparks: GPUParticles3D
var _smoke: GPUParticles3D
var _logs: Array = []
var _embers: ShaderMaterial
var _crackle: AudioStreamPlayer3D
var _strike: AudioStreamPlayer3D
var _heat := 1.0
var _t := 0.0


func _ready() -> void:
	var stone := Materials.get_mat("rock_fire")
	for k in range(11):
		var a := k / 11.0 * TAU + randf_range(-0.1, 0.1)
		main.world.place_rock(self, Vector3(cos(a) * 0.62, 0.04, sin(a) * 0.62), randf_range(0.22, 0.32),
			k % 8, randf() * TAU, false, stone)

	var bed := MeshInstance3D.new()
	var disc := SphereMesh.new()
	disc.radius = 0.48
	disc.height = 0.12
	disc.radial_segments = 32
	disc.rings = 8
	bed.mesh = disc
	_embers = ShaderMaterial.new()
	_embers.shader = load("res://shaders/embers.gdshader")
	bed.material_override = _embers
	add_child(bed)

	# Six logs crossed in a star, their ends pushed in as they burn. How many show follows the fuel.
	for k in range(6):
		var lm := MeshInstance3D.new()
		lm.mesh = Meshes.log_mesh(0.95, 0.055 + 0.01 * (k % 2), 300 + k, 0.02, 0.5)
		lm.material_override = Materials.get_mat("firewood")
		lm.rotation = Vector3(0.0, k * PI / 3.0 + 0.2, deg_to_rad(5.0 if k % 2 == 0 else -5.0))
		lm.position = Vector3(0.0, 0.07 + (k / 2) * 0.07, 0.0)
		add_child(lm)
		_logs.append(lm)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.25)
	_light.shadow_enabled = true
	_light.light_size = 0.12
	_light.shadow_bias = 0.06
	_light.light_volumetric_fog_energy = 1.4
	_light.position.y = 0.55
	add_child(_light)

	_flames = make_flames(48, 1.0)
	add_child(_flames)
	_sparks = _make_sparks()
	add_child(_sparks)
	_smoke = _make_smoke()
	add_child(_smoke)

	_crackle = AudioStreamPlayer3D.new()
	_crackle.stream = main.sound("fire_loop", true)
	_crackle.unit_size = 4.0
	_crackle.position.y = 0.4
	add_child(_crackle)
	_crackle.play()
	_strike = AudioStreamPlayer3D.new()
	_strike.stream = main.sound("strike")
	add_child(_strike)

	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.6
	cyl.height = 0.6
	cs.shape = cyl
	cs.position.y = 0.3
	add_child(cs)


static func _ramp(points: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(points.map(func(p): return p[0]))
	g.colors = PackedColorArray(points.map(func(p): return p[1]))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func make_flames(amount: int, size: float) -> GPUParticles3D:
	# Tongues of flame. Also used for the burning stick.
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.75
	p.position.y = 0.12 * size
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.17 * size
	m.direction = Vector3.UP
	m.spread = 12.0
	m.initial_velocity_min = 0.3 * size
	m.initial_velocity_max = 0.75 * size
	m.gravity = Vector3(0.0, 0.7, 0.0)
	m.scale_min = 0.6 * size
	m.scale_max = 1.15 * size
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.7))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 0.25))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	m.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.15, Color(1, 1, 1, 1)], [0.7, Color(1, 1, 1, 0.7)],
		[1.0, Color(1, 1, 1, 0)]])
	p.process_material = m
	p.draw_pass_1 = _quad("flame", {"mode": 0, "width": 0.46, "height": 0.7, "intensity": 0.75})
	return p


static func _quad(shader_name: String, params: Dictionary) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/%s.gdshader" % shader_name)
	for k in params:
		mat.set_shader_parameter(k, params[k])
	q.material = mat
	return q


func _make_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 2.2
	p.position.y = 0.25
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.2
	m.direction = Vector3.UP
	m.spread = 25.0
	m.initial_velocity_min = 0.8
	m.initial_velocity_max = 2.2
	m.gravity = Vector3(0.0, 0.3, 0.0)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.5
	m.turbulence_influence_min = 0.1
	m.turbulence_influence_max = 0.25
	m.color_ramp = _ramp([[0.0, Color(1, 1, 1, 1)], [0.7, Color(1, 1, 1, 0.6)], [1.0, Color(1, 1, 1, 0)]])
	p.process_material = m
	p.draw_pass_1 = _quad("flame", {"mode": 1, "width": 0.022, "height": 0.022})
	return p


func _make_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 28
	p.lifetime = 3.2
	p.position.y = 0.5
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.2
	m.direction = Vector3.UP
	m.spread = 14.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 0.9
	m.gravity = Vector3(0.0, 0.3, 0.0)
	m.scale_min = 0.6
	m.scale_max = 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 3.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	m.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.12, Color(1, 1, 1, 0.42)], [0.55, Color(1, 1, 1, 0.12)],
		[1.0, Color(1, 1, 1, 0)]])
	p.process_material = m
	p.draw_pass_1 = _quad("smoke", {"size": 0.9, "tint": Color(0.42, 0.42, 0.43)})
	return p


func strength() -> float:
	return clampf(fuel / 90.0, 0.0, 1.0) if lit else 0.0


func warm_radius() -> float:
	return 2.0 + 4.5 * strength() if lit else 0.0


func add_fuel(amount: float, kind: String) -> void:
	fuel = minf(MAX_FUEL, fuel + amount)
	if kind == "blubber":
		smoky = 40.0
	if not lit and fuel > 0.0:
		strikes_needed = 3


func _process(delta: float) -> void:
	var scaled: float = delta * main.time_scale
	_t += delta
	if lit and main.clock_running():
		fuel -= scaled
		smoky = maxf(0.0, smoky - scaled)
		if fuel <= 0.0:
			fuel = 0.0
			lit = false
			died.emit()

	var s := strength()
	_heat = move_toward(_heat, (0.25 + 0.75 * s) if lit else 0.0, delta * (0.6 if lit else 0.08))
	RenderingServer.global_shader_parameter_set("fire_heat", _heat)
	_embers.set_shader_parameter("heat", _heat)
	var flicker := 0.5 + 0.25 * sin(_t * 11.0) + 0.15 * sin(_t * 23.7) + 0.1 * sin(_t * 41.3)
	_light.visible = lit
	# From inside the tent the canvas hides the fire; its glow there comes from the tent's own light.
	_light.shadow_enabled = main.player == null or main.player.mode != "tent"
	_light.light_energy = (0.5 + 2.6 * s) * (0.8 + 0.3 * flicker)
	_light.omni_range = 2.5 + 7.0 * s
	_light.position.x = 0.03 * sin(_t * 7.3)
	_light.position.z = 0.03 * sin(_t * 5.1)
	var showing := clampi(ceili(fuel / 30.0), 1, 6) if fuel > 0.0 else 2
	for k in range(_logs.size()):
		_logs[k].visible = k < showing

	var wind: Vector2 = main.weather.wind_vector() if main.weather != null else Vector2.ZERO
	_flames.emitting = lit
	_flames.amount_ratio = 0.1 + 0.9 * s
	(_flames.process_material as ParticleProcessMaterial).gravity = Vector3(wind.x * 0.1, 0.8, wind.y * 0.1)
	_sparks.emitting = lit and s > 0.2
	(_sparks.process_material as ParticleProcessMaterial).gravity = Vector3(wind.x * 1.4, 0.3, wind.y * 1.4)
	_smoke.emitting = lit or fuel > 0.0
	_smoke.amount_ratio = 1.0 if smoky > 0.0 or (not lit and fuel > 0.0) else 0.3
	(_smoke.process_material as ParticleProcessMaterial).gravity = Vector3(wind.x * 1.2, 0.3, wind.y * 1.2)
	if lit:
		_crackle.volume_db = linear_to_db(0.08 + 0.92 * s) + 2.0
		if not _crackle.playing:
			_crackle.play()
	elif _crackle.playing:
		_crackle.stop()


func get_prompt(player) -> String:
	if player.carrying():
		return "Feed the fire" if lit else "Lay the fuel in the cold ashes"
	if not lit and fuel > 0.0:
		return "Strike the flint (%d)" % strikes_needed
	if not lit:
		return "The fire is dead. Bring fuel"
	if fuel > 25.0 and not player.has_torch:
		return "Take a burning stick"
	return ""


func interact(player) -> void:
	if player.carrying():
		for item in player.drop_all():
			add_fuel(item["value"], item["kind"])
		player.play_sfx("wood_drop")
		main.on_fed_fire()
	elif not lit and fuel > 0.0:
		_strike.pitch_scale = randf_range(0.9, 1.2)
		_strike.play()
		strikes_needed -= 1
		if strikes_needed <= 0:
			lit = true
			main.on_fire_relit()
	elif lit and fuel > 25.0 and not player.has_torch:
		fuel -= 15.0
		player.take_torch()
