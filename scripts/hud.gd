extends CanvasLayer
## Everything drawn over the world, at native resolution: vignette and grain, frost, the
## interaction prompt (in a place of its own, never under the subtitles), fades, title cards,
## the subtitles, and the settings (Esc).

const SubtitlesScript := preload("res://scripts/subtitles.gd")
const SETTINGS_PATH := "user://settings.cfg"
const PROMPT := Color(0.86, 0.87, 0.89, 0.92)
const KEY := Color(0.62, 0.65, 0.7)

var main
var subtitles
var quality := 1

var _post: ColorRect
var _frost: ColorRect
var _fade: ColorRect
var _prompt: RichTextLabel
var _title: Label
var _below: Label
var _debug: Label
var _menu: PanelContainer
var _menu_buttons := {}
var _fade_tween: Tween


func _ready() -> void:
	layer = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	var serif: Font = SubtitlesScript.serif(false)
	var italic: Font = SubtitlesScript.serif(true)

	_post = _full_rect()
	var post_mat := ShaderMaterial.new()
	post_mat.shader = load("res://shaders/post.gdshader")
	_post.material = post_mat
	add_child(_post)

	_frost = _full_rect()
	var frost_mat := ShaderMaterial.new()
	frost_mat.shader = load("res://shaders/frost.gdshader")
	_frost.material = frost_mat
	add_child(_frost)

	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.3)
	dot.size = Vector2(3, 3)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position -= Vector2(1.5, 1.5)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)

	# The prompt sits a little below the middle of the view: its own place, clear of the subtitles.
	_prompt = RichTextLabel.new()
	_prompt.bbcode_enabled = true
	_prompt.fit_content = true
	_prompt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_prompt.scroll_active = false
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_prompt.anchor_top = 0.57
	_prompt.anchor_bottom = 0.57
	_prompt.add_theme_font_override("normal_font", serif)
	_prompt.add_theme_font_size_override("normal_font_size", 27)
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_prompt.add_theme_constant_override("shadow_offset_x", 0)
	_prompt.add_theme_constant_override("shadow_offset_y", 1)
	_prompt.add_theme_constant_override("shadow_outline_size", 6)
	add_child(_prompt)

	_fade = _full_rect()
	_fade.color = Color(0, 0, 0, 0)
	add_child(_fade)

	_title = _label(serif, 104, Color(0.84, 0.86, 0.89))
	_title.offset_bottom = -60
	add_child(_title)
	_below = _label(italic, 34, Color(0.6, 0.63, 0.67))
	_below.offset_top = 110
	add_child(_below)

	subtitles = SubtitlesScript.new()
	add_child(subtitles)

	_debug = Label.new()
	_debug.add_theme_font_size_override("font_size", 18)
	_debug.add_theme_color_override("font_color", Color(0.9, 0.5, 0.4))
	_debug.position = Vector2(12, 8)
	add_child(_debug)

	_build_menu(serif)
	_load_settings()


func _full_rect() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _label(font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	return l


# --- Prompts, frost, fades, cards -------------------------------------------------

## The prompt for what Eske is looking at. `key` is shown before it, quieter: [E] Feed the fire.
func set_prompt(text: String, key := "") -> void:
	if text == "":
		_prompt.text = ""
		return
	var bb := text
	if key != "":
		bb = "[color=#%s][%s][/color]  %s" % [KEY.to_html(false), key, text]
	else:
		bb = text.replace("[E]", "[color=#%s][lb]E[rb][/color]" % KEY.to_html(false)) \
			.replace("[B]", "[color=#%s][lb]B[rb][/color]" % KEY.to_html(false)) \
			.replace("[Q]", "[color=#%s][lb]Q[rb][/color]" % KEY.to_html(false)) \
			.replace("[Space]", "[color=#%s][lb]Space[rb][/color]" % KEY.to_html(false))
	_prompt.text = "[center][color=#%s]%s[/color][/center]" % [PROMPT.to_html(true), bb]


func prompt_rect() -> Rect2:
	return _prompt.get_global_rect()


func set_frost(amount: float) -> void:
	(_frost.material as ShaderMaterial).set_shader_parameter("amount", amount)


func set_debug(text: String) -> void:
	_debug.text = text


func fade_to(alpha: float, seconds: float, color := Color.BLACK) -> Tween:
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	_fade.color = Color(color.r, color.g, color.b, _fade.color.a)
	if seconds <= 0.0:
		_fade.color.a = alpha
		return null
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", alpha, seconds)
	return _fade_tween


func show_title(text: String, below: String, seconds: float) -> void:
	_title.text = text
	_below.text = below
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 1.0, 2.5)
	tw.parallel().tween_property(_below, "modulate:a", 1.0, 3.5)
	tw.tween_interval(maxf(0.0, seconds - 5.5))
	tw.tween_property(_title, "modulate:a", 0.0, 3.0)
	tw.parallel().tween_property(_below, "modulate:a", 0.0, 3.0)


