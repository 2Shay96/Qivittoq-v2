# Qivittoq: voice-over script, Night 1

Every spoken line in Night 1, in Danish and in English. Eske and the men speak either language,
chosen in the settings (Esc); Danish is the default. The subtitles show the English line in both.

The game plays whatever WAV file sits under the name in the **File** column: in `vo/da/` for
Danish and in `vo/` for English. A real recording replaces a placeholder just by being saved over
it. Subtitles take their timing from the length of each file.

This file is written by `python3 tools/make_vo.py --script` from `data/lines.json`. Change lines
there, not here.

## Recording notes

- **Eske** is a Danish sailor in his thirties: tired, hoarse, cold, with his breath audible. He
  speaks quietly to himself, never to an audience. Never theatrical. Leave a breath before and after
  each line, and trim no closer than about 0.2 s.
- **The Danish lines** are plain modern Danish, translated from the English. Have a native speaker
  check them before recording; an actor may want them older or rougher (it is 1424), as long as
  each line still means what its English subtitle says.
- **Format:** WAV, mono, 44.1 kHz, 16-bit. Record dry and close; the game adds the open-air reverb
  outside and keeps the voice dry in the tent.
- **The cold:** the game muffles Eske as he freezes, and crossfades to a second take in
  `vo/da/cold/` (or `vo/cold/`) with the same file name if there is one. Record that take breathier,
  with teeth close to chattering, or make it from the normal take with
  `python3 tools/make_vo.py --recordings DIR --lang da`.
- **The men in the dream** shout from a boat far out on the water. Record them close and loud;
  `make_vo.py --recordings` pushes them out over the water.
- **Variants:** lines with several takes (need_firewood_1, _2, _3) are chosen in turn so the same
  words never come twice in a row.

## Eske

