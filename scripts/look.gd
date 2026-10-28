extends Node
## The look: sky, light, the distance haze and the color grade through the day.
##   Day: overcast, flat and cold, like light through ice.
##   Dusk: brief and violet-grey, never an orange sunset.
##   Night: blue-black, the snow barely readable, the fire a small warm pool.
## Everything is desaturated toward steel blue and grey; the grade gives back only the warm hues,
## so the fire is the only warm color in the game.

const QUALITY_NAMES := ["Low", "Medium", "High"]
# Colors are sRGB. Fog is the exponential density of the distance haze (layer 2).
const STATES := {
	"day": {"zenith": Color(0.43, 0.47, 0.53), "horizon": Color(0.71, 0.75, 0.8),
		"sun": Color(0.84, 0.89, 1.0), "sun_energy": 1.1, "sun_pitch": -16.0,
		"ambient": Color(0.6, 0.67, 0.78), "ambient_energy": 0.9, "fog": 0.03,
		"exposure": 1.0, "glint": 0.6, "mountain": Color(0.8, 0.84, 0.9)},
	"dusk": {"zenith": Color(0.28, 0.27, 0.35), "horizon": Color(0.52, 0.49, 0.58),
		"sun": Color(0.7, 0.66, 0.88), "sun_energy": 0.4, "sun_pitch": -5.0,
		"ambient": Color(0.46, 0.44, 0.58), "ambient_energy": 0.72, "fog": 0.032,
		"exposure": 1.15, "glint": 0.15, "mountain": Color(0.44, 0.42, 0.55)},
	"night": {"zenith": Color(0.012, 0.015, 0.028), "horizon": Color(0.03, 0.038, 0.062),
		"sun": Color(0.5, 0.6, 0.9), "sun_energy": 0.07, "sun_pitch": -40.0,
		"ambient": Color(0.07, 0.1, 0.19), "ambient_energy": 0.42, "fog": 0.034,
		"exposure": 1.2, "glint": 0.0, "mountain": Color(0.03, 0.035, 0.05)},
	"dream": {"zenith": Color(0.03, 0.036, 0.06), "horizon": Color(0.1, 0.115, 0.16),
		"sun": Color(0.55, 0.65, 0.95), "sun_energy": 0.18, "sun_pitch": -30.0,
		"ambient": Color(0.11, 0.14, 0.26), "ambient_energy": 0.6, "fog": 0.012,
		"exposure": 1.4, "glint": 0.0, "mountain": Color(0.03, 0.035, 0.05)},
}

var main
var env: Environment
var sun: DirectionalLight3D
var quality := 1


func build() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL  # the sky changes slowly; spread the work
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX

	# Layer 2, the distance haze: exponential depth fog, a low mist over the water, and aerial
	# perspective, so far things take the sky's own color and the horizon is lost.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_aerial_perspective = 1.0
	env.fog_sky_affect = 0.0
	env.fog_height = 0.0
	env.fog_height_density = 0.9
	env.fog_sun_scatter = 0.0

	# Layer 1, the blizzard, lives in the volumetric fog (see weather.gd).
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_albedo = Color(1, 1, 1)
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_ambient_inject = 1.0
	env.volumetric_fog_anisotropy = 0.25
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.85

	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15

	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.62
	env.adjustment_color_correction = _grade_lut()

	var we := WorldEnvironment.new()
	we.environment = env
	main.add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_angular_distance = 2.5
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.light_volumetric_fog_energy = 0.6
	main.add_child(sun)


func _grade_lut() -> ImageTexture3D:
	# Shadows pushed toward blue-teal, highlights pale and bloodless. The global saturation of 0.62
	# drains everything; here the warm hues get their color back, so the fire alone is warm.
	var n := 33
	var images: Array[Image] = []
	for b in range(n):
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for g in range(n):
			for r in range(n):
				img.set_pixel(r, g, grade(Color(r / (n - 1.0), g / (n - 1.0), b / (n - 1.0))))
		images.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, n, n, n, false, images)
	return tex


