extends Node3D
## Qivittoq, Night 1 prototype (v2): the dream, the title, one day, dusk and one night.
##
## Command-line options for testing (after a lone `--`):
##   --start=dream|day|walk|dusk|night|tent-night   where to begin
##   --look=YAW,PITCH                                 starting view in degrees
##   --at=X,Z                                         start standing here
##   --time=SECONDS                                   jump into the phase
##   --weather=lull|gust|calm|storm                   hold the weather
##   --quality=low|medium|high                        override the saved quality
##   --fast                                           run the clock 8x
##   --demo-subs                                      put a line and a caption on screen
##   --bench=SECONDS                                  print the frame rate, then quit
##   --selftest                                       play through every mechanic

const WorldBuilder := preload("res://scripts/world_builder.gd")
const PlayerScript := preload("res://scripts/player.gd")
const FireScript := preload("res://scripts/fire.gd")
const TentScript := preload("res://scripts/tent.gd")
const WoodpileScript := preload("res://scripts/woodpile.gd")
const HudScript := preload("res://scripts/hud.gd")
const VoiceScript := preload("res://scripts/voice.gd")
const WeatherScript := preload("res://scripts/weather.gd")
const LookScript := preload("res://scripts/look.gd")
const Meshes := preload("res://scripts/meshes.gd")
const Materials := preload("res://scripts/materials.gd")

const DAY_LENGTH := 240.0
const DUSK_LENGTH := 45.0
const NIGHT_LENGTH := 360.0
const DREAM_LENGTH := 49.0
const SLEEP_SPEED := 12.0
const FAST_SPEED := 8.0
const ICE := Vector3(-75.0, 0.0, 8.0)

var phase := "dream"
var phase_time := 0.0
var time_scale := 1.0
var sleeping := false
var debug_fast := false
var closeness := 0
var fires_died := 0
var times_frozen := 0
var held_breath := false
var carved_tonight := false

var world: WorldBuilder
var player: PlayerScript
var fire: FireScript
var tent: TentScript
var woodpile: WoodpileScript
var hud: HudScript
var voice: VoiceScript
var weather: WeatherScript
var look: LookScript
var args := {}

var _sounds := {}
var _prev_time := 0.0
var _breath_held_for := 0.0
var _lowpass: AudioEffectLowPassFilter
var _music: AudioStreamPlayer
var _ice: AudioStreamPlayer3D
var _canvas_breath: AudioStreamPlayer3D
var _lantern: Node3D
var _lantern_voice: AudioStreamPlayer3D
var _lantern_tween: Tween
var _waking := false


func _ready() -> void:
	_parse_args()
	debug_fast = args.has("fast")
	_setup_input()
	_setup_audio_bus()
	world = WorldBuilder.new()
	add_child(world.build_terrain())
	add_child(world.build_sea())
	world.build_props(self)
	world.spawn_fuel(self)

	look = LookScript.new()
	look.main = self
	add_child(look)
	look.build()

	hud = HudScript.new()
	hud.main = self
	add_child(hud)
	voice = VoiceScript.new()
	voice.main = self
	voice.subtitles = hud.subtitles
	add_child(voice)

	fire = FireScript.new()
	fire.main = self
	fire.position = world.ground(-1.6, 0.0)
	fire.died.connect(_on_fire_died)
	add_child(fire)

	tent = TentScript.new()
	tent.main = self
	tent.position = world.ground(WorldBuilder.TENT.x, WorldBuilder.TENT.y)
	add_child(tent)
	_canvas_breath = AudioStreamPlayer3D.new()
	_canvas_breath.stream = sound("breath_loop", true)
	_canvas_breath.position = Vector3(0.6, 0.8, -1.55)
	_canvas_breath.pitch_scale = 0.72
	_canvas_breath.unit_size = 2.0
	tent.add_child(_canvas_breath)

	woodpile = WoodpileScript.new()
	woodpile.main = self
	woodpile.position = world.ground(-1.2, 2.7)
	woodpile.rotation.y = 0.3
	add_child(woodpile)

	player = PlayerScript.new()
	player.main = self
	add_child(player)
	weather = WeatherScript.new()
	weather.main = self
	add_child(weather)
	weather.forced = args.get("weather", "")

	var q: int = hud.quality
	if args.has("quality"):
		q = maxi(0, ["low", "medium", "high"].find(args["quality"]))
		hud.quality = q
	look.apply_quality(q)
	_build_ambience()
	_begin(args.get("start", "dream"))
	if not OS.has_feature("movie"):  # leave the mouse alone while recording frames
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if args.has("selftest"):
		var test: Node = preload("res://scripts/selftest.gd").new()
		test.main = self
		add_child(test)
		test.run()
	if args.has("demo-subs"):
		_demo_subs()
	if args.has("bench"):
		_bench(float(args["bench"]))


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv: PackedStringArray = a.substr(2).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""


