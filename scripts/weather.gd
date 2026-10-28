extends Node3D
## The weather, all driven by one wind value. The wind blows the snow (fine streaks, a few big
## flakes close to the eyes, spindrift streaming along the ground), thickens the blizzard volume
## that travels with Eske, and sets how loud the wind is. Gusts come and go and white out the
## world. Twice on day 1 the wind drops away into a lull and, for a little while, the mountains
## are there.

const WIND := Vector2(-0.989, 0.149)  # the way the snow blows: off the ice cap, out to sea
const DAY_LULL := Vector2(100.0, 140.0)  # phase seconds
const DUSK_LULL := Vector2(5.0, 30.0)
const AMOUNTS := [[1400, 70, 50], [2600, 120, 80], [4000, 170, 110]]  # streaks, flakes, drift per quality

var main
var wind := 0.5   # 0 still air, 1 a full blizzard
var gust := 0.0   # 0 to 1: how white the near world is
var lull := 0.0   # 0 to 1
var reveal := 0.0 # how far the mountains show
var forced := ""  # "lull", "gust", "calm" or "storm", from --weather=
var whiteouts := 0

var _noise := FastNoiseLite.new()
var _t := 0.0
var _gust_t := -1.0
var _gust_len := 0.0
var _gust_peak := 0.0
var _next_gust := 22.0
var _offset := Vector2.ZERO
var _indoors := false
var _white := false
var _in_lull := false
var _streaks: GPUParticles3D
var _flakes: GPUParticles3D
var _drift: GPUParticles3D
var _fog: FogVolume
var _fog_mat: ShaderMaterial
var _wind_audio: AudioStreamPlayer
var _wind_low: AudioStreamPlayer
var _wind_gust: AudioStreamPlayer
var _wind_filter: AudioEffectLowPassFilter


func _ready() -> void:
	_noise.seed = 3
	_noise.frequency = 0.08
	_streaks = _layer(0, 1.7, 0.0085, 0.5, Vector3(16.0, 5.0, 16.0))
	_flakes = _layer(1, 3.0, 0.011, 0.85, Vector3(4.0, 2.5, 4.0))
	_drift = _layer(2, 2.6, 1.7, 0.32, Vector3(14.0, 0.1, 14.0))
	set_quality(1)

	_fog = FogVolume.new()
	_fog.size = Vector3(90.0, 36.0, 90.0)
	_fog.position.y = 10.0
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = load("res://shaders/blizzard.gdshader")
	var puffs := NoiseTexture3D.new()
	puffs.width = 64
	puffs.height = 64
	puffs.depth = 64
	puffs.seamless = true
	var n := FastNoiseLite.new()
	n.seed = 11
	n.frequency = 0.05
	n.fractal_octaves = 3
	puffs.noise = n
	_fog_mat.set_shader_parameter("puffs", puffs)
	_fog.material = _fog_mat
	add_child(_fog)

	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Wind")
	AudioServer.set_bus_send(bus, "Master")
	_wind_filter = AudioEffectLowPassFilter.new()
	_wind_filter.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(bus, _wind_filter)
	_wind_audio = _wind_player(1.0, 0.0)
	_wind_low = _wind_player(0.6, 7.0)
	_wind_gust = _wind_player(1.45, 3.0)


