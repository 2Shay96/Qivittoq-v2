extends Control
## Subtitles, drawn at native resolution in a serif on a soft dark band at the bottom of the
## screen. Three lanes, each styled for what it carries:
##   speech   Eske's words in plain white, or another voice with a grey cue: Voices on the water: “Eske!”
##   caption  sounds, in brackets and grey italics, stacking briefly above the speech
##   carved   the line carved into the rune stick: centered, parchment-warm, fading in slowly
## The voice system (scripts/voice.gd) decides what is said and for how long; this only shows it.

const MAX_CHARS := 42
const READ_CPS := 15.0
const MIN_TIME := 1.5
const MAX_TIME := 7.0
const FADE_IN := 0.15
const FADE_OUT := 0.3
const GAP := 0.2
const SIZES := [30, 38, 48]  # small, medium, large, in pixels at 1080p
const SIZE_NAMES := ["Small", "Medium", "Large"]
const BANDS := [0.0, 0.35, 0.6, 0.85]
const SPEECH := Color(0.96, 0.96, 0.94)
const SOUND := Color(0.64, 0.67, 0.71)
const CUE := Color(0.6, 0.63, 0.68)
const CARVED := Color(0.86, 0.76, 0.58)

var enabled := true
var size_index := 1
var band_index := 2

var _speech: Dictionary
var _caption: Dictionary
var _carved: Dictionary
var _captions: Array = []  # waiting captions: [text, duration, direction, queued_at]
var _stack: VBoxContainer
var _font: Font
var _italic: Font
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = serif(false)
	_italic = serif(true)
	_stack = VBoxContainer.new()
	_stack.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_stack.anchor_top = 0.45
	_stack.offset_bottom = -72.0
	_stack.alignment = BoxContainer.ALIGNMENT_END
	_stack.add_theme_constant_override("separation", 10)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)
	_caption = _lane(_stack)
	_speech = _lane(_stack)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.anchor_top = 0.3
	centre.anchor_bottom = 0.62
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_carved = _lane(centre, false)
	apply_settings()


static func serif(italic: bool) -> Font:
	# A bundled font in fonts/ wins; otherwise a humanist serif from the system.
	var bundled := "res://fonts/subtitles%s.ttf" % ("-italic" if italic else "")
	if ResourceLoader.exists(bundled):
		return load(bundled)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Palatino", "Palatino Linotype", "Book Antiqua", "Georgia",
		"Times New Roman", "serif"])
	f.font_italic = italic
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


func _lane(parent: Control, band := true) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	style.shadow_size = 22
	style.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", style)
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("normal_font", _font)
	label.add_theme_font_override("italics_font", _italic)
	label.add_theme_constant_override("line_separation", 2)
	panel.add_child(label)
	parent.add_child(panel)
	panel.visible = false
	panel.modulate.a = 0.0
	return {"panel": panel, "label": label, "style": style, "band": band, "text": "", "plain": "",
		"duration": 0.0, "shown": 0.0, "state": "idle", "handle": 0, "tween": null}


func apply_settings() -> void:
	var px: int = SIZES[size_index]
	for lane in [_speech, _caption]:
		var label: RichTextLabel = lane["label"]
		label.add_theme_font_size_override("normal_font_size", px)
		label.add_theme_font_size_override("italics_font_size", int(px * 0.92))
		var style: StyleBoxFlat = lane["style"]
		var a: float = BANDS[band_index]
		style.bg_color = Color(0.015, 0.02, 0.03, a)
		style.shadow_color = Color(0.015, 0.02, 0.03, a * 0.6)
	var carved_label: RichTextLabel = _carved["label"]
	carved_label.add_theme_font_size_override("normal_font_size", int(px * 1.3))
	var carved_style: StyleBoxFlat = _carved["style"]
	carved_style.bg_color = Color(0, 0, 0, 0)
	carved_style.shadow_color = Color(0.0, 0.0, 0.0, 0.0)
	if not enabled:
		_hide_now(_speech)
		_hide_now(_caption)
		_captions.clear()