func _exit_tree() -> void:
	# Let go of the shared meshes and materials, so nothing is left over when the game closes.
	Materials._cache.clear()
	preload("res://scripts/fuel_item.gd")._meshes.clear()
	preload("res://scripts/carcass.gd")._stain = null
	WoodpileScript._blubber = null


# --- Setup ---------------------------------------------------------------------

func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"interact": [KEY_E], "hold_breath": [KEY_SPACE], "candle": [KEY_B],
		"leave_tent": [KEY_Q], "restart": [KEY_R],
		"debug_fast": [KEY_F1], "debug_skip": [KEY_F2], "debug_wood": [KEY_F3],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _setup_audio_bus() -> void:
	while AudioServer.get_bus_effect_count(0) > 0:
		AudioServer.remove_bus_effect(0, 0)
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(0, _lowpass)


func _build_ambience() -> void:
	_ice = AudioStreamPlayer3D.new()
	_ice.position = ICE
	_ice.unit_size = 60.0
	_ice.max_distance = 600.0
	add_child(_ice)
	_music = AudioStreamPlayer.new()
	_music.stream = sound("title_theme")
	_music.volume_db = -4.0
	add_child(_music)


func sound(sound_name: String, loop := false) -> AudioStream:
	if not _sounds.has(sound_name):
		var stream: AudioStreamWAV = load("res://audio/%s.wav" % sound_name)
		if loop:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
		_sounds[sound_name] = stream
	return _sounds[sound_name]


func set_muffle(amount: float) -> void:
	var cutoff := lerpf(20000.0, 900.0, amount)
	if sleeping:
		cutoff = minf(cutoff, 1400.0)
	_lowpass.cutoff_hz = cutoff


# --- Phases ----------------------------------------------------------------------

func clock_running() -> bool:
	return phase == "day" or phase == "dusk" or phase == "night"


func _begin(start: String) -> void:
	match start:
		"day":
			_start_day()
		"walk":
			_start_day()
			hud.fade_to(0.0, 0.1)
			_waking = false
			player.exit_tent()
			player.place_outside(world.ground(-3.0, 3.0) + Vector3(0, 0.1, 0), PI * 0.5)
		"dusk":
			_start_day()
			hud.fade_to(0.0, 0.1)
			_waking = false
			player.exit_tent()
			player.place_outside(world.ground(-3.5, 4.0) + Vector3(0, 0.1, 0), PI * 0.5)
			_start_dusk()
		"night", "tent-night":
			_start_day()
			hud.fade_to(0.0, 0.1)
			_waking = false
			player.exit_tent()
			_start_night()
			fire.fuel = 120.0
			if start == "tent-night":
				player.enter_tent(tent)
			else:
				player.place_outside(world.ground(1.0, 6.0) + Vector3(0, 0.1, 0), 0.15)
		_:
			_start_dream()
	if args.has("time"):
		phase_time = float(args["time"])
		_prev_time = phase_time
		if phase == "dream":
			_lantern_tween.custom_step(phase_time)
			hud.fade_to(0.0, 0.0)
	if args.has("at"):
		var at: PackedStringArray = String(args["at"]).split(",")
		player.place_outside(world.ground(float(at[0]), float(at[1])) + Vector3(0, 0.1, 0), 0.0)
	if args.has("look"):
		var parts: PackedStringArray = String(args["look"]).split(",")
		player.look_at_yaw(deg_to_rad(float(parts[0])), deg_to_rad(float(parts[1])))


