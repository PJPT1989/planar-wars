# Planar Wars

A real-time strategy game built in Godot 4.3, in the spirit of *Age of Empires* and *StarCraft*.
Four worlds go to war: Phyrexia, Dominaria, Ravnica and Avishkar. Build a base, gather gold and
aether, raise an army, research upgrades and raze your rivals, alone against the AI or online with
friends, with AI players filling any empty seats.

Fan-made and unofficial. Plane and place names are kept for the setting; all unit names,
characters, models and text are original.

## How to play
- Each player starts with a town hall, five workers and a scout in one corner of the map.
- Workers gather **gold** from veins and **aether** from crystals and carry it to the hall or a
  depot. Houses raise the supply limit (each troop costs supply, at most 120).
- Select workers, press Build and click the ground to place a building. More workers build faster;
  right click a damaged building with workers to repair it.
- Train troops in the barracks, stables, workshop and sanctum. Research upgrades at the forge and
  elsewhere. Advance your town hall to the second and third age to unlock more.
- A player is out when they have no buildings and no workers left. Allies (same team) share the
  win. The last team standing wins.

## Controls
| Input | Action |
| --- | --- |
| Left click / drag | Select one / select everything in the box (Shift adds) |
| Double click | Select every unit of that kind on screen |
| Right click | Move, attack, gather, repair, build, or set a building's rally point |
| Q W E R / A S D F / Z X C V | The command card buttons (Shift + a troop button queues five) |
| A, then click | Attack-move: walk there and fight anything on the way |
| Ctrl + 1-9, 1-9 | Make a group / select it (press twice to jump to it) |
| H | Town hall |
| . (period) or Home | Next idle worker |
| Space | Jump to the last attack |
| Arrows, screen edge, middle drag, wheel | Pan and zoom the camera |
| + / - | Game speed (not online) |
| Esc or F10 | Menu (pauses when not online) |
| L / M | Graphics quality (Low, Medium, High) / sound on or off |

## One template, four races
Every race builds from the same template of troops, buildings and technologies, like the
civilisations in *Age of Empires*, but each has its own names and models, like the races in
*StarCraft*, and each lacks part of the template. The in-game **Codex** shows the whole table.

| Template | Phyrexia | Dominaria | Ravnica | Avishkar |
| --- | --- | --- | --- | --- |
| Worker | Vat Drone | Peasant | Guild Laborer | Servo |
| Infantry | Compleated Legionary | Benalish Footman | Legion Trooper | none |
| Spearman | Impaler Husk | Pikeman | Precinct Halberdier | Brass Lancer |
| Archer | Oil Spitter | Longbowman | Rooftop Crossbowman | Aether Rifleman |
| Cavalry | Ravager Hound | Benalish Knight | none | Aethercycle Rider |
| Siege engine | Gorger Engine | none | Spark Cannon | Aether Cannon |
| Flyer | Porcelain Drake | Pegasus Rider | Skyknight | Thopter |
| Caster (heals) | none | Tolarian Mage | Guild Mage | Inventor |
| Champion | Praetor's Chosen | Angel of the Host | Guardian Golem | Gearsmith Colossus |

| Race | Bonus | Unique technology | Also lacks |
| --- | --- | --- | --- |
| Phyrexia | All troops regenerate | Glistening Oil: melee +2 attack, regeneration x3 | Armour 3, Aether harvest 2, Elite casters |
| Dominaria | Foot troops +15% life, towers +1 range | Thran Masonry: buildings +50% life, towers and keeps +3 attack | Ranged attack 3, Elite siege, Elite flyers |
| Ravnica | Technologies cost 20% less | Guild Accord: every building trains 35% faster | Melee attack 3, Fortified towers, Elite cavalry |
| Avishkar | Workers 40 gold, aether gathered 20% faster | Aether Overdrive: cavalry and flyers +25% speed, +2 attack | Worker armour, Elite infantry, Elite spears |

Counters: infantry beats spearmen, spearmen stop cavalry and champions, archers shoot infantry and
flyers, cavalry runs down archers and siege engines, siege engines raze buildings. Only archers,
flyers, casters and towers can hit flyers.

## Maps
| Map | Plane | Shape |
| --- | --- | --- |
| Benalish Meadows | Dominaria | Open farmland with copses and ponds; many ways in |
| Ravnican Canals | Ravnica | Four districts split by canals; bridges are the only crossings |
| Ghirapur Canyon | Avishkar | Each base on a plateau with two ramps down to the canyon floor |
| Mirrex Expanse | New Phyrexia | Metal thickets wall in every base; a rich centre to fight over |

Each match lays the map out anew from a seed (the template's shape stays), for two to four players.

## Multiplayer
Open **Multiplayer**, type a name and press **Open a room**. Share the room code; friends type it
and press **Join**. The host sets each of the four seats to Open (for a friend), AI Easy, Normal or
Hard, or Closed, picks the map and starts. Everyone picks their own race and team. People and AI
players can be on any team, so you can play together against the AI, against each other, or both.
If someone leaves during a match, an AI takes over their side.

In the browser the players connect peer to peer (WebRTC); on the shop page the browsers find each
other through the shop's Supabase channel. The host's computer runs the match and the AI players.

## Running it
- Godot 4.3: open the folder in the editor and press Play, or `godot --path .`.
- Browser build: `tools/export_web.sh` writes `build/web/` (upload the whole folder; see
  `tools/web/HOW-TO-UPLOAD.txt`). The shop imports it with its `tools/game_import.py`.

## Tests
- `godot --headless --path . -- --simtest` plays an AI-only match on every map and prints the
  winner and each player's numbers (`--map=N --players=N --level=0..2 --minutes=N --seed=N`).
- `tools/smoke_test.sh [dir]` walks the menus, the codex and a match on every map and saves
  screenshots (default `/tmp/pw-shots`).
- `tools/net_test.sh [dir]` runs a host and a guest on this computer in one online match; both
  print the state of the match at the same moment and the lines must match.

## Files
| Path | What |
| --- | --- |
| `scripts/data.gd` | The template (troops, buildings, technologies), the races, maps, costs |
| `scripts/map_data.gd` | Lays out a map from its template and a seed |
| `scripts/sim.gd`, `ent.gd` | The match itself: orders, paths, gathering, building, combat, victory |
| `scripts/ai.gd` | AI players (Easy, Normal, Hard) |
| `scripts/match.gd` | Runs a match: input, selection, commands |
| `scripts/view.gd` | Draws the map and everything on it, fog of war, camera |
| `scripts/hud.gd` | Top bar, minimap, selection panel, command card, menu, results |
| `scripts/main.gd` | Title, skirmish setup, multiplayer rooms, codex, how to play |
| `scripts/net.gd` | Online rooms and snapshots; `tools/web/planar-net.js` is the browser signalling |
| `scripts/models.gd`, `mesh_kit.gd` | Every model, built in code |
| `scripts/portraits.gd` | Renders the portraits for the command card and codex at start-up |
| `scripts/game.gd` | Settings, materials, fonts and the generated sounds |
| `shaders/` | Units (team colour), ground, water, effects |