| Id | File | Danish | English (the subtitle) | When it plays | Delivery |
| --- | --- | --- | --- | --- | --- |
| `wake_bay` | `wake_bay.wav` | “Bugten er tom.” | “The bay is empty.” | Day 1, the first time he crawls out of the tent. | Flat and tired. He looked for the ship anyway. |
| `wake_alone` | `wake_alone.wav` | “Kun båden. Kun mig.” | “Only the boat. Only me.” | Straight after wake_bay. | Barely voiced, to himself. A small pause between the halves. |
| `wake_fire` | `wake_fire.wav` | “Ilden er næsten gået ud.” | “The fire's nearly out.” | After wake_alone. | Practical. The first job of the day. |
| `wake_wood` | `wake_wood.wav` | “Brænde. Jeg må have brænde.” | “Wood. I need wood.” | After wake_fire. | Making himself move. |
| `need_firewood` | `need_firewood_1.wav` | “Jeg mangler brænde.” | “I need firewood.” | The fire is low (under 40 s of fuel) and he is carrying nothing. At most once a minute. Dropped if the fire is fed first. | Low and matter-of-fact, afraid underneath. Not a complaint. |
| `need_firewood` | `need_firewood_2.wav` | “Brænde. Jeg må have mere brænde.” | “Wood. I need more wood.” | The fire is low (under 40 s of fuel) and he is carrying nothing. At most once a minute. Dropped if the fire is fed first. | Low and matter-of-fact, afraid underneath. Not a complaint. |
| `need_firewood` | `need_firewood_3.wav` | “Det holder ikke natten ud.” | “It won't last the night.” | The fire is low (under 40 s of fuel) and he is carrying nothing. At most once a minute. Dropped if the fire is fed first. | Low and matter-of-fact, afraid underneath. Not a complaint. |
| `first_wood` | `first_wood.wav` | “Bleget som en knogle. Det vil brænde.” | “Bleached like bone. It will burn.” | The first time he picks up driftwood. | Turning the wood over in his hands. Quiet. |
| `arms_full` | `arms_full_1.wav` | “Jeg har favnen fuld.” | “My arms are full.” | He has an armful of four and reaches for more. | Short of breath from the weight. |
| `arms_full` | `arms_full_2.wav` | “Ikke mere. Armene kan ikke mere.” | “No more. Not in these arms.” | He has an armful of four and reaches for more. | Short of breath from the weight. |
| `first_feed` | `first_feed.wav` | “Sådan. Bliv ved med at brænde.” | “There. Stay alight.” | The first time he feeds the fire. | Coaxing it, almost tender. |
| `fire_dying` | `fire_dying_1.wav` | “Ilden er ved at gå ud.” | “The fire's dying.” | Out walking while the fire is down to its last 20 seconds of fuel. | A spike of alarm, held down. |
| `fire_dying` | `fire_dying_2.wav` | “Den brænder ned. Gå tilbage.” | “It's burning down. Go back.” | Out walking while the fire is down to its last 20 seconds of fuel. | A spike of alarm, held down. |
| `see_faering` | `see_faering.wav` | “For lille til at følge efter dem.” | “Too small to follow them.” | The first time he looks at the færing from close by. | Not self-pity. A fact he has been avoiding. |
| `see_carcass` | `see_carcass.wav` | “De tog stødtænderne og lod resten ligge.” | “They took the tusks and left the rest.” | The first time he looks at a walrus carcass from close by. | Bitter and quiet. He knows the feeling. |
| `cut_blubber` | `cut_blubber.wav` | “Tilgiv mig.” | “Forgive me.” | The first time he cuts blubber from a carcass. | Whispered to the dead animal as the knife goes in. |
| `water` | `water.wav` | “Ikke vandet. Ikke den kulde.” | “Not the water. Not that cold.” | He tries to walk into the sea. | A step back from the edge. Fear in the breath. |
| `torch_take` | `torch_take.wav` | “En brændende pind. Den holder ikke længe.” | “A burning stick. It won't last long.” | He takes a burning stick from the fire. | Wary. He knows it is borrowed light. |
| `torch_out` | `torch_out.wav` | “Brændt helt ned til fingrene.” | “Burnt down to my fingers.” | The burning stick goes out in his hand. | A hiss of pain, then flat. |
| `first_whiteout` | `first_whiteout.wav` | “Stå stille. Det går over.” | “Stand still. It passes.” | The first gust that whites everything out while he is outside. | Eyes shut against the snow. A sailor riding out a squall, calm by force of will. |
| `mountains` | `mountains.wav` | “De har været der hele tiden.” | “They were there all along.” | The mountain reveal at dusk, if he is outside. The reveal on day 1 is left silent. | Almost a whisper. Awe and dread. |
| `cold_rising` | `cold_rising_1.wav` | “Mine hænder...” | “My hands...” | Away from the fire and getting cold (warmth under 40%). | Teeth close to chattering. Short breaths between the words. |
| `cold_rising` | `cold_rising_2.wav` | “Tilbage til ilden. Nu.” | “Back to the fire. Now.” | Away from the fire and getting cold (warmth under 40%). | Teeth close to chattering. Short breaths between the words. |
| `cold_rising` | `cold_rising_3.wav` | “Kan ikke mærke fingrene.” | “Can't feel my fingers.” | Away from the fire and getting cold (warmth under 40%). | Teeth close to chattering. Short breaths between the words. |
| `freeze` | `freeze.wav` | “Jeg kan ikke... mærke mine hænder.” | “I can't... feel my hands.” | He freezes and goes down in the snow. | Fading. The last words before he falls. |
| `woke_where` | `woke_where.wav` | “Hvordan kom jeg tilbage hertil?” | “How did I get back here?” | He wakes in the tent after freezing. | Confused and frightened, just woken. |
| `woke_fire` | `woke_fire.wav` | “Hvem har lagt på ilden?” | “Who built up the fire?” | Straight after woke_where. | Slower. The fear arriving. |
| `wake_cold` | `wake_cold.wav` | “Koldt. Ilden er ved at brænde ud.” | “Cold. The fire's burning low.” | Sleep ends because the fire is burning low. | Groggy, then alarmed. |
| `dusk_light` | `dusk_light.wav` | “Lyset forsvinder så hurtigt her.” | “The light goes so quickly here.” | Dusk begins. | Looking west. Resigned. |
| `dusk_short` | `dusk_short.wav` | “Ikke brænde nok. Ikke til hele natten.” | “Not enough wood. Not for the whole night.” | Dusk begins with fewer than five pieces on the woodpile. | Counting, and knowing. |
| `night_dark` | `night_dark.wav` | “Allerede mørkt.” | “Dark already.” | Night falls. | Almost nothing. A breath with words in it. |
| `mark_day` | `mark_day.wav` | “Mærk dagen, så jeg ikke mister tællingen.” | “Mark the day, so I don't lose count.” | The first time he crawls into the tent at dusk or night. | A habit to hold on to. |
| `sleep_hint` | `sleep_hint.wav` | “Pust så lyset ud, og sov.” | “Now blow out the light, and sleep.” | After he carves the day's line. | Telling himself, gently, as you would a child. |
| `only_ice` | `only_ice.wav` | “Det er bare isen. Bare isen.” | “Only the ice. Only the ice.” | Night 1 at 100 s, after the ice cries out. | Repeating it to make it true. |
| `dont_look` | `dont_look.wav` | “Kig ikke. Kig ikke.” | “Don't look. Don't look.” | Something breathes against the canvas after the fire dies. | A whisper through clenched teeth, eyes shut. Nothing outside must hear it. |
| `fire_died` | `fire_died.wav` | “Nej. Nej, nej. Ilden.” | “No. No, no. The fire.” | The fire goes out while he is outside. | Rising panic, quickly swallowed. |
| `relit` | `relit.wav` | “Brænd. Kom nu, brænd.” | “Burn. Please burn.” | The flint catches and the fire lives again. | Close to a prayer. |