# --- Timing and layout ------------------------------------------------------------------

static func reading_time(text: String) -> float:
	return clampf(text.length() / READ_CPS, MIN_TIME, MAX_TIME)


static func break_lines(text: String) -> PackedStringArray:
	# At most two lines of about 42 characters, broken where the sentence breaks naturally.
	if text.length() <= MAX_CHARS:
		return PackedStringArray([text])
	var best := -1
	var best_score := INF
	for i in range(1, text.length() - 1):
		if text[i] != " ":
			continue
		var left := i
		var right := text.length() - i - 1
		if left > MAX_CHARS + 6 or right > MAX_CHARS + 6:
			continue
		var prev := text[i - 1]
		var score := float(absi(left - right))
		if prev in ".!?":
			score -= 30.0
		elif prev in ",;:—":
			score -= 18.0
		if score < best_score:
			best_score = score
			best = i
	if best < 0:
		return PackedStringArray()  # too long for two lines: see pages()
	return PackedStringArray([text.substr(0, best), text.substr(best + 1)])


static func pages(text: String) -> Array:
	# Text too long for two lines, split into pages at sentence ends, each page two lines at most.
	if not break_lines(text).is_empty():
		return [text]
	var out := []
	var current := ""
	for word in text.split(" "):
		var trial := word if current == "" else current + " " + word
		if trial.length() > MAX_CHARS * 2 - 4 and current != "":
			out.append(current)
			current = word
		else:
			current = trial
			if (word.ends_with(".") or word.ends_with("?") or word.ends_with("!")) and current.length() > MAX_CHARS:
				out.append(current)
				current = ""
	if current != "":
		out.append(current)
	return out


# --- Showing lines ----------------------------------------------------------------------

## Show a spoken line for `duration` seconds. Returns a handle for end_line().
func show_line(text: String, speaker := "", duration := -1.0) -> int:
	if duration < 0.0:
		duration = reading_time(text)
	var plain := text if speaker == "" else "%s: “%s”" % [speaker, text]
	var lines := break_lines(plain)
	if lines.is_empty():
		lines = PackedStringArray([plain])
	var bb := _bb_lines(lines, _speech_line.bind(speaker))
	_speech["handle"] = int(_speech["handle"]) + 1
	_show(_speech, bb, plain, duration)
	return _speech["handle"]


func end_line(handle: int, fast := false) -> void:
	if int(_speech["handle"]) == handle and _speech["state"] != "idle":
		_fade_out(_speech, 0.12 if fast else FADE_OUT)


## A sound caption, shown in brackets and grey italics. `direction` is "", "left", "right" or "behind".
func caption(text: String, duration := -1.0, direction := "") -> void:
	if duration < 0.0:
		duration = reading_time(text) + 0.3
	_captions.append([text, duration, direction, _time])


func carved(text: String) -> void:
	# Shown whether subtitles are on or not: it is something he writes, not something heard.
	var bb := "[center][color=#%s]%s[/color][/center]" % [CARVED.to_html(false), text]
	_carved["text"] = bb
	_carved["plain"] = text
	_carved["duration"] = 7.0
	_carved["shown"] = 0.0
	_carved["state"] = "show"
	var label: RichTextLabel = _carved["label"]
	label.text = bb
	var panel: PanelContainer = _carved["panel"]
	panel.visible = true
	_kill(_carved)
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 2.2)
	tw.tween_interval(4.0)
	tw.tween_property(panel, "modulate:a", 0.0, 2.0)
	tw.tween_callback(_set_idle.bind(_carved))
	_carved["tween"] = tw


func clear() -> void:
	_captions.clear()
	for lane in [_speech, _caption, _carved]:
		_hide_now(lane)


