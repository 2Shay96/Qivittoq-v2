# Qivittoq — Night 1 prototype, version 2

A Danish sailor, alone on the coast of Greenland in the autumn of 1424, keeps a fire alive.
This prototype covers the opening dream, the title, day 1, dusk and night 1.

Version 2 keeps every mechanic of version 1 and changes how it looks, sounds and reads:

- **A realistic look at native resolution.** Forward+ with soft shadows, SSAO and restrained glow.
  The terrain is 1 m fine around the camp, with smooth normals, wind-carved drifts, rock on the
  slopes, a pebble beach and snow banked against the rocks and the windward end of the tent. Dark
  water with a slow swell, slush and pancake ice along the shore. A closed canvas tent big enough
  to sit up in, a fire of crossed logs, butchered walrus with the tusks hacked out, a clinker-built
  færing with oars, fractured rocks. Everything is built in code: no downloaded textures or models.
- **Colder grading.** AgX tonemapping, saturation 0.62, shadows pushed to blue-teal, pale
  highlights, a soft vignette and faint film grain. A color-correction lookup gives the warm hues
  back, so the fire is the only warm color.
- **Two layers of atmosphere.** Near: a blizzard volume that travels with Eske, gusting, with
  three kinds of blowing snow, all driven by one wind value that also sets the wind's loudness.
  Far: exponential haze with a low mist over the water and aerial perspective; the horizon is
  lost. Mountains 2 to 7 km off, 600 to 1,500 m tall, appear only in two deliberate lulls: once on
  day 1, once at dusk.
- **Subtitles.** Native-resolution serif text on a soft band, styled by kind: Eske's speech,
  other voices with a cue, bracketed sound captions that stack above speech, and the carved line
  centered in parchment. Timed to the voice clip, or to reading speed when there is none.
- **Voice-over for Eske**, with placeholder lines made by `tools/make_vo.py` and a script for
  recording real ones in `VO_SCRIPT.md`.

## Running it

You need Godot 4.7 (the standard or the .NET build; there is no C#). Open Godot, choose
**Import**, and pick `project.godot` in this folder. Then press Play (F5). Or, from a terminal,
with `GODOT` set to the path of your Godot executable:

```bash
"$GODOT" --path .
```

The first start imports the sounds, which takes a few seconds.

## Controls

| Key | What it does |
| --- | --- |
| W A S D, mouse | Walk and look |
| E | Pick up, cut blubber, feed the fire, take a burning stick, strike the flint, crawl into the tent, carve the day's line |
| Space | Hold your breath (in the dream) |
| B | Blow out or light the candle (in the tent; blowing it out at night is how you sleep) |
| Q | Crawl out of the tent |
| Esc | Settings: subtitles on or off, three sizes, background strength, quality |
| R | Begin again, on the closing card |

## Settings and performance

Quality is set in the Esc menu (or with `--quality=low|medium|high`) and remembered.

| Quality | 3D resolution | What changes |
| --- | --- | --- |
| Low | 60% with FSR | No SSAO, a smaller blizzard volume, cheaper shadows, fewer snowflakes |
| Medium (default) | 72% with FSR | Half-resolution SSAO, soft shadows (low), all three snow layers |
| High | 100% | Full SSAO, softer shadows, a finer blizzard volume, more snow |

Measured on an Apple M1 MacBook Air (8 GB), in a 1920x1080 window with vsync off:

| Scene | Low | Medium | High |
| --- | --- | --- | --- |
| Day at the camp | 89 fps | 60 fps | 28 fps |
| Night by the fire | | 61 fps | |
| Inside the tent at night | | 56 fps | |

SDFGI is not used: it would not hold the frame rate on this machine.

## Testing shortcuts

| Key | What it does |
| --- | --- |
| F1 | Run the clock 8x, and show the clock, fuel, warmth, wind and frame rate |
| F2 | Skip to the next phase |
| F3 | Put four pieces of driftwood on the woodpile |

Options go after a lone `--`:

```bash
"$GODOT" --path . -- --start=night --look=23,-14
```

| Option | What it does |
| --- | --- |
| `--start=dream\|day\|walk\|dusk\|night\|tent-night` | Where to begin |
| `--at=X,Z` | Start standing at this spot (east is +X, north is -Z) |
| `--look=YAW,PITCH` | The starting view, in degrees |
| `--time=SECONDS` | Jump into the phase (the dream, the day's lull at 100 to 140, dusk's at 5 to 30) |
| `--weather=lull\|gust\|calm\|storm` | Hold the weather |
| `--quality=low\|medium\|high` | Override the saved quality |
| `--fast` | Run the clock 8x |
| `--demo-subs` | Put a spoken line and a sound caption on screen |
| `--bench=SECONDS` | Print the frame rate, then quit |
| `--selftest` | Play through every mechanic and print PASS or FAIL for each |

The self-test checks every mechanic from version 1 and the new systems: every voiced line has a
clip and a colder take, `need_firewood` plays when the fire is low and its subtitle lasts as long
as the clip, the line is cut off or dropped once the fire is fed, story lines interrupt idle ones,
variants rotate, captions stack above speech, long lines break where the sentence breaks, prompts
never overlap subtitles, the wind drives the gusts, the loudness and the snow, a lull reveals the
mountains, and the voice is dry inside the tent and muffled when frozen.

```bash
"$GODOT" --headless --path . -- --start=walk --selftest
```

To record frames for judging the look, Godot's movie writer works (it opens a window for a
moment, and the game leaves the mouse alone while recording):

