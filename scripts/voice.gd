extends Node
## Every line of text in the game, from one table (data/lines.json): Eske's voice, the men in
## the dream, sound captions and carved lines. It decides what is said and when:
##   - story lines interrupt event lines and idle remarks; event lines interrupt idle remarks
##   - a line whose reason has passed is dropped ("I need firewood" once the fire is fed)
##   - each line has a cooldown, and the same words never come again within a few minutes
## Eske speaks on his own bus: a little open-air reverb outside, dry and close in the tent, and
## more muffled and breathy the colder he gets. He and the men speak Danish (vo/da/) or English
## (vo/), as set in the settings; the subtitles show the English line either way.

signal line_started(id: String)

const PRIORITY := {"idle": 0, "event": 1, "story": 2}
const REPEAT_WINDOW := 180.0  # seconds before the same words may come again
const POLL := 0.5
const QUIET_AFTER_STORY := 12.0
const GAP := 0.25  # silence between one line and the next
const STALE_AGE := {0: 6.0, 1: 12.0}  # how long idle and event lines may wait their turn

var main
var subtitles
var lines := {}
var spoken: Array = []   # [id, text, time] for everything said
var dropped: Array = []  # ids dropped because their reason passed
var current := {}
var cold := 0.0
var indoors := false
var language := "da"  # "da" or "en"

var _queue: Array = []
var _auto: Array = []
var _last_line := {}
var _last_text := {}
var _next_variant := {}
var _streams := {}
var _player: AudioStreamPlayer
var _player_cold: AudioStreamPlayer
var _lowpass: AudioEffectLowPassFilter
var _reverb: AudioEffectReverb
var _bus := 0
var _time := 0.0
var _poll_t := 0.0
var _gap := 0.0
var _end_at := 0.0
var _quiet_until := 0.0


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/lines.json"))
	for line in data["lines"]:
		lines[line["id"]] = line
		var trigger: String = line.get("trigger", "event")
		if trigger != "event":
			_auto.append(line["id"])
	_bus = AudioServer.bus_count
	AudioServer.add_bus(_bus)
	AudioServer.set_bus_name(_bus, "Voice")
	AudioServer.set_bus_send(_bus, "Master")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 12000.0
	AudioServer.add_bus_effect(_bus, _lowpass)
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.75
	_reverb.damping = 0.65
	_reverb.spread = 0.8
	_reverb.hipass = 0.2
	_reverb.predelay_msec = 40.0
	_reverb.dry = 1.0
	_reverb.wet = 0.14
	AudioServer.add_bus_effect(_bus, _reverb)
	_player = AudioStreamPlayer.new()
	_player.bus = "Voice"
	add_child(_player)
	_player_cold = AudioStreamPlayer.new()
	_player_cold.bus = "Voice"
	add_child(_player_cold)


func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


## The recording of a line in `lang` (the chosen language if empty), or its colder take.
func clip(file: String, cold_take := false, lang := "") -> AudioStream:
	var dir := "res://vo/" if (lang if lang != "" else language) == "en" else "res://vo/da/"
	return _stream(dir + ("cold/" if cold_take else "") + file)


# --- Asking for lines ------------------------------------------------------------------

## Ask for a line by id. Returns false if it is cooling down, already waiting, or used up.
## opts: "player" plays it through that AudioStreamPlayer3D instead (voices in the world).
func say(id: String, opts := {}) -> bool:
	if not lines.has(id):
		push_warning("No line called %s" % id)
		return false
	var line: Dictionary = lines[id]
	if line["kind"] == "caption":
		caption(id)
		return true
	if line["kind"] == "carved":
		carved(id)
		return true
	if not _allowed(line):
		return false
	var variant := _pick_variant(line)
	if variant.is_empty():
		return false
	var req := {"id": id, "line": line, "variant": variant, "priority": PRIORITY[line["priority"]],
		"queued_at": _time, "opts": opts}
	if not current.is_empty() and req["priority"] > current["priority"] and current["priority"] < PRIORITY["story"]:
		_interrupt()
	var at := _queue.size()
	for k in range(_queue.size()):
		if _queue[k]["priority"] < req["priority"]:
			at = k
			break
	_queue.insert(at, req)
	return true


func caption(id: String, source = null) -> void:
	var line: Dictionary = lines[id]
	var text: String = line["variants"][0]["text"]
	spoken.append([id, text, _time])
	subtitles.caption(text, -1.0, _direction(source))


func carved(id: String) -> void:
	var text: String = lines[id]["variants"][0]["text"]
	spoken.append([id, text, _time])
	subtitles.carved(text)


func clear() -> void:
	_queue.clear()
	if not current.is_empty():
		_interrupt()
	subtitles.clear()