func show_card(text: String, below: String) -> void:
	_title.text = text
	_below.text = below
	_title.add_theme_font_size_override("font_size", 64)
	_title.offset_bottom = -260
	_below.offset_top = 120
	_title.modulate.a = 1.0
	_below.modulate.a = 1.0


# --- Settings ----------------------------------------------------------------------

func _build_menu(font: Font) -> void:
	_menu = PanelContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.025, 0.035, 0.88)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(36)
	_menu.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_menu.add_child(box)
	for id in ["resume", "subtitles", "size", "band", "quality", "quit"]:
		var b := Button.new()
		b.flat = true
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 34)
		b.add_theme_color_override("font_color", Color(0.78, 0.8, 0.83))
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
		b.pressed.connect(_on_menu.bind(id))
		box.add_child(b)
		_menu_buttons[id] = b
	_menu.visible = false
	add_child(_menu)


func _menu_text() -> void:
	_menu_buttons["resume"].text = "Return to the cold"
	_menu_buttons["subtitles"].text = "Subtitles: %s" % ("On" if subtitles.enabled else "Off")
	_menu_buttons["size"].text = "Subtitle size: %s" % SubtitlesScript.SIZE_NAMES[subtitles.size_index]
	_menu_buttons["band"].text = "Subtitle background: %d%%" % int(SubtitlesScript.BANDS[subtitles.band_index] * 100.0)
	_menu_buttons["quality"].text = "Quality: %s" % ["Low", "Medium", "High"][quality]
	_menu_buttons["quit"].text = "Quit"


func menu_open() -> bool:
	return _menu.visible


func open_menu(open: bool) -> void:
	_menu.visible = open
	get_tree().paused = open
	if open:
		_menu_text()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_menu_buttons["resume"].grab_focus()
	elif main.phase != "end" and not OS.has_feature("movie"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and main.phase != "end" and not OS.has_feature("movie"):
		open_menu(not _menu.visible)
		get_viewport().set_input_as_handled()


func _on_menu(id: String) -> void:
	match id:
		"resume":
			open_menu(false)
			return
		"subtitles":
			subtitles.enabled = not subtitles.enabled
		"size":
			subtitles.size_index = (subtitles.size_index + 1) % 3
		"band":
			subtitles.band_index = (subtitles.band_index + 1) % SubtitlesScript.BANDS.size()
		"quality":
			quality = (quality + 1) % 3
			main.look.apply_quality(quality)
		"quit":
			get_tree().quit()
			return
	subtitles.apply_settings()
	_menu_text()
	_save_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		subtitles.enabled = cfg.get_value("subtitles", "on", true)
		subtitles.size_index = cfg.get_value("subtitles", "size", 1)
		subtitles.band_index = cfg.get_value("subtitles", "band", 2)
		quality = cfg.get_value("video", "quality", 1)
	subtitles.apply_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("subtitles", "on", subtitles.enabled)
	cfg.set_value("subtitles", "size", subtitles.size_index)
	cfg.set_value("subtitles", "band", subtitles.band_index)
	cfg.set_value("video", "quality", quality)
	cfg.save(SETTINGS_PATH)
