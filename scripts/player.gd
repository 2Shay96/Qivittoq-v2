extends CharacterBody3D
## Eske, seen from his own eyes. Modes: walk, tent, cutscene, frozen.

const Meshes := preload("res://scripts/meshes.gd")
const Materials := preload("res://scripts/materials.gd")
const FireScript := preload("res://scripts/fire.gd")
const FuelItem := preload("res://scripts/fuel_item.gd")

const WALK_SPEED := 2.3
const MOUSE_SENS := 0.0022
const GRAVITY := 9.8
const MAX_CARRY := 4
const STAND_HEIGHT := 1.6
const SIT_HEIGHT := 0.86

var main
var mode := "walk"
var warmth := 1.0
var carry: Array = []
var has_torch := false
var torch_time := 0.0
var candle_lit := false
var holding_breath := false

var head: Node3D
var camera: Camera3D
var ray: RayCast3D
var hands: Node3D
var tent

var _yaw := 0.0
var _pitch := 0.0
var _yaw_center := 0.0
var _yaw_limit := PI
var _pitch_limit := 1.4
var _head_height := STAND_HEIGHT
var _collision: CollisionShape3D
var _torch: Node3D
var _torch_light: OmniLight3D
var _torch_flames: GPUParticles3D
var _breath: AudioStreamPlayer
var _steps: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _step_acc := 0.0
var _bob := 0.0
var _shake_t := 0.0
var _focus = null
var _water_warned := false


func _ready() -> void:
	_collision = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	_collision.shape = capsule
	_collision.position.y = 0.875
	add_child(_collision)

	head = Node3D.new()
	head.position.y = STAND_HEIGHT
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.04
	camera.far = 9500.0
	camera.current = true
	head.add_child(camera)

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -2.6)
	ray.add_exception(self)
	camera.add_child(ray)

	hands = Node3D.new()
	hands.position = Vector3(0.0, -0.36, -0.5)
	camera.add_child(hands)
	_build_torch()

	_breath = AudioStreamPlayer.new()
	_breath.stream = main.sound("breath_loop", true)
	_breath.volume_db = -30.0
	add_child(_breath)
	_breath.play()
	_steps = AudioStreamPlayer.new()
	_steps.volume_db = -6.0
	add_child(_steps)
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)


func _build_torch() -> void:
	_torch = Node3D.new()
	_torch.position = Vector3(0.3, 0.06, 0.05)
	_torch.rotation = Vector3(0.0, 0.0, deg_to_rad(-62.0))
	var stick := MeshInstance3D.new()
	stick.mesh = Meshes.log_mesh(0.62, 0.022, 41, 0.02, 0.95)
	stick.material_override = Materials.get_mat("firewood")
	stick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_torch.add_child(stick)
	_torch_flames = FireScript.make_flames(18, 0.32)
	_torch_flames.position = Vector3(0.31, 0.0, 0.0)
	_torch_flames.rotation.z = deg_to_rad(62.0)
	_torch.add_child(_torch_flames)
	_torch_light = OmniLight3D.new()
	_torch_light.light_color = Color(1.0, 0.58, 0.28)
	_torch_light.light_energy = 1.2
	_torch_light.omni_range = 6.0
	_torch_light.shadow_enabled = true
	_torch_light.light_size = 0.05
	_torch_light.light_volumetric_fog_energy = 1.2
	_torch_light.position = Vector3(0.4, 0.05, 0.0)
	_torch.add_child(_torch_light)
	_torch.visible = false
	hands.add_child(_torch)


# --- Input ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if OS.has_feature("movie"):
		return
	if event is InputEventMouseButton and event.pressed:
		if main.phase != "end" and not main.hud.menu_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if mode == "frozen":
			return
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch -= event.relative.y * MOUSE_SENS
		_yaw = clampf(_yaw, _yaw_center - _yaw_limit, _yaw_center + _yaw_limit)
		_pitch = clampf(_pitch, -_pitch_limit, _pitch_limit)


func look_at_yaw(yaw: float, pitch := 0.0) -> void:
	_yaw = yaw
	_pitch = pitch
	_yaw_center = yaw