func _set_phase(p: String) -> void:
	phase = p
	phase_time = 0.0
	_prev_time = -0.001


func _start_dream() -> void:
	_set_phase("dream")
	# The night the ship left: there is no camp yet.
	tent.visible = false
	woodpile.visible = false
	fire.visible = false
	fire.lit = false
	fire.fuel = 0.0
	player.enter_cutscene(world.ground(30.5, -26.0), PI * 0.5, 0.7)
	hud.fade_to(1.0, 0.0)
	hud.fade_to(0.0, 5.0)
	_build_lantern()


func _build_lantern() -> void:
	# The ship's boat, searching the shore for Eske the night they left: oarsmen in the dark, and
	# a lantern on a pole at the bow.
	_lantern = Node3D.new()
	_lantern.position = Vector3(-125.0, -0.2, 34.0)
	add_child(_lantern)
	var hull := MeshInstance3D.new()
	hull.mesh = Meshes.faering()
	hull.material_override = Materials.get_mat("tar")
	hull.scale = Vector3(1.35, 1.2, 1.25)
	_lantern.add_child(hull)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.028, 0.026)
	dark.roughness = 1.0
	for k in range(4):
		var man := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.24
		cap.height = 1.15
		man.mesh = cap
		man.material_override = dark
		man.position = Vector3(-2.2 + k * 1.25, 0.95, 0.12 * (k % 2 - 0.5))
		man.rotation.z = 0.15
		_lantern.add_child(man)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.66, 0.3)
	light.light_energy = 8.0
	light.omni_range = 40.0
	light.light_volumetric_fog_energy = 3.0
	light.position = Vector3(3.3, 2.1, 0.0)
	_lantern.add_child(light)
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var halo_mat := ShaderMaterial.new()
	halo_mat.shader = load("res://shaders/flame.gdshader")
	halo_mat.set_shader_parameter("mode", 1)
	halo_mat.set_shader_parameter("width", 1.0)
	halo_mat.set_shader_parameter("height", 1.0)
	halo_mat.set_shader_parameter("intensity", 0.5)
	quad.material = halo_mat
	halo.mesh = quad
	halo.scale = Vector3.ONE * 4.0
	halo.position = light.position
	_lantern.add_child(halo)
	var oars := AudioStreamPlayer3D.new()
	oars.stream = sound("oars_loop", true)
	oars.unit_size = 22.0
	oars.max_distance = 400.0
	_lantern.add_child(oars)
	oars.play()
	_lantern_voice = AudioStreamPlayer3D.new()
	_lantern_voice.unit_size = 45.0
	_lantern_voice.max_distance = 500.0
	_lantern_voice.volume_db = 4.0
	_lantern.add_child(_lantern_voice)

	var legs := [[Vector3(-50.0, -0.2, -10.0), 18.0], [Vector3(-50.0, -0.2, -10.0), 12.0],
		[Vector3(-170.0, -0.2, -80.0), 19.0]]
	var tw := create_tween()
	_lantern_tween = tw
	var from := _lantern.position
	for leg in legs:
		var to: Vector3 = leg[0]
		var d := to - from
		if d.length() > 1.0:
			tw.tween_property(_lantern, "rotation:y", atan2(-d.z, d.x), 3.0)
			tw.tween_property(_lantern, "position", to, float(leg[1]) - 3.0)
		else:
			tw.tween_interval(leg[1])
		from = to