func _speech_line(line: String, speaker: String) -> String:
	if speaker != "" and line.begins_with(speaker + ":"):
		return "[i][color=#%s]%s:[/color][/i][color=#%s]%s[/color]" % [CUE.to_html(false), speaker,
			SPEECH.to_html(false), line.substr(speaker.length() + 1)]
	return "[color=#%s]%s[/color]" % [SPEECH.to_html(false), line]


func _caption_line(line: String) -> String:
	return "[i][color=#%s]%s[/color][/i]" % [SOUND.to_html(false), line]


func _set_idle(lane: Dictionary) -> void:
	lane["state"] = "idle"
	(lane["panel"] as PanelContainer).visible = false


func _bb_lines(lines: PackedStringArray, style: Callable) -> String:
	var parts := PackedStringArray()
	for l in lines:
		parts.append(style.call(l))
	return "[center]%s[/center]" % "\n".join(parts)


func _show(lane: Dictionary, bb: String, plain: String, duration: float) -> void:
	lane["text"] = bb
	lane["plain"] = plain
	lane["duration"] = duration
	lane["shown"] = 0.0
	lane["state"] = "show"
	var label: RichTextLabel = lane["label"]
	label.text = bb
	var panel: PanelContainer = lane["panel"]
	panel.visible = enabled
	_kill(lane)
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, FADE_IN)
	lane["tween"] = tw


func _fade_out(lane: Dictionary, seconds: float) -> void:
	lane["state"] = "out"
	var panel: PanelContainer = lane["panel"]
	_kill(lane)
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 0.0, seconds)
	tw.tween_interval(GAP)
	tw.tween_callback(_set_idle.bind(lane))
	lane["tween"] = tw


func _hide_now(lane: Dictionary) -> void:
	_kill(lane)
	lane["state"] = "idle"
	var panel: PanelContainer = lane["panel"]
	panel.modulate.a = 0.0
	panel.visible = false


func _kill(lane: Dictionary) -> void:
	var tw = lane["tween"]
	if tw != null and (tw as Tween).is_valid():
		(tw as Tween).kill()
	lane["tween"] = null


func _process(delta: float) -> void:
	_time += delta
	for lane in [_speech, _caption]:
		if lane["state"] == "show":
			lane["shown"] = float(lane["shown"]) + delta
			if lane["shown"] >= lane["duration"]:
				_fade_out(lane, FADE_OUT)
	# Captions go up one at a time; one that waited too long is no longer news.
	while not _captions.is_empty() and _time - float(_captions[0][3]) > 6.0:
		_captions.pop_front()
	if _caption["state"] == "idle" and not _captions.is_empty():
		var c: Array = _captions.pop_front()
		var text := "[%s]" % c[0]
		var arrow := ""
		match c[2]:
			"left":
				arrow = "‹  "
			"right":
				text += "  ›"
			"behind":
				text += "  behind you"
		var lines := break_lines(text)
		if lines.is_empty():
			lines = PackedStringArray([text])
		if arrow != "":
			lines[0] = arrow + lines[0]
		var bb := _bb_lines(lines, _caption_line)
		_show(_caption, bb, text, c[1])


# --- For the self-test -------------------------------------------------------------

func lane_text(lane_name: String) -> String:
	var lane := _lane_named(lane_name)
	return lane["plain"] if lane["state"] != "idle" else ""


func lane_duration(lane_name: String) -> float:
	return _lane_named(lane_name)["duration"]


func lane_rect(lane_name: String) -> Rect2:
	var panel: PanelContainer = _lane_named(lane_name)["panel"]
	return panel.get_global_rect()


func lane_visible(lane_name: String) -> bool:
	var panel: PanelContainer = _lane_named(lane_name)["panel"]
	return panel.visible and _lane_named(lane_name)["state"] != "idle"


func _lane_named(lane_name: String) -> Dictionary:
	match lane_name:
		"caption":
			return _caption
		"carved":
			return _carved
	return _speech