func _physics_process(delta: float) -> void:
	rotation.y = _yaw
	head.rotation.x = _pitch
	if mode != "walk":
		velocity = Vector3.ZERO
		return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := WALK_SPEED * (0.55 + 0.45 * warmth)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta

	# The sea is the one wall: Eske will not wade into it.
	var ahead := global_position + Vector3(velocity.x, 0.0, velocity.z) * 0.4
	if main.world.height_at(ahead.x, ahead.z) < -0.3:
		velocity.x = 0.0
		velocity.z = 0.0
		if not _water_warned:
			_water_warned = true
			main.voice.say("water")
	else:
		_water_warned = false
	move_and_slide()
	# Never fall through the world, wherever the cold lets him wander.
	var floor_y: float = main.world.height_at(global_position.x, global_position.z)
	if global_position.y < floor_y - 0.5:
		global_position.y = floor_y + 0.05
		velocity.y = 0.0

	var moving := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and moving > 0.3:
		_step_acc += moving * delta
		_bob += moving * delta * 6.5
		if _step_acc > 0.8:
			_step_acc = 0.0
			_steps.stream = main.sound("step_snow_%d" % randi_range(1, 4))
			_steps.pitch_scale = randf_range(0.9, 1.1)
			_steps.play()
	head.position.y = _head_height + sin(_bob) * 0.025 * clampf(moving, 0.0, 1.0)


# --- Per frame: cold, prompts, torch ------------------------------------------

func _process(delta: float) -> void:
	var scaled: float = delta * main.time_scale
	if main.clock_running() and mode != "frozen":
		_update_warmth(scaled)

	var cold := 1.0 - warmth
	main.hud.set_frost(smoothstep(0.3, 1.0, cold))
	main.set_muffle(smoothstep(0.4, 1.0, cold))
	main.voice.cold = cold
	var fear_breath: float = 0.6 if main.phase == "dream" else 0.0
	var breath_level := maxf(fear_breath, 0.08 + 0.92 * smoothstep(0.2, 1.0, cold))
	_breath.volume_db = -80.0 if holding_breath else linear_to_db(breath_level) - 6.0
	_breath.pitch_scale = 1.0 + 0.45 * cold
	_shake_t += delta * 30.0
	camera.rotation.z = sin(_shake_t * 1.3) * 0.006 * cold * cold
	hands.position.x = sin(_shake_t) * 0.008 * cold * cold

	if has_torch:
		torch_time -= scaled
		_torch_light.light_energy = 1.1 + 0.3 * sin(_shake_t * 0.37) + 0.2 * sin(_shake_t * 0.91)
		if torch_time <= 0.0:
			drop_torch()
			main.voice.say("torch_out")

	holding_breath = mode == "cutscene" and Input.is_action_pressed("hold_breath")
	match mode:
		"walk":
			_update_focus()
			if Input.is_action_just_pressed("interact") and _focus != null and is_instance_valid(_focus):
				_focus.interact(self)
		"tent":
			_update_tent()


func _update_warmth(dt: float) -> void:
	if mode == "tent":
		if main.fire.lit:
			warmth += dt / 40.0
		else:
			warmth -= dt / 300.0
	elif near_fire():
		warmth += dt / 12.0
	else:
		var rate: float = 1.0 / 150.0 if main.phase == "day" else 1.0 / 85.0
		if has_torch:
			rate *= 0.6
		warmth -= dt * rate
	warmth = clampf(warmth, 0.0, 1.0)
	if warmth <= 0.0 and mode == "walk":
		mode = "frozen"
		main.on_player_froze()


func near_fire() -> bool:
	var fire = main.fire
	return fire.lit and global_position.distance_to(fire.global_position) < fire.warm_radius()


func looking_at(target: Vector3, within: float) -> bool:
	var to := target - camera.global_position
	if to.length() > within:
		return false
	return (-camera.global_basis.z).dot(to.normalized()) > 0.88


func _update_focus() -> void:
	ray.force_raycast_update()
	var hit = ray.get_collider()
	_focus = null
	var prompt := ""
	if hit != null and hit.has_method("get_prompt"):
		prompt = hit.get_prompt(self)
		if prompt != "":
			_focus = hit
	main.hud.set_prompt(prompt, "E" if prompt != "" else "")


func _update_tent() -> void:
	var lines := PackedStringArray()
	if main.can_carve():
		lines.append("[E] Carve the day's line")
	lines.append("[B] Blow out the candle" if candle_lit else "[B] Light the candle")
	lines.append("[Q] Crawl out")
	main.hud.set_prompt("      ".join(lines))
	if Input.is_action_just_pressed("interact") and main.can_carve():
		main.carve()
	elif Input.is_action_just_pressed("candle"):
		set_candle(not candle_lit)
	elif Input.is_action_just_pressed("leave_tent"):
		exit_tent()