static func grade(c: Color) -> Color:
	var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	var warm := smoothstep(0.1, 0.3, c.r - c.b) * clampf((c.r - c.g) * 5.0 + 0.3, 0.0, 1.0)
	var sat := lerpf(1.0, 1.55, warm)
	var out := Color(l + (c.r - l) * sat, l + (c.g - l) * sat, l + (c.b - l) * sat)
	var shadow := (1.0 - smoothstep(0.0, 0.5, l)) * (1.0 - warm)
	out.r += -0.022 * shadow
	out.g += 0.006 * shadow
	out.b += 0.03 * shadow
	var high := smoothstep(0.55, 1.0, l) * (1.0 - warm)
	out = out.lerp(Color(l * 0.98, l * 0.995, l * 1.01), high * 0.55)
	return Color(clampf(out.r, 0.0, 1.0), clampf(out.g, 0.0, 1.0), clampf(out.b, 0.0, 1.0))


func _blend() -> Array:
	# Which two states to blend, and how far, for this moment.
	var t: float = main.phase_time
	match main.phase:
		"day":
			return ["day", "dusk", smoothstep(0.82, 1.0, t / main.DAY_LENGTH) * 0.5]
		"dusk":
			var f: float = t / main.DUSK_LENGTH
			if f < 0.5:
				return ["day", "dusk", 0.5 + f]
			return ["dusk", "night", (f - 0.5) * 2.0]
		"night", "end":
			return ["night", "night", 0.0]
		"title":
			return ["dream", "dream", 0.0]
	return ["dream", "dream", 0.0]


func update(weather) -> void:
	var b := _blend()
	var a: Dictionary = STATES[b[0]]
	var c: Dictionary = STATES[b[1]]
	var f: float = b[2]
	var zenith: Color = (a["zenith"] as Color).lerp(c["zenith"], f)
	var horizon: Color = (a["horizon"] as Color).lerp(c["horizon"], f)
	var lull: float = weather.lull if weather != null else 0.0
	var gust: float = weather.gust if weather != null else 0.0
	# In a whiteout the near haze brightens; in a lull the air clears.
	horizon = horizon.lerp(horizon.lightened(0.08), gust)
	var zl := zenith.srgb_to_linear()
	var hl := horizon.srgb_to_linear()
	RenderingServer.global_shader_parameter_set("sky_zenith", Vector3(zl.r, zl.g, zl.b))
	RenderingServer.global_shader_parameter_set("sky_horizon", Vector3(hl.r, hl.g, hl.b))
	var ml := (a["mountain"] as Color).lerp(c["mountain"], f).srgb_to_linear()
	RenderingServer.global_shader_parameter_set("mountain_light", Vector3(ml.r, ml.g, ml.b))
	RenderingServer.global_shader_parameter_set("snow_glint", lerpf(a["glint"], c["glint"], f))

	var fog: float = lerpf(a["fog"], c["fog"], f) * (0.85 + 0.3 * (weather.wind if weather != null else 0.5))
	env.fog_density = lerpf(fog, 0.0045, lull)
	env.fog_light_color = horizon
	env.ambient_light_color = (a["ambient"] as Color).lerp(c["ambient"], f)
	env.ambient_light_energy = lerpf(a["ambient_energy"], c["ambient_energy"], f)
	env.tonemap_exposure = lerpf(a["exposure"], c["exposure"], f)
	sun.light_color = (a["sun"] as Color).lerp(c["sun"], f)
	sun.light_energy = lerpf(a["sun_energy"], c["sun_energy"], f) * (1.0 + 0.25 * lull)
	sun.rotation_degrees = Vector3(lerpf(a["sun_pitch"], c["sun_pitch"], f), 200.0, 0.0)
	var to_sun := sun.global_basis.z
	RenderingServer.global_shader_parameter_set("light_dir", to_sun)


func apply_quality(q: int) -> void:
	quality = clampi(q, 0, 2)
	var vp: Viewport = main.get_viewport()
	match quality:
		0:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = 0.6
			env.ssao_enabled = false
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			RenderingServer.environment_set_volumetric_fog_volume_size(64, 48)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_DISABLED)
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		1:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			vp.scaling_3d_scale = 0.72
			env.ssao_enabled = true
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 50.0, 300.0)
			RenderingServer.environment_set_volumetric_fog_volume_size(80, 56)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
			RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_LOW)
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		2:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			env.ssao_enabled = true
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, false, 0.5, 2, 50.0, 300.0)
			RenderingServer.environment_set_volumetric_fog_volume_size(128, 96)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_MEDIUM)
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	if main.weather != null:
		main.weather.set_quality(quality)