```bash
"$GODOT" --path . --write-movie frames/f.png --fixed-fps 10 --quit-after 40 -- --start=walk --weather=lull --look=-95,7
```

## How it is built

| File | What it holds |
| --- | --- |
| `scripts/main.gd` | The phases, the clock, the night's events, sleep, freezing, and what sets lines off |
| `scripts/world_builder.gd` | The land out to the horizon, snow banks, collision, the sea, rocks, cairn, færing, mountains, fuel |
| `scripts/meshes.gd` | Procedural meshes: fractured rocks, logs, walrus, the clinker hull, oars, the tent canvas |
| `scripts/materials.gd` | The shared materials |
| `scripts/look.gd` | Sky, light, distance haze and color grade through the day; the quality presets |
| `scripts/weather.gd` | The wind: gusts, lulls, blowing snow, the blizzard volume, the wind's sound, the mountain reveal |
| `scripts/voice.gd` | The line table, triggers, priorities, staleness, cooldowns, the voice bus, the cold |
| `scripts/subtitles.gd` | Subtitle lanes, styles, timing, line breaking |
| `scripts/hud.gd` | Prompts, frost, fades, title cards, the settings menu |
| `scripts/player.gd` | Walking, carrying, the burning stick, the cold, the tent |
| `scripts/fire.gd` | Fuel, light, flames, sparks, smoke, relighting with flint |
| `scripts/tent.gd` | The tent, its inside, the candle, the fire's glow through the canvas |
| `scripts/selftest.gd` | The self-test |
| `data/lines.json` | Every line of text: id, kind, priority, cooldown, trigger, delivery note, variants and files |
| `shaders/` | Terrain, sea, sky, mountains, the blizzard volume, snow, flames, smoke, embers, rock, wood, cloth, skin, vignette and grain, frost |
| `tools/make_vo.py` | Makes every placeholder voice line and writes `VO_SCRIPT.md` |
| `tools/make_sfx.py`, `music/make_song.py` | The sounds and music, unchanged from version 1 |

## Open questions

- **English or Danish.** Eske speaks English, as asked. Whether he should speak Danish with
  English subtitles is still open in the design.
- **The placeholder voice** is a macOS system voice, pitched down and roughened. It is there for
  timing and placement, not performance. See `VO_SCRIPT.md` for recording the real lines.

## Not in yet

The hidden fear value, the creature, nights 2 to 10, the endings, and real voices.

## License

None. All rights are reserved. The placeholder voice clips in `vo/` are made with Apple's macOS
system voices; see `ASSETS.md`.
