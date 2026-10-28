extends RefCounted
## Materials shared by everything in the world, each made once.

static var _cache := {}


static func get_mat(mat_name: String) -> Material:
	if _cache.has(mat_name):
		return _cache[mat_name]
	var m: Material
	match mat_name:
		"rock":
			m = _shader("rock", {"base": Color(0.15, 0.155, 0.17), "snow_amount": 0.32})
		"rock_shore":
			m = _shader("rock", {"base": Color(0.12, 0.125, 0.135), "snow_amount": 0.3})
		"rock_fire":
			m = _shader("rock", {"base": Color(0.11, 0.105, 0.1), "snow_amount": 0.0})
		"driftwood":
			m = _shader("wood", {"base": Color(0.56, 0.54, 0.51), "snow_amount": 0.35})
		"carried":
			m = _shader("wood", {"base": Color(0.56, 0.54, 0.51), "snow_amount": 0.15})
		"firewood":
			m = _shader("wood", {"base": Color(0.33, 0.29, 0.25), "snow_amount": 0.0, "char_amount": 1.0})
		"tar":
			m = _shader("wood", {"base": Color(0.11, 0.095, 0.08), "snow_amount": 0.45, "grain_depth": 0.6})
		"pole":
			m = _shader("wood", {"base": Color(0.36, 0.31, 0.26), "snow_amount": 0.35})
		"oar":
			m = _shader("wood", {"base": Color(0.42, 0.37, 0.31), "snow_amount": 0.5})
		"canvas":
			m = _shader("cloth", {"base": Color(0.41, 0.395, 0.365), "flutter": 1.0, "glow_through": 0.5,
				"snow_amount": 0.5})
		"hide":
			m = _shader("cloth", {"base": Color(0.17, 0.14, 0.12), "weave": 0.0, "fur": 1.0,
				"snow_amount": 0.0, "glow_through": 0.0})
		"wool":
			m = _shader("cloth", {"base": Color(0.3, 0.29, 0.27), "weave": 0.6, "snow_amount": 0.0,
				"glow_through": 0.0})
		"walrus":
			m = _shader("skin", {"snow_amount": 0.12})
		"blubber":
			m = _shader("skin", {"snow_amount": 0.05})
		"rope":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.32, 0.29, 0.25)
			sm.roughness = 1.0
			m = sm
		"tallow":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.8, 0.76, 0.64)
			sm.roughness = 0.6
			sm.subsurf_scatter_enabled = true
			sm.subsurf_scatter_strength = 0.6
			m = sm
		"iron":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.12, 0.11, 0.1)
			sm.metallic = 0.7
			sm.roughness = 0.6
			m = sm
		_:
			push_error("No material called %s" % mat_name)
			m = StandardMaterial3D.new()
	_cache[mat_name] = m
	return m


static func _shader(shader_name: String, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/%s.gdshader" % shader_name)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m