func _start_title() -> void:
	_set_phase("title")
	if _lantern != null:
		_lantern.queue_free()
		_lantern = null
	voice.clear()
	hud.set_prompt("")
	hud.fade_to(1.0, 0.1)
	hud.show_title("QIVITTOQ", "Norðrseta, the autumn of 1424", 9.0)
	_music.play()


func _start_day() -> void:
	_set_phase("day")
	tent.visible = true
	woodpile.visible = true
	fire.visible = true
	fire.lit = true
	fire.fuel = 35.0
	player.warmth = 0.75
	player.enter_tent(tent)
	hud.fade_to(1.0, 0.0)
	hud.fade_to(0.0, 5.0)
	_waking = true


func _start_dusk() -> void:
	_set_phase("dusk")
	voice.say("dusk_light")
	if woodpile.count() < 5:
		voice.say("dusk_short")


func _start_night() -> void:
	_set_phase("night")
	carved_tonight = false
	voice.say("night_dark")


func _start_end() -> void:
	_set_phase("end")
	sleeping = false
	voice.clear()
	hud.set_prompt("")
	player.mode = "cutscene"
	hud.fade_to(1.0, 4.0, Color(0.72, 0.74, 0.78))
	await get_tree().create_timer(4.5).timeout
	hud.show_card("Day 2", "The first night is over.")
	await get_tree().create_timer(4.0).timeout
	var lines := PackedStringArray()
	if fires_died == 0:
		lines.append("The fire never went out.")
	else:
		lines.append("The fire went out %d time%s." % [fires_died, "" if fires_died == 1 else "s"])
	if closeness == 0:
		lines.append("Whatever waits out there kept its distance.")
	else:
		lines.append("Something is %d step%s closer." % [closeness, "" if closeness == 1 else "s"])
	if times_frozen > 0:
		lines.append("Someone carried you back to the tent.")
	lines.append("In the dream, you held your breath." if held_breath else "In the dream, you kept breathing.")
	lines.append("")
	lines.append("[R] Begin again")
	hud.show_card("End of the Night 1 prototype", "\n".join(lines))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- The clock ------------------------------------------------------------------------

func _process(delta: float) -> void:
	time_scale = (SLEEP_SPEED if sleeping else 1.0) * (FAST_SPEED if debug_fast else 1.0)
	if phase != "end":
		phase_time += delta * (time_scale if clock_running() else 1.0)
	_handle_debug_keys()
	look.update(weather)

	match phase:
		"dream":
			_run_dream(delta)
		"title":
			if _cross(9.5):
				var tw := create_tween()
				tw.tween_property(_music, "volume_db", -40.0, 6.0)
				tw.tween_callback(_music.stop)
				_start_day()
		"day":
			_run_day()
		"dusk":
			if phase_time >= DUSK_LENGTH:
				_start_night()
		"night":
			_run_night()
		"end":
			if Input.is_action_just_pressed("restart"):
				get_tree().reload_current_scene()
	_prev_time = phase_time

	if sleeping and fire.lit and fire.fuel < 10.0:
		wake("wake_cold")


func _cross(t: float) -> bool:
	return _prev_time < t and phase_time >= t


func _call(id: String) -> void:
	if _lantern_voice != null:
		voice.say(id, {"player": _lantern_voice})