func _allowed(line: Dictionary) -> bool:
	var id: String = line["id"]
	if current.get("id", "") == id:
		return false
	for r in _queue:
		if r["id"] == id:
			return false
	var cooldown: float = line.get("cooldown", 0.0)
	if _last_line.has(id):
		if cooldown < 0.0:
			return false
		if _time - float(_last_line[id]) < cooldown:
			return false
	return true


func _pick_variant(line: Dictionary) -> Dictionary:
	var variants: Array = line["variants"]
	var start: int = _next_variant.get(line["id"], 0)
	for k in range(variants.size()):
		var v: Dictionary = variants[(start + k) % variants.size()]
		var fresh: bool = not _last_text.has(v["text"]) or _time - float(_last_text[v["text"]]) > REPEAT_WINDOW
		if fresh or line["kind"] == "voice":
			_next_variant[line["id"]] = (start + k + 1) % variants.size()
			return v
	return {}


func _valid(req: Dictionary) -> bool:
	var cond: String = req["line"].get("valid_while", "")
	if cond != "" and not main.condition(cond):
		return false
	var max_age: float = STALE_AGE.get(req["priority"], INF)
	return current == req or _time - float(req["queued_at"]) <= max_age


# --- Speaking ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	for r in _queue.duplicate():
		if not _valid(r):
			_queue.erase(r)
			dropped.append(r["id"])
	if not current.is_empty():
		if current["priority"] == 0 and not _valid(current):
			dropped.append(current["id"])
			_interrupt()
		elif _time >= _end_at:
			if current["priority"] == PRIORITY["story"]:
				_quiet_until = _time + QUIET_AFTER_STORY
			current = {}
			_gap = GAP
	if current.is_empty():
		_gap -= delta
		if _gap <= 0.0 and not _queue.is_empty():
			_start(_queue.pop_front())
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL
		_poll_triggers()
	_update_sound()


func _poll_triggers() -> void:
	if main.sleeping or not main.clock_running() or _time < _quiet_until:
		return
	if not current.is_empty() or not _queue.is_empty():
		return
	for id in _auto:
		var line: Dictionary = lines[id]
		if main.condition(line["trigger"]) and _allowed(line):
			if say(id):
				return


func _start(req: Dictionary) -> void:
	current = req
	var line: Dictionary = req["line"]
	var v: Dictionary = req["variant"]
	var text: String = v["text"]
	var stream := clip(v.get("file", ""))
	var duration: float = subtitles.reading_time(text)
	var custom = req["opts"].get("player")
	if stream != null:
		duration = stream.get_length()
		if custom != null:
			custom.stream = stream
			custom.play()
		else:
			_player.stream = stream
			_player.volume_db = 0.0
			_player.play()
			var cold_stream := clip(v["file"], true)
			if cold_stream != null:
				_player_cold.stream = cold_stream
				_player_cold.play()
			else:
				_player_cold.stop()
	_end_at = _time + duration + 0.15
	current["duration"] = duration
	current["started"] = _time
	_last_line[line["id"]] = _time
	_last_text[text] = _time
	spoken.append([line["id"], text, _time])
	var speaker: String = line.get("speaker", "")
	current["handle"] = subtitles.show_line(text, speaker, duration + 0.15)
	line_started.emit(line["id"])


func _interrupt() -> void:
	if current.is_empty():
		return
	for p in [_player, _player_cold]:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -40.0, 0.12)
			tw.tween_callback(p.stop)
	subtitles.end_line(current.get("handle", -1), true)
	current = {}
	_gap = 0.2


func _update_sound() -> void:
	# Colder: more of the breathy take, and more muffled. In the tent: dry and close.
	var c := smoothstep(0.3, 0.95, cold)
	if _player.playing and _player_cold.playing:
		_player.volume_db = linear_to_db(maxf(1.0 - c, 0.001))
		_player_cold.volume_db = linear_to_db(maxf(c, 0.001)) + 1.0
	_lowpass.cutoff_hz = lerpf(12000.0, 2200.0, c)
	_reverb.wet = move_toward(_reverb.wet, 0.0 if indoors else 0.14, get_process_delta_time() * 0.5)


func _direction(source) -> String:
	if source == null or main.player == null:
		return ""
	var cam: Camera3D = main.player.camera
	var to: Vector3 = (source as Vector3) - cam.global_position
	to.y = 0.0
	if to.length() < 0.5:
		return ""
	to = to.normalized()
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := cam.global_basis.x
	var ahead := fwd.dot(to)
	if ahead < -0.4:
		return "behind"
	if ahead < 0.6:
		return "right" if right.dot(to) > 0.0 else "left"
	return ""


# --- For the self-test ---------------------------------------------------------------

func current_id() -> String:
	return current.get("id", "")


func is_queued(id: String) -> bool:
	for r in _queue:
		if r["id"] == id:
			return true
	return false


func reset(id: String) -> void:
	_last_line.erase(id)
	for v in lines[id]["variants"]:
		_last_text.erase(v["text"])
	_quiet_until = 0.0