func _wind_player(pitch: float, start: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = main.sound("wind_loop", true)
	p.pitch_scale = pitch
	p.bus = "Wind"
	p.volume_db = -80.0
	add_child(p)
	p.play(start)
	return p


func _layer(mode: int, lifetime: float, size: float, opacity: float, extents: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.lifetime = lifetime
	p.local_coords = false
	p.preprocess = lifetime
	p.visibility_aabb = AABB(Vector3(-70.0, -30.0, -70.0), Vector3(140.0, 60.0, 140.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.particle_flag_align_y = mode == 0
	m.spread = 6.0 if mode == 0 else 18.0
	m.scale_min = 0.6
	m.scale_max = 1.5
	if mode != 0:
		m.turbulence_enabled = true
		m.turbulence_noise_strength = 1.2 if mode == 1 else 0.6
		m.turbulence_noise_scale = 4.0
		m.turbulence_influence_min = 0.05
		m.turbulence_influence_max = 0.2
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.8, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	m.color_ramp = ramp
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/snow.gdshader")
	mat.set_shader_parameter("mode", mode)
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("opacity", opacity)
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	return p


func set_quality(q: int) -> void:
	var a: Array = AMOUNTS[clampi(q, 0, 2)]
	_streaks.amount = a[0]
	_flakes.amount = a[1]
	_drift.amount = a[2]


func set_indoors(on: bool) -> void:
	_indoors = on
	for p in [_streaks, _flakes, _drift]:
		p.emitting = not on
		p.visible = not on


func wind_vector() -> Vector2:
	# The wind as meters per second along the ground.
	return WIND * (2.5 + 16.0 * wind)


func _lull_target() -> float:
	if forced == "lull":
		return 1.0
	if forced != "":
		return 0.0
	var t: float = main.phase_time
	match main.phase:
		"day":
			return 1.0 if t > DAY_LULL.x and t < DAY_LULL.y else 0.0
		"dusk":
			return 1.0 if t > DUSK_LULL.x and t < DUSK_LULL.y else 0.0
	return 0.0


func _process(delta: float) -> void:
	_t += delta
	if main.player != null:
		global_position = main.player.global_position
	var phase: String = main.phase
	var outdoors_phase := phase == "day" or phase == "dusk" or phase == "night"

	var target := _lull_target()
	lull = move_toward(lull, target, delta / (7.0 if target > lull else 10.0))
	if forced == "lull":
		lull = 1.0

	var base := 0.55
	match phase:
		"dream":
			base = 0.22
		"title", "end":
			base = 0.35
		"dusk":
			base = 0.5
		"night":
			base = 0.62
	base += 0.16 * _noise.get_noise_1d(_t * 3.0)

	if _gust_t < 0.0:
		_next_gust -= delta
		if _next_gust <= 0.0 and lull < 0.05 and outdoors_phase:
			_gust_t = 0.0
			_gust_len = randf_range(9.0, 15.0)
			_gust_peak = randf_range(0.65, 1.0)
	else:
		_gust_t += delta
		if _gust_t >= _gust_len:
			_gust_t = -1.0
			_next_gust = randf_range(18.0, 45.0) if phase == "night" else randf_range(25.0, 60.0)
	var env := 0.0
	if _gust_t >= 0.0:
		# Up in a couple of seconds, a few seconds white, then easing off slowly.
		env = smoothstep(0.0, 2.5, _gust_t) * (1.0 - smoothstep(_gust_len - 6.0, _gust_len, _gust_t))
	gust = _gust_peak * env * (1.0 - lull)
	wind = clampf(base + gust * 0.45, 0.0, 1.0) * (1.0 - 0.85 * lull)
	match forced:
		"gust":
			gust = 1.0
			wind = 0.95
		"calm":
			gust = 0.0
			wind = 0.18
		"storm":
			gust = 0.45
			wind = 0.9
	reveal = smoothstep(0.4, 1.0, lull) if (phase == "day" or phase == "dusk") else 0.0
	_offset += wind_vector() * delta

	RenderingServer.global_shader_parameter_set("wind_dir", WIND)
	RenderingServer.global_shader_parameter_set("wind_strength", wind)
	RenderingServer.global_shader_parameter_set("wind_offset", _offset)
	RenderingServer.global_shader_parameter_set("gust", gust)
	RenderingServer.global_shader_parameter_set("mountain_reveal", reveal)

	_update_snow()
	_update_audio()
	_update_events(outdoors_phase)


func _update_snow() -> void:
	var dir := Vector3(WIND.x, 0.0, WIND.y)
	var speed := 2.5 + 16.0 * wind
	var sm := _streaks.process_material as ParticleProcessMaterial
	sm.direction = (dir + Vector3(0.0, -0.1, 0.0)).normalized()
	sm.initial_velocity_min = speed * 0.85
	sm.initial_velocity_max = speed * 1.15
	sm.gravity = Vector3(0.0, -1.2, 0.0)
	_streaks.position = -dir * 9.0 + Vector3(0.0, 3.0, 0.0)
	_streaks.amount_ratio = 0.3 + 0.7 * wind
	var fm := _flakes.process_material as ParticleProcessMaterial
	fm.direction = (dir + Vector3(0.0, -0.25, 0.0)).normalized()
	fm.initial_velocity_min = speed * 0.3
	fm.initial_velocity_max = speed * 0.5
	fm.gravity = Vector3(0.0, -0.6, 0.0)
	_flakes.position = -dir * 2.5 + Vector3(0.0, 1.6, 0.0)
	_flakes.amount_ratio = 0.4 + 0.6 * wind
	var dm := _drift.process_material as ParticleProcessMaterial
	dm.direction = dir
	dm.initial_velocity_min = speed * 0.55
	dm.initial_velocity_max = speed * 0.8
	dm.gravity = Vector3.ZERO
	_drift.position = -dir * 7.0 + Vector3(0.0, 0.02, 0.0)
	_drift.amount_ratio = smoothstep(0.2, 0.8, wind)
	_fog_mat.set_shader_parameter("ground_y", global_position.y)


func _update_audio() -> void:
	var muffled := _indoors
	_wind_filter.cutoff_hz = move_toward(_wind_filter.cutoff_hz, 650.0 if muffled else 20000.0,
		get_process_delta_time() * 40000.0)
	var quiet := 0.0 if main.phase == "dream" else 1.0
	_wind_audio.volume_db = linear_to_db(0.05 + 0.95 * wind) - 9.0 + (3.0 if muffled else 0.0)
	_wind_low.volume_db = linear_to_db(0.1 + 0.9 * wind) - 12.0 + 6.0 * (1.0 - quiet)
	_wind_gust.volume_db = linear_to_db(maxf(gust, 0.001)) - 6.0


func _update_events(outdoors_phase: bool) -> void:
	var outside: bool = main.player != null and main.player.mode == "walk"
	var white := gust > 0.72
	if white and not _white and outdoors_phase and outside and forced == "":
		whiteouts += 1
		main.on_whiteout(whiteouts)
	_white = white
	var in_lull := lull > 0.6
	if in_lull and not _in_lull and outdoors_phase and forced == "":
		main.on_lull()
	_in_lull = in_lull