func _run_dream(delta: float) -> void:
	var at: Vector3 = _lantern.global_position if _lantern != null else Vector3.ZERO
	if _cross(3.0):
		voice.caption("cap_lantern", at)
	if _cross(5.0):
		_call("dream_call_1")
	if _cross(9.5):
		_call("dream_call_2")
	if _cross(14.5):
		_call("dream_call_3")
	if _cross(18.0):
		voice.caption("cap_lantern_near", at)
	if _cross(20.0):
		_call("dream_call_4")
	if _cross(24.0):
		_call("dream_call_5")
	if _cross(30.0):
		_call("dream_call_6")
	if _cross(34.0):
		voice.caption("cap_lantern_away", at)
	if _cross(38.0):
		_call("dream_call_7")
	if _cross(DREAM_LENGTH - 6.0):
		hud.fade_to(1.0, 5.0)
	if _cross(DREAM_LENGTH):
		_start_title()
		return

	var window := phase_time > 18.0 and phase_time < 34.0
	hud.set_prompt("Hold your breath" if window else "", "Space")
	if window and player.holding_breath:
		_breath_held_for += delta
		if _breath_held_for > 1.5:
			held_breath = true


func _run_day() -> void:
	if _cross(70.0) or _cross(170.0):
		_ice.stream = sound("ice_groan")
		_ice.volume_db = -10.0
		_ice.play()
		voice.caption("cap_ice_far", ICE)
	if phase_time >= DAY_LENGTH:
		_start_dusk()


func _run_night() -> void:
	if _cross(100.0):
		if sleeping:
			wake("")
		_ice.stream = sound("ice_crack")
		_ice.volume_db = 2.0
		_ice.play()
		voice.caption("cap_ice_cry", ICE)
		voice.say("only_ice")
	if _cross(215.0):
		_ice.stream = sound("ice_groan")
		_ice.volume_db = -2.0
		_ice.play()
		voice.caption("cap_ice_groan", ICE)
	if _cross(300.0):
		_ice.stream = sound("ice_groan")
		_ice.volume_db = -12.0
		_ice.play()
		voice.caption("cap_ice_far", ICE)
	if phase_time >= NIGHT_LENGTH:
		_start_end()


func _handle_debug_keys() -> void:
	if Input.is_action_just_pressed("debug_fast"):
		debug_fast = not debug_fast
	if Input.is_action_just_pressed("debug_skip"):
		match phase:
			"dream":
				_start_title()
			"title":
				_start_day()
			"day":
				_start_dusk()
			"dusk":
				_start_night()
			"night":
				_start_end()
	if Input.is_action_just_pressed("debug_wood"):
		woodpile.add([{"kind": "driftwood", "value": 45.0}, {"kind": "driftwood", "value": 45.0},
			{"kind": "driftwood", "value": 45.0}, {"kind": "driftwood", "value": 45.0}])
	if debug_fast:
		hud.set_debug("x%d  %s %ds  fire %ds  warmth %d%%  wind %.2f  gust %.2f  lull %.2f  %d fps" % [
			int(FAST_SPEED), phase, int(phase_time), int(fire.fuel), int(player.warmth * 100.0),
			weather.wind, weather.gust, weather.lull, Engine.get_frames_per_second()])
	else:
		hud.set_debug("")


# --- What sets lines off -------------------------------------------------------------

func condition(cond: String) -> bool:
	match cond:
		"fire_low_no_fuel":
			return clock_running() and player.mode == "walk" and fire.lit and fire.fuel < 40.0 \
				and fire.fuel >= 15.0 and not player.carrying()
		"fire_dying":
			return clock_running() and player.mode == "walk" and fire.lit and fire.fuel < 15.0
		"cold_rising":
			return player.mode == "walk" and player.warmth < 0.4 and not player.near_fire()
		"looking_at_faering":
			return player.mode == "walk" and player.looking_at(world.faering_pos + Vector3(0, 0.4, 0), 14.0)
		"looking_at_carcass":
			if player.mode != "walk":
				return false
			for c in world.carcasses:
				if is_instance_valid(c) and player.looking_at(c.global_position + Vector3(0, 0.4, 0), 9.0):
					return true
			return false
	push_warning("No condition called %s" % cond)
	return false


# --- Sleep -------------------------------------------------------------------------------

func on_candle(lit: bool) -> void:
	if not lit and (phase == "dusk" or phase == "night"):
		_start_sleep()
	elif lit and sleeping:
		wake("")


