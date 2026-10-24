# History

## Round 1: the first version
**Request (Petr):** "I want to create now game into my game part of eshop. It will be RTS,
inspired by "age of empires" and "Starcraft". The idea is that there will be like 4 races.
Phyrexians, Dominaria, Ravnica, Avishkar. Couple of basic map templates will be enough (4). Each
race will have its own units and technologies in terms of name and look (like Starcraft) but those
units/tech will be coming from shared template (like AoE). Out of shared template each race will
have only certain unit and technology upgrades available (Much like in AoE). This game will have
multiplier to allow play against either AI or human, or both"

**Decided (defaults, offered to Petr):** the name Planar Wars; a new repository like the other
games; host-run online rooms like Aether Drift, with up to four seats that can each be a person or
an AI player.

**Built:**
- One shared template: 9 troop roles (worker, infantry, spearman, archer, cavalry, siege engine,
  flyer, caster, champion), 9 buildings and 27 technologies (three ages, economy, attack and armour
  levels, elite upgrades, towers, one unique technology per race).
- Four races on that template, each with its own names, models, colours, a bonus, a unique
  technology and a few roles and upgrades it lacks (Phyrexia: no caster; Dominaria: no siege;
  Ravnica: no cavalry; Avishkar: no infantry; plus missing upgrades each).
- Four map templates laid out from a seed: Benalish Meadows (open), Ravnican Canals (river and
  bridges), Ghirapur Canyon (plateaus and ramps), Mirrex Expanse (walled bases, rich centre).
- Gold and aether economy, supply, construction and repair, training queues, rally points,
  research, armour types and counters, splash, healing, towers, fog of war, victory by teams.
- AI players at three levels that build, expand, research and attack in waves.
- Controls in the classic RTS style: box select, groups, command card hotkeys, attack-move,
  minimap, idle worker and alert keys, game speed.
- Title screen with a live AI battle, skirmish setup (map, seats, races, teams), multiplayer rooms
  (WebRTC in the browser), a Codex showing the template table and how to play.
- Tests: an AI-only sim test, a visual smoke test, a two-player online test (desktop and two
  browser tabs). All art and sound are generated in code.

## Round 2: more detailed models and animation
**Request (Petr):** "I would like to improve the visuals/graphics. What are my options?" Offered:
detailed models, animation, terrain, effects, lighting, UI art. Petr: "lets do 1+2" (detailed
models and animation).

**Built:**
- Troops rebuilt with more shape: lofted torsos, knees and elbows, boots, faces, helmets with
  brims and nose guards, tabards that follow the body, belts with buckles and pouches, capes with
  folds; swords with guards and pommels, leaf-bladed spears with pennants, kite shields with a
  cross, curved bows with a nocked arrow, crossbows, rifles; lofted horses with a neck, head, mane,
  tail and barding; spoked wheels; layered feathered wings.
- Animation without skeletons: each model's parts are tagged (legs, weapon arm, shield arm, spear
  arm, aiming arms, casting arm, wings, four-legged gait, wheels, barrels, head, tail) and a vertex
  shader moves them. Troops walk in step with the ground they cover, swing, thrust, shoot with a
  kick, cast with a raised staff, gallop in diagonal pairs, beat their wings, roll their wheels;
  workers dig. The fallen topple (beasts and engines roll over, flyers drop), lie still and sink;
  razed buildings crumble down.
- Buildings: every one stands on paving of its race (cobbles, dark flagstones, cream and teal
  tiles, a riveted plate), walls have plinths, cornices and corner posts, roofs have tile courses,
  ridges and eaves, doors and windows have frames, sills and bars, half-timbering on Dominarian
  houses; banners flutter, Avishkar gears turn, orbit rings spin.
- A model check (`--lineup`) that renders every troop in four poses and every building.

## Round 3: music
**Request (Petr):** "can there be added music?"

**Built:**
- Five original tracks, synthesised by `tools/gen_music.py` (numpy instruments: strings, choir,
  horn, flute, plucked lute and harp, harpsichord, sitar, santoor, tanpura drone, bells, machine
  clangs, taiko, frame drum, snare, tabla; a convolution reverb) and saved as Ogg Vorbis in
  `music/` (about 5.6 MB). Each loops seamlessly.
- Title theme on the menus; in a match your race's theme, then the other races' and the title
  theme in turn, with a cross-fade between tracks.
- Music on/off: a button on the title screen and in the menu, N in a match, saved with the
  other settings. M still mutes everything.

## Round 4: more music and unit voices
**Request (Petr):** "i cannot hear any music in the test" (fixed: the browser's Web Audio sample
playback ignored the code-made music bus and the volume fade), then "extend the track list to
have 3 times the amount of music tracks. Also, have each unit to have "voice" so that they react
to commands".

**Built:**
- Ten more tracks (15 in all, about 23 minutes): three menu themes and three per race, each in
  its race's style. Encoded at a lower bitrate, so all fifteen take 7.9 MB.
- Voices: every troop answers when selected, ordered to move, ordered to attack and when trained,
  with three original lines per order (320 clips, 3.2 MB). Speech is made offline with Piper
  (LibriTTS-R voice, CC BY 4.0); each unit has its own speaker, picked by pitch and by how well a
  speech recogniser understood its lines after the race's treatment (Phyrexian doubled metallic
  rasp, the Angel's echo, deep slow golem, robotic colossus). Beasts and machines growl, shriek,
  grind, beep or whirr instead.
- Voices on/off button on the title screen and in the menu, saved with the settings.

