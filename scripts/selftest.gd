extends Node
## Plays through every mechanic of Night 1 without a person at the keys, and prints PASS or FAIL
## for each step: the voice-over and subtitles first, then the weather, then v1's mechanics.
## Run it headless:
##   Godot --headless --path . -- --start=walk --selftest

const FuelItem := preload("res://scripts/fuel_item.gd")
const Carcass := preload("res://scripts/carcass.gd")

var main
var _failures := 0


func run() -> void:
	await _wait(0.5)
	var p = main.player
	var fire = main.fire
	var voice = main.voice
	var subs = main.hud.subtitles
	_check(main.phase == "day" and p.mode == "walk", "starts outside in daylight")

	# --- Voice-over -----------------------------------------------------------------------
	voice.language = "da"
	for lang in ["da", "en"]:
		var missing := []
		var missing_cold := []
		var voiced := 0
		for id in voice.lines:
			var line: Dictionary = voice.lines[id]
			if line["kind"] != "speech" and line["kind"] != "voice":
				continue
			for v in line["variants"]:
				voiced += 1
				if voice.clip(v["file"], false, lang) == null:
					missing.append(v["file"])
				if line["kind"] == "speech" and voice.clip(v["file"], true, lang) == null:
					missing_cold.append(v["file"])
		_check(missing.is_empty(), "%s: every voiced line has its clip (%d clips, missing %s)" % [lang, voiced, missing])
		_check(missing_cold.is_empty(), "%s: every line of Eske's has a colder take (missing %s)" % [lang, missing_cold])

	fire.fuel = 30.0
	voice.reset("need_firewood")
	await _wait(1.3)
	_check(voice.current_id() == "need_firewood", "need_firewood plays when the fire is low and his arms are empty")
	var file: String = voice.current["variant"]["file"]
	var clip_len: float = voice.clip(file).get_length()
	var shown: float = subs.lane_duration("speech")
	_check(absf(shown - clip_len) < 0.3 and subs.lane_text("speech") == voice.current["variant"]["text"],
		"its subtitle lasts as long as the clip (clip %.2f s, subtitle %.2f s)" % [clip_len, shown])
	_check(voice._player.stream.resource_path.begins_with("res://vo/da/") and voice._player_cold.stream.resource_path
		.begins_with("res://vo/da/cold/"), "in Danish he speaks the Danish takes, under the English subtitle")
	_check(voice._player.playing and voice._player.bus == "Voice", "Eske speaks on his own bus")
	_check(not voice.say("need_firewood"), "the same line will not come again within its cooldown")
	fire.add_fuel(60.0, "driftwood")
	await _wait(0.3)
	_check(voice.current_id() != "need_firewood" and "need_firewood" in voice.dropped,
		"the line is cut off once the fire is fed")

	voice.clear()
	await _wait(0.3)
	fire.fuel = 30.0
	voice.reset("need_firewood")
	voice.reset("wake_bay")
	voice.say("wake_bay")
	voice.say("need_firewood")
	await _wait(0.1)
	var waiting: bool = voice.is_queued("need_firewood")
	var dropped_before: int = voice.dropped.size()
	fire.fuel = 90.0
	await _wait(0.3)
	_check(waiting and not voice.is_queued("need_firewood") and voice.dropped.size() > dropped_before,
		"a waiting line is dropped once its reason has passed")

	voice.clear()
	await _wait(0.3)
	fire.fuel = 30.0
	voice.reset("need_firewood")
	voice.say("need_firewood")
	await _wait(0.2)
	var idle_first: bool = voice.current_id() == "need_firewood"
	voice.reset("only_ice")
	voice.say("only_ice")
	await _wait(0.5)
	_check(idle_first and voice.current_id() == "only_ice", "a story line interrupts an idle remark")
	voice._last_line.erase("need_firewood")
	var said_before: String = voice.spoken.filter(func(s): return s[0] == "need_firewood").back()[1]
	voice.clear()
	await _wait(0.3)
	voice.say("need_firewood")
	await _wait(0.3)
	var said_now: String = voice.current.get("variant", {}).get("text", "")
	_check(said_now != "" and said_now != said_before, "the next time, other words: \"%s\" then \"%s\"" % [said_before, said_now])

	voice.clear()
	await _wait(0.3)
	voice.language = "en"
	voice.reset("wake_bay")
	voice.say("wake_bay")
	await _wait(0.4)
	var english: String = voice._player.stream.resource_path
	_check(english == "res://vo/wake_bay.wav" and subs.lane_text("speech") == "The bay is empty.",
		"switched to English, he speaks the English take (%s)" % english)
	voice.language = "da"

	# --- Subtitles ---------------------------------------------------------------------------
	voice.caption("cap_ice_cry")
	await _wait(0.3)
	var cap_rect: Rect2 = subs.lane_rect("caption")
	var speech_rect: Rect2 = subs.lane_rect("speech")
	_check(subs.lane_visible("caption") and subs.lane_visible("speech") and cap_rect.end.y <= speech_rect.position.y + 1.0,
		"a sound caption stacks above the speech")
	_check(subs.lane_text("caption").begins_with("[") and absf(subs.lane_duration("caption")
		- (subs.reading_time("The ice cries out, far out on the bay.") + 0.3)) < 0.01,
		"captions are bracketed and timed at reading speed (%.1f s)" % subs.lane_duration("caption"))
	_check(subs.reading_time("Dark.") == 1.5 and subs.reading_time("x".repeat(200)) == 7.0,
		"reading time stays between 1.5 and 7 seconds")
	var broken: PackedStringArray = subs.break_lines("The ice groans, long and low, like something turning over in its sleep.")
	_check(broken.size() == 2 and broken[0].ends_with(",") and broken[0].length() <= 48 and broken[1].length() <= 48,
		"long lines break in two where the sentence breaks: \"%s\" / \"%s\"" % [broken[0], broken[1]])

	subs.size_index = 2
	subs.apply_settings()
	main.hud.set_prompt("Lay the fuel in the cold ashes", "E")
	subs.show_line("He wandered off. The cold took him. Eske!", "A man on the water", 3.0)
	subs.caption("The ice groans, long and low, like something turning over in its sleep.")
	await _wait(0.4)
	var bottom: float = main.hud.prompt_rect().end.y
	var top: float = minf(subs.lane_rect("caption").position.y, subs.lane_rect("speech").position.y)
	if DisplayServer.window_get_size().y == 0:
		# Headless there is no window to lay out in, so measure: the prompt's line at 57% of a
		# 1080-line screen, and the two subtitle bands stacked up from 72 px above the bottom.
		bottom = 1080.0 * 0.57 + (main.hud._prompt.get_theme_font("normal_font") as Font).get_height(27)
		top = 1080.0 - 72.0 - 10.0 - (subs._caption["panel"] as Control).get_combined_minimum_size().y \
			- (subs._speech["panel"] as Control).get_combined_minimum_size().y
	_check(bottom < top, "prompts never overlap the subtitles, even at the largest size (prompt ends %d px, subtitles start %d px)"
		% [bottom, top])
	subs.enabled = false
	subs.apply_settings()
	subs.show_line("Dark already.")
	await _wait(0.2)
	_check(not subs.lane_visible("speech"), "subtitles can be turned off")
	subs.enabled = true
	subs.size_index = 1
	subs.apply_settings()
	voice.clear()

	# --- Weather ------------------------------------------------------------------------------
	var w = main.weather
	w.forced = "gust"
	await _wait(0.3)
	var gust_wind: float = w._wind_audio.volume_db
	var gust_speed: float = (w._streaks.process_material as ParticleProcessMaterial).initial_velocity_max
	w.forced = "calm"
	await _wait(0.3)
	_check(w.gust == 0.0 and w._wind_audio.volume_db < gust_wind - 6.0 and
		(w._streaks.process_material as ParticleProcessMaterial).initial_velocity_max < gust_speed * 0.5,
		"one wind value drives the gusts, the wind's loudness and the snow's speed")
	w.forced = "lull"
	await _wait(0.3)
	_check(w.reveal > 0.9 and main.look.env.fog_density < 0.01, "in a lull the haze thins and the mountains show")
	w.forced = ""
	main.phase_time = 120.0
	_check(w._lull_target() == 1.0, "day 1 has its lull, around two minutes in")
	main.phase_time = 30.0
	await _wait(0.2)

	# --- The mechanics from v1 ---------------------------------------------------------------
	var wood := _find(FuelItem)
	for k in range(4):
		wood[k].interact(p)
	_check(p.carry.size() == 4 and not p.can_carry(), "carries an armful of four")
	wood[4].interact(p)
	_check(p.carry.size() == 4, "cannot carry a fifth")

	main.woodpile.interact(p)
	_check(main.woodpile.count() == 4 and p.carry.is_empty(), "stacks the armful on the woodpile")
	main.woodpile.interact(p)
	var before: float = fire.fuel
	fire.interact(p)
	_check(fire.fuel > before + 100.0 and p.carry.is_empty(), "feeds the fire (%.0f -> %.0f)" % [before, fire.fuel])

	fire.interact(p)
	_check(p.has_torch, "takes a burning stick")

	var carcass = _find(Carcass)[0]
	carcass.interact(p)
	carcass.interact(p)
	carcass.interact(p)
	_check(p.carry.size() == 2 and carcass.blubber == 0, "cuts blubber twice, then nothing is left")
	fire.interact(p)
	_check(fire.smoky > 0.0, "blubber burns smoky")

	main._start_dusk()
	main._start_night()
	p.enter_tent(main.tent)
	_check(p.mode == "tent" and p.candle_lit, "crawls into the tent; the candle is lit at night")
	_check(main.tent.occupied and main.weather._indoors and not main.weather._streaks.emitting, "inside the closed tent no snow blows")
	await _wait(0.6)
	_check(voice._reverb.wet < 0.1, "in the tent his voice is dry and close")
	_check(main.can_carve(), "can carve the day's line")
	main.carve()
	await _wait(2.0)
	_check(main.carved_tonight and not main.can_carve(), "carves once per night")
	_check(subs.lane_text("carved") == "The ship is gone. They left me.", "the carved line is shown, not spoken")

	fire.fuel = 30.0
	p.set_candle(false)
	await _wait(0.1)
	_check(main.sleeping and main.time_scale >= main.SLEEP_SPEED, "blowing out the candle brings sleep")
	await _wait(2.5)
	_check(not main.sleeping, "wakes when the fire burns low (fire %.0f)" % fire.fuel)

	fire.fuel = 0.4
	await _wait(1.0)
	_check(not fire.lit and main.fires_died == 1 and main.closeness == 1, "the fire dies; it comes one step closer")
	await _wait(3.5)
	_check(main._canvas_breath.playing, "something breathes against the canvas")

	p.exit_tent()
	_check(not main.tent.occupied and main.weather._streaks.emitting, "outside again, the snow blows")
	p.carry_item("driftwood", 45.0)
	fire.interact(p)
	_check(not fire.lit and fire.strikes_needed == 3, "fuel in cold ashes needs three strikes")
	for k in range(3):
		fire.interact(p)
	_check(fire.lit, "the flint relights the fire")

	p.place_outside(main.world.ground(-20.0, 40.0) + Vector3(0, 0.2, 0), 0.0)  # far from the fire
	p.warmth = 0.005
	await _wait(1.0)
	_check(p.mode == "frozen" or p.mode == "tent", "freezing takes Eske down")
	_check(voice.cold > 0.95 and voice._lowpass.cutoff_hz < 3000.0, "frozen, his voice is muffled and breathy")
	await _wait(4.5)
	_check(p.mode == "tent" and fire.lit and main.times_frozen == 1, "wakes in the tent; someone built up the fire")

	main.phase_time = main.NIGHT_LENGTH - 0.2
	await _wait(1.0)
	_check(main.phase == "end", "dawn ends the night")
	await _wait(9.5)

	print("SELFTEST %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _find(script: Script) -> Array:
	var found := []
	for n in main.get_children():
		if n.get_script() == script:
			found.append(n)
	return found


func _wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds).timeout


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