## The men in the dream

| Id | File | Danish | English (the subtitle) | When it plays | Delivery |
| --- | --- | --- | --- | --- | --- |
| `dream_call_1` | `dream_call_1.wav` | “Eske!” | “Eske!” (Voices on the water) | The dream, 5 s. A crewman in the searching boat, far off. | Shouted across black water. Searching, not yet worried. |
| `dream_call_2` | `dream_call_2.wav` | “Eske! Hvor er du?” | “Eske! Where are you?” (A man on the water) | The dream, 9 s. | Louder, impatient. |
| `dream_call_3` | `dream_call_3.wav` | “Eske!” | “Eske!” (Voices on the water) | The dream, 13 s. A different man. | Higher, younger, scared of the dark. |
| `dream_call_4` | `dream_call_4.wav` | “ESKE!” | “ESKE!” (A man on the water) | The dream, 20 s. The lantern is close; this is the moment to hold your breath. | Very close now. A full-throated shout straight at the rocks where he hides. |
| `dream_call_5` | `dream_call_5.wav` | “Han er faret vild. Kulden har taget ham. Eske!” | “He wandered off. The cold took him. Eske!” (A man on the water) | The dream, 24 s. | To the others in the boat, giving up. Then one last shout. |
| `dream_call_6` | `dream_call_6.wav` | “Vi kan ikke vente på isen.” | “We can't wait for the ice.” (The skipper) | The dream, 28.5 s. The skipper decides. | Older, hard, final. Not cruel. |
| `dream_call_7` | `dream_call_7.wav` | “...Eske.” | “...Eske.” (Voices on the water) | The dream, 38 s. The boat is leaving. | Far off and quiet. Almost an apology. |

## Not spoken

- `carved_night_1`: “The ship is gone. They left me.” (“Skibet er borte. De efterlod mig.”) Carved into the rune stick on night 1. Shown, never spoken.