func _start_sleep() -> void:
	sleeping = true
	hud.fade_to(0.94, 2.5)


func wake(line_id: String) -> void:
	if not sleeping:
		return
	sleeping = false
	hud.fade_to(0.0, 1.5)
	if line_id != "":
		voice.say(line_id)


# --- Things Eske does, and what they set off ------------------------------------------------

func on_enter_tent() -> void:
	if phase == "dusk" or phase == "night":
		voice.say("mark_day")


func on_leave_tent() -> void:
	if _waking:
		_waking = false
		for id in ["wake_bay", "wake_alone", "wake_fire", "wake_wood"]:
			voice.say(id)


func on_picked_up(kind: String) -> void:
	if kind == "driftwood":
		voice.say("first_wood")


func on_cut_blubber() -> void:
	voice.say("cut_blubber")


func on_fed_fire() -> void:
	voice.say("first_feed")


func on_fire_relit() -> void:
	voice.say("relit")


func on_whiteout(count: int) -> void:
	if count == 1:
		voice.caption("cap_wind_roar")
		voice.say("first_whiteout")


func on_lull() -> void:
	voice.caption("cap_wind_drops")
	if phase == "dusk":
		# The mountains take a few seconds to come out of the haze. On day 1 they are left silent.
		await get_tree().create_timer(6.0).timeout
		if player.mode == "walk":
			voice.say("mountains")


func can_carve() -> bool:
	return (phase == "dusk" or phase == "night") and not carved_tonight and player.mode == "tent"


func carve() -> void:
	carved_tonight = true
	player.play_sfx("carve")
	await get_tree().create_timer(1.6).timeout
	voice.carved("carved_night_1")
	voice.say("sleep_hint")


func _on_fire_died() -> void:
	fires_died += 1
	closeness += 1
	if player.mode == "tent":
		wake("")
		voice.caption("cap_glow_out")
		await get_tree().create_timer(3.0).timeout
		if player.mode == "tent" and not fire.lit:
			_canvas_breath.play()
			voice.caption("cap_breath", _canvas_breath.global_position)
			voice.say("dont_look")
			await get_tree().create_timer(6.0).timeout
			_canvas_breath.stop()
	else:
		voice.say("fire_died")


func on_player_froze() -> void:
	voice.say("freeze")
	player.drop_all()
	player.drop_torch()
	var tw := hud.fade_to(1.0, 3.0)
	await tw.finished
	times_frozen += 1
	var length := DAY_LENGTH if phase == "day" else (DUSK_LENGTH if phase == "dusk" else NIGHT_LENGTH)
	phase_time = minf(phase_time + 30.0, length - 1.0)
	_prev_time = phase_time
	fire.lit = true
	fire.strikes_needed = 0
	fire.fuel = maxf(fire.fuel, 70.0)
	player.warmth = 0.45
	player.enter_tent(tent)
	hud.fade_to(0.0, 4.0)
	voice.say("woke_where")
	voice.say("woke_fire")


# --- For recording frames and measuring -------------------------------------------------

func _demo_subs() -> void:
	await get_tree().create_timer(0.6).timeout
	voice.say("see_carcass")
	voice.caption("cap_ice_cry", ICE)


func _bench(seconds: float) -> void:
	await get_tree().create_timer(4.0).timeout
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	await get_tree().create_timer(seconds).timeout
	var fps := (Engine.get_frames_drawn() - f0) / ((Time.get_ticks_usec() - t0) / 1e6)
	var size := get_viewport().get_visible_rect().size
	var px := DisplayServer.window_get_size()
	print("BENCH %s quality=%s window=%dx%d 3d_scale=%.2f fps=%.1f" % [phase, look.QUALITY_NAMES[look.quality],
		px.x, px.y, get_viewport().scaling_3d_scale, fps])
	print("BENCH ui_size=%s" % size)
	get_tree().quit()
