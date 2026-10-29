# Qivittoq assets (v2)

Everything the Night 1 prototype uses. There are no downloaded textures, models, fonts or addons:
the world is built in code and shaded procedurally, and the sounds and music are synthesized.

## The world (code and shaders)

| What | Where |
| --- | --- |
| Terrain to the horizon, snow banks, the beach, collision | `scripts/world_builder.gd`, `shaders/terrain.gdshader` |
| The sea, slush and pancake ice | `scripts/world_builder.gd`, `shaders/sea.gdshader` |
| Mountains and the ice cap's edge | `scripts/world_builder.gd`, `shaders/mountain.gdshader` |
| Rocks, logs, driftwood, walrus, færing, oars, tent canvas | `scripts/meshes.gd`; `shaders/rock`, `wood`, `skin`, `cloth` |
| Sky, haze, color grade | `scripts/look.gd`, `shaders/sky.gdshader` |
| Blowing snow and the blizzard volume | `scripts/weather.gd`, `shaders/snow.gdshader`, `shaders/blizzard.gdshader` |
| Flames, sparks, smoke, embers | `scripts/fire.gd`, `shaders/flame`, `smoke`, `embers` |
| Vignette and grain, frost | `shaders/post.gdshader`, `shaders/frost.gdshader` |

## Text

The subtitles and title use the system's Palatino (falling back to Georgia, Times or any serif);
no font file is bundled. To bundle an open-licensed font instead, save it as
`fonts/subtitles.ttf` (and `fonts/subtitles-italic.ttf`) and the game uses it.

Every line of text is in `data/lines.json`.

## Voice (`vo/` and `vo/da/`)

Placeholder clips in two languages, chosen in the settings: Danish in `vo/da/` (44 clips, 151
seconds) and English in `vo/` (44 clips, 152 seconds). Each has 37 of Eske's lines and variants,
each with a colder take in `cold/`, and 7 calls from the men in the dream. 16-bit mono 44.1 kHz WAV.

- **Eske in Danish:** macOS voice "Sara", a woman's voice, set down to a man's pitch (about
  110 Hz) with `say`'s `[[pbas 38]]` command and slowed 8%. If the Danish man's voice "Magnus" is
  installed, `make_vo.py` uses him instead.
- **Eske in English:** macOS voice "Daniel (English (UK))" at 135 words a minute, slowed and
  lowered about two semitones.
- **Both:** hoarse breath mixed under the words, an audible breath before and after, EQ, and a
  little grit. The cold take is breathier, muffled and shivers.
- **The men in the dream:** in Danish, Sara at five different pitches; in English, macOS voices
  Reed, Rocko, Ralph and Grandpa. Thinned, pushed far out over the water with echoes off the shore
  and a long tail. They replace v1's synthesized `audio/call_eske_*.wav`, which are still in
  `audio/` but no longer used.
- **The Danish words** are plain modern Danish translated from the English lines, not yet checked
  by a native speaker.
- **Regenerate:** `python3 tools/make_vo.py` for both languages, or `--lang da` for one (macOS
  only; it needs `say` and `afconvert`).
- **Replace:** see `VO_SCRIPT.md`. A real recording saved over a file in `vo/da/` or `vo/` is used
  as it is.
- **License caution:** these clips are made with Apple's system voices. Apple's macOS license
  limits what the voices may be used for, and may not allow sharing their recordings publicly or
  commercially. Treat them as stand-ins for this machine, and replace them with recorded or
  properly licensed voices before anything is released.

## Music (`music/`)

| File | Length | What it is |
| --- | --- | --- |
| `dromte_mig_en_drom.mid` | 4 bars | Eske's song, "Drømte mig en drøm i nat" (Codex Runicus, about 1300; public domain). D minor, 6/4, harp, the Danish words stored as lyrics. Transcription from Danish Wikipedia. |
| `the_dead_refrain.mid` | 4 bars | The dead's refrain: an original, wordless answer to Eske's song in the same scale and rhythm. Choir. |
| `night01_preview.wav` | 35.0 s | Night 1 version: Eske's song on a plucked lyre, clean and gentle, over a low drone and wind. |
| `night07_preview.wav` | 90.7 s | Night 7 version: Eske's song slows, drifts flat and breaks, unfinished. The dead hum the refrain far off in the fog, heard only between gusts, and finish it for him. Approved by the creator. |
| `dead_refrain_preview.wav` | 59.6 s | The refrain alone, near and clear, for judging the melody. |
| `make_song.py` | | Renders the MIDI files and each night's version. `python3 music/make_song.py night07` |

## Sounds (`audio/`)

| File | Length | Loops | What it is | Used for |
| --- | --- | --- | --- | --- |
| `title_theme.wav` | 35.0 s | no | Copy of `music/night01_preview.wav` | Title card |
| `wind_loop.wav` | 20.0 s | yes | Wind with slow gusts and a low howl | Always, plus a second copy pitched down to 0.6 |
| `fire_loop.wav` | 8.0 s | yes | Fire: low rumble, crackles, pops | The fire, louder with more fuel |
| `breath_loop.wav` | 3.5 s | yes | Inhale, exhale, pause | Eske's breathing (louder and faster with cold); pitched down to 0.72 as the thing breathing against the canvas |
| `step_snow_1.wav` to `_4` | 0.32 s | no | Footsteps crunching in snow | Walking |
| `ice_crack.wav` | 7.5 s | no | Sea ice snapping, the ringing "pew" of ice, a boom, a groan | Night 1 event, "the ice cries out" |
| `ice_groan.wav` | 8.0 s | no | Long low groan of shifting ice | Day and night ambience |
| `oars_loop.wav` | 6.0 s | yes | Oars dipping and an oarlock creaking, one stroke every 3 s | The dream: the crew's boat searching the shore |
| `call_eske_1.wav` to `_3` | 3.65 s | no | A man shouting "Eske!" far over water, at three pitches | v1's dream; replaced in v2 by `vo/dream_call_*.wav` |
| `candle_blow.wav` | 0.55 s | no | Blowing out a candle | The tent |
| `carve.wav` | 1.5 s | no | Knife scraping wood in short strokes | Carving the rune line; cutting blubber |
| `strike.wav` | 0.3 s | no | Flint on steel, with sparks | Relighting the fire |
| `wood_drop.wav` | 0.35 s | no | Wood thumping down | Picking up, stacking and feeding fuel |

The loops are made seamless by crossfading their tail into their head. In Godot, set
`loop_mode = AudioStreamWAV.LOOP_FORWARD` and `loop_end = int(get_length() * mix_rate)` when loading.


In v2 the wind plays three copies of `wind_loop.wav` (normal, pitched down to 0.6, and pitched up
to 1.45 for gusts) on its own bus, which is muffled inside the tent.

## Regenerating

- Voice: `python3 tools/make_vo.py` (writes `vo/da/`, `vo/`, their `cold/` folders and `VO_SCRIPT.md`)
- Sounds: `python3 tools/make_sfx.py` (writes into `audio/`; seeded, so the result is the same each time)
- Music: `python3 music/make_song.py` (writes next to itself)

All three need only Python 3 and its standard library; the voice also needs macOS.