# --- Carrying ------------------------------------------------------------------

func can_carry() -> bool:
	return carry.size() < MAX_CARRY


func carrying() -> bool:
	return not carry.is_empty()


func carry_item(kind: String, value: float) -> void:
	carry.append({"kind": kind, "value": value})
	play_sfx("wood_drop", -10.0)
	_rebuild_armful()
	main.on_picked_up(kind)
	if not can_carry():
		main.voice.say("arms_full")


func drop_all() -> Array:
	var items := carry.duplicate()
	carry.clear()
	_rebuild_armful()
	return items


func _rebuild_armful() -> void:
	# What he carries sits in the crook of his arms, low in the view.
	for child in hands.get_children():
		if child != _torch:
			child.queue_free()
	for k in range(carry.size()):
		var mi := MeshInstance3D.new()
		if carry[k]["kind"] == "blubber":
			mi.mesh = Meshes.blubber(k)
			mi.material_override = Materials.get_mat("blubber")
			mi.position = Vector3(-0.08 + 0.1 * (k % 2), -0.05 + k * 0.06, -0.02)
			mi.rotation = Vector3(0.2, 0.3 * k, 0.0)
		else:
			mi.mesh = FuelItem.driftwood_mesh(k)
			mi.material_override = Materials.get_mat("carried")
			mi.scale = Vector3(0.7, 1.0, 1.0)
			mi.position = Vector3(-0.05, -0.08 + k * 0.075, 0.02 * (k % 2))
			mi.rotation = Vector3(0.0, 0.28 * (k % 2 - 0.5) + 0.15, 0.08)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hands.add_child(mi)


func take_torch() -> void:
	has_torch = true
	torch_time = 60.0
	_torch.visible = true
	_torch_flames.emitting = true
	main.voice.say("torch_take")


func drop_torch() -> void:
	has_torch = false
	_torch.visible = false
	_torch_flames.emitting = false


func play_sfx(sound_name: String, volume_db := 0.0) -> void:
	_sfx.stream = main.sound(sound_name)
	_sfx.volume_db = volume_db
	_sfx.play()


# --- Places and poses ------------------------------------------------------------

func enter_tent(t) -> void:
	tent = t
	mode = "tent"
	if has_torch:
		drop_torch()
	_collision.disabled = true
	global_position = tent.inside_point()
	_head_height = SIT_HEIGHT
	head.position.y = SIT_HEIGHT
	look_at_yaw(tent.rotation.y + PI * 0.5, -0.08)
	_yaw_limit = 2.6
	_pitch_limit = 1.1
	tent.set_occupied(true)
	main.weather.set_indoors(true)
	main.voice.indoors = true
	main.hud.set_prompt("")
	set_candle(main.phase == "dusk" or main.phase == "night")
	main.on_enter_tent()


func exit_tent() -> void:
	if main.sleeping:
		main.wake("")
	candle_lit = false  # put out quietly; leaving is not going to sleep
	tent.set_candle(false)
	tent.set_occupied(false)
	main.weather.set_indoors(false)
	main.voice.indoors = false
	global_position = tent.outside_point()
	_collision.disabled = false
	_head_height = STAND_HEIGHT
	head.position.y = STAND_HEIGHT
	look_at_yaw(rotation.y, -0.05)
	_yaw_limit = PI * 4.0
	_pitch_limit = 1.4
	mode = "walk"
	main.on_leave_tent()


func set_candle(on: bool) -> void:
	if candle_lit and not on:
		play_sfx("candle_blow", -4.0)
	candle_lit = on
	if tent != null:
		tent.set_candle(on)
	if mode == "tent":
		main.on_candle(on)


func enter_cutscene(pos: Vector3, yaw: float, eye_height: float) -> void:
	mode = "cutscene"
	_collision.disabled = true
	global_position = pos
	_head_height = eye_height
	head.position.y = eye_height
	look_at_yaw(yaw, 0.0)
	_yaw_limit = 0.9
	_pitch_limit = 0.5


func place_outside(pos: Vector3, yaw: float) -> void:
	mode = "walk"
	_collision.disabled = false
	global_position = pos
	_head_height = STAND_HEIGHT
	head.position.y = STAND_HEIGHT
	look_at_yaw(yaw, -0.1)
	_yaw_limit = PI * 4.0
	_pitch_limit = 1.4
	if tent != null:
		tent.set_occupied(false)
	main.weather.set_indoors(false)
	main.voice.indoors = false
